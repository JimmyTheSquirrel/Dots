{
  self,
  inputs,
  ...
}: let
  # ── Keybinds: single source of truth ────────────────────────────────────────
  # Consumed twice, both derived from this one list:
  #   1. perSystem → the `binds` attrset baked into the wrapped niri package.
  #      That baked file is the ONLY keybind config the compositor ever reads.
  #   2. flake.nixosModules.niri → ~/.config/niri/niri-keybinds.kdl, which exists
  #      solely so noctalia's kenn/keybind-cheatsheet plugin has a file to parse.
  #
  # `title` becomes hotkey-overlay-title and `category` becomes the plugin's
  # `// #"…"` grouping comment (it prefers those over its own action-name
  # heuristic); the baked `binds` schema consumes `action` alone.
  # Add a bind here and both outputs stay in step — never hand-edit the KDL.
  # Panel column order. Within each category the convention is:
  # plain Mod binds first, then Mod+Shift binds, then Mod+WheelScroll last.
  #
  # Bare `playerctl` targets the first MPRIS bus name it finds, and skwd-daemon
  # registers an inert `org.mpris.MediaPlayer2.skwd-music` that sorts before
  # `spotify`. It advertises CanControl/CanPlay/CanGoNext = true but does
  # nothing, so every media key silently went nowhere. Prefer spotify, fall back
  # to a real player (browser video), never skwd-music.
  playerctlCmd = "playerctl --player=spotify,%any --ignore-player=skwd-music";

  keybindCategories = [
    "Applications"
    "Window Management"
    "Workspace - Navigation"
    "Workspace - Movement"
    "Workspace - Management"
    "Screenshots"
    "Media"
  ];

  mkKeybinds = {
    pkgs,
    lib,
  }: [
    # ── Applications ──
    {
      key = "Mod+Return";
      title = "Terminal";
      category = "Applications";
      action.spawn-sh = lib.getExe pkgs.kitty;
    }
    {
      key = "Mod+E";
      title = "Files";
      category = "Applications";
      action.spawn-sh = lib.getExe pkgs.xfce.thunar;
    }
    {
      key = "Mod+F";
      title = "Browser";
      category = "Applications";
      action.spawn-sh = "helium";
    }
    {
      key = "Mod+D";
      title = "Launcher";
      category = "Applications";
      action.spawn-sh = "noctalia msg panel-toggle launcher";
    }
    {
      key = "Mod+W";
      title = "Wallpaper";
      category = "Applications";
      action.spawn-sh = "skwd wall toggle";
    }
    {
      key = "Mod+B";
      title = "Keybind Cheatsheet";
      category = "Applications";
      action.spawn-sh = "noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet";
    }
    {
      key = "Mod+M";
      title = "Edit Widgets";
      category = "Applications";
      action.spawn-sh = "noctalia msg desktop-widgets-edit";
    }
    {
      key = "Mod+Shift+Delete";
      title = "Power Menu";
      category = "Applications";
      action.spawn-sh = "noctalia msg panel-toggle session";
    }
    {
      key = "Mod+Shift+R";
      title = "Rain Effect";
      category = "Applications";
      action.spawn-sh = "rain-toggle";
    }
    {
      key = "Mod+Shift+Slash";
      title = "Hotkey Overlay";
      category = "Applications";
      action.show-hotkey-overlay = _: {};
    }

    # ── Window Management ──
    # Fullscreen is Mod+Shift+F only; the duplicate Mod+F11 bind was dropped.
    {
      key = "Mod+Q";
      title = "Close Window";
      category = "Window Management";
      action.close-window = _: {};
    }
    {
      key = "Mod+A";
      title = "Overview";
      category = "Window Management";
      action.toggle-overview = _: {};
    }
    {
      key = "Mod+V";
      title = "Toggle Float";
      category = "Window Management";
      action.toggle-window-floating = _: {};
    }
    {
      key = "Mod+Shift+F";
      title = "Fullscreen";
      category = "Window Management";
      action.fullscreen-window = _: {};
    }

    # ── Workspace - Navigation ── (move focus)
    {
      key = "Mod+Left";
      title = "Focus Left";
      category = "Workspace - Navigation";
      action.focus-column-left = _: {};
    }
    {
      key = "Mod+Right";
      title = "Focus Right";
      category = "Workspace - Navigation";
      action.focus-column-right = _: {};
    }
    {
      key = "Mod+Up";
      title = "Workspace Up";
      category = "Workspace - Navigation";
      action.focus-workspace-up = _: {};
    }
    {
      key = "Mod+Down";
      title = "Workspace Down";
      category = "Workspace - Navigation";
      action.focus-workspace-down = _: {};
    }
    {
      key = "Mod+1";
      title = "Workspace 1";
      category = "Workspace - Navigation";
      action.focus-workspace = 1;
    }
    {
      key = "Mod+2";
      title = "Workspace 2";
      category = "Workspace - Navigation";
      action.focus-workspace = 2;
    }
    {
      key = "Mod+3";
      title = "Workspace 3";
      category = "Workspace - Navigation";
      action.focus-workspace = 3;
    }
    {
      key = "Mod+4";
      title = "Workspace 4";
      category = "Workspace - Navigation";
      action.focus-workspace = 4;
    }
    {
      key = "Mod+5";
      title = "Workspace 5";
      category = "Workspace - Navigation";
      action.focus-workspace = 5;
    }
    {
      key = "Mod+WheelScrollUp";
      title = "Scroll Left";
      category = "Workspace - Navigation";
      action.focus-column-left = _: {};
    }
    {
      key = "Mod+WheelScrollDown";
      title = "Scroll Right";
      category = "Workspace - Navigation";
      action.focus-column-right = _: {};
    }

    # ── Workspace - Movement ── (move the focused column)
    {
      key = "Mod+Shift+Left";
      title = "Move Column Left";
      category = "Workspace - Movement";
      action.move-column-left = _: {};
    }
    {
      key = "Mod+Shift+Right";
      title = "Move Column Right";
      category = "Workspace - Movement";
      action.move-column-right = _: {};
    }
    {
      key = "Mod+Shift+Up";
      title = "Move to Workspace Up";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace-up";
    }
    {
      key = "Mod+Shift+Down";
      title = "Move to Workspace Down";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace-down";
    }
    {
      key = "Mod+Shift+1";
      title = "Move to Workspace 1";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace 1";
    }
    {
      key = "Mod+Shift+2";
      title = "Move to Workspace 2";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace 2";
    }
    {
      key = "Mod+Shift+3";
      title = "Move to Workspace 3";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace 3";
    }
    {
      key = "Mod+Shift+4";
      title = "Move to Workspace 4";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace 4";
    }
    {
      key = "Mod+Shift+5";
      title = "Move to Workspace 5";
      category = "Workspace - Movement";
      action.spawn-sh = "niri msg action move-column-to-workspace 5";
    }

    # ── Workspace - Management ── (column sizing within a workspace)
    {
      key = "Mod+J";
      title = "Cycle Width";
      category = "Workspace - Management";
      action.switch-preset-column-width = _: {};
    }
    {
      key = "Mod+R";
      title = "Reset Height";
      category = "Workspace - Management";
      action.reset-window-height = _: {};
    }

    # ── Screenshots ──
    # `grim` needs the `-` operand to write to stdout, and `$(slurp)` must stay
    # quoted: slurp prints "x,y WxH", so an unquoted expansion word-splits and
    # grim reads the "WxH" half as an output filename instead.
    # Full-screen capture (was Mod+S) removed — region capture only.
    {
      key = "Mod+Shift+S";
      title = "Screenshot Region";
      category = "Screenshots";
      action.spawn-sh = "grim -g \"$(slurp)\" - | wl-copy";
    }

    # ── Media ──
    {
      key = "XF86AudioRaiseVolume";
      title = "Volume Up";
      category = "Media";
      action.spawn-sh = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+";
    }
    {
      key = "XF86AudioLowerVolume";
      title = "Volume Down";
      category = "Media";
      action.spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
    }
    {
      key = "XF86AudioMute";
      title = "Mute";
      category = "Media";
      action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
    }
    {
      key = "XF86AudioMicMute";
      title = "Mute Mic";
      category = "Media";
      action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
    }
    {
      key = "XF86AudioNext";
      title = "Next Track";
      category = "Media";
      action.spawn-sh = "${playerctlCmd} next";
    }
    {
      key = "XF86AudioPrev";
      title = "Prev Track";
      category = "Media";
      action.spawn-sh = "${playerctlCmd} previous";
    }
    {
      key = "XF86AudioPlay";
      title = "Play / Pause";
      category = "Media";
      action.spawn-sh = "${playerctlCmd} play-pause";
    }
    {
      key = "XF86AudioPause";
      title = "Play / Pause";
      category = "Media";
      action.spawn-sh = "${playerctlCmd} play-pause";
    }
  ];

  # The wrapper-modules `binds` schema is {"<key>".<action> = <arg>;} — drop the
  # cheatsheet-only metadata and hand it the action attrset.
  mkNiriBinds = args:
    builtins.listToAttrs (map (b: {
      name = b.key;
      value = b.action;
    }) (mkKeybinds args));

  # Render the same list into the KDL dialect the cheatsheet plugin tokenises.
  mkKeybindsKdl = {
    pkgs,
    lib,
  }: let
    binds = mkKeybinds {inherit pkgs lib;};
    renderBind = b: let
      action = builtins.head (builtins.attrNames b.action);
      value = b.action.${action};
      arg =
        # `_: {}` is how the wrapper-modules schema spells a no-argument action.
        if lib.isFunction value
        then ""
        else if builtins.isInt value
        then " ${toString value}"
        else " \"${lib.escape ["\\" "\""] value}\"";
      # Plain string, not '' '' — an indented string would strip the leading spaces.
    in "  ${b.key} hotkey-overlay-title=\"${b.title}\" { ${action}${arg}; }";
    renderCategory = category:
      "  // #\"${category}\"\n"
      + lib.concatMapStringsSep "\n" renderBind
      (builtins.filter (b: b.category == category) binds);
  in
    pkgs.writeText "niri-keybinds.kdl" ''
      // Generated from mkKeybinds in Modules/Desktops/niri.nix — do not edit.
      // Parsed by noctalia's kenn/keybind-cheatsheet plugin; niri never reads it.
      binds {
      ${lib.concatMapStringsSep "\n\n" renderCategory keybindCategories}
      }
    '';

  # config.kdl is the plugin's default `niri_config`; it follows the includes.
  # noctalia.kdl is written by noctalia's own niri theme template.
  niriIncludesKdl = pkgs:
    pkgs.writeText "niri-config-includes.kdl" ''
      // Generated from Modules/Desktops/niri.nix — do not edit.
      // Entry point for noctalia's kenn/keybind-cheatsheet plugin only.
      include "noctalia.kdl"
      include "niri-keybinds.kdl"
    '';
in {
  flake.nixosModules.niri = {
    config,
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
    hardware.bluetooth.powerOnBoot = true;
    hardware.bluetooth.settings.Policy.AutoEnable = "true";
    services.blueman.enable = true;
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    environment.systemPackages = with pkgs; [
      xwayland-satellite
      playerctl
      kdePackages.qttools # Provides qdbus6 for Noctalia D-Bus calls
      # Wrapped steam with GPU workaround for niri.
      #
      # MUST wrap config.programs.steam.package, NOT pkgs.steam. This script is
      # hiPrio, so it wins the `steam` name in the system path and every launch
      # goes through it — including the .desktop override further down, via
      # steam-open. Wrapping bare pkgs.steam therefore silently discards
      # everything Modules/steam.nix configures: it shadowed the Millennium
      # injection *and* the libpulseaudio/pipewire audio fix, both of which
      # looked correctly applied in `nix eval` while never reaching a real
      # launch. Fixed 2026-08-10 — see Claude/steam.md.
      (lib.hiPrio (writeShellScriptBin "steam" ''
        exec ${config.programs.steam.package}/bin/steam -no-cef-sandbox "$@"
      ''))
      # Steam launcher for Noctalia: niri msg action spawn fails to start Steam
      # without a brief delay (known niri issue #2463). sleep 1 fixes it.
      (writeShellScriptBin "steam-open" ''
        if pgrep -x steam >/dev/null; then
          steam steam://open/games &
        else
          sleep 1 && steam "$@" &
        fi
      '')
      # NOTE: pointer confinement for games is handled by gamescope, NOT by anything
      # in this file. There used to be a `game-lock` script on Mod+G that confined the
      # pointer by turning every other output OFF — removed 2026-08-05, that side effect
      # was never wanted (it also relocated the disabled monitor's windows and workspaces
      # and never moved them back).
      #
      # Niri still has no confinement primitive as of 26.04: `niri msg action` lists no
      # pointer/confine/grab action, and a `confine-pointer` window rule fails
      # `niri validate` as an unexpected node. A Wayland client cannot grab the pointer
      # on another client's behalf either, so no external helper can do it.
      #
      # Use gamescope instead — it is a nested compositor that owns the pointer outright.
      # Already available via programs.steam.gamescopeSession (Modules/steam.nix).
      # Per-game Steam launch options:
      #   gamescope -W 2560 -H 1080 -f --force-grab-cursor -- %command%
      # `--force-grab-cursor` forces relative mouse mode so the cursor cannot leave the
      # game. Games that request zwp_pointer_constraints_v1 themselves already work
      # unaided — this is for the ones that don't, usually borderless-windowed mode.
      #
      # Reads last-wallpaper.json from skwd-wall cache and applies swaybg immediately.
      # Runs early in spawn-at-startup so there's no black gap while skwd-daemon
      # initialises (which only happens after systemd graphical-session.target fires).
      #
      # swaybg's layer-shell namespace is "wallpaper", which the `place-within-backdrop`
      # layer-rule below matches — so this instance paints the OVERVIEW BACKDROP, not the
      # per-workspace background (skwd-paper owns that, namespace "skwd-paper"). Both sit
      # on the background layer; niri lifts the matched one into the backdrop. That is the
      # documented two-wallpaper-tool setup. Keep the flags identical to the swaybg call in
      # noctalia-sync-wallpaper (noctalia.nix) — it matches on `pgrep -f 'swaybg -m fill -i'`
      # to retire this login-time instance when the wallpaper changes mid-session.
      (writeShellScriptBin "wallpaper-restore" ''
        CACHE="$HOME/.cache/skwd-wall/last-wallpaper.json"
        [ -f "$CACHE" ] || exit 0
        WALL=$(${pkgs.jq}/bin/jq -r .path "$CACHE" 2>/dev/null)
        [ -n "$WALL" ] && [ -f "$WALL" ] || exit 0
        exec ${pkgs.swaybg}/bin/swaybg -m fill -i "$WALL"
      '')
      # Spotify startup launcher: delayed start for session init, opens to liked songs.
      # Used in niri spawn-at-startup — needs the sleep for session initialization.
      (writeShellScriptBin "spotify-startup" ''
        LIKED_SONGS="spotify:collection:tracks"
        sleep 3  # Wait for desktop/session to fully initialize
        # Once Spotify's CDP port is ready, apply saved matugen colors
        (
          sleep 8
          for _i in 1 2 3 4 5; do
            if ${pkgs.curl}/bin/curl -sf http://127.0.0.1:9222/json/list >/dev/null 2>&1; then
              spotify-apply-colors
              break
            fi
            sleep 3
          done
        ) &
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

    # Override Steam .desktop so the app launcher uses steam-open (with sleep 1 delay).
    # Niri's spawn mechanism requires a delay or Steam silently fails (niri issue #2463).
    home-manager.users.rock.xdg.desktopEntries.steam = {
      name = "Steam";
      exec = "steam-open %U";
      icon = "steam";
      terminal = false;
      categories = ["Network" "FileTransfer" "Game"];
      mimeType = ["x-scheme-handler/steam" "x-scheme-handler/steamlink"];
    };

    # Override Spotify .desktop so the app launcher uses spotify-open instead of spotify.
    # This means the launcher always opens Liked Songs without touching the spotify binary.
    home-manager.users.rock.xdg.desktopEntries.spotify = {
      name = "Spotify";
      genericName = "Music Player";
      exec = "spotify-open %U";
      icon = "${pkgs.spotify}/share/spotify/icons/spotify-linux-512.png";
      terminal = false;
      categories = ["Audio" "Music" "Player" "AudioVideo"];
      mimeType = ["x-scheme-handler/spotify"];
    };

    # Stable symlink to the full baked niri config (keybinds + window rules) — this is
    # the file the compositor actually runs. The wrapper-modules config lives at a store
    # path that changes every rebuild, so this is a fixed path for inspecting it.
    # Debug aid only; nothing reads it at runtime.
    home-manager.users.rock.home.file.".config/niri/niri-full-config.kdl".source =
      "${self.packages.${pkgs.stdenv.hostPlatform.system}.wrappedNiri}/niri-config.kdl";

    # ~/.config/niri/config.kdl and the niri-keybinds.kdl it includes exist ONLY for
    # noctalia's kenn/keybind-cheatsheet plugin, which parses config.kdl (its built-in
    # default for the `niri_config` setting) and follows the `include` directives there.
    #
    # Niri itself NEVER reads these files. The wrapped package pins its own config path,
    # so ~/.config/niri/config.kdl is not consulted even with NIRI_CONFIG unset — check
    # with `env -u NIRI_CONFIG niri validate`, which reports the store path. Editing
    # niri-keybinds.kdl therefore cannot change a live keybind; edit mkKeybinds and
    # rebuild, which regenerates this file from the same list as the baked config.
    #
    # Both files are installed as real files rather than home.file symlinks (the plugin
    # snapshots paths and a store symlink swap can race its reader) and are rewritten
    # unconditionally, so they never drift from the baked config.
    # `after = ["writeBoundary"]` is the raw form of lib.hm.dag.entryAfter — home-manager's
    # lib.hm extension is only in scope inside home-manager.users.<name> submodules, and
    # this is a NixOS module. Ordering after writeBoundary keeps `--dry-run` read-only;
    # the previous "after linkGeneration" wrote to $HOME even on a dry run.
    home-manager.users.rock.home.activation.niriCheatsheet = {
      after = ["writeBoundary"];
      before = [];
      data = ''
        mkdir -p "$HOME/.config/niri"
        install -m 644 ${mkKeybindsKdl {inherit pkgs lib;}} "$HOME/.config/niri/niri-keybinds.kdl"
        install -m 644 ${niriIncludesKdl pkgs} "$HOME/.config/niri/config.kdl"

        # noctalia writes noctalia.kdl from its niri theme template on first run; seed an
        # empty one so a fresh install has no dangling include for the plugin to chase.
        [ -e "$HOME/.config/niri/noctalia.kdl" ] || : > "$HOME/.config/niri/noctalia.kdl"

        # Drop the plugin's parsed-bindings cache so it re-reads the regenerated file.
        rm -f "$HOME/.local/state/noctalia/plugins/data/kenn/keybind-cheatsheet/bindings-cache.json"

        # Superseded by niri-keybinds.kdl — clean up leftovers from earlier generations.
        rm -f "$HOME/.config/niri/keybinds-for-cheatsheet.kdl"
      '';
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

          # Niri pops its built-in "Important Hotkeys" overlay at every session start
          # by default — i.e. on every login out of SDDM. Mod+Shift+Slash still opens
          # it on demand (and Mod+B opens the noctalia cheatsheet panel).
          hotkey-overlay.skip-at-startup = _: {};

          # Screenshot save location
          screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

          spawn-at-startup = [
            # Launch shell/bar first for instant visual feedback
            "noctalia"
            # Apply last wallpaper immediately — before skwd-daemon's systemd service fires
            "wallpaper-restore"
            # D-Bus environment setup runs in background (& at end)
            "sh -c 'dbus-update-activation-environment --systemd --all &'"
            "sh -c 'systemctl --user import-environment --all &'"
            # Clear stale Spotify singleton locks left over from previous sessions/reboots
            "sh -c 'rm -f ~/.cache/spotify/SingletonLock ~/.cache/spotify/SingletonSocket'"
            "spotify-startup"
          ];

          xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

          # Cursor
          cursor.xcursor-theme = "Bibata-Modern-Classic";
          cursor.xcursor-size = 24;

          # Input settings
          input.keyboard.xkb.layout = "us";
          input.mouse.accel-profile = "flat";
          # max-scroll-amount "0%" is what stops the left edge of the screen
          # yanking the view sideways. Without it, moving the pointer to the edge
          # lands it on the sliver of the neighbouring column, focus follows it,
          # and niri scrolls that column into view — so a stray mouse movement
          # silently changes what you're looking at. "0%" keeps focus-follows-mouse
          # for windows already fully on screen and refuses any focus change that
          # would require scrolling. NOT hot-corners, which are separately off.
          # The `_: { ... }` form emits KDL *properties* on the node
          # (`focus-follows-mouse max-scroll-amount="0%"`). A plain attrset would
          # emit child nodes instead, which niri rejects here.
          input.focus-follows-mouse = _: { max-scroll-amount = "0%"; };
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
              // This panel's EDID declares 2560x1080@59.938 as its PREFERRED mode (DTD 1);
              // 144 Hz is DTD 5, off in the CTA-861 extension block. Without this line niri
              // correctly honours the preferred flag and the monitor runs at 60 Hz.
              mode "2560x1080@144.001"
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
              opacity 0.75
              open-on-output "HDMI-A-1"
            }
            // This rule is what actually makes Steam glass — Steam's CEF surface
            // has no alpha channel, so the Millennium theme in Modules/steam.nix
            // cannot make it see-through on its own. Deleting this line does not
            // just un-dim Steam, it removes the effect the theme was built around.
            // See Claude/steam.md. Matches the client window only: in-game windows
            // get app-id "steam_app_<id>", which this regex excludes.
            window-rule {
              match app-id="^steam$"
              opacity 0.85
            }
            // Cult of the Lamb has no in-game monitor selector, so pin its window to
            // HDMI-A-1 (the output Sunshine captures, output_name=HDMI-A-1). open-fullscreen
            // makes it fill the 1080p output so Sunshine streams a full-frame capture.
            // This rule is unconditional — it has nothing to do with whether Moonlight is
            // connected. Sunshine captures a fixed output either way.
            // Two match directives (niri ORs them) because the app-id depends on how it launches:
            //   - bare Steam/Xwayland  -> app-id "steam_app_<appid>"
            //   - under gamescope      -> app-id is UNSET, so only the title can match
            // The game is launched via gamescope (Steam launch options) to stop Unity pausing
            // when it loses focus, so in practice the title rule is the one that fires.
            window-rule {
              match app-id="^steam_app_1313140$"
              match title="^Cult Of The Lamb$"
              open-on-output "HDMI-A-1"
              open-fullscreen true
            }
            window-rule {
              match app-id="^pavucontrol$"
              open-floating true
            }
            window-rule {
              match title="^Picture-in-Picture$"
              open-floating true
            }

            layer-rule {
              match namespace="^wallpaper$"
              place-within-backdrop true
            }
          '';

          # Derived from mkKeybinds at the top of this file — the same list also
          # generates ~/.config/niri/niri-keybinds.kdl for the cheatsheet plugin.
          binds = mkNiriBinds {inherit pkgs lib;};
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
