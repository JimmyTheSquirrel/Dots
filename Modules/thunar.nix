{ ... }: {
  flake.nixosModules.thunar = { pkgs, activeUser, ... }: {
    # Workaround for NixOS packaging bug: xarchiver.tap lives in xarchiver's
    # package but thunar-archive-plugin can't see it — copy it in at build time.
    # https://github.com/NixOS/nixpkgs/issues/248192
    nixpkgs.overlays = [
      (final: prev: {
        xfce = prev.xfce.overrideScope (xfinal: xprev: {
          thunar-archive-plugin = xprev.thunar-archive-plugin.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              cp ${prev.xarchiver}/libexec/thunar-archive-plugin/* $out/libexec/thunar-archive-plugin/
            '';
          });
        });
      })
    ];

    programs.thunar = {
      enable = true;
      plugins = with pkgs.xfce; [
        thunar-archive-plugin
        thunar-volman
      ];
    };

    environment.systemPackages = with pkgs; [
      xfce.tumbler
      ffmpegthumbnailer
      xarchiver
      p7zip
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

    home-manager.users.${activeUser} = {
      home.file.".config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml" = {
        force = true;
        text = ''
          <?xml version="1.0" encoding="UTF-8"?>
          <channel name="thunar" version="1.0">
            <property name="default-view" type="string" value="ThunarIconView"/>
            <property name="last-view" type="string" value="ThunarIconView"/>
            <property name="last-icon-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_100_PERCENT"/>
            <property name="misc-show-free-space" type="bool" value="true"/>
            <property name="misc-show-thumbnails" type="bool" value="true"/>
            <property name="misc-volume-management" type="bool" value="true"/>
            <property name="misc-single-click" type="bool" value="false"/>
            <property name="misc-show-hidden-files" type="bool" value="true"/>
            <property name="misc-folders-first" type="bool" value="true"/>
            <property name="misc-thumbnail-max-file-size" type="uint64" value="0"/>
            <property name="shortcuts-icon-size" type="string" value="THUNAR_ICON_SIZE_SMALL"/>
            <property name="tree-icon-size" type="string" value="THUNAR_ICON_SIZE_SMALL"/>
          </channel>
        '';
      };
    };
  };
}
