{ pkgs, config, lib, ... }:

let
  inherit (config.serverConfig.network.server) vpnIp localIp;
  inherit (config.serverConfig.network) localhost;
  wireguardEnabled = config.serverConfig.network.wireguard.enable;

  # Helper function to generate listen blocks for a port
  # Always listens on LAN IP, optionally adds VPN IP if WireGuard enabled
  mkListenBlocks = port:
    [{
      addr = localIp;
      inherit port;
      ssl = true;
    }] ++ lib.optionals wireguardEnabled [{
      addr = vpnIp;
      inherit port;
      ssl = true;
    }];
in {
  # Nginx - HTTPS reverse proxy for homelab (LAN-only access)
  # All services accessible via https://<SERVER_IP>:<port>
  #
  # Service URLs (HTTPS):
  # - https://<SERVER_IP>:2283   → Immich (photos)
  # - https://<SERVER_IP>:8222   → Vaultwarden (passwords - REQUIRES HTTPS)
  # - https://<SERVER_IP>:8200   → HashiCorp Vault
  # - https://<SERVER_IP>:9000   → Portainer (containers)
  # - https://<SERVER_IP>:3000   → Forgejo (git)
  # - https://<SERVER_IP>:8096   → Jellyfin (media)
  # - https://<SERVER_IP>:5678   → n8n (automation - REQUIRES HTTPS)
  # - https://<SERVER_IP>:5230   → Memos (notes)
  # - https://<SERVER_IP>:3500   → Linkwarden (bookmarks)
  # - https://<SERVER_IP>:3030   → Grafana (monitoring)
  # - https://<SERVER_IP>:8088   → AI/Ollama

  # Generate self-signed certificate for server IP address
  systemd.services.nginx-ssl-setup = {
    description = "Generate self-signed SSL certificate for homelab IP";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/nginx/ssl

      # Generate self-signed certificate for IP address
      if [ ! -f /var/lib/nginx/ssl/homelab.crt ]; then
        ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
          -keyout /var/lib/nginx/ssl/homelab.key \
          -out /var/lib/nginx/ssl/homelab.crt \
          -subj "/CN=${localIp}" \
          -addext "subjectAltName=IP:${localIp}"

        chmod 644 /var/lib/nginx/ssl/homelab.crt
        chmod 640 /var/lib/nginx/ssl/homelab.key
        chown root:nginx /var/lib/nginx/ssl/homelab.key
      fi
    '';
  };

  services.nginx = {
    enable = true;

    # Recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Bot protection (applied to all virtualHosts)
    appendHttpConfig = ''
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

    # Virtual hosts - each service on different HTTPS port
    virtualHosts = {
      # Immich - Photo management
      "${localIp}:2283" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 2283;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:2283";
          proxyWebsockets = true;
          extraConfig = ''
            if ($is_blocked_path = 1) { return 403; }
            client_max_body_size 50000M;
          '';
        };
      };

      # Vaultwarden - Password manager (REQUIRES HTTPS)
      "${localIp}:8222" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 8222;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8222";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 525M;
          '';
        };
      };

      # HashiCorp Vault
      "${localIp}:8200" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 8200;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8200";
          proxyWebsockets = true;
        };
      };

      # Portainer - Container management
      "${localIp}:9000" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 9000;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:9000";
          proxyWebsockets = true;
        };
      };

      # Forgejo - Git service
      "${localIp}:3000" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 3000;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3000";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 1G;
          '';
        };
      };

      # Jellyfin - Media server
      "${localIp}:8096" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 8096;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8096";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 0;
          '';
        };
      };

      # n8n - Workflow automation (REQUIRES HTTPS)
      "${localIp}:5678" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 5678;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:5678";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 50M;
          '';
        };
      };

      # Memos - Note-taking
      "${localIp}:5230" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 5230;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:5230";
          proxyWebsockets = true;
        };
      };

      # Linkwarden - Bookmark manager
      "${localIp}:3500" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 3500;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3500";
          proxyWebsockets = true;
        };
      };

      # Grafana - Monitoring
      "${localIp}:3030" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 3030;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:3030";
          proxyWebsockets = true;
        };
      };

      # AI Server - Ollama
      "${localIp}:8088" = {
        enableACME = false;
        forceSSL = true;
        sslCertificate = "/var/lib/nginx/ssl/homelab.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/homelab.key";
        listen = mkListenBlocks 8088;
        locations."/" = {
          proxyPass = "http://${localhost.ip}:8088";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 600s;
            proxy_connect_timeout 600s;
            proxy_send_timeout 600s;
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

  # Open firewall ports for HTTPS access on LAN
  networking.firewall.allowedTCPPorts = [
    2283 # Immich
    8222 # Vaultwarden
    8200 # HashiCorp Vault
    9000 # Portainer
    3000 # Forgejo
    8096 # Jellyfin
    5678 # n8n
    5230 # Memos
    3500 # Linkwarden
    3030 # Grafana
    8088 # AI/Ollama
  ];

  # CLIENT SETUP INSTRUCTIONS:
  #
  # 1. Download and trust the self-signed certificate (to avoid browser warnings):
  #    scp admin@<SERVER_IP>:/var/lib/nginx/ssl/homelab.crt ~/
  #
  #    Linux: sudo cp homelab.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
  #    macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab.crt
  #    Windows: Import into "Trusted Root Certification Authorities"
  #    Or: Just accept the browser warning each time
  #
  # 2. Access services via HTTPS (on original ports):
  #    https://<SERVER_IP>:2283  - Immich (photos)
  #    https://<SERVER_IP>:8222  - Vaultwarden (passwords)
  #    https://<SERVER_IP>:3000  - Forgejo (git)
  #    https://<SERVER_IP>:5678  - n8n (automation)
  #    https://<SERVER_IP>:9000  - Portainer (containers)
  #    https://<SERVER_IP>:8096  - Jellyfin (media)
  #    https://<SERVER_IP>:5230  - Memos (notes)
  #    https://<SERVER_IP>:3500  - Linkwarden (bookmarks)
  #    https://<SERVER_IP>:3030  - Grafana (monitoring)
  #    https://<SERVER_IP>:8200  - HashiCorp Vault
  #    https://<SERVER_IP>:8088  - AI/Ollama
}
