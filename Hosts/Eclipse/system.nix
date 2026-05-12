{ self, inputs, ... }:
let
  activeUser = "rock";
  hostName = "Eclipse";

  # Hardware config
  hardwareConfig = { lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ ];
    boot.extraModulePackages = [ ];
    swapDevices = [ ];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    # Pi5 bootloader (not GRUB)
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;
  };

  # Disko disk layout — targets /dev/mmcblk0 (Pi5 internal SD/eMMC)
  # nixos-anywhere will wipe and partition this automatically
  diskoConfig = { ... }: {
    disko.devices.disk.main = {
      device = "/dev/mmcblk0";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
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
  };
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      # Hardware
      hardwareConfig

      # Disko — declarative disk partitioning (used by nixos-anywhere)
      inputs.disko.nixosModules.disko
      diskoConfig

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

        # Tailscale (no sops on Pi — run `sudo tailscale up` after install)
        services.tailscale = {
          enable = true;
          openFirewall = true;
        };
        networking.firewall = {
          trustedInterfaces = [ "tailscale0" ];
          allowedUDPPorts = [ 41641 ];
        };

        # Sunshine game streaming (Pi5 uses software encoding, not vaapi)
        services.sunshine = {
          enable = true;
          autoStart = true;
          openFirewall = true;
        };
        hardware.uinput.enable = true;

        home-manager.users.${activeUser} = { lib, ... }: {
          home.activation.sunshineConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            CONF="$HOME/.config/sunshine/sunshine.conf"
            mkdir -p "$(dirname "$CONF")"
            if [ ! -s "$CONF" ]; then
              cat > "$CONF" <<'EOF'
# Pi5 uses software encoding (no VAAPI/AMD GPU)
encoder = software
hevc_mode = 1
fec_percentage = 20
EOF
            fi
          '';
        };
      }
    ];
  };
}
