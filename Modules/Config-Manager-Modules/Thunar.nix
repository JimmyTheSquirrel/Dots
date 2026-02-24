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
    xdg-utils
    adwaita-icon-theme
    hicolor-icon-theme
    papirus-icon-theme
  ];

  #### Services needed by Thunar
  services.gvfs.enable = true;
  programs.xfconf.enable = true;

  #### Portals
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-hyprland
  ];

  #### Make Thunar the default file manager
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "inode/directory" = ["thunar.desktop"];
      "application/x-directory" = ["thunar.desktop"];
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

  #### Set Thunar xfconf settings (shows free space in sidebar)
  system.activationScripts.thunarSettings = {
    deps = [];
    text = ''
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
      ${pkgs.xfce.xfconf}/bin/xfconf-query \
        -c thunar \
        -p /misc-show-free-space \
        -s true \
        --create \
        -t bool \
      || true
    '';
  };
}
