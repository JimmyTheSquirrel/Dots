# Modules/Nemo.nix
{ config, pkgs, ... }:

{
  ##### Install Nemo
  home.packages = with pkgs; [
    nemo
  ];

  ##### Make Nemo the default file manager
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory"         = [ "nemo.desktop" ];
      "application/x-directory" = [ "nemo.desktop" ];
    };
  };

  ##### GTK theming (Catppuccin + Tela)
  gtk = {
    enable = true;

    # If nixpkgs ever renames variants, you can list available ones with:
    # nix eval nixpkgs#catppuccin-gtk.themes
    theme = {
      name = "Catppuccin-Mocha-Standard-Blue-Dark";
      package = pkgs.catppuccin-gtk;
    };

    # If tela-circle fails on your channel, swap to pkgs.tela-icon-theme
    iconTheme = {
      name = "Tela-circle-dark";
      package = pkgs.tela-circle-icon-theme;
    };

    font = { name = "Inter 11"; };
  };

  ##### Nemo preferences (via dconf)
  dconf.settings = {
    "org/nemo/preferences" = {
      default-folder-viewer = "list-view"; # start in list view
      show-hidden-files = true;            # show dotfiles
      sort-directories-first = true;       # folders on top
      use-extra-pane = true;               # enable split pane (toggle with F3)
      date-format = "iso";                 # cleaner timestamps
    };

    "org/nemo/list-view" = {
      default-zoom-level = "large";       # small, standard, large, larger, largest
    };

    "org/nemo/icon-view" = {
      default-zoom-level = "large";
    };
  };
}
