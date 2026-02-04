{ pkgs, config, lib, ... }:

let
  inherit (config.serverConfig.network.server) vpnIp localIp;
  inherit (config.serverConfig.network) localhost;
  selfSignedMode = config.serverConfig.ingress.certMode == "self-signed";
in lib.mkIf selfSignedMode {
  # Nginx - Reverse proxy for friendly local domain names with HTTPS
  # Accessible from both VPN and LAN - provides *.local domains
  #
  # Most services accessible via VPN AND LAN:
  # - https://immich.local      → http://localhost:2283
  # - https://portainer.local   → http://localhost:9000
  # - https://forgejo.local     → http://localhost:3000 (Git)
  # - https://gitea.local       → http://localhost:3000 (Git - alternative, use one or the other)
  # - https://jellyfin.local    → http://localhost:8096
  # - https://n8n.local         → http://localhost:5678
  # - https://memos.local       → http://localhost:5230
  # - https://links.local       → http://localhost:3500 (Linkwarden)
  # - https://ai.local          → http://localhost:8088 (Ollama)
  # - https://argocd.local      → http://localhost:30443 (K3s GitOps - when enabled)
  #
  # VPN-ONLY services (explicit listen on VPN IP only):
  # - https://vault.local       → http://localhost:8222 (Vaultwarden)
  # - https://hashi-vault.local → http://localhost:8200 (HashiCorp Vault)
  # - https://monitoring.local  → http://localhost:3030 (Grafana)

  # Generate self-signed certificates for .local domains
  systemd.services.nginx-ssl-setup = {
    description = "Generate self-signed SSL certificates for nginx";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/nginx/ssl

      # Generate self-signed certificate for *.local domains
      if [ ! -f /var/lib/nginx/ssl/local-domains.crt ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
          -keyout /var/lib/nginx/ssl/local-domains.key \
          -out /var/lib/nginx/ssl/local-domains.crt \
          -subj "/CN=*.local" \
          -addext "subjectAltName=DNS:*.local,DNS:immich.local,DNS:vault.local,DNS:hashi-vault.local,DNS:authelia.local,DNS:portainer.local,DNS:gitea.local,DNS:forgejo.local,DNS:jellyfin.local,DNS:n8n.local,DNS:memos.local,DNS:links.local,DNS:monitoring.local,DNS:ai.local,DNS:argocd.local"

        chmod 644 /var/lib/nginx/ssl/local-domains.crt
        chmod 640 /var/lib/nginx/ssl/local-domains.key
        chown root:nginx /var/lib/nginx/ssl/local-domains.key
      fi
    '';
  };

  services.nginx = {
    enable = true;

    # Recommended settings for security and performance
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true; # Enable TLS settings for HTTPS

    # Common configuration for bot protection (applied to all virtualHosts)
    appendHttpConfig = ''
      # Block common bot scan paths to reduce attack surface
      # These paths don't exist on our server but bots scan for them constantly
      map $request_uri $is_blocked_path {
        default 0;
        # Version control and sensitive files
        "~*\.(git|svn|env|htaccess|htpasswd)$" 1;
        "~*/\.(git|svn|env|htaccess|htpasswd)" 1;
        # Common CMS admin panels
        "~*/wp-admin" 1;
        "~*/wp-login" 1;
        "~*/xmlrpc\.php" 1;
        # Database admin tools
        "~*/phpMyAdmin" 1;
        "~*/phpmyadmin" 1;
        "~*/pma" 1;
        "~*/adminer" 1;
        # Generic admin paths (but not API endpoints containing 'admin')
        "~*/admin$" 1;
        "~*/admin/" 1;
        "~*/administrator$" 1;
        "~*/administrator/" 1;
        # Config and backup files
        "~*/config\.php" 1;
        "~*/configuration\.php" 1;
        "~*/database\.sql" 1;
        "~*/db\.sql" 1;
        "~*/backup" 1;
        "~*/\.backup" 1;
        # Well-known PHP injection attempts
        "~*/\.well-known/.*\.php" 1;
      }
    '';

    # Listen on both VPN and LAN interfaces
    defaultListenAddresses = [ vpnIp localIp ];

    # Virtual hosts for each service
    virtualHosts = {
      # Immich - Photo management
      "immich.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:2283";
          proxyWebsockets = true; # Required for Immich live updates
          extraConfig = ''
            # Bot protection - block common exploit paths
            if ($is_blocked_path = 1) {
              return 403;
            }
            client_max_body_size 50000M;  # Allow large photo uploads
          '';
        };
      };

      # Vaultwarden - Password manager (VPN-ONLY for security)
      "vault.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        serverAliases = [ "vaultwarden.local" ];
        # Only listen on VPN interface
        listen = [{
          addr = vpnIp;
          port = 443;
          ssl = true;
        }];
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8222";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 525M;  # Allow large attachments
          '';
        };
      };

      # HashiCorp Vault UI - Secret management (VPN-only)
      "hashi-vault.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        serverAliases = [ "hashicorp-vault.local" ];
        # Only listen on VPN interface
        listen = [{
          addr = vpnIp;
          port = 443;
          ssl = true;
        }];
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8200";
          proxyWebsockets = true;
        };
      };

      # Authelia - SSO and OAuth provider (only needed for immich-friend OAuth)
      # Commenting out - not needed for direct access to services
      # "authelia.local" = {
      #   enableACME = false;
      #   forceSSL = true;
      #   sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
      #   sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
      #   locations."/" = {
      #     proxyPass = "http://${localhost.ip}:9091";
      #     proxyWebsockets = true;
      #   };
      # };

      # Portainer - Container management
      "portainer.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:9000";
          proxyWebsockets = true;
        };
      };

      # Forgejo - Git service
      "forgejo.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3000";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 1G;  # Allow large git pushes
          '';
        };
      };

      # Gitea - Git service (alternative to Forgejo, both use port 3000)
      "gitea.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3000";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 1G;  # Allow large git pushes
          '';
        };
      };

      # Jellyfin - Media server
      "jellyfin.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8096";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 0;  # No limit for media streaming
          '';
        };
      };

      # n8n - Workflow automation
      "n8n.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:5678";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 50M;  # Workflow files
          '';
        };
      };

      # Memos - Self-hosted note-taking and link management
      "memos.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:5230";
          proxyWebsockets = true;
        };
      };

      # Linkwarden - Bookmark manager
      "links.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3500";
          proxyWebsockets = true;
        };
      };

      # Grafana - Monitoring dashboards (VPN-ONLY via explicit listen block)
      "monitoring.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3030";
          proxyWebsockets = true;
        };
      };

      # AI Server - Ollama with Open WebUI
      "ai.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8088";
          proxyWebsockets = true;
          extraConfig = ''
            # Long timeouts for AI inference
            proxy_read_timeout 600s;
            proxy_connect_timeout 600s;
            proxy_send_timeout 600s;
          '';
        };
      };

      # ArgoCD - GitOps platform (only when K3s is enabled)
      # Proxies to K3s NodePort service on localhost:30443
      "argocd.local" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/local-domains.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/local-domains.key";
        locations."/" = {
          proxyPass = "http://${localhost.ip}:30443";
          proxyWebsockets = true;
          extraConfig = ''
            # ArgoCD-specific settings
            proxy_ssl_verify off;
            # proxy_http_version already set by recommendedProxySettings
          '';
        };
      };

    };
  };

  # Ensure nginx starts after SSL certificates are generated
  systemd.services.nginx = {
    after = [ "nginx-ssl-setup.service" ];
    requires = [ "nginx-ssl-setup.service" ];
  };

  # Firewall configuration consolidated in modules/system/networking.nix
  # Port 443 (HTTPS) opened for both LAN and VPN access

  # SECURITY NOTE: vault.local is configured to ONLY listen on VPN IP (<VPN_IP>)
  # So even though port 443 is open on LAN, Vaultwarden remains VPN-only

  # CLIENT SETUP INSTRUCTIONS:
  #
  # 1. Configure DNS via Pi-hole (recommended) OR manually add to /etc/hosts:
  #    <SERVER_IP>  immich.local vault.local hashi-vault.local portainer.local forgejo.local gitea.local jellyfin.local n8n.local memos.local links.local monitoring.local ai.local argocd.local
  #
  # 2. Trust the self-signed certificate:
  #    - Download: scp server:/var/lib/nginx/ssl/local-domains.crt ~/
  #    - Linux: sudo cp local-domains.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
  #    - macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain local-domains.crt
  #    - Windows: Import into "Trusted Root Certification Authorities"
  #    - Or just accept the browser warning each time
  #
  # 3. Access services via HTTPS:
  #    - https://immich.local (Photo management)
  #    - https://vault.local (Vaultwarden password manager - requires HTTPS for WebCrypto)
  #    - https://hashi-vault.local (HashiCorp Vault - VPN only)
  #    - https://portainer.local (Container management)
  #    - https://forgejo.local (Git)
  #    - https://gitea.local (Git - alternative)
  #    - https://jellyfin.local (Media streaming)
  #    - https://n8n.local (Workflow automation)
  #    - https://memos.local (Note-taking)
  #    - https://links.local (Linkwarden bookmark manager)
  #    - https://monitoring.local (Grafana dashboards - VPN only)
  #    - https://ai.local (Ollama AI server)
  #    - https://argocd.local (GitOps - when K3s enabled)
  #
  # SECURITY NOTES:
  # - HTTPS with self-signed certs for browser compatibility
  # - Nginx listens on both VPN and LAN IPs (from global-config.nix)
  # - VPN-only services (vault, hashi-vault, monitoring) use explicit listen blocks
  # - No public internet exposure (behind private network)
}
