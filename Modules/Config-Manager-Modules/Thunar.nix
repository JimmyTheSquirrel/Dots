{
  config,
  pkgs,
  lib,
  ...
}: {
  # ── Packages ───────────────────────────────────────────────────────────────
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

  # ── Services ───────────────────────────────────────────────────────────────
  services.gvfs.enable = true;
  programs.xfconf.enable = true;

  # ── Default file manager ───────────────────────────────────────────────────
  xdg.mime.defaultApplications = {
    "inode/directory" = ["thunar.desktop"];
    "application/x-directory" = ["thunar.desktop"];
  };

  # ── System-wide GTK theme ──────────────────────────────────────────────────
  environment.etc."gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=adw-gtk3-dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-application-prefer-dark-theme=1
  '';
  environment.etc."gtk-4.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=adw-gtk3-dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-application-prefer-dark-theme=1
  '';

  # ── Thunar xfconf settings ─────────────────────────────────────────────────
  system.activationScripts.thunarSettings = {
    deps = [];
    text = ''
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

      set_xfconf() {
        ${pkgs.xfce.xfconf}/bin/xfconf-query \
          -c thunar -p "$1" -s "$2" --create -t "$3" || true
      }

      # View & sidebar
      set_xfconf /misc-show-free-space       true  bool
      set_xfconf /misc-show-thumbnails       true  bool
      set_xfconf /misc-volume-management     true  bool
      set_xfconf /misc-single-click          false bool
      set_xfconf /misc-show-hidden-files     false bool

      # Default view
      set_xfconf /default-view               ThunarDetailsView string
      set_xfconf /last-view                  ThunarDetailsView string

      # Sidebar bookmarks / shortcuts panel
      set_xfconf /shortcuts-icon-size        THUNAR_ICON_SIZE_SMALL string
      set_xfconf /tree-icon-size             THUNAR_ICON_SIZE_SMALL string
      set_xfconf /misc-folders-first         true  bool

      # Thumbnail sizes
      set_xfconf /misc-thumbnail-max-file-size 0 int
    '';
  };
}
