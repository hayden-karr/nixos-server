{ config, lib, ... }:

let
  cfg = config.services.k3s;

  # K3s networking configuration
  # Controls whether k3s ports are exposed to LAN or VPN-only
  #
  # Security considerations:
  # - LAN access: Convenient but exposes cluster to local network threats
  # - VPN-only: More secure, requires VPN connection for all access
  # - SSH tunnel: Most secure, on-demand access only
  #
  # Configure via config.nix: container-backend.k3s.exposeLAN = true/false
in {
  config = lib.mkIf cfg.enable {
    networking.firewall = {
      # Conditionally expose k3s ports based on configuration
      allowedTCPPorts =
        lib.optionals config.serverConfig.container-backend.k3s.exposeLAN [
          6443 # k3s API server
          8300 # Vault (via NodePort)
          10443 # ArgoCD (via NodePort)
        ];

      # Always allow k3s ports via VPN
      interfaces."wg0" = {
        allowedTCPPorts = [
          6443 # k3s API server
          8300 # Vault (via NodePort)
          10443 # ArgoCD (via NodePort)
        ];
      };
    };
  };
}
