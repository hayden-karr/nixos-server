{ pkgs, ... }:
let
  # Database backup script
  backupDatabasesScript = pkgs.writeShellScript "backup-databases" ''
    set -euo pipefail

    BACKUP_DIR="/mnt/storage/backups/databases"
    TIMESTAMP=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)

    echo "Starting database backups at $TIMESTAMP"

    # Backup all PostgreSQL databases
    for DB in postgres gitea immich vaultwarden n8n; do
      echo "Backing up database: $DB"
      ${pkgs.doas}/bin/doas -u postgres ${pkgs.postgresql}/bin/pg_dump $DB | ${pkgs.gzip}/bin/gzip > "$BACKUP_DIR/$DB-$TIMESTAMP.sql.gz"
    done

    # Clean up old backups (keep last 30 days)
    ${pkgs.findutils}/bin/find "$BACKUP_DIR" -name "*.sql.gz" -mtime +30 -delete

    echo "Database backups complete"
  '';

  # Minecraft BTRFS snapshot script
  backupMinecraftScript = pkgs.writeShellScript "backup-minecraft-btrfs" ''
    set -euo pipefail

    WORLD_DIR="/mnt/ssd/minecraft/world"
    SNAPSHOT_DIR="/mnt/storage/backups/minecraft/world-snapshots"
    TIMESTAMP=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)

    echo "Starting Minecraft BTRFS snapshot at $TIMESTAMP"

    # Create snapshot directory if it doesn't exist (owned by minecraft user)
    ${pkgs.coreutils}/bin/mkdir -p "$SNAPSHOT_DIR"
    ${pkgs.coreutils}/bin/chown -R minecraft:minecraft "$SNAPSHOT_DIR"

    # Create read-only BTRFS snapshot of the world directory
    # Note: This is a subvolume snapshot, not a directory snapshot
    # If minecraft/world is not a subvolume, this will fail
    # In that case, we snapshot the parent /mnt/ssd and reference the world path
    if ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$WORLD_DIR" &>/dev/null; then
      # world is a subvolume, snapshot it directly
      ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r "$WORLD_DIR" "$SNAPSHOT_DIR/world-$TIMESTAMP"
    else
      # world is a directory, create a writable snapshot and copy (fallback)
      # Better approach: make world a subvolume first with:
      # btrfs subvolume create /mnt/ssd/minecraft/world
      echo "Warning: $WORLD_DIR is not a BTRFS subvolume"
      echo "Creating directory-based backup instead"
      ${pkgs.coreutils}/bin/mkdir -p "$SNAPSHOT_DIR/world-$TIMESTAMP"
      ${pkgs.rsync}/bin/rsync -a --delete "$WORLD_DIR/" "$SNAPSHOT_DIR/world-$TIMESTAMP/"
    fi

    # Ensure new backup is owned by minecraft user
    ${pkgs.coreutils}/bin/chown -R minecraft:minecraft "$SNAPSHOT_DIR/world-$TIMESTAMP"

    # Keep only the 5 most recent backups
    # List all world-* directories, sort by modification time (newest first), skip first 5, delete the rest
    ${pkgs.findutils}/bin/find "$SNAPSHOT_DIR" -maxdepth 1 -name "world-*" -type d -printf '%T@ %p\n' | \
      ${pkgs.coreutils}/bin/sort -rn | \
      ${pkgs.coreutils}/bin/tail -n +6 | \
      ${pkgs.coreutils}/bin/cut -d' ' -f2- | \
      while read -r old_backup; do
        # Try to delete as BTRFS subvolume first, fall back to rm if not a subvolume
        ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "$old_backup" 2>/dev/null || ${pkgs.coreutils}/bin/rm -rf "$old_backup"
        echo "Deleted old backup: $old_backup"
      done

    echo "Minecraft snapshot complete: world-$TIMESTAMP"
  '';

in {
  # ===========================================================================
  # DATABASE BACKUPS - Automated every 12 hours
  # ===========================================================================

  # Database backup service
  systemd = {
    services.backup-databases = {
      description = "PostgreSQL database backup service";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupDatabasesScript}";
      };
      after = [ "postgresql.service" ];
    };

    # Database backup every 12 hours
    timers.backup-databases = {
      description = "Database backups every 12 hours";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00,12:00:00"; # Every day at midnight and noon
        Persistent = true;
      };
    };

    # ===========================================================================
    # MINECRAFT WORLD BACKUPS - Using BTRFS snapshots (minimal disk wear)
    # ===========================================================================
    # Note: Minecraft world is on /mnt/ssd which is already snapshotted by btrfs-snapshots.nix
    # This provides additional Minecraft-specific snapshots with custom retention
    # BTRFS snapshots are CoW (copy-on-write) so they only store diffs - minimal disk usage
    # For off-server backups, consider restic or enable tar.gz backup below

    # Minecraft backup service
    services.backup-minecraft = {
      description = "Minecraft world BTRFS snapshot service";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupMinecraftScript}";
      };
    };

    # Minecraft backup once daily (optimal for HDD wear)
    timers.backup-minecraft = {
      description = "Minecraft world snapshots daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily"; # Once per day at midnight
        Persistent = true;
      };
    };
  };
  # ===========================================================================
  # OPTIONAL: Minecraft tar.gz backup for off-server storage
  # ===========================================================================
  # Uncomment below if you want traditional tar.gz backups in addition to BTRFS snapshots
  # Useful for copying backups off-server (e.g., to cloud storage)

  # environment.etc."backup-minecraft-tar.sh" = {
  #   text = ''
  #     #!/usr/bin/env bash
  #     set -euo pipefail
  #     WORLD_DIR="/mnt/ssd/minecraft/world"
  #     BACKUP_DIR="/mnt/storage/backups/minecraft"
  #     TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  #     echo "Starting Minecraft tar.gz backup at $TIMESTAMP"
  #     ${pkgs.gnutar}/bin/tar -czf "$BACKUP_DIR/world-$TIMESTAMP.tar.gz" -C /mnt/ssd/minecraft world
  #     find "$BACKUP_DIR" -name "world-*.tar.gz" -mtime +30 -delete
  #     echo "Minecraft tar.gz backup complete: world-$TIMESTAMP.tar.gz"
  #   '';
  #   mode = "0755";
  # };
  #
  # systemd.services.backup-minecraft-tar = {
  #   description = "Minecraft world tar.gz backup for off-server storage";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "/etc/backup-minecraft-tar.sh";
  #   };
  # };
  #
  # systemd.timers.backup-minecraft-tar = {
  #   description = "Minecraft tar.gz backups weekly";
  #   wantedBy = [ "timers.target" ];
  #   timerConfig = {
  #     OnCalendar = "Sun 03:00:00"; # Weekly on Sundays at 3 AM
  #     Persistent = true;
  #   };
  # };
}
