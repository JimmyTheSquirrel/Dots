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
            floating = true;
            widgets = [
              "org.kde.plasma.kickoff"
              {
                name = "org.kde.plasma.pager";
                config = {
                  General = {
                    displayedText = "Number";
                    showWindowIcons = false;
                  };
                };
              }
              "org.kde.plasma.icontasks"
              "org.kde.plasma.marginsseparator"
              "org.kde.plasma.systemtray"
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
