{
  imports =
    [ ./hardware-configuration.nix ./nvidia.nix ./nvidia-undervolt.nix ];

  services.nvidia-undervolt = { enable = true; };
}
