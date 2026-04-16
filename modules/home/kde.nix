{ inputs, ... }: {
  flake.homeModules.kde = { pkgs, ... }: {
    imports = [
      inputs.plasma-manager.homeModules.plasma-manager
    ];

    home.packages = [
      (pkgs.writeShellScriptBin "skwd-wallpaper-toggle" ''
        quickshell ipc -p ~/.config/skwd-wall/daemon.qml call wallpaper toggle
      '')
      (pkgs.writeShellScriptBin "skwd-wall-daemon" ''
        exec quickshell -p ~/.config/skwd-wall/daemon.qml
      '')
    ];

    # Autostart skwd-wall daemon
    xdg.configFile."autostart/skwd-wall-daemon.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=SKWD Wall Daemon
      Exec=skwd-wall-daemon
      X-KDE-autostart-phase=2
    '';

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
          command = "skwd-wallpaper-toggle";
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
}
