{ config, ... }:

let inherit (config.serverConfig.ssh) authorizedKeys;
in {
  # SSH keys configured in config.nix via global-config.nix
  users.users.admin.openssh.authorizedKeys.keys = authorizedKeys;

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding =
        true; # Enable for SSH tunnels (kubectl, vault, argocd access)
      MaxAuthTries = 3;
      MaxSessions = 10;
    };
  };
}
