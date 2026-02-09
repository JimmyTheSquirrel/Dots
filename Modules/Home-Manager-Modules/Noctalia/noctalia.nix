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

  # DateTime widget plugin
  datetime-widget-plugin = pkgs.stdenv.mkDerivation {
    name = "noctalia-datetime-widget";

    dontUnpack = true;
    installPhase = ''
            mkdir -p $out

            # Create DesktopWidget.qml following Noctalia's structure
            cat > $out/DesktopWidget.qml << 'EOF'
      import QtQuick
      import QtQuick.Layouts
      import qs.Commons
      import qs.Modules.DesktopWidgets
      import qs.Widgets

      DraggableDesktopWidget {
        id: root

        // Required by Noctalia
        property var pluginApi: null

        // Scaled dimensions
        implicitWidth: Math.round(400 * widgetScale)
        implicitHeight: Math.round(200 * widgetScale)
        width: implicitWidth
        height: implicitHeight

        // Custom background since we want specific styling
        showBackground: false

        Rectangle {
          anchors.fill: parent
          color: "#40000000"
          opacity: 0.3
          radius: 0

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Math.round(8 * widgetScale)

            NText {
              id: dayText
              Layout.alignment: Qt.AlignHCenter
              color: "#E8E3D3"
              pointSize: Math.round(48 * widgetScale)
              font.family: "JetBrains Mono"
              font.letterSpacing: Math.round(8 * widgetScale)
              font.weight: Font.Light
            }

            NText {
              id: dateText
              Layout.alignment: Qt.AlignHCenter
              color: "#A89F8F"
              pointSize: Math.round(16 * widgetScale)
              font.family: "JetBrains Mono"
              font.letterSpacing: Math.round(2 * widgetScale)
            }

            NText {
              id: timeText
              Layout.alignment: Qt.AlignHCenter
              color: "#A89F8F"
              pointSize: Math.round(16 * widgetScale)
              font.family: "JetBrains Mono"
              font.letterSpacing: Math.round(2 * widgetScale)
            }
          }
        }

        Timer {
          interval: 1000
          running: true
          repeat: true
          onTriggered: updateDateTime()
        }

        Component.onCompleted: updateDateTime()

        function updateDateTime() {
          var now = new Date();
          dayText.text = Qt.formatDate(now, "dddd").toUpperCase();
          dateText.text = Qt.formatDate(now, "dd MMM yyyy").toUpperCase();
          timeText.text = "- " + Qt.formatTime(now, "hh:mm AP").toUpperCase() + " -";
        }
      }
      EOF

            # Create manifest.json with proper structure
            cat > $out/manifest.json << EOF
      {
        "id": "datetime-widget",
        "name": "DateTime Widget",
        "description": "Retro-styled date and time display",
        "version": "1.0.0",
        "minNoctaliaVersion": "3.6.0",
        "author": "rock",
        "license": "MIT",
        "tags": ["Desktop"],
        "entryPoints": {
          "desktopWidget": "DesktopWidget.qml"
        },
        "metadata": {
          "defaultSettings": {}
        }
      }
      EOF
    '';
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
    pkgs.jetbrains-mono
    noctaliaPython

    # Useful to debug interactively:
    pkgs.gobject-introspection
    pkgs.evolution-data-server
    pkgs.libsoup_3
    pkgs.libical
  ];

  # Ensure plugins exist declaratively
  home.file.".config/noctalia/plugins/weekly-calendar".source = "${weekly-calendar-plugin}/weekly-calendar";
  home.file.".config/noctalia/plugins/datetime-widget".source = datetime-widget-plugin;

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

      ui = {
        fontDefault = "Sans Serif";
        fontFixed = "monospace";
        fontDefaultScale = 1;
        fontFixedScale = 1;
        tooltipsEnabled = true;
        panelBackgroundOpacity = 0.93;
        panelsAttachedToBar = true;
        settingsPanelMode = "attached";
        wifiDetailsViewMode = "grid";
        bluetoothDetailsViewMode = "grid";
        networkPanelView = "wifi";
        bluetoothHideUnnamedDevices = false;
        boxBorderEnabled = false;
      };

      location = {
        name = "Sydney";
        weatherEnabled = true;
        weatherShowEffects = true;
        useFahrenheit = false;
        use12hourFormat = false;
        showWeekNumberInCalendar = false;
        showCalendarEvents = true;
        showCalendarWeather = true;
        analogClockInCalendar = false;
        firstDayOfWeek = -1;
        hideWeatherTimezone = false;
        hideWeatherCityName = false;
      };

      calendar = {
        cards = [
          {
            enabled = true;
            id = "calendar-header-card";
          }
          {
            enabled = true;
            id = "calendar-month-card";
          }
          {
            enabled = true;
            id = "weather-card";
          }
        ];
      };

      # ---- Wallpaper (match your JSON) ----
      wallpaper = {
        enabled = true;
        overviewEnabled = false;
        directory = "/home/rock/Pictures/Wallpapers";
        monitorDirectories = [];
        enableMultiMonitorDirectories = false;
        showHiddenFiles = false;
        viewMode = "single";
        setWallpaperOnAllMonitors = true;
        fillMode = "center";
        fillColor = "#000000";
        useSolidColor = false;
        solidColor = "#1a1a2e";
        automationEnabled = false;
        wallpaperChangeMode = "random";
        randomIntervalSec = 300;
        transitionDuration = 500;
        transitionType = "random";
        transitionEdgeSmoothness = 0.05;
        panelPosition = "follow_bar";
        hideWallpaperFilenames = false;

        useWallhaven = false;
        wallhavenQuery = "";
        wallhavenSorting = "relevance";
        wallhavenOrder = "desc";
        wallhavenCategories = "111";
        wallhavenPurity = "100";
        wallhavenRatios = "";
        wallhavenApiKey = "";
        wallhavenResolutionMode = "atleast";
        wallhavenResolutionWidth = "";
        wallhavenResolutionHeight = "";

        sortOrder = "name";
      };

      appLauncher = {
        enableClipboardHistory = false;
        autoPasteClipboard = false;
        enableClipPreview = true;
        clipboardWrapText = true;
        clipboardWatchTextCommand = "wl-paste --type text --watch cliphist store";
        clipboardWatchImageCommand = "wl-paste --type image --watch cliphist store";
        position = "center";
        pinnedApps = [];
        useApp2Unit = false;
        sortByMostUsed = true;
        terminalCommand = "alacritty -e";
        customLaunchPrefixEnabled = false;
        customLaunchPrefix = "";
        viewMode = "list";
        showCategories = false;
        iconMode = "tabler";
        showIconBackground = false;
        enableSettingsSearch = true;
        enableWindowsSearch = true;
        ignoreMouseInput = false;
        screenshotAnnotationTool = "";
      };

      controlCenter = {
        position = "close_to_bar_button";
        diskPath = "/";
        shortcuts = {
          left = [
            {id = "Network";}
            {id = "Bluetooth";}
            {id = "NoctaliaPerformance";}
          ];
          right = [
            {id = "Notifications";}
            {id = "KeepAwake";}
            {id = "NightLight";}
          ];
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

      systemMonitor = {
        cpuWarningThreshold = 80;
        cpuCriticalThreshold = 90;
        tempWarningThreshold = 80;
        tempCriticalThreshold = 90;
        gpuWarningThreshold = 80;
        gpuCriticalThreshold = 90;
        memWarningThreshold = 80;
        memCriticalThreshold = 90;
        swapWarningThreshold = 80;
        swapCriticalThreshold = 90;
        diskWarningThreshold = 80;
        diskCriticalThreshold = 90;
        cpuPollingInterval = 1000;
        gpuPollingInterval = 3000;
        enableDgpuMonitoring = false;
        memPollingInterval = 1000;
        diskPollingInterval = 30000;
        networkPollingInterval = 1000;
        loadAvgPollingInterval = 3000;
        useCustomColors = false;
        warningColor = "";
        criticalColor = "";
        externalMonitor = "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor";
      };

      dock = {
        enabled = false;
        position = "bottom";
        displayMode = "auto_hide";
        backgroundOpacity = 1;
        floatingRatio = 1;
        size = 1;
        onlySameOutput = true;
        monitors = [];
        pinnedApps = [];
        colorizeIcons = false;
        pinnedStatic = false;
        inactiveIndicators = false;
        deadOpacity = 0.6;
        animationSpeed = 1;
      };

      network = {
        wifiEnabled = true;
        bluetoothRssiPollingEnabled = false;
        bluetoothRssiPollIntervalMs = 10000;
        wifiDetailsViewMode = "grid";
        bluetoothDetailsViewMode = "grid";
        bluetoothHideUnnamedDevices = false;
      };

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

      notifications = {
        enabled = true;
        monitors = [];
        location = "top_right";
        overlayLayer = true;
        backgroundOpacity = 1;
        respectExpireTimeout = false;
        lowUrgencyDuration = 3;
        normalUrgencyDuration = 8;
        criticalUrgencyDuration = 15;
        enableKeyboardLayoutToast = true;
        saveToHistory = {
          low = true;
          normal = true;
          critical = true;
        };
        sounds = {
          enabled = false;
          volume = 0.5;
          separateSounds = false;
          criticalSoundFile = "";
          normalSoundFile = "";
          lowSoundFile = "";
          excludedApps = "discord,firefox,chrome,chromium,edge";
        };
        enableMediaToast = false;
      };

      osd = {
        enabled = true;
        location = "top_right";
        autoHideMs = 2000;
        overlayLayer = true;
        backgroundOpacity = 1;
        enabledTypes = [0 1 2];
        monitors = [];
      };

      audio = {
        volumeStep = 5;
        volumeOverdrive = false;
        cavaFrameRate = 30;
        visualizerType = "linear";
        mprisBlacklist = [];
        preferredPlayer = "";
        volumeFeedback = false;
      };

      brightness = {
        brightnessStep = 5;
        enforceMinimum = true;
        enableDdcSupport = false;
      };

      # ---- Auto colours (match your JSON) ----
      colorSchemes = {
        useWallpaperColors = true;
        predefinedScheme = "Gruvbox";
        darkMode = true;
        schedulingMode = "off";
        manualSunrise = "06:30";
        manualSunset = "18:30";
        generationMethod = "rainbow";
        monitorForColors = "";
      };

      templates = {
        activeTemplates = [];
        enableUserTheming = false;
      };

      nightLight = {
        enabled = false;
        forced = false;
        autoSchedule = true;
        nightTemp = "4000";
        dayTemp = "6500";
        manualSunrise = "06:30";
        manualSunset = "18:30";
      };

      hooks = {
        enabled = false;
        wallpaperChange = "";
        darkModeChange = "";
        screenLock = "";
        screenUnlock = "";
        performanceModeEnabled = "";
        performanceModeDisabled = "";
        startup = "";
        session = "";
      };

      # Desktop widgets with datetime widget added
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
              {
                plugin = "datetime-widget";
                x = 760;
                y = 440;
              }
            ];
          }
        ];
      };
    };
  };

  # ✅ Make Noctalia's systemd service able to see python + typelibs + shared libs
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
