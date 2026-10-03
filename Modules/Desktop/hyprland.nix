{ ... }: {
  flake.nixosModules.hyprland = { lib, config, activeUser, ... }:
  let
    mainMod = "SUPER";

    # Prefer Spotify, fall back to any real player, never skwd-music — the same
    # string niri.nix binds; see the media-key note further down.
    playerctlCmd = "playerctl --player=spotify,%any --ignore-player=skwd-music";

    # Shorthand so the opacity rules below stay readable.
    o = {
      light = config.my.hyprland.opacityLight;
      strong = config.my.hyprland.opacityStrong;
    };

  displayOptions = { lib, ... }: {
    options.my.hyprland = {
      monitors = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # Empty: Hyprland's catch-all `,preferred,auto,1` (appended below) lights
        # up every output on its own. The connector names a host lists here are
        # per-machine facts, so there is no sensible shared default.
        default = [ ];
        description = "Hyprland `monitor=` lines, most specific first.";
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

          Per-host because taste differs sharply: the default is the original
          heavy look, Kit-Kat asked for it dialled right back.
        '';
      };

      wallpaperCommand = lib.mkOption {
        type = lib.types.str;
        default = "skwd-wall-v2";
        description = ''
          Command bound to Mod+W.

          skwd v2 (Modules/Desktop/skwd.nix) has NO `skwd` binary — it ships
          `skwd-wall-v2`, which starts the picker on demand and exits when closed,
          so there is nothing to toggle. The old default was v1's
          `skwd wall toggle`, and a v2 host binding it gets a key that silently
          does nothing, which is exactly how Kit-Kat ended up unable to change
          her wallpaper. v1 is gone, so v2's command is now the default.
        '';
      };
    };
  };
  in {
    imports = [ displayOptions ];


    # ============================================================
    # SYSTEM CONFIG
    # ============================================================
    # The X server, keymap, XCURSOR_*/NIXOS_OZONE_WL, Bluetooth and
    # hardware.graphics are shared with niri and live in
    # Modules/Desktop/desktop.nix; the greeter is Modules/Boot/sddm.nix. Only
    # what is Hyprland's own stays here.
    programs.hyprland.enable = true;
    programs.xwayland.enable = true;

    services.displayManager.defaultSession = "hyprland";

    # Portals. programs.hyprland already installs xdg-desktop-portal-hyprland,
    # and its wayland-session.nix adds xdg-desktop-portal-gtk, so nothing needs
    # adding to extraPortals — only the routing needs saying.
    #
    # This used to be `config.common.default = "gtk"` plus the GNOME portal, and
    # that routed EVERYTHING to the gtk portal — screen sharing and screenshots
    # included, which gtk does not implement. xdg-desktop-portal reads
    # /etc/xdg/xdg-desktop-portal/ before the per-package defaults in share/, so
    # the generated portals.conf (`common`) won over the hyprland-portals.conf
    # that ships with Hyprland and says exactly this. The GNOME portal does
    # nothing useful outside a GNOME/niri session, so it is gone too.
    xdg.portal.config.hyprland.default = [ "hyprland" "gtk" ];

    environment.sessionVariables = {
      HYPRCURSOR_THEME = "Bibata-Modern-Classic";
      HYPRCURSOR_SIZE = "24";
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
        # The retired Odysseus host never hit this only because it was on
        # stateVersion 25.05. Kit-Kat is a fresh 26.05 install and hit it
        # immediately. Pinning here keeps the
        # module self-consistent regardless of a host's stateVersion.
        configType = "hyprlang";

        settings = {
          # Host's own rules first, then an unconditional catch-all so an unlisted
          # connector still lights up instead of staying dark.
          monitor = config.my.hyprland.monitors ++ [ ",preferred,auto,1" ];

          "$terminal" = "kitty";
          "$fileManager" = "thunar";

          # DXVK_ASYNC and WINE_FULLSCREEN_FSR used to be set here too, and both
          # were no-ops: DXVK_ASYNC was read only by the dxvk-async fork, which
          # GE-Proton dropped once DXVK's graphics-pipeline-library landed, and
          # GE-Proton already defaults WINE_FULLSCREEN_FSR to 1 wherever its
          # fullscreen hack still exists. For upscaling, use a gamescope launch
          # option (see Modules/Gaming/steam.nix).
          env = [
            "XCURSOR_SIZE,24"
            "HYPRCURSOR_SIZE,24"
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
            # dispatcher only now (and not bound here). Leaving it here logs
            #   config option <dwindle:pseudotile> does not exist
            preserve_split = true;
          };

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

          # Keybinds
          # Keymap, deliberately mirroring rock's niri layout so the two machines
          # feel the same. Trimmed to what she actually uses: workspaces 1-5 (not
          # 1-10), no named discord/spotify/blank workspaces, no pseudo-tile.
          #
          # Niri-only entries from that map have no Hyprland equivalent and are
          # simply absent: Overview (Mod+A), Cycle Width / Reset Height (niri's
          # column model), Hotkey Overlay (Mod+Shift+Slash), Rain Effect (retired).
          #
          # Screenshots come from Modules/Desktop/screenshot.nix (Mod+Shift+S region,
          # Mod+Print fullscreen, Mod+Ctrl+S active window). Mod+S is focusmonitor
          # below, not a screenshot.
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
            # 1-5 only, and unpinned — they act on whichever screen has focus
            # (see `workspace = [ ]` below).
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
            # No XF86MonBrightness binds: brightnessctl is not installed, and both
            # of her panels are external monitors with no backlight to drive.
          ];

          # Same player selection as niri's media keys (playerctlCmd in
          # Modules/Desktop/niri.nix): bare `playerctl` can pick skwd-daemon's
          # inert skwd-music MPRIS player, which accepts every command and does
          # nothing, so the keys silently go nowhere.
          bindl = [
            ", XF86AudioNext, exec, ${playerctlCmd} next"
            ", XF86AudioPause, exec, ${playerctlCmd} play-pause"
            ", XF86AudioPlay, exec, ${playerctlCmd} play-pause"
            ", XF86AudioPrev, exec, ${playerctlCmd} previous"
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
            #
            # Classes mirror the app-ids niri.nix matches (verified there with
            # `niri msg windows`); Hyprland matches the class case-sensitively,
            # exactly like niri's app-id, and several of the old patterns here
            # never matched anything:
            #   ^(Steam)$   — the client's class is lowercase `steam`. Anchored, so
            #                in-game `steam_app_<id>` windows stay opaque.
            #   ^(discord)$ — the client here is Vesktop, class `vesktop`.
            #   ^(brave)$   — Brave's class is `brave-browser`.
            #   ^(thunar)$  — the autostarted `Thunar --daemon` serves windows as
            #                `Thunar`; only a direct `bin/thunar` launch is
            #                lowercase. See the matching rule in niri.nix.
            "match:class ^[Tt]hunar$, opacity ${o.light} ${o.light}"
            "match:class ^brave-browser$, opacity ${o.strong} ${o.strong}"
            "match:class ^(codium)$, opacity ${o.light} ${o.light}"
            "match:class ^(discord|vesktop)$, opacity ${o.strong} ${o.strong}"
            "match:class ^(spotify)$, opacity ${o.strong} ${o.strong}"
            "match:class ^steam$, opacity ${o.strong} ${o.strong}"
          ];

          exec-once = [
            # Discord auto-launch removed at her request — Spotify only.
            "hyprctl dispatch exec [workspace 2 silent] spotify"
            "dbus-update-activation-environment --systemd --all"
            "systemctl --user import-environment --all"
            # No polkit agent here: Modules/Core/polkit.nix runs polkit-gnome as a
            # graphical-session user service (the bare name was never on PATH
            # anyway — it lives in libexec/). No gnome-keyring-daemon either: it
            # is not installed on this host, and its ssh component would fight
            # programs.ssh.startAgent (Modules/Core/base.nix) for SSH_AUTH_SOCK.
            "noctalia"
          ];
        };
      };
    };
  };
}
