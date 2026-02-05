{ pkgs, ... }:

{
  # Base system configuration

  environment = {
    # Minimal packages
    defaultPackages = [ ];
    systemPackages = with pkgs; [
      # btrfs tooling
      btrfs-progs

      # Editors
      vim

      # Version control
      git
      lazygit

      # System monitoring
      htop
      iotop
      nethogs

      # Network tools
      curl
      wget
      dnsutils

      # Text processing
      jq
      ripgrep

      # File management
      ncdu # Disk usage analyzer
      rclone # Cloud sync
      fclones # Duplicate finder
      rsync # File sync

      # Backup tools
      restic
      gzip

      # Age for SOPS
      age
      sops
      libargon2
      openssl

      # Infrastructure as Code
      opentofu

      # Terminal multiplexer
      zellij

      # QR Code For Wireguard
      qrencode
    ];
  };

  # Disable unnecessary services
  documentation.enable = false;
  documentation.nixos.enable = false;
  services.xserver.enable = false;

  # Security
  security = {
    apparmor.enable = true;
    audit.enable = true;
    auditd.enable = true;

    # Restrict ptrace to same user (prevents debugging other users' processes)
    allowUserNamespaces = true;
    protectKernelImage = true;
  };

  # Allow unfree for nvidia + hashicorp vault
  nixpkgs.config = { allowUnfree = true; };

  # Automatic garbage collection
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      max-jobs = "auto";
      auto-optimise-store = true;

      # Sandbox builds
      sandbox = true;

      # Allow nix commands for wheel group + container system users (needed for home-manager)
      allowed-users = [ "@wheel" "minecraft" ];
    };

    # Automatic garbage collection - removes old system generations
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Optimize store periodically
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };

  # System-wide shell configuration
  programs.bash = {
    completion.enable = true;

    shellAliases = {
      ll = "ls -lah";
      df = "df -h";
      du = "du -h";
      free = "free -h";

      # Safety aliases
      rm = "rm -i";
      cp = "cp -i";
      mv = "mv -i";

      # Quick commands
      rebuild = "doas nixos-rebuild switch --flake /etc/nixos#server";
      logs = "journalctl -f";
      container-logs = "podman logs -f";

      mc = "doas machinectl shell minecraft@ /usr/bin/env";
    };
  };

  time.timeZone = "America/Chicago";

  # Secrets - sops-nix configuration
  # Module-specific secrets are declared in their respective modules (separation of concerns)
  sops = {
    defaultSopsFile =
      ../../secrets.yaml; # Path from modules/system/ to repo root
    age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets = { "user-password".neededForUsers = true; };
  };

  system.stateVersion = "25.05";
}
