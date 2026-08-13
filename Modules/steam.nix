{ self, inputs, ... }:
let
  # ============================================================
  # MILLENNIUM QUICK CSS GENERATOR
  # ============================================================
  # Zehn's ENTIRE accent system resolves from one variable:
  #     --zehn-rgb-accent: var(--SystemAccentColor-RGB, 210, 115, 138)
  # with ~30 shades (accent-10..100, darken/lighten/negative) derived from it.
  # --SystemAccentColor-RGB is a Windows DWM value: nothing sets it on Linux and
  # Steam does not define it either, so Zehn renders with no live accent at all —
  # selections and borders come out flat black. Supplying the one triplet Windows
  # would have supplied is the whole fix.
  #
  # Must be a bare "R, G, B" triplet, NOT a hex — Zehn consumes it as
  # rgb(var(--SystemAccentColor-RGB)).
  #
  # Same two-instantiation trick as Modules/btop.nix, so the two can't drift:
  #   1. `staticQuickCss`  — literal hex, seeded so Steam has an accent before
  #                          any wallpaper change (and on hosts without skwd-wall).
  #   2. `matugenTemplate` — same file with matugen tokens. Modules/skwd-wall.nix
  #                          installs it and matugen re-renders it over the seed
  #                          on every wallpaper change.
  mkQuickCss = a: ''
    /* Millennium Quick CSS — generated from Modules/steam.nix. Do not edit by hand.
     *
     * Injected into every Steam document on top of the active theme. This is the
     * supported place for local tweaks: Zehn's own custom.css says to use Quick
     * CSS instead, because the theme folder is overwritten on update — and here
     * Nix overwrites the theme folder on every rebuild too.
     *
     * On skwd-wall hosts matugen rewrites this exact path on every wallpaper
     * change (the "steam" integration in Modules/skwd-wall.nix).
     *
     * NOTE: Millennium's settings UI has a Quick CSS editor that writes here.
     * Anything typed into it is lost on the next wallpaper change or rebuild. */

    :root {
      /* Our own handle, used by the rules further down so they don't care which
       * theme is active. Always a literal triplet, never `var(...)` — see the
       * SystemAccentColor note below for why indirection is not trusted here. */
      --dots-accent-rgb: ${a.base};

      /* --- SpaceTheme --- */
      /* Its whole palette is bare R,G,B triplets in src/css/root.css, which is
       * exactly matugen's output shape. Setting these is harmless when Zehn is
       * the active theme and vice versa, so one Quick CSS drives either. */
      /* accent-2 is SpaceTheme's hover/lighter variant. It must come from
       * `lightest`, not `lighter` — for many wallpapers matugen's
       * primary_fixed_dim resolves to the same value as primary, which would
       * leave hover states visually identical to rest. */
      --st-accent-1: ${a.base} !important;
      --st-accent-2: ${a.lightest} !important;

      /* --- Zehn --- */
      /* Set the derived variables DIRECTLY, with !important.
       *
       * The obvious route — defining --SystemAccentColor-RGB and letting Zehn's
       * `var(--SystemAccentColor-RGB, 210, 115, 138)` pick it up — was tried and
       * VERIFIED NOT TO WORK: Steam still rendered a colourless accent. Quick CSS
       * itself loads fine (forcing --zehn-rgb-accent to pure red visibly turned
       * the nav underline red), and no other rule in the theme defines the
       * variable, so the indirection is simply not resolving in Steam's CEF.
       * Don't "simplify" this back to the single SystemAccentColor line.
       *
       * All seven are set so hover/pressed states stay in the same hue — Zehn
       * uses the lighten/darken ramp for those, and leaving them at their pink
       * fallbacks while overriding only the base looks broken. */
      --zehn-rgb-accent-lighten-major:  ${a.lightest} !important;
      --zehn-rgb-accent-lighten-medium: ${a.lighter} !important;
      --zehn-rgb-accent-lighten-minor:  ${a.base} !important;
      --zehn-rgb-accent:                ${a.base} !important;
      --zehn-rgb-accent-darken-minor:   ${a.darker} !important;
      --zehn-rgb-accent-darken-medium:  ${a.darkest} !important;
      --zehn-rgb-accent-darken-major:   ${a.darkest} !important;

      /* Zehn's other two colour inputs. These are the tints its "Background
       * Color Mix" / "Foreground Color Mix" sliders blend into surfaces and
       * text; stock they are a fixed pink and cream, which is why raising a
       * slider used to drag the UI away from the wallpaper palette instead of
       * toward it. Both mixes currently sit at 0, so these have no visible
       * effect until a slider is raised in Millennium -> Settings -> Themes —
       * they are wired so that when you do, it tints with your wallpaper. */
      --option-rgb-blend-background: ${a.base} !important;
      --option-rgb-blend-foreground: ${a.lightest} !important;
    }

    /* Accent ring around the whole window.
     *
     * Must be html::after with position:fixed. Steam's `body` box starts BELOW
     * the titlebar, so a border on body (or on .DesktopUI) draws only the left,
     * right and bottom edges and leaves the titlebar strip bare — that is the
     * "half there" border. `html` itself takes no visible box at all, so an
     * inset shadow on it renders nothing. A viewport-fixed pseudo-element is
     * the only one of the three that covers the full window. All verified by
     * screenshotting a live session.
     *
     * Radius matches geometry-corner-radius 12 in the Niri window rule.
     * pointer-events:none so it never eats a click. */
    html::after {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      border-radius: 12px;
      z-index: 2147483647;
      /* A soft inward glow, NOT a `border`. A hard border reads as a sharp
       * stroke at any width — thick looks harsh, thin looks like it is missing.
       * Two stacked inset shadows instead: a 1px hairline so the edge stays
       * defined, and a blurred one that fades inward.
       *
       * Knobs, in order: hairline alpha / blur radius / spread / glow alpha. */
      box-shadow:
        inset 0 0 0 1px rgba(var(--dots-accent-rgb), 0.30),
        inset 0 0 18px 3px rgba(var(--dots-accent-rgb), 0.28);
    }

    /* Steam's OWN hardcoded blues, which Zehn does not recolour. These are
     * literal hex gradients in Steam's library.css, not variables, so they have
     * to be overridden per element.
     *
     * Safe to hardcode: every selector here is one of Steam's stable
     * design-system classes (.Dialog*, .ModalPosition*), NOT a per-build hashed
     * name, so these survive Steam client updates.
     *
     * Steam's originals, for reference when Steam changes them:
     *   DialogButton.Primary        linear-gradient(#47bfff, #1a44c2)
     *   DialogToggleField_Option    #2d73ff
     *   DialogSlider_Value          linear-gradient(#00ccff, #2d73ff)
     *   ModalPosition_TopBar        linear-gradient(#00ccff, #3366ff)
     *
     * Text colour comes from matugen's on_primary, which is generated to
     * contrast with primary — a hardcoded dark would become unreadable the
     * first time a wallpaper produces a dark accent. */
    button.DialogButton.Primary,
    button.DialogButton.Primary:hover,
    button.DialogButton.Primary.gpfocus {
      background: rgb(var(--dots-accent-rgb)) !important;
      color: rgb(${a.onAccent}) !important;
    }

    .DialogToggleField_Option.Active {
      background: rgb(var(--dots-accent-rgb)) !important;
      color: rgb(${a.onAccent}) !important;
    }

    .DialogSlider_Value,
    div.ModalPosition_TopBar {
      background: rgb(var(--dots-accent-rgb)) !important;
    }
  '';

  # Bare "R, G, B" from matugen. The integer channel accessors are the trick:
  # `.rgb` yields "rgb(128, 213, 211)" with the wrapper, which Zehn cannot use,
  # and matugen's engine is NOT Tera so `replace(from=…, to=…)` is a parse error
  # (its filters take colon args, `| lighten: 20.0`, and do not chain into
  # `.red`). Verified against matugen 4.0.0.
  ch = role: lib0:
    "{{colors.${role}.default.red}}, {{colors.${role}.default.green}}, {{colors.${role}.default.blue}}";

  # Zehn wants a light->dark ramp. matugen filters can't chain into the channel
  # accessors, so the ramp comes from distinct Material You roles instead, which
  # are already tonal steps of the same hue.
  matugenAccent = {
    lightest = ch "primary_fixed" null;
    lighter  = ch "primary_fixed_dim" null;
    base     = ch "primary" null;
    # Generated to contrast with `primary`, so accent-filled buttons stay
    # readable whatever hue the wallpaper produces.
    onAccent = ch "on_primary" null;
    darker   = ch "inverse_primary" null;
    darkest  = ch "primary_container" null;
  };

  # ============================================================
  # QUICK CSS WATCHER PLUGIN
  # ============================================================
  # Steam reads quick.css EXACTLY ONCE, at startup. So a wallpaper change
  # rewrites the file but Steam keeps rendering the colours it booted with —
  # the UI silently goes stale until the next full restart.
  #
  # Millennium already solves this internally: `Core_WatchQuickCss` registers a
  # file watcher whose callback runs `UpdateStylesLive`, which walks every open
  # Steam window and swaps the contents of the `MillenniumQuickCss` stylesheet
  # in place — no restart, no flicker. But it is only registered by a React
  # effect in the Quick CSS settings panel, gated on a "watch" toggle that
  # defaults to false and is persisted nowhere.
  #
  # This plugin exists purely to call that one function at startup, making the
  # watcher permanent.
  #
  # Things that do NOT work, all tested — don't retry them:
  #   - Restarting only steamwebhelper. It does reload the UI without closing
  #     Steam, but Millennium's backend lives in the `steam` process and serves
  #     a cached copy, so the fresh webhelper gets the same stale CSS.
  #   - Any steam:// URL. There is no UI-reload protocol handler.
  #   - Attaching over CDP. Millennium launches steamwebhelper with
  #     --remote-debugging-pipe, so there is no TCP port.
  pluginName = "quickcss-watcher";

  # Hand-written to match the wrapper that Millennium's transpiler emits
  # (src/typescript/ttc/src/transpiler.ts, buildPluginWrapper). Writing it out
  # directly avoids pulling their bun + rollup toolchain in just to emit ~20
  # lines. The shape is load-bearing: the loader calls `PluginModule.default()`
  # and expects the module object back from `PluginEntryPointMain`.
  #
  # `@steambrew/sdk` is externalised to `window.MILLENNIUM_API` by that same
  # transpiler, which is why ffi is reached through it here.
  #
  # The call MUST use the two-argument overload, ffi("core", "Core_WatchQuickCss").
  # Millennium's own settings panel uses the one-argument form because it *is*
  # the core plugin; from a third-party plugin that form fails at runtime with
  # `Millennium Error: plugin not running`. Confirmed by probing all three call
  # forms in a live session — only ffi("core", route) succeeded.
  mkQuickCssWatcherPlugin = pkgs:
  let
    manifest = pkgs.writeText "plugin.json" (builtins.toJSON {
      name = pluginName;
      common_name = "Quick CSS Watcher";
      description = "Registers Millennium's quick.css file watcher at startup so matugen colour changes apply live, without restarting Steam. Managed by Modules/steam.nix.";
      useBackend = false;
    });

    index = pkgs.writeText "index.js" ''
      const MILLENNIUM_IS_CLIENT_MODULE = true;
      const pluginName = "${pluginName}";
      (window.PLUGIN_LIST ||= {})[pluginName] ||= {};
      window.MILLENNIUM_SIDEBAR_NAVIGATION_PANELS ||= {};

      let PluginEntryPointMain = function () {
        const millennium_main = {
          default: async function () {
            try {
              await window.MILLENNIUM_API.ffi("core", "Core_WatchQuickCss")();
              console.log("[${pluginName}] quick.css watcher registered");
            } catch (e) {
              console.error("[${pluginName}] failed to register quick.css watcher", e);
            }
          },
        };
        return millennium_main;
      };

      (async () => {
        const PluginModule = PluginEntryPointMain();
        Object.assign(window.PLUGIN_LIST[pluginName], {
          ...PluginModule,
          __millennium_internal_plugin_name_do_not_use_or_change__: pluginName,
        });
        await PluginModule.default();
        if (MILLENNIUM_IS_CLIENT_MODULE) {
          MILLENNIUM_BACKEND_IPC.postMessage(1, { pluginName: pluginName });
        }
      })();
    '';
  in pkgs.runCommand "millennium-${pluginName}" { } ''
    mkdir -p "$out/.millennium/Dist"
    install -m 0644 ${manifest} "$out/plugin.json"
    install -m 0644 ${index}    "$out/.millennium/Dist/index.js"
  '';

  # Fallback for hosts with no skwd-wall, and for first boot. Same ramp shape,
  # rendered from the Material You palette of #80d5d3.
  fallbackAccent = {
    lightest = "166, 240, 237";
    lighter  = "128, 213, 211";
    base     = "128, 213, 211";
    onAccent = "0, 55, 54";
    darker   = "0, 107, 105";
    darkest  = "0, 80, 79";
  };
in {
  flake.lib.steam = {
    matugenTemplate = mkQuickCss matugenAccent;
    quickCssPath = ".config/millennium/quick.css";
  };

  flake.nixosModules.steam = { pkgs, activeUser, ... }:
  let
    millennium = inputs.millennium.packages.${pkgs.stdenv.hostPlatform.system}.millennium;

    # Millennium is a CSS/JS injector for the Steam client — it is what makes
    # Steam themeable at all. Full writeup in Claude/steam.md; read it before
    # changing anything here.
    #
    # The glass effect is NOT produced by this module. Steam's CEF surface has no
    # alpha channel, so the theme cannot make Steam see-through — that comes from
    # the `opacity 0.85` window rule on app-id "steam" in Modules/Desktops/niri.nix.
    # The theme's job is only to make Steam look right at 85%.
    #
    # Upstream ships a `millennium-steam` package, but it
    # is built against upstream's own pinned nixpkgs, which would pull a second
    # Steam into the closure and drop the audio-library override below. So the
    # injection is reproduced here against our nixpkgs instead; it is only three
    # knobs, all documented in upstream's packages/nix/steam.nix.
    #
    # It works by making Steam load Millennium in place of libXtst: the bootstrap
    # .so re-exports the real libXtst symbols and spawns Millennium alongside.
    steamPackage = pkgs.steam.override {
      extraLibraries = _pkgs: [
        # Override Steam's bundled old audio libraries with host versions:
        # - libpulseaudio: Steam's scout runtime ships PA 1.1 which crashes talking to pipewire-pulse
        # - pipewire: Steam/CS2 bundles old libpipewire-0.3 (protocol v4) which desynchs from
        #   the system PipeWire server and causes audio to cut out mid-session
        _pkgs.libpulseaudio
        _pkgs.pipewire
        # Millennium's own runtime deps — it links against both ABIs of openssl.
        millennium
        _pkgs.openssl
        pkgs.pkgsi686Linux.openssl
      ];

      extraEnv = {
        MILLENNIUM_RUNTIME_PATH = "${millennium}/lib/libmillennium_x86.so";
      };

      # Re-linked on every launch rather than by an activation script, because
      # Steam's own self-updater rewrites ubuntu12_{32,64} and would clobber a
      # one-shot symlink. Steam is the only writer of those directories, so this
      # is the "unavoidable imperative state" case from CLAUDE.md — it just
      # happens to self-heal.
      extraProfile = ''
        ln -sf ${millennium}/lib/libmillennium_bootstrap_x86.so "$HOME/.local/share/Steam/ubuntu12_32/libXtst.so.6"
        ln -sf ${millennium}/lib/libmillennium_bootstrap_hhx64.so "$HOME/.local/share/Steam/ubuntu12_64/libXtst.so.6"
      '';
    };
  in {
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;

      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];

      extraPackages = with pkgs; [
        mangohud
      ];

      package = steamPackage;
    };

    programs.gamemode.enable = true;
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

    environment.systemPackages = with pkgs; [
      steam-run
      vulkan-loader
      vulkan-tools
      vulkan-validation-layers
    ];

    networking.firewall.allowedTCPPorts = [
      27014 27015 27036 27037 27038 27039 27040 27041
      27042 27043 27044 27045 27046 27047
    ];

    networking.firewall.allowedUDPPorts = [
      27000 27001 27002 27003 27004 27005
      27020 27021 27022 27023 27024 27025
      27026 27027 27028 27029 27030
    ];

    # ============================================================
    # MILLENNIUM THEMES
    # ============================================================
    # `lib` comes from the Home Manager module args, not the NixOS ones —
    # lib.hm.dag only exists on Home Manager's extended lib.
    home-manager.users.${activeUser} = { config, lib, ... }:
    let
      # Zehn — Windows 10 Fluent Design, and the theme actually in use.
      #
      # Pinned to a tag on purpose. Steam theming depends on Steam's per-build
      # hashed class names, so Zehn retags whenever a Steam update breaks them
      # (it tagged 5 times in the first week of Aug 2026). An unpinned fetch
      # would silently restyle the client on an unrelated rebuild — and, worse,
      # would make `nix build` non-reproducible. Bumping is a deliberate act:
      #   nix-prefetch-git --url https://github.com/yurisuika/Zehn --rev refs/tags/<tag>
      zehn = pkgs.fetchFromGitHub {
        owner = "yurisuika";
        repo = "Zehn";
        rev = "2026.8.9";
        hash = "sha256-ksAopxVb9r7Z3Et8MHq6PsxW1FgTpVaRV+QYFfN+fkM=";
      };

      # Both themes are installed; only `activeTheme` decides which renders.
      # dots-glass is kept as the fallback — it targets only Steam's stable
      # design-system classes, so it still works on a Steam release that Zehn
      # has not caught up with yet. Switch by editing activeTheme below, or
      # live in Steam via Millennium -> Settings -> Themes.
      # SpaceTheme — dark, modular, the most-downloaded Millennium theme.
      #
      # Pinned to a COMMIT, not a tag: upstream stopped tagging (latest tag is
      # v202505024 from May 2025) and ships straight to main, so a tag would pin
      # something 15 months stale.
      #   nix-prefetch-git --url https://github.com/SpaceTheme/Steam --rev <sha>
      spaceTheme = pkgs.fetchFromGitHub {
        owner = "SpaceTheme";
        repo = "Steam";
        rev = "cbf0213604316601ae554db5abbb76b9d0282af0"; # 2026-08-01
        hash = "sha256-sefU4QmLJ5dgdPEXajmAxDwhAdIuRRhSb7Q6JuHrzvc=";
      };

      themes = {
        "SpaceTheme" = spaceTheme;
        "Zehn" = zehn;
        "dots-glass" = "${self}/Resources/Steam-Glass-Theme";
      };
      activeTheme = "SpaceTheme";

      # Zehn's own options, as shown under Millennium -> Settings -> Themes.
      #
      # Anything listed here is FORCED on every rebuild — Nix owns it, and a change
      # made in the Steam UI to one of these keys reverts. Anything NOT listed is
      # left completely alone and stays yours to tweak live.
      #
      # Keep this list short, for a reason: Millennium writes *all ~24* of Zehn's
      # defaults into config.json on first run, so "seed only if absent" stops
      # working after that first launch — declaring a key is the only way to
      # actually control it. Blanket-forcing the whole set would trample live
      # tweaks (e.g. Foreground Color Mix), hence the deliberate opt-in.
      # Keyed by theme name — each theme names its options differently, so a
      # setting forced for Zehn does nothing under SpaceTheme and vice versa.
      conditionsForced = {
        "SpaceTheme" = {
          # Values are Compact | Hide | Show (default Compact, i.e. still visible).
          "What's New" = "Hide";
          # Default "yes" keeps the game-list sidebar pinned across Store,
          # Community and profile pages, where it is just dead space. "no"
          # confines it to the Library. Upstream notes that with this off, the
          # userpanel and download bar also become Library-only.
          "Always show sidebar" = "no";
          # Library game list on the left.
          "Sidebar on right" = "no";
          # NB: reads backwards. Upstream's description is "Hides the scrollbars
          # in the SteamUI", so "yes" HIDES them; the default "no" shows them.
          "Scrollbars" = "yes";
        };

        "Zehn" = {
          # Zehn defaults to "Auto", which can land on the light variant.
          "Color Mode" = "Dark";
          # The news/promo carousel above the library grid.
          "Show What's New" = "no";
          # Blends --option-rgb-blend-foreground (a cream, 193/180/146) into
          # every foreground colour. This had drifted to 81, which desaturates
          # the whole UI toward grey-cream and was a large part of why Steam
          # looked colourless next to Zehn's own screenshots. Default is 0.
          "Foreground Color Mix" = "0";
        };
      };

      # Millennium reads themes from <steam>/millennium/themes (get_steam_path()
      # is hardcoded to ~/.steam/steam on Linux) but its config from
      # ~/.config/millennium/config.json. The two are NOT under a common root.
      themesRoot = "${config.home.homeDirectory}/.steam/steam/millennium/themes";
      configFile = "${config.xdg.configHome}/millennium/config.json";
      quickCssFile = "${config.home.homeDirectory}/${self.lib.steam.quickCssPath}";
      quickCssSeedMarker = "${config.xdg.configHome}/millennium/.quick.css.seed";
      # Plugins live under XDG_DATA_HOME, unlike themes (Steam dir) and config
      # (XDG_CONFIG_HOME). Three different roots — see Claude/steam.md.
      pluginDir = "${config.xdg.dataHome}/millennium/plugins/${pluginName}";
      watcherPlugin = mkQuickCssWatcherPlugin pkgs;

      quickCssSeed = pkgs.writeText "millennium-quick.css" (mkQuickCss fallbackAccent);

      # Copied rather than symlinked: Millennium serves theme files over its own
      # HTTP hook, and a dangling store symlink survives a GC worse than a plain
      # copy does. Removed first so files deleted upstream don't linger, and
      # chmod'd because store sources are read-only.
      installTheme = name: src: ''
        rm -rf "${themesRoot}/${name}"
        mkdir -p "${themesRoot}/${name}"
        cp -rT ${src} "${themesRoot}/${name}"
        chmod -R u+w "${themesRoot}/${name}"
      '';
    in {
      home.activation.steamMillenniumThemes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # quick.css cannot be a home-manager symlink: matugen rewrites this exact
        # path on every wallpaper change and store symlinks are read-only. Seed it
        # as a plain writable file, using btop's refresh rule — write the seed only
        # when the file is missing or is still byte-identical to the seed installed
        # last time (i.e. matugen has not taken ownership yet). Once matugen owns
        # it, editing the generator above stops clobbering the live colours.
        mkdir -p "$(dirname "${quickCssFile}")"
        if [ ! -e "${quickCssFile}" ] \
           || { [ -e "${quickCssSeedMarker}" ] && ${pkgs.diffutils}/bin/cmp -s "${quickCssFile}" "${quickCssSeedMarker}"; }; then
          install -m 0644 ${quickCssSeed} "${quickCssFile}"
        fi
        install -m 0644 ${quickCssSeed} "${quickCssSeedMarker}"

        # Quick CSS watcher plugin — see the long comment in this module.
        rm -rf "${pluginDir}"
        mkdir -p "${pluginDir}"
        cp -rT ${watcherPlugin} "${pluginDir}"
        chmod -R u+w "${pluginDir}"

        ${lib.concatStrings (lib.mapAttrsToList installTheme themes)}
        # Millennium fills in every other key from its own defaults on first
        # start, so a partial config here is safe.
        mkdir -p "$(dirname "${configFile}")"
        [ -f "${configFile}" ] || echo '{}' > "${configFile}"

        # activeTheme is forced (Nix owns which theme runs). $forced is merged on
        # the RIGHT so declared keys win over what Millennium wrote, while every
        # undeclared condition is preserved exactly as the Steam UI left it.
        # A plugin only loads if its name is in plugins.enabledPlugins, so add it
        # without disturbing any other entries.
        ${pkgs.jq}/bin/jq --argjson forced ${lib.escapeShellArg (builtins.toJSON conditionsForced)} '
          .themes = (.themes // {}) |
          .themes.activeTheme = "${activeTheme}" |
          .themes.conditions = (.themes.conditions // {}) |
          reduce ($forced | keys[]) as $t (.;
            .themes.conditions[$t] = ((.themes.conditions[$t] // {}) + $forced[$t])) |
          .plugins = (.plugins // {}) |
          .plugins.enabledPlugins = (((.plugins.enabledPlugins // []) + ["${pluginName}"]) | unique)
        ' "${configFile}" > "${configFile}.tmp" && mv "${configFile}.tmp" "${configFile}"
      '';
    };
  };
}
