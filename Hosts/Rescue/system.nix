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

      # Reuse config modules (no bloat)
      self.nixosModules.locale
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.git
      self.nixosModules.fastfetch

      # Niri + auto-login
      {
        programs.niri.enable = true;
        services.greetd = {
          enable = true;
          settings.default_session = {
            command = "niri-session";
            user = activeUser;
          };
        };
        xdg.portal = {
          enable = true;
          extraPortals = with (import inputs.nixpkgs { system = "x86_64-linux"; }); [
            xdg-desktop-portal-gnome
            xdg-desktop-portal-gtk
          ];
          config.common.default = "gtk";
        };
      }

      # Rescue system config
      ({ pkgs, lib, ... }: {
        networking.hostName = hostName;
        system.stateVersion = "25.05";
        nixpkgs.config.allowUnfree = true;

        # Nix
        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        # Networking
        networking.networkmanager.enable = true;

        # User
        users.users.${activeUser} = {
          isNormalUser = true;
          extraGroups = [ "networkmanager" "wheel" "video" "input" ];
          password = "rescue";
          shell = pkgs.zsh;
        };
        programs.zsh.enable = true;
        programs.dconf.enable = true;
        security.sudo.wheelNeedsPassword = false;

        # Packages — lean rescue toolkit
        environment.systemPackages = with pkgs; [
          git
          vim
          btop
          home-manager
          grim
          slurp
          wl-clipboard
          gparted
          parted
          ntfs3g
          nix-output-monitor
          claude-code
        ];

        # Fonts (kitty needs this)
        fonts = {
          fontconfig.enable = true;
          packages = with pkgs; [
            nerd-fonts.fantasque-sans-mono
          ];
        };

        # ISO config
        isoImage.isoName = "nixos-rescue-rock.iso";
        isoImage.volumeID = "NIXOS_RESCUE";

        # Ventoy compatibility — squashfs is default and works great
        isoImage.squashfsCompression = "zstd -Xcompression-level 6";
      })
    ];
  };
}
