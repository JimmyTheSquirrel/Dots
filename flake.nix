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
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    noctalia,
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
