# GRUB with the CelesteGRUB theme — Elektra only.
#
# Deliberately separate from Modules/Boot/grub.nix, which is the multi-profile
# bootloader for THIS machine: it hardcodes Sisyphus's rootFsUuid and generates a
# "System Select" submenu from /nix/var/nix/profiles/system-profiles/*. Her
# machine is single-boot, so none of that applies and importing it would emit menu
# entries for profiles that do not exist on her disk.
#
# Theme: https://github.com/suilven641/CelesteGRUB (catalogued by
# jacksaur/Gorgeous-GRUB, which is an index rather than the source).
#
# Upstream ships one tarball per resolution rather than a scalable theme, so the
# 1080p build is pinned here to match her two 1920x1080 panels — read off the
# machine over SSH while it was booted from the Apollo stick. On a different
# resolution the layout is simply mispositioned, not broken; swap the file name
# and the hash below.
{ ... }: {
  flake.nixosModules.grub-celeste = { pkgs, lib, ... }: let
    celesteTheme = pkgs.stdenvNoCC.mkDerivation {
      pname = "celeste-grub-theme";
      version = "1080p-2025-07-29";

      src = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/suilven641/CelesteGRUB/7c8de0e6fa3a1f3d7ecef7bf0239dcbb033f5d02/CelesteGRUB1080p.tar.gz";
        hash = "sha256-cGRsPyljXCZReNi62u+XozmFvBwliZNBpag8ri58ajI=";
      };

      # Pinned to a commit rather than a branch: this repo is a handful of release
      # tarballs with no tags, so `main` moving would silently change the theme and
      # break the hash on the next `nix flake update`-adjacent rebuild.

      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        # unpackPhase already cd'd into the tarball's single top-level directory
        # (sourceRoot = CelesteGRUB1080p), so copy the CONTENTS of cwd, not a
        # directory of that name — `cp -r CelesteGRUB1080p` fails with
        # "No such file or directory" from inside it.
        mkdir -p $out/share/grub/themes/CelesteGRUB
        cp -r . $out/share/grub/themes/CelesteGRUB/
        runHook postInstall
      '';

      meta = {
        description = "Celeste-themed GRUB background and menu";
        homepage = "https://github.com/suilven641/CelesteGRUB";
        license = lib.licenses.gpl3Only;
      };
    };
  in {
    boot.loader = {
      # Nothing else on Elektra enables systemd-boot today; this is a guard so
      # that a module which does can never leave two bootloaders claiming the ESP.
      systemd-boot.enable = lib.mkForce false;

      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot";

      grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
        configurationLimit = 10;

        # Off. Her only disk is wiped and repartitioned by disko, so there is no
        # other OS on it to find — the one thing os-prober WOULD find is the
        # Apollo stick or any other drive left plugged in during a rebuild,
        # baking a boot entry for it into her menu that dangles once it is
        # removed. (That also makes the module's old `environment.systemPackages
        # = [ pkgs.os-prober ]` moot; it was never needed anyway, since nixpkgs
        # puts os-prober on install-grub's own PATH when this option is on.)
        useOSProber = false;

        theme = "${celesteTheme}/share/grub/themes/CelesteGRUB";

        # The theme is drawn at a fixed 1080p. Without pinning the mode GRUB often
        # picks whatever EFI hands it (commonly 800x600 or 1024x768) and the
        # background is cropped or letterboxed with the menu off-centre.
        #
        # EFI only: there is no gfxmodeBios because there is no BIOS GRUB here
        # (device = "nodev" installs the EFI image alone), and install-grub.pl
        # only reads the BIOS mode when GRUB runs on a non-EFI platform.
        gfxmodeEfi = "1920x1080";
      };
    };
  };
}
