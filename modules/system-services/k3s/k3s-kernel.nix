{ config, pkgs, lib, ... }:

# K3s Kernel Requirements (System-level)
# Rootless K3s still requires certain kernel modules and sysctl settings
# These must be configured at system level (cannot be done by unprivileged user)

{
  config = lib.mkIf (config.serverConfig.container-backend.backend == "k3s") {
    # K3s required kernel modules
    boot.kernelModules = [
      "br_netfilter"
      "overlay"
      "nf_conntrack"
      "nf_nat"
      "xt_conntrack"
      "xt_MASQUERADE"
    ];

    # Enable nftables support for K3s networking
    networking.nftables.enable = true;

    # K3s required kernel settings
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

    # Delegate cgroup controllers for rootless k3s
    # Allows k3s to manage resources (memory, cpu, cpuset, etc.) in user namespace
    systemd.services."user@".serviceConfig.Delegate =
      "cpuset cpu io memory pids";

    # Create k3s data directories with proper ownership
    # Separated from podman directories for complete environment isolation
    systemd.tmpfiles.rules = [
      # SSD storage - frequently accessed data
      "d /mnt/ssd/immich_friend/k3s 0755 immich-friend immich-friend -"
      "d /mnt/ssd/immich_friend/k3s/postgres 0700 immich-friend immich-friend -"
      "d /mnt/ssd/immich_friend/k3s/authelia 0700 immich-friend immich-friend -"
      "d /mnt/ssd/immich_friend/k3s/thumbs 0755 immich-friend immich-friend -"
      "d /mnt/ssd/immich_friend/k3s/profile 0755 immich-friend immich-friend -"
      "d /mnt/ssd/immich_friend/k3s/upload 0755 immich-friend immich-friend -"

      # HDD storage - large, less frequently accessed data
      "d /mnt/storage/immich_friend/k3s 0755 immich-friend immich-friend -"
      "d /mnt/storage/immich_friend/k3s/originals 0755 immich-friend immich-friend -"
      "d /mnt/storage/immich_friend/k3s/encoded-video 0755 immich-friend immich-friend -"
      "d /mnt/storage/immich_friend/k3s/backups 0755 immich-friend immich-friend -"
    ];

    # Install kubectl and helm globally for admin user
    environment.systemPackages = with pkgs; [ kubectl kubernetes-helm ];

    # Set KUBECONFIG for all users (kubeconfig is world-readable mode 644)
    environment.variables.KUBECONFIG = "/var/lib/immich-friend/k3s/k3s.yaml";
  };
}
