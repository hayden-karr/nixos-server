{
  imports = [
    # PostgreSQL database
    ./database

    # Vault secrets management
    ./vault

    # Grafana, Loki, Prometheus, Alertmanager
    ./monitoring

    # SMTP relay
    ./mail

    # Rootful containers (Gitea, Vaultwarden, etc.)
    ./rootful-podman

    # K3s system requirements (kernel modules, networking, options)
    # Actual k3s service runs user-level (modules/users/immich-friend/k3s)
    ./k3s
  ];
}
