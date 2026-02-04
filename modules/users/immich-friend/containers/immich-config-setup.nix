{ pkgs, osConfig, ... }:

let
  # Immich-Friend Configuration Setup
  # Generates YAML configuration file from SOPS secrets and Vault secrets
  # This runs as a user service before the immich-friend container starts

  inherit (osConfig.serverConfig) smtp;

in {
  # Setup Immich configuration YAML (user service)
  systemd.user.services.immich-friend-config-setup = {
    Unit = {
      Description = "Setup the yaml config for immich-friend";
      # Only start if vault secrets and domain secrets exist
      ConditionPathExists = [
        "/run/vault/immich-friend/oauth-client-secret"
        "/run/vault/resend/resend-api-key"
        "/run/secrets/domain-immich-friend"
        "/run/secrets/domain-authelia"
      ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ConditionPathExists = "!/mnt/ssd/immich_friend/immich-config.yaml";
      ExecStart = pkgs.writeShellScript "immich-friend-config-setup" ''
                set -e

                # Read secrets from Vault (created by system vault-agent services)
                CLIENT_SECRET_PLAIN=$(${pkgs.coreutils}/bin/cat /run/vault/immich-friend/oauth-client-secret)
                RESEND_API_KEY=$(${pkgs.coreutils}/bin/cat /run/vault/resend/resend-api-key)

                # Read domain configuration from SOPS secrets (world-readable at /run/secrets/)
                IMMICH_DOMAIN=$(${pkgs.coreutils}/bin/cat /run/secrets/domain-immich-friend)
                AUTH_DOMAIN=$(${pkgs.coreutils}/bin/cat /run/secrets/domain-authelia)

                # Generate Immich config YAML (shell expands variables in heredoc)
                ${pkgs.coreutils}/bin/cat > /mnt/ssd/immich_friend/immich-config.yaml <<EOF
        # FFmpeg settings for video transcoding
        ffmpeg:
          crf: 23
          threads: 0
          preset: "ultrafast"
          targetVideoCodec: "h264"
          acceptedVideoCodecs:
            - "h264"
          targetAudioCodec: "aac"
          acceptedAudioCodecs:
            - "aac"
            - "mp3"
            - "libopus"
            - "pcm_s16le"
          acceptedContainers:
            - "mov"
            - "ogg"
            - "webm"
          targetResolution: "720"
          maxBitrate: "0"
          bframes: -1
          refs: 0
          gopSize: 0
          temporalAQ: false
          cqMode: "auto"
          twoPass: false
          preferredHwDevice: "auto"
          transcode: "required"
          tonemap: "hable"
          accel: "disabled"
          accelDecode: false

        # Backup settings
        backup:
          database:
            enabled: true
            cronExpression: "0 02 * * *"
            keepLastAmount: 14

        # Job concurrency
        job:
          backgroundTask:
            concurrency: 5
          smartSearch:
            concurrency: 2
          metadataExtraction:
            concurrency: 5
          faceDetection:
            concurrency: 2
          search:
            concurrency: 5
          sidecar:
            concurrency: 5
          library:
            concurrency: 5
          migration:
            concurrency: 5
          thumbnailGeneration:
            concurrency: 3
          videoConversion:
            concurrency: 1
          notifications:
            concurrency: 5

        # Logging
        logging:
          enabled: true
          level: "log"

        # Machine Learning
        machineLearning:
          enabled: false
          urls:
            - "http://immich-machine-learning:3003"
          clip:
            enabled: true
            modelName: "ViT-B-32__openai"
          duplicateDetection:
            enabled: true
            maxDistance: 0.01
          facialRecognition:
            enabled: true
            modelName: "buffalo_l"
            minScore: 0.7
            maxDistance: 0.5
            minFaces: 3

        # Map settings
        map:
          enabled: true
          lightStyle: "https://tiles.immich.cloud/v1/style/light.json"
          darkStyle: "https://tiles.immich.cloud/v1/style/dark.json"

        # Reverse geocoding
        reverseGeocoding:
          enabled: true

        # Metadata
        metadata:
          faces:
            import: false

        # OAuth settings for Authelia integration
        oauth:
          autoLaunch: true
          autoRegister: true
          buttonText: "Login with OAuth"
          clientId: "immich-friend"
          clientSecret: "''${CLIENT_SECRET_PLAIN}"
          tokenEndpointAuthMethod: "client_secret_post"
          defaultStorageQuota: null
          enabled: true
          issuerUrl: "https://''${AUTH_DOMAIN}"
          mobileOverrideEnabled: false
          mobileRedirectUri: ""
          scope: "openid email profile"
          signingAlgorithm: "RS256"
          profileSigningAlgorithm: "none"
          storageLabelClaim: "preferred_username"
          storageQuotaClaim: "immich_quota"

        # Password login
        passwordLogin:
          enabled: false

        # Storage template for organized file structure
        storageTemplate:
          enabled: true
          hashVerificationEnabled: true
          template: "{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}"

        # Image settings
        image:
          thumbnail:
            format: "webp"
            size: 250
            quality: 80
          preview:
            format: "jpeg"
            size: 1440
            quality: 80
          colorspace: "p3"
          extractEmbedded: false

        # New version check
        newVersionCheck:
          enabled: true

        # Trash settings
        trash:
          enabled: true
          days: 30

        # Theme
        theme:
          customCss: ""

        # Library settings
        library:
          scan:
            enabled: true
            cronExpression: "0 0 * * *"
          watch:
            enabled: false

        # Server config
        server:
          externalDomain: "https://''${IMMICH_DOMAIN}"
          loginPageMessage: ""

        # Notifications (comment out to disable email notifications)
        notifications:
          smtp:
            enabled: false
            from: "${smtp.from}"
            replyTo: "${smtp.from}"
            transport:
              ignoreCert: false
              host: "${smtp.host}"
              port: ${toString smtp.port}
              username: "${smtp.username}"
              password: "''${RESEND_API_KEY}"

        # User management
        user:
          deleteDelay: 7
        EOF

                ${pkgs.coreutils}/bin/chmod 644 /mnt/ssd/immich_friend/immich-config.yaml
      '';
    };

    Install = { WantedBy = [ "default.target" ]; };
  };
}
