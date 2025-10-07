# Modules/Spotify.nix
{ config, pkgs, lib, inputs, ... }:

let
  sp = inputs.spicetify-nix;  # provided via extraSpecialArgs in flake
in
{
  # Pull in the spicetify Home Manager module
  imports = [ sp.homeManagerModule ];

  # Install Spotify itself
  home.packages = [ pkgs.spotify ];

  # Spicetify config
  programs.spicetify = {
    enable = true;

    # Pick a theme you like. Catppuccin is a nice default.
    # You can swap to: sp.themes.Sleek, sp.themes.Ziro, sp.themes.Comfy, etc.
    theme = sp.themes.catppuccin;
    colorScheme = "mocha"; # "latte" | "frappe" | "macchiato" | "mocha"

    enabledExtensions = with sp.extensions; [
      adblock
      autoSkipVideos
      betterGenres
      keyboardShortcut
      loopylist
      powerBar
      shuffle
      fullAppDisplay
      volumePercentage
    ];

    # These are safe defaults that work well
    injectCss = true;
    replaceColors = true;
    overwriteAssets = true;

    # Optional tweaks
    spotifyPackage = pkgs.spotify;  # explicit
  };

  # Quality of life: desktop entry for "Spicetified" Spotify stays the same,
  # so you just launch Spotify as normal.
}
