{ lib, ... }:

# Global Configuration Options
# Makes values from config.nix available as NixOS options throughout the system
# This eliminates the need for relative imports like "import ../../config.nix"
#
# Usage in any module:
#   { config, ... }: {
#     # Access via config.serverConfig instead of importing
#     some.option = config.serverConfig.network.server.localIp;
#   }

let globalConfig = import ../../config.nix;
in {
  options.serverConfig = {
    # User configuration
    user = {
      email = lib.mkOption {
        type = lib.types.str;
        default = globalConfig.user.email;
        description = "Admin user email for alerts, Let's Encrypt, etc.";
      };
      gitName = lib.mkOption {
        type = lib.types.str;
        default = globalConfig.user.gitName;
        description = "Git commit author name";
      };
    };

    # SSH configuration
    ssh = {
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = globalConfig.ssh.authorizedKeys;
        description = "SSH public keys for admin user";
      };
    };

    # Network configuration
    network = {
      server = {
        localIp = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.server.localIp;
          description = "Server LAN IP address";
        };
        vpnIp = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.server.vpnIp;
          description = "Server WireGuard VPN IP";
        };
        vpnIpWithCidr = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.server.vpnIpWithCidr;
          description = "Server VPN IP with CIDR notation";
        };
        lanNetwork = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.server.lanNetwork;
          description = "Local area network CIDR";
        };
        vpnNetwork = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.server.vpnNetwork;
          description = "WireGuard VPN network CIDR";
        };
      };

      containers = {
        immichNetwork = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.containers.immichNetwork;
          description = "Immich container network CIDR";
        };
        immichFriendNetwork = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.containers.immichFriendNetwork;
          description = "Immich-friend container network CIDR";
        };
        dockerBridge = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.containers.dockerBridge;
          description = "Docker default bridge network CIDR";
        };
      };

      localhost = {
        ip = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.localhost.ip;
          description = "Localhost IP address (127.0.0.1)";
        };
        network = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.network.localhost.network;
          description = "Localhost network CIDR (127.0.0.0/8)";
        };
      };
    };

    # Ingress configuration
    ingress = {
      certMode = lib.mkOption {
        type = lib.types.enum [ "self-signed" "letsencrypt" ];
        default = globalConfig.ingress.certMode;
        description = ''
          Certificate mode for nginx:
          - "self-signed": Self-signed certs for *.local domains (no external dependencies, browser warnings)
          - "letsencrypt": Let's Encrypt with real domain (requires Cloudflare DNS, trusted certs)
        '';
      };

      baseDomain = lib.mkOption {
        type = lib.types.str;
        default = globalConfig.ingress.baseDomain;
        description =
          "Base domain for Let's Encrypt certificates (only used when certMode = letsencrypt)";
      };
    };

    # Mail configuration
    mail = {
      from = lib.mkOption {
        type = lib.types.str;
        default = globalConfig.mail.from;
        description = "From address for system emails";
      };
    };

    # SMTP configuration (Resend)
    smtp = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "smtp.resend.com";
        description = "SMTP server hostname";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP server port (STARTTLS)";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "resend";
        description = "SMTP authentication username";
      };
      from = lib.mkOption {
        type = lib.types.str;
        default = globalConfig.mail.from;
        description = "SMTP from address (same as mail.from)";
      };
    };

    # Monitoring alert configuration
    monitoring = {
      alerts = {
        discord = lib.mkOption {
          type = lib.types.bool;
          default = globalConfig.monitoring.alerts.discord;
          description = "Enable Discord alerts";
        };
        email = lib.mkOption {
          type = lib.types.bool;
          default = globalConfig.monitoring.alerts.email;
          description = "Enable email alerts via SMTP";
        };
      };
    };

    # Container backend configuration
    container-backend = {
      backend = lib.mkOption {
        type = lib.types.enum [ "podman" "k3s" ];
        default = globalConfig.container-backend.backend;
        description = "Container backend to use";
      };

      k3s = {
        storageMode = lib.mkOption {
          type = lib.types.enum [ "hostPath" "pvc" ];
          default = globalConfig.container-backend.k3s.storageMode;
          description = "K3s storage mode";
        };
        storageClassName = lib.mkOption {
          type = lib.types.str;
          default = globalConfig.container-backend.k3s.storageClassName;
          description = "K3s storage class name";
        };
        exposeLAN = lib.mkOption {
          type = lib.types.bool;
          default = globalConfig.container-backend.k3s.exposeLAN;
          description = "Whether to expose k3s services on LAN";
        };

        gitops = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = globalConfig.container-backend.k3s.gitops.enable;
            description = "Enable ArgoCD GitOps";
          };
          gitProvider = lib.mkOption {
            type = lib.types.enum [ "gitea" "github" ];
            default = globalConfig.container-backend.k3s.gitops.gitProvider;
            description = "Git provider for GitOps";
          };
          sshKeyPath = lib.mkOption {
            type = lib.types.str;
            default = globalConfig.container-backend.k3s.gitops.sshKeyPath;
            description = "SSH key path for Git authentication";
          };

          gitea = {
            repoURL = lib.mkOption {
              type = lib.types.str;
              default = globalConfig.container-backend.k3s.gitops.gitea.repoURL;
              description = "Gitea repository URL";
            };
            internalURL = lib.mkOption {
              type = lib.types.str;
              default =
                globalConfig.container-backend.k3s.gitops.gitea.internalURL;
              description = "Gitea internal URL for k3s";
            };
            targetRevision = lib.mkOption {
              type = lib.types.str;
              default =
                globalConfig.container-backend.k3s.gitops.gitea.targetRevision;
              description = "Git branch to track";
            };
          };

          github = {
            repoURL = lib.mkOption {
              type = lib.types.str;
              default =
                globalConfig.container-backend.k3s.gitops.github.repoURL;
              description = "GitHub repository URL";
            };
            targetRevision = lib.mkOption {
              type = lib.types.str;
              default =
                globalConfig.container-backend.k3s.gitops.github.targetRevision;
              description = "Git branch to track";
            };
          };
        };
      };
    };
  };

  # Set config values (these are already defaults in options above)
  config = { };
}
