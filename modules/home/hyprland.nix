{ ... }: {
  flake.homeModules.hyprland = { pkgs, lib, ... }: let
    mainMod = "SUPER";
  in {
    wayland.windowManager.hyprland = {
      enable = true;

      settings = {
        monitor = [
          "DP-2,2560x1080@144,0x0,1"
          "HDMI-A-1,1920x1080@60,320x-1080,1"
        ];

        "$terminal" = "kitty";
        "$fileManager" = "thunar";
        "$menu" = "noctalia-shell ipc call sessionMenu toggle";

        env = [
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"
          "WINE_FULLSCREEN_FSR,1"
          "DXVK_ASYNC,1"
        ];

        general = {
          gaps_in = 1;
          gaps_out = 2;
          border_size = 2;
          "col.active_border" = "rgba(595959aa)";
          "col.inactive_border" = "rgba(595959aa)";
          resize_on_border = false;
          allow_tearing = false;
          layout = "dwindle";
        };

        decoration = {
          rounding = 10;
          rounding_power = 2;
          active_opacity = 1.0;
          inactive_opacity = 1.0;
          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
            color = "rgba(1a1a1aee)";
          };
          blur = {
            enabled = true;
            size = 3;
            passes = 1;
            vibrancy = 0.1696;
          };
        };

        animations = {
          enabled = "yes, please :)";
          bezier = [
            "easeOutQuint,0.23,1,0.32,1"
            "easeInOutCubic,0.65,0.05,0.36,1"
            "linear,0,0,1,1"
            "almostLinear,0.5,0.5,0.75,1.0"
            "quick,0.15,0,0.1,1"
          ];
          animation = [
            "global, 1, 10, default"
            "border, 1, 5.39, easeOutQuint"
            "windows, 1, 4.79, easeOutQuint"
            "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
            "windowsOut, 1, 1.49, linear, popin 87%"
            "fadeIn, 1, 1.73, almostLinear"
            "fadeOut, 1, 1.46, almostLinear"
            "fade, 1, 3.03, quick"
            "layers, 1, 3.81, easeOutQuint"
            "layersIn, 1, 4, easeOutQuint, fade"
            "layersOut, 1, 1.5, linear, fade"
            "fadeLayersIn, 1, 1.79, almostLinear"
            "fadeLayersOut, 1, 1.39, almostLinear"
            "workspaces, 1, 1.94, almostLinear, fade"
            "workspacesIn, 1, 1.21, almostLinear, fade"
            "workspacesOut, 1, 1.94, almostLinear, fade"
          ];
        };

        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        master = { new_status = "master"; };

        misc = {
          force_default_wallpaper = -1;
          disable_hyprland_logo = false;
        };

        input = {
          kb_layout = "us";
          follow_mouse = 1;
          sensitivity = 0;
          touchpad = { natural_scroll = false; };
        };

        device = [
          {
            name = "epic-mouse-v1";
            sensitivity = -0.5;
          }
        ];

        # Keybinds
        bind = [
          "${mainMod}, RETURN, exec, $terminal"
          "${mainMod}, Q, killactive,"
          "${mainMod}, D, exec, noctalia-shell ipc call launcher toggle"
          "${mainMod}, W, exec, quickshell ipc -p /home/rock/.config/skwd-wall/daemon.qml call wallpaper toggle"
          "${mainMod}, M, exec, noctalia-shell ipc call sessionMenu toggle"
          "${mainMod}, E, exec, thunar"
          "${mainMod}, V, togglefloating,"
          "${mainMod}, P, pseudo,"
          "${mainMod}, J, togglesplit,"
          "${mainMod}, F, exec, brave"
          "${mainMod} SHIFT, F, fullscreen"
          "${mainMod} SHIFT, B, exec, noctalia-shell ipc call bar toggle"
          "${mainMod} SHIFT, DELETE, exec, noctalia-shell ipc call sessionMenu toggle"
          "${mainMod}, left, movefocus, l"
          "${mainMod}, right, movefocus, r"
          "${mainMod}, up, movefocus, u"
          "${mainMod}, down, movefocus, d"
          "${mainMod}, 1, workspace, 1"
          "${mainMod}, 2, workspace, 2"
          "${mainMod}, 3, workspace, 3"
          "${mainMod}, 4, workspace, 4"
          "${mainMod}, 5, workspace, 5"
          "${mainMod}, 6, workspace, 6"
          "${mainMod}, 7, workspace, 7"
          "${mainMod}, 8, workspace, 8"
          "${mainMod}, 9, workspace, 9"
          "${mainMod}, 0, workspace, 10"
          "${mainMod} SHIFT, 1, movetoworkspace, 1"
          "${mainMod} SHIFT, 2, movetoworkspace, 2"
          "${mainMod} SHIFT, 3, movetoworkspace, 3"
          "${mainMod} SHIFT, 4, movetoworkspace, 4"
          "${mainMod} SHIFT, 5, movetoworkspace, 5"
          "${mainMod} SHIFT, 6, movetoworkspace, 6"
          "${mainMod} SHIFT, 7, movetoworkspace, 7"
          "${mainMod} SHIFT, 8, movetoworkspace, 8"
          "${mainMod} SHIFT, 9, movetoworkspace, 9"
          "${mainMod} SHIFT, 0, movetoworkspace, 10"
          "${mainMod}, F1, workspace, name:discord"
          "${mainMod}, F2, workspace, name:spotify"
          "${mainMod}, F3, workspace, name:blank-01"
          "${mainMod}, F4, workspace, name:blank-02"
          "${mainMod} SHIFT, F1, movetoworkspace, name:discord"
          "${mainMod} SHIFT, F2, movetoworkspace, name:spotify"
          "${mainMod} SHIFT, F3, movetoworkspace, name:blank-01"
          "${mainMod} SHIFT, F4, movetoworkspace, name:blank-02"
          "${mainMod}, mouse_down, workspace, e+1"
          "${mainMod}, mouse_up, workspace, e-1"
        ];

        bindm = [
          "${mainMod}, mouse:272, movewindow"
          "${mainMod}, mouse:273, resizewindow"
        ];

        bindel = [
          ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
          ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
          ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
          ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
        ];

        bindl = [
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPause, exec, playerctl play-pause"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioPrev, exec, playerctl previous"
        ];

        workspace = [
          "1, monitor:DP-2"
          "2, monitor:DP-2"
          "3, monitor:DP-2"
          "4, monitor:DP-2"
          "5, monitor:DP-2"
          "6, monitor:DP-2"
          "name:discord,  monitor:HDMI-A-1"
          "name:spotify,  monitor:HDMI-A-1"
          "name:blank-01, monitor:HDMI-A-1"
          "name:blank-02, monitor:HDMI-A-1"
        ];

        windowrule = [
          "workspace name:discord silent, class:^(discord|vesktop)$"
          "workspace name:spotify silent, class:^(spotify)$"
          "bordersize 0, floating:1"
          "rounding 0, floating:1"
          "suppressevent maximize, class:.*"
          "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
        ];

        windowrulev2 = [
          "opacity 0.75 0.75, class:^(thunar)$"
          "opacity 0.60 0.60, class:^(brave)$"
          "opacity 0.75 0.75, class:^(codium)$"
          "opacity 0.60 0.60, class:^(discord)$"
          "opacity 0.60 0.60, class:^(spotify)$"
          "opacity 0.60 0.60, class:^(Steam)$"
          "tile, class:^(rsi-launcher)$"
          "workspace 5 silent, class:^(rsi-launcher)$"
          "fullscreen, class:^(StarCitizen)$"
          "monitor DP-2, class:^(StarCitizen)$"
          "immediate, class:^(StarCitizen)$"
          "noborder, class:^(StarCitizen)$"
          "nofocus, class:^(wine)$, floating:1"
          "nofocus, class:^(wineserver)$"
        ];

        layerrule = [
          "blur, ^rofi-wal$"
          "blurpopups, ^rofi-wal$"
          "dimaround, ^rofi-wal$"
          "ignorezero, ^rofi-wal$"
        ];

        exec-once = [
          "hyprctl dispatch exec [workspace name:discord silent] discord"
          "hyprctl dispatch exec [workspace name:spotify silent] spotify"
          "dbus-update-activation-environment --systemd --all"
          "systemctl --user import-environment --all"
          "gnome-keyring-daemon --start --components=secrets,ssh,pkcs11"
          "polkit-gnome-authentication-agent-1"
          "noctalia-shell"
          "QT_PLUGIN_PATH=/nix/store/qhsikrhvhhv39cm0lcwmgd5fimf58vkb-qtmultimedia-6.10.2/lib/qt-6/plugins:$QT_PLUGIN_PATH quickshell -p /home/rock/.config/skwd-wall/daemon.qml"
        ];
      };
    };
  };
}
