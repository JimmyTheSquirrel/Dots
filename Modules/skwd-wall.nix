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

      # Hide from app launchers — skwd-wall is keybind-driven (Meta+W)
      xdg.desktopEntries."skwd-wall" = {
        name = "Skwd-wall";
        exec = "skwd wall toggle";
        noDisplay = true;
      };

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

        # Patch spicetify integrations: color.ini (rebuild-time) + matugen-colors.json (runtime via fs.watchFile)
        if [ -f "${configPath}/config.json" ]; then
          ${pkgs.jq}/bin/jq '
            if (.integrations | map(.name) | contains(["spicetify"])) | not then
              .integrations += [{"name": "spicetify", "template": "spicetify-text.ini", "output": "~/.config/spicetify/Themes/text/color.ini"}]
            else . end |
            # Add spicetify-live integration or patch reload to use CDP injection
            if (.integrations | map(.name) | contains(["spicetify-live"])) then
              .integrations = (.integrations | map(if .name == "spicetify-live" then
                .reload = "spotify-apply-colors"
              else . end))
            else
              .integrations += [{"name": "spicetify-live", "template": "spicetify-colors.json", "output": "~/.config/spicetify/matugen-colors.json", "reload": "spotify-apply-colors"}]
            end
          ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
            && mv "${configPath}/config.json.tmp" "${configPath}/config.json"
        fi

        # Always sync matugen templates (managed by Nix)
        cat > "${configPath}/data/matugen/templates/spicetify-colors.json" << 'EOF'
{
  "--spice-text": "{{colors.on_surface.default.hex}}",
  "--spice-subtext": "{{colors.on_surface_variant.default.hex}}",
  "--spice-main": "{{colors.surface.default.hex}}",
  "--spice-accent": "{{colors.primary.default.hex}}",
  "--spice-accent-active": "{{colors.primary_container.default.hex}}",
  "--spice-accent-inactive": "{{colors.surface.default.hex}}",
  "--spice-banner": "{{colors.primary.default.hex}}",
  "--spice-border-active": "{{colors.primary.default.hex}}",
  "--spice-border-inactive": "{{colors.outline.default.hex}}",
  "--spice-header": "{{colors.primary_container.default.hex}}",
  "--spice-highlight": "{{colors.surface_container.default.hex}}",
  "--spice-notification": "{{colors.primary_container.default.hex}}",
  "--spice-notification-error": "{{colors.error.default.hex}}"
}
EOF

        cat > "${configPath}/data/matugen/templates/spicetify-text.ini" << 'EOF'
[Matugen]
accent             = {{colors.primary.default.hex_stripped}}
accent-active      = {{colors.primary_container.default.hex_stripped}}
accent-inactive    = {{colors.surface.default.hex_stripped}}
banner             = {{colors.primary.default.hex_stripped}}
border-active      = {{colors.primary.default.hex_stripped}}
border-inactive    = {{colors.outline.default.hex_stripped}}
header             = {{colors.primary_container.default.hex_stripped}}
highlight          = {{colors.surface_container.default.hex_stripped}}
main               = {{colors.surface.default.hex_stripped}}
notification       = {{colors.primary_container.default.hex_stripped}}
notification-error = {{colors.error.default.hex_stripped}}
subtext            = {{colors.on_surface_variant.default.hex_stripped}}
text               = {{colors.on_surface.default.hex_stripped}}
EOF

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
