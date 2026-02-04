{ pkgs, osConfig, ... }:

let
  # Authelia-Friend Configuration Setup
  # Generates configuration files and users database from SOPS secrets and Vault secrets
  # This runs as a user service before the authelia-friend container starts

  inherit (osConfig.serverConfig) smtp;

in {
  # Setup Authelia configuration and users database (user service)
  # Reads from Vault secrets via system-level Vault Agent
  systemd.user.services.authelia-friend-setup = {
    Unit = {
      Description = "Setup Authelia Friend configuration";
      # Only start if vault secrets and domain secrets exist
      ConditionPathExists = [
        "/run/vault/immich-friend/oauth-client-secret"
        "/run/vault/immich-friend/jwt-secret"
        "/run/vault/resend/resend-api-key"
        "/run/secrets/domain-base"
        "/run/secrets/domain-immich-friend"
        "/run/secrets/domain-authelia"
        "/run/secrets/domain-admin-email"
      ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ConditionPathExists =
        "!/mnt/ssd/immich_friend/authelia/configuration.yml";
      ExecStart = pkgs.writeShellScript "authelia-friend-setup" ''
                set -e
                ${pkgs.coreutils}/bin/mkdir -p /mnt/ssd/immich_friend/authelia

                # Generate RSA key pair for OIDC JWKS if it doesn't exist
                if [ ! -f /mnt/ssd/immich_friend/authelia/oidc_rsa.pem ]; then
                  ${pkgs.podman}/bin/podman run --rm \
                    -v /mnt/ssd/immich_friend/authelia:/keys \
                    authelia/authelia:latest \
                    authelia crypto pair rsa generate \
                    --directory /keys \
                    --file.private-key oidc_rsa.pem \
                    --file.public-key oidc_rsa.pub.pem
                fi

                # Read secrets from Vault via Vault Agent
                CLIENT_SECRET_PLAIN=$(${pkgs.coreutils}/bin/cat /run/vault/immich-friend/oauth-client-secret)
                JWT_SECRET=$(${pkgs.coreutils}/bin/cat /run/vault/immich-friend/jwt-secret)
                SMTP_PASSWORD=$(${pkgs.coreutils}/bin/cat /run/vault/resend/resend-api-key)

                # Read domain configuration from SOPS secrets (world-readable at /run/secrets/)
                BASE_DOMAIN=$(${pkgs.coreutils}/bin/cat /run/secrets/domain-base)
                IMMICH_DOMAIN=$(${pkgs.coreutils}/bin/cat /run/secrets/domain-immich-friend)
                AUTH_DOMAIN=$(${pkgs.coreutils}/bin/cat /run/secrets/domain-authelia)
                ADMIN_EMAIL=$(${pkgs.coreutils}/bin/cat /run/secrets/domain-admin-email)

                # Hash the client secret using PBKDF2 (recommended by Authelia)
                # Extract only the hash, removing "Digest: " prefix
                CLIENT_SECRET=$(${pkgs.podman}/bin/podman run --rm authelia/authelia:latest \
                  authelia crypto hash generate pbkdf2 --variant sha512 --password "$CLIENT_SECRET_PLAIN" \
                  | ${pkgs.gnugrep}/bin/grep -oP '\$pbkdf2-sha512\$[^\s]+')

                # Create notification file with proper permissions
                ${pkgs.coreutils}/bin/touch /mnt/ssd/immich_friend/authelia/notification.txt
                ${pkgs.coreutils}/bin/chmod 644 /mnt/ssd/immich_friend/authelia/notification.txt

                # Create Authelia configuration (shell expands variables in heredoc)
                ${pkgs.coreutils}/bin/cat > /mnt/ssd/immich_friend/authelia/configuration.yml <<EOF
        theme: auto
        default_2fa_method: webauthn

        server:
          address: 'tcp://0.0.0.0:9091/'

        log:
          level: info

        identity_validation:
          reset_password:
            jwt_secret: ''${JWT_SECRET}

        totp:
          issuer: ''${BASE_DOMAIN}

        webauthn:
          disable: false
          display_name: Authelia
          timeout: 60s

        authentication_backend:
          file:
            path: /config/users_database.yml

        access_control:
          default_policy: two_factor
          rules: []

        regulation:
          max_retries: 5
          find_time: 10m
          ban_time: 3h

        session:
          secret: file:///secrets/session
          cookies:
            - domain: ''${BASE_DOMAIN}
              authelia_url: https://''${AUTH_DOMAIN}

        storage:
          encryption_key: file:///secrets/storage
          local:
            path: /config/db.sqlite3

        notifier:
          disable_startup_check: true
          # Email notifications (comment out and uncomment filesystem to disable)
          # smtp:
          #   host: ${smtp.host}
          #   port: ${toString smtp.port}
          #   username: ${smtp.username}
          #   password: ''${SMTP_PASSWORD}
          #   sender: "${smtp.from}"
          #   identifier: ''${BASE_DOMAIN}
          #   subject: "[Authelia] {title}"
          #   startup_check_address: ''${ADMIN_EMAIL}
          #   disable_require_tls: false
          #   disable_html_emails: false
          # Filesystem notifier (fallback - comment SMTP above and uncomment this to use)
          filesystem:
            filename: /config/notification.txt

        identity_providers:
          oidc:
            hmac_secret: file:///secrets/oidc
            jwks:
              - key_id: 'immich-friend-rsa'
                algorithm: 'RS256'
                use: 'sig'
                key: |
        $(${pkgs.gnused}/bin/sed 's/^/          /' /mnt/ssd/immich_friend/authelia/oidc_rsa.pem)
            clients:
              - client_id: immich-friend
                client_name: Immich Friend
                client_secret: ''${CLIENT_SECRET}
                public: false
                authorization_policy: two_factor
                token_endpoint_auth_method: client_secret_post
                redirect_uris:
                  - https://''${IMMICH_DOMAIN}/auth/login
                  - https://''${IMMICH_DOMAIN}/user-settings
                  - https://''${IMMICH_DOMAIN}/api/oauth/mobile-redirect
                  - app.immich:///oauth-callback
                scopes:
                  - openid
                  - profile
                  - email
                grant_types:
                  - authorization_code
                response_types:
                  - code
        EOF

                ${pkgs.coreutils}/bin/chmod 644 /mnt/ssd/immich_friend/authelia/configuration.yml

                # Create users database with a default user if doesn't exist
                if [ ! -f /mnt/ssd/immich_friend/authelia/users_database.yml ]; then
                  # Generate a random password and hash it
                  TEMP_PASS=$(${pkgs.openssl}/bin/openssl rand -base64 16)
                  TEMP_HASH=$(${pkgs.podman}/bin/podman run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$TEMP_PASS" | ${pkgs.coreutils}/bin/tail -1)

                  ${pkgs.coreutils}/bin/cat > /mnt/ssd/immich_friend/authelia/users_database.yml <<EOF
        users:
          admin:
            displayname: "Admin User"
            password: "''${TEMP_HASH}"
            email: ''${ADMIN_EMAIL}
            groups:
              - admins
        # Temporary password: ''${TEMP_PASS}
        # Change this password after first login!
        # To add more users, run:
        # podman run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YourPassword'
        EOF

                  ${pkgs.coreutils}/bin/chmod 644 /mnt/ssd/immich_friend/authelia/users_database.yml
                  ${pkgs.coreutils}/bin/echo "Authelia temporary admin password: $TEMP_PASS" > /mnt/ssd/immich_friend/authelia/ADMIN_PASSWORD.txt
                  ${pkgs.coreutils}/bin/chmod 600 /mnt/ssd/immich_friend/authelia/ADMIN_PASSWORD.txt
                fi

                # Ensure RSA keys are readable
                ${pkgs.coreutils}/bin/chmod 644 /mnt/ssd/immich_friend/authelia/oidc_rsa.pem 2>/dev/null || true
                ${pkgs.coreutils}/bin/chmod 644 /mnt/ssd/immich_friend/authelia/oidc_rsa.pub.pem 2>/dev/null || true
      '';
    };

    Install = { WantedBy = [ "default.target" ]; };
  };
}
