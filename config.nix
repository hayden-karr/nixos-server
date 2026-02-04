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
      vpnIp = "10.0.0.1"; # WireGuard VPN IP
      vpnIpWithCidr = "10.0.0.1/24"; # VPN IP with CIDR notation

      # Network ranges
      lanNetwork = "192.168.1.0/24"; # Local area network
      vpnNetwork = "10.0.0.0/24"; # WireGuard VPN network
    };

    # Container network ranges (internal docker/podman bridges)
    containers = {
      immichNetwork = "10.88.0.0/16"; # Immich container network
      immichFriendNetwork = "10.89.0.0/16"; # Immich-friend container network
      dockerBridge = "172.16.0.0/12"; # Docker default bridge network
    };

    # Standard localhost
    localhost = {
      ip = "127.0.0.1";
      network = "127.0.0.0/8";
    };
  };

  # ==========================================
  # INGRESS CONFIGURATION
  # ==========================================
  ingress = {
    # Certificate mode
    # - "self-signed": Self-signed certs for *.local domains (no external dependencies)
    # - "letsencrypt": Let's Encrypt with real domain (requires Cloudflare DNS)
    certMode = "self-signed"; # or "letsencrypt"

    # Domain name for Let's Encrypt certificates (only used when certMode = "letsencrypt")
    baseDomain = "example.com"; # e.g., "yourdomain.com"
  };

  # ==========================================
  # MAIL CONFIGURATION
  # ==========================================
  mail = {
    # "From" address for system emails (monitoring, alerts, etc.)
    from = "noreply@example.com"; # e.g., "noreply@yourdomain.com"
  };

  # ==========================================
  # MONITORING ALERTS
  # ==========================================
  monitoring = {
    alerts = {
      # Enable Discord alerts (requires discord-webhook-url in Vault)
      discord = true;
      # Enable email alerts (requires resend-api-key in Vault and mail.from configured)
      email = true;
    };
  };

  # ==========================================
  # CONTAINER DEPLOYMENT
  # ==========================================
  container-backend = {
    # Container backend selection
    # Change this to "k3s" to switch from podman to k3s
    backend = "k3s"; # "podman" or "k3s"

    # K3s configuration (only used when backend = "k3s")
    k3s = {
      # Storage configuration
      # "hostPath" shares data with podman (single-node only)
      # "pvc" for network storage (enables multi-node clusters)
      storageMode = "hostPath";

      # Storage class (only matters for pvc mode)
      # Options: "local-path", "nfs-client", "longhorn"
      storageClassName = "local-path";

      # Network exposure configuration
      # false = VPN-only or SSH tunnel access (recommended, secure)
      # true = Expose k3s API (6443), Vault (8300), ArgoCD (10443) on LAN
      exposeLAN = false;

      # GitOps configuration
      gitops = {
        enable = true; # Enable ArgoCD GitOps

        # Git provider: "gitea" (self-hosted) or "github" (cloud)
        gitProvider = "github"; # Using GitHub with SSH

        # Authentication - Choose ONE method:

        # OPTION 1: SSH Key (deploy key for ArgoCD - read-only, repository-specific)
        sshKeyPath = "/var/lib/immich-friend/.ssh/argocd-deploy-key";

        # OPTION 2: HTTPS with token (for Gitea or GitHub)
        # username = "YOUR_USERNAME";
        # passwordFile = "/run/secrets/git-token";  # SOPS-managed secret

        # Gitea configuration (for self-hosted git)
        gitea = {
          # External URL (for cloning/pushing from host)
          repoURL = "http://forgejo.local:3000/YOUR_USERNAME/nixos-server";

          # Internal URL (for ArgoCD inside k3s cluster)
          # Use host.k3s.internal to reach the host from k3s pods
          internalURL =
            "http://host.k3s.internal:3000/YOUR_USERNAME/nixos-server";

          # Git branch to track
          targetRevision = "main";
        };

        # GitHub configuration (using SSH)
        github = {
          repoURL =
            "git@github.com:YOUR_USERNAME/YOUR_REPO.git"; # SSH format for private repos
          targetRevision = "main";
        };
      };
    };
  };
}
