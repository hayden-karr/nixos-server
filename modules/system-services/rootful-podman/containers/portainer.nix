_: {
  # Portainer - Container management UI
  # VPN-only access for admin
  # Access: http://10.0.0.1:9000 (via WireGuard)

  virtualisation.oci-containers.containers.portainer = {
    image = "portainer/portainer-ce:latest";
    autoStart = true;

    # Port mapping for better isolation
    ports = [ "9000:9000" "9443:9443" ];

    volumes = [
      # Portainer data persistence
      "/mnt/ssd/portainer/data:/data:U"

      # Podman socket access (for managing containers)
      "/run/podman/podman.sock:/var/run/docker.sock:ro"

      # Timezone
      "/etc/localtime:/etc/localtime:ro"
    ];

    environment = {
      # Portainer will be accessible on port 9000 (HTTP) and 9443 (HTTPS)
    };

    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      # "--userns=auto"
    ];
  };

  # Directory structure defined in file-paths.nix

  # No firewall ports opened - VPN-only access via WireGuard
  # Access: http://10.0.0.1:9000 (via VPN)

  # SECURITY NOTES:
  # - No public ports exposed
  # - Only accessible via WireGuard VPN (10.0.0.1:9000)
  # - Read-only access to Podman socket (can't modify host)
  # - Data persisted to /mnt/ssd/portainer/data
}
