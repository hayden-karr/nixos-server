{ config, ... }:

let
  inherit (config.serverConfig.network) localhost server;
in {
  # Static Pages - Simple HTML pages served via nginx
  # Tunneled through cloudflared for public access
  # Directory structure defined in file-paths.nix

  # Eddie subdomain page with embedded YouTube video
  environment.etc."static-pages/eddie/index.html".text = ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Eddie's Page</title>
      <style>
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }

        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 20px;
        }

        .container {
          background: black;
          border-radius: 20px;
          box-shadow: 0 20px 60px rgba(0,0,0,0.3);
          max-width: 900px;
          width: 100%;
          padding: 40px;
        }

        h1 {
          color: white;
          margin-bottom: 10px;
          font-size: 2.5em;
        }

        .subtitle {
          color: white;
          margin-bottom: 30px;
          font-size: 1.1em;
        }

        .video-container {
          position: relative;
          padding-bottom: 56.25%; /* 16:9 aspect ratio */
          height: 0;
          overflow: hidden;
          border-radius: 10px;
          box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }

        .video-container iframe {
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          border: none;
        }

        @media (max-width: 600px) {
          .container {
            padding: 20px;
          }

          h1 {
            font-size: 2em;
          }
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>EDDIE!</h1>
        <p class="subtitle">Shork</p>

        <div class="video-container">
          <iframe
            src="https://www.youtube-nocookie.com/embed/CUDD85T9qD4"
            title="YouTube video player"
            frameborder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            referrerpolicy="strict-origin-when-cross-origin"
            allowfullscreen>
          </iframe>
        </div>
      </div>
    </body>
    </html>
  '';

  # Copy static content to web directory
  systemd.services.static-pages-setup = {
    description = "Setup static pages";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Copy eddie page
      mkdir -p /var/www/eddie
      cp ${
        config.environment.etc."static-pages/eddie/index.html".source
      } /var/www/eddie/index.html
      chown -R nginx:nginx /var/www/eddie
      chmod -R 755 /var/www/eddie
    '';
  };

  # Nginx configuration for eddie static page
  # VirtualHost name is arbitrary - cloudflared handles the actual domain routing
  # The real domain is configured in cloudflared and SOPS secret "domain-static-page-1"
  services.nginx.virtualHosts."eddie-static" = {
    # Cloudflared routes to port 80
    listen = [
      {
        addr = localhost.ip;
        port = 80;
      }
      {
        addr = server.localIp;
        port = 80;
      }
    ];

    locations."/" = {
      root = "/var/www/eddie";
      index = "index.html";

      # Security headers
      extraConfig = ''
        # Only allow embedding YouTube videos
        add_header Content-Security-Policy "default-src 'self'; frame-src https://www.youtube-nocookie.com; style-src 'unsafe-inline';" always;

        # Prevent clickjacking
        add_header X-Frame-Options "DENY" always;

        # Prevent MIME sniffing
        add_header X-Content-Type-Options "nosniff" always;

        # Disable referrer for privacy
        add_header Referrer-Policy "no-referrer" always;
      '';
    };
  };

  # Note: Configure cloudflared tunnel to route eddie.domain.com -> localhost:80
  # See cloudflared.nix for tunnel configuration
}
