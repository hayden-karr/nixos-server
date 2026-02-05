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

      wireguard = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = globalConfig.network.wireguard.enable or false;
          description = ''
            Enable WireGuard VPN for remote access.
            When enabled, all nginx services become accessible via VPN.
            Requires domain-vpn secret in secrets.yaml.
          '';
        };
      };
    };

    # Nginx configuration
    nginx = {
      mode = lib.mkOption {
        type = lib.types.enum [ "domain-names" "ip-ports" ];
        default = globalConfig.nginx.mode;
        description = ''
          Nginx reverse proxy mode:
          - "domain-names": Uses friendly .local domains (e.g., immich.local) on port 443
            Requires Pi-hole DNS or manual /etc/hosts entries
            All services accessible via https://*.local
          - "ip-ports": Uses server IP with different ports (e.g., 192.168.1.100:2283)
            No DNS configuration needed
            Each service on different HTTPS port
        '';
      };
    };
  };

  # Set config values (these are already defaults in options above)
  config = { };
}
