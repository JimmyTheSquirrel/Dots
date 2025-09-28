{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

     home-manager = {
       url = "github:nix-community/home-manager";
       inputs.nixpkgs.follows = "nixpkgs";
     };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
      system = system;
      config.allowUnfree = true;
    };
   in {
    # use "nixos", or your hostname as the name of the configuration
    # it's a better practice than "default" shown in the video
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      modules = [
        system = "x86_64-linux";
        modules = [ ./configuration.nix ]
      ];
    };
    homeConfigurations = {
      rock = home-manager.lib.homeManagerConfiguration {
        system = system;
        modules = [ ./home.nix ];
      };

    };

  };
}
