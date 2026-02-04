{ pkgs, lib, config, ... }:

# Vault Agent Configuration
# Creates vault-agent instances for each container to fetch secrets from Vault
# Self-healing directory management ensures proper permissions on boot

let
  meta = import ./vault-metadata.nix config.serverConfig;
  vaultLib = import ./vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  vaultExtractDbCreds = vaultLib.mkVaultExtractDbCreds pkgs;

in {
  # Vault Agent instances for all containers (generated from metadata)
  services.vault-agent.instances = vaultLib.mkAllVaultAgents;

  # Create /run/vault directories with proper ownership (d=create, z=fix ownership)
  systemd.tmpfiles.rules = [ "d /run/vault 0750 root vault-access -" ]
    ++ (lib.concatMap (name:
      let containerConfig = meta.containers.${name};
      in [
        "d /run/vault/${name} 0750 ${containerConfig.user} ${containerConfig.group} -"
        "z /run/vault/${name} 0750 ${containerConfig.user} ${containerConfig.group} -"
      ]) (lib.attrNames meta.containers));

  # Create shared group for vault access
  users.groups.vault-access = { };

  # Add all container users to vault-access group
  users.users = lib.mkMerge (lib.mapAttrsToList
    (_name: config: { ${config.user}.extraGroups = [ "vault-access" ]; })
    meta.containers);

  # Vault Agent service configuration
  systemd.services = lib.mkMerge ([{
    systemd-tmpfiles-setup.before =
      map (name: "vault-agent-${name}.service") (lib.attrNames meta.containers);
  }] ++ (map (name: {
    "vault-agent-${name}" = {
      after = [ "vault-unseal.service" "systemd-tmpfiles-setup.service" ];
      wants = [ "vault-unseal.service" ];
      requires = [ "systemd-tmpfiles-setup.service" ];
      path = [ vaultExtractDbCreds ];

      # Only start if AppRole credentials exist and aren't placeholders
      unitConfig = {
        ConditionPathExists = [
          "/run/secrets/vault-approle-${name}-role-id"
          "/run/secrets/vault-approle-${name}-secret-id"
        ];
      };

      serviceConfig = let containerConfig = meta.containers.${name};
      in {
        ReadWritePaths = [ "/run/vault/${name}" ];

        # '+' prefix = run with elevated privileges before sandboxing
        ExecStartPre = [
          # Ensure directory exists with correct ownership (fixes boot-time race conditions)
          ("+" + (pkgs.writeShellScript "setup-vault-dir-${name}" ''
            set -euo pipefail

            # Create parent directory if needed
            ${pkgs.coreutils}/bin/mkdir -p /run/vault
            ${pkgs.coreutils}/bin/chown root:vault-access /run/vault
            ${pkgs.coreutils}/bin/chmod 0750 /run/vault

            # Create and fix ownership of container directory
            ${pkgs.coreutils}/bin/mkdir -p /run/vault/${name}
            ${pkgs.coreutils}/bin/chown ${containerConfig.user}:${containerConfig.group} /run/vault/${name}
            ${pkgs.coreutils}/bin/chmod 0750 /run/vault/${name}
          ''))

          # Check if credentials are real (not PLACEHOLDER) before starting
          (pkgs.writeShellScript "check-vault-approle-${name}" ''
            set -euo pipefail

            ROLE_ID_FILE="/run/secrets/vault-approle-${name}-role-id"
            SECRET_ID_FILE="/run/secrets/vault-approle-${name}-secret-id"

            if ${pkgs.gnugrep}/bin/grep -qi "PLACEHOLDER" "$ROLE_ID_FILE" || \
               ${pkgs.gnugrep}/bin/grep -qi "PLACEHOLDER" "$SECRET_ID_FILE"; then
              echo "AppRole credentials for ${name} are placeholders - skipping vault-agent startup"
              echo "Run 'sudo vault-setup-policies' to generate real credentials"
              exit 1
            fi
          '')
        ];
      };
    };
  }) (lib.attrNames meta.containers)));

  # Helper script for containers to extract database credentials
  environment.systemPackages = [ vaultExtractDbCreds ];
}
