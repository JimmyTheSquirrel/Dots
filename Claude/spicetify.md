# Spicetify — Spotify Theming

**Module:** `Modules/spicetify.nix`
**Theme files:** `Resources/Spicetify-Text-Theme/`
**Flake input:** `spicetify-nix`

## Theme Overview

Custom **"text" theme** with matugen dynamic colors:
- JetBrains Mono font throughout
- ASCII art banners and pane border labels ("Nav", "Main", "Playing", etc.)
- Custom Unicode icons for player controls
- Transparent background for compositor transparency
- Hidden right sidebar
- Marketplace app + adblock/shuffle + matugen-colors extensions
- `colorScheme = "Matugen"` in `spicetify.nix` — `[Matugen]` section in `color.ini` is the baked-in fallback

## Dynamic Colors via Matugen (CDP Injection)

Colors update live in Spotify when skwd-wall changes the wallpaper — no restart or rebuild needed.

**How it works:**
1. skwd-wall runs matugen on wallpaper change, writing:
   - `~/.config/spicetify/matugen-colors.json` — CSS custom property values (`--spice-*`) for runtime use
   - `~/.config/spicetify/Themes/text/color.ini` — `[Matugen]` section for bake-in on next rebuild
2. The `spicetify-live` integration in skwd-wall config has `"reload": "spotify-apply-colors"` — runs automatically after matugen writes
3. `spotify-apply-colors` (in `home.packages` in `spicetify.nix`) connects to Spotify's CDP debug port (9222), reads `matugen-colors.json`, and injects each `--spice-*` variable via `Runtime.evaluate` → `document.documentElement.style.setProperty()`
4. Spotify must be launched with `--remote-debugging-port=9222` (set in both `spotify-startup` and `spotify-open` in `niri.nix`)
5. The baked-in `matugen-colors.js` extension hooks `Spicetify.Platform.History.listen` to re-apply the injected `<style>` element after SPA navigation wipes inline styles
6. On boot, `spotify-startup` runs `spotify-apply-colors` automatically — background subshell polls `localhost:9222/json/list` until CDP is ready (up to 5 retries, 3s apart, starting 8s after launch)

**Why not `fs.watch` or `fetch()`?** Spotify uses CEF (Chromium Embedded Framework), not Electron. The renderer has no Node.js `require('fs')` and blocks all localhost HTTP connections. CDP is the only reliable way to inject JS from outside.

**If colors stop updating:** check `journalctl --user -u skwd-daemon` for matugen errors and verify `~/.config/spicetify/matugen-colors.json` is being written on wallpaper change.

## Matugen Templates

Synced by `skwd-wall.nix` activation script:
- `spicetify-colors.json` → outputs `~/.config/spicetify/matugen-colors.json` (runtime CSS vars)
- `spicetify-text.ini` → outputs `~/.config/spicetify/Themes/text/color.ini` (rebuild-time color.ini)

## Color Choices

- `--spice-text` = `on_primary_container` — light tinted accent, gives warmth to body text
- `--spice-subtext` = `on_surface_variant` — slightly dimmer, for secondary text
- `--spice-main` = overridden to `#0d0d0d !important` in `additionalCss` — neutral dark, ignores matugen surface tint
- `--spice-banner` = `primary` (from matugen) — accent color for "Liked Songs" / playlist titles

## CSS Fixes (additionalCss)

**Volume bar:** `x-progressBar-sliderArea` is only 4px tall with `overflow: hidden`. The text theme sets `height: 9px` on the fill which clips the `border-bottom`. Fixed by overriding to 4px solid fill with a dim track background.

**Pane borders/labels:** Always show in `--spice-border-active` color (matugen primary). Removed hover-only coloring from `user.css`.

**Transparency:** Spotify window opacity set to `0.75` in Niri window rules. Pane container backgrounds (Nav, Library, Main, Playing) forced transparent so wallpaper shows through. `--spice-main` stays solid `#0d0d0d` so UI elements remain readable. **Niri opacity changes require logout/login.**

**Now-playing (Playing pane) seekbar:** The text theme uses `position: absolute` + `width: 100vw` on `.playback-bar` (full viewport width). Overridden in `additionalCss`:
- Centered with `left: 50%; transform: translateX(-50%); width: 75%`
- 14px tall, 7px border-radius (rounded pill)
- `bottom: 38px` — closer to play/skip buttons
- `padding-bottom: 52px` on `.main-nowPlayingBar-nowPlayingBar` — room for bar + time numbers
- `margin: 8px 14px 6px 10px` on `.Root__now-playing-bar` — aligns with Nav/Library/Main borders
- Hover states locked: `--fg-color` and `--bg-color` pinned
- Scrubber handle always visible: `div[data-testid="progress-bar-handle"] { opacity: 1; transform: none }`

**After CSS changes:** Spotify must be **fully killed and relaunched** — layout CSS is compiled into the binary by spicetify at build time, not injected live like colors.
