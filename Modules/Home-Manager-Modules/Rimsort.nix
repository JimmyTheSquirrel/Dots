{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.rimsort;

  rimsortPkg = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "rimsort";
    version = cfg.version;

    src = pkgs.fetchzip {
      url = "https://github.com/RimSort/RimSort/releases/download/v${version}/RimSort-linux-x64.zip";
      hash = cfg.sha256; # must be SRI form: "sha256-...."
      stripRoot = false;
    };

    nativeBuildInputs = [pkgs.makeWrapper];

    desktopItem = pkgs.makeDesktopItem {
      name = "rimsort";
      desktopName = "RimSort";
      exec = "RimSort";
      terminal = false;
      categories = ["Game" "Utility"];
    };

    installPhase = ''
      runHook preInstall

      mkdir -p $out/opt/RimSort
      cp -r ./* $out/opt/RimSort/

      # Expected upstream binary name:
      chmod +x $out/opt/RimSort/RimSort || true

      mkdir -p $out/bin
      makeWrapper ${pkgs.steam-run}/bin/steam-run $out/bin/RimSort \
        --add-flags "$out/opt/RimSort/RimSort"

      mkdir -p $out/share/applications
      ln -s ${desktopItem}/share/applications/* $out/share/applications/

      runHook postInstall
    '';

    meta = with lib; {
      description = "RimSort mod manager (wrapped to run on NixOS via steam-run)";
      homepage = "https://github.com/RimSort/RimSort";
      platforms = ["x86_64-linux"];
      mainProgram = "RimSort";
    };
  };
in {
  options.programs.rimsort = {
    enable = lib.mkEnableOption "RimSort";

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.0.0";
      description = "RimSort release version tag (without leading 'v').";
    };

    sha256 = lib.mkOption {
      type = lib.types.str;
      default = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      description = "SRI sha256 for the RimSort Linux zip (use nix-prefetch-url --unpack to get it).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [rimsortPkg];
  };
}
