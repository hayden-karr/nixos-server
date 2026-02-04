{
  imports = [
    # Core system configuration (boot, hardware, networking, ssh, etc.)
    ./system

    # Storage infrastructure (file paths, pools, mergerfs)
    ./storage

    # Networking
    ./network

    # System-level services (database, vault, monitoring, mail, containers)
    ./system-services

    # Ingress services (VPN, nginx, cloudflared)
    ./ingress

    # Backup and snapshot services
    ./backups

    # User-level services (rootless containers)
    ./users

    # AI for local development through ollama
    ./ai
  ];
}
