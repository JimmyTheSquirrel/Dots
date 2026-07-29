{ inputs, ... }: {
  flake.nixosModules.kde = { pkgs, activeUser, ... }: {
    # ============================================================
    # SYSTEM CONFIG
    # ============================================================
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.displayManager.sddm.wayland.enable = true;
    services.desktopManager.plasma6.enable = true;

    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      konsole
      kate
      elisa
    ];

    programs.kdeconnect.enable = true;

    environment.systemPackages = with pkgs.kdePackages; [
      ark
      filelight
      kcalc
      dolphin
      dolphin-plugins
    ];

    # ============================================================
    # HOME MANAGER CONFIG
    # ============================================================
    home-manager.users.${activeUser} = {
      imports = [
        inputs.plasma-manager.homeModules.plasma-manager
      ];

      programs.plasma = {
        enable = true;

        workspace = {
          theme = "breeze-dark";
          colorScheme = "BreezeDark";
          cursor.theme = "Bibata-Modern-Classic";
          iconTheme = "breeze-dark";
          wallpaper = null;
        };

        panels = [
          {
            location = "bottom";
            screen = 0;  # DP-2 (primary)
            height = 32;
            floating = false;
            widgets = [
              "org.kde.plasma.kickoff"
              {
                name = "org.kde.plasma.pager";
                config = {
                  General = {
                    displayedText = "None";
                    showWindowIcons = false;
                  };
                };
              }
              "org.kde.plasma.icontasks"
              "org.kde.plasma.marginsseparator"
              {
                systemTray.items = {
                  # Only these stay on the bar; the rest collapse into the arrow popup
                  shown = [
                    "org.kde.plasma.volume"
                    "org.kde.plasma.networkmanagement"
                  ];
                  hidden = [
                    "org.kde.plasma.battery"
                    "org.kde.plasma.brightness"
                    "org.kde.plasma.cameraindicator"
                    "org.kde.plasma.clipboard"
                    "org.kde.plasma.devicenotifier"
                    "org.kde.plasma.keyboardindicator"
                    "org.kde.plasma.keyboardlayout"
                    "org.kde.plasma.manage-inputmethod"
                    "org.kde.plasma.mediacontroller"
                    "org.kde.plasma.notifications"
                    "org.kde.plasma.printmanager"
                    "org.kde.plasma.weather"
                    "org.kde.kdeconnect"
                    "org.kde.kscreen"
                  ];
                };
              }
              "org.kde.plasma.digitalclock"
            ];
          }
        ];

        kwin = {
          virtualDesktops = {
            rows = 1;
            number = 6;
          };
        };

        shortcuts = {
          kwin = {
            "Window Close" = "Meta+Q";
            "Window Fullscreen" = "Meta+Shift+F";
            "Overview" = "Meta+A";
            "Show Desktop" = "none";  # default Meta+D, freed for KRunner
            # Workspace keybinds mirroring niri on Sisyphus (Mod+N / Mod+Shift+N)
            "Switch to Desktop 1" = "Meta+1";
            "Switch to Desktop 2" = "Meta+2";
            "Switch to Desktop 3" = "Meta+3";
            "Switch to Desktop 4" = "Meta+4";
            "Switch to Desktop 5" = "Meta+5";
            "Switch to Desktop 6" = "Meta+6";
            "Window to Desktop 1" = "Meta+Shift+1";
            "Window to Desktop 2" = "Meta+Shift+2";
            "Window to Desktop 3" = "Meta+Shift+3";
            "Window to Desktop 4" = "Meta+Shift+4";
            "Window to Desktop 5" = "Meta+Shift+5";
            "Window to Desktop 6" = "Meta+Shift+6";
          };
          # Meta+N activates pinned taskbar apps by default — free it for desktops
          plasmashell = {
            "activate task manager entry 1" = "none";
            "activate task manager entry 2" = "none";
            "activate task manager entry 3" = "none";
            "activate task manager entry 4" = "none";
            "activate task manager entry 5" = "none";
            "activate task manager entry 6" = "none";
          };
          "services/org.kde.krunner.desktop" = {
            "_launch" = "Meta+D";
          };
        };

        hotkeys.commands = {
          "launch-terminal" = {
            name = "Launch Terminal (Kitty)";
            key = "Meta+Return";
            command = "kitty";
          };
          "launch-file-browser" = {
            name = "Launch File Browser (Thunar)";
            key = "Meta+E";
            command = "thunar";
          };
          "launch-brave" = {
            name = "Launch Brave Browser";
            key = "Meta+F";
            command = "brave";
          };
          "skwd-wallpaper" = {
            name = "SKWD Wallpaper Selector";
            key = "Meta+W";
            command = "skwd wall toggle";
          };
        };

        configFile = {
          kdeglobals = {
            KDE.SingleClick = false;
          };
          kwinrc = {
            Compositing.Backend = "OpenGL";
            Desktops.Number = 6;
          };
        };
      };
    };
  };
}
