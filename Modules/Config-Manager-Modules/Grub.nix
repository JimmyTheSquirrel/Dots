{ config, pkgs, lib, ... }:

{
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    useOSProber = true;
    configurationLimit = 10;
  };

  # make sure os-prober is available when GRUB runs
  environment.systemPackages = with pkgs; [
    os-prober
  ];

  boot.supportedFilesystems = [ "ntfs" ];
}
