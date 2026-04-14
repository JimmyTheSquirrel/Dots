{ inputs, ... }: {
  flake.homeModules.kde = { ... }: {
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
          location = "top";
          height = 32;
          widgets = [
            "org.kde.plasma.kickoff"
            "org.kde.plasma.pager"
            "org.kde.plasma.taskmanager"
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
