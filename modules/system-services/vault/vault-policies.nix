{ config, pkgs, lib, ... }:

# Vault Policy Management
# Manual script to create Vault policies and AppRole credentials
# SECURITY: Admin runs manually for setup/rotation, not automatic

let
  meta = import ./vault-metadata.nix config.serverConfig;
  vaultLib = import ./vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  vault = "${pkgs.vault}/bin/vault";

  # Idempotent script - safe to run multiple times (reuses existing AppRoles)
  vaultSetupScript = pkgs.writeShellScriptBin "vault-setup-policies" ''
    set -euo pipefail

    export VAULT_ADDR=${meta.vaultAddr}
    export HOME=/root

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    # Check Vault is unsealed
    if ! ${vault} status 2>&1 | ${pkgs.gnugrep}/bin/grep -q "Sealed.*false"; then
      echo -e "''${RED}ERROR: Cannot connect to Vault or Vault is sealed.''${NC}"
      echo ""
      echo "This script must be run with elevated privileges:"
      echo "  doas vault-setup-policies"
      echo ""
      echo "If vault is actually sealed, unseal it first:"
      echo "  sudo systemctl restart vault-unseal.service"
      exit 1
    fi

    VAULT_TOKEN=$(cat ${config.sops.secrets.vault-root-token.path})

    if echo "$VAULT_TOKEN" | ${pkgs.gnugrep}/bin/grep -qi "placeholder"; then
      echo -e "''${RED}ERROR: Root token is a placeholder.''${NC}"
      echo "Initialize Vault first and update secrets.yaml with the real token."
      exit 1
    fi

    export VAULT_TOKEN

    echo ""
    echo "Vault Setup: Policies & AppRoles"
    echo "─────────────────────────────────────────────────────"

    if ! ${vault} auth list | ${pkgs.gnugrep}/bin/grep -q "approle/"; then
      ${vault} auth enable approle >/dev/null 2>&1
      echo "✓ AppRole auth enabled"
    fi

    if ! ${vault} secrets list | ${pkgs.gnugrep}/bin/grep -q "secret/"; then
      ${vault} secrets enable -path=secret kv-v2 >/dev/null 2>&1
      echo "✓ KV v2 secrets enabled"
    fi

    if ! ${vault} secrets list | ${pkgs.gnugrep}/bin/grep -q "database/"; then
      ${vault} secrets enable database >/dev/null 2>&1
      echo "✓ Database secrets enabled"
    fi

    ${vault} write database/config/postgresql \
      plugin_name=postgresql-database-plugin \
      allowed_roles="${vaultLib.getAllowedDbRoles}" \
      connection_url="postgresql://{{username}}:{{password}}@${meta.postgres.host}:${
        toString meta.postgres.port
      }/postgres?sslmode=disable" \
      username="${meta.postgres.adminUser}" \
      password="$(cat ${config.sops.secrets.vault-postgres-admin-password.path})" >/dev/null 2>&1
    echo "✓ PostgreSQL configured"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: config: vaultLib.mkDatabaseRoleCmd name config vault)
      meta.containers)}
    echo "✓ Database roles configured"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: config: ''
      ${vault} policy write ${name}-policy - <<'EOF' >/dev/null 2>&1
      ${vaultLib.mkPolicy name config}
      EOF
    '') meta.containers)}
    echo "✓ Policies created"

    echo ""
    echo "AppRole Credentials (copy to secrets.yaml):"
    echo "─────────────────────────────────────────────────────"

    ${lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: config: vaultLib.mkAppRoleCmd name config vault)
      meta.containers)}

    echo "─────────────────────────────────────────────────────"
    echo ""
    echo "Next steps:"
    echo "  1. sops secrets.yaml"
    echo "  2. Paste the credentials above"
    echo "  3. sudo nixos-rebuild switch"
    echo ""
  '';

in {
  # USAGE: sudo vault-setup-policies (manual - run for setup/credential rotation)
  environment.systemPackages = [ vaultSetupScript ];

  # SOPS secrets for AppRole credentials
  sops.secrets = vaultLib.mkAllSopsSecrets // {
    vault-postgres-admin-password = {
      owner = "root";
      mode = "0400";
    };
  };
}
