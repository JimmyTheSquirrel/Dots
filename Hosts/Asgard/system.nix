{ self, inputs, ... }:
let
  activeUser = "rock";
  hostName = "Asgard";

  hardwareConfig = { config, lib, modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-intel" ];
    boot.extraModulePackages = [ ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Disko — declarative disk partitioning
  # NVMe (nvme0n1, 1TB): boot + root (+ /downloads for SABnzbd temp)
  # HDD (sda, 8TB): /data (media, photos, state)
  diskoConfig = {
    disko.devices = {
      disk = {
        nvme = {
          type = "disk";
          device = "/dev/nvme0n1";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "fmask=0077" "dmask=0077" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
        hdd = {
          type = "disk";
          device = "/dev/sda";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/data";
                };
              };
            };
          };
        };
      };
    };
  };
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      hardwareConfig

      # Disko — declarative disk partitioning (NVMe + HDD)
      inputs.disko.nixosModules.disko
      diskoConfig

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

        # Boot — systemd-boot (no GRUB on server, single system)
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # Allow remote deploys from Sisyphus (nix-copy-closure needs trusted-users)
        nix.settings.trusted-users = [ "rock" ];

        # SSH for remote management
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = true;
        };

        # Passwordless sudo for server management
        security.sudo.wheelNeedsPassword = false;

        # Fallback password (change with passwd after first login)
        users.users.${activeUser}.initialPassword = "asgard";

        # /downloads on NVMe for fast SABnzbd unpacking
        systemd.tmpfiles.rules = [
          "d /downloads              0775 root  media -"
          "d /downloads/usenet       0775 root  media -"
        ];
      }
    ];
  };
}
