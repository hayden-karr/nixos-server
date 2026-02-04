{ pkgs, ... }:

# Restic REST Server - Backup repository for other PCs
# Secrets managed by Vault Agent (see modules/vault-agents.nix)

{
  virtualisation.oci-containers.containers.restic = {
    image = "restic/rest-server:latest";
    autoStart = true;

    # Port mapping for better isolation (not host network)
    # Using port 8001 on host since 8000 is used by nginx
    ports = [ "8001:8000" ];

    volumes = [
      # Backup repository storage on HDD pool (large capacity + SnapRAID parity)
      "/mnt/storage/restic/data:/data:U"

      # Password file for authentication from Vault
      # Must be at /data/.htpasswd for rest-server to find it
      "/run/secrets/restic/restic-htpasswd:/data/.htpasswd:ro"
    ];

    environment = {
      # Enable authentication with htpasswd file
      OPTIONS = "--listen 0.0.0.0:8000 --path /data";
    };

    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      # "--userns=auto"
    ];
  };

  # Ensure Restic starts after Vault Agent
  # Directory created by file-paths.nix
  systemd.services."podman-restic" = {
    after = [ "vault-agent-restic.service" ];
    requires = [ "vault-agent-restic.service" ];

    serviceConfig = {
      RestartSec = "5s";
      ExecStartPre = pkgs.writeShellScript "restic-secrets-setup" ''
        set -euo pipefail
        mkdir -p /run/secrets/restic

        # Link htpasswd file directly (only if it exists)
        if [ -f /run/vault/restic/restic-htpasswd ]; then
          ln -sf /run/vault/restic/restic-htpasswd /run/secrets/restic/restic-htpasswd
          echo "Secrets ready for Restic"
        else
          echo "Waiting for vault-agent to create /run/vault/restic/restic-htpasswd"
          exit 1
        fi
      '';
    };
  };

  # SETUP INSTRUCTIONS:
  #
  # 1. Generate password file (on server):
  #    sops secrets.yaml
  #    Add: restic-rest-password: |
  #           your-username:your-htpasswd-hash
  #
  # 2. Run: sudo nixos-rebuild switch
  #
  # 3. On client PC, initialize repository:
  #    restic -r rest:http://10.0.0.1:8001/mybackup init
  #
  # 4. Backup from client:
  #    restic -r rest:http://10.0.0.1:8001/mybackup backup ~/Documents
  #
  # 5. Restore from client:
  #    restic -r rest:http://10.0.0.1:8001/mybackup restore latest --target /tmp/restore
  #
  # BACKUP STRATEGY:
  # - Each client PC should use its own repository path (e.g., /desktop, /laptop)
  # - Run automated backups via systemd timer or cron
  # - Test restores regularly!
}
