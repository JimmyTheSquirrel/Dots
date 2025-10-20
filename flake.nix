{
  description = "NixOS system + separate Home Manager (per-user structure)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
  let
    system = "x86_64-linux";
  in
  {
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
        config.allowUnfree = true;
      };

      modules = [ ./Users/Sisyphus/home.nix ];

      # Make flake inputs available inside HM modules if needed
      extraSpecialArgs = { inherit inputs; };
    };
  };
}
