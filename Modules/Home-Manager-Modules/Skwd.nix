# Skewd.nix
# Home Manager module for skwd — A Skewed Quickshell desktop shell
# https://github.com/liixini/skwd
#
# ── How to wire this in ──────────────────────────────────────────────────────
#
# 1. In your flake.nix, pass pkgs-unstable via extraSpecialArgs:
#
#      home-manager.extraSpecialArgs = {
#        inherit inputs activeUser;
#        pkgs-unstable = import nixpkgs-unstable {
#          inherit system;
#          config.allowUnfree = true;
#        };
#      };
#
# 2. In home-manager.sharedModules (or a specific home.nix):
#
#      home-manager.sharedModules = [
#        inputs.plasma-manager.homeModules.plasma-manager
#        (import ./Skewd.nix)
#      ];
#
# 3. Enable in your Sisyphus/home.nix:
#
#      programs.skwd = {
#        enable                = true;
#        compositor            = "hyprland";
#        weatherCity           = "Sydney";
#        wifiInterface         = "wlan0";   # confirm with: ip link
#        enableOllama          = true;
#        enableWallpaperEngine = true;
#        enableGrim            = true;
#      };
#
# 4. nixos-rebuild switch --flake .#rock-Sisyphus
#    (first build will fail with a hash mismatch — paste the printed hash
#     into the `hash` field below and rebuild once more)
#
# 5. Run once after first boot:  ~/.config/skwd/scripts/bash/setup
# ─────────────────────────────────────────────────────────────────────────────

{ config, pkgs, pkgs-unstable, lib, inputs, ... }:

let
  cfg = config.programs.skwd;

  # --------------------------------------------------------------------------
  # skwd source fetched from GitHub into the Nix store
  # --------------------------------------------------------------------------
  skwdPackage = pkgs.stdenvNoCC.mkDerivation {
    pname   = "skwd";
    version = "git";

    src = pkgs.fetchFromGitHub {
      owner = "liixini";
      repo  = "skwd";
      rev   = "main";
      # ⚠ Replace with the real hash after the first failed build, e.g.:
      #   error: hash mismatch ... got: sha256-XXXX
      # Or get it upfront:
      #   nix-prefetch-github liixini skwd --rev main
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
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

      # Launcher — points at ~/.config/skwd so live user edits are picked up
      mkdir -p $out/bin
      cat > $out/bin/skwd << 'WRAPPER'
#!/bin/sh
export SKWD_INSTALL="$out/share/skwd"
exec quickshell -p "$HOME/.config/skwd" "$@"
WRAPPER
      chmod 755 $out/bin/skwd

      runHook postInstall
    '';

    meta = {
      description = "A skewed take on desktop shells — Quickshell/QML";
      homepage    = "https://github.com/liixini/skwd";
      license     = lib.licenses.mit;
      platforms   = lib.platforms.linux;
    };
  };

  # --------------------------------------------------------------------------
  # Python env — syncedlyrics is NOT in nixpkgs yet; the setup script will
  # install it into a venv via pip so we leave it out here.
  # --------------------------------------------------------------------------
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    requests  # HTTP (Ollama, Home Assistant, lrclib)
    pillow    # Image processing for wallpaper thumbnails
  ]);

in {
  # ============================================================
  # Options
  # ============================================================
  options.programs.skwd = {
    enable = lib.mkEnableOption "skwd — A Skewed Quickshell desktop shell";

    compositor = lib.mkOption {
      type    = lib.types.enum [ "hyprland" "niri" "sway" ];
      default = "hyprland";
      description = "Wayland compositor skwd will run on.";
    };

    weatherCity = lib.mkOption {
      type    = lib.types.str;
      default = "";
      example = "Stockholm";
      description = "City name for the weather widget in the bar.";
    };

    wifiInterface = lib.mkOption {
      type    = lib.types.str;
      default = "wlan0";
      description = "Network interface for the Wi-Fi widget (confirm with: ip link).";
    };

    preferredMusicPlayer = lib.mkOption {
      type    = lib.types.str;
      default = "spotify";
      description = "Preferred playerctl media player name.";
    };

    enableOllama = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Enable ollama for local LLM wallpaper analysis/tagging.";
    };

    enableWallpaperEngine = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Enable linux-wallpaperengine (Steam Wallpaper Engine).";
    };

    enableGrim = lib.mkOption {
      type    = lib.types.bool;
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
    home.packages = with pkgs; [

      # ── Quickshell — from nixpkgs-unstable (not in stable 25.11 yet) ──
      pkgs-unstable.quickshell

      # ── Qt6 runtime deps ──────────────────────────────────
      qt6.qtbase
      qt6.qtconnectivity
      qt6.qtmultimedia
      qt6.qtwayland

      # ── skwd files ────────────────────────────────────────
      skwdPackage

      # ── Python ────────────────────────────────────────────
      pythonEnv

      # ── CLI tools ─────────────────────────────────────────
      jq           # JSON parsing in bash scripts
      ffmpeg       # Video frame extraction / thumbnailing
      parallel     # GNU parallel (used by setup script)
      matugen      # Material You colour generation from wallpapers
      playerctl    # Media player control (lyrics, now-playing)
      cava         # Audio visualiser for the lyrics bar
      libnotify    # notify-send desktop notifications
      mpvpaper     # Video wallpaper rendering
      imagemagick  # Image manipulation
      # awww is not in nixpkgs yet — setup script handles it via cargo/git

      # ── Fonts ─────────────────────────────────────────────
      roboto
      nerd-fonts.roboto-mono    # nixpkgs 25.11+ style
      nerd-fonts.symbols-only
      # material-design-icons   # uncomment if available in your nixpkgs

    ]
    ++ lib.optional cfg.enableOllama          pkgs-unstable.ollama
    ++ lib.optional cfg.enableWallpaperEngine pkgs.linux-wallpaperengine
    ++ lib.optional cfg.enableGrim            pkgs.grim;

    # ----------------------------------------------------------
    # Put skwd files into ~/.config/skwd (Home Manager symlinks these)
    # ----------------------------------------------------------
    xdg.configFile."skwd" = {
      source    = "${skwdPackage}/share/skwd";
      recursive = true;
    };

    # ----------------------------------------------------------
    # Generate ~/.config/skwd/data/config.json from module options.
    # The setup script can still override this afterwards.
    # ----------------------------------------------------------
    xdg.configFile."skwd/data/config.json".text = builtins.toJSON {
      compositor = cfg.compositor;
      components = {
        bar = {
          enabled   = true;
          weather   = { city = cfg.weatherCity; };
          wifi      = { interface = cfg.wifiInterface; };
          bluetooth = true;
          volume    = true;
          calendar  = true;
          music = {
            enabled          = true;
            preferredPlayer  = cfg.preferredMusicPlayer;
            visualizer       = "wave";
            visualizerTop    = true;
            visualizerBottom = true;
          };
        };
        lockscreen        = true;
        appLauncher       = true;
        wallpaperSelector = true;
        windowSwitcher    = true;
        powerMenu         = true;
        smartHome         = true;
        notifications     = true;
      };
    };

    # ----------------------------------------------------------
    # Hyprland autostart + keybindings
    # Uncomment if you manage Hyprland entirely through Home Manager,
    # otherwise paste these into your hyprland.conf manually.
    # ----------------------------------------------------------
    # wayland.windowManager.hyprland.extraConfig = ''
    #   exec-once = skwd
    #   exec-once = ~/.config/skwd/scripts/bash/restore-wallpaper
    #
    #   bind = $mainMod, R,       exec, echo applauncher > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = $mainMod, D,       exec, echo toggleBar   > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = $mainMod, T,       exec, echo wallpaper   > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = $mainMod, L,       exec, echo lock        > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = $mainMod, ESCAPE,  exec, echo powermenu   > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = $mainMod SHIFT, L, exec, echo powermenu   > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = $mainMod SHIFT, S, exec, echo smarthome   > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = ALT, TAB,          exec, echo switcherNext    > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = ALT SHIFT, TAB,    exec, echo switcherPrev    > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = ALT, RETURN,       exec, echo switcherConfirm > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = ALT, ESCAPE,       exec, echo switcherCancel  > $XDG_RUNTIME_DIR/skwd/cmd
    #   bind = ALT, C,            exec, echo switcherClose   > $XDG_RUNTIME_DIR/skwd/cmd
    # '';

    # ----------------------------------------------------------
    # Session environment
    # ----------------------------------------------------------
    home.sessionVariables = {
      SKWD_INSTALL = "${skwdPackage}/share/skwd";
    };
  };
}
