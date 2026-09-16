{ inputs, ... }: {
  # NieR: Automata SDDM greeter (qylock). Sisyphus only — Odysseus still uses
  # `Modules/sddm.nix` (silentSDDM). The two cannot coexist on one host: silentSDDM
  # sets `GreeterEnvironment=QML2_IMPORT_PATH=<its own theme dir>`, which *replaces*
  # the greeter's QML path rather than appending to it, so it would hide the Qt6
  # modules this theme imports. SDDM itself is enabled by `Modules/Desktops/niri.nix`.
  flake.nixosModules.sddm-nier = { pkgs, ... }: let
    # The theme's FontLoader (Main.qml:57) takes the first *.ttf/*.otf a
    # FolderListModel finds in the theme's own `font/` directory — so the font has
    # to live inside the theme package, not in `fonts.packages`. Upstream ships
    # that directory holding only a .gitkeep (FOT-Rodin is copyrighted and can't be
    # redistributed), which is why untouched qylock falls back to Qt's default sans.
    #
    # `programs.qylock` builds its theme package privately and exposes no override,
    # so we call the builder it publishes and patch the font in ourselves. That also
    # means doing the three things the module would have done (theme name,
    # extraPackages, systemPackages) by hand — importing it *as well* would put two
    # packages providing share/sddm/themes/nier-automata into systemPackages and
    # collide in the profile.
    themes = (inputs.qylock.legacyPackages.${pkgs.stdenv.hostPlatform.system}.mkSddmThemes { }).overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        # `cp -r` from the store carries the source's read-only mode onto the copied
        # directories, so the font/ dir is not writable until we say so.
        chmod -R u+w $out/share/sddm/themes/nier-automata
        install -Dm444 ${../Resources/Fonts/FOT-Rodin-Pro-DB.otf} \
          $out/share/sddm/themes/nier-automata/font/rodin.otf
      '';
    });
  in {
    services.displayManager.sddm = {
      theme = "nier-automata";

      # extraPackages contributes lib/qt-6/qml to the greeter's QML import path.
      # qt5compat is load-bearing: Main.qml imports Qt5Compat.GraphicalEffects, and
      # without it SDDM logs `module "Qt5Compat.GraphicalEffects" is not installed`
      # and silently falls back to its built-in embedded theme.
      extraPackages = [
        themes
        pkgs.qt6.qt5compat
        pkgs.qt6.qtmultimedia
        pkgs.qt6.qtsvg
      ];

      # SDDM's compiled-in default for InputMethod is `qtvirtualkeyboard`, and the
      # NixOS module only overrides it for the kwin-wayland greeter. Left unset, an
      # on-screen keyboard docks over the lower half of the screen and squashes the
      # theme's layout into a letterbox.
      settings.General.InputMethod = "";
    };

    # Puts the theme under /run/current-system/sw/share/sddm/themes, which is where
    # SDDM's ThemeDir points.
    environment.systemPackages = [ themes ];
  };
}
