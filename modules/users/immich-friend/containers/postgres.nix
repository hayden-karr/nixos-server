{ pkgs, ... }:

let
  waitDns = import ./wait-dns.nix { inherit pkgs; };
in

# PostgreSQL database for Immich Friend
# Provides isolated database in dedicated network
# Secrets managed by system-level Vault Agent (see modules/vault/vault-agents.nix)
# Network configuration in network.nix

{
  services.podman.containers = {
    # PostgreSQL - Isolated database for friend's Immich
    immich-friend-postgres = {
      image = "ghcr.io/immich-app/postgres:16-vectorchord0.3.0-pgvectors0.3.0";
      autoStart = true;
      network = "immich-friend";

      volumes = [
        "/mnt/ssd/immich_friend/postgres:/var/lib/postgresql/data"
        "/run/vault/immich-friend/db-password:/run/secrets/db_password:ro"
      ];

      environment = {
        POSTGRES_USER = "immich";
        POSTGRES_DB = "immich";
        POSTGRES_PASSWORD_FILE = "/run/secrets/db_password";
      };

      extraPodmanArgs = [
        # No additional security restrictions for PostgreSQL
        # Database containers require broader permissions for:
        # - Managing file permissions (chown, chmod)
        # - User/group management (setuid, setgid)
        # - Database file operations (direct disk I/O)
      ];

      extraConfig = {
        Unit = {
          After = [ "vault-agent-immich-friend.service" ];
          Wants = [ "vault-agent-immich-friend.service" ];
        };
        Service = {
          ExecStartPre = [
            "${waitDns}"
            "${pkgs.writeShellScript "wait-vault-db-password" ''
              set -euo pipefail
              TIMEOUT=60
              ELAPSED=0
              SECRET="/run/vault/immich-friend/db-password"

              while [ $ELAPSED -lt $TIMEOUT ]; do
                if [ -f "$SECRET" ]; then
                  exit 0
                fi
                sleep 1
                ELAPSED=$((ELAPSED + 1))
              done

              exit 1
            ''}"
          ];
        };
      };
    };
  };
}
