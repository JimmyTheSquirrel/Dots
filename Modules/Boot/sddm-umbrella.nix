# "Women · Umbrella" SDDM greeter (qylock) — Kit-Kat only.
#
# Same upstream collection as Modules/Boot/sddm-nier.nix, different theme. The two
# cannot be imported together: both put a package providing
# share/sddm/themes/<...> into systemPackages and would collide in the profile,
# and only one `services.displayManager.sddm.theme` can win anyway.
#
# Unlike nier-automata this theme needs NO font patching — upstream ships
# font/Itim-Regular.ttf inside the theme directory, which is where its
# FontLoader (Main.qml:34) looks via a FolderListModel. That is the whole reason
# sddm-nier.nix has to override the derivation and we don't.
#
# SDDM itself is enabled by Modules/Desktop/niri.nix.
{ inputs, ... }: {
  flake.nixosModules.sddm-umbrella = { pkgs, ... }: let
    themes = inputs.qylock.legacyPackages.${pkgs.stdenv.hostPlatform.system}.mkSddmThemes { };
  in {
    services.displayManager.sddm = {
      theme = "women-umbrella";

      # extraPackages contributes lib/qt-6/qml to the greeter's QML import path.
      # Main.qml imports Qt5Compat.GraphicalEffects and Qt.labs.folderlistmodel;
      # without qt5compat SDDM logs `module "Qt5Compat.GraphicalEffects" is not
      # installed` and silently falls back to its built-in embedded theme — which
      # looks like "the theme didn't apply" rather than an error.
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
