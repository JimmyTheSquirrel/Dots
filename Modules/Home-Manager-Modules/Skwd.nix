{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  ...
}: let
  cfg = config.programs.skwd;

  # --------------------------------------------------------------------------
  # awww compat wrappers — skwd scripts call awww/awww-daemon but we have
  # swww installed. These shims forward the calls transparently.
  # --------------------------------------------------------------------------
  awwwCompat = pkgs.writeShellScriptBin "awww" ''
    exec ${pkgs.swww}/bin/swww "$@"
  '';

  awwwDaemonCompat = pkgs.writeShellScriptBin "awww-daemon" ''
    exec ${pkgs.swww}/bin/swww-daemon "$@"
  '';

  # --------------------------------------------------------------------------
  # skwd source fetched from GitHub into the Nix store
  # --------------------------------------------------------------------------
  skwdPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "skwd";
    version = "git";

    src = pkgs.fetchFromGitHub {
      owner = "liixini";
      repo = "skwd";
      rev = "main";
      hash = "sha256-GuStHN8flJdCk08CxdIa/Cpf1BGa6l4wlzkPQFY5pe4=";
    };

    installPhase = ''
            runHook preInstall

            instdir=$out/share/skwd
            mkdir -p $instdir

            cp shell.qml  $instdir/
            cp -r qml     $instdir/
            cp -r ext     $instdir/
            cp -r images  $instdir/
            cp -r scripts $instdir/
            cp -r data    $instdir/

            chmod +x $instdir/scripts/bash/*
            chmod +x $instdir/scripts/python/*
            rm -rf $instdir/scripts/.venv $instdir/scripts/python/__pycache__

            mkdir -p $out/bin
            cat > $out/bin/skwd << WRAPPER
      #!/bin/sh
      export SKWD_INSTALL="$out/share/skwd"
      exec quickshell -p "\$HOME/.config/skwd" "\$@"
      WRAPPER
            chmod 755 $out/bin/skwd

            runHook postInstall
    '';

    meta = {
      description = "A skewed take on desktop shells — Quickshell/QML";
      homepage = "https://github.com/liixini/skwd";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };

  # --------------------------------------------------------------------------
  # Python env
  # --------------------------------------------------------------------------
  pythonEnv = pkgs.python3.withPackages (ps:
    with ps; [
      requests
      pillow
    ]);
in {
  # ============================================================
  # Options
  # ============================================================
  options.programs.skwd = {
    enable = lib.mkEnableOption "skwd — A Skewed Quickshell desktop shell";

    compositor = lib.mkOption {
      type = lib.types.enum ["hyprland" "niri" "sway"];
      default = "hyprland";
      description = "Wayland compositor skwd will run on.";
    };

    weatherCity = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Stockholm";
      description = "City name for the weather widget in the bar.";
    };

    wifiInterface = lib.mkOption {
      type = lib.types.str;
      default = "wlan0";
      description = "Network interface for the Wi-Fi widget (confirm with: ip link).";
    };

    preferredMusicPlayer = lib.mkOption {
      type = lib.types.str;
      default = "spotify";
      description = "Preferred playerctl media player name.";
    };

    enableOllama = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ollama for local LLM wallpaper analysis/tagging.";
    };

    enableWallpaperEngine = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable linux-wallpaperengine (Steam Wallpaper Engine).";
    };

    enableGrim = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable grim for window-switcher screenshots.";
    };
  };

  # ============================================================
  # Implementation
  # ============================================================
  config = lib.mkIf cfg.enable {
    # ----------------------------------------------------------
    # Packages
    # ----------------------------------------------------------
    home.packages = with pkgs;
      [
        # ── Quickshell from nixpkgs-unstable ──────────────────
        pkgs-unstable.quickshell

        # ── Qt6 runtime deps (must match unstable quickshell) ─
        pkgs-unstable.qt6.qtbase
        pkgs-unstable.qt6.qtconnectivity
        pkgs-unstable.qt6.qtmultimedia
        pkgs-unstable.qt6.qtwayland

        # ── skwd files ────────────────────────────────────────
        skwdPackage

        # ── Python ────────────────────────────────────────────
        pythonEnv

        # ── CLI tools ─────────────────────────────────────────
        jq
        ffmpeg
        parallel
        matugen
        playerctl
        cava
        libnotify
        mpvpaper
        imagemagick
        swww # wallpaper daemon
        awwwCompat # awww → swww shim (skwd scripts call awww)
        awwwDaemonCompat # awww-daemon → swww-daemon shim

        # ── Fonts ─────────────────────────────────────────────
        roboto
        nerd-fonts.roboto-mono
        nerd-fonts.symbols-only
      ]
      ++ lib.optional cfg.enableOllama pkgs-unstable.ollama
      ++ lib.optional cfg.enableWallpaperEngine pkgs.linux-wallpaperengine
      ++ lib.optional cfg.enableGrim pkgs.grim;

    # ----------------------------------------------------------
    # Put skwd files into ~/.config/skwd
    # ----------------------------------------------------------
    xdg.configFile."skwd" = {
      source = "${skwdPackage}/share/skwd";
      recursive = true;
    };

    # ----------------------------------------------------------
    # Generate config.json from module options
    # ----------------------------------------------------------
    xdg.configFile."skwd/data/config.json".text = builtins.toJSON {
      compositor = "hyprland";
      terminal = "kitty";
      monitor = "DP-2";
      wallpaperMute = true;
      paths = {
        cache = "~/.cache/skwd";
        wallpaper = "~/Pictures/Wallpapers";
      };
      ollama = {
        url = "http://localhost:11434";
        model = "gemma3:4b";
      };
      components = {
        bar = {enabled = false;};
        lockscreen = false;
        appLauncher = true;
        wallpaperSelector = {
          enabled = true;
          showColorDots = false;
        };
        windowSwitcher = true;
        powerMenu = {
          enabled = true;
          items = [
            {
              action = "lock";
              icon = "\uf023";
              label = "";
            }
            {
              action = "logout";
              icon = "\uf2f5";
              label = "";
            }
            {
              action = "reboot";
              icon = "\uf2f9";
              label = "";
            }
            {
              action = "poweroff";
              icon = "\uf011";
              label = "";
            }
          ];
        };
        smartHome = false;
        notifications = true;
      };
    };

    # ----------------------------------------------------------
    # Hyprland autostart + keybindings
    # ----------------------------------------------------------
    wayland.windowManager.hyprland.settings = {
      exec-once = [
        "swww-daemon"
        "skwd"
        "~/.config/skwd/scripts/bash/restore-wallpaper"
      ];

      bind = [
        # ── skwd launchers ────────────────────────────────
        #"SUPER, W, exec, echo wallpaper   > $XDG_RUNTIME_DIR/skwd/cmd"
        #"SUPER, D, exec, echo applauncher > $XDG_RUNTIME_DIR/skwd/cmd"

        # ── other skwd commands ───────────────────────────
        #"SUPER, L,       exec, echo lock      > $XDG_RUNTIME_DIR/skwd/cmd"
        #"SUPER SHIFT, L, exec, echo powermenu > $XDG_RUNTIME_DIR/skwd/cmd"
        #"SUPER, T,       exec, echo toggleBar > $XDG_RUNTIME_DIR/skwd/cmd"
        #"SUPER SHIFT, S, exec, echo smarthome > $XDG_RUNTIME_DIR/skwd/cmd"

        # ── window switcher ───────────────────────────────
        #"ALT, Tab,       exec, echo switcherNext    > $XDG_RUNTIME_DIR/skwd/cmd"
        #"ALT SHIFT, Tab, exec, echo switcherPrev    > $XDG_RUNTIME_DIR/skwd/cmd"
        #"ALT, Return,    exec, echo switcherConfirm > $XDG_RUNTIME_DIR/skwd/cmd"
        #"ALT, Escape,    exec, echo switcherCancel  > $XDG_RUNTIME_DIR/skwd/cmd"
        #"ALT, C,         exec, echo switcherClose   > $XDG_RUNTIME_DIR/skwd/cmd"
      ];
    };

    # ----------------------------------------------------------
    # Session environment
    # ----------------------------------------------------------
    home.sessionVariables = {
      SKWD_INSTALL = "${skwdPackage}/share/skwd";
    };
  };
}
