{ self, inputs, ... }: {
  flake.nixosModules.skwd-wall = { pkgs, activeUser, ... }:
  let
    # Selector opens with the favourites filter pre-enabled — upstream hardcodes
    # the default to false and offers no config knob for it
    skwdPackage = (inputs.skwd-wall.packages.${pkgs.stdenv.hostPlatform.system}.default).overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        # Upstream file contains stray NUL bytes, which substituteInPlace refuses
        # to process — strip them first
        tr -d '\0' < qml/wallpaper/WallpaperSelectorService.qml > wss.tmp
        mv wss.tmp qml/wallpaper/WallpaperSelectorService.qml
        substituteInPlace qml/wallpaper/WallpaperSelectorService.qml \
          --replace-fail "property bool favouriteFilterActive: false" \
                         "property bool favouriteFilterActive: true"
      '';
    });
    # skwd-daemon applies KDE wallpapers via `qdbus6`, but NixOS ships the Qt6
    # tool as plain `qdbus` — without this shim the plasmashell evaluateScript
    # call silently fails and Plasma keeps its previous wallpaper
    qdbus6Shim = pkgs.runCommand "qdbus6-shim" {} ''
      mkdir -p $out/bin
      ln -s ${pkgs.kdePackages.qttools}/bin/qdbus $out/bin/qdbus6
    '';
  in {
    home-manager.users.${activeUser} = { config, lib, hostName, ... }:
    let
      configPath = "${config.home.homeDirectory}/.config/skwd-wall";
      compositor = {
        Sisyphus = "niri";
        # Elektra is gone — that profile became Hosts/Kit-Kat (Niri, separate
        # hardware) and does not import this v1 module at all. Anything unlisted
        # falls through to the "niri" default below.
        Odysseus = "hyprland";
      }.${hostName} or "niri";
      # btop's theme is generated from the same Material You palette as everything
      # else. The template is built in Modules/btop.nix so the fallback theme baked
      # into the store and this rendered one can't drift apart.
      btopTemplate = pkgs.writeText "btop-theme.theme" self.lib.btop.matugenTemplate;
      # Steam's Millennium Quick CSS — one accent triplet, from which the Zehn
      # theme derives ~30 shades. Template lives in Modules/steam.nix alongside
      # the static seed, same as btop's.
      steamTemplate = pkgs.writeText "steam-quick.css" self.lib.steam.matugenTemplate;
    in {
      # ============================================================
      # PACKAGE
      # ============================================================
      home.packages = [ skwdPackage pkgs.matugen ]
        ++ lib.optional (compositor == "kde") qdbus6Shim
        ++ [
          # swaybg is only needed for the script below, which only v1 hosts use.
          pkgs.swaybg

          # noctalia-sync-wallpaper — MOVED HERE from Modules/noctalia.nix on
          # 2026-09-15, because it is now a v1-only concern and noctalia.nix is
          # shared with Sisyphus.
          #
          # Sisyphus (skwd v2) no longer has or needs it: skwd renders noctalia's
          # palette directly and re-reads it via noctalia-apply-palette, and the
          # niri overview backdrop is served by skwd's native skwd-paper-backdrop
          # surface instead of swaybg. On v1 none of that exists, so this script
          # stays exactly as it was — noctalia generates its own Material You
          # colours and has to be pointed at the right image.
          #
          # It is registered as a postProcessing hook further down THIS file, so
          # the script and its registration now live together.
          #
          # Elektra imports this module without noctalia, so the `noctalia msg`
          # calls fail there — unchanged from before, since the hook was already
          # registered unconditionally and failed the same way.
          #
          # Binaries by store path: skwd-daemon runs hooks with a trimmed PATH, so
          # bare pgrep/ps/sleep are not guaranteed to resolve.
          (pkgs.writeShellScriptBin "noctalia-sync-wallpaper" ''
            # $1 is skwd's %path% placeholder — the wallpaper just applied.
            # Reading the cache instead is WRONG during a live change: skwd writes
            # last-wallpaper.json AFTER running its hooks (measured 2026-08-16),
            # so every swap would sync the PREVIOUS wallpaper. The cache is a
            # fallback for manual invocation only, where nothing is in flight.
            #
            # Do NOT re-derive from `skwd status`: that field is null on a fresh
            # session and has no directory component. A grep/sed version once
            # yielded the literal '"current_wallpaper": null,' as a filename.
            WALL="$1"
            if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
              CACHE="$HOME/.cache/skwd-wall/last-wallpaper.json"
              [ -f "$CACHE" ] || exit 0
              WALL=$(${pkgs.jq}/bin/jq -r '.path // empty' "$CACHE" 2>/dev/null)
            fi
            [ -n "$WALL" ] && [ -f "$WALL" ] || exit 0

            # Skip the expensive wallpaper-set if noctalia started <10s ago: it
            # already has last session's cached colours, and wallpaper-set blocks
            # rendering ~5s at startup.
            NOCTALIA_PID=$(${pkgs.procps}/bin/pgrep -x noctalia 2>/dev/null || true)
            PROC_AGE=$(${pkgs.procps}/bin/ps -o etimes= -p "$NOCTALIA_PID" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d ' ')
            if [ -z "$PROC_AGE" ] || [ "$PROC_AGE" -gt 10 ]; then
              noctalia msg wallpaper-set "$WALL"
            fi

            # Swap the swaybg backdrop. Record current PIDs FIRST, start the
            # replacement, then kill only those — a blanket pkill afterwards could
            # take out the new instance, and killing first leaves a black frame.
            # Match on the command line (-f): nixpkgs wraps swaybg, so comm is
            # ".swaybg-wrapped" and -x swaybg never matches.
            OLD=$(${pkgs.procps}/bin/pgrep -f 'swaybg -m fill -i' 2>/dev/null || true)
            ${pkgs.swaybg}/bin/swaybg -m fill -i "$WALL" &
            ${pkgs.coreutils}/bin/sleep 0.3
            [ -n "$OLD" ] && kill $OLD 2>/dev/null || true

            noctalia msg templates-apply
          '')
        ];

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
  "compositor": "${compositor}",
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
            # Compositor is host-determined (niri/kde/hyprland) — keep existing configs in sync
            .compositor = "${compositor}" |
            # Persist last position when reopening selector (saves cursor across show/hide)
            .general = ((.general // {}) | .reopenAtLastSelection = true) |
            # Remove zen integrations (their output paths contain literal \n which corrupts generated TOML)
            .integrations = ((.integrations // []) | map(select(.name != "zen" and .name != "zen-content"))) |
            # Add skwd-wall built-in integration if missing (needed for UI colors)
            if (.integrations | map(.name) | contains(["skwd-wall"])) | not then
              .integrations = [{"name": "skwd-wall", "template": "quickshell-colors.json", "output": "colors.json"}] + .integrations
            else . end
          ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
            && mv "${configPath}/config.json.tmp" "${configPath}/config.json"
        fi

        # Add the noctalia integration (template only — no reload command).
        # noctalia-sync-wallpaper: tells noctalia the actual skwd-wall wallpaper path so it
        # generates Material You colors from the correct image, then re-applies theme templates.
        #
        # It is wired as a postProcessing command, NOT integrations[].reload, because only
        # postProcessing substitutes placeholders (%path% = the wallpaper just applied).
        # reload commands get no arguments, which forced the script to read
        # ~/.cache/skwd-wall/last-wallpaper.json — a file skwd writes AFTER running its
        # hooks, so every swap synced the previous wallpaper. See the comment on
        # noctalia-sync-wallpaper in Modules/noctalia.nix for the measurement.
        if [ -f "${configPath}/config.json" ]; then
          ${pkgs.jq}/bin/jq '
            (if (.integrations | map(.name) | contains(["noctalia"])) then
              .integrations = (.integrations | map(if .name == "noctalia" then
                del(.reload)
              else . end))
            else
              .integrations += [{"name": "noctalia", "template": "noctalia-colors.json", "output": "~/.config/noctalia/colors.json"}]
            end)
            # Idempotent: drop any previous form of this hook, then append the current one.
            | .postProcessing = (((.postProcessing // [])
                | map(select((.command // "") | test("noctalia-sync-wallpaper") | not)))
                + [{"command": "noctalia-sync-wallpaper %path%", "type": "all"}])
            # Fire the hook on session restore too. The reload command used to run at
            # login; without this the palette would only resync on a manual swap.
            # noctalia-sync-wallpaper skips the expensive wallpaper-set when noctalia is
            # under 10s old, so this stays cheap at startup.
            | .postProcessOnRestore = true
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

        # Add the btop integration, or patch its reload command.
        # btop-reload-theme sends SIGUSR2, btop's hot-reload signal — a running
        # instance re-reads the freshly rendered theme off disk without restarting.
        if [ -f "${configPath}/config.json" ]; then
          ${pkgs.jq}/bin/jq '
            if (.integrations | map(.name) | contains(["btop"])) then
              .integrations = (.integrations | map(if .name == "btop" then
                .reload = "btop-reload-theme"
              else . end))
            else
              .integrations += [{"name": "btop", "template": "btop-theme.theme", "output": "~/.config/btop/themes/${self.lib.btop.themeName}.theme", "reload": "btop-reload-theme"}]
            end
          ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
            && mv "${configPath}/config.json.tmp" "${configPath}/config.json"
        fi

        # Add the steam integration (Millennium Quick CSS -> Zehn accent).
        # No reload command: Steam has no way to re-read Quick CSS from outside
        # (Millennium's watcher is an editor-only toggle), so the new accent
        # applies the next time Steam starts.
        if [ -f "${configPath}/config.json" ]; then
          ${pkgs.jq}/bin/jq '
            if (.integrations | map(.name) | contains(["steam"])) | not then
              .integrations += [{"name": "steam", "template": "steam-quick.css", "output": "~/${self.lib.steam.quickCssPath}"}]
            else . end
          ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
            && mv "${configPath}/config.json.tmp" "${configPath}/config.json"
        fi

        # Always sync matugen templates (managed by Nix)
        # Installed from the store rather than a heredoc so the template text lives
        # in exactly one place (Modules/btop.nix). Mode 0644 — matugen only reads it,
        # but a 0444 store copy would break the next rebuild's overwrite.
        install -m 0644 ${btopTemplate} "${configPath}/data/matugen/templates/btop-theme.theme"
        install -m 0644 ${steamTemplate} "${configPath}/data/matugen/templates/steam-quick.css"

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

        cat > "${configPath}/data/matugen/templates/spicetify-colors.json" << 'EOF'
{
  "--spice-text": "{{colors.on_primary_container.default.hex}}",
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
text               = {{colors.on_primary_container.default.hex_stripped}}
EOF

      '';
    };
  };
}
