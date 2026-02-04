# Reusable secret waiter for Vault-backed containers
# Waits for all specified secrets to exist before proceeding
# This prevents containers from starting before Vault Agent has fetched secrets
#
# Usage:
#   let waitSecrets = import ./wait-for-secrets.nix { inherit pkgs; };
#   in {
#     Service.ExecStartPre = [
#       (waitSecrets [
#         "/run/vault/immich-friend/session-secret"
#         "/run/vault/immich-friend/storage-key"
#       ])
#     ];
#   }
{ pkgs }:

secretPaths:

pkgs.writeShellScript "wait-vault-secrets" ''
  set -euo pipefail
  TIMEOUT=60
  ELAPSED=0
  SECRETS=(
    ${builtins.concatStringsSep "\n    " (map (s: ''"${s}"'') secretPaths)}
  )

  while [ $ELAPSED -lt $TIMEOUT ]; do
    ALL_EXIST=true
    for secret in "''${SECRETS[@]}"; do
      if [ ! -f "$secret" ]; then
        ALL_EXIST=false
        break
      fi
    done

    if [ "$ALL_EXIST" = true ]; then
      exit 0
    fi

    sleep 1
    ELAPSED=$((ELAPSED + 1))
  done

  echo "Timeout waiting for Vault secrets:" >&2
  for secret in "''${SECRETS[@]}"; do
    if [ ! -f "$secret" ]; then
      echo "  Missing: $secret" >&2
    fi
  done
  exit 1
''
