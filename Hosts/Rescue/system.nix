{ self, inputs, ... }:
let
  activeUser = "rock";
  hostName = "Rescue";
in {
  flake.nixosConfigurations."${activeUser}-${hostName}" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs activeUser; };
    modules = [
      # ISO base
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

      # Home Manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
        home-manager.extraSpecialArgs = {
          inherit inputs activeUser;
          hostName = hostName;
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

      # Your actual modules — keybinds, shell, browser, all work
      self.nixosModules.niri
      self.nixosModules.noctalia
      self.nixosModules.helium
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.polkit

      # Rescue-specific overrides
      ({ pkgs, lib, ... }: {
        networking.hostName = hostName;
        system.stateVersion = "25.05";
        nixpkgs.config.allowUnfree = true;
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        networking.networkmanager.enable = true;

        # Override niri module's SDDM — use greetd for auto-login instead
        services.displayManager.sddm.enable = lib.mkForce false;
        services.greetd = {
          enable = true;
          settings.default_session = {
            command = "niri-session";
            user = activeUser;
          };
        };

        # User
        users.users.${activeUser} = {
          isNormalUser = true;
          extraGroups = [ "networkmanager" "wheel" "video" "render" "input" ];
          password = "rescue";
          shell = pkgs.zsh;
        };
        programs.zsh.enable = true;
        programs.dconf.enable = true;
        security.sudo.wheelNeedsPassword = false;

        # Lean rescue toolkit
        environment.systemPackages = with pkgs; [
          vim
          btop
          home-manager
          gparted
          parted
          ntfs3g
          nix-output-monitor
          claude-code
          wl-clipboard
          grim
          slurp
        ];

        # Fonts
        fonts = {
          fontconfig.enable = true;
          packages = with pkgs; [
            nerd-fonts.fantasque-sans-mono
          ];
        };

        # ISO config
        isoImage.isoName = "nixos-rescue-rock.iso";
        isoImage.volumeID = "NIXOS_RESCUE";
        isoImage.squashfsCompression = "zstd -Xcompression-level 6";
      })
    ];
  };
}
