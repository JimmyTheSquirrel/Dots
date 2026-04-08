{
  config,
  pkgs,
  lib,
  ...
}: let
  yorha-grub-theme = pkgs.stdenvNoCC.mkDerivation {
    name = "yorha-grub-theme";
    src = pkgs.fetchFromGitHub {
      owner = "OliveThePuffin";
      repo = "yorha-grub-theme";
      rev = "refs/heads/master";
      sha256 = "sha256-XVzYDwJM7Q9DvdF4ZOqayjiYpasUeMhAWWcXtnhJ0WQ=";
    };
    installPhase = ''
      mkdir -p $out
      cp -r yorha-1920x1080/* $out/
    '';
  };
in {
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
    theme = yorha-grub-theme;
  };

  environment.systemPackages = with pkgs; [
    os-prober
  ];

  boot.supportedFilesystems = ["ntfs"];
}
