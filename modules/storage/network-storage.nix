{ config, pkgs, ... }:

# Samba Network File Sharing
# WARNING: This configuration is UNTESTED and may require adjustments
# Provides SMB/CIFS access to server storage for Windows, macOS, and Linux clients

{

  services.samba = {
    enable = true;

    # Security settings
    securityType = "user"; # Require username/password
    enableNmbd = true; # NetBIOS name service (for network browsing)
    enableWinbindd = false; # We don't need Windows domain integration

    # Global Samba configuration
    extraConfig = ''
      # Server identification
      workgroup = WORKGROUP
      server string = NixOS Server
      netbios name = server

      # Security
      security = user
      map to guest = never
      guest ok = no

      # Performance tuning
      socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
      read raw = yes
      write raw = yes
      max xmit = 65535
      dead time = 15

      # macOS compatibility
      vfs objects = catia fruit streams_xattr
      fruit:metadata = stream
      fruit:model = MacSamba
      fruit:posix_rename = yes
      fruit:veto_appledouble = no
      fruit:nfs_aces = no
      fruit:wipe_intentionally_left_blank_rfork = yes
      fruit:delete_empty_adfiles = yes

      # Logging
      log file = /var/log/samba/log.%m
      max log size = 50
      log level = 1
    '';

    # Share definitions
    shares = {
      # Main storage share - read/write access
      storage = {
        path = "/mnt/storage";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "admin";
        "force group" = "users";
        comment = "Main Storage";
      };

      # SSD storage share
      ssd = {
        path = "/mnt/ssd";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "admin";
        "force group" = "users";
        comment = "SSD Storage";
      };

      # You can comment out shares you don't want to expose
      # or add more as needed
    };
  };

  # Auto-set Samba password from sops secret
  sops.secrets.samba-password = {
    owner = "root";
    mode = "0400";
  };

  systemd.services.samba-password-sync = {
    description = "Set Samba password from sops secret";
    wantedBy = [ "samba-smbd.service" ];
    before = [ "samba-smbd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Read password from sops secret and set it for the user
      ${pkgs.samba}/bin/smbpasswd -s -a admin < ${config.sops.secrets.samba-password.path}
      echo "Samba password set for user admin"
    '';
  };

  # Open firewall for Samba
  networking.firewall.allowedTCPPorts = [
    139 # NetBIOS Session Service
    445 # Microsoft-DS (SMB over TCP)
  ];
  networking.firewall.allowedUDPPorts = [
    137 # NetBIOS Name Service
    138 # NetBIOS Datagram Service
  ];

  # SETUP:
  # 1. Add samba password to secrets.yaml: samba-password: "YourPassword"
  # 2. Deploy: sudo nixos-rebuild switch
  # 3. Connect from clients:
  #    - Windows: \\server\storage (or \\<IP>\storage)
  #    - macOS: smb://server/storage (Cmd+K in Finder)
  #    - Linux: smb://server/storage
  # 4. Test: smbclient -L localhost -U admin
  #
  # Available shares: storage (/mnt/storage), ssd (/mnt/ssd)
  # Files owned by admin:users, permissions 0644/0755
  # Includes macOS compatibility and LAN performance optimizations
}
