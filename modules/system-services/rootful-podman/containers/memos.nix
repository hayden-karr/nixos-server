{ pkgs, lib, config, ... }:

# Memos - Self-hosted note-taking and link management
# Secrets managed by Vault Agent (see modules/vault-agents.nix)
# Settings on the first user to disable sign ups

let
  vaultLib = import ../../../system-services/vault/vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  inherit (config.serverConfig.network.server) localIp;
  inherit (config.serverConfig.network) localhost;
in {

  virtualisation.oci-containers.containers.memos = {
    image = "neosmemo/memos:latest";
    autoStart = true;

    ports = [ "${localhost.ip}:5230:5230" ];

    volumes = [
      "/mnt/ssd/memos:/var/opt/memos:U"
      "/etc/localtime:/etc/localtime:ro"
      "/run/secrets/memos:/run/secrets:U,ro"
    ];

    # Load DSN from environment file created by ExecStartPre
    environmentFiles = [ "/run/secrets/memos/memos-env" ];

    environment = {
      # Use PostgreSQL instead of SQLite for production
      MEMOS_DRIVER = "postgres";
      # MEMOS_DSN loaded from environmentFiles

      # Server configuration
      MEMOS_PORT = "5230";
      MEMOS_MODE = "prod";
      MEMOS_ADDR = "0.0.0.0";

      # Public URL for link previews to work correctly
      MEMOS_PUBLIC_URL = "https://memos.local";

      # Timezone
      TZ = "America/Chicago";
    };

    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--tmpfs=/run:rw,noexec,nosuid"
      # "--userns=auto"
    ];
  };

  # CRITICAL: Ensure Memos starts AFTER PostgreSQL and Vault Agent
  systemd.services."podman-memos" = vaultLib.mkPodmanServiceWithDbCreds {
    name = "memos";
    inherit pkgs;
    additionalSecretSetup = ''
      # Build DSN environment file
      source /run/vault/memos/db-creds
      cat > /run/secrets/memos/memos-env <<EOF
      MEMOS_DSN=postgresql://$USERNAME:$PASSWORD@${localIp}:5432/memos_homelab?sslmode=disable
      EOF
    '';
  };

  # VPN-only access
  # Access: https://memos.local (via nginx) or http://10.0.0.1:5230 (direct)
  #
  # SETUP INSTRUCTIONS:
  #
  # 1. Vault manages all secrets automatically:
  #    - Dynamic PostgreSQL credentials (auto-rotated every 24h)
  #    - Database and user created automatically by vault-policies.nix
  #    - No manual secret management needed!
  #
  # 2. To verify Vault is working:
  #    sudo systemctl status vault-agent-memos
  #    ls -la /run/vault/memos/  # Should see db-creds file
  #
  # 3. Add memos.local DNS record to Pi-hole:
  #    Edit modules/containers/pihole.nix line 66:
  #
  # 4. Add nginx reverse proxy for memos.local:
  #
  # 5. Add memos module to configuration.nix:
  #    ./modules/containers/memos.nix
  #
  # 6. Deploy:
  #    sudo nixos-rebuild switch
  #
  # 7. Access Memos:
  #    https://memos.local
}
