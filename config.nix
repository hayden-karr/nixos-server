# ==============================================
# SERVER CONFIGURATION
# ==============================================
# Single source of truth for all server settings
# Update this file to customize your deployment
{
  # ==========================================
  # USER CONFIGURATION
  # ==========================================
  user = {
    # Admin user settings
    email = "admin@example.com"; # Used for alerts, Let's Encrypt, Git, etc.
    gitName = "Your Name"; # Git commit author name
  };

  # ==========================================
  # SSH CONFIGURATION
  # ==========================================
  ssh = {
    # SSH public keys for admin user (REQUIRED for server access)
    # Generate with: ssh-keygen -t ed25519
    # Get public key: cat ~/.ssh/id_ed25519.pub
    authorizedKeys = [
      "ssh-ed25519 AAAAC3... your-key-here"
      # Add more keys as needed
    ];
  };

  # ==========================================
  # NETWORK CONFIGURATION
  # ==========================================
  network = {
    server = {
      # Server IP addresses - update to match your network
      localIp = "192.168.1.100"; # LAN IP address

      # Network ranges
      lanNetwork = "192.168.1.0/24"; # Local area network
      vpnNetwork = "10.0.0.0/24"; # WireGuard VPN network

      # WireGuard VPN IPs (used even when disabled for config reference)
      vpnIp = "10.0.0.1"; # WireGuard VPN IP
      vpnIpWithCidr = "10.0.0.1/24"; # VPN IP with CIDR notation
    };

    # WIREGUARD VPN (OPTIONAL)
    # Set enable = true to activate WireGuard VPN for remote access
    wireguard = {
      enable = true; # Toggle VPN on/off

      # REQUIREMENTS WHEN ENABLED:
      # 1. LAN-only testing (recommended first):
      #    - Set domain-vpn in secrets.yaml to: "YOUR_LOCAL_IP:51820"
      #    - Test VPN connection from local network first
      #
      # 2. Remote access (from internet):
      #    - Requires public IP or DDNS
      #    - Set domain-vpn in secrets.yaml to: "YOUR_PUBLIC_IP:51820"
      #    - Configure port forwarding on router: UDP 51820 → YOUR_LOCAL_IP:51820
      #
      # When enabled, all services become accessible via VPN (both nginx modes)
    };

    # Container network ranges (internal docker/podman bridges)
    containers = {
      immichNetwork = "10.88.0.0/15"; # Covers both 10.88.x.x and 10.89.x.x
      dockerBridge = "172.16.0.0/12"; # Docker default bridge network
    };

    # Standard localhost - never needs to change
    localhost = {
      ip = "127.0.0.1";
      network = "127.0.0.0/8";
    };
  };

  # ==========================================
  # NGINX CONFIGURATION
  # ==========================================
  nginx = {
    # Choose nginx reverse proxy mode
    # - "ip-ports": Server IP with different ports per service (no DNS needed)
    #   Access: https://192.168.1.100:2283, https://192.168.1.100:8222, etc.
    # - "domain-names": Friendly .local domains on port 443 (requires Pi-hole DNS)
    #   Access: https://immich.local, https://vault.local, etc.
    mode = "ip-ports";
  };
}
