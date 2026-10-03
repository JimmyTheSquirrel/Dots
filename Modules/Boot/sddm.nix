# SDDM greeter — a single qylock theme, chosen per host.
#
#   Sisyphus: nier-automata      (my.sddm.theme = "nier-automata")
#   Kit-Kat:  women-umbrella     (my.sddm.theme = "women-umbrella")
#
# This replaced two near-identical modules, sddm-nier.nix and sddm-umbrella.nix.
# Both called qylock's `mkSddmThemes { }`, which copies ALL ~40 of its themes —
# 526 MB, into the system closure — to use one (nier-automata is 236 KB,
# women-umbrella 3.3 MB). It also forced an evaluation of qylock's own nixpkgs
# import just to reach that builder.
#
# The builder does nothing else these two themes need: its only extra step is
# `mkConfEdits`, a set of theme.conf seds for terraria / Genshin / clockwork /
# osu. Each theme directory is self-contained (Main.qml, metadata.desktop,
# theme.conf, bg.png, font/), so copying the one directory out of the flake
# source is the whole build.
#
# Owning the theme here is also what makes the two mutually exclusive by
# construction: an enum cannot hold two values, so there is no longer a way to
# import both greeters and collide two share/sddm/themes packages in the profile.
{ inputs, ... }: {
  flake.nixosModules.sddm = { config, pkgs, lib, ... }: let
    themeName = config.my.sddm.theme;

    theme = pkgs.runCommand "qylock-sddm-${themeName}" { } (''
      mkdir -p $out/share/sddm/themes
      cp -r ${inputs.qylock}/themes/${themeName} $out/share/sddm/themes/${themeName}
      # `cp -r` from the store carries the source's read-only mode onto the copied
      # directories, so nothing under it is writable until we say so.
      chmod -R u+w $out/share/sddm/themes/${themeName}
    '' + lib.optionalString (themeName == "nier-automata") ''
      # The theme's FontLoader (Main.qml:57) takes the first *.ttf/*.otf a
      # FolderListModel finds in the theme's own `font/` directory — so the font
      # has to live inside the theme package, not in `fonts.packages`. Upstream
      # ships that directory holding only a .gitkeep (FOT-Rodin is copyrighted and
      # can't be redistributed), which is why untouched qylock falls back to Qt's
      # default sans.
      #
      # women-umbrella needs none of this: upstream ships font/Itim-Regular.ttf
      # inside its theme directory, which is where its FontLoader (Main.qml:34)
      # looks.
      install -Dm444 ${../../Resources/Fonts/FOT-Rodin-Pro-DB.otf} \
        $out/share/sddm/themes/nier-automata/font/rodin.otf
    '');
  in {
    options.my.sddm.theme = lib.mkOption {
      type = lib.types.enum [ "nier-automata" "women-umbrella" ];
      description = ''
        Which qylock theme the SDDM greeter shows. Only this one theme is built
        into the system. To offer another, add its directory name (under
        qylock's themes/) to the enum, after checking whether it needs a font
        dropped into its font/ directory the way nier-automata does.
      '';
    };

    config = {
      services.displayManager.sddm = {
        enable = true;
        theme = themeName;

        # extraPackages contributes lib/qt-6/qml to the greeter's QML import path.
        # qt5compat is load-bearing: both themes' Main.qml import
        # Qt5Compat.GraphicalEffects (and Qt.labs.folderlistmodel), and without it
        # SDDM logs `module "Qt5Compat.GraphicalEffects" is not installed` and
        # silently falls back to its built-in embedded theme — which looks like
        # "the theme didn't apply" rather than an error.
        extraPackages = [
          theme
          pkgs.qt6.qt5compat
          pkgs.qt6.qtmultimedia
          pkgs.qt6.qtsvg
        ];

        settings.General = {
          # SDDM's compiled-in default for InputMethod is `qtvirtualkeyboard`, and
          # the NixOS module only overrides it for the kwin-wayland greeter. Left
          # unset, an on-screen keyboard docks over the lower half of the screen
          # and squashes the theme's layout into a letterbox.
          InputMethod = "";

          # Same cursor as the session (XCURSOR_* in Modules/Desktop/desktop.nix),
          # so the pointer does not change shape between greeter and desktop.
          CursorTheme = "Bibata-Modern-Classic";
          CursorSize = 24;
        };
      };

      # Puts the theme under /run/current-system/sw/share/sddm/themes, which is
      # where SDDM's ThemeDir points.
      environment.systemPackages = [ theme ];
    };
  };
}
