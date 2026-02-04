_: {
  # Jellyfin - Media server for movies, TV shows, music
  # VPN-only access for privacy
  # Access: https://jellyfin.local (via WireGuard)
  #
  # FEATURES:
  # - Stream media to any device
  # - Hardware transcoding enabled (NVIDIA GPU)
  # - Subtitle support, multi-user profiles
  # - Mobile apps available

  virtualisation.oci-containers.containers.jellyfin = {
    image = "jellyfin/jellyfin:latest";
    autoStart = true;

    # Port mapping for better isolation (not host network)
    ports = [ "8096:8096" ];

    # Enable NVIDIA GPU for hardware transcoding
    extraOptions = [
      "--device=nvidia.com/gpu=all"
      "--security-opt=no-new-privileges"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--tmpfs=/config/transcodes:rw,exec"
    ];

    volumes = [
      # Configuration and metadata (SSD for fast access)
      "/mnt/ssd/jellyfin/config:/config:U"

      # Cache on SSD (transcoding is I/O intensive, don't bottleneck GPU)
      "/mnt/ssd/jellyfin/cache:/cache:U"

      # Media libraries (from HDD pool for bulk storage)
      "/mnt/storage/jellyfin/media:/media:ro" # Read-only media mount

      # Timezone
      "/etc/localtime:/etc/localtime:ro"
    ];

    environment = {
      # Server settings
      JELLYFIN_PublishedServerUrl = "https://jellyfin.local";

      # GPU settings (NVIDIA)
      NVIDIA_VISIBLE_DEVICES = "all";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    };
  };

  # Directory structure defined in file-paths.nix
  # SSD: config, cache (fast I/O for transcoding, don't bottleneck NVENC GPU)
  # HDD: media (bulk storage via /mnt/storage pool)

  # VPN-only access
  # Access: https://jellyfin.local (via nginx reverse proxy)

  # SETUP INSTRUCTIONS:
  # 1. Add your media files to /mnt/storage/jellyfin/media/
  # 2. Run: sudo nixos-rebuild switch
  # 3. Connect to VPN
  # 4. Navigate to https://jellyfin.local
  # 5. Complete initial setup wizard
  # 6. Add libraries pointing to /media/* directories
  # 7. Enable hardware transcoding:
  #    Dashboard → Playback → Transcoding
  #    - Hardware acceleration: NVIDIA NVENC
  #    - Enable hardware encoding for: All codecs
  #    - Save
  #
  # ORGANIZING MEDIA:
  # /mnt/storage/jellyfin/media/
  #   ├── movies/
  #   │   ├── Movie Name (2023)/Movie Name (2023).mkv
  #   ├── tv/
  #   │   ├── Show Name/Season 01/Show Name S01E01.mkv
  #   └── music/
  #       ├── Artist/Album/01 - Song.mp3
}
