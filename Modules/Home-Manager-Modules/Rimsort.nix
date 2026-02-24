{
  config,
  pkgs,
  lib,
  ...
}: let
  version = "v1.0.69";
  sha256 = "sha256-rr/ZbqQpp6M3E4qFuL+rPtDGnR0NrAib8DXqH+uzt6k=";

  runtimeLibs = [
    # For libsmime3.so (NSS)
    pkgs.nss
    pkgs.nspr

    # X/GL libs commonly needed
    pkgs.xorg.libxshmfence
    pkgs.xorg.libxkbfile
    pkgs.xorg.libX11
    pkgs.xorg.libXext
    pkgs.xorg.libXrender
    pkgs.xorg.libXrandr
    pkgs.xorg.libXi
    pkgs.xorg.libXcursor
    pkgs.xorg.libxcb
    pkgs.mesa
    pkgs.libGL
  ];

  runtimeLibPath = lib.makeLibraryPath runtimeLibs;

  rimsortPkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "rimsort";
    inherit version;

    src = pkgs.fetchzip {
      url = "https://github.com/oceancabbage/RimSort/releases/download/${version}/RimSort-${version}-Ubuntu-24.04_x86_64.zip";
      hash = sha256;
      stripRoot = false;
    };

    nativeBuildInputs = [pkgs.makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/opt/rimsort
      if [ -d "./RimSort" ]; then
        cp -r ./RimSort/* $out/opt/rimsort/
      else
        cp -r ./* $out/opt/rimsort/
      fi

      chmod +x $out/opt/rimsort/RimSort || true

      mkdir -p $out/bin
      makeWrapper ${pkgs.steam-run}/bin/steam-run $out/bin/RimSort \
        --prefix LD_LIBRARY_PATH : "${runtimeLibPath}" \
        --add-flags "$out/opt/rimsort/RimSort"

      ln -s $out/bin/RimSort $out/bin/rimsort

      mkdir -p $out/share/applications
      cat > $out/share/applications/RimSort.desktop <<'EOF'
      [Desktop Entry]
      Type=Application
      Name=RimSort
      Exec=RimSort
      Terminal=false
      Categories=Game;Utility;
      EOF

      runHook postInstall
    '';

    meta = with lib; {
      description = "RimSort mod manager wrapped for NixOS (steam-run + runtime libs)";
      homepage = "https://github.com/oceancabbage/RimSort";
      platforms = ["x86_64-linux"];
      mainProgram = "RimSort";
    };
  };
in {
  config = {
    home.packages = [rimsortPkg];
  };
}
