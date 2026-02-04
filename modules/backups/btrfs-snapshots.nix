{ config, pkgs, lib, ... }:
let
  # BTRFS snapshot script
  snapshotBtrfsScript = pkgs.writeShellScript "snapshot-btrfs" ''
    set -euo pipefail

    TIMESTAMP=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)

    # Snapshot SSD
    if [ -d /mnt/ssd ]; then
      ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /mnt/ssd /mnt/ssd/.snapshots/snapshot-$TIMESTAMP
      echo "Created SSD snapshot: snapshot-$TIMESTAMP"
    fi

    # Snapshot all data HDDs from pool config
    ${lib.concatStringsSep "\n" (map (disk: ''
      if [ -d ${disk.mountPoint} ]; then
        ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r ${disk.mountPoint} ${disk.mountPoint}/.snapshots/snapshot-$TIMESTAMP
        echo "Created ${disk.name} snapshot: snapshot-$TIMESTAMP"
      fi
    '') config.storage.hddPool.dataDisks)}

    # Snapshot all parity drives
    ${lib.concatStringsSep "\n" (map (disk: ''
      if [ -d ${disk.mountPoint} ]; then
        ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r ${disk.mountPoint} ${disk.mountPoint}/.snapshots/snapshot-$TIMESTAMP
        echo "Created ${disk.name} snapshot: snapshot-$TIMESTAMP"
      fi
    '') config.storage.hddPool.parityDisks)}

    # Clean up old snapshots (keep last 30 days)
    ${pkgs.findutils}/bin/find /mnt/ssd/.snapshots -maxdepth 1 -name "snapshot-*" -mtime +30 -exec ${pkgs.btrfs-progs}/bin/btrfs subvolume delete {} \; 2>/dev/null || true

    ${lib.concatStringsSep "\n" (map (disk: ''
      ${pkgs.findutils}/bin/find ${disk.mountPoint}/.snapshots -maxdepth 1 -name "snapshot-*" -mtime +30 -exec ${pkgs.btrfs-progs}/bin/btrfs subvolume delete {} \; 2>/dev/null || true
    '')
      (config.storage.hddPool.dataDisks ++ config.storage.hddPool.parityDisks))}
  '';
in {
  # ===========================================================================
  # BTRFS SNAPSHOTS - Automated daily snapshots
  # ===========================================================================
  # Creates read-only snapshots of SSD and all HDDs in the pool.
  # References hdd-pool.nix for drive configuration.
  # ===========================================================================

  # Daily snapshot service
  systemd.services.btrfs-snapshot = {
    description = "BTRFS snapshot service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${snapshotBtrfsScript}";
    };
  };

  # Daily snapshot timer
  systemd.timers.btrfs-snapshot = {
    description = "Daily BTRFS snapshots";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
