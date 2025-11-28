{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) mkIf;

  # Handle Nerd Fonts for both old/new nixpkgs layouts
  jetbrainsNerd =
    if pkgs ? nerd-fonts
    then pkgs.nerd-fonts.jetbrains-mono
    else (pkgs.nerdfonts.override {fonts = ["JetBrainsMono"];});
in {
  ###### Basic dependencies ######
  home.packages = with pkgs; [
    papirus-icon-theme
    jetbrainsNerd
  ];

  fonts.fontconfig.enable = true;

  ###### App Launcher: Fuzzel ######
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # Font & appearance
        font = "JetBrainsMono Nerd Font:size=14";
        prompt = ""; # hide "drun:"
        icons-enabled = true;
        icon-theme = "Papirus-Dark";

        # Layout & placement
        width = 50; # 50% of screen width
        lines = 12; # visible app rows
        layer = "overlay";
        anchor = "center";
        inner-pad = 12;
        horizontal-pad = 20;
        vertical-pad = 20;

        # Behavior
        fuzzy = true;
        dpi-aware = true;
        terminal = "foot"; # change to your terminal if needed
      };

      colors = {
        background = "1a1c21cc"; # dark, slightly transparent
        text = "e5e7ebff"; # light text
        selection = "3d4452ff"; # highlight
        selection-text = "e5e7ebff";
        border = "8aadf4ff"; # accent blue border
      };

      border = {
        width = 2;
        radius = 16;
      };
    };
  };

  ###### Hyprland binding ######
  wayland.windowManager.hyprland = mkIf (config.wayland.windowManager.hyprland.enable or false) {
    settings.bind = [
      # App launcher
      "SUPER, SPACE, exec, fuzzel --log-level none"
    ];
  };

  ###### Optional notes ######
  # You can theme further by editing ~/.config/fuzzel/fuzzel.ini
  # or use environment variables like FUZZEL_STYLE if needed.
}
