{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  # Weekly Calendar plugin
  weekly-calendar-plugin = pkgs.fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia-plugins";
    rev = "main";
    sha256 = "sha256-wierciZBGmkcOSCMoQkZFtIQuR7P9NNtDq3p+K114M4=";
  };

  # Python env for Noctalia calendar integration:
  # - pygobject3 provides `gi`
  # - (optional) you can add other python deps here if Noctalia needs them
  noctaliaPython = pkgs.python3.withPackages (ps: [
    ps.pygobject3
  ]);

  # Runtime deps for EDS + GI typelibs it pulls in
  edsPkgs = with pkgs; [
    evolution-data-server
    libsoup_3
    pkgs.libical
    glib
    gobject-introspection
  ];

  # Where GI looks for *.typelib
  giTypelibPath = lib.makeSearchPath "lib/girepository-1.0" edsPkgs;

  # Some GI modules dlopen shared libs; on Nix we often need this too
  ldLibraryPath = lib.makeLibraryPath edsPkgs;
in {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  home.packages = [
    pkgs.playerctl
    noctaliaPython

    # Useful to debug interactively:
    pkgs.gobject-introspection
    pkgs.evolution-data-server
    pkgs.libsoup_3
    pkgs.libical
  ];

  # Ensure plugin exists declaratively
  home.file.".config/noctalia/plugins/weekly-calendar".source = "${weekly-calendar-plugin}/weekly-calendar";

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
            {
              id = "ControlCenter";
              useDistroLogo = false;
            }
            {
              id = "Workspace";
              hideUnoccupied = true;
              labelMode = "name";
              characterCount = 1;
              emptyColor = "primary";
              focusedColor = "secondary";
              occupiedColor = "primary";
            }
          ];

          center = [
            {
              id = "MediaMini";
              hideMode = "hidden";
              showAlbumArt = true;
              showArtistFirst = true;
              showVisualizer = true;
              visualizerType = "linear";
              maxWidth = 500;
              useFixedWidth = false;
              showProgressRing = true;
              scrollingMode = "hover";
            }
          ];

          right = [
            {
              id = "Volume";
              displayMode = "onhover";
            }
            {
              id = "Network";
              displayMode = "onhover";
            }
            {
              id = "Bluetooth";
              displayMode = "onhover";
            }

            # ✅ plugin bar widget – this is what your settings.json shows
            {id = "plugin:weekly-calendar";}

            {
              id = "Clock";
              formatHorizontal = "hh:mm a";
              formatVertical = "hh mm a";
              usePrimaryColor = true;
            }
            {id = "NotificationHistory";}
          ];
        };

        screenOverrides = [
          {
            enabled = true;
            name = "HDMI-A-1";
            widgets = {
              left = [
                {
                  id = "ControlCenter";
                  useDistroLogo = false;
                }
              ];
              center = [
                {
                  id = "MediaMini";
                  hideMode = "hidden";
                  showAlbumArt = true;
                  showArtistFirst = true;
                  showVisualizer = true;
                  visualizerType = "linear";
                  maxWidth = 500;
                  useFixedWidth = false;
                  showProgressRing = true;
                  scrollingMode = "hover";
                }
              ];
              right = [
                {
                  id = "Volume";
                  displayMode = "onhover";
                }
                {
                  id = "Network";
                  displayMode = "onhover";
                }
                {
                  id = "Bluetooth";
                  displayMode = "onhover";
                }
                {
                  id = "Clock";
                  formatHorizontal = "HH:mm";
                  formatVertical = "HH mm";
                  usePrimaryColor = true;
                }
                {id = "NotificationHistory";}
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

      location = {
        name = "Sydney";
        weatherEnabled = true;
        useFahrenheit = false;
      };

      wallpaper.enabled = false;
      dock.enabled = false;

      controlCenter = {
        shortcuts = {
          left = [{id = "Network";} {id = "Bluetooth";} {id = "NoctaliaPerformance";}];
          right = [{id = "Notifications";} {id = "KeepAwake";} {id = "NightLight";}];
        };
        cards = [
          {
            id = "profile-card";
            enabled = true;
          }
          {
            id = "shortcuts-card";
            enabled = true;
          }
          {
            id = "audio-card";
            enabled = true;
          }
          {
            id = "brightness-card";
            enabled = false;
          }
          {
            id = "weather-card";
            enabled = true;
          }
          {
            id = "media-sysmon-card";
            enabled = false;
          }
        ];
      };

      appLauncher.showCategories = false;
      colorSchemes.predefinedScheme = "Gruvbox";

      sessionMenu = {
        enableCountdown = true;
        countdownDuration = 3000;
        position = "center";
        showHeader = true;
        largeButtonsStyle = true;
        largeButtonsLayout = "single-row";
        showNumberLabels = true;
        powerOptions = [
          {
            action = "lock";
            enabled = true;
          }
          {
            action = "suspend";
            enabled = false;
          }
          {
            action = "hibernate";
            enabled = false;
          }
          {
            action = "reboot";
            enabled = true;
          }
          {
            action = "logout";
            enabled = true;
          }
          {
            action = "shutdown";
            enabled = true;
          }
        ];
      };

      # Optional: if you still want it as a desktop widget too
      desktopWidgets = {
        enabled = true;
        gridSnap = true;
        monitorWidgets = [
          {
            monitor = "DP-2";
            widgets = [
              {
                plugin = "weekly-calendar";
                x = 50;
                y = 100;
              }
            ];
          }
        ];
      };
    };
  };

  # ✅ Make Noctalia’s systemd service able to see python + typelibs + shared libs
  systemd.user.services.noctalia-shell.Service = {
    Environment = [
      "PATH=${noctaliaPython}/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/run/current-system/sw/sbin"
      "PYTHON=${noctaliaPython}/bin/python3"
      "GI_TYPELIB_PATH=${giTypelibPath}"
      "LD_LIBRARY_PATH=${ldLibraryPath}"

      # Helps a lot of GNOME/GSettings lookups on Nix
      "XDG_DATA_DIRS=${lib.makeSearchPath "share" [pkgs.gsettings-desktop-schemas pkgs.glib]}:${config.home.profileDirectory}/share:/run/current-system/sw/share"
    ];
  };
}
