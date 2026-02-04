{ pkgs, config, ... }:

{
  # Admin user with full system privileges
  # Real login user (unlike immich-friend/minecraft which are system users)
  # SSH keys: modules/system/ssh.nix
  # FIDO2: modules/system/fido2.nix

  # Used to set the password declaratively and will populate from secrets on rebuild
  users.mutableUsers = false;

  users.users.admin = {
    isNormalUser = true;
    description = "System Administrator";
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."user-password".path;
    shell = pkgs.bash;
  };
}
