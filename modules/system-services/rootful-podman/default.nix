{
  imports = [
    # Podman
    ./podman.nix
    # Containers
    ./containers/vault.nix
    # Git Service - Choose ONE (both use port 3000)
    ./containers/forgejo.nix # Privacy-focused, community-driven
    # ./containers/gitea.nix # Alternative Git service
    ./containers/immich.nix
    ./containers/portainer.nix
    ./containers/vaultwarden.nix
    ./containers/pihole.nix
    ./containers/n8n.nix
    ./containers/jellyfin.nix
    ./containers/restic.nix
    ./containers/memos.nix
    ./containers/linkwarden.nix
  ];
}
