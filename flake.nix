{
  description = "NixOS system + separate Home Manager (per-user structure)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NEW: spicetify-nix for Spotify theming
    spicetify-nix.url = "github:Gerg-L/spicetify-nix";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    spicetify-nix,
    ...
  } @ inputs: let
    system = "x86_64-linux";
  in {
    ########################################
    # 🖥️ System configuration (no HM here)
    ########################################
    nixosConfigurations.Sisyphus = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./Users/Sisyphus/configuration.nix
        ./Users/Sisyphus/hardware-configuration.nix
      ];
    };

    ########################################
    # 🏠 Home Manager configuration (same key)
    ########################################
    homeConfigurations.Sisyphus = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        inherit system;
        # You already had this – keep it for Spotify (unfree)
        config.allowUnfree = true;
      };

      # Your main HM config + the Spicetify/Hazy module
      modules = [
        ./Users/Sisyphus/home.nix
        ./Users/Sisyphus/spicetify.nix
      ];

      # Make flake inputs (incl. spicetify-nix) available inside HM modules
      extraSpecialArgs = {inherit inputs;};
    };
  };
}
