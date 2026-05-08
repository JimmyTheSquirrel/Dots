{ inputs, ... }: {
  flake.nixosModules.spicetify = { pkgs, activeUser, ... }:
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
    home-manager.users.${activeUser} = { config, ... }: {
      imports = [ inputs.spicetify-nix.homeManagerModules.default ];

      programs.spicetify = {
        enable = true;

        theme = {
          name = "text";
          src = ../Resources/Spicetify-Text-Theme;
          appendName = false;
          injectCss = true;
          replaceColors = true;
          overwriteAssets = false;
          sidebarConfig = false;
          additionalCss = ''
            /* Transparent background for compositor transparency */
            body,
            .Root,
            .Root__top-container,
            .Root__main-view,
            .Root__nav-bar,
            .Root__now-playing-bar,
            .main-view-container,
            .main-view-container__scroll-node,
            .main-view-container__scroll-node-child,
            .main-home-content,
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

            /* Fix playback bar - remove absolute positioning and extra size */
            .Root__now-playing-bar {
              position: relative !important;
              height: auto !important;
              min-height: unset !important;
              margin: 0 !important;
              padding: 0 !important;
            }
            .main-nowPlayingBar-nowPlayingBar {
              padding: 8px !important;
              height: auto !important;
              min-height: unset !important;
            }
            .playback-bar {
              position: relative !important;
              left: unset !important;
              bottom: unset !important;
              width: 100% !important;
              margin: 0 !important;
            }

            /* Make player controls always visible (not just on hover) */
            .player-controls__buttons,
            .main-nowPlayingBar-extraControls,
            .main-nowPlayingBar-left,
            .main-nowPlayingBar-center,
            .main-nowPlayingBar-right {
              opacity: 1 !important;
            }

            /* Fix connect bar - make clickable and position properly */
            .main-connectBar-connectBar {
              position: relative !important;
              pointer-events: auto !important;
              right: unset !important;
              bottom: unset !important;
              opacity: 1 !important;
              padding: 0 8px !important;
            }

            /* Ensure right side of now playing bar has proper layout */
            .main-nowPlayingBar-right {
              display: flex !important;
              align-items: center !important;
              gap: 8px !important;
              flex-shrink: 0 !important;
            }
          '';
        };

        colorScheme = "Matugen";

        enabledExtensions = with spicePkgs.extensions; [
          adblock
          shuffle
          { src = matugenExt; name = "matugen-colors.js"; }
        ];

        enabledCustomApps = with spicePkgs.apps; [
          marketplace
        ];
      };

      # spotify-apply-colors: injects current matugen colors into the running Spotify via CDP.
      # Spotify must be launched with --remote-debugging-port=9222 (see niri.nix).
      # Called by skwd-wall's spicetify-live integration reload command on wallpaper change.
      home.packages = [
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
