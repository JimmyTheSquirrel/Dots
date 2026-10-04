# ============================================================================
# Skwd-wall v2 — upstream flake + our colour-pipeline wiring
# ============================================================================
#
# Upstream now ships NixOS support on the `nix` branch, so this file no longer
# builds anything. It imports `nixosModules.default` (which installs the suite
# and defines skwd-walld) and adds only the parts that are ours: the matugen
# integrations that drive noctalia/spicetify/btop/Steam, and the templates
# those integrations render.
#
# Upstream's flake distributes *prebuilt release binaries* autoPatchelf'd
# against its own pinned nixpkgs. Do NOT add `inputs.nixpkgs.follows` — the
# derivations then stop matching the store paths upstream publishes in
# channel.json and every build becomes a local rebuild instead of a cache hit.
#
# Serves Sisyphus (niri) and Kit-Kat (Hyprland). v1 (QuickShell,
# Modules/skwd-wall.nix) is gone along with the Elektra and Odysseus hosts it
# served; v2 keeps its own ~/.config/skwd-wall-v2 and ~/.cache/skwd-wall-v2, so
# nothing of v1's lingering state is read.
# ============================================================================
{ self, inputs, ... }:
{
  flake.nixosModules.skwd = { pkgs, lib, config, activeUser, ... }:
  let
    skwd = inputs.skwd-wall-v2.packages.${pkgs.stdenv.hostPlatform.system};

    # The spicetify pair belongs to the matugen/Text-theme path only. On a host
    # that has picked an upstream theme (my.spicetify.theme) they are actively
    # harmful, so they are DELETED rather than merely skipped: an integration
    # seeded by an earlier rebuild keeps rendering into
    # ~/.config/spicetify/Themes/text/color.ini — a directory the new theme does
    # not have — and keeps calling spotify-apply-colors, which is no longer
    # built. skwd never logs a failed reload (see the `path` comment below), so
    # leaving them in place would be a silent 127 on every wallpaper change.
    #
    # `or null` so this module still evaluates on a host that imports skwd
    # without spicetify; null is the pre-existing behaviour.
    #
    # The two templates are still written either way — matugen only renders
    # what a live integration references, so an orphan template is inert.
    #
    # NOTE: no apostrophes in the jq below, same reason as the main program.
    spicetifyIntegrations =
      if (config.my.spicetify.theme or null) == null then ''
          | upsert({name: "spicetify", template: "spicetify-text.ini", output: "~/.config/spicetify/Themes/text/color.ini"})
          | upsert({name: "spicetify-live", template: "spicetify-colors.json", output: "~/.config/spicetify/matugen-colors.json", reload: "spotify-apply-colors"})
      '' else ''
          | .integrations = ((.integrations // []) | map(select(.name != "spicetify" and .name != "spicetify-live")))
      '';

    # Steam: same shape as the spicetify pair. The integration renders a
    # Millennium Quick CSS, so it only means anything where Millennium is
    # injected (my.steam.millennium, Modules/Gaming/steam.nix). Kit-Kat runs
    # plain Steam, where it was rendering into a quick.css nothing loads; it is
    # deleted there rather than skipped, for the same reason as above.
    #
    # Steam gets no reload: Millennium Quick CSS cannot be re-read from outside
    # the client, so a new accent lands at the next Steam launch.
    steamIntegration =
      if config.my.steam.millennium or false then ''
          | upsert({name: "steam", template: "steam-quick.css", output: "~/${self.lib.steam.quickCssPath}"})
      '' else ''
          | .integrations = ((.integrations // []) | map(select(.name != "steam")))
      '';

    # ---- niri overview backdrop ----
    # Pinned on niri, unlike the rest of the user-tunable skwd settings, because
    # it is structural rather than taste: it REPLACES the swaybg instance and
    # the `wallpaper-restore` script that were deleted on 2026-09-15. Left
    # unpinned, a fresh install would come up with no overview backdrop at all,
    # and toggling it off in the settings UI would silently lose one.
    #
    # backdropFollowWallpaper must be true or the backdrop stays pinned to
    # whatever single image `niri.backdrop` names — which is how it ended up
    # showing a stale, unrelated wallpaper earlier that day.
    #
    # The look knobs — overviewBackdropBlurEnabled, overviewBackdropBlur,
    # backdropDim, backdropTheme — are deliberately NOT pinned; tune those
    # in the settings UI. The paired niri layer-rule lives in
    # Modules/Desktop/niri.nix and is what keeps the surface in the
    # overview instead of on top of the desktop.
    #
    # Everywhere else (Kit-Kat's Hyprland) it is forced OFF. There is no niri
    # overview to put it in and no `place-within-backdrop` rule to keep it
    # there, so a backdrop surface would only be a second background layer
    # painted over the real wallpaper — and this module used to force it ON for
    # every host, so Kit-Kat's config.json still says true until this runs.
    niriBackdrop =
      if config.programs.niri.enable then ''
          | .niri.overviewBackdrop = true
          | .niri.backdropFollowWallpaper = true
      '' else ''
          | .niri.overviewBackdrop = false
      '';
  in
  {
    # Installs the suite + the SigLIP 2 model pack system-wide, exports
    # SKWD_LENS_HOME, and defines the skwd-walld user unit.
    imports = [ inputs.skwd-wall-v2.nixosModules.default ];

    services.skwd-deck.enable = true;

    systemd.user.services.skwd-walld = {
      # Upstream's module drops the flag that its own shipped unit file passes.
      # Without it the daemon can come up before the Wayland socket exists and
      # has to be restarted into a working session by Restart=on-failure.
      serviceConfig.ExecStart = lib.mkForce "${skwd.deck}/bin/skwd-walld --wait-for-session";

      # `path` renders as Environment=PATH=…, which REPLACES the inherited PATH
      # rather than extending it — so listing anything here (upstream lists
      # paper and lens) drops the user profile off the daemon's PATH. The
      # integration reload commands below (noctalia-apply-palette,
      # spotify-apply-colors, btop-reload-theme) are home.packages, and without
      # these two entries every reload fails with `exit status: 127`.
      #
      # Note skwd does NOT log a failed reload — no "command failed" line ever
      # appears in skwd-walld.log — so a broken PATH here is silent. Verify by
      # checking that the reload's output file mtime moves across an apply.
      path = [
        "/etc/profiles/per-user/${activeUser}"
        "/run/current-system/sw"
      ];
    };

    # `lib` here comes from home-manager, not the NixOS module args — the
    # activation script needs lib.hm.dag, which only exists on HM's lib.
    home-manager.users.${activeUser} = { config, lib, hostName, ... }:
    let
      # The seeded config.json names a monitor, and connector names are per-machine.
      # Only hosts listed here get the key; anywhere else it is omitted and skwd
      # fills in its own default on first run. Guessing a connector that does not
      # exist is worse than letting the daemon pick.
      seedMonitor = { Sisyphus = "DP-2"; }.${hostName} or null;
      monitorSeed = if seedMonitor == null then "" else "  \"monitor\": \"${seedMonitor}\",";
      configPath = "${config.home.homeDirectory}/.config/skwd-wall-v2";
      # NOT data/matugen/templates. `data/` is the layout inside the *package*
      # (share/skwd-wall-v2/data/matugen/templates); the daemon's own seeder
      # writes user templates to ~/.config/skwd-wall-v2/matugen/templates and
      # resolves integrations[].template against that, with no `data/`.
      # Getting this wrong is silent-ish: the integrations still run, they just
      # log `template not found` once per integration per apply and never
      # render. Measured 2026-09-14: 3435 such warnings, +5 per wallpaper apply,
      # and every colour output on disk was a static Nix fallback, not a render.
      templateDir = "${configPath}/matugen/templates";

      # Store-backed templates, so btop's and Steam's colour mappings have
      # exactly one definition (Modules/Shell/btop.nix, Modules/Gaming/steam.nix) shared with
      # the static fallback themes.
      btopTemplate = pkgs.writeText "btop-theme.theme" self.lib.btop.matugenTemplate;
      steamTemplate = pkgs.writeText "steam-quick.css" self.lib.steam.matugenTemplate;
      discordTemplate = pkgs.writeText "discord-colors.css" self.lib.discord.matugenTemplate;

      # First-run seed for config.json — written only when the file is missing,
      # see the activation script.
      configSeed = pkgs.writeText "skwd-wall-v2-config.json" ''
        {
        ${monitorSeed}
          "paths": {
            "wallpaper": "~/Pictures/Wallpapers",
            "videoWallpaper": "~/Pictures/Wallpapers",
            "steam": "~/.local/share/Steam"
          },
          "features": {
            "matugen": true,
            "steam": true,
            "wallhaven": true
          },
          "matugen": {
            "schemeType": "scheme-tonal-spot",
            "mode": "dark"
          },
          "wallpaperMute": true
        }
      '';

      # noctalia's custom-palette schema: a dark and a light block, each with
      # the mXxx roles plus a terminal sub-object. Both blocks are always
      # emitted so `noctalia msg theme-mode-set light` works without a
      # wallpaper re-apply — skwd-iris resolves `.dark` / `.light` independently
      # of the configured matugen.mode (verified 2026-09-15).
      #
      # Surfaces follow the wallpaper. They used to be pinned to neutral greys
      # (#0a0a0a / #1a1a1a / #333333) which made the bar ignore the palette
      # entirely; the surface* roles keep the same dark weight while picking up
      # the wallpaper's tint.
      #
      # The terminal block maps skwd's real ansi_* roles rather than deriving
      # fake ANSI colours from Material roles, which is what the old hand-built
      # palette did (its "blue" was tertiary and its "green" was primary).
      #
      # One function for both modes: the two blocks used to be written out by
      # hand and differed only in `.dark.` vs `.light.`.
      paletteFor = mode: let
        c = role: "{{colors.${role}.${mode}.hex}}";
      in {
        mPrimary = c "primary";
        mOnPrimary = c "on_primary";
        mSecondary = c "secondary";
        mOnSecondary = c "on_secondary";
        mTertiary = c "tertiary";
        mOnTertiary = c "on_tertiary";
        mError = c "error";
        mOnError = c "on_error";
        mSurface = c "surface";
        mOnSurface = c "on_surface";
        mSurfaceVariant = c "surface_variant";
        mOnSurfaceVariant = c "on_surface_variant";
        mOutline = c "outline";
        mShadow = c "shadow";
        mHover = c "tertiary";
        mOnHover = c "on_tertiary";
        terminal = {
          background = c "surface";
          foreground = c "on_surface";
          cursor = c "primary";
          cursorText = c "on_primary";
          selectionBg = c "surface_variant";
          selectionFg = c "on_surface_variant";
          normal = {
            black = c "surface_variant";
            red = c "ansi_red";
            green = c "ansi_green";
            yellow = c "ansi_yellow";
            blue = c "ansi_blue";
            magenta = c "ansi_magenta";
            cyan = c "ansi_cyan";
            white = c "on_surface";
          };
          bright = {
            black = c "outline";
            red = c "ansi_red_bright";
            green = c "ansi_green_bright";
            yellow = c "ansi_yellow_bright";
            blue = c "ansi_blue_bright";
            magenta = c "ansi_magenta_bright";
            cyan = c "ansi_cyan_bright";
            white = c "on_surface";
          };
        };
      };
      noctaliaPaletteTemplate = pkgs.writeText "noctalia-palette.json"
        (builtins.toJSON { dark = paletteFor "dark"; light = paletteFor "light"; });

      spicetifyColorsTemplate = pkgs.writeText "spicetify-colors.json" ''
        {
          "--spice-text": "{{colors.on_primary_container.default.hex}}",
          "--spice-subtext": "{{colors.on_surface_variant.default.hex}}",
          "--spice-main": "{{colors.surface.default.hex}}",
          "--spice-accent": "{{colors.primary.default.hex}}",
          "--spice-accent-active": "{{colors.primary_container.default.hex}}",
          "--spice-accent-inactive": "{{colors.surface.default.hex}}",
          "--spice-banner": "{{colors.primary.default.hex}}",
          "--spice-border-active": "{{colors.primary.default.hex}}",
          "--spice-border-inactive": "{{colors.outline.default.hex}}",
          "--spice-header": "{{colors.primary_container.default.hex}}",
          "--spice-highlight": "{{colors.surface_container.default.hex}}",
          "--spice-notification": "{{colors.primary_container.default.hex}}",
          "--spice-notification-error": "{{colors.error.default.hex}}"
        }
      '';

      spicetifyTextTemplate = pkgs.writeText "spicetify-text.ini" ''
        [Matugen]
        accent             = {{colors.primary.default.hex_stripped}}
        accent-active      = {{colors.primary_container.default.hex_stripped}}
        accent-inactive    = {{colors.surface.default.hex_stripped}}
        banner             = {{colors.primary.default.hex_stripped}}
        border-active      = {{colors.primary.default.hex_stripped}}
        border-inactive    = {{colors.outline.default.hex_stripped}}
        header             = {{colors.primary_container.default.hex_stripped}}
        highlight          = {{colors.surface_container.default.hex_stripped}}
        main               = {{colors.surface.default.hex_stripped}}
        notification       = {{colors.primary_container.default.hex_stripped}}
        notification-error = {{colors.error.default.hex_stripped}}
        subtext            = {{colors.on_surface_variant.default.hex_stripped}}
        text               = {{colors.on_primary_container.default.hex_stripped}}
      '';
    in {
      # The suite itself is in environment.systemPackages via upstream's module.
      # matugen is not part of it, and without matugen every integration fails
      # silently (skwd-walld catches the error and swallows it).
      #
      # wallust/pywal are the non-Material-You extraction backends. skwd's
      # `theme.authority` lists them, but it SHELLS OUT to the binary and falls
      # back to skwd-iris when it is missing — with no error, so the setting
      # appears to take and nothing changes. They are here purely so that
      # choosing them in the settings UI actually does something; the choice
      # itself stays UI state and is deliberately not pinned (see below).
      #
      # Why they are worth having: iris/matugen/caelestia are all Material You,
      # which derives an entire palette from ONE source colour by tonal maths —
      # so every wallpaper lands on a similar-feeling scheme by design. wallust
      # quantises the actual image instead (its `kmeans` backend samples across
      # the whole frame), which is what gives a genuinely different spread per
      # wallpaper.
      home.packages = [ pkgs.matugen pkgs.wallust pkgs.pywal ];

      # ============================================================
      # CONFIG + MATUGEN TEMPLATES
      # ============================================================
      # Deliberately NOT a full seeded config.json. v2's schema is large and it
      # normalises its own defaults on first run, so a hand-written seed would
      # go stale and fight the settings UI. Create the file only if missing,
      # then patch in just the parts Nix owns.
      home.activation.skwdWallV2Config = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${templateDir}"
        # skwd renders straight into noctalia's palette dir, which does not exist
        # on a fresh install until noctalia's settings UI first writes a palette.
        mkdir -p "${config.home.homeDirectory}/.config/noctalia/palettes"
        # Vencord only creates themes/ once a theme is installed through its UI.
        mkdir -p "${config.home.homeDirectory}/.config/vesktop/themes"

        # 0644 so skwd (and the jq pass below) can rewrite it.
        [ -f "${configPath}/config.json" ] \
          || install -m 0644 ${configSeed} "${configPath}/config.json"
        # ⚠️ `matugen` above is a v1 leftover and is NOT what generates the
        # palette on v2. The engine is skwd-iris, configured by the top-level
        # `theme` object (authority / scheme / style) — the daemon logs
        # `theme apply: backend=skwd-iris` per apply. Verified 2026-09-15:
        # `.dark` / `.light` template variants both resolve regardless of
        # `matugen.mode`, so that key does nothing here.
        #
        # The keys are left in the seed because `features.matugen` still gates
        # the integration renderer (which uses matugen TEMPLATE SYNTAX, and needs
        # pkgs.matugen on PATH) — but do not reach for `matugen.schemeType` when
        # the colours look wrong. Reach for `theme.authority` first; see
        # Claude/skwd-wall.md.
        #
        # `theme.*` and the other taste keys below are seeded as DEFAULTS ONLY —
        # `setdefault` writes a value just when the key is absent, so a fresh
        # install gets a sane, tuned starting point while anything dialled in
        # through the settings UI afterwards survives every rebuild. (This used
        # to say theme.* was not seeded at all. The cost of that showed up on
        # Kit-Kat's first install: with no `theme.engine` the daemon fell back to
        # the skwd-iris backend instead of pywal, so her colours were derived
        # differently from Sisyphus's for no reason anyone had chosen.)
        #
        # The `niri.*` backdrop keys further down stay FORCED, because they are
        # structural rather than taste.

        # ---- Integrations ----
        # matugen renders each template after a wallpaper change, then runs the
        # integration's `reload` command (no arguments). Every entry is upserted
        # by name so hand-edits in the settings UI survive and repeated rebuilds
        # cannot stack duplicates.
        ${pkgs.jq}/bin/jq '
          def upsert($entry):
            if (.integrations // []) | map(.name) | index($entry.name) then
              .integrations = (.integrations | map(if .name == $entry.name then . * $entry else . end))
            else
              .integrations = ((.integrations // []) + [$entry])
            end;

          # Write $v at $p only when nothing is there yet. getpath returns null
          # for a missing path, so an existing explicit null is treated as unset
          # too — which is what we want, a null engine is no engine.
          def setdefault($p; $v):
            if (getpath($p) == null) then setpath($p; $v) else . end;

          # ---- Taste defaults, read off Sisyphus 2026-10-03 ----
          # Parity with the config rock dialled in so a new machine does not start
          # from upstream bare defaults. All setdefault, so the GUI still wins.
          #
          # NOTE: no apostrophes in this jq program (single-quoted shell arg).
          setdefault(["theme","engine"];    "pywal")
          | setdefault(["theme","authority"]; "skwd")
          | setdefault(["theme","policy"];    "wallpaper")
          | setdefault(["theme","scheme"];    "vibrant")
          | setdefault(["theme","style"];     "natural")

          # iris is the transition rock runs. The shader is NOT the reason an
          # apply feels slow — measured 2026-10-03, a retheme with no wallpaper
          # change costs 3 ms. The time goes on CPU JPEG decode of the source
          # image, so a 42 MP wallpaper costs ~3 s and an 11 MP one ~0.3 s.
          | setdefault(["transition","shader"]; "iris")

          | setdefault(["launch","animation"];   "fade")
          | setdefault(["motion","launchSpeed"]; "standard")

          # Apply to the monitor the picker is on, rather than every output.
          # Worth ~500 ms per apply on a two-monitor machine, with the tradeoff
          # that each screen then keeps its own wallpaper instead of sharing one.
          | setdefault(["general","applyOnPickerMonitor"]; true)

          # Square corners on the picker itself — she does not want rounded
          # anything, and rock runs it squared too.
          | setdefault(["components","wallpaperSelector","roundCorners"]; false)

          | setdefault(["sources","unsplash","enabled"]; true)
          | setdefault(["sources","pexels","enabled"];   true)
          | setdefault(["sources","youtube","enabled"];  true)
          | setdefault(["postProcessOnRestore"]; true)

          # noctalia is the fan-out hub: skwd-iris is the only palette generator,
          # and noctalia re-renders its own UI plus every template it has enabled
          # (discord, etc.) from the palette written here.
          #
          # The output MUST be the custom-palette file, not colors.json. noctalia
          # reads whatever `theme.custom_palette` names under palettes/, and reads
          # colors.json never — writing there is silently inert. Measured
          # 2026-09-15: skwd had been refreshing colors.json on every swap while
          # palettes/skwd-wall.json — the file actually read — had not changed in
          # five days, so noctalia and everything downstream of it (Discord, the
          # noctalia btop theme) were frozen on a stale palette.
          #
          # NOTE: no apostrophes anywhere in this jq program — it is passed inside
          # a single-quoted shell argument, so one apostrophe ends the string and
          # the activation script dies with a bash syntax error.
          #
          # reload, NOT postProcessing: `color-scheme-set` takes no wallpaper path,
          # and the reload of an integration is the only hook guaranteed to run
          # *after* the file of that integration is on disk. (postProcessing fires
          # earlier in the apply, before the template renders.)
          | upsert({name: "noctalia", template: "noctalia-palette.json", output: "~/.config/noctalia/palettes/skwd-wall.json", reload: "noctalia-apply-palette"})

        ${spicetifyIntegrations}
          | upsert({name: "btop", template: "btop-theme.theme", output: "~/.config/btop/themes/${self.lib.btop.themeName}.theme", reload: "btop-reload-theme"})

          # Discord. No reload: Vencord watches ~/.config/vesktop/themes and
          # hot-reloads a changed theme file by itself.
          #
          # This renders a colours-only file that quickCss consumes — NOT a full
          # theme. Do not point this at a complete Discord theme: the client runs
          # transparent here, and an opaque theme layered under the transparency
          # quickCss makes it glitch. See Modules/Apps/discord.nix.
          | upsert({name: "discord", template: "discord-colors.css", output: "~/.config/vesktop/themes/${self.lib.discord.matugenThemeFile}"})

        ${niriBackdrop}
        ${steamIntegration}
          # postProcessing is deliberately empty. It used to run
          # `noctalia-sync-wallpaper %path%`; that script is gone — its colour
          # work moved to the noctalia integration reload above (the right hook:
          # postProcessing fires BEFORE templates render, so anything
          # colour-related there pushes the previous palette), and its swaybg
          # backdrop swap was retired when skwd took over the niri overview
          # backdrop natively via `niri.overviewBackdrop`.
          #
          # Anything added here in future must genuinely need the wallpaper path:
          # %path% substitution is the only thing postProcessing offers over a
          # reload, and it is paid for by running too early to see new colours.
        ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
          && mv "${configPath}/config.json.tmp" "${configPath}/config.json"

        # ---- Templates ----
        # Upstream's shipped set first (only where absent, so edits stick),
        # then the ones Nix owns, which are always refreshed.
        for t in ${skwd.default}/share/skwd-wall-v2/data/matugen/templates/*; do
          [ -e "$t" ] || continue
          [ -e "${templateDir}/$(basename "$t")" ] || install -m 0644 "$t" "${templateDir}/"
        done

        # Mode 0644, not the 0444 of a store copy — the next rebuild has to be
        # able to overwrite these, and matugen only ever reads them.
        install -m 0644 ${btopTemplate} "${templateDir}/btop-theme.theme"
        install -m 0644 ${steamTemplate} "${templateDir}/steam-quick.css"
        install -m 0644 ${discordTemplate} "${templateDir}/discord-colors.css"
        install -m 0644 ${noctaliaPaletteTemplate} "${templateDir}/noctalia-palette.json"
        install -m 0644 ${spicetifyColorsTemplate} "${templateDir}/spicetify-colors.json"
        install -m 0644 ${spicetifyTextTemplate} "${templateDir}/spicetify-text.ini"
      '';
    };
  };
}
