{ pkgs, lib, ... }:

let
  kb = import ./Hyprland-Keybinds.nix { inherit lib; };
  ws = import ./Workspace.nix { inherit lib; };
in
{
  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      # --- MONITORS ---
   monitor = [
        # DP-4 ultrawide (main, bottom)
        "DP-4,2560x1080@144,0x0,1"

        # HDMI-A-2 (secondary, top — centered above ultrawide)
        "HDMI-A-2,1920x1080@60,320x-1080,1"
      ];

      # --- PROGRAM VARIABLES ---
      "$terminal"    = "kitty";
      "$fileManager" = "thunar";
      "$menu"        = "rofi -show drun";

      # --- ENVIRONMENT VARIABLES ---
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
      ];

      # --- LOOK AND FEEL ---
      general = {
        gaps_in  = 5;
        gaps_out = 20;
        border_size = 2;
        "col.active_border"   = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        resize_on_border = false;
        allow_tearing    = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        rounding_power = 2;
        active_opacity   = 1.0;
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

      # --- ANIMATIONS ---
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

      # --- LAYOUTS ---
      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      master = { new_status = "master"; };

      # --- MISC ---
      misc = {
        force_default_wallpaper = -1;
        disable_hyprland_logo = false;
      };

      # --- INPUT ---
      input = {
        kb_layout  = "us";
        kb_variant = "";
        kb_model   = "";
        kb_options = "";
        kb_rules   = "";

        follow_mouse = 1;
        sensitivity  = 0;

        touchpad = { natural_scroll = false; };
      };

      gestures = { workspace_swipe = false; };

      device = [
        { name = "epic-mouse-v1"; sensitivity = -0.5; }
      ];

      # --- KEYBINDINGS ---
      inherit (kb) bind bindm bindel bindl;

      # --- WORKSPACES / WINDOW RULES ---
      inherit (ws) workspace windowrule;

      # --- AUTOSTART ---
      exec-once = [ "hyprpanel" ];
    };
  };
}
