{lib, ...}: let
  mainMod = "SUPER";
in {
  # ---- core keybinds ----
  bind = [
    # Apps & system
    "${mainMod}, RETURN, exec, $terminal"
    "${mainMod}, Q, killactive,"

    # NOCTALIA: App Launcher
    "${mainMod}, D, exec, noctalia-shell ipc call launcher toggle"

    # NOCTALIA: Session/Power Menu
    "${mainMod}, M, exec, noctalia-shell ipc call sessionMenu toggle"

    "${mainMod}, E, exec, thunar"
    "${mainMod}, V, togglefloating,"
    "${mainMod}, P, pseudo,"
    "${mainMod}, J, togglesplit,"
    "${mainMod}, F, exec, brave"
    "${mainMod}, W, exec, /home/rock/.local/bin/wallpaper_selector.sh"
    "${mainMod} SHIFT, F, fullscreen"

    # NOCTALIA: Session menu (replaces wlogout)
    "${mainMod} SHIFT, DELETE, exec, noctalia-shell ipc call sessionMenu toggle"

    # Move focus
    "${mainMod}, left, movefocus, l"
    "${mainMod}, right, movefocus, r"
    "${mainMod}, up, movefocus, u"
    "${mainMod}, down, movefocus, d"

    # ---- dp-4 workspaces (ultrawide, numbered) ----
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

    # ---- hdmi-a-2 workspaces (named on F1–F4) ----
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
}
