{ lib, serverConfig }:

# Vault Helper Library
# Pure functions for generating Vault configs from metadata
# All functions are metadata-driven from vault-metadata.nix

let
  inherit (lib) concatMapStringsSep concatStringsSep mapAttrsToList attrNames;

  meta = import ./vault-metadata.nix serverConfig;

in rec {
  # Generate Vault HCL policy for a container
  mkPolicy = name: config: ''
    # ${name} container policy
    ${lib.optionalString (config.dynamicDb != null) ''
      # Dynamic database credentials (auto-rotated every ${config.dynamicDb.ttl})
      path "database/creds/${name}-role" {
        capabilities = ["read"]
      }
    ''}
    ${concatMapStringsSep "\n" (secret: ''
      # ${secret.path}
      path "secret/data/${secret.path}" {
        capabilities = ["read", "list"]
      }
    '') config.kvSecrets}
    ${lib.optionalString
    (config.kvSecrets != [ ] || config.dynamicDb != null) ''
      # List available secrets
      path "secret/metadata/${name}/*" {
        capabilities = ["list"]
      }
    ''}
  '';

  # Generate Vault CLI commands to create AppRole (outputs to console for secrets.yaml)
  mkAppRoleCmd = name: _config: vault: ''
    # Create AppRole for ${name}
    ${vault} write auth/approle/role/${name} \
      token_ttl=${meta.approle.tokenTtl} \
      token_max_ttl=${meta.approle.tokenMaxTtl} \
      policies="${name}-policy" \
      secret_id_bound_cidrs="${meta.approle.secretIdBoundCidrs}" \
      token_bound_cidrs="${meta.approle.tokenBoundCidrs}" >/dev/null 2>&1

    ROLE_ID=$(${vault} read -field=role_id auth/approle/role/${name}/role-id 2>/dev/null)
    SECRET_ID=$(${vault} write -field=secret_id -f auth/approle/role/${name}/secret-id 2>/dev/null)

    printf "  %-40s %s\n" "vault-approle-${name}-role-id:" "$ROLE_ID"
    printf "  %-40s %s\n" "vault-approle-${name}-secret-id:" "$SECRET_ID"
    echo ""
  '';

  # Generate database role creation command (assumes ${database}_owner role exists)
  mkDatabaseRoleCmd = name: config: vault:
    lib.optionalString (config.dynamicDb != null) ''
      ${vault} write database/roles/${name}-role \
        db_name=postgresql \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ${config.dynamicDb.database}_owner TO \"{{name}}\";" \
        revocation_statements="REASSIGN OWNED BY \"{{name}}\" TO ${config.dynamicDb.database}_owner; DROP OWNED BY \"{{name}}\"; DROP ROLE IF EXISTS \"{{name}}\";" \
        default_ttl="${config.dynamicDb.ttl}" \
        max_ttl="${config.dynamicDb.maxTtl}" || true
    '';

  # Generate Vault Agent template for database credentials
  mkDbCredTemplate = name: config:
    lib.optionalString (config.dynamicDb != null) {
      destination = "/run/vault/${name}/db-creds";
      perms = "0600";
      contents = ''
        {{- with secret "database/creds/${name}-role" -}}
        USERNAME={{ .Data.username }}
        PASSWORD={{ .Data.password }}
        {{- end -}}
      '';
    };

  # Generate Vault Agent template for KV secret (0640 for shared groups, 0600 otherwise)
  mkKvSecretTemplate = name: secret:
    let
      config = meta.containers.${name};
      isGroupShared = config.group != "root" && config.group != config.user;
    in {
      destination = "/run/vault/${name}/${
          secret.fileName or (lib.replaceStrings [ "/" ] [ "-" ] secret.path)
        }";
      perms = if isGroupShared then "0640" else "0600";
      contents = ''
        {{- with secret "secret/data/${secret.path}" -}}
        ${if (secret.envVar or null) != null then
          "${secret.envVar}={{ .Data.data.${secret.field} }}"
        else
          "{{ .Data.data.${secret.field} }}"}
        {{- end -}}
      '';
    };

  # Generate combined environment file (DATABASE_URL + all env secrets)
  mkCombinedEnvTemplate = name: config:
    lib.optionalString (config.outputFormat == "combined") {
      destination = "/run/vault/${name}/env";
      perms = "0600";
      contents = ''
        ${lib.optionalString (config.dynamicDb != null) ''
          {{- with secret "database/creds/${name}-role" -}}
          DATABASE_URL=postgresql://{{ .Data.username }}:{{ .Data.password }}@${meta.postgres.host}:${
            toString meta.postgres.port
          }/${config.dynamicDb.database}
          DB_USERNAME={{ .Data.username }}
          DB_PASSWORD={{ .Data.password }}
          {{- end -}}
        ''}
        ${concatMapStringsSep "\n" (secret: ''
          {{- with secret "secret/data/${secret.path}" -}}
          ${
            secret.envVar or (lib.toUpper
              (lib.replaceStrings [ "/" ] [ "_" ] secret.path))
          }={{ .Data.data.${secret.field} }}
          {{- end -}}
        '') (lib.filter (s: (s.envVar or null) != null) config.kvSecrets)}
      '';
    };

  # Generate DATABASE_URL file (for apps using DATABASE_URL_FILE)
  mkDatabaseUrlFileTemplate = name: config:
    if (config.useDatabaseUrlFile or false) then {
      destination = "/run/vault/${name}/database-url";
      perms = "0600";
      contents = ''
        {{- with secret "database/creds/${name}-role" -}}
        postgresql://{{ .Data.username }}:{{ .Data.password }}@${meta.postgres.host}:${
          toString meta.postgres.port
        }/${config.dynamicDb.database}
        {{- end -}}
      '';
    } else
      null;

  # Generate all templates for a container's Vault Agent
  mkAgentTemplates = name: config:
    lib.filter (t: t != null) ([
      (if config.outputFormat == "combined" then
        mkCombinedEnvTemplate name config
      else
        null)
      (mkDatabaseUrlFileTemplate name config)
      (if config.outputFormat == "separate" && config.dynamicDb != null then
        mkDbCredTemplate name config
      else
        null)
    ] ++ (if config.outputFormat == "separate" then
      map (secret: mkKvSecretTemplate name secret) config.kvSecrets
    else
      map (secret: mkKvSecretTemplate name secret)
      (lib.filter (s: (s.envVar or null) == null) config.kvSecrets)));

  # Generate Vault Agent configuration for a container
  mkVaultAgent = name: config: {
    enable = true;
    inherit (config) user;
    inherit (config) group;

    settings = {
      vault.address = meta.vaultAddr;

      auto_auth = {
        method = [{
          type = "approle";
          config = {
            role_id_file_path = "/run/secrets/vault-approle-${name}-role-id";
            secret_id_file_path =
              "/run/secrets/vault-approle-${name}-secret-id";
            remove_secret_id_file_after_reading = false;
          };
        }];

        sink = [{
          type = "file";
          config = { path = "/run/vault/${name}/.vault-token"; };
        }];
      };

      template = mkAgentTemplates name config;
    };
  };

  # Generate SOPS secret declarations for a container's AppRole credentials
  mkSopsSecrets = name: config: {
    "vault-approle-${name}-role-id" = {
      owner = config.user;
      inherit (config) group;
      mode = "0400";
    };
    "vault-approle-${name}-secret-id" = {
      owner = config.user;
      inherit (config) group;
      mode = "0400";
    };
  };

  # Generate all SOPS secrets for all containers
  mkAllSopsSecrets = lib.mkMerge
    (mapAttrsToList (name: config: mkSopsSecrets name config) meta.containers);

  # Generate all Vault Agent instances
  mkAllVaultAgents =
    lib.mapAttrs (name: config: mkVaultAgent name config) meta.containers;

  # List of database role names for PostgreSQL connection config
  getAllowedDbRoles = concatStringsSep "," (map (name: "${name}-role")
    (lib.filter (name: meta.containers.${name}.dynamicDb != null)
      (attrNames meta.containers)));

  # Convert container names to SOPS output format (uppercase with underscores)
  mkSopsOutput = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);

  # Filter containers by capability
  getContainersWithDb =
    lib.filter (name: meta.containers.${name}.dynamicDb != null)
    (attrNames meta.containers);
  getContainersWithKv =
    lib.filter (name: meta.containers.${name}.kvSecrets != [ ])
    (attrNames meta.containers);

  # Script to extract database credentials (usage: vault-extract-db-creds <container> <output-dir>)
  mkVaultExtractDbCreds = pkgs:
    pkgs.writeShellScriptBin "vault-extract-db-creds" ''
      set -euo pipefail

      CONTAINER=$1
      OUTPUT_DIR=$2

      mkdir -p "$OUTPUT_DIR"

      if [ ! -f "/run/vault/$CONTAINER/db-creds" ]; then
        echo "ERROR: Vault credentials not found for $CONTAINER at /run/vault/$CONTAINER/db-creds"
        exit 1
      fi

      source "/run/vault/$CONTAINER/db-creds"
      echo "$USERNAME" > "$OUTPUT_DIR/db_username"
      echo "$PASSWORD" > "$OUTPUT_DIR/db_password"
      chmod 400 "$OUTPUT_DIR"/*
    '';

  # Generate systemd service configuration for Podman containers with Vault database credentials
  # Usage: mkPodmanServiceWithDbCreds { name, pkgs, additionalSecretSetup ? "" }
  # - Always extracts database credentials
  # - Optionally runs additional secret extraction (e.g., encryption keys, auth tokens)
  mkPodmanServiceWithDbCreds = { name, pkgs, additionalSecretSetup ? "" }:
    let vaultExtractDbCreds = mkVaultExtractDbCreds pkgs;
    in {
      after = [
        "postgresql.service"
        "postgresql-vault-setup.service"
        "vault-agent-${name}.service"
      ];
      requires = [ "postgresql.service" "vault-agent-${name}.service" ];

      serviceConfig = {
        RestartSec = "5s";
        ExecStartPre = pkgs.writeShellScript "${name}-secrets-setup" ''
          set -euo pipefail
          mkdir -p /run/secrets/${name}
          # Extract database credentials
          ${vaultExtractDbCreds}/bin/vault-extract-db-creds ${name} /run/secrets/${name}
          ${additionalSecretSetup}
          echo "✓ Secrets ready for ${name}"
        '';
      };
    };
}
