{ inputs, ... }: {
  flake.homeModules.noctalia = { pkgs, ... }: {
    imports = [
      inputs.noctalia.homeModules.default
    ];

    home.packages = [
      pkgs.playerctl
      pkgs.jetbrains-mono
    ];

    programs.noctalia-shell = {
      enable = true;
      systemd.enable = true;

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
                  { id = "Clock"; formatHorizontal = "HH:mm"; formatVertical = "HH mm"; usePrimaryColor = true; }
                  { id = "NotificationHistory"; }
                  { id = "Tray"; displayMode = "onhover"; }
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
          predefinedScheme = "Gruvbox";
          darkMode = true;
        };
      };
    };
  };
}
