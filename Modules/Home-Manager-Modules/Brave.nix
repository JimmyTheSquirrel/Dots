{ config, pkgs, ... }:

{
  # Install Brave for this user
  programs.brave = {
    enable = true;
    # keep any extensions you like
    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
    ];
  };

  # Pass runtime flags through Brave's standard flags file
  # - basic password store (no KWallet/GNOME Keyring)
  # - Wayland backend (use x11 if you prefer)
  home.file.".config/brave-flags.conf".text = ''
    --password-store=basic
    --enable-features=UseOzonePlatform
    --ozone-platform=wayland
  '';

  # Make Brave default browser (per-user)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html"             = [ "brave-browser.desktop" ];
      "x-scheme-handler/http" = [ "brave-browser.desktop" ];
      "x-scheme-handler/https"= [ "brave-browser.desktop" ];
    };
  };

  # (Optional) if you previously had an alias forcing x11, drop it now
  programs.zsh.shellAliases.brave = "brave";
}
