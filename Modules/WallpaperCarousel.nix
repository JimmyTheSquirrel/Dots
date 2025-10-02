{ config, lib, pkgs, ... }:

let
  scriptsDir = ./Scripts;
in {
  # Required programs
  home.packages = with pkgs; [
    rofi
    swww
    imagemagick
    jq
    pywal
  ];

  # Wallpaper script
  home.file."scripts/wallpaper_selector.sh".source = scriptsDir + "/wallpaper_selector.sh";

  # Rofi theme file
  home.file.".config/rofi/wallpaper-sel-config.rasi".source = scriptsDir + "/wallpaper-sel-config.rasi";

  # Stub out the pywal rofi-colors if not generated yet
  home.file.".cache/wal/rofi-colors.rasi".text = ''
    * {
      background: #1e1e2e;
      foreground: #cdd6f4;
      selected-normal-background: #89b4fa;
      selected-normal-foreground: #1e1e2e;
      border-color: #f38ba8;
    }
  '';

  # Make script executable
  home.activation.makeWallpaperScriptExecutable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod +x "${config.home.homeDirectory}/scripts/wallpaper_selector.sh"
  '';

  # Optional: Rofi alias for quick testing
  home.shellAliases.wall = "bash ~/scripts/wallpaper_selector.sh";
}
