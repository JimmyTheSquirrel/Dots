# Modules/Nemo.nix
{ config, pkgs, ... }:

{
  # Install Nemo
  home.packages = with pkgs; [ nemo ];

  # Make Nemo the default file manager
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory"         = [ "nemo.desktop" ];
      "application/x-directory" = [ "nemo.desktop" ];
    };
  };

  # GTK theming (reliable dark)
  gtk = {
    enable = true;

    # adw-gtk3 is very dependable for GTK3 apps like Nemo
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };

    # Pick any icon theme you like; these two are good:
    iconTheme = {
      name = "Papirus-Dark";             # or "Tela-circle-dark"
      package = pkgs.papirus-icon-theme; # or pkgs.tela-circle-icon-theme
    };

    font = { name = "Inter 11"; };
  };

  # Nemo defaults (list, hidden, nicer sizing)
  dconf.settings = {
    "org/nemo/preferences" = {
      default-folder-viewer   = "list-view";
      show-hidden-files       = true;
      sort-directories-first  = true;
      use-extra-pane          = true;
      date-format             = "iso";
    };
    "org/nemo/list-view" = {
      default-zoom-level = "larger";     # small|standard|large|larger|largest
    };
    "org/nemo/icon-view" = {
      default-zoom-level = "larger";
    };

    # Some toolkits also respect this dark hint:
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
