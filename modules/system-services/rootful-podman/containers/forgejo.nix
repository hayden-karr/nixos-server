{ pkgs, lib, config, ... }:

# Forgejo - Self-hosted Git service (community-driven Gitea fork)
# Secrets managed by Vault Agent (see modules/vault-agents.nix)
# Alternative to Gitea - use one or the other, not both

let
  vaultLib = import ../../../system-services/vault/vault-lib.nix {
    inherit lib;
    inherit (config) serverConfig;
  };
  inherit (config.serverConfig.network.server) localIp;

in {
  virtualisation.oci-containers.containers.forgejo = {
    image = "codeberg.org/forgejo/forgejo:9";
    autoStart = true;
    ports = [ "3000:3000" ];

    volumes = [
      "/mnt/ssd/forgejo:/config:U"
      "/mnt/storage/forgejo/data:/data:U"
      "/etc/localtime:/etc/localtime:ro"
      "/run/secrets/forgejo:/run/secrets:U,ro"
    ];

    extraOptions = [
      "--cap-drop=ALL"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--cap-add=CHOWN"
      "--cap-add=FOWNER"
      "--cap-add=DAC_OVERRIDE"
      "--security-opt=no-new-privileges"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--tmpfs=/run:rw,exec,nosuid"
      "--tmpfs=/var:rw,noexec,nosuid"
      # Disable s6 openssh service by mounting empty tmpfs over it
      # This prevents the container's sshd from starting and trying to bind to port 22
      "--tmpfs=/etc/s6/openssh:rw,noexec,nosuid"
      "--tmpfs=/run/s6:rw,exec,nosuid"
      "--tmpfs=/etc/ssh:rw,noexec,nosuid"
    ];

    environment = {
      USER_UID = "1000";
      USER_GID = "1000";
      # Forgejo uses Gitea-compatible environment variables
      GITEA__database__DB_TYPE = "postgres";
      GITEA__database__HOST = "${localIp}:5432";
      GITEA__database__NAME = "forgejo";
      GITEA__database__USER__FILE = "/run/secrets/db_username";
      GITEA__database__PASSWD__FILE = "/run/secrets/db_password";
      GITEA__server__DOMAIN = localIp;
      GITEA__server__ROOT_URL = "http://${localIp}:3000/";
      GITEA__server__HTTP_PORT = "3000";
      # SSH Configuration - Completely disabled
      GITEA__server__DISABLE_SSH = "true";
      GITEA__server__START_SSH_SERVER = "false";
      GITEA__server__SSH_PORT = "0"; # Disable SSH port binding
      GITEA__server__SSH_LISTEN_PORT = "0"; # Disable SSH listen port
      TZ = "America/Chicago";
    };
  };

  systemd.services."podman-forgejo" = vaultLib.mkPodmanServiceWithDbCreds {
    name = "forgejo";
    inherit pkgs;
  };
}
