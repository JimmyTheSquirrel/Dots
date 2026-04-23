{ self, inputs, ... }:
let
  anuratiFont = "${self}/Resources/Fonts/Anurati-Regular.otf";
in {
  flake.nixosModules.noctalia = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = {
      home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.wrappedNoctalia
        self.packages.${pkgs.stdenv.hostPlatform.system}.anurati-font
        pkgs.playerctl
        pkgs.google-fonts
        pkgs.jq
      ];

      # Declaratively ensure desktop widgets and plugins are configured
      # This patches config files on each activation since outOfStoreConfig
      # means noctalia ignores the Nix-generated widget config
      home.activation.noctaliaDesktopWidgets = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        CONFIG_DIR="$HOME/.config/noctalia"
        SETTINGS_FILE="$CONFIG_DIR/settings.json"
        PLUGINS_FILE="$CONFIG_DIR/plugins.json"
        PLUGIN_DIR="$CONFIG_DIR/plugins/desktop-clock"

        # Create config directory if it doesn't exist
        mkdir -p "$CONFIG_DIR/plugins"

        # Create default settings.json if it doesn't exist
        if [ ! -f "$SETTINGS_FILE" ]; then
          echo '{"desktopWidgets":{"enabled":true}}' > "$SETTINGS_FILE"
        fi

        # Create default plugins.json if it doesn't exist
        if [ ! -f "$PLUGINS_FILE" ]; then
          echo '{"version":2,"sources":[],"states":{}}' > "$PLUGINS_FILE"
        fi

        # Patch settings.json to add desktop clock widgets
        ${pkgs.jq}/bin/jq '.desktopWidgets.monitorWidgets = [
          {"name": "DP-2", "widgets": [{"id": "plugin:desktop-clock", "showBackground": false}]},
          {"name": "HDMI-A-1", "widgets": [{"id": "plugin:desktop-clock", "showBackground": false}]}
        ]' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

        # Patch plugins.json to enable the desktop-clock plugin
        ${pkgs.jq}/bin/jq '.states["desktop-clock"] = {"enabled": true}' "$PLUGINS_FILE" > "$PLUGINS_FILE.tmp" && mv "$PLUGINS_FILE.tmp" "$PLUGINS_FILE"

        # Sync desktop-clock plugin files from nix store to user config
        mkdir -p "$PLUGIN_DIR"
        cp -f ${anuratiFont} "$PLUGIN_DIR/Anurati-Regular.otf"
        cp -f ${self}/Resources/Noctalia-Plugins/desktop-clock/DesktopWidget.qml "$PLUGIN_DIR/DesktopWidget.qml"
        cp -f ${self}/Resources/Noctalia-Plugins/desktop-clock/manifest.json "$PLUGIN_DIR/manifest.json"
      '';
    };
  };

  perSystem = { pkgs, system, ... }: {
    # Anurati font - futuristic geometric display font by Emmeran Richard
    packages.anurati-font = pkgs.stdenvNoCC.mkDerivation {
      pname = "anurati-font";
      version = "1.0";
      dontUnpack = true;
      src = anuratiFont;

      installPhase = ''
        mkdir -p $out/share/fonts/opentype
        cp $src $out/share/fonts/opentype/Anurati-Regular.otf
      '';

      meta = {
        description = "Anurati - futuristic geometric display font";
        license = pkgs.lib.licenses.ofl;  # Free for personal use
      };
    };
    packages.wrappedNoctalia = inputs.wrapper-modules.wrappers.noctalia-shell.wrap {
      inherit pkgs;
      package = inputs.noctalia.packages.${system}.default;

      # Use out-of-store config so matugen can write colors.json
      outOfStoreConfig = "/home/rock/.config/noctalia";

      # Desktop clock plugin
      preInstalledPlugins.desktop-clock = {
        enabled = true;
        src = "${self}/Resources/Noctalia-Plugins/desktop-clock";
      };

      settings = {
        bar = {
          position = "top";
          density = "default";
          showCapsule = true;
          capsuleOpacity = 1;
          backgroundOpacity = 0.7;
          useSeparateOpacity = true;
          showOutline = false;
          frameThickness = 12;
          frameRadius = 16;
          marginVertical = 8;
          marginHorizontal = 8;
          outerCorners = true;
          floating = false;

          widgets = {
            left = [
              { id = "ControlCenter"; useDistroLogo = false; }
              { id = "Workspace"; hideUnoccupied = true; labelMode = "name"; characterCount = 1; emptyColor = "primary"; focusedColor = "secondary"; occupiedColor = "primary"; }
            ];
            center = [
              { id = "MediaMini"; hideMode = "hidden"; showAlbumArt = true; showArtistFirst = true; showVisualizer = true; visualizerType = "linear"; maxWidth = 500; useFixedWidth = false; showProgressRing = true; scrollingMode = "hover"; }
            ];
            right = [
              { id = "Volume"; displayMode = "onhover"; }
              { id = "Network"; displayMode = "onhover"; icon = "plug-connected"; }
              { id = "Bluetooth"; displayMode = "onhover"; }
              { id = "Clock"; formatHorizontal = "hh:mm a"; formatVertical = "hh mm a"; usePrimaryColor = true; }
              { id = "NotificationHistory"; }
              { id = "Tray"; displayMode = "onhover"; }
            ];
          };

          screenOverrides = [
            {
              enabled = true;
              name = "HDMI-A-1";
              widgets = {
                left = [ { id = "ControlCenter"; useDistroLogo = false; } ];
                center = [ { id = "MediaMini"; hideMode = "hidden"; showAlbumArt = true; showArtistFirst = true; showVisualizer = true; visualizerType = "linear"; maxWidth = 500; useFixedWidth = false; showProgressRing = true; scrollingMode = "hover"; } ];
                right = [
                  { id = "Volume"; displayMode = "onhover"; }
                  { id = "Network"; displayMode = "onhover"; icon = "plug-connected"; }
                  { id = "Bluetooth"; displayMode = "onhover"; }
                  { id = "Clock"; formatHorizontal = "hh:mm a"; formatVertical = "hh mm a"; usePrimaryColor = true; }
                  { id = "NotificationHistory"; }
                ];
              };
            }
          ];
        };

        general = {
          radiusRatio = 0.3;
          iRadiusRatio = 0.6;
          enableShadows = true;
          shadowDirection = "bottom_right";
          shadowOffsetX = 3;
          shadowOffsetY = 4;
          avatarImage = "/home/rock/.face";
        };

        ui = {
          fontDefault = "Sans Serif";
          fontFixed = "monospace";
          tooltipsEnabled = true;
          panelBackgroundOpacity = 0.93;
          panelsAttachedToBar = true;
        };

        location = {
          name = "Sydney";
          weatherEnabled = true;
          useFahrenheit = false;
        };

        wallpaper.enabled = false;

        appLauncher = {
          position = "center";
          sortByMostUsed = true;
          viewMode = "list";
        };

        controlCenter = {
          position = "close_to_bar_button";
          shortcuts = {
            left = [ { id = "Network"; } { id = "Bluetooth"; } { id = "NoctaliaPerformance"; } ];
            right = [ { id = "Notifications"; } { id = "KeepAwake"; } { id = "NightLight"; } ];
          };
          cards = [
            { id = "profile-card"; enabled = true; }
            { id = "shortcuts-card"; enabled = true; }
            { id = "audio-card"; enabled = true; }
            { id = "weather-card"; enabled = true; }
          ];
        };

        sessionMenu = {
          enableCountdown = true;
          countdownDuration = 3000;
          position = "center";
          showHeader = true;
          largeButtonsStyle = true;
          powerOptions = [
            { action = "lock"; enabled = true; }
            { action = "reboot"; enabled = true; }
            { action = "logout"; enabled = true; }
            { action = "shutdown"; enabled = true; }
          ];
        };

        notifications = {
          enabled = true;
          location = "top_right";
        };

        colorSchemes = {
          useWallpaperColors = true;
          darkMode = true;
        };

        desktopWidgets = {
          enabled = true;
          gridSnap = true;
          gridSnapScale = false;
          overviewEnabled = true;
          monitorWidgets = [
            {
              name = "DP-2";
              widgets = [
                { id = "plugin:desktop-clock"; showBackground = false; }
              ];
            }
            {
              name = "HDMI-A-1";
              widgets = [
                { id = "plugin:desktop-clock"; showBackground = false; }
              ];
            }
          ];
        };
      };
    };
  };
}
