{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf mkMerge;
in {
  # Fonts + icon theme so app icons show up nicely
  home.packages = with pkgs; [
    papirus-icon-theme
    (nerdfonts.override {fonts = ["JetBrainsMono"];})
  ];

  fonts.fontconfig.enable = true;

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland; # change to pkgs.rofi if you're on X11
    extraConfig = {
      modi = "drun,run";
      show-icons = true;
      drun-display-format = "{icon}  {name}";
      icon-theme = "Papirus-Dark";
      font = "JetBrainsMono Nerd Font 12";
      lines = 8;
    };
    theme = "~/.config/rofi/minimal-dark-icons.rasi";
  };

  # Write the minimal, centered dark theme
  home.file.".config/rofi/minimal-dark-icons.rasi".text = ''
    * {
      bg: #0f1115;
      fg: #e5e7eb;
      sel: #1f2937;
      font: "JetBrainsMono Nerd Font 12";
    }

    configuration {
      location: 0;
      anchor: "center";
      fullscreen: false;
      show-icons: true;
      drun-display-format: "{icon}  {name}";
      lines: 8;
    }

    window {
      width: 520px;
      border: 0px;
      border-radius: 14px;
      padding: 10px;
      background-color: @bg;
    }

    mainbox { spacing: 8px; padding: 8px; }

    inputbar {
      background-color: @bg;
      text-color: @fg;
      padding: 8px 10px;
      children: [ entry ];
    }

    prompt { enabled: false; }  /* hides “drun:” */

    listview {
      background-color: @bg;
      spacing: 4px;
      dynamic: true;
    }

    element {
      padding: 6px 8px;
      background-color: transparent;
      text-color: @fg;
    }

    element-icon { size: 18; margin: 0 8px 0 2px; }
    element selected { background-color: @sel; text-color: @fg; }
  '';

  # Optional: Hyprland keybinding ($mod + SPACE) to open the menu
  wayland.windowManager.hyprland = mkIf (config.wayland.windowManager.hyprland.enable or false) {
    settings = {
      bind = [
        "$mod, SPACE, exec, rofi -show drun -theme ~/.config/rofi/minimal-dark-icons.rasi"
      ];
    };
  };
}
