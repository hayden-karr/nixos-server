{ config, pkgs, ... }:

let
  inherit (config.serverConfig.network) localhost;
in
{
  # HashiCorp Vault - Enterprise-grade secret management
  # Production-ready configuration without manual bootstrap
  #
  # SECURITY ARCHITECTURE:
  # - Manual unseal using SOPS-stored recovery keys
  # - UID-based policies for container isolation
  # - AppRole authentication per container
  # - Audit logging enabled
  # - No secrets on disk (tmpfs for runtime data)
  #
  # RECOVERY:
  # - Recovery keys stored in SOPS (secrets.yaml)
  # - Root token backed up in SOPS
  # - Can regenerate root token with recovery keys
  # - Automated backups every 6 hours

  # SOPS secrets for Vault
  sops.secrets.vault-root-token = {
    owner = "root";
    mode = "0400";
  };

  sops.secrets.vault-recovery-keys = {
    owner = "root";
    mode = "0400";
  };

  # Vault container - rootful with unique UID namespace
  virtualisation.oci-containers.containers.vault = {
    image = "hashicorp/vault:latest";
    autoStart = true;
    cmd = [ "server" ]; # Explicitly run in server mode, not dev mode

    ports = [
      "8200:8200" # API/UI
      "8201:8201" # Cluster port (for HA in future)
    ];

    volumes = [
      "/mnt/ssd/vault/data:/vault/data"
      "/mnt/ssd/vault/audit:/vault/audit"
      "/etc/vault/vault.hcl:/vault/config/vault.hcl:ro"
      "/mnt/ssd/vault/logs:/vault/logs"
      "/etc/localtime:/etc/localtime:ro"
    ];

    environment = {
      VAULT_ADDR = "http://${localhost.ip}:8200";
      VAULT_API_ADDR = "http://${localhost.ip}:8200";
      VAULT_CLUSTER_ADDR = "http://${localhost.ip}:8201";
      VAULT_DISABLE_MLOCK = "true";
    };

    extraOptions = [
      "--cap-add=IPC_LOCK"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      # "--tmpfs=/vault/logs:rw,noexec,nosuid"
    ];
  };

  # Vault configuration file
  environment.etc."vault/vault.hcl".text = ''
    storage "raft" {
      path = "/vault/data"
      node_id = "vault-primary"
    }

    listener "tcp" {
      address = "0.0.0.0:8200"
      tls_disable = true
    }

    api_addr = "http://${localhost.ip}:8200"
    cluster_addr = "http://${localhost.ip}:8201"
    disable_mlock = true
    ui = true
  '';

  systemd = {
    services = {
      # Vault container service configuration
      "podman-vault" = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Restart = "always";
          RestartSec = "10s";
        };
      };

      # Vault unseal service (runs after each reboot)
      vault-unseal = {
        description = "Unseal HashiCorp Vault";
        after = [ "podman-vault.service" ];
        wants = [ "podman-vault.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";

          ExecStart = pkgs.writeShellScript "vault-unseal" ''
            set -euo pipefail

            export VAULT_ADDR=http://${localhost.ip}:8200
            export HOME=/root

            # Wait for Vault to be ready (accept any HTTP response including 503 when sealed)
            echo "Waiting for Vault to start..."
            timeout=60
            while [ $timeout -gt 0 ]; do
              if ${pkgs.curl}/bin/curl -s http://${localhost.ip}:8200/v1/sys/health >/dev/null 2>&1; then
                break
              fi
              sleep 1
              timeout=$((timeout - 1))
            done

            if [ $timeout -eq 0 ]; then
              echo "ERROR: Vault did not start within 60 seconds"
              exit 1
            fi

            # Check if already unsealed
            if ${pkgs.vault}/bin/vault status 2>&1 | ${pkgs.gnugrep}/bin/grep -q "Sealed[[:space:]]*false"; then
              echo "Vault is already unsealed"
              exit 0
            fi

            echo "Vault is sealed. Unsealing..."

            # Read recovery keys (already decrypted by SOPS)
            RECOVERY_KEYS=$(cat ${config.sops.secrets.vault-recovery-keys.path})

            # Check if keys are placeholders
            if echo "$RECOVERY_KEYS" | ${pkgs.gnugrep}/bin/grep -qi "placeholder"; then
              echo "Recovery keys appear to be placeholders. Update secrets.yaml with real keys after initializing Vault"
              exit 0
            fi

            # Unseal with first 3 keys (threshold)
            KEY1=$(echo "$RECOVERY_KEYS" | ${pkgs.yq}/bin/yq -r '.[0]')
            KEY2=$(echo "$RECOVERY_KEYS" | ${pkgs.yq}/bin/yq -r '.[1]')
            KEY3=$(echo "$RECOVERY_KEYS" | ${pkgs.yq}/bin/yq -r '.[2]')

            echo "Unsealing with key 1..."
            ${pkgs.vault}/bin/vault operator unseal "$KEY1"
            echo "Unsealing with key 2..."
            ${pkgs.vault}/bin/vault operator unseal "$KEY2"
            echo "Unsealing with key 3..."
            ${pkgs.vault}/bin/vault operator unseal "$KEY3"

            echo "Vault unsealed successfully!"
          '';
        };
      };

      # Vault audit log enabler (runs after unseal)
      vault-enable-audit = {
        description = "Enable HashiCorp Vault audit logging";
        after = [ "vault-unseal.service" ];
        wants = [ "vault-unseal.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;

          ExecStart = pkgs.writeShellScript "vault-enable-audit" ''
            set -euo pipefail

            export VAULT_ADDR=http://${localhost.ip}:8200
            export HOME=/root

            # Check if Vault is unsealed
            if ! ${pkgs.vault}/bin/vault status 2>&1 | ${pkgs.gnugrep}/bin/grep -q "Sealed.*false"; then
              echo "Vault is sealed. Skipping audit setup."
              exit 0
            fi

            # Get root token (already decrypted by SOPS)
            VAULT_TOKEN=$(cat ${config.sops.secrets.vault-root-token.path})

            if echo "$VAULT_TOKEN" | ${pkgs.gnugrep}/bin/grep -qi "placeholder"; then
              echo "Root token is a placeholder. Skipping audit setup."
              exit 0
            fi

            export VAULT_TOKEN

            # Enable file audit device if not already enabled
            if ! ${pkgs.vault}/bin/vault audit list | ${pkgs.gnugrep}/bin/grep -q "file/"; then
              ${pkgs.vault}/bin/vault audit enable file file_path=/vault/audit/audit.log
              echo "Audit logging enabled at /vault/audit/audit.log"
            else
              echo "Audit logging already enabled"
            fi
          '';
        };
      };

      # Vault backup service
      vault-backup = {
        description = "Backup HashiCorp Vault data";
        after = [ "podman-vault.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = "root";

          ExecStart = pkgs.writeShellScript "vault-backup" ''
            set -euo pipefail

            # Add gzip to PATH for tar -z flag
            export PATH="${pkgs.gzip}/bin:$PATH"

            BACKUP_DIR="/mnt/storage/vault/backups"
            TIMESTAMP=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)
            BACKUP_FILE="$BACKUP_DIR/vault-backup-$TIMESTAMP.tar.gz"

            echo "Creating Vault backup: $BACKUP_FILE"

            # Backup Vault data directory
            ${pkgs.gnutar}/bin/tar -czf "$BACKUP_FILE" -C /mnt/ssd/vault data/

            echo "Backup created successfully"

            # Keep only last 30 backups
            ls -t "$BACKUP_DIR"/vault-backup-*.tar.gz | \
              ${pkgs.coreutils}/bin/tail -n +31 | \
              ${pkgs.findutils}/bin/xargs -r ${pkgs.coreutils}/bin/rm -f

            echo "Old backups cleaned up"
          '';
        };
      };
    };

    # Vault backup timer - runs every 6 hours
    timers.vault-backup = {
      description = "Backup HashiCorp Vault data";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00,06,12,18:00:00";
        Persistent = true;
      };
    };
  };

  # SETUP INSTRUCTIONS:
  #
  # FIRST TIME SETUP (if Vault is not initialized):
  # 1. Start Vault container:
  #    sudo nixos-rebuild switch
  #
  # 2. Initialize Vault manually:
  #    vault operator init -key-shares=5 -key-threshold=3
  #
  # 3. Store the unseal keys and root token in SOPS:
  #    sops secrets.yaml
  #    # Add vault-root-token and vault-recovery-keys (as array)
  #
  # 4. Restart to unseal automatically:
  #    sudo systemctl restart vault-unseal.service
  #
  # NORMAL OPERATIONS:
  # - Vault automatically unseals on boot using SOPS keys
  # - Policies and AppRoles auto-configured via vault-setup-policies.service
  # - Vault agents auto-start and fetch secrets for containers
  #
  # RECOVERY:
  # - If sealed: sudo systemctl restart vault-unseal.service
  # - If lost root token: vault operator generate-root -init
  # - If data corrupted: restore from /mnt/ssd/vault/backups/
}
