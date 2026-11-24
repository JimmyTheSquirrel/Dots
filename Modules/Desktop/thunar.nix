{ ... }: {
  flake.nixosModules.thunar = { pkgs, activeUser, ... }: {
    # Workaround for NixOS packaging bug: xarchiver.tap lives in xarchiver's
    # package but thunar-archive-plugin can't see it — copy it in at build time.
    # https://github.com/NixOS/nixpkgs/issues/248192
    #
    # Still needed as of nixpkgs 26.05: the plugin's package has no xarchiver
    # input and only looks for *.tap files in its own libexec/. It now overrides
    # the TOP-LEVEL thunar-archive-plugin — the Thunar family moved out of the
    # `xfce` scope (2025-12), and `xfce.*` is only a warning alias to it now.
    nixpkgs.overlays = [
      (final: prev: {
        thunar-archive-plugin = prev.thunar-archive-plugin.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            cp ${prev.xarchiver}/libexec/thunar-archive-plugin/* $out/libexec/thunar-archive-plugin/
          '';
        });
      })
    ];

    programs.thunar = {
      enable = true;
      plugins = with pkgs; [
        thunar-archive-plugin
        thunar-volman
      ];
    };

    # ⚠️ ELEKTRA ONLY as of 2026-11-20. Sisyphus swapped Thunar for Luciole
    # (Modules/Desktop/luciole.nix) and dropped this module, so this file now
    # configures exactly one machine — her Hyprland desktop, where Thunar stays.
    # The overlay above, programs.xfconf and the inode/directory default below
    # therefore no longer apply to Sisyphus at all.
    #
    # Only Thunar's OWN dependencies are left here. The generic session bits
    # that used to ride along in this list — xdg-utils, p7zip and the three icon
    # themes — moved to Modules/Desktop/desktop.nix, which both compositors
    # import, so that dropping a file manager could not quietly take xdg-open
    # and GTK's icon fallbacks with it.
    environment.systemPackages = with pkgs; [
      tumbler            # Thunar's thumbnailer service
      ffmpegthumbnailer  # video thumbnails, via tumbler
      xarchiver          # the backend thunar-archive-plugin shells out to
    ];

    # services.gvfs (trash, network locations, thunar-volman's mounts) is NOT
    # repeated here: Modules/Core/polkit.nix enables it unconditionally, and
    # every host that imports this module imports that one too.
    programs.xfconf.enable = true;

    xdg.mime.defaultApplications = {
      "inode/directory" = [ "thunar.desktop" ];
      "application/x-directory" = [ "thunar.desktop" ];
    };

    # No /etc/gtk-3.0 or /etc/gtk-4.0 settings.ini. Both used to be written here
    # (adw-gtk3-dark + Papirus-Dark + prefer-dark) and GTK never read either:
    # it looks in $XDG_CONFIG_DIRS (/etc/xdg/gtk-3.0) and its own build-time
    # sysconfdir, which on NixOS is a store path — never /etc/gtk-3.0. Do not
    # "fix" this by moving them to /etc/xdg: that would switch on the
    # adw-gtk3/Papirus theming that was rejected on taste (Claude/misc.md).

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
