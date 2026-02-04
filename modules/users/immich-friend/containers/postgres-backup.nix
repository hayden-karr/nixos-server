{ pkgs, ... }:

# PostgreSQL Backup for Podman Immich Friend
# Runs daily backups of the containerized postgres database
# Backups stored in /mnt/storage/immich_friend/backups (shared with k3s backups)

let
  backupScript = pkgs.writeShellScript "backup-immich-friend-postgres" ''
    set -euo pipefail

    BACKUP_DIR="/mnt/storage/immich_friend/backups"
    BACKUP_FILE="$BACKUP_DIR/immich-podman-backup-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).sql.gz"

    echo "Creating backup: $BACKUP_FILE"

    # Run pg_dump inside the container and compress
    ${pkgs.podman}/bin/podman exec immich-friend-postgres \
      pg_dump -U immich immich | ${pkgs.gzip}/bin/gzip > "$BACKUP_FILE"

    echo "Backup completed successfully"

    # Keep only last 7 days of backups
    ${pkgs.findutils}/bin/find "$BACKUP_DIR" -name "immich-podman-backup-*.sql.gz" -mtime +7 -delete
    echo "Old backups cleaned up"

    ${pkgs.coreutils}/bin/ls -lh "$BACKUP_DIR/"
  '';
in
{
  systemd.user = {
    services.backup-immich-friend-postgres = {
      Unit = {
        Description = "Backup Immich Friend PostgreSQL database (podman)";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
      };
    };

    timers.backup-immich-friend-postgres = {
      Unit = {
        Description = "Daily backup of Immich Friend PostgreSQL database";
      };

      Timer = {
        # Run at 3 AM daily (different from k3s backup at 2 AM)
        OnCalendar = "03:00";
        Persistent = true;
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
