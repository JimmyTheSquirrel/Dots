{ inputs, ... }:
let
  spicetifyOptions = { lib, ... }: {
    options.my.spicetify.theme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "sleek";
      description = ''
        Name of an upstream `spicetify-nix` theme to use instead of the local
        Text theme in `Resources/Spicetify-Text-Theme`.

        `null` (the default) keeps the Text theme *and* the whole matugen live
        colour pipeline: the `spicetify` / `spicetify-live` skwd integrations,
        the `matugen-colors.js` extension and the `spotify-apply-colors` CDP
        script. Setting a name here drops all four, because they exist only to
        repaint the Text theme from the current wallpaper and would write into
        `Themes/text/` — a directory that no longer exists.

        Valid names are the attribute names of
        `spicetify-nix.legacyPackages.<system>.themes` (sleek, dribbblish,
        catppuccin, comfy, text, …).
      '';
    };

    options.my.spicetify.colorScheme = lib.mkOption {
      type = lib.types.str;
      default = "Matugen";
      example = "Coral";
      description = ''
        Colour scheme within the chosen theme — a section name from that
        theme's `color.ini`, matched case-sensitively.

        "Matugen" is the scheme the local Text theme carries and the one the
        wallpaper pipeline rewrites, so it only makes sense alongside
        `my.spicetify.theme = null`. Sleek ships 19, including Coral, Cherry,
        Nord, Dracula and TokyoNight.
      '';
    };
  };
in {
  flake.nixosModules.spicetify = { pkgs, lib, activeUser, ... }:
  let
    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};

    # Live color injection is handled externally via CDP (Chrome DevTools Protocol).
    # When wallpaper changes, skwd-wall runs spotify-apply-colors which connects to
    # Spotify's CDP port (9222) and calls setProperty directly in the renderer.
    # This extension handles the startup case: re-applies colors after SPA navigation
    # using a <style> element injected at startup via CDP (colors are already in the DOM).
    # No Node.js require() or network fetch needed — the style element persists in the DOM.
    matugenExt = pkgs.writeTextFile {
      name = "spicetify-matugen-colors";
      destination = "/matugen-colors.js";
      text = ''
        (function () {
          // Re-apply the matugen-dynamic-colors style after SPA navigation wipes inline styles.
          // The actual colors are injected externally via CDP (spotify-apply-colors script).
          function reapply() {
            const style = document.getElementById('matugen-dynamic-colors');
            if (style) {
              // Force browser to re-process the style by toggling it
              const text = style.textContent;
              style.textContent = ''';
              style.textContent = text;
            }
          }
          if (Spicetify?.Platform?.History) {
            Spicetify.Platform.History.listen(reapply);
          }
        })();
      '';
    };
  in {
    imports = [ spicetifyOptions ];

    home-manager.users.${activeUser} = { config, osConfig, ... }:
    let
      upstreamTheme = osConfig.my.spicetify.theme;
      # The matugen pipeline is all-or-nothing and is tied to the Text theme —
      # see the option description in this file.
      useMatugen = upstreamTheme == null;
    in {
      imports = [ inputs.spicetify-nix.homeManagerModules.default ];

      programs.spicetify = {
        enable = true;

        # An upstream theme is taken wholesale — no injectCss/additionalCss
        # layering. The CSS below is written against the Text theme's variables
        # and its transparency assumptions, so grafting it onto Sleek would
        # fight the theme rather than tune it.
        theme =
          if !useMatugen then spicePkgs.themes.${upstreamTheme} else {
          name = "text";
          src = ../../Resources/Spicetify-Text-Theme;
          appendName = false;
          injectCss = true;
          replaceColors = true;
          overwriteAssets = false;
          sidebarConfig = false;
          additionalCss = ''
            /* Transparent background for compositor transparency.

               Spotify's see-through look comes ENTIRELY from the niri window-rule
               (opacity 0.85 on ^spotify$ in Modules/Desktop/niri.nix). Do NOT try to
               do it in CSS with an alpha background here — it cannot work, for the same
               reason Steam's Millennium theme can't: Spotify is CEF and its window
               surface has no alpha channel, so anything translucent composites against
               opaque black, not against the wallpaper.

               Measured 2026-09-16 over CDP: with `html, body { background: transparent }`
               forced, the window still rendered solid black; adding CEF's
               --enable-transparent-visuals flag changed nothing. A previous attempt
               here painted `html body` at 55% via color-mix and produced exactly that
               — a fully black backdrop, since `html` still paints an opaque
               --spice-main underneath it.

               So: every container below is transparent, `html` paints one flat opaque
               --spice-main, and niri fades the composited result. The cost is that
               niri's opacity is uniform — it fades text too — which is why the value
               is 0.85 and not the bar's 0.55. noctalia's bar fades background only
               (bar.main background_opacity); a CEF window cannot do that. */
            body,
            .Root,
            .Root__top-container,
            .Root__main-view,
            .Root__nav-bar,
            .Root__now-playing-bar,
            .Root__globalNav,
            .main-yourLibraryX-entryPoints,
            .main-view-container,
            .main-view-container__scroll-node,
            .main-view-container__scroll-node-child,
            .main-home-content,
            .main-topBar-background,
            .main-home-filterChipsSection,
            .main-home-filterChipsSection::after,
            .main-trackList-trackListHeader,
            .main-trackList-trackListHeaderStuck,
            .main-entityHeader-container + div,
            .main-entityHeader-container + div > div,
            .os-viewport,
            .os-content {
              background: transparent !important;
              background-color: transparent !important;
            }

            /* Hide right sidebar (now playing view / related content) */
            .Root__right-sidebar,
            .Root__right-sidebar * {
              display: none !important;
              width: 0 !important;
              min-width: 0 !important;
            }

            /* Seekbar: centered, 75% wide, 14px tall, rounded, always visible.
               Text theme uses position:absolute + 100vw (full viewport edge-to-edge). */
            .Root__now-playing-bar .playback-bar {
              left: 50% !important;
              transform: translateX(-50%) !important;
              width: 75% !important;
              bottom: 38px !important; /* higher — closer to play/skip buttons */
            }
            .Root__now-playing-bar .playback-progressbar-container div[data-testid="progress-bar"] {
              --progress-bar-height: 14px !important;
              --progress-bar-radius: 7px !important;
              --fg-color: var(--spice-button-active) !important;
              --bg-color: var(--spice-button-disabled) !important;
            }
            /* Prevent hover from darkening/brightening the fill color */
            .Root__now-playing-bar .playback-progressbar-isInteractive:hover div[data-testid="progress-bar"],
            .Root__now-playing-bar .playback-progressbar-container:hover div[data-testid="progress-bar"] {
              --fg-color: var(--spice-button-active) !important;
              --bg-color: var(--spice-button-disabled) !important;
            }
            /* Always show the scrubber handle — Spotify hides it until hover */
            .Root__now-playing-bar div[data-testid="progress-bar-handle"] {
              opacity: 1 !important;
              transform: none !important;
            }
            /* Increase pane height to contain bar + time numbers */
            .Root__now-playing-bar .main-nowPlayingBar-nowPlayingBar {
              padding-bottom: 52px !important;
            }
            /* Margins align Playing pane border with Nav/Main outer borders */
            .Root__now-playing-bar {
              margin: 8px 14px 6px 10px !important;
            }
            /* Always visible — not just on hover */
            .Root__now-playing-bar .playback-bar,
            .Root__now-playing-bar .playback-progressbar-container,
            .Root__now-playing-bar .x-progressBar-sliderArea,
            .Root__now-playing-bar .x-progressBar-fillColor,
            .Root__now-playing-bar div[data-testid="progress-bar"],
            .Root__now-playing-bar div[data-testid="progress-bar-background"] {
              opacity: 1 !important;
              visibility: visible !important;
            }

            /* Make player controls always visible */
            .player-controls__buttons,
            .main-nowPlayingBar-extraControls,
            .main-nowPlayingBar-left,
            .main-nowPlayingBar-center,
            .main-nowPlayingBar-right {
              opacity: 1 !important;
            }

            /* Keep connect bar clickable */
            .main-connectBar-connectBar {
              pointer-events: auto !important;
              opacity: 1 !important;
            }

            /* Neutral dark backdrop — deliberately does NOT follow the palette.
               Without this pin, --spice-main resolves to matugen's `surface` role
               (skwd template `{{colors.surface.default.hex}}`, Modules/Desktop/skwd.nix),
               which is still near-black but carries the wallpaper's hue — observed
               #161306 and #15130c. Pinned by choice 2026-09-16: the backdrop stays
               identical on every wallpaper and is immune to a light-mode flip.
               Accents, text and borders still follow matugen; only this flat
               backdrop is frozen.

               This wins over the CDP colour injection because the injection sets
               --spice-main as a normal inline property, and an !important
               stylesheet declaration outranks normal inline. */
            :root {
              --spice-main: #0d0d0d !important;
              --spice-rgb-main: 13, 13, 13 !important;
            }

            /* Let matugen handle text shades naturally (on_surface / on_surface_variant) */

            /* Volume bar fix: sliderArea is 4px tall with overflow:hidden,
               theme sets 9px on fill so border-bottom is always clipped.
               Switch to solid background-color fill that fits in 4px. */
            .volume-bar__slider-container .x-progressBar-fillColor {
              height: 4px !important;
              background-color: var(--spice-text) !important;
              border-bottom: none !important;
            }
            .volume-bar__slider-container .x-progressBar-sliderArea {
              height: 4px !important;
            }
            /* Background track (dim) */
            .volume-bar__slider-container .x-progressBar-sliderArea:first-child > div {
              background-color: rgba(255, 255, 255, 0.15) !important;
              height: 4px !important;
            }
          '';
        };

        colorScheme = osConfig.my.spicetify.colorScheme;

        enabledExtensions = with spicePkgs.extensions; [
          adblock
          shuffle
        ]
        ++ lib.optional useMatugen { src = matugenExt; name = "matugen-colors.js"; };


        enabledCustomApps = with spicePkgs.apps; [
          marketplace
        ];
      };

      # spotify-apply-colors: injects current matugen colors into the running Spotify via CDP.
      # Spotify must be launched with --remote-debugging-port=9222 (see niri.nix).
      # Called by skwd-wall's spicetify-live integration reload command on wallpaper change.
      # Only built on the matugen path — nothing calls it otherwise, and skwd
      # no longer seeds the integration that would.
      home.packages = lib.optionals useMatugen [
        pkgs.websocat
        (pkgs.writeShellScriptBin "spotify-apply-colors" ''
          COLORS_FILE="$HOME/.config/spicetify/matugen-colors.json"
          CDP="http://127.0.0.1:9222"

          [ -f "$COLORS_FILE" ] || exit 0

          # Find the main xpui page target
          WS_URL=$(${pkgs.curl}/bin/curl -s "$CDP/json/list" 2>/dev/null \
            | ${pkgs.jq}/bin/jq -r '[.[] | select(.type == "page")] | .[0].webSocketDebuggerUrl' 2>/dev/null)
          [ -n "$WS_URL" ] && [ "$WS_URL" != "null" ] || exit 0

          # Compact colors to one line so the JS expression has no newlines
          COLORS=$(${pkgs.jq}/bin/jq -c . "$COLORS_FILE")
          JS="(function(){var c=''${COLORS};var r=document.documentElement;Object.entries(c).forEach(function(kv){r.style.setProperty(kv[0],kv[1]);});})();"

          # -cn = compact single-line JSON (websocat --one-message reads one line at a time)
          MSG=$(${pkgs.jq}/bin/jq -cn --arg e "$JS" '{"id":1,"method":"Runtime.evaluate","params":{"expression":$e}}')
          echo "$MSG" | ${pkgs.websocat}/bin/websocat --one-message "$WS_URL" 2>/dev/null || true
        '')
      ];

    };
  };
}
