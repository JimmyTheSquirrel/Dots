{ config, lib, pkgs, ... }:

let
  scriptsDir = ./Scripts;
in {
  # Required tools
  home.packages = with pkgs; [
    rofi
    swww
    imagemagick
    jq
  ];

  # Install the wallpaper selector script, with executable flag
  home.file."scripts/wallpaper_selector.sh" = {
    source = scriptsDir + "/wallpaper_selector.sh";
    executable = true;
  };

  # Install the custom rofi theme
  home.file.".config/rofi/wallpaper-sel-config.rasi".source =
    scriptsDir + "/wallpaper-sel-config.rasi";

  # Stub pywal's rofi-colors file (until pywal runs)
  home.file.".cache/wal/rofi-colors.rasi".text = ''
    * {
      background: #1e1e2e;
      foreground: #cdd6f4;
      selected-normal-background: #89b4fa;
      selected-normal-foreground: #1e1e2e;
      border-color: #f38ba8;
    }
  '';

  # Optional: auto-generate initial pywal theme if missing
  home.activation.generateInitialPywalTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WAL_COLORS="${config.home.homeDirectory}/.cache/wal/colors.sh"
    if [ ! -f "$WAL_COLORS" ]; then
      echo "Generating pywal theme..."
      wal -i "${config.home.homeDirectory}/Pictures/Wallpapers" || true
    fi
  '';

  # Alias to run the script easily
  home.shellAliases.wall = "bash ~/scripts/wallpaper_selector.sh";
}
