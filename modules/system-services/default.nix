{
  imports = [
    # PostgreSQL database
    ./database

    # Vault secrets management
    ./vault

    # Grafana, Loki, Prometheus, Alertmanager
    ./monitoring

    # Rootful containers (Gitea, Vaultwarden, etc.)
    ./rootful-podman
  ];
}
