{ config, lib, pkgs, ... }:

let
  scriptDir = ../../Dots/Modules/Scripts;
in
{
  home.packages = with pkgs; [
    rofi
    swww
    imagemagick
    jq
    pywal
  ];

  home.file."scripts/wallpaper_selector.sh".source = "${scriptDir}/wallpaper_selector.sh";

  home.file."config/waypaper/config.ini".source = "${scriptDir}/config.ini";

  # Optional: make the script executable
  home.activation.makeScriptsExecutable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod +x "${config.home.homeDirectory}/scripts/wallpaper_selector.sh"
  '';

  # Optional: alias to make it easy to call
  home.shellAliases.wall = "bash ~/scripts/wallpaper_selector.sh";

  # Optional: Desktop entry to launch from menu
  home.file.".local/share/applications/WallpaperSelector.desktop".text = ''
    [Desktop Entry]
    Name=Wallpaper Selector
    Exec=${config.home.homeDirectory}/scripts/wallpaper_selector.sh
    Type=Application
    Terminal=false
  '';
}
