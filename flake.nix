{
  description = "Nixos config flake";

  inputs = {
    # Pin nixpkgs once
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # Make home-manager follow *that same* nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations.Sisyphus = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ ./configuration.nix ];
      specialArgs = { inherit inputs; };
    };

    homeConfigurations.rock = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [ ./home.nix ];
    };
  };
}
