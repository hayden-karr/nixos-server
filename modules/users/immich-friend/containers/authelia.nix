{ pkgs, config, ... }:

let
  inherit (config.serverConfig.network) localhost;
  waitDns = import ./wait-dns.nix { inherit pkgs; };
  waitForSecrets = import ./wait-for-secrets.nix { inherit pkgs; };

  autheliaWaitScript = waitForSecrets [
    "/run/vault/immich-friend/session-secret"
    "/run/vault/immich-friend/storage-key"
    "/run/vault/immich-friend/oidc-hmac-secret"
  ];

  # Authelia-Friend - Container definition
  # OAuth provider with FIDO2/WebAuthn for Immich Friend
  # Provides secure authentication for the friend's Immich instance
  # Secrets managed by system-level Vault Agent (see modules/vault/vault-agents.nix)
  # Config setup defined in authelia-config-setup.nix

in {
  # Authelia Friend - OAuth provider with FIDO2/WebAuthn
  services.podman.containers.authelia-friend = {
    image = "authelia/authelia:latest";
    autoStart = true;
    network = "immich-friend"; # Uses network created in immich.nix

    ports = [ "${localhost.ip}:9092:9091" ];

    volumes = [
      "/mnt/ssd/immich_friend/authelia:/config"
      "/etc/localtime:/etc/localtime:ro"
      "/run/vault/immich-friend/session-secret:/secrets/session:ro"
      "/run/vault/immich-friend/storage-key:/secrets/storage:ro"
      "/run/vault/immich-friend/oidc-hmac-secret:/secrets/oidc:ro"
    ];

    environment = {
      TZ = "America/Chicago";
      AUTHELIA_SERVER_DISABLE_HEALTHCHECK = "true";
    };

    extraPodmanArgs = [
      # Note: Security restrictions loosened - cap-drop=ALL prevents su-exec from working
      "--security-opt=no-new-privileges"
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
    ];

    # Wait for setup service and ensure secrets exist before starting
    extraConfig = {
      Unit = {
        After = [
          "authelia-friend-setup.service"
          "vault-agent-immich-friend.service"
        ];
        Wants = [
          "authelia-friend-setup.service"
          "vault-agent-immich-friend.service"
        ];
      };
      Service = { ExecStartPre = [ "${waitDns}" "${autheliaWaitScript}" ]; };
    };
  };
}
