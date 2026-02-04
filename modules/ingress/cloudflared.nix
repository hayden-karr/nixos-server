{ config, pkgs, ... }: {
  # Cloudflare Tunnel for Friend's Immich
  # Provides secure access to photos.example.com -> localhost:2284 (podman) or localhost:8081 (k3s)
  # No ports exposed to internet - all traffic through Cloudflare
  #
  # NOTE: When using k3s mode, update your tunnel in Cloudflare dashboard to:
  #   - subdomain.domain.com → http://localhost:8081
  #   - subdomain.domain.com → http://localhost:8081
  # (Nginx ingress controller routes by hostname, port 8081 avoids Pi-hole on 8080)

  # Secret configuration - uses LoadCredential
  # doesn't require the secret to be owned by the DynamicUser as per LoadCredential
  sops.secrets.cloudflared-tunnel-token = { mode = "0400"; };

  # Cloudflared tunnel service
  systemd.services.cloudflared-immich-friend = {
    description = "Cloudflare Tunnel for Immich Friend and Authelia";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    script = ''
      # Read token from credentials directory (managed by systemd)
      TOKEN=$(cat "$CREDENTIALS_DIRECTORY/tunnel-token")
      exec ${pkgs.cloudflared}/bin/cloudflared tunnel run --token "$TOKEN"
    '';

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";

      # Dynamic user
      DynamicUser = true;

      # LoadCredential: systemd securely loads the secret into $CREDENTIALS_DIRECTORY for this service only to use
      LoadCredential =
        "tunnel-token:${config.sops.secrets.cloudflared-tunnel-token.path}";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  # SECURITY NOTES:
  # - LoadCredential + DynamicUser
  # - No world-readable files - systemd handles permissions
  # - No firewall ports opened
  # - Traffic encrypted end-to-end via Cloudflare
  # - Only accessible via Cloudflare Tunnel
}
