# Vault Container Metadata
# All container secrets and Vault configurations defined here
# Takes serverConfig as a parameter to access network configuration
serverConfig:

let
  inherit (serverConfig.network) localhost;
in
{
  # Global Vault configuration
  vaultAddr = "http://${localhost.ip}:8200";

  # PostgreSQL configuration
  postgres = {
    host = serverConfig.network.server.localIp;
    port = 5432;
    adminUser = "vault_admin";
    # Databases to create
    databases =
      [ "gitea" "forgejo" "immich" "vaultwarden" "n8n" "memos" "linkwarden" ];
  };

  # AppRole token configuration (applies to all containers)
  approle = {
    tokenTtl = "1h";
    tokenMaxTtl = "4h";
    secretIdBoundCidrs = "${localhost.ip}/32,10.88.0.0/16";
    tokenBoundCidrs =
      "${localhost.ip}/32,${serverConfig.network.server.vpnIp}/32,10.88.0.0/16";
  };

  # Container secret definitions
  # Each container gets:
  # - Optional dynamic database credentials (auto-rotated)
  # - Optional static KV secrets
  # - User/group for file ownership (rootless vs rootful)
  containers = {

    # === Rootful containers (run as root) ===

    # Photo management and sharing
    immich = {
      dynamicDb = {
        database = "immich";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [ ];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Password manager (Bitwarden-compatible)
    vaultwarden = {
      dynamicDb = {
        database = "vaultwarden";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [{
        path = "vaultwarden/admin-token";
        field = "token";
      }];
      outputFormat = "combined";
      useDatabaseUrlFile = true;
      user = "root";
      group = "root";
    };

    # Self-hosted Git service (alternative to Forgejo)
    gitea = {
      dynamicDb = {
        database = "gitea";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [ ];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Self-hosted Git service (default, community-driven)
    forgejo = {
      dynamicDb = {
        database = "forgejo";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [ ];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Workflow automation
    n8n = {
      dynamicDb = {
        database = "n8n";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [{
        path = "n8n/encryption-key";
        field = "key";
        envVar = "N8N_ENCRYPTION_KEY";
      }];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Note-taking
    memos = {
      dynamicDb = {
        database = "memos";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [ ];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Link/bookmark management
    linkwarden = {
      dynamicDb = {
        database = "linkwarden";
        ttl = "24h";
        maxTtl = "72h";
      };
      kvSecrets = [{
        path = "linkwarden/nextauth";
        field = "secret";
        envVar = "NEXTAUTH_SECRET";
        fileName = "nextauth-secret";
      }];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Backup repository server
    restic = {
      dynamicDb = null;
      kvSecrets = [{
        path = "restic/htpasswd";
        field = "htpasswd";
      }];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # DNS server and ad blocker
    pihole = {
      dynamicDb = null;
      kvSecrets = [{
        path = "pihole/webpassword";
        field = "password";
        envVar = "WEBPASSWORD";
      }];
      outputFormat = "combined";
      user = "root";
      group = "root";
    };

    # Network file sharing (SMB/CIFS)
    samba = {
      dynamicDb = null;
      kvSecrets = [{
        path = "samba/password";
        field = "password";
        fileName = "samba-password";
      }];
      outputFormat = "separate";
      user = "root";
      group = "root";
    };

    # Discord webhook (shared for alerts and notifications)
    discord = {
      dynamicDb = null;
      kvSecrets = [{
        path = "discord/webhook";
        field = "url";
        fileName = "discord-webhook-url";
      }];
      outputFormat = "separate";
      user = "root";
      group = "smtp";
    };

    # Email API key (shared for SMTP and alerts)
    resend = {
      dynamicDb = null;
      kvSecrets = [{
        path = "resend/api";
        field = "key";
        fileName = "resend-api-key";
      }];
      outputFormat = "separate";
      user = "root";
      group = "smtp";
    };

    # === Rootless containers (user-owned) ===

    # Minecraft vanilla server
    # minecraft = {
    #   dynamicDb = null;
    #   kvSecrets = [{
    #     path = "minecraft/whitelist";
    #     field = "json";
    #     fileName = "whitelist.json";
    #   }];
    #   outputFormat = "separate";
    #   user = "minecraft";
    #   group = "minecraft";
    # };

    # Minecraft modded server
    # minecraft-modded = {
    #   dynamicDb = null;
    #   kvSecrets = [{
    #     path = "minecraft-modded/whitelist";
    #     field = "json";
    #     fileName = "whitelist.json";
    #   }];
    #   outputFormat = "separate";
    #   user = "minecraft";
    #   group = "minecraft";
    # };

    # Immich with OAuth authentication (Authelia)
    immich-friend = {
      dynamicDb = null;
      kvSecrets = [
        {
          path = "immich-friend/oauth";
          field = "client_secret";
          fileName = "oauth-client-secret";
        }
        {
          path = "immich-friend/jwt";
          field = "secret";
          fileName = "jwt-secret";
        }
        {
          path = "immich-friend/session";
          field = "secret";
          fileName = "session-secret";
        }
        {
          path = "immich-friend/storage";
          field = "key";
          fileName = "storage-key";
        }
        {
          path = "immich-friend/oidc-hmac";
          field = "secret";
          fileName = "oidc-hmac-secret";
        }
        {
          path = "immich-friend/database";
          field = "password";
          fileName = "db-password";
        }
      ];
      outputFormat = "separate";
      user = "immich-friend";
      group = "immich-friend";
    };
  };
}
