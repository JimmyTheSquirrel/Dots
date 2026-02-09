# Modules/Brrtfetch.nix
{
  pkgs,
  lib,
  ...
}: let
  brrtfetch = pkgs.buildGoModule rec {
    pname = "brrtfetch";
    version = "unstable-2025-01-09";

    src = pkgs.fetchFromGitHub {
      owner = "ferrebarrat";
      repo = "brrtfetch";
      rev = "main";
      sha256 = "sha256-4Z0eAyFCxrZl7wSAfSt02zktFd47bk7mV4k/OKjilpw=";
    };

    # The repo doesn't use Go modules
    vendorHash = null;

    # Try without patching first - let's see what we actually have
    # The dots might be the current state of the repo

    # Build from the go subdirectory
    preBuild = ''
      cd go
      # Print what the current character array looks like
      echo "=== Current character mapping in main.go ==="
      grep -n "chars :=" main.go || echo "Pattern not found with 'chars :='"
      grep -n '[]string{' main.go | head -5 || echo "No string arrays found"
      echo "==========================================="
    '';

    # Build and name it brrtfetch
    buildPhase = ''
      runHook preBuild
      go build -o brrtfetch main.go
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp brrtfetch $out/bin/
      runHook postInstall
    '';

    meta = with lib; {
      description = "Render animated ASCII art from a GIF for your sysinfo fetcher of choice";
      homepage = "https://github.com/ferrebarrat/brrtfetch";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "brrtfetch";
    };
  };
in {
  home.packages = [
    brrtfetch
    # Dependencies for brrtfetch
    pkgs.util-linux # provides 'script' command
    pkgs.expect # provides 'unbuffer' command
  ];
}
