# Elektra — her noctalia bar and desktop shell. Hers only; see
# Hosts/Elektra/system.nix. The shell itself is Modules/Desktop/noctalia.nix.
#
# ⚠️ This goes in `lockedSettingsExtra`, NEVER the shared lock in
# Modules/Desktop/noctalia.nix — that one is every host's.
{ ... }: {
  flake.nixosModules.elektra-noctalia = { ... }: {
    # ── Her noctalia desktop ──────────────────────────────────────────────
    #
    # Captured from what she actually dialled in through the GUI. It has to be
    # here: Modules/Desktop/noctalia.nix force-writes settings.toml on every rebuild,
    # so anything not recorded in Nix is silently reverted at the next switch.
    # Read back off her machine, not invented.
    my.noctalia.lockedSettingsExtra = {
      # The global corner-roundness scale (Appearance -> Interface in the GUI),
      # range 0.0-2.0. Setting it to 0 squares EVERYTHING noctalia draws in one
      # place — bar, panels, popups, lockscreen — rather than hunting down each
      # widget's own radius/capsule_radius.
      shell.corner_radius_scale = 0.0;

      # The rounded overlay noctalia paints over the four SCREEN corners
      # (Desktop -> Screen corners in the GUI). Separate from
      # corner_radius_scale above, which only scales the radii of noctalia's
      # own surfaces — this one masks the physical display edges, so it is
      # what makes "the corners of the screen look round".
      #
      # `enabled = false` rather than `size = 0`: turning it off in the GUI
      # leaves enabled = true and only drops the size, which still composites
      # a (tiny) mask every frame. rock keeps his at size 35.
      shell.screen_corners.enabled = false;

      bar.main = {
        # Bar radius explicitly 0 as well — corner_radius_scale above scales
        # radii, and 0 x anything is 0, but being explicit costs nothing.
        radius = 0;
        position = "bottom";
        # Solid, like every window — she wants the terminal to be the only
        # see-through thing on the desktop (2026-11-23; was 0.88).
        background_opacity = 1.0;
        scale = 1.05;
        thickness = 32;
        margin_ends = 0;
        start = [ "workspaces" "spacer_2" "taskbar" ];
        end = [ "volume" "keybinds" "network" "bluetooth" "notifications" "tray" "clock" ];

        # The media/visualizer capsule carries its own radius, and it is a LIST
        # so recursiveUpdate replaces it wholesale rather than merging — the
        # whole entry has to be restated, not just the radius.
        capsule_group = [{
          id = "g1";
          enabled = true;
          members = [ "media" "audio_visualizer" ];
          fill = "surface_variant";
          opacity = 0.45;
          padding = 9.0;
          radius = 0;
        }];
      };

      # Only what differs from the shared lock in Modules/Desktop/noctalia.nix.
      # Her audio_visualizer, network, taskbar (including show_all_outputs,
      # the "show it on every monitor's bar" toggle she found herself in the
      # GUI) and tray.drawer settings are identical to it, so they are
      # inherited rather than restated.
      widget = {
        clock = { capsule = false; capsule_opacity = 0.34; };
        keybinds.type = "kenn/keybind-cheatsheet:keybinds";
        spacer_2 = { capsule = false; length = 104; scale = 0.4; type = "spacer"; };

        # show_labels = false hides the workspace NUMBERS, leaving just the
        # pills. (Noctalia 5.2 split the old `display = "none" | "id" |
        # "name"` into show_labels + label_source; `noctalia config
        # validate` flags the old key.)
        workspaces = { show_labels = false; };
      };
    };
  };
}
