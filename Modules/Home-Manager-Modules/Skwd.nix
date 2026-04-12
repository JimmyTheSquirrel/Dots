# Modules/Home-Manager-Modules/Skwd.nix
{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}: let
  skwdPath = "${config.home.homeDirectory}/.config/skwd-wall";
in {
  # ============================================================
  # PACKAGES
  # ============================================================
  home.packages = with pkgs; [
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
    curl
    sqlite
    ffmpeg
    imagemagick
    inotify-tools
    nerd-fonts.symbols-only
    roboto
    roboto-mono
    material-design-icons
    matugen
    pkgs-unstable.qt6.qtmultimedia
    steamcmd
    mpvpaper
  ];

  # ============================================================
  # CLONE REPO ON ACTIVATION
  # ============================================================
  home.activation.cloneSkwdWall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "${skwdPath}" ]; then
      ${pkgs.git}/bin/git clone https://github.com/liixini/skwd-wall "${skwdPath}"
    fi
  '';

  # ============================================================
  # SEED CONFIG ON FIRST CLONE
  # ============================================================
  home.activation.skwdWallConfig = lib.hm.dag.entryAfter ["cloneSkwdWall"] ''
        if [ ! -f "${skwdPath}/config.json" ]; then
          cat > "${skwdPath}/config.json" << 'EOF'
    {
      "compositor": "hyprland",
      "monitor": "",
      "paths": {
        "wallpaper": "~/Pictures/Wallpapers",
        "videoWallpaper": "~/Pictures/Wallpapers",
        "cache": "",
        "templates": "",
        "scripts": "",
        "steam": "",
        "steamWorkshop": "",
        "steamWeAssets": ""
      },
      "features": {
        "matugen": true,
        "ollama": false,
        "steam": false,
        "wallhaven": true
      },
      "colorSource": "magick",
      "ollama": {
        "url": "http://localhost:11434",
        "model": "gemma3:4b"
      },
      "steam": {
        "apiKey": "",
        "username": "JimmyTheSquirrel`"
      },
      "wallhaven": {
        "apiKey": ""
      },
      "matugen": {
        "schemeType": "scheme-fidelity"
      },
      "wallpaperMute": true,
      "performance": {
        "imageOptimizePreset": "balanced",
        "imageOptimizeResolution": "2k",
        "videoConvertPreset": "balanced",
        "videoConvertResolution": "2k",
        "autoOptimizeImages": false,
        "autoConvertVideos": false,
        "imageTrashDays": 7,
        "videoTrashDays": 7,
        "autoDeleteImageTrash": false,
        "autoDeleteVideoTrash": false
      }
    }
    EOF
        fi
  '';

  # STEAM API KEY = "apiKey": "B178602040CA3D9242889895A46A04B8",

  # ============================================================
  # PATCH MPVPAPER OPTIONS — panscan + target main monitor only
  # ============================================================
  home.activation.skwdWallPatchMpv = lib.hm.dag.entryAfter ["cloneSkwdWall"] ''
    ${pkgs.gnused}/bin/sed -i \
      "s|'loop --mute=yes'|'loop --mute=yes --panscan=1.0'|g; \
       s|'loop'|'loop --panscan=1.0'|g; \
       s|'\*'|DP-2|g" \
      "${skwdPath}/qml/services/WallpaperApplyService.qml"
  '';
}
