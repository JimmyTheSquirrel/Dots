# modules/wallpaper-picker.nix
{ config, pkgs, lib, ... }:

{
  # Use rofi-wayland explicitly (prevents the rofi vs rofi-wayland collision)
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
  };

  # Tools used by the script
  home.packages = with pkgs; [
    imagemagick
    swww   # or waypaper if you prefer
  ];

  # Put your theme files in ~/.config/rofi/
  xdg.configFile = {
    "rofi/rofi-simple-config.rasi".source   = ./Scripts/rofi-simple-config.rasi;
    "rofi/rofi-wallpaper-sel.rasi".source   = ./Scripts/rofi-wallpaper-sel.rasi;
    # optional compat symlink: some scripts look for this name
    "rofi/wallpaper-sel-config.rasi".source = ./Scripts/rofi-wallpaper-sel.rasi;
  };

  # Install the launcher script
  home.file.".local/bin/wallpaper_selector.sh" = {
    source = ./Scripts/wallpaper_selector.sh;
    executable = true;
  };
}
