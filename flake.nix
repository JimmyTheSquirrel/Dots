{
  description = "NixOS system + Home Manager (unified)";

  # ============================================================
  # INPUTS
  # ============================================================
  inputs = {
    # --- Nixpkgs ---
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # --- Home Manager ---
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Desktop Shell ---
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell/v4.7.1";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # --- Quickshell (for skwd) ---
    quickshell = {
      url = "github:outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # --- KDE Plasma Manager ---
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # --- Star Citizen ---
    nix-citizen = {
      url = "github:LovingMelody/nix-citizen";
      inputs.nix-gaming.follows = "nix-gaming";
    };
    nix-gaming.url = "github:fufexan/nix-gaming";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    noctalia,
    plasma-manager,
    nix-citizen,
    nix-gaming,
    quickshell,
    ...
  } @ inputs: let
    system = "x86_64-linux";

    # ============================================================
    # HELPER — wraps home-manager into a nixosSystem cleanly
    # ============================================================
    mkSystem = {
      systemName,
      activeUser,
      extraModules ? [],
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs activeUser;};
        modules =
          [
            ./Machines/Systems/${systemName}/configuration.nix
            ./Machines/Users/${activeUser}/hardware-configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {inherit inputs activeUser;};
              home-manager.users.${activeUser} = import ./Machines/Systems/${systemName}/home.nix;

              # --- Shared Home Manager modules ---
              home-manager.sharedModules = [
                inputs.plasma-manager.homeModules.plasma-manager
              ];
            }
          ]
          ++ extraModules;
      };
  in {
    # ============================================================
    # SYSTEMS
    # ============================================================

    nixosConfigurations = {
      # --- Sisyphus | Hyprland ---
      "rock-Sisyphus" = mkSystem {
        systemName = "Sisyphus";
        activeUser = "rock";
      };

      # --- Elektra | KDE Plasma ---
      "rock-Elektra" = mkSystem {
        systemName = "Elektra";
        activeUser = "rock";
      };
    };
  };
}
