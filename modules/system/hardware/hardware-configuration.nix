{ config, lib, modulesPath, ... }:

# IMPORTANT: Replace UUIDs with your actual disk UUIDs
# Find UUIDs with: lsblk -f or blkid
# Use filesystem UUID, not partition UUID
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd.availableKernelModules =
      [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
    initrd.kernelModules = [ ];
    kernelModules = [ ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; # Replace with your root filesystem UUID
      fsType = "btrfs";
      options = [ "subvol=root" ];
    };

    "/home" = {
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; # Same UUID as root (different subvolume)
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

    "/nix" = {
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; # Same UUID as root (different subvolume)
      fsType = "btrfs";
      options = [ "subvol=nix" ];
    };

    "/.snapshots" = {
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; # Same UUID as root (different subvolume)
      fsType = "btrfs";
      options = [ "subvol=snapshots" ];
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/XXXX-XXXX"; # Replace with your boot partition UUID (FAT32 format)
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };
    "/mnt/ssd" = {
      # Dedicated subvolume for container fast storage (isolated from /home)
      device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; # Same UUID as root (different subvolume)
      fsType = "btrfs";
      options = [ "subvol=containers" "compress=zstd" "noatime" ];
    };
  };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp5s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp4s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
}
