{ ... }:

{
  imports = [
    ./system.nix # System user definition
    # Home.nix imported by home-manager in flake.nix
    # - Podman containers (when backend = "podman")
    # - Rootless K3s (when backend = "k3s")
  ];
}
