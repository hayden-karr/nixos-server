let globalConfig = import ../../config.nix;
in {
  imports = [
    # Web services - Internal reverse proxy
    # Conditionally import nginx configuration based on config.nix setting:
    # - "ip-ports": HTTPS on IP:port without DNS (default)
    #   Access: https://192.168.1.100:2283, https://192.168.1.100:8222, etc.
    # - "domain-names": HTTPS on .local domains (requires Pi-hole DNS)
    #   Access: https://immich.local, https://vault.local, etc.
    #
    # Change mode in config.nix: nginx.mode = "domain-names" or "ip-ports"
    (if globalConfig.nginx.mode == "domain-names" then
      ./nginx.nix
    else
      ./nginx-ip-ports.nix)
  ];
}
