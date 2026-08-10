{ ... }:
let
  # ============================================================
  # THEME GENERATOR
  # ============================================================
  # Slot names mirror matugen's Material You colour keys. The generator is
  # instantiated twice:
  #   1. `staticTheme`   — literal hex, baked into the store. Seeded on first
  #                        rebuild so btop looks right before any wallpaper
  #                        change, and is the permanent theme on hosts without
  #                        skwd-wall (Asgard, Rescue).
  #   2. `matugenTemplate` — the same mapping with matugen template tokens.
  #                        `Modules/skwd-wall.nix` installs it as a matugen
  #                        template and matugen re-renders it over the seeded
  #                        file on every wallpaper change.
  # Keeping one generator means the two can't drift.
  mkTheme = c: ''
    # btop theme — generated from Modules/btop.nix. Do not edit by hand.
    # On Sisyphus/Elektra/Odysseus this file is overwritten by matugen on every
    # wallpaper change (skwd-wall "btop" integration).

    # main_bg is deliberately empty: btop then paints nothing behind itself and
    # the terminal background shows through (kitty runs at 0.70 opacity).
    # `theme_background = False` in btop.conf enforces the same thing.
    theme[main_bg]=""
    theme[main_fg]="${c.onSurface}"

    theme[title]="${c.onSurface}"
    theme[hi_fg]="${c.primary}"

    theme[selected_bg]="${c.primaryContainer}"
    theme[selected_fg]="${c.primaryFixed}"

    theme[inactive_fg]="${c.outline}"
    theme[graph_text]="${c.onSurfaceVariant}"
    theme[proc_misc]="${c.tertiary}"

    # The unfilled meter track is the one thing allowed to stay dark: it should
    # recede, and losing it over a dark patch of wallpaper costs nothing because
    # the filled portion still reads.
    theme[meter_bg]="${c.outlineVariant}"

    # Borders are uniform and sit just below the text in brightness. With no
    # background of our own the boxes are the only thing giving the layout
    # structure, so they carry `on_surface_variant` — `outline` and
    # `outline_variant` both read as washed-out over a busy wallpaper.
    # Dividers stay one step below the borders.
    theme[cpu_box]="${c.onSurfaceVariant}"
    theme[mem_box]="${c.onSurfaceVariant}"
    theme[net_box]="${c.onSurfaceVariant}"
    theme[proc_box]="${c.onSurfaceVariant}"
    theme[div_line]="${c.outline}"

    # ---- Gradients ----
    # Every ramp stays inside the bright half of the palette. btop interpolates
    # start→mid→end by value, so a dark `start` means an idle system renders in
    # colours that disappear against the wallpaper — which is exactly what the
    # container tones (#00504e, #324863, #3f4948) did here. Bright floors read
    # over a light wallpaper *and* a dark one; dark floors only ever work against
    # a background we control, and with transparency we don't have one.

    # Cool blue when idle, accent when working, error red when hot/loaded.
    theme[temp_start]="${c.tertiary}"
    theme[temp_mid]="${c.primary}"
    theme[temp_end]="${c.error}"

    theme[cpu_start]="${c.tertiary}"
    theme[cpu_mid]="${c.primary}"
    theme[cpu_end]="${c.error}"

    # Memory / disks — one hue per meter so the four bars stay distinguishable,
    # each ramping dim→bright within that hue rather than dark→light.
    theme[free_start]="${c.onSurfaceVariant}"
    theme[free_mid]="${c.onSurface}"
    theme[free_end]="${c.onSurface}"

    theme[cached_start]="${c.secondary}"
    theme[cached_mid]="${c.secondaryFixed}"
    theme[cached_end]="${c.secondaryFixed}"

    theme[available_start]="${c.tertiary}"
    theme[available_mid]="${c.tertiaryFixed}"
    theme[available_end]="${c.tertiaryFixed}"

    theme[used_start]="${c.primary}"
    theme[used_mid]="${c.primaryFixed}"
    theme[used_end]="${c.error}"

    # Network — download on the primary ramp, upload on the tertiary ramp
    theme[download_start]="${c.primary}"
    theme[download_mid]="${c.primaryFixed}"
    theme[download_end]="${c.primaryFixed}"

    theme[upload_start]="${c.tertiary}"
    theme[upload_mid]="${c.tertiaryFixed}"
    theme[upload_end]="${c.tertiaryFixed}"

    # Process list Cpu% column: neutral when idle, accent when busy, red for hogs
    theme[process_start]="${c.onSurfaceVariant}"
    theme[process_mid]="${c.primary}"
    theme[process_end]="${c.error}"

    # Process box banners (pause / follow). These are the only elements that
    # paint a real cell background, so a dark container tone is safe here.
    theme[proc_pause_bg]="${c.error}"
    theme[proc_follow_bg]="${c.tertiary}"
    theme[proc_banner_bg]="${c.primaryContainer}"
    theme[proc_banner_fg]="${c.primaryFixed}"
    theme[followed_bg]="${c.tertiaryContainer}"
    theme[followed_fg]="${c.tertiaryFixed}"
  '';

  # Fallback palette — matugen "scheme-tonal-spot" dark output for a teal source
  # colour, i.e. the same shape skwd-wall generates. Only ever visible before the
  # first wallpaper change, or on hosts with no skwd-wall.
  fallbackPalette = {
    onSurface = "#dde4e3";
    onSurfaceVariant = "#bec9c7";
    outline = "#889392";
    outlineVariant = "#3f4948";
    primary = "#80d5d2";
    primaryFixed = "#9cf1ef";
    primaryContainer = "#00504e";
    secondary = "#b0ccca";
    secondaryFixed = "#cce8e6";
    secondaryContainer = "#324b4a";
    tertiary = "#b2c8e8";
    tertiaryFixed = "#d2e4ff";
    tertiaryContainer = "#324863";
    error = "#ffb4ab";
  };

  matugenPalette = {
    onSurface = "{{colors.on_surface.default.hex}}";
    onSurfaceVariant = "{{colors.on_surface_variant.default.hex}}";
    outline = "{{colors.outline.default.hex}}";
    outlineVariant = "{{colors.outline_variant.default.hex}}";
    primary = "{{colors.primary.default.hex}}";
    primaryFixed = "{{colors.primary_fixed.default.hex}}";
    primaryContainer = "{{colors.primary_container.default.hex}}";
    secondary = "{{colors.secondary.default.hex}}";
    secondaryFixed = "{{colors.secondary_fixed.default.hex}}";
    secondaryContainer = "{{colors.secondary_container.default.hex}}";
    tertiary = "{{colors.tertiary.default.hex}}";
    tertiaryFixed = "{{colors.tertiary_fixed.default.hex}}";
    tertiaryContainer = "{{colors.tertiary_container.default.hex}}";
    error = "{{colors.error.default.hex}}";
  };

  themeName = "dots";
in {
  # Consumed by Modules/skwd-wall.nix, which writes this into skwd-wall's
  # matugen template directory and registers the "btop" integration.
  flake.lib.btop = {
    inherit themeName;
    matugenTemplate = mkTheme matugenPalette;
  };

  flake.nixosModules.btop = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser} = { lib, ... }:
    let
      seed = pkgs.writeText "btop-${themeName}.theme" (mkTheme fallbackPalette);
    in {
      # Wallpaper changes repaint a *running* btop. SIGUSR2 is btop's hot-reload
      # signal (same path as Ctrl+R): it re-runs init_config, Theme::updateThemes
      # and Theme::setTheme, and setTheme calls loadFile() — so the theme comes
      # back off disk rather than from a cache. No restart, no lost state.
      #
      # Registered as the skwd-wall "btop" integration's reload command, which
      # runs with a trimmed PATH — hence the store path for pkill, and hence
      # this being a package rather than a script in ~/.local/bin. See
      # Claude/skwd-wall.md.
      home.packages = [
        (pkgs.writeShellScriptBin "btop-reload-theme" ''
          # `-x btop`: nixpkgs does not wrap btop, so the process name is exactly
          # "btop". Matching is verified in Claude/misc.md.
          # pkill exits 1 when nothing matched (no btop running), which skwd-daemon
          # would log as a failed reload — that case is normal, so swallow it.
          ${pkgs.procps}/bin/pkill -USR2 -x btop || true
        '')
      ];

      programs.btop = {
        enable = true;

        settings = {
          # ---- Look ----
          color_theme = themeName;
          # The one knob that actually makes btop transparent: with this off btop
          # skips painting main_bg and the terminal background shows through.
          theme_background = false;
          truecolor = true;
          rounded_corners = true;

          # Braille everywhere — 4x the horizontal resolution of the block symbols
          # and a far finer texture. The per-box overrides are deliberately left
          # unset so they inherit this; "block" renders the mem and process graphs
          # as chunky solid slabs that look nothing like the rest of the UI.
          graph_symbol = "braille";

          shown_boxes = "cpu mem net proc";
          update_ms = 1000;
          clock_format = "%H:%M";

          # `p` / `shift+p` cycle presets. Preset 0 is always "all boxes, default
          # settings" and is implicit — these are 1 (CPU + processes, CPU in the
          # alternate position) and 2 (dashboard: no process list).
          presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default";

          # ---- CPU ----
          cpu_graph_upper = "total";
          cpu_graph_lower = "total";
          cpu_invert_lower = true;
          cpu_single_graph = false;
          cpu_bottom = false;
          check_temp = true;
          show_coretemp = true;
          temp_scale = "celsius";
          show_cpu_freq = true;
          show_uptime = true;

          # ---- Memory / disks ----
          mem_graphs = true;
          mem_below_net = false;
          show_swap = true;
          swap_disk = true;
          show_disks = true;
          only_physical = true;
          use_fstab = true;
          show_io_stat = true;

          # ---- Processes ----
          proc_sorting = "cpu lazy";
          # Off deliberately. The gradient fades rows toward `inactive_fg` as you
          # go down the list, which looks good on a solid dark background and is
          # unreadable over a wallpaper — it was washing out most of the process
          # list. Rows now all render at full strength.
          proc_gradient = false;
          proc_colors = true;
          proc_mem_bytes = true;
          proc_cpu_graphs = true;
          proc_tree = false;
          proc_per_core = false;

          # ---- Misc ----
          # Desktops and the server — no battery meter cluttering the CPU box.
          show_battery = false;
          background_update = true;
          log_level = "WARNING";
        };
      };

      # The theme file cannot be a home-manager symlink: on skwd-wall hosts matugen
      # rewrites this exact path on every wallpaper change, and store symlinks are
      # read-only. Seed it as a plain writable file instead.
      #
      # Refresh rule: write the seed when the file is missing, or when it is still
      # byte-identical to the seed installed last time (i.e. matugen has not taken
      # ownership yet). Once matugen has written it, edits to the palette above
      # stop clobbering the live colours.
      home.activation.btopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        themeDir="$HOME/.config/btop/themes"
        dest="$themeDir/${themeName}.theme"
        prev="$themeDir/.${themeName}.seed"

        run ${pkgs.coreutils}/bin/mkdir -p "$themeDir"

        if [ ! -e "$dest" ] || { [ -e "$prev" ] && ${pkgs.diffutils}/bin/cmp -s "$dest" "$prev"; }; then
          run ${pkgs.coreutils}/bin/install -m 0644 ${seed} "$dest"
        fi
        run ${pkgs.coreutils}/bin/install -m 0644 ${seed} "$prev"
      '';
    };
  };
}
