{
  lib,
  pkgs,
  ...
}: let
  # ────────────────────────────────────────────────────────────────────────────
  # Edit these to change your theme selection and pin
  # ────────────────────────────────────────────────────────────────────────────
  themeVariant = "rei"; # e.g. "rei", "rei-alt", etc.
  src = pkgs.fetchFromGitHub {
    owner = "uiriansan";
    repo = "SilentSDDM";
    rev = "v1.3.0"; # tag or commit; change here when updating
    sha256 = "sha256-REPLACE_ME"; # put a fake value first; build once to get the real one from the error
  };

  # Where the theme will live under $out/share/sddm/themes/
  themeDir = themeVariant;

  themePkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "silent-sddm-${themeVariant}";
    version = "${builtins.substring 0 7 (src.rev or "dev")}";
    src = src;
    installPhase = ''
      set -euo pipefail
      mkdir -p "$out/share/sddm/themes/${themeDir}"
      cp -r . "$out/share/sddm/themes/${themeDir}"
    '';
    # Provide virtual keyboard at login; add more Qt modules here if needed
    propagatedBuildInputs = [pkgs.qt6.qtvirtualkeyboard];
  };

  baseSettings = {
    General = {
      # Make QML components visible and enable the Qt virtual keyboard
      GreeterEnvironment = "QML2_IMPORT_PATH=${themePkg}/share/sddm/themes/${themeDir}/components/,QT_IM_MODULE=qtvirtualkeyboard";
      InputMethod = "qtvirtualkeyboard";
    };
  };
in {
  # No options exposed — this module directly declares the system settings.

  # Ensure the display stack pieces are on
  services.xserver.enable = true; # needed for SDDM module wiring
  qt.enable = true; # Qt bits for SDDM greeter

  # Install the theme package so SDDM can see it
  environment.systemPackages = [themePkg];

  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm; # Qt6 SDDM (recommended for Plasma 6)
    theme = themeDir; # must match the directory we installed
    extraPackages = themePkg.propagatedBuildInputs;
    settings = baseSettings; # merge more keys here if desired
    # wayland.enable = true; # uncomment if you want Wayland greeter
  };
}
