{ pkgs, ... }:

{
  # udev rules for FIDO2 devices
  services.udev.packages = [ pkgs.libfido2 ];

  # Add admin to plugdev group
  users.users.admin.extraGroups = [ "plugdev" ];
}
