{ config, pkgs, lib, ... }:

# Immich - Photo management (VPN-only access)
# Secrets managed by Vault Agent (see modules/vault-agents.nix)

let
  vaultLib = import ../../../system-services/vault/vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  vaultExtractDbCreds = vaultLib.mkVaultExtractDbCreds pkgs;
  inherit (config.serverConfig.network.server) localIp;

  # Immich declarative configuration - YAML format
  # Reference: https://docs.immich.app/install/config-file/
  yamlFormat = pkgs.formats.yaml { };
  immichConfig = yamlFormat.generate "immich-config.yaml" {
    ffmpeg = {
      crf = 23;
      threads = 0;
      preset = "ultrafast";
      targetVideoCodec = "h264";
      acceptedVideoCodecs = [ "h264" ];
      targetAudioCodec = "aac";
      acceptedAudioCodecs = [ "aac" "mp3" "libopus" "pcm_s16le" ];
      acceptedContainers = [ "mov" "ogg" "webm" ];
      targetResolution = "720";
      maxBitrate = "0";
      bframes = -1;
      refs = 0;
      gopSize = 0;
      temporalAQ = false;
      cqMode = "auto";
      twoPass = false;
      preferredHwDevice = "auto";
      transcode = "required";
      tonemap = "hable";
      accel = "disabled";
      accelDecode = false;
    };

    backup = {
      database = {
        enabled = true;
        cronExpression = "0 02 * * *";
        keepLastAmount = 14;
      };
    };

    job = {
      backgroundTask = { concurrency = 5; };
      smartSearch = { concurrency = 2; };
      metadataExtraction = { concurrency = 5; };
      faceDetection = { concurrency = 2; };
      search = { concurrency = 5; };
      sidecar = { concurrency = 5; };
      library = { concurrency = 5; };
      migration = { concurrency = 5; };
      thumbnailGeneration = { concurrency = 3; };
      videoConversion = { concurrency = 1; };
      notifications = { concurrency = 5; };
    };

    logging = {
      enabled = true;
      level = "log";
    };

    machineLearning = {
      enabled = true;
      urls = [ "http://immich-machine-learning:3003" ];
      clip = {
        enabled = true;
        modelName = "ViT-B-32__openai";
      };
      duplicateDetection = {
        enabled = true;
        maxDistance = 1.0e-2;
      };
      facialRecognition = {
        enabled = true;
        modelName = "buffalo_l";
        minScore = 0.7;
        maxDistance = 0.5;
        minFaces = 3;
      };
    };

    map = {
      enabled = true;
      lightStyle = "https://tiles.immich.cloud/v1/style/light.json";
      darkStyle = "https://tiles.immich.cloud/v1/style/dark.json";
    };

    reverseGeocoding = { enabled = true; };

    metadata = { faces = { import = false; }; };

    oauth = {
      autoLaunch = false;
      autoRegister = true;
      buttonText = "Login with OAuth";
      clientId = "";
      clientSecret = "";
      defaultStorageQuota = null;
      enabled = false;
      issuerUrl = "";
      mobileOverrideEnabled = false;
      mobileRedirectUri = "";
      scope = "openid email profile";
      signingAlgorithm = "RS256";
      profileSigningAlgorithm = "none";
      storageLabelClaim = "preferred_username";
      storageQuotaClaim = "immich_quota";
    };

    passwordLogin = { enabled = true; };

    storageTemplate = {
      enabled = true;
      hashVerificationEnabled = true;
      template = "{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}";
    };

    image = {
      thumbnail = {
        format = "webp";
        size = 250;
        quality = 80;
      };
      preview = {
        format = "jpeg";
        size = 1440;
        quality = 80;
      };
      colorspace = "p3";
      extractEmbedded = false;
    };

    newVersionCheck = { enabled = true; };

    trash = {
      enabled = true;
      days = 30;
    };

    theme = { customCss = ""; };

    library = {
      scan = {
        enabled = true;
        cronExpression = "0 0 * * *";
      };
      watch = { enabled = false; };
    };

    server = {
      externalDomain = "";
      loginPageMessage = "";
    };

    notifications = {
      smtp = {
        enabled = false;
        from = "";
        replyTo = "";
        transport = {
          ignoreCert = false;
          host = "";
          port = 587;
          username = "";
          password = "";
        };
      };
    };

    user = { deleteDelay = 7; };
  };
in {
  # Redis for Immich caching
  virtualisation = {
    oci-containers = {
      containers = {
        immich-redis = {
          image = "redis:alpine";
          autoStart = true;
          extraOptions = [
            "--network=immich"
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges"
            "--read-only"
            "--tmpfs=/tmp:rw,noexec,nosuid"
            "--tmpfs=/run:rw,noexec,nosuid"
            "--tmpfs=/data:rw,noexec,nosuid"
            # "--userns=auto"
          ];
        };

        # Immich Machine Learning - GPU accelerated
        immich-ml = {
          image = "ghcr.io/immich-app/immich-machine-learning:release";
          autoStart = true;
          extraOptions = [
            "--network=immich"
            "--device=nvidia.com/gpu=all" # Use NVIDIA GPU for ML
            "--security-opt=no-new-privileges"
            "--tmpfs=/tmp:rw,exec"
          ];
          volumes = [ "/mnt/ssd/immich/model-cache:/cache:U" ];
          environment = {
            # Enable GPU acceleration
            MACHINE_LEARNING_DEVICE = "cuda";

            # Reduce CPU usage - load models on-demand instead of at startup
            MACHINE_LEARNING_EAGER_STARTUP = "false";

            # Limit concurrent model loading
            MACHINE_LEARNING_MODEL_TTL = "300"; # Unload models after 5min idle
          };
        };

        # Immich Server
        immich = {
          image = "ghcr.io/immich-app/immich-server:release";
          autoStart = true;

          # Port mapping for better isolation
          ports = [ "2283:2283" ];

          # Connect to immich network + allow access to host PostgreSQL
          extraOptions = [
            "--network=immich"
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges"
            "--read-only"
            "--tmpfs=/tmp:rw,noexec,nosuid"
            "--tmpfs=/run:rw,noexec,nosuid"
            # "--userns=auto"
          ];

          volumes = [
            # Tiered storage: Originals on HDD, thumbs/encoded on SSD
            # :U flag handles UID mapping for both rootful and rootless containers
            "/mnt/storage/immich/originals:/usr/src/app/upload/library:U"
            "/mnt/ssd/immich/thumbs:/usr/src/app/upload/thumbs:U"
            "/mnt/storage/immich/encoded-video:/usr/src/app/upload/encoded-video:U" # Moved to HDD pool
            "/mnt/ssd/immich/profile:/usr/src/app/upload/profile:U"
            "/mnt/ssd/immich/upload:/usr/src/app/upload/upload:U" # Temp upload directory
            "/mnt/storage/immich/backups:/usr/src/app/upload/backups:U" # Database backups on HDD (infrequent access)
            "/etc/localtime:/etc/localtime:ro"

            # Declarative YAML configuration file
            "${immichConfig}:/config/config.yaml:ro"

            # Secrets from Vault
            "/run/secrets/immich:/run/secrets:U,ro"
          ];

          environment = {
            # Database connection via direct host IP (simpler than host.containers.internal)
            DB_HOSTNAME = localIp;
            DB_PORT = "5432";
            DB_USERNAME_FILE = "/run/secrets/db_username";
            DB_DATABASE_NAME = "immich";
            DB_PASSWORD_FILE = "/run/secrets/db_password";

            # Redis connection - hardcoded IP due to DNS issues
            # TODO: Container name resolution (immich-redis) times out despite:
            #   - aardvark-dns running (confirmed via ps aux)
            #   - dns_enabled: true on network
            #   - Both containers on same network (10.89.0.0/24)
            #   - getent hosts immich-redis hangs indefinitely
            # This worked previously with hostname, unclear what changed
            # Investigate: podman version changes, DNS config, systemd-resolved conflict
            # Change immich-redis to 10.89.0.0/24 and it works -> further testing needed
            REDIS_HOSTNAME = "immich-redis";
            REDIS_PORT = "6379";

            # Machine Learning via container name (same network)
            IMMICH_MACHINE_LEARNING_URL = "http://immich-ml:3003";

            # Upload location (Immich creates subdirectories inside this)
            UPLOAD_LOCATION = "/usr/src/app/upload";

            # CPU usage reduction - run all workers but limit concurrency
            # IMMICH_WORKERS_INCLUDE = "api";  # Disabled - need microservices for thumbnails!

            # Limit concurrent jobs (reduce from default to save CPU)
            IMMICH_WORKERS_CONCURRENCY = "2"; # 2 jobs at a time (was disabled)

            # Limit background job concurrency to reduce CPU usage
            IMMICH_JOB_THUMBNAIL_GENERATION_CONCURRENCY =
              "2"; # Need this enabled!
            IMMICH_JOB_METADATA_EXTRACTION_CONCURRENCY = "1";
            IMMICH_JOB_VIDEO_CONVERSION_CONCURRENCY = "1";
            IMMICH_JOB_SMART_SEARCH_CONCURRENCY = "1";
            IMMICH_JOB_FACE_DETECTION_CONCURRENCY = "1";

            # Point to declarative YAML config file
            IMMICH_CONFIG_FILE = "/config/config.yaml";
          };
        };
      };
    };
  };

  # Create isolated podman network for Immich containers to communicate
  systemd = {
    services = {
      "podman-network-immich" = {
        description = "Create Podman network for Immich";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${config.virtualisation.podman.package}/bin/podman network exists immich || \
          ${config.virtualisation.podman.package}/bin/podman network create immich
        '';
        preStop = ''
          ${config.virtualisation.podman.package}/bin/podman network rm -f immich || true
        '';
      };

      # Ensure containers start after network is created
      "podman-immich-redis" = {
        after = [ "podman-network-immich.service" ];
        requires = [ "podman-network-immich.service" ];
      };

      "podman-immich-ml" = {
        after = [ "podman-network-immich.service" ];
        requires = [ "podman-network-immich.service" ];
      };

      "podman-immich" = {
        after = [
          "podman-network-immich.service"
          "podman-immich-redis.service"
          "podman-immich-ml.service"
          "postgresql.service"
          "postgresql-vault-setup.service"
          "vault-agent-immich.service"
        ];
        requires = [
          "podman-network-immich.service"
          "podman-immich-redis.service"
          "podman-immich-ml.service"
          "postgresql.service"
          "vault-agent-immich.service"
        ];

        serviceConfig = {
          RestartSec = "5s";
          ExecStartPre = [
            "${vaultExtractDbCreds}/bin/vault-extract-db-creds immich /run/secrets/immich"
          ];
        };
      };
    };
  };

  # VPN-only access
  # Access: https://immich.local (via nginx) or http://10.0.0.1:2283 (direct)
  #
  # CONFIGURE SERVER URL IN IMMICH WEB UI:
  # 1. Log in to https://immich.local
  # 2. Go to: Administration → Server Settings → External Domain
  # 3. Set to: https://immich.local
  # 4. This makes share links use the correct URL
}
