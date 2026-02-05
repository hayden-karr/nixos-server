# Vault Container Metadata
# All container secrets and Vault configurations defined here
# Takes serverConfig as a parameter to access network configuration
serverConfig:
let
  inherit (serverConfig.network) localhost;
  inherit (serverConfig.network.server) vpnIp;
in {
  # Global Vault configuration
  vaultAddr = "http://${localhost.ip}:8200";

  # PostgreSQL configuration
  postgres = {
    host = serverConfig.network.server.localIp;
    port = 5432;
    adminUser = "vault_admin";
    # Databases with _homelab suffix for safe branch switching
    databases = [
      "gitea_homelab"
      "forgejo_homelab"
      "immich_homelab"
      "vaultwarden_homelab"
      "n8n_homelab"
      "memos_homelab"
      "linkwarden_homelab"
    ];
  };

  # AppRole token configuration (applies to all containers)
  approle = {
    tokenTtl = "1h";
    tokenMaxTtl = "4h";
    secretIdBoundCidrs = "${localhost.ip}/32,10.88.0.0/16";
    tokenBoundCidrs = "${localhost.ip}/32,${vpnIp}/32,10.88.0.0/16";
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
        database = "immich_homelab";
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
        database = "vaultwarden_homelab";
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
        database = "gitea_homelab";
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
        database = "forgejo_homelab";
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
        database = "n8n_homelab";
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
        database = "memos_homelab";
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
        database = "linkwarden_homelab";
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
      group = "discord";
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
  };
}
