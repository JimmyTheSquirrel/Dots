{ inputs, ... }: {
  flake.homeModules.skwd = { config, pkgs, pkgs-unstable, lib, ... }:
  let
    skwdPath = "${config.home.homeDirectory}/.config/skwd";
  in {
    # ============================================================
    # PACKAGES
    # ============================================================
    home.packages = with pkgs; [
      # Core
      inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
      pkgs-unstable.qt6.qtmultimedia
      pkgs-unstable.qt6.qtconnectivity

      # CLI tools
      curl
      jq
      sqlite
      ffmpeg
      imagemagick
      inotify-tools
      matugen
      playerctl
      parallel
      cava
      mpvpaper
      psmisc  # provides fuser, killall

      # Python
      (python3.withPackages (ps: with ps; [
        requests
        pillow
      ]))

      # Fonts
      nerd-fonts.symbols-only
      roboto
      roboto-mono
      material-design-icons
    ];

    # ============================================================
    # CLONE REPO ON ACTIVATION
    # ============================================================
    home.activation.cloneSkwd = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ ! -d "${skwdPath}" ]; then
        ${pkgs.git}/bin/git clone https://github.com/liixini/skwd "${skwdPath}"
      fi
    '';

    # ============================================================
    # SEED CONFIG ON FIRST CLONE
    # ============================================================
    home.activation.skwdConfig = lib.hm.dag.entryAfter ["cloneSkwd"] ''
      mkdir -p "${skwdPath}/data"
      if [ ! -f "${skwdPath}/data/config.json" ]; then
        cat > "${skwdPath}/data/config.json" << 'EOF'
{
  "compositor": "niri",
  "monitor": "DP-2",
  "paths": {
    "scripts": "",
    "cache": "~/.cache/skwd",
    "wallpaper": "~/Pictures/Wallpapers",
    "steamWorkshop": "",
    "steamWeAssets": "",
    "steam": "~/.local/share/Steam"
  },
  "ollama": {
    "url": "http://localhost:11434",
    "model": "gemma3:4b"
  },
  "matugen": {
    "schemeType": "scheme-fidelity"
  },
  "intervals": {
    "weatherPollMs": 600000,
    "wifiPollMs": 10000,
    "smartHomePollMs": 5000,
    "ollamaStatusPollMs": 5000,
    "notificationExpireMs": 8000
  },
  "terminal": "kitty",
  "wallpaperMute": true,
  "components": {
    "bar": {
      "enabled": false
    },
    "lockscreen": false,
    "appLauncher": true,
    "wallpaperSelector": {
      "enabled": true,
      "showColorDots": true
    },
    "windowSwitcher": true,
    "powerMenu": {
      "enabled": true,
      "items": [
        { "action": "lock", "icon": "\uf023", "label": "" },
        { "action": "logout", "icon": "\uf2f5", "label": "" },
        { "action": "reboot", "icon": "\uf2f9", "label": "" },
        { "action": "poweroff", "icon": "\uf011", "label": "" }
      ]
    },
    "smartHome": false,
    "notifications": true
  }
}
EOF
      fi
    '';

    # ============================================================
    # CREATE SKWD WRAPPER SCRIPT
    # ============================================================
    home.file.".local/bin/skwd" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        SKWD_DIR="${skwdPath}"

        case "$1" in
          "")
            exec quickshell -p "$SKWD_DIR/shell.qml"
            ;;
          "ipc")
            shift
            exec quickshell -p "$SKWD_DIR/shell.qml" ipc "$@"
            ;;
          *)
            # Send command to FIFO
            FIFO="$XDG_RUNTIME_DIR/skwd/cmd"
            if [ -p "$FIFO" ]; then
              echo "$1" > "$FIFO"
            else
              echo "SKWD not running or FIFO not found"
              exit 1
            fi
            ;;
        esac
      '';
    };

    # ============================================================
    # PATCH FOR NIRI COMPATIBILITY
    # ============================================================
    home.activation.skwdPatchMpv = lib.hm.dag.entryAfter ["cloneSkwd"] ''
      if [ -f "${skwdPath}/qml/services/WallpaperApplyService.qml" ]; then
        ${pkgs.gnused}/bin/sed -i \
          "s|'loop --mute=yes'|'loop --mute=yes --panscan=1.0'|g; \
           s|'loop'|'loop --panscan=1.0'|g; \
           s|'\*'|DP-2|g" \
          "${skwdPath}/qml/services/WallpaperApplyService.qml" 2>/dev/null || true
      fi
    '';

    # ============================================================
    # PATCH FOR NIXOS DESKTOP FILE PATHS
    # ============================================================
    home.activation.skwdPatchNixos = lib.hm.dag.entryAfter ["cloneSkwd"] ''
      # Patch Python script to include NixOS desktop/icon paths
      PYFILE="${skwdPath}/scripts/python/build-app-cache"
      if [ -f "$PYFILE" ]; then
        # Add NixOS desktop dirs after the flatpak line
        if ! grep -q "run/current-system" "$PYFILE"; then
          ${pkgs.gnused}/bin/sed -i \
            '/Path.home.*flatpak.*applications/a\    Path("/run/current-system/sw/share/applications"),\n    Path("/etc/profiles/per-user/${config.home.username}/share/applications"),' \
            "$PYFILE"
        fi

        # Add NixOS icon dirs after the /usr/share/icons line
        if ! grep -q "run/current-system.*icons" "$PYFILE"; then
          ${pkgs.gnused}/bin/sed -i \
            '/Path.*\/usr\/share\/icons")/a\    Path("/run/current-system/sw/share/icons/hicolor"),\n    Path("/run/current-system/sw/share/pixmaps"),\n    Path("/etc/profiles/per-user/${config.home.username}/share/icons/hicolor"),' \
            "$PYFILE"
        fi
      fi

      # Patch QML watcher to include NixOS paths
      QMLFILE="${skwdPath}/qml/launcher/AppLauncherService.qml"
      if [ -f "$QMLFILE" ]; then
        if ! grep -q "run/current-system" "$QMLFILE"; then
          ${pkgs.gnused}/bin/sed -i \
            's|/var/lib/flatpak/exports/share/applications|/var/lib/flatpak/exports/share/applications /run/current-system/sw/share/applications /etc/profiles/per-user/${config.home.username}/share/applications|g' \
            "$QMLFILE"
        fi
      fi
    '';

    # ============================================================
    # FIX MATUGEN TILDE EXPANSION BUG
    # ============================================================
    home.activation.skwdFixMatugen = lib.hm.dag.entryAfter ["cloneSkwd"] ''
      # Fix the config.toml.in template to use $HOME instead of ~
      TEMPLATE="${skwdPath}/ext/matugen/config.toml.in"
      if [ -f "$TEMPLATE" ]; then
        ${pkgs.gnused}/bin/sed -i 's|"~/|"${config.home.homeDirectory}/|g' "$TEMPLATE"
      fi

      # Regenerate the matugen config with fixed paths
      CACHE="${config.home.homeDirectory}/.cache/skwd"
      mkdir -p "$CACHE"
      CONFIG="${skwdPath}/data/config.json"
      MATUGEN_CONFIG="$CACHE/matugen-config.toml"

      if [ -f "$TEMPLATE" ] && [ -f "$CONFIG" ]; then
        # Read integration paths (empty = disabled)
        int_kitty=$(${pkgs.jq}/bin/jq -r '.integrations.kitty // ""' "$CONFIG")
        int_kde=$(${pkgs.jq}/bin/jq -r '.integrations.kde // ""' "$CONFIG")
        int_vscode=$(${pkgs.jq}/bin/jq -r '.integrations.vscode // ""' "$CONFIG")
        int_vesktop=$(${pkgs.jq}/bin/jq -r '.integrations.vesktop // ""' "$CONFIG")
        int_zen=$(${pkgs.jq}/bin/jq -r '.integrations.zen // ""' "$CONFIG")
        int_spicetify=$(${pkgs.jq}/bin/jq -r '.integrations.spicetify // ""' "$CONFIG")
        int_spicetify_css=$(${pkgs.jq}/bin/jq -r '.integrations.spicetifyCss // ""' "$CONFIG")
        int_yazi=$(${pkgs.jq}/bin/jq -r '.integrations.yazi // ""' "$CONFIG")
        int_qt6ct=$(${pkgs.jq}/bin/jq -r '.integrations.qt6ct // ""' "$CONFIG")

        ${pkgs.gnused}/bin/sed \
          -e "s|@SKWD_INSTALL@|${skwdPath}|g" \
          -e "s|@OUTPUT_KITTY@|$int_kitty|g" \
          -e "s|@OUTPUT_KDE@|$int_kde|g" \
          -e "s|@OUTPUT_VSCODE@|$int_vscode|g" \
          -e "s|@OUTPUT_VESKTOP@|$int_vesktop|g" \
          -e "s|@OUTPUT_ZEN@|$int_zen|g" \
          -e "s|@OUTPUT_SPICETIFY@|$int_spicetify|g" \
          -e "s|@OUTPUT_SPICETIFYCSS@|$int_spicetify_css|g" \
          -e "s|@OUTPUT_YAZI@|$int_yazi|g" \
          -e "s|@OUTPUT_QT6CT@|$int_qt6ct|g" \
          "$TEMPLATE" > "$MATUGEN_CONFIG.tmp"

        # Remove template blocks where output_path is empty
        ${pkgs.python3}/bin/python3 -c "
import re, sys
text = open(sys.argv[1]).read()
# Match template blocks with empty output_path, handling varying whitespace
text = re.sub(r'\n*\[templates\.[^\]]+\]\s*\ninput_path\s*=\s*\"[^\"]*\"\s*\noutput_path\s*=\s*\"\"\s*\n*', '\n', text)
open(sys.argv[1], 'w').write(text)
" "$MATUGEN_CONFIG.tmp"

        mv "$MATUGEN_CONFIG.tmp" "$MATUGEN_CONFIG"
      fi
    '';

  };
}
