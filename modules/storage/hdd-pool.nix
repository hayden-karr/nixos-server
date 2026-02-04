{ lib, config, ... }: {
  # ===========================================================================
  # HDD POOL - Single Source of Truth for all HDD drives
  # ===========================================================================
  # This module defines all HDD drives in the storage pool.
  # Order matters - drives are numbered sequentially for SnapRAID.
  # All other modules (mergerfs, snapraid, btrfs-snapshots) reference this.
  # ===========================================================================

  options = {
    storage.hddPool = {
      dataDisks = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Disk name (e.g., 'hdd1', 'hdd2')";
            };
            uuid = lib.mkOption {
              type = lib.types.str;
              description = "UUID of the BTRFS filesystem";
            };
            mountPoint = lib.mkOption {
              type = lib.types.str;
              description = "Mount point path (e.g., '/mnt/hdd1')";
            };
            snapraidName = lib.mkOption {
              type = lib.types.str;
              description = "SnapRAID data disk name (e.g., 'd1', 'd2')";
            };
          };
        });
        default = [ ];
        description =
          "List of data HDDs in the pool (order matters for SnapRAID)";
      };

      parityDisks = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Parity disk name (e.g., 'parity1', 'parity2')";
            };
            uuid = lib.mkOption {
              type = lib.types.str;
              description = "UUID of the BTRFS filesystem";
            };
            mountPoint = lib.mkOption {
              type = lib.types.str;
              description = "Mount point path (e.g., '/mnt/parity1')";
            };
            parityFile = lib.mkOption {
              type = lib.types.str;
              description =
                "Path to parity file (e.g., '/mnt/parity1/snapraid.parity')";
            };
          };
        });
        default = [ ];
        description = "List of parity drives for SnapRAID";
      };
    };
  };

  config = {
    # ===========================================================================
    # HDD POOL CONFIGURATION - Add your drives here
    # ===========================================================================

    storage.hddPool = {
      # Data disks (ORDER MATTERS - this is the sequence for SnapRAID)
      dataDisks = [
        # {
        #   name = "hdd1";
        #   uuid = "YOUR-HDD1-UUID-HERE";
        #   mountPoint = "/mnt/hdd1";
        #   snapraidName = "d1";
        # }
        # Add more data drives here as you expand:
        # {
        #   name = "hdd2";
        #   uuid = "YOUR-HDD2-UUID-HERE";
        #   mountPoint = "/mnt/hdd2";
        #   snapraidName = "d2";
        # }
        # {
        #   name = "hdd3";
        #   uuid = "YOUR-HDD3-UUID-HERE";
        #   mountPoint = "/mnt/hdd3";
        #   snapraidName = "d3";
        # }
      ];

      # Parity disks (add as you grow the pool)
      parityDisks = [
        # {
        #   name = "parity1";
        #   uuid = "YOUR-PARITY1-UUID-HERE";
        #   mountPoint = "/mnt/parity1";
        #   parityFile = "/mnt/parity1/snapraid.parity";
        # }
        # Add second parity when you have 4+ data drives:
        # {
        #   name = "parity2";
        #   uuid = "YOUR-PARITY2-UUID-HERE";
        #   mountPoint = "/mnt/parity2";
        #   parityFile = "/mnt/parity2/snapraid.parity";
        # }
      ];
    };

    # ===========================================================================
    # FILESYSTEM MOUNTS - Auto-generated from pool config
    # ===========================================================================

    # Mount all data disks with BTRFS
    fileSystems = lib.mkMerge [
      # Data disks
      (lib.mkMerge (map (disk: {
        ${disk.mountPoint} = {
          device = "/dev/disk/by-uuid/${disk.uuid}";
          fsType = "btrfs";
          options = [
            "defaults"
            "compress=zstd:3"
            "noatime"
            "space_cache=v2"
            "autodefrag"
          ];
        };
      }) config.storage.hddPool.dataDisks))

      # Parity disks
      (lib.mkMerge (map (disk: {
        ${disk.mountPoint} = {
          device = "/dev/disk/by-uuid/${disk.uuid}";
          fsType = "btrfs";
          options = [ "defaults" "compress=zstd:3" "noatime" "space_cache=v2" ];
        };
      }) config.storage.hddPool.parityDisks))
    ];

    # Create .snapshots directories for all HDDs
    systemd.tmpfiles.rules =
      (map (disk: "d ${disk.mountPoint}/.snapshots 0755 root root -")
        config.storage.hddPool.dataDisks)
      ++ (map (disk: "d ${disk.mountPoint}/.snapshots 0755 root root -")
        config.storage.hddPool.parityDisks);
  };
}
