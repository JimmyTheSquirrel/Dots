{ self, inputs, ... }: {
  flake.nixosModules.niri = { pkgs, lib, ... }: {
    programs.niri = {
      enable = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.wrappedNiri;
    };

    services.xserver.enable = true;
    services.xserver.videoDrivers = [ "amdgpu" ];
    services.xserver.xkb = {
      layout = "au";
      variant = "";
    };

    services.displayManager.sddm.enable = true;
    services.displayManager.defaultSession = "niri";
    services.displayManager.sddm.settings.General = {
      CursorTheme = "Bibata-Modern-Classic";
      CursorSize = 24;
    };

    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common.default = "gtk";
    };

    xdg.mime = {
      enable = true;
      defaultApplications = {
        "text/plain" = [ "codium.desktop" ];
        "text/x-nix" = [ "codium.desktop" ];
        "text/markdown" = [ "codium.desktop" ];
        "application/json" = [ "codium.desktop" ];
        "application/x-yaml" = [ "codium.desktop" ];
        "application/toml" = [ "codium.desktop" ];
        "text/yaml" = [ "codium.desktop" ];
      };
    };

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XCURSOR_THEME = "Bibata-Modern-Classic";
      XCURSOR_SIZE = "24";
      GTK_USE_PORTAL = "1";
    };

    hardware.bluetooth.enable = true;
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    environment.systemPackages = with pkgs; [
      xwayland-satellite
      playerctl
      kdePackages.qttools  # Provides qdbus6 for Noctalia D-Bus calls
      # Wrapped steam with GPU workaround for niri
      (lib.hiPrio (writeShellScriptBin "steam" ''
        exec ${steam}/bin/steam -no-cef-sandbox "$@"
      ''))
      # Wrapped spotify: GPU workaround + navigate to Liked Songs via D-Bus
      (lib.hiPrio (writeShellScriptBin "spotify" ''
        LIKED_SONGS="spotify:collection:tracks"

        # Check if Spotify is already running
        if ! pgrep -x spotify >/dev/null; then
          # First launch - start Spotify then navigate via D-Bus after it's ready
          /etc/profiles/per-user/rock/bin/spotify \
            --disable-gpu-sandbox --use-gl=angle --use-angle=swiftshader "$@" &
          SPOTIFY_PID=$!
          # Wait for D-Bus interface to become available, then open Liked Songs
          (for i in $(seq 1 30); do
            sleep 1
            if qdbus6 org.mpris.MediaPlayer2.spotify / org.freedesktop.MediaPlayer2.OpenUri "$LIKED_SONGS" 2>/dev/null; then
              break
            fi
          done) &
          wait $SPOTIFY_PID
        else
          # Already running - navigate via D-Bus
          qdbus6 org.mpris.MediaPlayer2.spotify / org.freedesktop.MediaPlayer2.OpenUri "$LIKED_SONGS" 2>/dev/null || true
        fi
      ''))
      # SKWD shell daemon launcher (niri spawn-at-startup needs single executable)
      (writeShellScriptBin "skwd-daemon" ''
        exec ${inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/quickshell -p /home/rock/.config/skwd/shell.qml "$@"
      '')
      # SKWD wallpaper restore (run on startup to restore last wallpaper)
      (writeShellScriptBin "skwd-wallpaper-restore" ''
        # Wait for SKWD FIFO to exist (indicates SKWD is ready)
        FIFO="$XDG_RUNTIME_DIR/skwd/cmd"
        for i in $(seq 1 50); do
          [ -p "$FIFO" ] && break
          sleep 0.1
        done
        export SKWD_CACHE="''${XDG_CACHE_HOME:-$HOME/.cache}/skwd"
        export SKWD_CONFIG="''${XDG_CONFIG_HOME:-$HOME/.config}/skwd"
        exec /home/rock/.config/skwd/scripts/bash/restore-wallpaper
      '')
      # Spotify startup launcher (delayed start for session init)
      (writeShellScriptBin "spotify-startup" ''
        sleep 3  # Wait for desktop to initialize
        exec spotify
      '')
    ];

    # Disable GNOME SSH agent to avoid conflict with programs.ssh.startAgent
    services.gnome.gcr-ssh-agent.enable = false;
  };

  perSystem = { pkgs, lib, self', ... }: {
    packages.wrappedNiri = inputs.wrapper-modules.wrappers.niri.wrap {
      inherit pkgs;
      settings = {
        # Disable client-side decorations
        prefer-no-csd = _: {};

        # Screenshot save location
        screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

        spawn-at-startup = [
          # Launch shell/bar and wallpaper first for instant visual feedback
          (lib.getExe self'.packages.wrappedNoctalia)
          "skwd-daemon"
          "skwd-wallpaper-restore"
          # D-Bus environment setup runs in background (& at end)
          "sh -c 'dbus-update-activation-environment --systemd --all &'"
          "sh -c 'systemctl --user import-environment --all &'"
          "spotify-startup"
        ];

        xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

        # Input settings
        input.keyboard.xkb.layout = "us";
        input.mouse.accel-profile = "flat";
        input.focus-follows-mouse = _: {};
        input.touchpad.tap = _: {};

        # Layout
        layout.gaps = 4;
        layout.center-focused-column = "never";
        layout.focus-ring.width = 0;  # Disable focus ring (using border instead)
        layout.border.width = 4;
        layout.border.active-color = "#555555";
        layout.border.inactive-color = "#555555";


        # Default column width (100% = full monitor width)
        layout.default-column-width.proportion = 1.0;

        # Window rules as raw KDL (wrapper-modules can't generate the correct match syntax)
        extraConfig = ''
          gestures {
            hot-corners {
              off
            }
          }

          output "DP-2" {
            position x=0 y=1080
          }

          output "HDMI-A-1" {
            position x=320 y=0
          }

          window-rule {
            draw-border-with-background false
            geometry-corner-radius 14
          }
          window-rule {
            match app-id="^thunar$"
            opacity 0.90
          }
          window-rule {
            match app-id="^brave-browser$"
            opacity 0.85
          }
          window-rule {
            match app-id="^codium$"
            opacity 0.80
          }
          window-rule {
            match app-id="^discord$"
            opacity 0.80
          }
          window-rule {
            match app-id="^vesktop$"
            opacity 0.85
          }
          window-rule {
            match app-id="^spotify$"
            opacity 0.90
            open-on-output "HDMI-A-1"
          }
          window-rule {
            match app-id="^pavucontrol$"
            open-floating true
          }
          window-rule {
            match title="^Picture-in-Picture$"
            open-floating true
          }
        '';

        binds = {
          "Mod+Return".spawn-sh = lib.getExe pkgs.kitty;
          "Mod+E".spawn-sh = lib.getExe pkgs.xfce.thunar;
          "Mod+F".spawn-sh = lib.getExe pkgs.brave;
          "Mod+D".spawn-sh = "echo applauncher > $XDG_RUNTIME_DIR/skwd/cmd";
          "Mod+W".spawn-sh = "echo wallpaper > $XDG_RUNTIME_DIR/skwd/cmd";
          "Mod+Shift+Delete".spawn-sh = "noctalia-shell ipc call sessionMenu toggle";
          "Mod+Q".close-window = _: {};
          "Mod+V".toggle-window-floating = _: {};
          "Mod+Shift+F".fullscreen-window = _: {};
          "Mod+F11".fullscreen-window = _: {};
          "Mod+J".switch-preset-column-width = _: {};
          "Mod+R".reset-window-height = _: {};
          "Mod+A".toggle-overview = _: {};
          "Mod+Shift+Slash".show-hotkey-overlay = _: {};
          "Mod+Left".focus-column-left = _: {};
          "Mod+Right".focus-column-right = _: {};
          "Mod+Up".focus-workspace-up = _: {};
          "Mod+Down".focus-workspace-down = _: {};
          "Mod+1".focus-workspace = 1;
          "Mod+2".focus-workspace = 2;
          "Mod+3".focus-workspace = 3;
          "Mod+4".focus-workspace = 4;
          "Mod+5".focus-workspace = 5;
          "Mod+Shift+Left".move-column-left = _: {};
          "Mod+Shift+Right".move-column-right = _: {};
          "Mod+Shift+Up".spawn-sh = "niri msg action move-column-to-workspace-up";
          "Mod+Shift+Down".spawn-sh = "niri msg action move-column-to-workspace-down";
          "Mod+Shift+1".spawn-sh = "niri msg action move-column-to-workspace 1";
          "Mod+Shift+2".spawn-sh = "niri msg action move-column-to-workspace 2";
          "Mod+Shift+3".spawn-sh = "niri msg action move-column-to-workspace 3";
          "Mod+Shift+4".spawn-sh = "niri msg action move-column-to-workspace 4";
          "Mod+Shift+5".spawn-sh = "niri msg action move-column-to-workspace 5";
          "Mod+WheelScrollDown".focus-column-right = _: {};
          "Mod+WheelScrollUp".focus-column-left = _: {};
          "Mod+Shift+S".spawn-sh = "grim -g \"$(slurp)\" - | wl-copy";
          "Mod+S".spawn-sh = "grim - | wl-copy";
          "XF86AudioRaiseVolume".spawn-sh = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+";
          "XF86AudioLowerVolume".spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
          "XF86AudioMute".spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          "XF86AudioMicMute".spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          "XF86AudioNext".spawn-sh = "playerctl next";
          "XF86AudioPrev".spawn-sh = "playerctl previous";
          "XF86AudioPlay".spawn-sh = "playerctl play-pause";
          "XF86AudioPause".spawn-sh = "playerctl play-pause";
        };
      };
    };
  };
}
