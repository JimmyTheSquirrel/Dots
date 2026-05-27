{ self, inputs, ... }:
let
  activeUser = "rock";
  hostName = "Asgard";

  # Hardware reused from Sisyphus (same physical machine).
  # When moving to a dedicated box, replace the UUIDs from `nixos-generate-config`.
  hardwareConfig = { config, lib, modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-amd" ];
    boot.extraModulePackages = [ ];

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
  };
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      hardwareConfig

      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
        home-manager.extraSpecialArgs = {
          inherit inputs activeUser hostName;
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        };
        home-manager.users.${activeUser} = {
          home.username = activeUser;
          home.homeDirectory = "/home/${activeUser}";
          home.stateVersion = "25.05";
        };
      }

      # Shared base modules (shell, git, fonts, nix settings, user setup)
      self.nixosModules.base
      self.nixosModules.grub
      self.nixosModules.locale
      self.nixosModules.sops
      self.nixosModules.zsh
      self.nixosModules.git
      self.nixosModules.starship
      self.nixosModules.fastfetch

      # The full media server stack
      self.nixosModules.server

      {
        networking.hostName = hostName;
        system.stateVersion = "25.05";

        # SSH for remote management (password auth disabled — use keys)
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = false;
        };
      }
    ];
  };
}
