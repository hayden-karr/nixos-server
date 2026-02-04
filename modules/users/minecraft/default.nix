{
  imports = [
    ./system.nix # System user definition
    # Containers and home.nix are imported by home-manager in flake.nix, not here
  ];
}
