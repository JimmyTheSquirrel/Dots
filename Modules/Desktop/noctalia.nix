{ self, inputs, ... }:
let
  anuratiFont = ../../Resources/Fonts/Anurati-Regular.otf;

  # Per-host overrides, deep-merged OVER the shared lock below. Needed because
  # this module force-writes settings.toml on every rebuild, so anything a user
  # changes in the noctalia GUI is reverted at the next switch. That is the
  # intended behaviour for rock's machines, but a second person's desktop has to
  # be able to differ without forking the whole snapshot.
  noctaliaOptions = { lib, ... }: {
    options.my.noctalia.lockedSettingsExtra = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Deep-merged over the module's lockedSettings, this host winning.

        Capture a user's GUI tweaks here or the next rebuild discards them.
      '';
    };
  };
in {
  flake.nixosModules.noctalia = { pkgs, lib, config, activeUser, ... }:
  let
    # ── The locked desktop state ───────────────────────────────────────────────
    # Snapshot of ~/.local/state/noctalia/settings.toml as dialled in via the
    # GUI on 2026-09-30, minus the runtime keys listed in the
    # home.activation.noctaliaSettingsLock comment. Edit THIS to change the
    # desktop; a rebuild forces it back over whatever the GUI has since written.
    #
    # To re-snapshot after a round of GUI tuning:
    #   noctalia config export merged        # or just read settings.toml
    # and fold the changed keys back in here. Floats are written clean (0.55,
    # not the 0.54999998770654202 a slider produces) — noctalia stores them as
    # float32 and the difference is not representable on screen.
    lockedSettings = {
      bar.main = {
        position = "top";
        background_opacity = 0.55;
        radius = 80;
        start = [ "workspaces" ];
        center = [ "group:g1" ];
        end = [ "volume" "network" "bluetooth" "notifications" "tray" "clock" ];

        # The media + visualizer pill in the centre of the bar.
        capsule_group = [{
          id = "g1";
          enabled = true;
          members = [ "media" "audio_visualizer" ];
          fill = "surface_variant";
          opacity = 0.45;
          padding = 9.0;
          radius = 7.0;
        }];
      };

      desktop_widgets = {
        schema_version = 2;
        widget_order = [ ];
        grid = { cell_size = 16; major_interval = 4; visible = true; };
      };

      dock.icon_size = 29;
      location.address = "Sydney";
      lockscreen.blur_intensity = 0.25;

      # Login box is placed per-output, so this is display-geometry dependent:
      # DP-2 is the 2560x1080 primary, HDMI-A-1 the 1920x1080 secondary. cx is
      # half of each output's width. Revisit if the monitor layout changes.
      lockscreen_widgets = {
        enabled = false;
        schema_version = 2;
        widget_order = [ "lockscreen-login-box@HDMI-A-1" "lockscreen-login-box@DP-2" ];
        grid = { cell_size = 16; major_interval = 4; visible = true; };
        widget = let
          loginBox = output: cx: {
            inherit output;
            inherit cx;
            type = "login_box";
            box_height = 196.0;
            box_width = 810.0;
            cy = 898.0;
            rotation = 0.0;
            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
          };
        in {
          "lockscreen-login-box@DP-2" = loginBox "DP-2" 1280.0;
          "lockscreen-login-box@HDMI-A-1" = loginBox "HDMI-A-1" 960.0;
        };
      };

      shell = {
        password_style = "random";
        launcher.categories = false;
        panel = {
          floating_layer = "top";
          session_placement = "floating";
          session_position = "center";
          # "solid" (default), "soft", or "glass" — controls launcher/panel
          # background transparency.
          transparency_mode = "soft";
        };
        screen_corners = { enabled = true; size = 35; };

        # ⚠️ Possibly obsolete on v2 — see the matching note in Desktop/niri.nix.
        # skwd-music was absent from the bus in a 2026-09-15 static-wallpaper
        # test; it may only register for video / Wallpaper Engine wallpapers.
        # Harmless to keep, so it stays until checked with a video wallpaper.
        #
        # skwd-daemon registers an inert org.mpris.MediaPlayer2.skwd-music
        # player. It carries no metadata but reports CanControl/CanPlay/CanGoNext
        # = true, so it can win noctalia's "active player" pick and swallow
        # `noctalia msg media`. The niri and Hyprland media keys dodge it with
        # playerctl --ignore-player; this is the same exclusion for noctalia's
        # own media widget.
        mpris.blacklist = [ "skwd-music" ];

        # Order here is the on-screen order, and `shortcut` is the key that
        # triggers each one in the session panel.
        session.actions = [
          { action = "lock";              shortcut = "1"; enabled = true;  variant = "default";     countdown_seconds = 0.0; }
          { action = "logout";            shortcut = "2"; enabled = true;  variant = "default";     countdown_seconds = 0.0; }
          { action = "lock_and_suspend";  shortcut = "3"; enabled = false; variant = "default";     countdown_seconds = 0.0; }
          { action = "reboot";            shortcut = "4"; enabled = true;  variant = "default";     countdown_seconds = 0.0; }
          { action = "shutdown";          shortcut = "5"; enabled = true;  variant = "destructive"; countdown_seconds = 0.0; }
        ];
      };

      # ── Monitor power-save: screens off after 5 minutes idle ──────────────
      # noctalia has its own idle manager (src/idle/idle_manager.cpp), so this
      # needs no swayidle/hypridle. It takes the timeout from the compositor via
      # ext-idle-notify-v1 and drives DPMS through the compositor's own IPC — on
      # niri that is PowerOffMonitors / PowerOnMonitors, on Hyprland (Elektra)
      # the equivalent dispatcher. Same as `noctalia msg dpms-off` by hand.
      #
      # This is DPMS, NOT an output disable: the outputs stay configured, so
      # nothing moves windows or workspaces between monitors the way
      # `niri msg output ... off` would.
      #
      # The `screen_off` action auto-pairs a ScreenOn resume, so any keyboard or
      # mouse event wakes both screens — no resume_command needed, and no chance
      # of being left staring at a black screen.
      #
      # Idle is inhibited by all three of the usual mechanisms, so this will not
      # blank mid-film:
      #   - zwp_idle_inhibitor_v1 (mpv, browsers playing video) — noctalia binds
      #     the inhibitor-aware get_idle_notification, not the input-only variant
      #   - org.freedesktop.ScreenSaver D-Bus inhibits (Steam, most games)
      #   - the bar's Caffeine toggle / `noctalia msg caffeine-toggle`, for a
      #     manual hold
      #
      # ⚠️ Sunshine does NOT inhibit idle. Moonlight's injected keyboard/mouse
      # events are real uinput devices so they reset the timer, but a
      # controller-only session sends nothing libinput can see — 5 minutes in,
      # the screens DPMS off and the wlr capture goes with them. Hit Caffeine
      # before a couch-gamepad stream (see Claude/streaming.md).
      #
      # Schema notes (upstream src/config/schema/config_schema.cpp):
      #   - behaviors are a namedMap: `[idle.behavior.<name>]`, NOT `[[idle.behavior]]`
      #   - the key is `timeout` (seconds), not `timeout_seconds`
      #   - valid actions: lock | screen_off | suspend | lock_and_suspend, or any
      #     other string to run `command` / `resume_command` as a shell action
      #   - declaring ANY behavior replaces the built-in default list
      #     (lock 600s, screen-off 660s, lock-and-suspend 900s — all three ship
      #     `enabled = false`, so nothing is lost by dropping them). Leaving the
      #     list empty is what restores those defaults.
      idle = {
        # Fullscreen dim as a warning before the action fires; any activity
        # during the fade cancels it. 0 disables the warning. 2.0 is upstream's
        # default, pinned here so the visible behaviour can't move under us.
        pre_action_fade_seconds = 2.0;

        behavior.screen-off = {
          enabled = true;
          timeout = 300;
          action = "screen_off";
        };
      };

      # ── Colours: skwd generates, noctalia fans out ──────────────────────────
      # skwd-iris is the only palette generator on this host. It renders
      # ~/.config/noctalia/palettes/skwd-wall.json on every wallpaper change
      # (the `noctalia` integration in Modules/Desktop/skwd.nix) and then runs
      # noctalia-apply-palette, which makes noctalia re-read it. noctalia
      # recolours its own UI and pushes the palette to every template below.
      #
      # source MUST stay "custom" and custom_palette "skwd-wall" — with
      # source = "wallpaper" noctalia runs its own generator off its internal
      # wallpaper path and skwd's palette is ignored, which puts two different
      # palettes on one desktop (skwd's picker chrome always themes itself from
      # skwd-iris). Locking it here means a GUI experiment with the palette
      # picker cannot leave the colour pipeline broken past a rebuild.
      theme = {
        source = "custom";
        custom_palette = "skwd-wall";
        mode = "dark";

        # builtin_ids is deliberately empty. The builtin templates for kitty,
        # starship and btop write a theme file and then run an apply.sh that
        # appends an include to the app's main config — but kitty.conf,
        # starship.toml and btop.conf are all read-only Nix store symlinks here,
        # so the append cannot land. btop in particular is already handled by
        # skwd's own integration, which renders the mapping owned by
        # Modules/Shell/btop.nix into the `dots` theme that btop.conf actually
        # selects; enabling the builtin as well just writes a second, unused
        # noctalia.theme.
        #
        # community_ids is empty too, and Discord is the reason it must stay
        # that way. The `discord` community template was enabled on 2026-09-15
        # and had to be pulled the same day: it is a 20 KB full redesign with
        # opaque panels, and this host runs Vesktop with transparent = true plus
        # a quickCss that forces transparency with !important. Both loaded at
        # once made Discord visibly glitch, and it only became visible once the
        # palette started actually updating — before that the theme was frozen,
        # so the conflict sat there statically.
        #
        # Discord now gets its colours from skwd instead, as a colours-only file
        # that quickCss consumes. See Modules/Apps/discord.nix.
        #
        # The spicetify and steam community templates do not fit either: theirs
        # target the Comfy/Colorful spicetify themes and the SFP Material-Theme
        # Steam skin, while this host uses the `text` spicetify theme and
        # Millennium/Zehn. Both stay on their own skwd integrations.
        #
        # Net effect: noctalia recolours its OWN UI from the skwd palette and
        # fans out to nothing. Enable a template here only after checking its
        # output path against what this host actually runs.
        templates = { builtin_ids = [ ]; community_ids = [ ]; };
      };

      # Only `enabled`. The paths under [wallpaper] are skwd's to write.
      wallpaper.enabled = false;

      widget = {
        audio_visualizer = { bands = 30; centered = false; scale = 1.1; width = 170; };
        clock = {
          capsule = true;
          capsule_opacity = 0.34;
          # strftime format: %H=24h hour, %I=12h hour, %-I=12h no leading zero,
          # %M=minute, %p=AM/PM, %P=am/pm. Use "%H:%M" for 24-hour.
          format = "%-I:%M %p";
          tooltip_format = "%A, %B %d %Y";
        };
        network = { font_family = "42dot Sans"; show_label = false; vpn_status = "both"; };
        taskbar = { scale = 1.35; show_all_outputs = true; };
        tray.drawer = true;
      };

      # NOTE: do NOT add a plugins."kenn/keybind-cheatsheet" table to point the
      # plugin at a custom niri config. Per-plugin tables are silently dropped,
      # and TOML has no "~" expansion either way. The plugin instead uses its own
      # default, ~/.config/niri/config.kdl, and follows the `include` directives
      # found there; niri.nix generates that file plus the niri-keybinds.kdl it
      # includes.
      plugins = {
        enabled = [ "kenn/keybind-cheatsheet" ];
        source = [
          { kind = "git"; name = "official";  location = "https://github.com/noctalia-dev/official-plugins"; }
          { kind = "git"; name = "community"; location = "https://github.com/noctalia-dev/community-plugins"; }
        ];
      };
    };

    mergedLockedSettings =
      lib.recursiveUpdate lockedSettings config.my.noctalia.lockedSettingsExtra;

    lockedSettingsFile =
      (pkgs.formats.toml { }).generate "noctalia-settings-lock.toml" mergedLockedSettings;

    pythonWithTomlkit = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);

    # Deep-merges the lock file INTO the live settings.toml, lock winning.
    # tomlkit rather than tomllib+tomli_w so that comments, key order and
    # formatting in the parts we do not touch survive the round-trip.
    settingsMergeScript = pkgs.writeText "noctalia-settings-merge.py" ''
      import sys
      import tomlkit

      live_path, lock_path = sys.argv[1], sys.argv[2]

      with open(lock_path) as f:
          lock = tomlkit.parse(f.read())

      # First run on a fresh install: noctalia has not started yet, so there is
      # no settings.toml. Start from an empty document and write the lock out in
      # full, which is what makes the bar come up correct on a wiped machine
      # instead of showing noctalia's defaults until the GUI is touched.
      try:
          with open(live_path) as f:
              live = tomlkit.parse(f.read())
      except FileNotFoundError:
          live = tomlkit.document()

      def merge(dst, src):
          for key, value in src.items():
              # Recurse only into tables. Arrays — including arrays of tables
              # like capsule_group and session.actions — are dict-unlike here,
              # so they fall through and replace wholesale, which is the
              # semantics we want for a locked list.
              if isinstance(value, dict) and isinstance(dst.get(key), dict):
                  merge(dst[key], value)
              else:
                  dst[key] = value

      merge(live, lock)

      import os
      os.makedirs(os.path.dirname(live_path), exist_ok=True)

      # Write via a temp file in the same directory + atomic rename, so a
      # rebuild interrupted mid-write cannot leave noctalia with a truncated
      # settings.toml (it would fall back to defaults and lose the layout).
      tmp_path = live_path + ".nix-tmp"
      with open(tmp_path, "w") as f:
          f.write(tomlkit.dumps(live))
      os.replace(tmp_path, live_path)
    '';
  in {
    imports = [ inputs.noctalia.nixosModules.default noctaliaOptions ];

    programs.noctalia = {
      enable = true;
      recommendedServices.enable = true;
    };

    # ── Audio visualizer source: Spotify only ─────────────────────────────────
    # The `audio_visualizer` bar widget opens a PipeWire capture stream called
    # "Noctalia Spectrum" with stream.capture.sink = true, aimed at the DEFAULT
    # SINK's monitor — i.e. everything mixed into the speakers, so Discord voice,
    # game audio and browser tabs all drive the bars. The widget exposes no
    # source setting (`noctalia config export full` lists only bands / centered /
    # scale / width), so the only place to fix this is the PipeWire graph.
    #
    # Shape of the fix: a loopback sink `spotify_tap` that Spotify plays into and
    # which forwards to whatever the default sink currently is, so audio still
    # comes out of the speakers normally. The Spectrum stream is then pointed at
    # `spotify_tap`'s monitor instead of the hardware sink's. Nothing else is
    # routed into it, so nothing else can move the bars.
    services.pipewire.extraConfig = {
      pipewire."91-spotify-tap-sink" = {
        "context.modules" = [
          {
            name = "libpipewire-module-loopback";
            args = {
              "capture.props" = {
                "node.name" = "spotify_tap";
                "node.description" = "Spotify";
                "media.class" = "Audio/Sink";
                "audio.position" = ["FL" "FR"];
                # Keep it well below any hardware sink so WirePlumber never picks
                # it as the system default. It feeds back into the default sink,
                # and default = spotify_tap would be a graph cycle.
                "priority.session" = 100;
              };
              "playback.props" = {
                "node.name" = "spotify_tap_out";
                "node.description" = "Spotify (loopback to default output)";
                "audio.position" = ["FL" "FR"];
                # Deliberately no target: an untargeted stream follows the default
                # sink, so the loopback keeps working across output switches
                # (headset ↔ HDMI) with no extra wiring.
              };
            };
          }
        ];
      };

      # Spotify is a PulseAudio client (client.api = "pipewire-pulse",
      # application.process.binary = ".spotify-wrapped"), so its node props are
      # rewritten by pulse.rules, not by client.conf's stream.rules.
      pipewire-pulse."91-spotify-tap-route" = {
        "pulse.rules" = [
          {
            matches = [{"application.name" = "spotify";}];
            actions.update-props."target.object" = "spotify_tap";
          }
        ];
      };

      # noctalia is a native libpipewire client, so its stream props come from
      # client.conf. Match on media.name — node.name is the useless
      # ".noctalia-wrapped", shared with noctalia's other PipeWire clients.
      #
      # NOTE: WirePlumber also has a `stream.rules` section, and it is NOT the
      # one to use. That copy only feeds state-stream.lua's save/restore
      # bookkeeping; the linking policy reads target.object off the real node
      # props, which only PipeWire's own client.conf / pipewire-pulse.conf rules
      # can rewrite.
      client."91-noctalia-spectrum-capture" = {
        "stream.rules" = [
          {
            matches = [{"media.name" = "Noctalia Spectrum";}];
            actions.update-props."target.object" = "spotify_tap";
          }
        ];
      };
    };

    # `lib` here is home-manager's, not the NixOS one — the activation script
    # below needs lib.hm.dag, which only exists on HM's lib.
    home-manager.users.${activeUser} = { lib, ... }: {
      home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.anurati-font
        pkgs.playerctl
        # Only 42dot Sans is actually referenced (shell.font_family in noctalia's
        # settings.toml). The unfiltered google-fonts set is a 2.3 GiB closure;
        # this override is 5.5 MiB. Add families here if the font picker needs more.
        (pkgs.google-fonts.override { fonts = ["42dotSans"]; })

        # Makes noctalia re-read its custom palette file. Run as the `noctalia`
        # integration's reload command in Modules/Desktop/skwd.nix, immediately after skwd
        # writes ~/.config/noctalia/palettes/skwd-wall.json.
        #
        # `templates-apply` is NOT enough on its own: it re-renders from the
        # palette noctalia already holds in memory, so when only the file on disk
        # has changed it reports "ok" and writes nothing at all. Measured
        # 2026-09-15 — a fresh palette plus templates-apply left every output file
        # untouched; color-scheme-set rewrote them within a second.
        #
        # Re-selecting the palette that is already selected is what forces the
        # re-read, and it fans out to noctalia's own UI plus every enabled
        # template (Discord, etc.) on its own — no templates-apply needed after.
        #
        # Installed as a package, not ~/.local/bin: skwd runs reload commands with
        # a trimmed PATH that only covers nix profile dirs.
        (pkgs.writeShellScriptBin "noctalia-apply-palette" ''
          # Never fail the integration when the shell is not up yet (e.g. a
          # wallpaper restored at login before noctalia has registered its IPC
          # socket) — skwd logs a non-zero reload as a warning per apply.
          noctalia msg color-scheme-set custom skwd-wall 2>/dev/null || true
        '')

        # NOTE: `noctalia-sync-wallpaper` used to be here and is GONE (2026-09-15).
        # It ran from skwd's postProcessing hook and did three things, all of which
        # were removed in turn until nothing was left:
        #
        #   1. `noctalia msg templates-apply` — wrong hook. postProcessing fires
        #      BEFORE the integrations render, so it pushed the previous palette.
        #      Moved to noctalia-apply-palette above (an integration reload).
        #   2. `noctalia msg wallpaper-set` — vestigial once theme.source became
        #      "custom", and it caused the bar to flash the old colour before
        #      settling on the new one.
        #   3. the swaybg backdrop swap — replaced by skwd's native
        #      `skwd-paper-backdrop` surface (see Modules/Desktop/niri.nix).
        #
        # skwd's `postProcessing` entry that invoked it was stripped from
        # config.json by a one-off migration in Modules/Desktop/skwd.nix (since
        # removed). Nothing on this host now uses postProcessing, and the
        # `%path%` placeholder machinery is no longer needed anywhere — the one
        # remaining hook, noctalia-apply-palette, takes no arguments.
      ];

      # ── Lock the GUI's own settings.toml to the state declared here ──────────
      # THIS is what makes the desktop reproducible. Any *.toml in
      # ~/.config/noctalia/ is merged UNDERNEATH
      # ~/.local/state/noctalia/settings.toml, so anything the settings GUI has
      # ever written wins outright and Nix can never take it back that way.
      # (This module used to write one, nix-config.toml; half its keys were
      # already shadowed by the lock below and the rest now live in
      # `lockedSettings` too, so it is gone.) Bar position, widget slots,
      # capsule groups, lockscreen layout and the template lists all live in
      # settings.toml — so before this script
      # existed, none of them were controlled by Nix at all. A rebuild changed
      # nothing and a fresh install came up with noctalia's defaults.
      #
      # So we write settings.toml directly, on top of whatever is there:
      #   locked keys  -> forced to the value declared in `lockedSettings`
      #   everything else -> passed through untouched
      #
      # That last half is the reason this is a deep merge and not a `cp`.
      # settings.toml also holds genuine runtime state that must NOT be pinned:
      # `config_version` (noctalia migrates it — pinning would fight its own
      # schema upgrades) and [wallpaper.last]/[wallpaper.default]/
      # [wallpaper.monitors.*] (rewritten by skwd on every wallpaper swap).
      # Only `wallpaper.enabled` is locked, since noctalia must keep painting
      # nothing — skwd owns the wallpaper. See Claude/noctalia.md.
      #
      # Tuning in the GUI still works and still persists; the next rebuild is
      # what reverts it. That is the intent: the GUI is for testing, the repo is
      # the source of truth.
      #
      # Arrays are replaced wholesale, not appended — a locked `start` list or
      # `capsule_group` is the complete list. tomlkit's arrays-of-tables are
      # list-like so they fall through to plain assignment; only tables recurse.
      #
      # Supersedes an earlier two-key `sed` that forced builtin_ids /
      # community_ids empty. That mattered (measured 2026-09-15: settings.toml
      # still carried builtin_ids = ["btop"] and community_ids = ["discord"], so
      # noctalia and skwd were BOTH writing colour files on every wallpaper
      # swap), but it could only rewrite keys that already existed on their own
      # line and could not express nested tables. Those two keys are now just
      # part of `lockedSettings` like everything else.
      home.activation.noctaliaSettingsLock = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pythonWithTomlkit}/bin/python3 ${settingsMergeScript} \
          "$HOME/.local/state/noctalia/settings.toml" \
          ${lockedSettingsFile}

        # Make the running shell adopt the rewrite. Verified 2026-09-30:
        # config-reload genuinely re-reads settings.toml — a value changed on
        # disk survived a subsequent noctalia-initiated write of the same file,
        # which it could not have done if the shell were still holding its old
        # copy in memory. So no re-login is needed (contrast niri, whose config
        # is baked into the wrapper).
        #
        # By absolute path: Home Manager runs activation with an EMPTY PATH
        # (home.emptyActivationPath), so a bare `noctalia` was "command not
        # found" on every switch — and the redirect hid it, so this line never
        # actually reloaded anything. The socket it talks to is found from
        # XDG_RUNTIME_DIR + WAYLAND_DISPLAY, which home-manager-<user>.service
        # imports from the user's systemd environment.
        #
        # noctalia is spawned by the compositor (niri's spawn-at-startup,
        # Hyprland's exec-once), not systemd, so it is simply absent during a
        # boot-time or --boot rebuild. Never fail activation for that.
        ${lib.getExe config.programs.noctalia.package} msg config-reload >/dev/null 2>&1 || true
      '';
    };
  };

  perSystem = { pkgs, system, ... }: {
    packages.anurati-font = pkgs.stdenvNoCC.mkDerivation {
      pname = "anurati-font";
      version = "1.0";
      dontUnpack = true;
      src = anuratiFont;
      installPhase = ''
        mkdir -p $out/share/fonts/opentype
        cp $src $out/share/fonts/opentype/Anurati-Regular.otf
      '';
      meta = {
        description = "Anurati - futuristic geometric display font";
        license = pkgs.lib.licenses.ofl;
      };
    };
  };
}
