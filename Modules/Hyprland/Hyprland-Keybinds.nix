{ lib, ... }:

let
  mainMod = "SUPER";
in {
  # ---- core keybinds ----
  bind = [
    # Apps & system
    "${mainMod}, RETURN, exec, $terminal"
    "${mainMod}, Q, killactive,"
    "${mainMod}, D, exec, $menu"
    "${mainMod}, M, exit,"
    "${mainMod}, E, exec, $fileManager"
    "${mainMod}, V, togglefloating,"
    "${mainMod}, P, pseudo,"
    "${mainMod}, J, togglesplit,"
    "${mainMod} SHIFT, S, exec, swappy"

    # Move focus
    "${mainMod}, left, movefocus, l"
    "${mainMod}, right, movefocus, r"
    "${mainMod}, up, movefocus, u"
    "${mainMod}, down, movefocus, d"

    # ---- dp-4 workspaces (ultrawide, numbered) ----
    # Switch
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

    # Move
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
    # Switch (use name:<ws> to be explicit)
    "${mainMod}, F1, workspace, name:discord"
    "${mainMod}, F2, workspace, name:spotify"
    "${mainMod}, F3, workspace, name:blank-01"
    "${mainMod}, F4, workspace, name:blank-02"

    # Move
    "${mainMod} SHIFT, F1, movetoworkspace, name:discord"
    "${mainMod} SHIFT, F2, movetoworkspace, name:spotify"
    "${mainMod} SHIFT, F3, movetoworkspace, name:blank-01"
    "${mainMod} SHIFT, F4, movetoworkspace, name:blank-02"

    # ---- special workspace ----
    "${mainMod}, S, togglespecialworkspace, magic"
    "${mainMod} SHIFT, S, movetoworkspace, special:magic"

    # Scroll workspaces
    "${mainMod}, mouse_down, workspace, e+1"
    "${mainMod}, mouse_up, workspace, e-1"
  ];

  # ---- mouse bindings ----
  bindm = [
    "${mainMod}, mouse:272, movewindow"
    "${mainMod}, mouse:273, resizewindow"
  ];

  # ---- press and hold (el) ----
  bindel = [
    ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
    ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
    ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
    ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
  ];

  # ---- media keys (l) ----
  bindl = [
    ", XF86AudioNext, exec, playerctl next"
    ", XF86AudioPause, exec, playerctl play-pause"
    ", XF86AudioPlay, exec, playerctl play-pause"
    ", XF86AudioPrev, exec, playerctl previous"
  ];
}
