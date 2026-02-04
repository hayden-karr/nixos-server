{
  imports = [
    # Domain configuration (SOPS secrets)
    ./domain-secrets.nix

    # Web services - Internal reverse proxy
    # ───────────────────────────────────────────────────────────────────────
    # Both modules imported, only one activates based on config.nix:
    # - certMode = "self-signed": nginx.nix activates
    # - certMode = "letsencrypt": nginx-letsencrypt.nix activates
    #
    # Change in config.nix: ingress.certMode = "self-signed" or "letsencrypt"
    # ───────────────────────────────────────────────────────────────────────
    ./nginx.nix
    ./nginx-letsencrypt.nix

    # Public services (cloudflare tunnel)
    ./cloudflared.nix
    ./static-pages.nix
  ];
}

