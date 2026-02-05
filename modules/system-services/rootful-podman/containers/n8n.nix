{ pkgs, lib, config, ... }:

# n8n - Workflow automation platform
# Secrets managed by Vault Agent (see modules/vault-agents.nix)

let
  vaultLib = import ../../../system-services/vault/vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  inherit (config.serverConfig.network.server) localIp;
  inherit (config.serverConfig.network) localhost;
in {
  virtualisation.oci-containers.containers.n8n = {
    image = "n8nio/n8n:latest";
    autoStart = true;

    ports = [ "${localhost.ip}:5678:5678" ];

    volumes = [
      "/mnt/ssd/n8n/data:/home/node/.n8n:U"
      "/etc/localtime:/etc/localtime:ro"
      "/run/secrets/n8n:/run/secrets:U,ro"
    ];

    environment = {
      N8N_HOST = "0.0.0.0";
      N8N_PORT = "5678";
      N8N_PROTOCOL = "https";
      # USE THE https://n8n.local if you have the nginx rather than the nginx-ip-ports to use pi-hole dns
      WEBHOOK_URL =
        "https://${localIp}:5678"; # Homelab mode (HTTPS via nginx on original port)

      # Database connection - credentials from Vault
      DB_TYPE = "postgresdb";
      DB_POSTGRESDB_HOST = localIp;
      DB_POSTGRESDB_PORT = "5432";
      DB_POSTGRESDB_DATABASE = "n8n_homelab";
      DB_POSTGRESDB_USER_FILE = "/run/secrets/db_username";
      DB_POSTGRESDB_PASSWORD_FILE = "/run/secrets/db_password";
      N8N_ENCRYPTION_KEY_FILE = "/run/secrets/encryption_key";

      # Task runners
      N8N_RUNNERS_ENABLED = "true";

      # Timezone
      GENERIC_TIMEZONE = "America/Chicago";
      TZ = "America/Chicago";

      # Execution settings
      EXECUTIONS_DATA_SAVE_ON_SUCCESS = "all";
      EXECUTIONS_DATA_SAVE_ON_ERROR = "all";
      EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS = "true";
    };

    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--tmpfs=/run:rw,noexec,nosuid"
      "--tmpfs=/home/node/.cache:rw,noexec,nosuid"
      # "--userns=auto"
    ];
  };

  systemd.services."podman-n8n" = vaultLib.mkPodmanServiceWithDbCreds {
    name = "n8n";
    inherit pkgs;
    additionalSecretSetup = ''
      # Extract encryption key
      source /run/vault/n8n/n8n-encryption-key
      echo "$N8N_ENCRYPTION_KEY" > /run/secrets/n8n/encryption_key
      chmod 400 /run/secrets/n8n/encryption_key
    '';
  };
}
