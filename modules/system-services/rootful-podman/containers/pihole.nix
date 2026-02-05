{ pkgs, config, ... }:

# Pi-hole - DNS server for .local domain resolution
# Secrets managed by Vault Agent (see modules/vault-agents.nix)

let inherit (config.serverConfig.network.server) localIp;
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

      # Allow DNS queries from any device on the network (not just localhost)
      # This is required for Pi-hole to work as a network-wide DNS server
      FTLCONF_dns_listeningMode = "all";

      # Custom DNS records using official Pi-hole v6 FTL environment variable
      # Format: semicolon-delimited string "IP HOSTNAME;IP HOSTNAME;..."
      # All services point to LAN IP (${localIp}) for homelab access
      FTLCONF_dns_hosts =
        "${localIp} immich.local;${localIp} hashi-vault.local; ${localIp} vault.local;${localIp} portainer.local; ${localIp} gitea.local; ${localIp} forgejo.local; ${localIp} jellyfin.local; ${localIp} n8n.local; ${localIp} memos.local; ${localIp} links.local; ${localIp} monitoring.local;${localIp} ai.local";
    };

    # Load environment variables from Vault secret (contains WEBPASSWORD)
    environmentFiles = [ "/run/secrets/pihole/pihole-env" ];

    ports = [
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
  # 3. Configure your router to use Pi-hole as DNS:
  #    - Access your router's admin panel
  #    - Set primary DNS to <SERVER_IP> (Pi-hole)
  #    - Set secondary DNS to 9.9.9.9 (Quad9 fallback)
  #    - This makes .local domains work for all devices on your network
  #
  # 4. Access admin panel:
  #    http://<SERVER_IP>:8080/admin
  #    Password: <what you set in secrets.yaml>
  #
  # 5. Test DNS resolution from any device on your LAN:
  #    nslookup forgejo.local
  #    Should return <SERVER_IP>
  #
  #    Now you can access services via .local domains:
  #    - https://forgejo.local
  #    - https://immich.local
  #    - https://vault.local
  #    - etc.
  #
}
