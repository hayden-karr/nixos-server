# TODO: Update flake for unstable to use this version of config
{ osConfig, ... }:

let inherit (osConfig.serverConfig) user;
in {
  # Git configuration for admin user
  # To enable: uncomment the import in home.nix (line 33)
  # User details pulled from config.nix via global-config.nix
  programs.git = {
    enable = true;
    userName = user.gitName;
    userEmail = user.email;

    # Older home-manager uses extraConfig instead of settings
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      url."git@github.com:".insteadOf = "https://github.com/";
    };
  };
}
