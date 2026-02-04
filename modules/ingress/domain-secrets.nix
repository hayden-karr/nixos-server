# SOPS Domain Secret Declarations
# Domains are stored in SOPS for privacy (keeps your infrastructure private from git history)
# All domains are world-readable (mode 0444) so any service can read them
_:

{
  sops.secrets = {
    # Base domain (e.g., "example.com")
    "domain-base" = {
      mode = "0444";
      owner = "root";
    };

    # VPN subdomain (e.g., "vpn.example.com")
    "domain-vpn" = {
      mode = "0444";
      owner = "root";
    };

    # Immich Friend subdomain (e.g., "photos.example.com")
    "domain-immich-friend" = {
      mode = "0444";
      owner = "root";
    };

    # Authelia subdomain (e.g., "auth.example.com")
    "domain-authelia" = {
      mode = "0444";
      owner = "root";
    };

    # Admin email (e.g., "admin@example.com")
    "domain-admin-email" = {
      mode = "0444";
      owner = "root";
    };

    # Issuer domain for OAuth (e.g., "example.com")
    "domain-issuer" = {
      mode = "0444";
      owner = "root";
    };

    # Static page domains (add as needed)
    # "domain-static-page-1" = { mode = "0444"; owner = "root"; };
  };
}
