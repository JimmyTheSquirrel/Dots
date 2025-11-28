{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  # Spicetify packages (extensions, apps, snippets)
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
in {
  ########################################
  # Install Spotify + allow unfree
  ########################################

  # Required for Spotify
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["spotify"];

  # Install Spotify itself (Home Manager will put it in your PATH)
  home.packages = [
    pkgs.spotify
  ];

  ########################################
  # Import spicetify-nix Home Manager module
  ########################################

  imports = [
    inputs.spicetify-nix.homeManagerModules.spicetify
  ];

  ########################################
  # Spicetify configuration – Hazy theme
  ########################################

  programs.spicetify = {
    enable = true;

    theme = {
      name = "Hazy";

      src = pkgs.fetchFromGitHub {
        owner = "Astromations";
        repo = "Hazy";

        # Get commit:
        #   git ls-remote https://github.com/Astromations/Hazy main
        rev = "<COMMIT-HASH-HERE>";

        # First build with fake hash, Nix prints the real one:
        #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        hash = "<SHA256-HERE>";
      };

      # Required for Hazy according to README:
      injectCss = true;
      injectThemeJs = true;
      replaceColors = true;
      overwriteAssets = true;

      # Nice defaults from spicetify-nix ecosystem:
      sidebarConfig = true;
      homeConfig = true;

      additonalCss = "";
    };

    # Optional: extensions you may want
    enabledExtensions = with spicePkgs.extensions; [
      # fullAppDisplay
      # adblock
      # shuffle
      # hidePodcasts
    ];

    # Optional additional apps/snippets:
    # enabledCustomApps = with spicePkgs.apps; [ newReleases ];
    # enabledSnippets   = with spicePkgs.snippets; [ rotatingCoverart ];
  };
}
