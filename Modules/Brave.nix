# Modules/Brave.nix
{ config, pkgs, ... }:

{
  # Install Brave + Bitwarden extension
  programs.brave = {
    enable = true;
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };

  # Wrap the brave command so terminal launches use X11
  home.packages = [
    (pkgs.writeShellScriptBin "brave" ''
      exec ${pkgs.brave}/bin/brave --ozone-platform=x11 "$@"
    '')
  ];

  # Make the launcher entry also use X11 (so the menu icon works)
  xdg.desktopEntries."brave-browser" = {
    name = "Brave Web Browser";
    exec = "brave --ozone-platform=x11 %U";
    terminal = false;
    categories = [ "Network" "WebBrowser" ];
    mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
    icon = "brave-browser";
  };

  # Optional: keep Brave as default browser (if you want this inside the module)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "brave-browser.desktop" ];
      "x-scheme-handler/http" = [ "brave-browser.desktop" ];
      "x-scheme-handler/https" = [ "brave-browser.desktop" ];
    };
  };
}
