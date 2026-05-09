{ self, inputs, ... }:
let
  activeUser = "rock";
  hostName = "Eclipse";

  # Hardware config — fill in after running nixos-generate-config on the Pi
  hardwareConfig = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ ];
    boot.extraModulePackages = [ ];

    # TODO: replace with actual UUIDs from nixos-generate-config
    fileSystems."/" = {
      device = "/dev/disk/by-uuid/PLACEHOLDER";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/PLACEHOLDER";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

    swapDevices = [ ];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # Pi5 bootloader (not GRUB)
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;
  };
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      # Hardware
      hardwareConfig

      # Home Manager setup
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
        home-manager.extraSpecialArgs = {
          inherit inputs activeUser hostName;
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = "aarch64-linux";
            config.allowUnfree = true;
          };
        };
        home-manager.users.${activeUser} = {
          home.username = activeUser;
          home.homeDirectory = "/home/${activeUser}";
          home.stateVersion = "25.05";
        };
      }

      # Modules
      self.nixosModules.pi5-base
      self.nixosModules.pi5-niri
      self.nixosModules.polkit
      self.nixosModules.noctalia
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.navi

      # System-specific settings
      {
        networking.hostName = hostName;
        system.stateVersion = "25.05";
      }
    ];
  };
}
