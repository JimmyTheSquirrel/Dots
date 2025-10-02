{ config, pkgs, lib, ... }:

let
  wallpaperPath = "${config.home.homeDirectory}/Pictures/Wallpapers/current.jpg";
in
{
  home.packages = with pkgs; [
    pywal
  ];

  # Generate a pywal theme at login (optional but useful)
  systemd.user.services.pywal-init = {
    Unit = {
      Description = "Generate pywal theme from current wallpaper";
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.pywal}/bin/wal -i ${wallpaperPath}";
      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Source pywal colors at shell login
  programs.bash.initExtra = ''
    [ -f "${config.home.homeDirectory}/.cache/wal/colors.sh" ] && source "${config.home.homeDirectory}/.cache/wal/colors.sh"
  '';

  # If you use zsh
  programs.zsh.initExtra = ''
    [ -f "${config.home.homeDirectory}/.cache/wal/colors.sh" ] && source "${config.home.homeDirectory}/.cache/wal/colors.sh"
  '';

  # Rofi config link for pywal to theme it
  home.file.".config/rofi/wallpaper-sel-config.rasi".source = "${config.home.homeDirectory}/.cache/wal/rofi-colors.rasi";
}
