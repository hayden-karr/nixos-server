{ lib, ... }:

# K3s Options (System-level)
# These options are configured in config.nix and read by user-level services

{
  options.container-backend.k3s = {
    # K3s server options
    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:6443";
      description = "K3s API server address";
    };

    # K3s network exposure
    exposeLAN = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to expose k3s services on the LAN interface.

        - false (recommended): VPN-only or SSH tunnel access
        - true: Expose k3s API (6443), Vault (8300), ArgoCD (10443) on LAN

        Configure in config.nix
      '';
    };
  };

  options.container-backend.k3s.gitops = {
    enable = lib.mkEnableOption "GitOps configuration for k3s" // {
      default = false; # Manually enable in config.nix
    };

    gitProvider = lib.mkOption {
      type = lib.types.enum [ "github" "gitea" ];
      default = "github";
      description = ''
        Git provider to use for GitOps.
        - "github": GitHub (recommended for external access)
        - "gitea": Self-hosted Gitea instance
      '';
    };

    # Authentication configuration
    sshKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/home/admin/.ssh/github";
      description = ''
        Path to SSH private key for Git authentication.
        Use this for private GitHub repos with existing SSH keys.
        If null, uses username/passwordFile for HTTPS auth.
      '';
    };

    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Git username for HTTPS authentication";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/github-token";
      description =
        "Path to file containing Git password/token for HTTPS authentication";
    };

    # GitHub configuration
    github = {
      repoURL = lib.mkOption {
        type = lib.types.str;
        default = "git@github.com:YOUR_USERNAME/YOUR_REPO.git";
        description = "GitHub repository URL (SSH format)";
      };

      targetRevision = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Git branch to track";
      };
    };

    # Gitea configuration
    gitea = {
      repoURL = lib.mkOption {
        type = lib.types.str;
        default = "http://gitea.local:3000/YOUR_USERNAME/nixos-server-2";
        description = "Gitea repository URL (external access)";
      };

      internalURL = lib.mkOption {
        type = lib.types.str;
        default = "http://host.k3s.internal:3000/YOUR_USERNAME/nixos-server-2";
        description = "Gitea URL accessible from inside k3s cluster";
      };

      targetRevision = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Git branch to track";
      };
    };
  };
}
