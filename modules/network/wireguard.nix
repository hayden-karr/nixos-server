{ config, lib, ... }:
let
  inherit (config.serverConfig.network.server) vpnIpWithCidr;
  wireguardEnabled = config.serverConfig.network.wireguard.enable;
  wireguard-priv-key = config.sops.secrets.wireguard-private-key.path;
in {
  # Decrypt WireGuard secrets from sops
  sops.secrets.wireguard-private-key = lib.mkIf wireguardEnabled {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets.domain-vpn = lib.mkIf wireguardEnabled {
    owner = "root";
    mode = "0400";
  };

  networking.wireguard.interfaces.wg0 = lib.mkIf wireguardEnabled {
    ips = [ vpnIpWithCidr ];
    listenPort = 51820;
    privateKeyFile = wireguard-priv-key;

    peers = [
      # Add your WireGuard peers here
      # Use: doas wg-add-peer (to generate client keys and show config)
      # Then add the peer configuration here and deploy
      #
      # Example peer configuration:
      # {
      #   publicKey = "CLIENT_PUBLIC_KEY_HERE";
      #   allowedIPs = [ "10.0.0.2/32" ]; # Unique IP for each peer
      # }
      # {
      #   publicKey = "ANOTHER_CLIENT_PUBLIC_KEY";
      #   allowedIPs = [ "10.0.0.3/32" ];
      # }
    ];
  };
}
