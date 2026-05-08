{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.niri = {
    pkgs,
    lib,
    ...
  }: {
    programs.niri = {
      enable = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.wrappedNiri;
    };

    services.xserver.enable = true;
    services.xserver.videoDrivers = ["amdgpu"];
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
      config.common = {
        default = "gtk";
        "org.freedesktop.impl.portal.ScreenCast" = "gnome";
        "org.freedesktop.impl.portal.Screenshot" = "gnome";
        "org.freedesktop.impl.portal.RemoteDesktop" = "gnome";
      };
    };

    xdg.mime = {
      enable = true;
      defaultApplications = {
        "text/plain" = ["codium.desktop"];
        "text/x-nix" = ["codium.desktop"];
        "text/markdown" = ["codium.desktop"];
        "application/json" = ["codium.desktop"];
        "application/x-yaml" = ["codium.desktop"];
        "application/toml" = ["codium.desktop"];
        "text/yaml" = ["codium.desktop"];
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
      kdePackages.qttools # Provides qdbus6 for Noctalia D-Bus calls
      # Wrapped steam with GPU workaround for niri
      (lib.hiPrio (writeShellScriptBin "steam" ''
        exec ${steam}/bin/steam -no-cef-sandbox "$@"
      ''))
      # Spotify startup launcher: delayed start for session init, opens to liked songs.
      # Used in niri spawn-at-startup — needs the sleep for session initialization.
      (writeShellScriptBin "spotify-startup" ''
        LIKED_SONGS="spotify:collection:tracks"
        sleep 3  # Wait for desktop/session to fully initialize
        exec spotify \
          --disable-gpu-sandbox --use-gl=angle --use-angle=swiftshader \
          --remote-debugging-port=9222 \
          --uri="$LIKED_SONGS"
      '')
      # Spotify manual launcher: no sleep, handles fresh launch + already-running.
      # Used by the .desktop file so the app launcher opens Spotify to liked songs.
      # Avoids infinite recursion by never replacing the 'spotify' binary in PATH.
      (writeShellScriptBin "spotify-open" ''
        LIKED_SONGS="spotify:collection:tracks"
        if ! pgrep -x spotify >/dev/null; then
          # Fresh launch — pass URI directly, Spotify opens straight to playlist
          spotify \
            --disable-gpu-sandbox --use-gl=angle --use-angle=swiftshader \
            --remote-debugging-port=9222 \
            --uri="$LIKED_SONGS" "$@" &
        else
          # Already running — navigate via D-Bus MPRIS
          dbus-send --dest=org.mpris.MediaPlayer2.spotify \
            /org/mpris/MediaPlayer2 \
            org.mpris.MediaPlayer2.Player.OpenUri \
            string:"$LIKED_SONGS" 2>/dev/null || true
        fi
      '')
    ];

    # Override Spotify .desktop so the app launcher uses spotify-open instead of spotify.
    # This means the launcher always opens Liked Songs without touching the spotify binary.
    home-manager.users.rock.xdg.desktopEntries.spotify = {
      name = "Spotify";
      genericName = "Music Player";
      exec = "spotify-open %U";
      icon = "spotify";
      terminal = false;
      categories = ["Audio" "Music" "Player" "AudioVideo"];
      mimeType = ["x-scheme-handler/spotify"];
    };

    # Disable GNOME SSH agent to avoid conflict with programs.ssh.startAgent
    services.gnome.gcr-ssh-agent.enable = false;
  };

  perSystem = {
    pkgs,
    lib,
    self',
    ...
  }: {
    packages.wrappedNiri = let
      baseNiri = inputs.wrapper-modules.wrappers.niri.wrap {
        inherit pkgs;
        settings = {
          # Disable client-side decorations
          prefer-no-csd = _: {};

          # Screenshot save location
          screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

          spawn-at-startup = [
            # Launch shell/bar first for instant visual feedback
            (lib.getExe self'.packages.wrappedNoctalia)
            # D-Bus environment setup runs in background (& at end)
            "sh -c 'dbus-update-activation-environment --systemd --all &'"
            "sh -c 'systemctl --user import-environment --all &'"
            "spotify-startup"
          ];

          xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

          # Cursor
          cursor.xcursor-theme = "Bibata-Modern-Classic";
          cursor.xcursor-size = 24;

          # Input settings
          input.keyboard.xkb.layout = "us";
          input.mouse.accel-profile = "flat";
          input.focus-follows-mouse = _: {};
          input.touchpad.tap = _: {};

          # Layout
          layout.gaps = 4;
          layout.center-focused-column = "never";
          layout.focus-ring.width = 0; # Disable focus ring (using border instead)
          layout.border.width = 2;
          layout.border.active-color = "#333333";
          layout.border.inactive-color = "#333333";

          # Default column width (100% = full monitor width)
          layout.default-column-width.proportion = 1.0;

          # Window rules as raw KDL (wrapper-modules can't generate the correct match syntax)
          extraConfig = ''
            animations {
              window-open {
                duration-ms 1500
                curve "ease-out-cubic"
                custom-shader r"
                  float hash(vec2 p) {
                      return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
                  }

                  float noise(vec2 p) {
                      vec2 i = floor(p);
                      vec2 f = fract(p);
                      f = f * f * (3.0 - 2.0 * f);
                      float a = hash(i);
                      float b = hash(i + vec2(1.0, 0.0));
                      float c = hash(i + vec2(0.0, 1.0));
                      float d = hash(i + vec2(1.0, 1.0));
                      return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
                  }

                  float fbm(vec2 p) {
                      float v = 0.0;
                      float amp = 0.5;
                      for (int i = 0; i < 6; i++) {
                          v += amp * noise(p);
                          p *= 2.0;
                          amp *= 0.5;
                      }
                      return v;
                  }

                  float warpedFbm(vec2 p, float t) {
                      vec2 q = vec2(fbm(p + vec2(0.0, 0.0)),
                                    fbm(p + vec2(5.2, 1.3)));

                      vec2 r = vec2(fbm(p + 6.0 * q + vec2(1.7, 9.2) + 0.25 * t),
                                    fbm(p + 6.0 * q + vec2(8.3, 2.8) + 0.22 * t));

                      vec2 s = vec2(fbm(p + 5.0 * r + vec2(3.1, 7.4) + 0.18 * t),
                                    fbm(p + 5.0 * r + vec2(6.7, 0.9) + 0.2 * t));

                      return fbm(p + 6.0 * s);
                  }

                  vec4 open_color(vec3 coords_geo, vec3 size_geo) {
                      float p = niri_clamped_progress;
                      vec2 uv = coords_geo.xy;
                      float seed = niri_random_seed * 100.0;

                      float t = p * 12.0 + seed;

                      float fluid = warpedFbm(uv * 2.0 + seed, t);

                      vec2 center = uv - 0.5;
                      float dist = length(center * vec2(1.0, 0.7));

                      float appear = (1.0 - dist * 1.2) + (1.0 - fluid) * 0.7;
                      float reveal = smoothstep(appear + 0.5, appear - 0.5, (1.0 - p) * 1.8);

                      float distort_strength = (1.0 - p) * (1.0 - p) * 0.35;
                      vec2 wq = vec2(fbm(uv * 2.0 + vec2(0.0, t * 0.2)),
                                     fbm(uv * 2.0 + vec2(5.2, t * 0.2)));
                      vec2 wr = vec2(fbm(uv * 2.0 + 4.0 * wq + vec2(1.7, 9.2)),
                                     fbm(uv * 2.0 + 4.0 * wq + vec2(8.3, 2.8)));
                      vec2 warped_uv = uv + (wr - 0.5) * distort_strength;

                      vec3 tex_coords = niri_geo_to_tex * vec3(warped_uv, 1.0);
                      vec4 color = texture2D(niri_tex, tex_coords.st);

                      return color * reveal;
                  }
                "
              }

              window-close {
                duration-ms 750
                curve "ease-out-cubic"
                custom-shader r"
                  float hash(vec2 p) {
                      return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
                  }

                  float noise(vec2 p) {
                      vec2 i = floor(p);
                      vec2 f = fract(p);
                      f = f * f * (3.0 - 2.0 * f);
                      float a = hash(i);
                      float b = hash(i + vec2(1.0, 0.0));
                      float c = hash(i + vec2(0.0, 1.0));
                      float d = hash(i + vec2(1.0, 1.0));
                      return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
                  }

                  float fbm(vec2 p) {
                      float v = 0.0;
                      float amp = 0.5;
                      for (int i = 0; i < 6; i++) {
                          v += amp * noise(p);
                          p *= 2.0;
                          amp *= 0.5;
                      }
                      return v;
                  }

                  float warpedFbm(vec2 p, float t) {
                      vec2 q = vec2(fbm(p + vec2(0.0, 0.0)),
                                    fbm(p + vec2(5.2, 1.3)));

                      vec2 r = vec2(fbm(p + 6.0 * q + vec2(1.7, 9.2) + 0.25 * t),
                                    fbm(p + 6.0 * q + vec2(8.3, 2.8) + 0.22 * t));

                      vec2 s = vec2(fbm(p + 5.0 * r + vec2(3.1, 7.4) + 0.18 * t),
                                    fbm(p + 5.0 * r + vec2(6.7, 0.9) + 0.2 * t));

                      return fbm(p + 6.0 * s);
                  }

                  vec4 close_color(vec3 coords_geo, vec3 size_geo) {
                      float p = niri_clamped_progress;
                      vec2 uv = coords_geo.xy;
                      float seed = niri_random_seed * 100.0;

                      float t = p * 12.0 + seed;

                      float fluid = warpedFbm(uv * 2.0 + seed, t);

                      vec2 center = uv - 0.5;
                      float dist = length(center * vec2(1.0, 0.7));

                      float dissolve = (1.0 - dist) * 1.2 + fluid * 0.7;
                      float remain = smoothstep(dissolve + 0.5, dissolve - 0.5, p * 1.8);

                      float distort_strength = p * p * 0.4;
                      vec2 wq = vec2(fbm(uv * 2.0 + vec2(0.0, t * 0.2)),
                                     fbm(uv * 2.0 + vec2(5.2, t * 0.2)));
                      vec2 wr = vec2(fbm(uv * 2.0 + 4.0 * wq + vec2(1.7, 9.2)),
                                     fbm(uv * 2.0 + 4.0 * wq + vec2(8.3, 2.8)));
                      vec2 warped_uv = uv + (wr - 0.5) * distort_strength;

                      vec3 tex_coords = niri_geo_to_tex * vec3(warped_uv, 1.0);
                      vec4 color = texture2D(niri_tex, tex_coords.st);

                      float tail = smoothstep(1.0, 0.8, p);
                      return color * remain * tail;
                  }
                "
              }
            }

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
              clip-to-geometry true
              geometry-corner-radius 12
              draw-border-with-background false
            }
            window-rule {
              match app-id="^thunar$"
              opacity 0.90
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
              match app-id="^helium$"
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
            "Mod+F".spawn-sh = "helium";
            "Mod+D".spawn-sh = "noctalia-shell ipc call launcher toggle";
            "Mod+W".spawn-sh = "skwd wall toggle";
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
            "Mod+Shift+R".spawn-sh = "rain-toggle";
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
    in
      pkgs.symlinkJoin {
        name = "niri-with-delay";
        paths = [baseNiri];
        postBuild = ''
                  rm $out/bin/niri
                  cat > $out/bin/niri << 'EOF'
          #!/bin/sh
          exec ${baseNiri}/bin/niri "$@"
          EOF
                  chmod +x $out/bin/niri
        '';
        passthru =
          baseNiri.passthru or {}
          // {
            providedSessions = ["niri"];
          };
      };
  };
}
