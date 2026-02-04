{ config, pkgs, lib, ... }:

let
  meta = import ../vault/vault-metadata.nix config.serverConfig;
  inherit (config.serverConfig.network) localhost server containers;
in {
  # PostgreSQL - Native NixOS service
  # Integrated with Vault for dynamic credential management
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    # Extensions
    extensions = with pkgs.postgresql_16.pkgs;
      [
        pgvector # Required for Immich AI search
      ];

    # Data directory on SSD
    dataDir = "/mnt/ssd/postgresql/data";

    # Enable TCP/IP connections
    enableTCPIP = true;

    # Listen on all interfaces (secured by authentication rules)
    settings = {
      listen_addresses = lib.mkForce "*";
      inherit (meta.postgres) port;
      max_connections = 100;
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      maintenance_work_mem = "64MB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "16MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
    };

    # Authentication - containers use scram-sha-256
    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE        USER            ADDRESS                                        METHOD
      local   all             all                                                            trust
      host    all             all             ${localhost.ip}/32                     trust
      host    all             all             ${server.lanNetwork}                   scram-sha-256
      host    all             all             ${containers.immichNetwork}            scram-sha-256
      host    all             all             ${containers.immichFriendNetwork}      scram-sha-256
      host    all             all             ${containers.dockerBridge}             scram-sha-256
      host    all             all             ${server.vpnNetwork}                   scram-sha-256
    '';

    # Databases (generated from metadata)
    ensureDatabases = meta.postgres.databases;

    # Vault admin user - manages dynamic credentials
    ensureUsers = [{
      name = meta.postgres.adminUser;
      ensureClauses = { superuser = true; };
    }];
  };

  # SOPS secret for Vault admin password
  sops.secrets.vault-postgres-admin-password = {
    owner = "postgres";
    mode = "0400";
  };

  # Set vault_admin password and enable extensions
  systemd.services.postgresql-vault-setup = {
    description = "Configure PostgreSQL for Vault integration";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };

    script = ''
      # Wait for PostgreSQL to be ready
      while ! ${pkgs.postgresql_16}/bin/pg_isready -q; do
        sleep 1
      done

      # Set vault_admin password (used by Vault to create dynamic users)
      VAULT_PASS=$(cat ${config.sops.secrets.vault-postgres-admin-password.path})
      ${pkgs.postgresql_16}/bin/psql -c "ALTER USER ${meta.postgres.adminUser} WITH PASSWORD '$VAULT_PASS';" || true

      # Enable pgvector extension for Immich
      ${pkgs.postgresql_16}/bin/psql -d immich -c "CREATE EXTENSION IF NOT EXISTS vector;" || true
      ${pkgs.postgresql_16}/bin/psql -d immich -c "CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;" || true

      # Create owner roles for Vault dynamic user inheritance
      # Vault will grant these roles to dynamically-created users
      for DB in ${lib.concatStringsSep " " meta.postgres.databases}; do
        # Create owner role
        ${pkgs.postgresql_16}/bin/psql -c "CREATE ROLE ''${DB}_owner;" || true

        # Grant database-level privileges to owner role
        ${pkgs.postgresql_16}/bin/psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB TO ''${DB}_owner;" || true

        # Grant schema-level privileges
        ${pkgs.postgresql_16}/bin/psql -d "$DB" -c "
          GRANT ALL PRIVILEGES ON SCHEMA public TO ''${DB}_owner;
          GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ''${DB}_owner;
          GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ''${DB}_owner;
          GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ''${DB}_owner;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ''${DB}_owner;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ''${DB}_owner;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO ''${DB}_owner;
        " || true
      done

      echo "PostgreSQL configured for Vault dynamic credential management"
    '';
  };

  # Open PostgreSQL port for container access
  networking.firewall.allowedTCPPorts = [ meta.postgres.port ];
}
