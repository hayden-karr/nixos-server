{ pkgs, config, ... }:

let inherit (config.serverConfig.network.server) vpnNetwork vpnIp;
in {
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "wg-add-peer" ''
      #!/usr/bin/env bash
      set -euo pipefail

      # Network configuration from global-config.nix
      VPN_NETWORK="${vpnNetwork}"
      VPN_IP="${vpnIp}"
      # Extract network prefix (e.g., "10.0.0.0/24" -> "10.0.0")
      VPN_PREFIX=$(echo "$VPN_NETWORK" | ${pkgs.gnused}/bin/sed 's/\.[0-9]*\/.*$//')

      # Colors
      GREEN='\033[0;32m'
      BLUE='\033[0;34m'
      YELLOW='\033[1;33m'
      RED='\033[0;31m'
      NC='\033[0m'

      echo -e "''${BLUE}═══════════════════════════════════════════════════════''${NC}"
      echo -e "''${BLUE}  Wireguard Peer Generator''${NC}"
      echo -e "''${BLUE}═══════════════════════════════════════════════════════''${NC}"
      echo ""

      # Get server public key
      if ! SERVER_PUBKEY=$(${pkgs.wireguard-tools}/bin/wg show wg0 public-key 2>/dev/null); then
        echo -e "''${RED}ERROR: Cannot get server public key. Is Wireguard running?''${NC}"
        echo "Run: systemctl status wireguard-wg0"
        exit 1
      fi

      # Get server endpoint from SOPS secret (domain-vpn contains "vpn.yourdomain.com")
      VPN_DOMAIN=$(cat ${config.sops.secrets.domain-vpn.path})
      SERVER_ENDPOINT="$VPN_DOMAIN:51820"

      # Find next available IP
      EXISTING_IPS=$(${pkgs.wireguard-tools}/bin/wg show wg0 allowed-ips | ${pkgs.gawk}/bin/awk '{print $2}' | ${pkgs.gnused}/bin/sed 's/\/32//' | sort -V)
      LAST_OCTET=$(echo "$EXISTING_IPS" | ${pkgs.gnused}/bin/sed "s/$VPN_PREFIX\.//" | sort -n | tail -1)
      NEXT_OCTET=$((LAST_OCTET + 1))
      CLIENT_IP="$VPN_PREFIX.$NEXT_OCTET/32"

      echo -e "''${GREEN}Server Public Key:''${NC} $SERVER_PUBKEY"
      echo -e "''${GREEN}Server Endpoint:''${NC} $SERVER_ENDPOINT"
      echo -e "''${GREEN}Client IP:''${NC} $CLIENT_IP"
      echo ""

      # Ask for peer name
      read -p "Enter peer name (e.g., laptop, tablet, phone2): " PEER_NAME
      if [ -z "$PEER_NAME" ]; then
        echo -e "''${RED}ERROR: Peer name cannot be empty''${NC}"
        exit 1
      fi

      echo -e "''${YELLOW}Generating keypair...''${NC}"

      # Generate keys
      CLIENT_PRIVKEY=$(${pkgs.wireguard-tools}/bin/wg genkey)
      CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | ${pkgs.wireguard-tools}/bin/wg pubkey)

      echo -e "''${GREEN}✓ Keys generated''${NC}"
      echo ""
      echo -e "''${YELLOW}═══════════════════════════════════════════════════════''${NC}"
      echo -e "''${YELLOW}  STEP 1: Add to Server Configuration''${NC}"
      echo -e "''${YELLOW}═══════════════════════════════════════════════════════''${NC}"
      echo ""
      echo "Edit: modules/network/wireguard.nix"
      echo ""
      echo "Add this peer to the peers list:"
      echo ""
      echo -e "''${BLUE}      {
        publicKey = \"$CLIENT_PUBKEY\";
        allowedIPs = [ \"$CLIENT_IP\" ];
      }''${NC}"
      echo ""
      echo "Then run: nixos-rebuild switch"
      echo ""
      read -p "Press Enter when you've added the peer and deployed..."
      echo ""

      # Generate client config
      CONFIG_FILE="/tmp/wg-$PEER_NAME.conf"
      cat > "$CONFIG_FILE" <<EOF
      [Interface]
      PrivateKey = $CLIENT_PRIVKEY
      Address = $CLIENT_IP
      DNS = $VPN_IP

      [Peer]
      PublicKey = $SERVER_PUBKEY
      Endpoint = $SERVER_ENDPOINT
      AllowedIPs = 0.0.0.0/0, ::/0
      PersistentKeepalive = 25
      EOF

      echo -e "''${YELLOW}═══════════════════════════════════════════════════════''${NC}"
      echo -e "''${YELLOW}  STEP 2: Scan QR Code on Client Device''${NC}"
      echo -e "''${YELLOW}═══════════════════════════════════════════════════════''${NC}"
      echo ""
      echo -e "Peer: ''${GREEN}$PEER_NAME''${NC}"
      echo -e "IP: ''${GREEN}$CLIENT_IP''${NC}"
      echo ""

      # Show QR code
      ${pkgs.qrencode}/bin/qrencode -t ansiutf8 < "$CONFIG_FILE"

      echo ""
      echo -e "''${BLUE}Configuration saved to: $CONFIG_FILE''${NC}"
      echo ""
      echo "Options:"
      echo "  - Save as PNG: qrencode -o $PEER_NAME.png < $CONFIG_FILE"
      echo "  - View again: qrencode -t ansiutf8 < $CONFIG_FILE"
      echo "  - Manual config: cat $CONFIG_FILE"
      echo ""
      read -p "Delete temporary config file? [Y/n] " -n 1 -r
      echo

      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        rm -f "$CONFIG_FILE"
        echo -e "''${GREEN}✓ Temporary file deleted''${NC}"
      else
        echo -e "''${YELLOW}⚠ Temporary file kept at: $CONFIG_FILE''${NC}"
        echo -e "''${RED}Remember to delete it when done: rm $CONFIG_FILE''${NC}"
      fi

      echo ""
      echo -e "''${GREEN}═══════════════════════════════════════════════════════''${NC}"
      echo -e "''${GREEN}  Peer setup complete!''${NC}"
      echo -e "''${GREEN}═══════════════════════════════════════════════════════''${NC}"
      echo ""
      echo "Summary:"
      echo "  - Peer: $PEER_NAME"
      echo "  - IP: $CLIENT_IP"
      echo "  - Public Key: $CLIENT_PUBKEY"
      echo ""
    '')
  ];
}
