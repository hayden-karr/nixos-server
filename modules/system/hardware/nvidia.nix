{ config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # NVIDIA Persistence Daemon - keeps GPU driver loaded at all times
  # Critical for containers (Immich ML, Jellyfin, Ollama) to avoid driver reload delays
  # Fixes race condition by waiting for kernel modules and udev before starting
  systemd.services.nvidia-persistenced = {
    after = [ "systemd-modules-load.service" "systemd-udev-settle.service" ];
    wants = [ "systemd-modules-load.service" ];
    # Only start if GPU is detected - prevents boot failure if GPU missing
    unitConfig = { ConditionPathExists = "/dev/nvidia0"; };
  };
}
