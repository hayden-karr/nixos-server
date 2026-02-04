{ config, pkgs, ... }: {
  # Home Manager configuration for minecraft user
  # This user runs Minecraft server containers in rootless mode

  imports = [
    ./containers/vanilla.nix # Vanilla Minecraft server (Paper)
    ./containers/modded.nix # Modded Minecraft server (Fabric)
  ];

  # Enable podman service for rootless containers
  services.podman = {
    enable = true;
    autoUpdate.enable = true;

    # Configure storage for BTRFS compatibility
    # Use BTRFS driver to avoid "value too large" errors with overlay on BTRFS
    settings.storage = { storage = { driver = "btrfs"; }; };
  };

  # User environment configuration
  home = {
    sessionVariables = {
      # Ensure PATH includes rootless podman socket
      DOCKER_HOST =
        "unix://${config.home.homeDirectory}/.local/share/containers/podman/podman.sock";
    };

    # Container management tools for monitoring/debugging
    packages = with pkgs; [ podman-compose podman-tui ];

    stateVersion = "25.05";
  };
}
