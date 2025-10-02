# Modules/Rofi/default.nix
{ pkgs, ... }:

let
  rofiTheme = pkgs.writeText "rofi-theme.rasi" ''
    * {
      font: "JetBrainsMono Nerd Font 12";
      bg: #111318;
      bg-alt: #171922;
      fg: #E6E6E6;
      sel-bg: #2a2f3a;
      sel-fg: #ffffff;
      acc: #c4a7e7;
      br: #262a34;
      radius: 12px;
      padding: 10px;
      spacing: 6px;
    }

    window {
      location: center;
      width: 40%;
      background-color: @bg;
      border: 1px;
      border-color: @br;
      border-radius: @radius;
    }

    mainbox {
      padding: @padding;
      spacing: @spacing;
    }

    inputbar {
      background-color: @bg-alt;
      border: 1px;
      border-color: @br;
      border-radius: @radius;
      padding: 8px;
    }

    prompt { enabled: false; }

    entry {
      placeholder: "Type to filter";
      text-color: @fg;
    }

    listview {
      background-color: transparent;
      spacing: 4px;
      scrollbar: true;
      fixed-height: 0;
      lines: 12;
    }

    element {
      padding: 8px;
      border-radius: 10px;
    }

    /* state selectors use dot syntax */
    element.selected {
      background-color: @sel-bg;
      text-color: @sel-fg;
      border: 1px;
      border-color: @acc;
    }

    element-icon {
      size: 22;
      vertical-align: 0.5;
      horizontal-align: 0.0;
      margin: 0 8px 0 2px;
    }

    element-text {
      highlight: bold;
    }
  '';
in
{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    font = "JetBrainsMono Nerd Font 12";

    extraConfig = {
      modi = "drun,run";
      show-icons = true;
      drun-display-format = "{name}";
    };

    theme = rofiTheme;  # <- pass a path to the .rasi we just wrote
  };

  # Make sure the font is available for rofi and other apps
  home.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
}
