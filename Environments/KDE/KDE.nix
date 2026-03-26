# KDE Plasma 6 base configuration — dark mode, Papirus icons, Bibata cursor, top bar
{
  config,
  pkgs,
  lib,
  activeUser,
  ...
}: {
  # --- Packages needed for theming ---
  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
    kdePackages.qt6ct
    kdePackages.breeze
  ];

  # --- Cursor ---
  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # --- GTK dark (for GTK apps running inside Plasma) ---
  gtk = {
    enable = true;
    theme = {
      name = "Breeze-Dark";
      package = pkgs.kdePackages.breeze-gtk;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
      size = 24;
    };
  };

  # --- KDE Plasma settings via plasma-manager ---
  programs.plasma = {
    enable = true;

    # --- Workspace / Theme ---
    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      colorScheme = "BreezeDark";
      iconTheme = "Papirus-Dark";
      cursorTheme = "Bibata-Modern-Classic";
      cursorSize = 24;
      wallpaper = "/home/${activeUser}/Pictures/Wallpapers";
    };

    # --- KWin effects + virtual desktops ---
    kwin = {
      effects = {
        blur.enable = true;
        translucency.enable = true;
        desktopSwitching = {
          effect = "thumbnail";
        };
        minimization = {
          effect = "magiclamp";
        };
      };
      virtualDesktops = {
        number = 4;
        names = ["Main" "Work" "Media" "Chat"];
      };
    };

    # --- Top bar only, no dock ---
    panels = [
      {
        location = "top";
        floating = false;
        height = 32;
        widgets = [
          {
            name = "org.kde.plasma.kickoff";
            config.General.icon = "nix-snowflake";
          }
          {name = "org.kde.plasma.pager";}
          {
            name = "org.kde.plasma.taskmanager";
            config.General = {
              groupingStrategy = 1;
              sortingStrategy = 2;
              showOnlyCurrentScreen = false;
            };
          }
          "org.kde.plasma.panelspacer"
          {
            name = "org.kde.plasma.digitalclock";
            config.Appearance = {
              showDate = true;
              dateFormat = "shortDate";
              use24hFormat = 2;
            };
          }
          "org.kde.plasma.panelspacer"
          {name = "org.kde.plasma.systemtray";}
        ];
      }
    ];

    # --- Shortcuts ---
    shortcuts = {
      # --- Window Management ---
      "kwin"."Window Close" = "Meta+Q";
      "kwin"."Window Maximize" = "Meta+Shift+F";
      "kwin"."Window Fullscreen" = "Meta+Shift+F";
      "kwin"."Toggle Window Floating" = "Meta+V";

      # --- Focus ---
      "kwin"."Switch Window Left" = "Meta+Left";
      "kwin"."Switch Window Right" = "Meta+Right";
      "kwin"."Switch Window Up" = "Meta+Up";
      "kwin"."Switch Window Down" = "Meta+Down";

      # --- Virtual Desktops ---
      "kwin"."Switch to Desktop 1" = "Meta+1";
      "kwin"."Switch to Desktop 2" = "Meta+2";
      "kwin"."Switch to Desktop 3" = "Meta+3";
      "kwin"."Switch to Desktop 4" = "Meta+4";
      "kwin"."Switch to Desktop 5" = "Meta+5";
      "kwin"."Switch to Desktop 6" = "Meta+6";
      "kwin"."Switch to Desktop 7" = "Meta+7";
      "kwin"."Switch to Desktop 8" = "Meta+8";
      "kwin"."Switch to Desktop 9" = "Meta+9";
      "kwin"."Switch to Desktop 10" = "Meta+0";

      # --- Move Window to Desktop ---
      "kwin"."Window to Desktop 1" = "Meta+Shift+1";
      "kwin"."Window to Desktop 2" = "Meta+Shift+2";
      "kwin"."Window to Desktop 3" = "Meta+Shift+3";
      "kwin"."Window to Desktop 4" = "Meta+Shift+4";
      "kwin"."Window to Desktop 5" = "Meta+Shift+5";
      "kwin"."Window to Desktop 6" = "Meta+Shift+6";
      "kwin"."Window to Desktop 7" = "Meta+Shift+7";
      "kwin"."Window to Desktop 8" = "Meta+Shift+8";
      "kwin"."Window to Desktop 9" = "Meta+Shift+9";
      "kwin"."Window to Desktop 10" = "Meta+Shift+0";

      # --- Scroll Desktops ---
      "kwin"."Switch to Next Desktop" = "Meta+Mouse Wheel Down";
      "kwin"."Switch to Previous Desktop" = "Meta+Mouse Wheel Up";

      # --- Apps ---
      "services/kitty.desktop"."_launch" = "Meta+Return";
      "services/brave-browser.desktop"."_launch" = "Meta+F";
      "services/thunar.desktop"."_launch" = "Meta+E";

      # --- Media Keys ---
      "kwin"."Volume Up" = "XF86AudioRaiseVolume";
      "kwin"."Volume Down" = "XF86AudioLowerVolume";
      "kwin"."Mute" = "XF86AudioMute";
      "kwin"."MicMute" = "XF86AudioMicMute";
      "mediacontrol"."next" = "XF86AudioNext";
      "mediacontrol"."previous" = "XF86AudioPrev";
      "mediacontrol"."playPause" = "XF86AudioPlay";
    };
  };
}
