{ inputs, ... }: {
  flake.homeModules.spicetify = { pkgs, lib, ... }:
  let
    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  in {
    imports = [ inputs.spicetify-nix.homeManagerModules.default ];

    programs.spicetify = {
      enable = true;

      theme = {
        name = "text";
        src = ./spicetify-text-theme;
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

      colorScheme = "custom";

      # Blue color scheme
      customColorScheme = {
        accent = "4a6fa5";
        accent-active = "5b8cc9";
        accent-inactive = "09090F";
        banner = "6b8cae";
        border-active = "7aa2c7";
        border-inactive = "7aa2c7";  # Same as active so borders always show
        header = "7aa2c7";
        highlight = "3d5a80";
        main = "09090F";
        notification = "7aa2c7";
        notification-error = "5c7a99";
        subtext = "7aa2c7";
        text = "a8c5db";
      };

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
