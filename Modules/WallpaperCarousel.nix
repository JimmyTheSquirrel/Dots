{ config, lib, pkgs, ... }:

let
  scriptsDir = ./Scripts;
in {
  home.packages = with pkgs; [
    rofi
    swww
    imagemagick
    jq
  ];

  # Install the wallpaper selector script
  home.file."scripts/wallpaper_selector.sh" = {
    source = scriptsDir + "/wallpaper_selector.sh";
    executable = true;
  };

  # Link your static rofi theme (manually written)
  home.file.".config/rofi/wallpaper-sel-config.rasi".source =
    scriptsDir + "/wallpaper-sel-config.rasi";

  # Optional: run via alias
  home.shellAliases.wall = "bash ~/scripts/wallpaper_selector.sh";
}
