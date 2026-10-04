{ lib, flake-parts-lib, inputs, ... }: {
  # flake-parts leaves undeclared flake outputs as `types.raw`, which refuses to
  # merge — so a second module defining `flake.lib.<name>` fails the eval with
  # "Define the value only once" (hit when Modules/Gaming/steam.nix joined
  # Modules/Shell/btop.nix in exporting a matugen template).
  #
  # Declaring it as lazyAttrsOf lets each module contribute its own key.
  options.flake = flake-parts-lib.mkSubmoduleOptions {
    lib = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = ''
        Flake-level values shared between modules: `mkHost` (below), `sshKeys`
        (Core/base.nix), and the matugen template + theme-name pairs exported by
        btop.nix, steam.nix and discord.nix, which Desktop/skwd.nix installs as
        matugen templates. Keeps each template defined once, next to the static
        fallback it must match.
      '';
    };
  };

  # Tailnet addresses other machines need to name. One definition, so a node
  # re-joining with a new IP is a one-line change (Asgard's changed once
  # already, and a stale copy in SABnzbd's host whitelist went unnoticed).
  config.flake.lib.tailnet = {
    asgard = "100.126.205.100";
  };

  # mkHost — the boilerplate every Hosts/<Host>/system.nix used to copy-paste:
  # nixosSystem, specialArgs, the Home Manager wiring, hostName and stateVersion.
  # A host file is then just "who logs in, and which modules".
  #
  # `pkgs-unstable` is instantiated ONCE here and handed to both NixOS and Home
  # Manager modules as an argument. `import nixpkgs { … }` is not memoised, so
  # base.nix and helium.nix each importing it themselves meant two full
  # nixpkgs-unstable evaluations per desktop host.
  config.flake.lib.mkHost =
    { activeUser
    , hostName
    , stateVersion
    , homeStateVersion ? stateVersion
    , modules
    }:
    let
      system = "x86_64-linux";
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs activeUser hostName pkgs-unstable; };
      modules = [
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = { inherit inputs activeUser hostName pkgs-unstable; };
          home-manager.users.${activeUser} = {
            home.username = activeUser;
            home.homeDirectory = "/home/${activeUser}";
            home.stateVersion = homeStateVersion;
          };
        }
        {
          # mkDefault: Apollo's tailnet name differs from its flake name.
          networking.hostName = lib.mkDefault hostName;
          system.stateVersion = stateVersion;
        }
      ] ++ modules;
    };
}
