{ config, pkgs, ... }:

{
  programs.brave = {
    enable = true;
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };

  # Terminal convenience: make 'brave' default to X11
  programs.zsh.shellAliases.brave = "brave --ozone-platform=x11";

  # Launcher entry that forces X11 (valid .desktop Exec)
  xdg.desktopEntries."brave-browser" = {
    name = "Brave Web Browser";
    exec = "brave --ozone-platform=x11 %U";   # <-- no quotes, no sh -c
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
    icon = "brave-browser";
  };

  # (optional) make Brave default
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "brave-browser.desktop" ];
      "x-scheme-handler/http" = [ "brave-browser.desktop" ];
      "x-scheme-handler/https" = [ "brave-browser.desktop" ];
    };
  };
}
