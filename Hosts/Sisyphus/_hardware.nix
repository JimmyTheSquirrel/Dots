# Sisyphus hardware — a plain NixOS module, imported by ./system.nix.
#
# The leading underscore is load-bearing: import-tree skips any path containing
# "/_", so this file is NOT loaded as a flake-parts module (which is what forced
# hardware config to be inlined into system.nix before, behind a no-op
# hardware.nix stub).
{ config, lib, modulesPath, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Modules/Boot/grub.nix hardcodes this root UUID for its profile entries —
  # change both together.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/ee6c7638-4daf-4f37-aa05-bd6068c113f1";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/21BA-2C3E";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/a0478bec-dbd0-4f91-8021-5a6dead6d769"; }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
