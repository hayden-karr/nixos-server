{
  imports = [
    ./system.nix # System user definition
    # home.nix is imported by home-manager in flake.nix
    # SSH keys: modules/system/ssh.nix
    # FIDO2 support: modules/system/fido2.nix
  ];
}
