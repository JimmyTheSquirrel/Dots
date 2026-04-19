{ inputs, ... }: {
  flake.nixosModules.skwd-wall = { pkgs, activeUser, ... }:
  let
    skwdPackage = inputs.skwd-wall.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in {
    home-manager.users.${activeUser} = { config, lib, ... }:
    let
      configPath = "${config.home.homeDirectory}/.config/skwd-wall";
    in {
      # ============================================================
      # PACKAGE
      # ============================================================
      home.packages = [ skwdPackage ];

      # ============================================================
      # SYSTEMD SERVICE
      # ============================================================
      systemd.user.services.skwd-daemon = {
        Unit = {
          Description = "SKWD Wallpaper Daemon";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${skwdPackage}/bin/skwd-daemon";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      # ============================================================
      # SEED CONFIG ON FIRST RUN
      # ============================================================
      home.activation.skwdWallConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${configPath}"
        if [ ! -f "${configPath}/config.json" ]; then
          cat > "${configPath}/config.json" << 'EOF'
{
  "compositor": "niri",
  "monitor": "DP-2",
  "paths": {
    "wallpaper": "~/Pictures/Wallpapers",
    "videoWallpaper": "~/Pictures/Wallpapers",
    "cache": "",
    "templates": "",
    "scripts": "",
    "steam": "~/.local/share/Steam",
    "steamWorkshop": "",
    "steamWeAssets": ""
  },
  "features": {
    "matugen": true,
    "ollama": false,
    "steam": true,
    "wallhaven": true
  },
  "colorSource": "magick",
  "ollama": {
    "url": "http://localhost:11434",
    "model": "gemma3:4b"
  },
  "steam": {
    "apiKey": "",
    "username": ""
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
    };
  };
}
