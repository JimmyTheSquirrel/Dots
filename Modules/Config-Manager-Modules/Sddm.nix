# modules/sddm.nix
{
  lib,
  pkgs,
  ...
}: let
  themeVariant = "rei"; # "rei", "rei-alt", etc.

  rev = "v1.3.0"; # tag or commit from https://github.com/uiriansan/SilentSDDM
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

  # QML import paths
  qmlPaths = lib.concatStringsSep ":" [
    "${themePkg}/share/sddm/themes/${themeDir}/components/"
    "${pkgs.qt6.qtmultimedia}/lib/qt6/qml"
    "${pkgs.qt6.qtvirtualkeyboard}/lib/qt6/qml"
    "${pkgs.qt6.qtsvg}/lib/qt6/qml"
    "${pkgs.qt6.qtquickcontrols2}/lib/qt6/qml"
    "${pkgs.qt6.qtdeclarative}/lib/qt6/qml"
  ];
in {
  services.xserver.enable = true;
  qt.enable = true;

  environment.systemPackages = [themePkg];

  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm; # Qt6 SDDM
    theme = themeDir;

    # Required Qt6 modules for SilentSDDM
    extraPackages = with pkgs.qt6; [
      qtvirtualkeyboard
      qtmultimedia
      qtsvg
      qtquickcontrols2
      qtdeclarative
    ];

    settings = {
      General = {
        GreeterEnvironment = "QML2_IMPORT_PATH=${qmlPaths},QT_IM_MODULE=qtvirtualkeyboard";
        InputMethod = "qtvirtualkeyboard";
      };
    };
  };
}
