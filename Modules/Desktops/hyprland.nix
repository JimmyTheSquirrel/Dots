{ ... }: {
  flake.nixosModules.hyprland = { pkgs, lib, config, activeUser, ... }:
  let
    mainMod = "SUPER";

    # Shorthand so the opacity rules below stay readable.
    o = {
      light = config.my.hyprland.opacityLight;
      strong = config.my.hyprland.opacityStrong;
    };

  displayOptions = { lib, ... }: {
    options.my.hyprland = {
      monitors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "DP-2,2560x1080@144,0x0,1"
          "HDMI-A-1,1920x1080@60,320x-1080,1"
        ];
        description = "Hyprland `monitor=` lines, most specific first.";
      };

      primaryMonitor = lib.mkOption {
        type = lib.types.str;
        default = "DP-2";
        description = "Connector that workspaces 1-6 are pinned to.";
      };

      secondaryWorkspace = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 2;
        description = ''
          Workspace number to pin to the secondary monitor and make its default.

          null (Odysseus) puts workspaces 1-6 all on the primary monitor, which is
          the original single-focus layout. Kit-Kat uses 2, so her pivoted side
          monitor owns one numbered workspace rather than only named ones.
        '';
      };

      effects = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Blur and drop shadows.

          Both are per-frame GPU work. On a 60 Hz NVIDIA setup with a ROTATED
          output they are the cheapest thing to give up for snappiness — a 90°
          transform already forces a rotation pass every frame and rules out
          direct scanout, so the compositor is doing more work than on an
          unrotated 144 Hz display before any effects are added.

          Kit-Kat has these off: she wanted a plainer look anyway (no rounded
          corners), so it costs her nothing visually.
        '';
      };

      rounding = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = ''
          Corner radius for windows. 0 gives hard square corners throughout.

          Per-host taste: rock keeps the rounded look, Kit-Kat asked for none.
          Note the noctalia bar has its OWN radius (bar.main.radius) and the
          lockscreen/widgets theirs — squaring off the desktop means setting both.
        '';
      };

      opacityLight = lib.mkOption {
        type = lib.types.str;
        default = "0.75";
        description = "Opacity for lightly-transparent apps (thunar, codium).";
      };

      opacityStrong = lib.mkOption {
        type = lib.types.str;
        default = "0.60";
        description = ''
          Opacity for the heavily-transparent apps (brave, discord, spotify, Steam).

          Per-host because taste differs sharply: Odysseus runs the original heavy
          look, Kit-Kat asked for it dialled right back.
        '';
      };

      wallpaperCommand = lib.mkOption {
        type = lib.types.str;
        default = "skwd wall toggle";
        description = ''
          Command bound to Mod+W.

          skwd v1 (Odysseus) ships an `skwd` CLI with a resident picker, hence
          `skwd wall toggle`. v2 has NO `skwd` binary at all — it ships
          `skwd-wall-v2`, which starts the picker on demand and exits when closed,
          so there is nothing to toggle. A v2 host binding the v1 command gets a
          key that silently does nothing, which is exactly how Kit-Kat ended up
          unable to change her wallpaper.
        '';
      };

      secondaryMonitor = lib.mkOption {
        type = lib.types.str;
        default = "HDMI-A-1";
        description = "Connector for the named discord/spotify/blank workspaces.";
      };
    };
  };
  in {
    imports = [ displayOptions ];


    # ============================================================
    # SYSTEM CONFIG
    # ============================================================
    programs.hyprland.enable = true;
    programs.xwayland.enable = true;

    services.xserver.enable = true;
    services.xserver.videoDrivers = [ "amdgpu" ];
    services.xserver.xkb = {
      layout = "au";
      variant = "";
    };

    services.displayManager.sddm.enable = true;
    services.displayManager.defaultSession = "hyprland";
    services.displayManager.sddm.settings.General = {
      CursorTheme = "Bibata-Modern-Classic";
      CursorSize = 24;
    };

    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-hyprland
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
      HYPRCURSOR_THEME = "Bibata-Modern-Classic";
      HYPRCURSOR_SIZE = "24";
    };

    hardware.bluetooth.enable = true;
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # ============================================================
    # HOME MANAGER CONFIG
    # ============================================================
    home-manager.users.${activeUser} = {
      wayland.windowManager.hyprland = {
        enable = true;

        # PIN THE FORMAT. home-manager defaults `configType` off home.stateVersion:
        # < 26.05 gets `hyprlang` (hyprland.conf), >= 26.05 gets `lua`
        # (hyprland.lua). The settings below are hyprlang, and they are NOT valid
        # Lua: variables like `$terminal` render as `hl.$terminal("kitty")`, and `$`
        # is not a legal Lua identifier character. Hyprland then starts but shows a
        # red config-error bar:
        #   hyprland.lua:5: <name> expected near '$'
        #
        # Odysseus never hit this only because it is on stateVersion 25.05. Kit-Kat
        # is a fresh 26.05 install and hit it immediately. Pinning here keeps the
        # module self-consistent regardless of a host's stateVersion.
        configType = "hyprlang";

        settings = {
          # Host's own rules first, then an unconditional catch-all so an unlisted
          # connector still lights up instead of staying dark.
          monitor = config.my.hyprland.monitors ++ [ ",preferred,auto,1" ];

          "$terminal" = "kitty";
          "$fileManager" = "thunar";
          "$menu" = "noctalia msg panel-toggle session";

          env = [
            "XCURSOR_SIZE,24"
            "HYPRCURSOR_SIZE,24"
            "WINE_FULLSCREEN_FSR,1"
            "DXVK_ASYNC,1"
          ];

          general = {
            gaps_in = 1;
            gaps_out = 2;
            border_size = 2;
            "col.active_border" = "rgba(595959aa)";
            "col.inactive_border" = "rgba(595959aa)";
            resize_on_border = false;
            allow_tearing = false;
            layout = "dwindle";
          };

          decoration = {
            rounding = config.my.hyprland.rounding;
            rounding_power = 2;
            active_opacity = 1.0;
            inactive_opacity = 1.0;
            shadow = {
              enabled = config.my.hyprland.effects;
              range = 4;
              render_power = 3;
              color = "rgba(1a1a1aee)";
            };
            blur = {
              enabled = config.my.hyprland.effects;
              size = 3;
              passes = 1;
              vibrancy = 0.1696;
            };
          };

          animations = {
            enabled = "yes, please :)";
            bezier = [
              "easeOutQuint,0.23,1,0.32,1"
              "easeInOutCubic,0.65,0.05,0.36,1"
              "linear,0,0,1,1"
              "almostLinear,0.5,0.5,0.75,1.0"
              "quick,0.15,0,0.1,1"
            ];
            animation = [
              "global, 1, 10, default"
              "border, 1, 5.39, easeOutQuint"
              "windows, 1, 4.79, easeOutQuint"
              "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
              "windowsOut, 1, 1.49, linear, popin 87%"
              "fadeIn, 1, 1.73, almostLinear"
              "fadeOut, 1, 1.46, almostLinear"
              "fade, 1, 3.03, quick"
              "layers, 1, 3.81, easeOutQuint"
              "layersIn, 1, 4, easeOutQuint, fade"
              "layersOut, 1, 1.5, linear, fade"
              "fadeLayersIn, 1, 1.79, almostLinear"
              "fadeLayersOut, 1, 1.39, almostLinear"
              "workspaces, 1, 1.94, almostLinear, fade"
              "workspacesIn, 1, 1.21, almostLinear, fade"
              "workspacesOut, 1, 1.94, almostLinear, fade"
            ];
          };

          dwindle = {
            # `pseudotile` was removed as a dwindle option in Hyprland 0.5x — it is a
            # dispatcher only now (Mod+P below). Leaving it here logs
            #   config option <dwindle:pseudotile> does not exist
            preserve_split = true;
          };

          master = { new_status = "master"; };

          misc = {
            force_default_wallpaper = -1;
            disable_hyprland_logo = false;
          };

          # ---- NVIDIA / 60 Hz responsiveness ----
          # Both of these were read off the live machine with `hyprctl getoption`
          # before being set, and both default the *slow* way on this hardware.
          #
          # Hyprland is Kit-Kat-only (Odysseus is gone), so these sit here
          # unconditionally rather than behind a `my.hyprland.*` option. If this
          # file ever gains a second, non-NVIDIA host, gate them then.

          cursor = {
            # Measured 1 (software cursors) on her box. Hyprland turns hardware
            # cursors off by itself on NVIDIA, and the cost is the whole reason
            # the desktop "feels" slow while nothing is actually dropping frames:
            # a software cursor makes every pointer movement damage and
            # recomposite the region it crosses, at 60 Hz, on a GPU that is
            # otherwise idling at P8/210 MHz.
            #
            # The one thing to watch is DP-3, which is rotated (transform 3). A
            # hardware cursor plane cannot always rotate, so if the cursor goes
            # missing, smears, or points the wrong way *on the sideways monitor
            # only*, this is why — set it back to `true` and the old behaviour
            # returns. Nothing else depends on it.
            no_hardware_cursors = false;
          };

          opengl = {
            # Defaults to true. Upstream's own docs say it "may reduce
            # performance"; it exists to paper over flickering on some NVIDIA
            # setups. Off until flicker is actually observed — if she reports
            # flashing or black flashes on window open/close, put it back.
            nvidia_anti_flicker = false;
          };

          input = {
            kb_layout = "us";
            follow_mouse = 1;
            sensitivity = 0;
            touchpad = { natural_scroll = false; };
          };

          device = [
            {
              name = "epic-mouse-v1";
              sensitivity = -0.5;
            }
          ];

          # Keybinds
          # Keymap, deliberately mirroring rock's niri layout so the two machines
          # feel the same. Trimmed to what she actually uses: workspaces 1-5 (not
          # 1-10), no named discord/spotify/blank workspaces, no pseudo-tile.
          #
          # Niri-only entries from that map have no Hyprland equivalent and are
          # simply absent: Overview (Mod+A), Cycle Width / Reset Height (niri's
          # column model), Hotkey Overlay (Mod+Shift+Slash), Rain Effect (retired).
          #
          # Screenshots come from Modules/screenshot.nix (Mod+Shift+S region,
          # Mod+S fullscreen, Mod+Ctrl+S active window).
          bind = [
            # ── Applications ──────────────────────────────────────────────────
            "${mainMod}, RETURN, exec, $terminal"
            "${mainMod}, E, exec, $fileManager"
            "${mainMod}, F, exec, brave"
            "${mainMod}, D, exec, noctalia msg panel-toggle launcher"
            "${mainMod}, W, exec, ${config.my.hyprland.wallpaperCommand}"
            "${mainMod}, B, exec, noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet"
            "${mainMod}, M, exec, noctalia msg desktop-widgets-edit"
            "${mainMod} SHIFT, DELETE, exec, noctalia msg panel-toggle session"

            # ── Window management ─────────────────────────────────────────────
            "${mainMod}, Q, killactive,"
            "${mainMod}, V, togglefloating,"
            "${mainMod} SHIFT, F, fullscreen"
            "${mainMod}, J, layoutmsg, togglesplit"

            # Move focus to the other screen. With workspaces unpinned this is how
            # she picks a monitor, then 1-5 act on whichever has focus.
            "${mainMod}, S, focusmonitor, +1"
            "${mainMod} SHIFT, B, exec, noctalia msg bar-toggle"

            # ── Focus ─────────────────────────────────────────────────────────
            "${mainMod}, left, movefocus, l"
            "${mainMod}, right, movefocus, r"
            "${mainMod}, up, movefocus, u"
            "${mainMod}, down, movefocus, d"

            # ── Move the focused window ───────────────────────────────────────
            "${mainMod} SHIFT, left, movewindow, l"
            "${mainMod} SHIFT, right, movewindow, r"
            "${mainMod} SHIFT, up, movewindow, u"
            "${mainMod} SHIFT, down, movewindow, d"

            # ── Workspaces ────────────────────────────────────────────────────
            # 1-5 only. 1 and 3-5 live on the Philips, 2 on the pivoted Dell.
            "${mainMod}, 1, workspace, 1"
            "${mainMod}, 2, workspace, 2"
            "${mainMod}, 3, workspace, 3"
            "${mainMod}, 4, workspace, 4"
            "${mainMod}, 5, workspace, 5"
            "${mainMod} SHIFT, 1, movetoworkspace, 1"
            "${mainMod} SHIFT, 2, movetoworkspace, 2"
            "${mainMod} SHIFT, 3, movetoworkspace, 3"
            "${mainMod} SHIFT, 4, movetoworkspace, 4"
            "${mainMod} SHIFT, 5, movetoworkspace, 5"

            # Scroll the mouse wheel over the bar/desktop to change workspace.
            "${mainMod}, mouse_down, workspace, e+1"
            "${mainMod}, mouse_up, workspace, e-1"
          ];

          bindm = [
            "${mainMod}, mouse:272, movewindow"
            "${mainMod}, mouse:273, resizewindow"
          ];

          bindel = [
            ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
            ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
            ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
            ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
            ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
            ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
          ];

          bindl = [
            ", XF86AudioNext, exec, playerctl next"
            ", XF86AudioPause, exec, playerctl play-pause"
            ", XF86AudioPlay, exec, playerctl play-pause"
            ", XF86AudioPrev, exec, playerctl previous"
          ];

          # Workspaces are NOT pinned to monitors and NOT persistent.
          #
          # Earlier revisions pinned 1-5 across the two screens and forced them to
          # persist, which meant constantly thinking about which number lived on
          # which monitor. This is the simpler model she asked for: pick the screen
          # with Mod+S, then 1-5 apply to whichever screen has focus. Workspaces
          # appear when something is on them and disappear when empty, which is
          # Hyprland's native behaviour.
          #
          # Nothing here pins monitors, so the list is empty — kept as an explicit
          # empty list rather than deleted so the intent is obvious.
          workspace = [ ];

          # ── Window / layer rules: Hyprland 0.53+ syntax ──────────────────────
          #
          # 0.53 overhauled this completely and the old forms SILENTLY DO NOTHING.
          # Matchers are `match:<field> <value>`, properties are `<name> <value>`,
          # and `windowrulev2` no longer exists.
          #
          # The property names were also renamed, and NOT uniformly — each one was
          # verified against Hyprland 0.55.4 itself with
          #   hyprctl keyword windowrule "match:class ^(zzz)$, <candidate>"
          # which answers `ok` or `invalid field type <name>`. Guessing from the old
          # names gets several wrong:
          #   nofocus      -> no_focus          suppressevent -> suppress_event
          #   bordersize   -> border_size       blurpopups    -> blur_popups
          #   dimaround    -> dim_around        ignorezero    -> ignore_alpha <float>
          #   floating     -> float   (matcher; `no_border` does NOT exist at all —
          #                            use border_size 0)
          windowrule = [
            # workspace placement
            "match:class ^(discord|vesktop)$, workspace 2 silent"
            "match:class ^(spotify)$, workspace 2 silent"

            # floating window chrome
            "match:float true, border_size 0"
            "match:float true, rounding 0"

            # misc behaviour
            "match:class .*, suppress_event maximize"
            "match:class ^$, match:title ^$, match:xwayland true, match:float true, no_focus on"

            # transparency
            "match:class ^(thunar)$, opacity ${o.light} ${o.light}"
            "match:class ^(brave)$, opacity ${o.strong} ${o.strong}"
            "match:class ^(codium)$, opacity ${o.light} ${o.light}"
            "match:class ^(discord)$, opacity ${o.strong} ${o.strong}"
            "match:class ^(spotify)$, opacity ${o.strong} ${o.strong}"
            "match:class ^(Steam)$, opacity ${o.strong} ${o.strong}"

            # Star Citizen / wine
            "match:class ^(rsi-launcher)$, tile on"
            "match:class ^(rsi-launcher)$, workspace 5 silent"
            "match:class ^(StarCitizen)$, fullscreen on"
            "match:class ^(StarCitizen)$, immediate on"
            "match:class ^(StarCitizen)$, border_size 0"
            "match:class ^(wine)$, match:float true, no_focus on"
            "match:class ^(wineserver)$, no_focus on"
          ];

          layerrule = [
            "match:namespace ^rofi-wal$, blur true"
            "match:namespace ^rofi-wal$, blur_popups true"
            "match:namespace ^rofi-wal$, dim_around true"
            "match:namespace ^rofi-wal$, ignore_alpha 0.0"
          ];

          exec-once = [
            # Discord auto-launch removed at her request — Spotify only.
            "hyprctl dispatch exec [workspace 2 silent] spotify"
            "dbus-update-activation-environment --systemd --all"
            "systemctl --user import-environment --all"
            "gnome-keyring-daemon --start --components=secrets,ssh,pkcs11"
            "polkit-gnome-authentication-agent-1"
            "noctalia"
          ];
        };
      };
    };
  };
}
