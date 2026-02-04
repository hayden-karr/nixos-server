{ pkgs, config, ... }:

# Pi-hole - DNS server for .local domain resolution
# Secrets managed by Vault Agent (see modules/vault-agents.nix)

let inherit (config.serverConfig.network.server) vpnIp localIp;
in {
  virtualisation.oci-containers.containers.pihole = {
    image = "pihole/pihole:latest";
    autoStart = true;

    extraOptions = [
      "--cap-drop=ALL"
      "--cap-add=NET_BIND_SERVICE"
      "--cap-add=NET_RAW"
      "--cap-add=CHOWN"
      "--cap-add=SETFCAP"
      "--cap-add=FOWNER"
      "--cap-add=DAC_OVERRIDE"
      "--cap-add=SETGID"
      "--cap-add=SETUID"
      "--security-opt=no-new-privileges"
      # Removed --read-only - pihole needs write access
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--tmpfs=/run:rw,noexec,nosuid"
      # "--userns=auto"
    ];

    volumes = [
      "/mnt/ssd/pihole/etc:/etc/pihole:U"
      "/mnt/ssd/pihole/log:/var/log/pihole:U"
      "/mnt/ssd/pihole/dnsmasq:/etc/dnsmasq.d:U"
      "/etc/localtime:/etc/localtime:ro"
    ];

    environment = {
      # Timezone
      TZ = "America/Chicago";

      # Run dnsmasq as root (required for read-only filesystem with capabilities)
      DNSMASQ_USER = "root";

      # Web interface on port 8080 (not 80, nginx uses that)
      WEB_PORT = "8080";

      # DNS settings - Use Quad9 for privacy (same as your Private DNS)
      PIHOLE_DNS_ = "9.9.9.9;149.112.112.112"; # Quad9 upstream DNS servers
      DNSSEC = "true";

      # Web interface settings
      VIRTUAL_HOST = "pihole.local";

      # Disable FTL database (we only care about DNS)
      PIHOLE_FTL_CONF_REPLY_WHEN_BUSY = "DROP";

      # Allow queries from any source (since we're already firewalled by VPN)
      FTLCONF_dns_listeningMode = "all";

      # Custom DNS records using official Pi-hole v6 FTL environment variable
      # Format: semicolon-delimited string "IP HOSTNAME;IP HOSTNAME;..."
      # Most services point to LAN IP for both LAN and VPN access
      # vault.local = Vaultwarden (password manager, VPN-only)
      # hashicorp-vault.local = HashiCorp Vault UI (secret management, LAN access)
      FTLCONF_dns_hosts =
        "${localIp} immich.local;${vpnIp} hashi-vault.local; ${vpnIp} vault.local;${localIp} portainer.local; ${localIp} gitea.local; ${localIp} forgejo.local; ${localIp} jellyfin.local; ${localIp} n8n.local; ${localIp} memos.local; ${localIp} links.local; ${vpnIp} monitoring.local;${localIp} ai.local;${localIp} argocd.local";
    };

    # Load environment variables from Vault secret (contains WEBPASSWORD)
    environmentFiles = [ "/run/secrets/pihole/pihole-env" ];

    ports = [
      # VPN interface
      "${vpnIp}:53:53/tcp"
      "${vpnIp}:53:53/udp"
      "${vpnIp}:8080:80/tcp"

      # LAN interface for whole-network ad blocking
      "${localIp}:53:53/tcp"
      "${localIp}:53:53/udp"
      "${localIp}:8080:80/tcp" # Web interface accessible on LAN too
    ];
  };

  # Setup Pi-hole directories before container starts
  systemd.services.pihole-setup = {
    description = "Setup Pi-hole directories";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /mnt/ssd/pihole/etc
      mkdir -p /mnt/ssd/pihole/log
      mkdir -p /mnt/ssd/pihole/dnsmasq
    '';
  };

  # Ensure pihole starts after setup and vault
  systemd.services."podman-pihole" = {
    after = [ "pihole-setup.service" "vault-agent-pihole.service" ];
    requires = [ "pihole-setup.service" "vault-agent-pihole.service" ];

    serviceConfig = {
      RestartSec = "5s";
      ExecStartPre = pkgs.writeShellScript "pihole-secrets-setup" ''
        set -euo pipefail
        mkdir -p /run/secrets/pihole

        # Link vault env file directly (only if it exists)
        if [ -f /run/vault/pihole/env ]; then
          ln -sf /run/vault/pihole/env /run/secrets/pihole/pihole-env
          echo "Secrets ready for Pi-hole"
        else
          echo "Waiting for vault-agent to create /run/vault/pihole/env"
          exit 1
        fi
      '';
    };
  };

  # SETUP INSTRUCTIONS:
  #
  # 1. Add password to secrets.yaml:
  #    sops secrets.yaml
  #
  #    pihole-env: |
  #      WEBPASSWORD=YOUR_PASSWORD_HERE
  #
  # 2. Deploy:
  #    sudo nixos-rebuild switch
  #
  # 3. Configure WireGuard clients to use Pi-hole DNS:
  #    Edit your WireGuard config and set:
  #    DNS = 10.0.0.1
  #
  #    Then reconnect to VPN.
  #
  # 4. Access admin panel:
  #    http://10.0.0.1:8080/admin
  #    Password: <what you set in secrets.yaml>
  #
  # 5. Test DNS resolution on your phone/laptop:
  #    nslookup gitea.local
  #    Should return 10.0.0.1
  #
  #    Now you can access:
  #    - http://gitea.local
  #    - http://immich.local
  #    - http://vault.local
  #    - etc.
  #
  # After setup, all .local domains will work on any device connected to VPN!
}
