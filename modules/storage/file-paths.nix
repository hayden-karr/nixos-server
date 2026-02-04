_: {
  # ===========================================================================
  # FILE PATHS - Single source of truth for all directory structures
  # ===========================================================================
  # Defines all application and service directory paths.
  # Organized by storage tier: SSD (hot) vs HDD (cold)
  #
  # Note: Dynamic tmpfiles (hdd-pool snapshots, vault runtime dirs) remain
  # in their respective modules. Ollama directories managed separately.
  # ===========================================================================

  systemd.tmpfiles.rules = [
    # =========================================================================
    # SYSTEM DIRECTORIES
    # =========================================================================

    # System logs
    "f /var/log/msmtp.log 0644 root root -"

    # WireGuard
    "d /var/lib/wireguard 0700 root root -"
    "d /var/lib/wireguard/peer-configs 0700 root root -"

    # Nginx SSL
    "d /var/lib/nginx/ssl 0755 root root -"

    # Static web pages
    "d /var/www/eddie 0755 nginx nginx -"

    # SnapRAID metadata
    "d /var/snapraid 0755 root root -"

    # =========================================================================
    # SSD - HOT STORAGE (Fast access for active data)
    # =========================================================================

    # Vault (directories owned by UID/GID 100 - vault user inside container)
    "d /mnt/ssd/vault 0755 root root -"
    "d /mnt/ssd/vault/data 0750 100 100 -"
    "d /mnt/ssd/vault/audit 0750 100 100 -"
    "d /mnt/ssd/vault/logs 0750 100 100 -"
    "d /etc/vault 0755 root root -"

    # Monitoring
    "d /mnt/ssd/monitoring 0755 grafana grafana -"
    "d /mnt/ssd/monitoring/grafana 0755 grafana grafana -"
    "d /mnt/ssd/monitoring/grafana/data 0755 grafana grafana -"
    "d /mnt/ssd/monitoring/grafana/logs 0755 grafana grafana -"
    "d /mnt/ssd/monitoring/loki 0755 loki loki -"
    "d /mnt/ssd/monitoring/loki/index 0755 loki loki -"
    "d /mnt/ssd/monitoring/loki/cache 0755 loki loki -"
    "d /mnt/ssd/monitoring/loki/chunks 0755 loki loki -"
    "d /mnt/ssd/monitoring/loki/compactor 0755 loki loki -"
    "d /mnt/ssd/monitoring/prometheus 0755 prometheus prometheus -"

    # Podman storage
    "d /mnt/ssd/podman-storage 0750 root root -"

    # PostgreSQL - All databases on SSD for performance
    "d /mnt/ssd/postgresql 0750 postgres postgres -"
    "d /mnt/ssd/postgresql/data 0750 postgres postgres -"

    # Minecraft - Active world on SSD, backups on HDD (owned by minecraft user for rootless containers)
    "d /mnt/ssd/minecraft 0750 minecraft minecraft -"
    "d /mnt/ssd/minecraft/world 0750 minecraft minecraft -"
    "d /mnt/ssd/minecraft/plugins 0750 minecraft minecraft -"
    "d /mnt/ssd/minecraft/config 0750 minecraft minecraft -"

    # Modded Minecraft (Foundation) - Active modded world on SSD (owned by minecraft user for rootless containers)
    "d /mnt/ssd/minecraft-modded 0750 minecraft minecraft -"

    # Immich - Thumbnails on SSD for fast loading, everything else on HDD
    # Rootful container with --userns=auto, :U flag handles UID mapping
    "d /mnt/ssd/immich 0755 root root -"
    "d /mnt/ssd/immich/thumbs 0755 root root -"
    "d /mnt/ssd/immich/profile 0755 root root -"
    "d /mnt/ssd/immich/upload 0755 root root -"
    "d /mnt/ssd/immich/model-cache 0755 root root -"
    "f /mnt/ssd/immich/thumbs/.immich 0644 root root -"
    "f /mnt/ssd/immich/profile/.immich 0644 root root -"
    "f /mnt/ssd/immich/upload/.immich 0644 root root -"

    # Gitea - Config on SSD for fast access
    "d /mnt/ssd/gitea 0755 root root -"

    # Forgejo - Config on SSD for fast access (alternative to Gitea)
    "d /mnt/ssd/forgejo 0755 root root -"

    # Portainer
    "d /mnt/ssd/portainer 0750 root root -"
    "d /mnt/ssd/portainer/data 0750 root root -"

    # Vaultwarden
    "d /mnt/ssd/vaultwarden 0750 root root -"
    "d /mnt/ssd/vaultwarden/data 0750 root root -"

    # Pi-hole
    "d /mnt/ssd/pihole 0755 root root -"
    "d /mnt/ssd/pihole/etc 0755 root root -"

    # n8n - Rootful container with --userns=auto
    "d /mnt/ssd/n8n 0750 root root -"
    "d /mnt/ssd/n8n/data 0750 root root -"

    # Jellyfin - Config and cache on SSD (transcoding is I/O intensive)
    "d /mnt/ssd/jellyfin 0750 root root -"
    "d /mnt/ssd/jellyfin/config 0750 root root -"
    "d /mnt/ssd/jellyfin/cache 0750 root root -"

    # Immich Friend - rootless containers owned by immich-friend user (UID 1001)
    "d /mnt/ssd/immich_friend 0755 immich-friend immich-friend -"
    "d /mnt/ssd/immich_friend/thumbs 0755 immich-friend immich-friend -"
    "d /mnt/ssd/immich_friend/profile 0755 immich-friend immich-friend -"
    "d /mnt/ssd/immich_friend/upload 0755 immich-friend immich-friend -"
    "d /mnt/ssd/immich_friend/postgres 0750 immich-friend immich-friend -"
    "d /mnt/ssd/immich_friend/authelia 0770 immich-friend immich-friend -"
    "f /mnt/ssd/immich_friend/thumbs/.immich 0644 immich-friend immich-friend -"
    "f /mnt/ssd/immich_friend/profile/.immich 0644 immich-friend immich-friend -"
    "f /mnt/ssd/immich_friend/upload/.immich 0644 immich-friend immich-friend -"
    "f /mnt/ssd/immich_friend/authelia/notification.txt 0666 immich-friend immich-friend -"
    "f /mnt/ssd/immich_friend/authelia/db.sqlite3 0666 immich-friend immich-friend -"

    # Authelia
    "d /mnt/ssd/authelia 0750 root root -"
    "d /mnt/ssd/authelia/data 0750 root root -"

    # WireGuard
    "d /var/lib/wireguard 0700 root root -"
    "d /var/lib/wireguard/peer-configs 0700 root root -"

    # Nginx SSL
    "d /var/lib/nginx/ssl 0755 root root -"

    # Static web pages
    "d /var/www/eddie 0755 nginx nginx -"

    # SnapRAID metadata
    "d /var/snapraid 0755 root root -"

    # SSD snapshots directory
    "d /mnt/ssd/.snapshots 0755 root root -"

    # linkwarden
    "d /mnt/ssd/linkwarden 0755 root root -"
    "d /mnt/ssd/linkwarden/data 0755 root root -"

    # Memos
    "d /mnt/ssd/memos 0755 root root -"

    # SSD snapshots (BTRFS snapshots for SSD)
    "d /mnt/ssd/.snapshots 0755 root root -"

    # =========================================================================
    # HDD - COLD STORAGE (Bulk storage via MergeFS pool)
    # =========================================================================

    # Vault backups on SSD
    "d /mnt/ssd/vault/backups 0750 root root -"

    # Vault backups on HDD storage pool (for long-term retention)
    "d /mnt/storage/vault 0755 root root -"
    "d /mnt/storage/vault/backups 0750 root root -"

    # MergeFS pool mount point
    "d /mnt/storage 0755 root root -"

    # Gitea - Repository data (can be large)
    "d /mnt/storage/gitea 0755 root root -"
    "d /mnt/storage/gitea/data 0755 root root -"

    # Forgejo - Repository data (alternative to Gitea)
    "d /mnt/storage/forgejo 0755 root root -"
    "d /mnt/storage/forgejo/data 0755 root root -"

    # Immich - Originals and encoded videos (bulk storage)
    # Rootful container with --userns=auto
    "d /mnt/storage/immich 0755 root root -"
    "d /mnt/storage/immich/originals 0755 root root -"
    "d /mnt/storage/immich/encoded-video 0755 root root -"
    "d /mnt/storage/immich/backups 0755 root root -"
    "f /mnt/storage/immich/originals/.immich 0644 root root -"
    "f /mnt/storage/immich/encoded-video/.immich 0644 root root -"
    "f /mnt/storage/immich/backups/.immich 0644 root root -"

    # Immich Friend originals (rootless - owned by immich-friend user)
    "d /mnt/storage/immich_friend 0755 immich-friend immich-friend -"
    "d /mnt/storage/immich_friend/originals 0755 immich-friend immich-friend -"
    "d /mnt/storage/immich_friend/encoded-video 0755 immich-friend immich-friend -"
    "d /mnt/storage/immich_friend/backups 0755 immich-friend immich-friend -"
    "f /mnt/storage/immich_friend/originals/.immich 0644 immich-friend immich-friend -"
    "f /mnt/storage/immich_friend/encoded-video/.immich 0644 immich-friend immich-friend -"
    "f /mnt/storage/immich_friend/backups/.immich 0644 immich-friend immich-friend -"

    # Jellyfin media library
    "d /mnt/storage/jellyfin 0750 root root -"
    "d /mnt/storage/jellyfin/media 0750 root root -"

    # Backups - All backup data
    "d /mnt/storage/backups 0750 root root -"
    "d /mnt/storage/backups/databases 0750 postgres postgres -"
    "d /mnt/storage/backups/minecraft 0750 minecraft minecraft -"
    "d /mnt/storage/backups/restic 0750 root root -"
    "d /mnt/storage/backups/vaultwarden 0750 root root -"
    "d /mnt/storage/backups/documents 0755 root root -"

    # Restic REST Server - Repository storage for client backups
    "d /mnt/storage/restic 0755 root root -"
    "d /mnt/storage/restic/data 0755 root root -"
  ];
}
