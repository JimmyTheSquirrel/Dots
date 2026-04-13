{ inputs, ... }: {
  flake.homeModules.niri = { pkgs, lib, ... }: {
    imports = [
      inputs.niri.homeModules.niri
    ];

    programs.niri = {
      enable = true;

      settings = {
        prefer-no-csd = true;

        outputs = {
          "DP-2" = {
            enable = true;
            mode = { width = 2560; height = 1080; refresh = 144.0; };
            position = { x = 0; y = 0; };
            scale = 1.0;
          };
          "HDMI-A-1" = {
            enable = true;
            mode = { width = 1920; height = 1080; refresh = 60.0; };
            position = { x = 320; y = -1080; };
            scale = 1.0;
          };
        };

        input = {
          keyboard.xkb.layout = "us";
          mouse = { accel-speed = 0.0; accel-profile = "flat"; };
          touchpad = { tap = true; natural-scroll = false; };
          focus-follows-mouse.enable = true;
        };

        layout = {
          gaps = 4;
          center-focused-column = "never";
          default-column-width = { proportion = 1.0; };
          focus-ring.width = 1;
          border.width = 0;
        };

        cursor = {
          theme = "Bibata-Modern-Classic";
          size = 24;
        };

        screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

        spawn-at-startup = [
          { command = [ "dbus-update-activation-environment" "--systemd" "--all" ]; }
          { command = [ "systemctl" "--user" "import-environment" "--all" ]; }
          { command = [ "gnome-keyring-daemon" "--start" "--components=secrets,ssh,pkcs11" ]; }
          { command = [ "swww-daemon" ]; }
        ];

        window-rules = [
          { draw-border-with-background = false; }
          { matches = [{ app-id = "^thunar$"; }]; opacity = 0.90; }
          { matches = [{ app-id = "^brave-browser$"; }]; opacity = 0.85; }
          { matches = [{ app-id = "^codium$"; }]; opacity = 0.80; }
          { matches = [{ app-id = "^discord$"; }]; opacity = 0.80; }
          { matches = [{ app-id = "^spotify$"; }]; opacity = 0.70; }
          { matches = [{ app-id = "^pavucontrol$"; }]; open-floating = true; }
          { matches = [{ title = "^Picture-in-Picture$"; }]; open-floating = true; }
        ];

        binds = {
          "Super+Return".action.spawn = [ "kitty" ];
          "Super+E".action.spawn = [ "thunar" ];
          "Super+F".action.spawn = [ "brave" ];
          "Super+D".action.spawn = [ "noctalia-shell" "ipc" "call" "launcher" "toggle" ];
          "Super+M".action.spawn = [ "noctalia-shell" "ipc" "call" "sessionMenu" "toggle" ];
          "Super+W".action.spawn = [ "noctalia-shell" "ipc" "call" "wallpaper" "toggle" ];
          "Super+Shift+Delete".action.spawn = [ "noctalia-shell" "ipc" "call" "sessionMenu" "toggle" ];
          "Super+Q".action.close-window = {};
          "Super+V".action.toggle-window-floating = {};
          "Super+Shift+F".action.fullscreen-window = {};
          "Super+F11".action.fullscreen-window = {};
          "Super+J".action.switch-preset-column-width = {};
          "Super+R".action.reset-window-height = {};
          "Super+A".action.toggle-overview = {};
          "Super+Shift+Slash".action.show-hotkey-overlay = {};
          "Super+Left".action.focus-column-left = {};
          "Super+Right".action.focus-column-right = {};
          "Super+Up".action.focus-workspace-up = {};
          "Super+Down".action.focus-workspace-down = {};
          "Super+1".action.focus-workspace-up = {};
          "Super+2".action.focus-workspace-down = {};
          "Super+Shift+Left".action.move-column-left = {};
          "Super+Shift+Right".action.move-column-right = {};
          "Super+Shift+Up".action.move-window-up = {};
          "Super+Shift+Down".action.move-window-down = {};
          "Super+WheelScrollDown".action.focus-column-right = {};
          "Super+WheelScrollUp".action.focus-column-left = {};
          "Super+Shift+S".action.spawn = [ "bash" "-c" "grim -g \"$(slurp)\" - | wl-copy" ];
          "Super+S".action.spawn = [ "bash" "-c" "grim - | wl-copy" ];
          "XF86AudioRaiseVolume".action.spawn = [ "wpctl" "set-volume" "-l" "1" "@DEFAULT_AUDIO_SINK@" "5%+" ];
          "XF86AudioLowerVolume".action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-" ];
          "XF86AudioMute".action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ];
          "XF86AudioMicMute".action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ];
          "XF86AudioNext".action.spawn = [ "playerctl" "next" ];
          "XF86AudioPrev".action.spawn = [ "playerctl" "previous" ];
          "XF86AudioPlay".action.spawn = [ "playerctl" "play-pause" ];
          "XF86AudioPause".action.spawn = [ "playerctl" "play-pause" ];
          "XF86MonBrightnessUp".action.spawn = [ "brightnessctl" "-e4" "-n2" "set" "5%+" ];
          "XF86MonBrightnessDown".action.spawn = [ "brightnessctl" "-e4" "-n2" "set" "5%-" ];
        };
      };
    };
  };
}
