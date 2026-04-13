{
  config,
  pkgs,
  ...
}: {
  # User-level Steam configuration
  # System-level config (packages, firewall) is in Config-Manager-Modules/Steam.nix

  xdg.desktopEntries.steam = {
    name = "Steam";
    comment = "Application for managing and playing games on Steam";
    exec = "steam -nofriendsui -nochatui %U";
    icon = "steam";
    terminal = false;
    categories = ["Game"];
    mimeType = ["x-scheme-handler/steam" "x-scheme-handler/steamlink"];
  };
}
