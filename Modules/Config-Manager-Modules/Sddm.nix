# modules/sddm.nix
{
  lib,
  pkgs,
  ...
}: let
  themeVariant = "rei"; # choose "rei", "rei-alt", etc.

  rev = "v1.3.0";
  src = pkgs.fetchFromGitHub {
    owner = "uiriansan";
    repo = "SilentSDDM";
    inherit rev;
    sha256 = "sha256-B/vh3n5ZDwd9Lx/35XAx4o/37g4V/oa3aFSe6b8+DfM=";
  };

  themeDir = themeVariant;

  themePkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "silent-sddm-${themeVariant}";
    version = rev;
    inherit src;
    dontWrapQtApps = true;
    installPhase = ''
      set -euo pipefail
      mkdir -p "$out/share/sddm/themes/${themeDir}"
      cp -r . "$out/share/sddm/themes/${themeDir}"
    '';
  };

  qt6 = pkgs.qt6;

  # Gracefully detect which Qt modules exist in this nixpkgs
  availableQtPkgs = lib.filter (x: x != null) [
    (qt6.qtvirtualkeyboard or null)
    (qt6.qtmultimedia or null)
    (qt6.qtsvg or null)
    (qt6.qtquickcontrols2 or qt6.qtquickcontrols or null)
    (qt6.qtdeclarative or null)
  ];

  qmlDirs =
    (map (p: "${p}/lib/qt6/qml") availableQtPkgs)
    ++ ["${themePkg}/share/sddm/themes/${themeDir}/components/"];

  qmlPaths = lib.concatStringsSep ":" qmlDirs;
in {
  services.xserver.enable = true;
  qt.enable = true;

  environment.systemPackages = [themePkg];

  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm; # Qt6 SDDM
    theme = themeDir;
    extraPackages = availableQtPkgs;
    settings = {
      General = {
        GreeterEnvironment = "QML2_IMPORT_PATH=${qmlPaths},QT_IM_MODULE=qtvirtualkeyboard";
        InputMethod = "qtvirtualkeyboard";
      };
    };
  };
}
