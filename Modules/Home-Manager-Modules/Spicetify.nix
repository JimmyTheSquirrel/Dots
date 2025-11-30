{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  # Spicetify packages (extensions, apps, snippets)
  spicePkgs =
    inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  # Glassify theme source
  glassifySrc = pkgs.fetchFromGitHub {
    owner = "sanoojes";
    repo = "spicetify-glassify";
    rev = "main";

    # TEMP hash – let Nix tell you the real one:
    # first use this dummy value, then copy the "got:" value from the error
    hash = "sha256-6O2ZjI87Yr9cqUcEzUXWXv1XxOmOjx0IYBfpg3rlw18=";
  };
in {
  ########################################
  # Allow Spotify (unfree)
  ########################################

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["spotify"];

  ########################################
  # Import spicetify-nix Home Manager module
  ########################################

  imports = [
    inputs.spicetify-nix.homeManagerModules.spicetify
  ];

  ########################################
  # Spicetify configuration – Glassify theme
  ########################################

  programs.spicetify = {
    enable = true;

    theme = {
      name = "Glassify";
      src = glassifySrc;

      # Glassify is a full theme with JS + CSS, so we enable all the usual flags
      injectCss = true;
      injectThemeJs = true;
      replaceColors = true;
      overwriteAssets = true;

      sidebarConfig = true;
      homeConfig = true;

      additonalCss = "";
      requiredExtensions = []; # Glassify uses a manifest, so no extra JS file to register here
    };

    # Marketplace in sidebar (optional, but handy)
    enabledCustomApps = with spicePkgs.apps; [
      marketplace
    ];

    enabledExtensions = with spicePkgs.extensions; [
      # adblock
      # shuffle
      # hidePodcasts
    ];
  };
}
