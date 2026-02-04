{
  imports = [
    # Networking
    ./networking.nix

    # VPN
    ./wireguard.nix
    ./wireguard-peer-gen.nix
  ];
}
