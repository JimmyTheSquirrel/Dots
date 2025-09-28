programs.hyprland = {
  enable = true;

  settings = {
    env = [
      "mainMod SUPER"
      "scriptsDir $HOME/.config/hypr/scripts"
      "UserScripts $HOME/.config/hypr/UserScripts"
      "UserConfigs $HOME/.config/hypr/UserConfigs"
      "term kitty"         # ⬅️ Set your default terminal here
      "files nautilus"     # ⬅️ Set your default file manager here
    ];

    bind = [
      # Common shortcuts
      "$mainMod, D, exec, pkill rofi || true && rofi -show drun -modi drun,filebrowser,run,window"
      "$mainMod, A, exec, pkill rofi || true && ags -t 'overview'"
      "$mainMod, Return, exec, $term"
      "$mainMod, E, exec, $files"

      # Features / Extras
      "$mainMod, H, exec, $scriptsDir/KeyHints.sh"
      "$mainMod ALT, R, exec, $scriptsDir/Refresh.sh"
      "$mainMod ALT, E, exec, $scriptsDir/RofiEmoji.sh"
      "$mainMod, S, exec, $scriptsDir/RofiSearch.sh"
      "$mainMod ALT, O, exec, $scriptsDir/ChangeBlur.sh"
      "$mainMod SHIFT, G, exec, $scriptsDir/GameMode.sh"
      "$mainMod ALT, L, exec, $scriptsDir/ChangeLayout.sh"
      "$mainMod ALT, V, exec, $scriptsDir/ClipManager.sh"
      "$mainMod CTRL, R, exec, $scriptsDir/RofiThemeSelector.sh"
      "$mainMod CTRL SHIFT, R, exec, pkill rofi || true && $scriptsDir/RofiThemeSelector-modified.sh"

      # Floating / fullscreen
      "$mainMod SHIFT, F, fullscreen"
      "$mainMod CTRL, F, fullscreen, 1"
      "$mainMod, SPACE, togglefloating"
      "$mainMod ALT, SPACE, exec, hyprctl dispatch workspaceopt allfloat"
      "$mainMod SHIFT, Return, exec, [float; move 15% 5%; size 70% 60%] $term"

      # Zoom / magnifier
      "$mainMod SHIFT, mouse_down, exec, hyprctl keyword cursor:zoom_factor \"$(hyprctl getoption cursor:zoom_factor | awk 'NR==1 {factor = $2; if (factor < 1) {factor = 1}; print factor * 2.0}')\""
      "$mainMod SHIFT, mouse_up, exec, hyprctl keyword cursor:zoom_factor \"$(hyprctl getoption cursor:zoom_factor | awk 'NR==1 {factor = $2; if (factor < 1) {factor = 1}; print factor / 2.0}')\""

      # Waybar
      "$mainMod CTRL ALT, B, exec, pkill -SIGUSR1 waybar"
      "$mainMod CTRL, B, exec, $scriptsDir/WaybarStyles.sh"
      "$mainMod ALT, B, exec, $scriptsDir/WaybarLayout.sh"

      # UserScripts
      "$mainMod SHIFT, M, exec, $UserScripts/RofiBeats.sh"
      "$mainMod, W, exec, $UserScripts/WallpaperSelect.sh"
      "$mainMod SHIFT, W, exec, $UserScripts/WallpaperEffects.sh"
      "CTRL ALT, W, exec, $UserScripts/WallpaperRandom.sh"
      "$mainMod CTRL, O, exec, hyprctl setprop active opaque toggle"
      "$mainMod SHIFT, K, exec, $scriptsDir/KeyBinds.sh"
      "$mainMod SHIFT, A, exec, $scriptsDir/Animations.sh"
      "$mainMod SHIFT, O, exec, $UserScripts/ZshChangeTheme.sh"
      "$mainMod ALT, C, exec, $UserScripts/RofiCalc.sh"

      # Browser
      "$mainMod, F, exec, brave"
    ];

    bindl = [
      # Layout switcher
      "ALT_L SHIFT_L, exec, $scriptsDir/SwitchKeyboardLayout.sh"
    ];

    # Example: You can add monitor/input/windowrules/decoration/animations/input/etc here
    # input = {
    #   kb_layout = "us";
    # };
  };
};

