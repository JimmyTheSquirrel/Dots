# modules/sddm.nix
{
  lib,
  pkgs,
  ...
}: let
  themeName = "pixel-emerald";

  src = pkgs.fetchFromGitHub {
    owner = "Darkkal44";
    repo = "qylock";
    rev = "bf917857b07b311f9c7f3cbe954d36d2fe08f254";
    sha256 = "sha256-BHXhRGZsTI2wJHtmaKYM8slQ7dbQKB0mKfE+MyUNIyk=";
  };

  themePkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "qylock-${themeName}";
    version = "bf917857b07b311f9c7f3cbe954d36d2fe08f254";
    inherit src;
    dontWrapQtApps = true;
    installPhase = ''
      set -euo pipefail
      mkdir -p "$out/share/sddm/themes/${themeName}"
      cp -r themes/${themeName}/. "$out/share/sddm/themes/${themeName}"
    '';
  };

  qtDeps = with pkgs.kdePackages; [
    qtmultimedia
    qtsvg
    qtdeclarative
    qt5compat
  ];

  qmlDirs = map (p: "${p}/lib/qt6/qml") qtDeps;
  qmlPaths = lib.concatStringsSep ":" qmlDirs;
in {
  services.xserver.enable = true;

  environment.systemPackages = [themePkg];

  services.displayManager.sddm = {
    enable = true;
    theme = themeName;
    extraPackages = qtDeps;
    settings = {
      General = {
        GreeterEnvironment = "QML2_IMPORT_PATH=${qmlPaths}";
      };
    };
  };
}
