{ config, lib, pkgs, osConfig, ... }:

# Rootless K3s - Lightweight Kubernetes running as immich-friend user
# All applications deployed from k8s/ directory via ArgoCD
# Runs in user systemd namespace for improved security

let
  k3sDataDir = "${config.home.homeDirectory}/k3s";
  kubeconfigPath = "${k3sDataDir}/k3s.yaml";
in {
  imports = [
    ./argocd.nix # GitOps platform
  ];

  config = lib.mkIf (osConfig.serverConfig.container-backend.backend == "k3s") {
    # Install K3s and rootless dependencies
    # kubectl and helm installed system-wide in k3s-kernel.nix
    home = {
      packages = with pkgs; [
        k3s
        slirp4netns # Required for rootless networking
      ];

      # Set KUBECONFIG environment variable
      sessionVariables = { KUBECONFIG = kubeconfigPath; };

      # Create K3s data directory
      file."k3s/.keep".text = "";
    };

    # Rootless K3s server service
    systemd.user.services.k3s-server = {
      Unit = {
        Description = "Rootless K3s Kubernetes server";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "exec";
        KillMode = "mixed";
        Delegate = "yes";
        LimitNOFILE = 1048576;
        LimitNPROC = "infinity";
        LimitCORE = "infinity";
        TasksMax = "infinity";
        Restart = "always";
        RestartSec = "5s";

        # K3s server command with rootless flags
        ExecStart = toString [
          "${pkgs.k3s}/bin/k3s server"
          "--data-dir=${k3sDataDir}"
          "--write-kubeconfig=${kubeconfigPath}"
          "--write-kubeconfig-mode=640"
          "--disable=traefik"
          # servicelb is REQUIRED for LoadBalancer services in rootless k3s
          # It binds LoadBalancer ports to the host network
          # "--disable=servicelb"  # DO NOT DISABLE
          "--disable=metrics-server"
          "--rootless"
        ];

        # Environment variables for rootless operation
        Environment = [
          "PATH=/run/wrappers/bin:${pkgs.k3s}/bin:${pkgs.slirp4netns}/bin:${pkgs.iptables}/bin:${pkgs.coreutils}/bin"
          "K3S_ROOTLESS=1"
        ];
      };

      Install = { WantedBy = [ "default.target" ]; };
    };

    # Note: Use standard kubectl commands (KUBECONFIG is set automatically)
    # - kubectl get nodes
    # - kubectl get pods -A
    # - journalctl --user -u k3s-server
  };
}
