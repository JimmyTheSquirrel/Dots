{
  description = "NixOS system + separate Home Manager (per-user structure)";

  inputs = {
    # System + HM stay on stable 25.05
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # Unstable only for Noctalia (Quickshell freshness)
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager release matching 25.05, follows stable nixpkgs
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix.url = "github:Gerg-L/spicetify-nix";

    # Noctalia follows unstable nixpkgs internally
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
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
  in {
    nixosConfigurations.Sisyphus = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./Users/Sisyphus/configuration.nix
        ./Users/Sisyphus/hardware-configuration.nix
      ];
    };

    homeConfigurations.Sisyphus = home-manager.lib.homeManagerConfiguration {
      # ✅ HM packages back to stable (fixes rofi-wayland merge issues)
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      modules = [
        ./Users/Sisyphus/home.nix
      ];

      extraSpecialArgs = {inherit inputs;};
    };
  };
}
