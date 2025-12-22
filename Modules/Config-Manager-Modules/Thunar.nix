{
  config,
  pkgs,
  lib,
  ...
}: {
  #### Apps & helpers (system-wide)
  environment.systemPackages = with pkgs; [
    xfce.thunar
    xfce.thunar-volman
    xfce.tumbler
    ffmpegthumbnailer
    file-roller

    # Needed so “Open in Terminal” (xdg-terminal-exec) works
    xdg-utils

    # themes/icons so Thunar has proper icons out of the box
    adwaita-icon-theme
    hicolor-icon-theme
    papirus-icon-theme
  ];

  #### Services needed by Thunar
  services.gvfs.enable = true; # mounts, trash, file chooser helpers
  programs.xfconf.enable = true; # Xfce/Thunar settings backend

  #### Portals (Wayland-friendly file dialogs / xdg-open)
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-hyprland # keep if you use Hyprland
  ];

  #### Make Thunar the default file manager
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "inode/directory" = ["thunar.desktop"];

      # Register kitty as the default terminal emulator handler
      # Fixes: “Failed to launch preferred application for category TerminalEmulator”
      "x-scheme-handler/terminal" = ["kitty.desktop"];
    };
  };

  #### System-wide GTK theme + icon defaults
  environment.etc."gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Adwaita-dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-application-prefer-dark-theme=1
  '';
  environment.etc."gtk-4.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Adwaita-dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-application-prefer-dark-theme=1
  '';
}
