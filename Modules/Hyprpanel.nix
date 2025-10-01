{ pkgs, lib, ... }:

{
  # --- Packages (fonts Hyprpanel expects) ---
  home.packages = with pkgs; [
    nerd-fonts.caskaydia-cove
    nerd-fonts.fantasque-sans-mono
  ];

  # --- Hyprpanel config (writes ~/.config/hyprpanel/config.json) ---
  programs.hyprpanel = {
    enable = true;

    settings = {
      # --- LAYOUTS ---
      layout = {
        "bar.layouts" = {
          "0" = {
            left   = [ "dashboard" "workspaces" "windowtitle" ];
            middle = [ "media" ];
            right  = [ "volume" "microphone" "systray" "clock" "notifications" ];
          };
          "1" = {
            left   = [ "dashboard" "workspaces" "windowtitle" ];
            middle = [ "media" ];
            right  = [ "volume" "network" "bluetooth" "updates" "clock" "notifications" ];
          };
        };
      };

      # --- General ---
      menus.transition = "crossfade";
      menus.transitionTime = 150;
      scalingPriority = "gdk";
      bar.scrollSpeed = 5;
      tear = true;

      # --- Workspaces ---
      bar.workspaces = {
        monitorSpecific = true;
        show_icons = false;
        show_numbered = false;
        workspaceMask = false;
        showWsIcons = true;
        showApplicationIcons = true;
        applicationIconOncePerWorkspace = true;
        numbered_active_indicator = "underline";
        showAllActive = false;
      };

      # --- Window title ---
      bar.windowtitle = {
        custom_title = true;
        label = true;
        icon = true;
        truncation = true;
        class_name = true;
        truncation_size = 50;
      };

      # --- Clock & weather ---
      bar.clock = {
        showTime = true;
        format = "%a %b %d  %I:%M %p";
        showIcon = true;
      };
      menus.clock = {
        time = { military = false; hideSeconds = true; };
        weather = {
          enabled = true;
          unit = "metric";
          location = "Sydney";
          interval = 2000;
        };
      };

      # --- Media / notifications ---
      bar.media.truncation_size = 80;
      notifications.showActionsOnHover = true;
      bar.notifications = { show_total = false; hideCountWhenZero = false; };

      # --- Network / bluetooth ---
      bar.network = { label = true; rightClick = ""; showWifiInfo = true; };

      # --- Volume / battery ---
      bar.volume.label = true;
      bar.battery = { label = true; hideLabelWhenFull = true; };

      # --- Dashboard ---
      menus.dashboard = {
        directories.enabled = false;
        stats = { enabled = true; enable_gpu = false; interval = 2000; };
        powermenu = {
          avatar = { name = "Rock @ Sisyphus"; image = "/home/rock/Downloads/My ChatGPT image.png"; };
          sleep = "systemctl suspend";
          logout = "hyprctl dispatch exit";
          reboot = "systemctl reboot";
          shutdown = "systemctl poweroff";
          confirmation = true;
        };
        controls.enabled = false;
        shortcuts.left.shortcut1 = { command = "brave"; tooltip = "Brave"; };
        shortcuts.left.shortcut4 = {
          tooltip = "Screenshot";
          command = ''bash -c "/usr/share/hyprpanel/scripts/snapshot.sh"'';
          icon = "󰄀";
        };
        recording.path = "$HOME/Videos/Screen Recs";
        profile.size = "17.5em";
      };

      # --- Launcher / systray ---
      bar.launcher = { autoDetectIcon = true; rightClick = "menu:powerdropdown"; };
      bar.systray.customIcon = "#e0def4";

      # --- Custom modules ---
      bar.customModules = {
        storage = {
          paths = [ "/home/rock/" ];
          label = true;
          labelType = "percentage";
          units = "tebibytes";
          tooltipStyle = "tree";
          round = true;
        };
        updates = { autoHide = true; pollingInterval = 1440000; };
        netstat = { dynamicIcon = true; rateUnit = "auto"; labelType = "in"; rightClick = "menu:network"; };
        cava = { channels = 2; stereo = true; bars = 15; samplerate = 44100; };
      };

      # --- Theme ---
      theme = {
        bar = {
          location = "top";
          layer = "top";
          enableShadow = false;
          border.location = "none";
          transparent = false;
          opacity = 70;
          floating = false;
          buttons = {
            style = "split";
            enableBorders = false;
            windowtitle.enableBorder = false;
            volume.enableBorder = false;
            network.enableBorder = false;
            bluetooth.enableBorder = false;
            clock.enableBorder = false;
            media.enableBorder = true;
            notifications.enableBorder = true;
          };
          background = "#191724";
          menus = {
            enableShadow = true;
            background = "#191724";
            opacity = 90;
            border.color = "#1f1d2e";
            cards = "#21202e";
            text = "#e0def4";
            label = "#c4a7e7";
            feinttext = "#1f1d2e";
            menu.dashboard.scaling = 90;
          };
          border.color = "#c4a7e7";
        };

        notification = {
          scaling = 100;
          close_button = { label = "#191724"; background = "#eb6f92"; };
          text = "#e0def4";
          background = "#1f1d2e";
          border = "#1f1d2e";
          label = "#c4a7e7";
          time = "#403d52";
          actions = { text = "#1f1d2e"; background = "#c4a7e7"; };
        };

        osd = {
          label = "#c4a7e7";
          icon = "#191724";
          icon_container = "#c4a7e7";
          bar_container = "#191724";
          bar_color = "#c4a7e7";
          bar_empty_color = "#1f1d2e";
          bar_overflow_color = "#eb6f92";
          border.color = "#8ff0a4";
        };

        font = {
          name  = "FantasqueSansM Nerd Font Propo";  # or "CaskaydiaCove NF"
          label = "FantasqueSansM Nerd Font Propo Bold Italic";
          style = "italic";
        };

        matugen = true;
        matugen_settings = { mode = "dark"; scheme_type = "content"; variation = "standard_1"; };
      };

      # --- Wallpaper ---
      wallpaper = {
        enable = false;
        pywal = true;
        image = "";
      };
    };
  };

  # --- Disable HM’s hyprpanel systemd service (let Hyprland exec-once handle it) ---
  systemd.user.services.hyprpanel.Install.WantedBy = lib.mkForce [ ];
}
