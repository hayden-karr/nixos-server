_: {
  virtualisation = {
    containers = {
      enable = true;
      storage.settings = {
        storage = {
          driver = "overlay";
          graphroot = "/mnt/ssd/podman-storage";
          runroot = "/run/containers/storage";
        };
      };
    };
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune.enable = true;
      dockerCompat = true;
    };
    oci-containers.backend = "podman";
  };

  # Ensure nvidia-container-toolkit is available
  hardware.nvidia-container-toolkit.enable = true;
}
