{ pkgs, config, ... }:

let
  inherit (config.serverConfig.network) localhost;
  waitDns = import ./wait-dns.nix { inherit pkgs; };
  waitForSecrets = import ./wait-for-secrets.nix { inherit pkgs; };

  immichWaitScript = waitForSecrets [
    "/run/vault/immich-friend/db-password"
    "/mnt/ssd/immich_friend/immich-config.yaml"
  ];

  # Immich-Friend - Container definitions
  # Secrets managed by system-level Vault Agent (see modules/vault/vault-agents.nix)
  # Network and PostgreSQL database defined in postgres.nix
  # Config setup defined in immich-config-setup.nix

in {
  # NOTE: AppRole credentials must be configured in system-level NixOS config
  # with mode 0444 so the user can read them. See vault-policies.nix.

  services.podman.containers = {
    # Redis - Required by Immich for job queuing
    immich-friend-redis = {
      image = "redis:alpine";
      autoStart = true;
      network = "immich-friend";

      extraPodmanArgs = [
        # Note: Security restrictions loosened - cap-drop can cause issues with redis user switching
        "--security-opt=no-new-privileges"
        "--read-only"
        "--tmpfs=/tmp:rw,noexec,nosuid"
      ];

      extraConfig.Service = { ExecStartPre = "${waitDns}"; };
    };

    # Immich Server - Friend's instance
    immich-friend = {
      image = "ghcr.io/immich-app/immich-server:release";
      autoStart = true;
      network = "immich-friend";

      ports = [ "${localhost.ip}:2284:2283" ]; # Different from your Immich (2283)

      volumes = [
        # Tiered storage like main Immich: originals on HDD, cache on SSD
        "/mnt/storage/immich_friend/originals:/usr/src/app/upload/library"
        "/mnt/ssd/immich_friend/thumbs:/usr/src/app/upload/thumbs"
        "/mnt/storage/immich_friend/encoded-video:/usr/src/app/upload/encoded-video"
        "/mnt/ssd/immich_friend/profile:/usr/src/app/upload/profile"
        "/mnt/ssd/immich_friend/upload:/usr/src/app/upload/upload"
        "/mnt/storage/immich_friend/backups:/usr/src/app/upload/backups"
        "/etc/localtime:/etc/localtime:ro"
        "/run/vault/immich-friend/db-password:/run/secrets/db_password:ro"

        # Declarative YAML configuration file
        "/mnt/ssd/immich_friend/immich-config.yaml:/config/config.yaml:ro"
      ];

      environment = {
        # Database connection - use container name for DNS
        DB_HOSTNAME = "immich-friend-postgres";
        DB_PORT = "5432";
        DB_USERNAME = "immich";
        DB_DATABASE_NAME = "immich";
        DB_PASSWORD_FILE = "/run/secrets/db_password";

        # Redis connection - use container name for DNS
        REDIS_HOSTNAME = "immich-friend-redis";
        REDIS_PORT = "6379";

        # No Machine Learning - backup only
        IMMICH_MACHINE_LEARNING_URL = "";

        # Upload location
        UPLOAD_LOCATION = "/usr/src/app/upload";

        # Run all workers (needed to move files from upload to library!)
        # IMMICH_WORKERS_INCLUDE = "api";  # DO NOT SET - disables microservices!
        IMMICH_WORKERS_CONCURRENCY = "1";

        # Limit background jobs for backup use case
        IMMICH_JOB_THUMBNAIL_GENERATION_CONCURRENCY = "1";
        IMMICH_JOB_METADATA_EXTRACTION_CONCURRENCY = "1";
        IMMICH_JOB_VIDEO_CONVERSION_CONCURRENCY = "1";

        # Public URL configuration loaded from YAML config (generated from SOPS secrets)
        # See immich-friend-config-setup service below

        # Point to declarative YAML config file
        IMMICH_CONFIG_FILE = "/config/config.yaml";
      };

      extraPodmanArgs = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--read-only"
        "--tmpfs=/tmp:rw,noexec,nosuid"

        # External DNS servers (podman's internal DNS may not forward at boot)
        "--dns=1.1.1.1"
        "--dns=1.0.0.1"
      ];

      extraConfig = {
        Unit = {
          After = [
            "immich-friend-config-setup.service"
            "vault-agent-immich-friend.service"
          ];
          Wants = [
            "immich-friend-config-setup.service"
            "vault-agent-immich-friend.service"
          ];
        };
        Service = { ExecStartPre = [ "${waitDns}" "${immichWaitScript}" ]; };
      };
    };
  };
}
