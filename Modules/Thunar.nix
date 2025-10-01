# Modules/Thunar.nix
{ config, pkgs, ... }:

{
  # Install Thunar and plugins
  home.packages = with pkgs; [
    xfce.thunar
    xfce.thunar-archive-plugin
    xfce.thunar-media-tags-plugin
    xfce.thunar-volman
    file-roller
    lxappearance
    gvfs
    udisks2
  ];

  # Needed for Thunar settings + thumbnails
  programs.xfconf.enable = true;
  services.tumbler.enable = true;
  services.gvfs.enable = true;

  # Set Thunar as the default file manager
  xdg.mimeApps.defaultApplications = {
    "inode/directory" = [ "thunar.desktop" ];
    "application/x-directory" = [ "thunar.desktop" ];
  };

  # GTK theming with Gruvbox
  gtk = {
    enable = true;

    theme = {
      name = "Gruvbox-Dark-B"; # available: Gruvbox-Dark-{A,B}, Gruvbox-Light-{A,B}
      package = pkgs.gruvbox-gtk-theme;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    font = {
      name = "Inter 10";
    };
  };
}
