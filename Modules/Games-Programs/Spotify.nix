# Modules/Games-Programs/Spotify.nix
{ config, pkgs, lib, ... }:

let
  # Pin the maintained fork (pure)
  spSrc = builtins.fetchTarball {
    url = "https://github.com/Gerg-L/spicetify-nix/archive/e13267e8f3eb1664329fcb78a43b38b985f96f6f.tar.gz";
    sha256 = "1qriwhfw7hpl2g9nmmrsd8dvs8699sz6hbflvygq2lywv4wa353g";
  };

  # Import the package set directly (exposes .themes and .extensions)
  spicePkgs = import "${spSrc}/pkgs" { inherit pkgs; };

  # Provide a flake-like `self` the module expects
  selfShim = {
    # Some code paths check `self.packages`, others `self.legacyPackages.${system}`
    packages = spicePkgs;
    legacyPackages = { ${pkgs.stdenv.system} = spicePkgs; };
  };

  # ✅ Import the NixOS module FUNCTION and pass `self` explicitly
  spNixosModule = import "${spSrc}/modules/nixos.nix" {
    inherit lib pkgs;
    self = selfShim;
  };

in
{
  # Allow Spotify if unfree isn’t global
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "spotify" ];

  # Import the module we just constructed (already closed over `self`)
  imports = [ spNixosModule ];

  programs.spicetify = {
    enable = true;

    theme = spicePkgs.themes.catppuccin;
    colorScheme = "mocha";

    enabledExtensions = with spicePkgs.extensions; [
      fullAppDisplay
      shuffle
      hidePodcasts
      adblock
      volumePercentage
      keyboardShortcut
    ];
  };
}
