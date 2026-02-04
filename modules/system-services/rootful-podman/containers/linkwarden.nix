{ pkgs, lib, config, ... }:

# Linkwarden - Bookmark manager with automatic screenshots and link previews
# Secrets managed by Vault Agent (see modules/vault-agents.nix)

let
  vaultLib = import ../../../system-services/vault/vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  inherit (config.serverConfig.network.server) localIp;

in {

  # Linkwarden container
  virtualisation.oci-containers.containers.linkwarden = {
    image = "ghcr.io/linkwarden/linkwarden:latest";
    autoStart = true;

    # Port mapping for better isolation
    ports = [ "3500:3000" ];

    volumes = [
      # Data directory (screenshots, archives)
      "/mnt/ssd/linkwarden/data:/data/data:U"

      # Timezone
      "/etc/localtime:/etc/localtime:ro"

      # Secrets from Vault
      "/run/secrets/linkwarden:/run/secrets:U,ro"
    ];

    # Load NEXTAUTH_SECRET from Vault
    environmentFiles = [ "/run/secrets/linkwarden/linkwarden-env" ];

    environment = {
      # Database connection (dynamic credentials injected via environmentFiles)
      # DATABASE_URL loaded from environmentFiles

      # NextAuth configuration (for authentication)
      NEXTAUTH_URL = "https://links.local";
      # NEXTAUTH_SECRET loaded from environmentFiles

      # Pagination settings
      NEXT_PUBLIC_PAGINATION_TAKE_COUNT = "20";

      # Disable registration after first user (optional security measure)
      # Set to "true" after you create your account
      NEXT_PUBLIC_DISABLE_REGISTRATION = "true";

      # Archive settings - enable full page archives
      NEXT_PUBLIC_ARCHIVE_FULL_PAGE = "true";

      # Screenshot settings
      NEXT_PUBLIC_SCREENSHOT_ENABLED = "true";

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

  # CRITICAL: Ensure Linkwarden starts AFTER PostgreSQL and Vault Agent
  systemd.services."podman-linkwarden" = vaultLib.mkPodmanServiceWithDbCreds {
    name = "linkwarden";
    inherit pkgs;
    additionalSecretSetup = ''
      # Extract and combine with NEXTAUTH_SECRET
      source /run/vault/linkwarden/db-creds
      source /run/vault/linkwarden/nextauth-secret
      cat > /run/secrets/linkwarden/linkwarden-env <<EOF
      DATABASE_URL=postgresql://$USERNAME:$PASSWORD@${localIp}:5432/linkwarden
      NEXTAUTH_SECRET=$NEXTAUTH_SECRET
      EOF
    '';
  };
}
