{ inputs, ... }: {
  flake.homeModules.spicetify = { config, pkgs, lib, ... }:
  let
    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  in {
    imports = [ inputs.spicetify-nix.homeManagerModules.default ];

    programs.spicetify = {
      enable = true;

      theme = {
        name = "text";
        src = ./spicetify-text-theme;
        appendName = false;
        injectCss = true;
        replaceColors = true;
        overwriteAssets = false;
        sidebarConfig = false;
        additionalCss = ''
          /* Transparent background for compositor transparency */
          body,
          .Root,
          .Root__top-container,
          .Root__main-view,
          .Root__nav-bar,
          .Root__now-playing-bar,
          .main-view-container,
          .main-view-container__scroll-node,
          .main-view-container__scroll-node-child,
          .main-home-content,
          .os-viewport,
          .os-content {
            background: transparent !important;
            background-color: transparent !important;
          }

          /* Hide right sidebar (now playing view / related content) */
          .Root__right-sidebar,
          .Root__right-sidebar * {
            display: none !important;
            width: 0 !important;
            min-width: 0 !important;
          }

          /* Fix playback bar - remove absolute positioning and extra size */
          .Root__now-playing-bar {
            position: relative !important;
            height: auto !important;
            min-height: unset !important;
            margin: 0 !important;
            padding: 0 !important;
          }
          .main-nowPlayingBar-nowPlayingBar {
            padding: 8px !important;
            height: auto !important;
            min-height: unset !important;
          }
          .playback-bar {
            position: relative !important;
            left: unset !important;
            bottom: unset !important;
            width: 100% !important;
            margin: 0 !important;
          }

          /* Make player controls always visible (not just on hover) */
          .player-controls__buttons,
          .main-nowPlayingBar-extraControls,
          .main-nowPlayingBar-left,
          .main-nowPlayingBar-center,
          .main-nowPlayingBar-right {
            opacity: 1 !important;
          }
        '';
      };

      colorScheme = "Matugen";

      enabledExtensions = with spicePkgs.extensions; [
        adblock
        shuffle
      ];

      enabledCustomApps = with spicePkgs.apps; [
        marketplace
      ];
    };
  };
}
