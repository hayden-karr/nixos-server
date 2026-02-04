{ config, lib, pkgs, osConfig, ... }: {
  # Home Manager configuration for immich-friend user
  # Runs either Podman containers OR rootless K3s based on containerBackend setting

  imports =
    # Podman containers (when backend is podman)
    lib.optionals
    ((osConfig.serverConfig.container-backend.backend or "podman") != "k3s") [
      ./containers/network.nix # Podman network configuration
      ./containers/postgres.nix # PostgreSQL database
      ./containers/postgres-backup.nix # PostgreSQL daily backup
      ./containers/authelia-config-setup.nix # Authelia config generator
      ./containers/authelia.nix # Authelia OAuth provider
      ./containers/immich.nix # Immich server and Redis
      ./containers/immich-config-setup.nix # Immich YAML config generator
    ] ++
    # Rootless K3s (when backend is k3s)
    lib.optionals
    ((osConfig.serverConfig.container-backend.backend or "podman") == "k3s") [
      ./k3s # Rootless K3s server and ArgoCD
    ];

  # Enable podman service for rootless containers (only when not using k3s)
  services.podman = lib.mkIf
    ((osConfig.serverConfig.container-backend.backend or "podman") != "k3s") {
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
