{ ... }: {
  # NixOS module - system packages and services
  flake.nixosModules.thunar = { pkgs, ... }: {
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

    services.gvfs.enable = true;
    programs.xfconf.enable = true;

    xdg.mime.defaultApplications = {
      "inode/directory" = [ "thunar.desktop" ];
      "application/x-directory" = [ "thunar.desktop" ];
    };

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
  };

  # Home Manager module - user config
  flake.homeModules.thunar = { ... }: {
    home.file.".config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" = {
      force = true;
      text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <channel name="thunar" version="1.0">
        <property name="default-view" type="string" value="ThunarDetailsView"/>
        <property name="last-view" type="string" value="ThunarDetailsView"/>
        <property name="misc-show-free-space" type="bool" value="true"/>
        <property name="misc-show-thumbnails" type="bool" value="true"/>
        <property name="misc-volume-management" type="bool" value="true"/>
        <property name="misc-single-click" type="bool" value="false"/>
        <property name="misc-show-hidden-files" type="bool" value="false"/>
        <property name="misc-folders-first" type="bool" value="true"/>
        <property name="misc-thumbnail-max-file-size" type="uint64" value="0"/>
        <property name="shortcuts-icon-size" type="string" value="THUNAR_ICON_SIZE_SMALL"/>
        <property name="tree-icon-size" type="string" value="THUNAR_ICON_SIZE_SMALL"/>
      </channel>
    '';
    };
  };
}
