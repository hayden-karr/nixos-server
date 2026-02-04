{ config, pkgs, lib, ... }: {
  # ===========================================================================
  # STORAGE POOL - MergeFS + SnapRAID
  # ===========================================================================
  # Pools all data HDDs into unified storage with parity protection.
  # References hdd-pool.nix for drive configuration.
  # ===========================================================================

  # Required packages
  environment.systemPackages = with pkgs; [ mergerfs snapraid ];

  # ===========================================================================
  # MERGERFS - Unified Pool Mount
  # ===========================================================================

  # Pool all data drives into /mnt/storage
  fileSystems."/mnt/storage" =
    lib.mkIf (config.storage.hddPool.dataDisks != [ ]) {
      device = lib.concatStringsSep ":"
        (map (disk: disk.mountPoint) config.storage.hddPool.dataDisks);
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=mfs" # Most free space for new files
        "moveonenospc=true" # Auto-move files if disk full
        "minfreespace=50G" # Keep 50GB free on each drive
      ];
    };

  # ===========================================================================
  # SYSTEMD CONFIGURATION
  # ===========================================================================

  systemd = {
    services = {
      # Ensure MergerFS mounts after all individual HDDs
      "mnt-storage.mount" = lib.mkIf (config.storage.hddPool.dataDisks != [ ]) {
        after = map (disk:
          "${
            lib.replaceStrings [ "/" ] [ "-" ]
            (lib.removePrefix "/" disk.mountPoint)
          }.mount") config.storage.hddPool.dataDisks;
        requires = map (disk:
          "${
            lib.replaceStrings [ "/" ] [ "-" ]
            (lib.removePrefix "/" disk.mountPoint)
          }.mount") config.storage.hddPool.dataDisks;
      };

      # SnapRAID sync - Daily parity calculation for new/changed files
      snapraid-sync = lib.mkIf (config.storage.hddPool.parityDisks != [ ]) {
        description = "SnapRAID sync - Calculate parity for changed files";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.snapraid}/bin/snapraid sync";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };

      # SnapRAID scrub - Weekly data integrity verification (10% of data, max 5 days old)
      snapraid-scrub = lib.mkIf (config.storage.hddPool.parityDisks != [ ]) {
        description = "SnapRAID scrub - Verify data integrity";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.snapraid}/bin/snapraid scrub -p 10 -o 5";
          Nice = 15;
          IOSchedulingClass = "idle";
        };
      };

      # SnapRAID status - Manual array health check
      snapraid-status = lib.mkIf (config.storage.hddPool.parityDisks != [ ]) {
        description = "SnapRAID status - Check array health";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.snapraid}/bin/snapraid status";
        };
      };
    };

    timers = {
      # Daily SnapRAID sync timer - Runs at a random time each day
      snapraid-sync = lib.mkIf (config.storage.hddPool.parityDisks != [ ]) {
        description = "Run SnapRAID sync daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };

      # Weekly SnapRAID scrub timer - Runs once per week
      snapraid-scrub = lib.mkIf (config.storage.hddPool.parityDisks != [ ]) {
        description = "Run SnapRAID scrub weekly";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
      };
    };
  };

  # ===========================================================================
  # SNAPRAID CONFIGURATION
  # ===========================================================================

  environment.etc."snapraid.conf" =
    lib.mkIf (config.storage.hddPool.parityDisks != [ ]) {
      text = ''
        # SnapRAID Configuration - Auto-generated from hdd-pool.nix
        # Provides parity protection for the storage pool

        ${lib.concatStringsSep "\n" (map (disk: "parity ${disk.parityFile}")
          config.storage.hddPool.parityDisks)}

        # Content files (metadata - stored on multiple drives for redundancy)
        content /var/snapraid/snapraid.content
        ${lib.concatStringsSep "\n"
        (map (disk: "content ${disk.mountPoint}/.snapraid.content")
          config.storage.hddPool.dataDisks)}
        ${lib.concatStringsSep "\n"
        (map (disk: "content ${disk.mountPoint}/.snapraid.content")
          config.storage.hddPool.parityDisks)}

        # Data disks (order preserved from hdd-pool.nix)
        ${lib.concatStringsSep "\n"
        (map (disk: "data ${disk.snapraidName} ${disk.mountPoint}")
          config.storage.hddPool.dataDisks)}

        # Exclude patterns
        exclude *.unrecoverable
        exclude /tmp/
        exclude /lost+found/
        exclude *.!sync
        exclude .AppleDouble
        exclude ._AppleDouble
        exclude .DS_Store
        exclude ._.DS_Store
        exclude .Thumbs.db
        exclude .fseventsd
        exclude .Spotlight-V100
        exclude .TemporaryItems
        exclude .Trashes
        exclude .snapshots/

        # Block size (256KB - good balance of speed and granularity)
        block_size 256

        # Hash type for data verification
        hashsize 16

        # Auto-save state every 10GB processed
        autosave 10
      '';
    };

  # Directory structure defined in file-paths.nix

}

