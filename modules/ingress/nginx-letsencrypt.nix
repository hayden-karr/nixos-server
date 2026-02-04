{ config, lib, ... }:

# ═══════════════════════════════════════════════════════════════════════════
# Nginx with Let's Encrypt Certificates
# ═══════════════════════════════════════════════════════════════════════════
# This module provides HTTPS reverse proxy with Let's Encrypt certificates
# Alternative to nginx.nix (self-signed certs)
#
# REQUIREMENTS:
# - Domain registered and managed by Cloudflare DNS
# - Cloudflare API token with Zone:DNS:Edit and Zone:Zone:Read permissions
# - SOPS secrets.yaml with cloudflare-api-token
#
# SETUP:
# 1. Set certMode = "letsencrypt" and baseDomain in config.nix
# 2. Add Cloudflare API token to secrets.yaml (see line 100 below)
# 3. Run: sudo nixos-rebuild switch --flake .#server
#
# PRIVACY NOTE: Certificate Transparency logs will expose your subdomains
# ═══════════════════════════════════════════════════════════════════════════

let
  # Network addresses from global config
  inherit (config.serverConfig.network.server) vpnIp localIp;
  inherit (config.serverConfig.network) localhost;
  inherit (config.serverConfig.ingress) baseDomain;
  vpnIP = vpnIp; # Alias for compatibility
  lanIP = localIp; # Alias for compatibility

  letsencryptMode = config.serverConfig.ingress.certMode == "letsencrypt";

  # ═══════════════════════════════════════════════════════════════════════
  # SERVICE DEFINITIONS
  # ═══════════════════════════════════════════════════════════════════════
  # Each service maps to a subdomain (e.g., gitea.yourdomain.com)
  # Add new services here to automatically generate nginx virtual hosts
  # ═══════════════════════════════════════════════════════════════════════

  services = {
    immich = {
      description = "Photo management and sharing";
      port = 2283;
      extraConfig = "client_max_body_size 50000M;"; # Large photo uploads
    };

    vaultwarden = {
      description = "Password manager (Bitwarden-compatible)";
      port = 8222;
      vpnOnly = true; # Extra security for sensitive service
      serverAliases = [
        "vault.${baseDomain}"
      ]; # Support both vaultwarden and vault subdomains
      extraConfig = "client_max_body_size 525M;"; # Attachment support
    };

    "hashi-vault" = {
      description = "HashiCorp Vault - Secret management";
      port = 8200;
      vpnOnly = true;
      serverAliases = [ "hashicorp-vault.${baseDomain}" ];
    };

    forgejo = {
      description = "Git service";
      port = 3000;
      extraConfig = "client_max_body_size 1G;"; # Large git pushes
    };

    gitea = {
      description = "Git service (alternative to Forgejo)";
      port = 3000;
      extraConfig = "client_max_body_size 1G;"; # Large git pushes
    };

    n8n = {
      description = "Workflow automation platform";
      port = 5678;
      extraConfig = "client_max_body_size 50M;";
    };

    memos = {
      description = "Self-hosted note-taking";
      port = 5230;
    };

    linkwarden = {
      description = "Bookmark manager with screenshots";
      port = 3500;
      serverAliases = [ "links.${baseDomain}" ];
    };

    jellyfin = {
      description = "Media streaming server";
      port = 8096;
      extraConfig = "client_max_body_size 0;"; # No limit for media
    };

    portainer = {
      description = "Container management UI";
      port = 9000;
    };

    monitoring = {
      description = "Grafana monitoring dashboards";
      port = 3030;
      vpnOnly = true; # Monitoring should be internal only
    };

    ai = {
      description = "Ollama AI server with Open WebUI";
      port = 8088;
      extraConfig = ''
        # Extended timeouts for AI inference
        proxy_read_timeout 600s;
        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
      '';
    };
  };

in lib.mkIf letsencryptMode {
  # ═════════════════════════════════════════════════════════════════════════
  # SOPS Secret Configuration
  # ═════════════════════════════════════════════════════════════════════════
  # Add to secrets.yaml:
  #
  # cloudflare-api-token: |
  #   CF_DNS_API_TOKEN=your_cloudflare_api_token_here
  #
  # Get token from: https://dash.cloudflare.com/profile/api-tokens
  # Required permissions: Zone:DNS:Edit, Zone:Zone:Read
  # ═════════════════════════════════════════════════════════════════════════

  sops.secrets.cloudflare-api-token = {
    mode = "0400";
    owner = "acme";
  };

  # ═════════════════════════════════════════════════════════════════════════
  # Let's Encrypt ACME Configuration
  # ═════════════════════════════════════════════════════════════════════════

  security.acme = {
    acceptTerms = true;
    defaults = {
      inherit (config.serverConfig.user) email; # Let's Encrypt notifications

      # DNS-01 challenge via Cloudflare
      # Proves domain ownership by creating DNS TXT records via API
      # Works WITHOUT public HTTP server!
      dnsProvider = "cloudflare";
      credentialsFile = config.sops.secrets.cloudflare-api-token.path;

      # Let's Encrypt production server
      # For testing, use staging: https://acme-staging-v02.api.letsencrypt.org/directory
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };
  };

  # ═════════════════════════════════════════════════════════════════════════
  # Nginx Reverse Proxy
  # ═════════════════════════════════════════════════════════════════════════

  services.nginx = {
    enable = true;

    # Recommended security and performance settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # ═══════════════════════════════════════════════════════════════════════
    # Virtual Host Generation
    # ═══════════════════════════════════════════════════════════════════════
    # Automatically creates a virtual host for each service defined above
    # Pattern: <serviceName>.<baseDomain> → http://localhost:<port>
    #
    # Example: gitea.yourdomain.com → http://lacalhost:3000
    #
    # vpnOnly services: Listen only on VPN interface (10.0.0.1)
    # Normal services: Listen on both VPN and LAN interfaces
    # ═══════════════════════════════════════════════════════════════════════

    virtualHosts = lib.mapAttrs' (name: svcCfg:
      lib.nameValuePair "${name}.${baseDomain}" {
        # Listen configuration based on security requirements
        listen =
          # VPN-only services: Single listen block on VPN IP
          if (svcCfg.vpnOnly or false) then [{
            addr = vpnIP;
            port = 443;
            ssl = true;
          }]
          # Normal services: Listen on both VPN and LAN IPs
          else [
            {
              addr = vpnIP;
              port = 443;
              ssl = true;
            }
            {
              addr = lanIP;
              port = 443;
              ssl = true;
            }
          ];

        # Let's Encrypt certificate (auto-renewed every 60 days)
        enableACME = true;
        forceSSL = true;

        # Server aliases for alternate subdomain names
        serverAliases = svcCfg.serverAliases or [ ];

        # Reverse proxy to local service
        locations."/" = {
          proxyPass = "http://${localhost.ip}:${toString svcCfg.port}";
          proxyWebsockets = true; # Enable WebSocket support

          extraConfig = ''
            # Standard proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Defense in depth: Prevent search engine indexing
            add_header X-Robots-Tag "noindex, nofollow, noarchive" always;

            # Service-specific configuration
            ${svcCfg.extraConfig or ""}
          '';
        };
      }) services;
  };

  # ═════════════════════════════════════════════════════════════════════════
  # Firewall Configuration
  # ═════════════════════════════════════════════════════════════════════════

  networking.firewall = {
    interfaces."wg0".allowedTCPPorts = [ 443 ]; # VPN interface
    allowedTCPPorts = [ 443 ]; # All interfaces (LAN)
  };

  # ═════════════════════════════════════════════════════════════════════════
  # User/Group Setup
  # ═════════════════════════════════════════════════════════════════════════
  # Ensure acme user exists for certificate management

  users.users.acme = {
    isSystemUser = true;
    group = "acme";
  };
  users.groups.acme = { };
}

# ═══════════════════════════════════════════════════════════════════════════
# QUICK START GUIDE
# ═══════════════════════════════════════════════════════════════════════════
#
# 1. CONFIGURE DOMAIN (config.nix:48)
#    baseDomain = "yourdomain.com"
#
# 2. CREATE CLOUDFLARE API TOKEN
#    - Visit: https://dash.cloudflare.com/profile/api-tokens
#    - Template: "Edit zone DNS"
#    - Permissions: Zone:DNS:Edit + Zone:Zone:Read
#    - Scope: Your specific domain
#
# 3. ADD TOKEN TO secrets.yaml
#    cloudflare-api-token: |
#      CF_DNS_API_TOKEN=your_token_here
#    Then run: sops secrets.yaml
#
# 4. ACTIVATE THIS MODULE (modules/ingress/default.nix)
#    Comment out: ./nginx.nix
#    Uncomment: ./nginx-letsencrypt.nix
#
# 5. DEPLOY
#    sudo nixos-rebuild switch --flake .#server
#
# FIRST RUN:
# - ACME requests certificates (~30s per service)
# - Certificates stored in /var/lib/acme/
# - Auto-renewed every 60 days
#
# ACCESS SERVICES:
# - https://forgejo.yourdomain.com (or gitea.yourdomain.com)
# - https://n8n.yourdomain.com
# - https://vault.yourdomain.com (VPN-only)
# - etc.
#
# DNS SETUP (Optional):
# You can create A records in Cloudflare pointing to your VPN IP (10.0.0.1).
# DNS-01 challenge works WITHOUT public A records!
#
# PRIVACY WARNING:
# Certificate Transparency logs expose subdomains publicly.
# For maximum privacy, use nginx.nix with self-signed certificates instead.
#
# ═══════════════════════════════════════════════════════════════════════════
