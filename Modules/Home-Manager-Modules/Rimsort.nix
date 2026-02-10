{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  steam-run,
  makeDesktopItem,
}: let
  pname = "rimsort";
  version = "1.0.0"; # <-- change to the RimSort release version you download

  # RimSort provides prebuilt Linux zip releases; you want the Linux x86_64 zip asset.
  src = fetchzip {
    url = "https://github.com/RimSort/RimSort/releases/download/v${version}/RimSort-linux-x64.zip";
    # IMPORTANT: replace with the correct hash (see instructions below)
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    stripRoot = false;
  };

  desktopItem = makeDesktopItem {
    name = "RimSort";
    desktopName = "RimSort";
    exec = "RimSort";
    terminal = false;
    categories = ["Game" "Utility"];
  };
in
  stdenvNoCC.mkDerivation {
    inherit pname version src;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/opt/RimSort
      cp -r ./* $out/opt/RimSort/

      # Some zips ship the binary as "RimSort", others may differ; this expects "RimSort".
      # If your extracted zip uses a different filename, adjust the path below.
      chmod +x $out/opt/RimSort/RimSort || true

      mkdir -p $out/bin
      makeWrapper ${steam-run}/bin/steam-run $out/bin/RimSort \
        --add-flags "$out/opt/RimSort/RimSort"

      # Desktop entry
      mkdir -p $out/share/applications
      ln -s ${desktopItem}/share/applications/* $out/share/applications/

      runHook postInstall
    '';

    meta = with lib; {
      description = "RimSort mod manager (wrapped to run on NixOS via steam-run)";
      homepage = "https://github.com/RimSort/RimSort";
      platforms = ["x86_64-linux"];
      mainProgram = "RimSort";
      license = licenses.mit; # if this differs for RimSort, adjust accordingly
    };
  }
