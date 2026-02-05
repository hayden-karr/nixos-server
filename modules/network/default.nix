{
  imports = [
    # Networking
    ./networking.nix

    # WireGuard VPN (conditionally enabled)
    # Toggle in config.nix: network.wireguard.enable = true/false
    ./wireguard.nix
    ./wireguard-peer-gen.nix
  ];
}
