{ ... }: {
  flake.nixosModules.grub = { pkgs, lib, config, ... }: let
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

    # Root filesystem UUID (from hardware config)
    rootFsUuid = "ee6c7638-4daf-4f37-aa05-bd6068c113f1";

    # Script to generate GRUB entries for named profiles
    generateProfileEntries = pkgs.writeShellScript "generate-grub-profiles" ''
      PROFILES_DIR="/nix/var/nix/profiles/system-profiles"
      OUTPUT_FILE="/boot/grub/custom-profiles.cfg"

      # Create empty file if no profiles exist yet
      echo "# Auto-generated NixOS profile entries" > "$OUTPUT_FILE"
      echo 'submenu "NixOS - System Select" {' >> "$OUTPUT_FILE"

      generate_entry() {
        local profile_name="$1"
        local display_name="$2"
        local profile_path="$PROFILES_DIR/$profile_name"

        if [ -L "$profile_path" ]; then
          # Resolve symlink to actual store path
          local real_path=$(readlink -f "$profile_path")

          # Read kernel params
          local params=""
          if [ -f "$real_path/kernel-params" ]; then
            params=$(cat "$real_path/kernel-params")
          fi

          cat >> "$OUTPUT_FILE" << ENTRY
  menuentry "$display_name" {
    search --set=nixos --fs-uuid ${rootFsUuid}
    linux (\$nixos)$real_path/kernel init=$real_path/init $params
    initrd (\$nixos)$real_path/initrd
  }
ENTRY
        fi
      }

      generate_entry "sisyphus" "Sisyphus (Niri)"
      generate_entry "elektra" "Elektra (KDE Plasma 6)"
      generate_entry "odysseus" "Odysseus (Hyprland)"

      echo '}' >> "$OUTPUT_FILE"
    '';

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

      # Include the generated profile entries
      extraConfig = ''
        if [ -f /boot/grub/custom-profiles.cfg ]; then
          source /boot/grub/custom-profiles.cfg
        fi
      '';
    };

    # Generate profile entries on system activation
    system.activationScripts.generateGrubProfiles = lib.stringAfter [ "etc" ] ''
      ${generateProfileEntries}
    '';

    environment.systemPackages = [ pkgs.os-prober ];

    boot.supportedFilesystems = [ "ntfs" ];
  };
}
