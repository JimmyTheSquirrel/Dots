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
        mkdir -p "${configPath}/data/matugen/templates"

        # Seed config.json on first run only
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
    "schemeType": "scheme-tonal-spot",
    "mode": "dark"
  },
  "integrations": [
    {
      "name": "skwd-wall",
      "template": "quickshell-colors.json",
      "output": "colors.json"
    },
    {
      "name": "noctalia",
      "template": "noctalia-colors.json",
      "output": "~/.config/noctalia/colors.json",
      "reload": "noctalia-shell ipc call colorScheme refresh"
    }
  ],
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

        # Always patch integrations: ensure skwd-wall built-in + noctalia reload
        if [ -f "${configPath}/config.json" ]; then
          ${pkgs.jq}/bin/jq '
            # Remove zen integrations (broken paths cause matugen TOML parse errors)
            .integrations = ((.integrations // []) | map(select(.name != "zen" and .name != "zen-content"))) |
            # Fix noctalia reload (colorScheme refresh was removed; wallpaper refresh triggers re-read)
            .integrations = (
              .integrations |
              map(if .name == "noctalia" then
                .reload = "noctalia-shell ipc call wallpaper refresh"
              else . end)
            ) |
            # Add skwd-wall built-in integration if missing (needed for UI colors)
            if (.integrations | map(.name) | contains(["skwd-wall"])) | not then
              .integrations = [{"name": "skwd-wall", "template": "quickshell-colors.json", "output": "colors.json"}] + .integrations
            else . end
          ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
            && mv "${configPath}/config.json.tmp" "${configPath}/config.json"
        fi

        # Always sync the matugen template (managed by Nix)
        cat > "${configPath}/data/matugen/templates/noctalia-colors.json" << 'EOF'
{
  "mPrimary": "{{colors.primary.default.hex}}",
  "mOnPrimary": "{{colors.on_primary.default.hex}}",

  "mSecondary": "{{colors.secondary.default.hex}}",
  "mOnSecondary": "{{colors.on_secondary.default.hex}}",

  "mTertiary": "{{colors.tertiary.default.hex}}",
  "mOnTertiary": "{{colors.on_tertiary.default.hex}}",

  "mError": "{{colors.error.default.hex}}",
  "mOnError": "{{colors.on_error.default.hex}}",

  "mSurface": "#0a0a0a",
  "mOnSurface": "#e0e0e0",

  "mSurfaceVariant": "#1a1a1a",
  "mOnSurfaceVariant": "#c0c0c0",

  "mOutline": "#333333",
  "mShadow": "#000000",

  "mHover": "{{colors.tertiary.default.hex}}",
  "mOnHover": "{{colors.on_tertiary.default.hex}}"
}
EOF
      '';
    };
  };
}
