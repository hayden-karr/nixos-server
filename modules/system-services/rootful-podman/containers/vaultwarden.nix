_:

# Vaultwarden - Self-hosted Bitwarden-compatible password manager
# Secrets managed by Vault Agent (see modules/vault-agents.nix)
# Container configuration automatically integrates with metadata-driven Vault setup

{
  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server:latest";
    autoStart = true;
    ports = [ "8222:8222" ];

    volumes = [
      "/mnt/ssd/vaultwarden/data:/data:U"
      "/etc/localtime:/etc/localtime:ro"
      "/run/vault/vaultwarden/database-url:/run/secrets/database-url:ro"
      "/run/vault/vaultwarden/vaultwarden-admin-token:/run/secrets/admin-token:ro"
    ];

    environment = {
      # Database connection via file (supports dynamic credential rotation)
      DATABASE_URL_FILE = "/run/secrets/database-url";

      # Admin token from Vault
      ADMIN_TOKEN_FILE = "/run/secrets/admin-token";

      # Domain and network
      DOMAIN = "https://vault.local";
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = "8222";

      # Security settings
      SIGNUPS_ALLOWED = "false";
      INVITATIONS_ALLOWED = "true";
      SHOW_PASSWORD_HINT = "false";

      # Logging
      LOG_LEVEL = "info";
      EXTENDED_LOGGING = "true";
      ICON_SERVICE = "internal";
    };

    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      # "--userns=auto"
    ];
  };

  systemd.services."podman-vaultwarden" = {
    after = [
      "postgresql.service"
      "postgresql-vault-setup.service"
      "vault-agent-vaultwarden.service"
    ];
    requires = [ "postgresql.service" "vault-agent-vaultwarden.service" ];

    serviceConfig = { RestartSec = "5s"; };
  };
}
