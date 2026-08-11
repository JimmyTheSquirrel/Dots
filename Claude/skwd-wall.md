# SKWD Wallpaper Selector

**Module:** `Modules/skwd-wall.nix`
**Flake input:** `github:liixini/skwd-wall`
**Used on:** All three systems

## Overview

Wallpaper selector with matugen integration for Material You color schemes. Provides `skwd`, `skwd-wall`, and `skwd-daemon` executables. Runs as a systemd user service (`skwd-daemon`) that auto-starts with the graphical session.

## Usage

```bash
skwd wall toggle              # Toggle wallpaper selector (Meta+W on all systems)
skwd wallpaper set /path/to/image.jpg
skwd wallpaper random
```

## Config File

`~/.config/skwd-wall/config.json`
- `compositor`: `"niri"`, `"hyprland"`, or `"kde"`
- `monitor`: Target monitor (e.g., `"DP-2"`)
- `paths.wallpaper`: Wallpaper directory
- `features.matugen`: Enable Material You color generation
- `matugen.schemeType`: Use `"scheme-tonal-spot"` for colorful Material You colors
- `matugen.mode`: `"dark"`
- `integrations`: Array of matugen template integrations

## Matugen Integrations

After each wallpaper change skwd-wall runs matugen on the new wallpaper, renders each template, and executes its `reload` command. The activation script patches `config.json` on every rebuild to keep integration fields correct.

**Active integrations (managed by Nix):**

| name | template | output | reload |
|------|----------|--------|--------|
| `skwd-wall` | `quickshell-colors.json` | `colors.json` | *(none)* |
| `noctalia` | `noctalia-colors.json` | `~/.config/noctalia/colors.json` | `noctalia-sync-wallpaper` |
| `spicetify` | `spicetify-text.ini` | `~/.config/spicetify/Themes/text/color.ini` | *(none)* |
| `spicetify-live` | `spicetify-colors.json` | `~/.config/spicetify/matugen-colors.json` | `spotify-apply-colors` |
| `btop` | `btop-theme.theme` | `~/.config/btop/themes/dots.theme` | `btop-reload-theme` |
| `steam` | `steam-quick.css` | `~/.config/millennium/quick.css` | *(none — see below)* |

**Steam has no reload command on purpose.** Steam cannot be told to re-read
Millennium's Quick CSS from outside, so the new accent applies at the next Steam
launch. Its template lives in `Modules/steam.nix` (like btop's), and renders a
single `R, G, B` triplet from which the Zehn theme derives ~30 shades. Note the
integration is named `steam` in `integrations`, which is unrelated to the
top-level `features.steam` / `steam` keys in this same config — those are
skwd-wall's own Steam Workshop wallpaper import. See `Claude/steam.md`.

The `skwd-wall` built-in integration (`quickshell-colors.json`) is **required** — without it the selector UI stays pink/default.

**btop template lives in `Modules/btop.nix`, not here.** `skwd-wall.nix` installs it from the store (`self.lib.btop.matugenTemplate`) rather than writing a heredoc, so the theme mapping has exactly one definition shared with the fallback theme baked into btop's module. Its reload command, `btop-reload-theme`, sends `SIGUSR2` — btop's hot-reload signal — so a running instance re-reads the theme off disk without restarting. See `Claude/misc.md`.

**Noctalia color note:** Noctalia v5 generates its own Material You colors from its **internal wallpaper path** — it does not use the `colors.json` matugen writes. The `noctalia-sync-wallpaper` reload script (deployed via `home.packages` in `noctalia.nix`) reads the wallpaper path from `~/.cache/skwd-wall/last-wallpaper.json`, calls `noctalia msg wallpaper-set <path>` to point noctalia at the correct wallpaper (so it regenerates the right palette), swaps the swaybg backdrop, then calls `noctalia msg templates-apply` to push the new palette to kitty, niri, gtk, etc. Full detail in `Claude/noctalia.md`.

**`skwd status` is not a reliable wallpaper source** — its `current_wallpaper` is `null` on a fresh session and is a bare filename otherwise. Use `~/.cache/skwd-wall/last-wallpaper.json` (`.path`, absolute) with `jq`.

## Important Gotchas

- **KDE (Elektra): daemon calls `qdbus6`**, but NixOS ships the Qt6 tool as plain `qdbus`. Without the `qdbus6-shim` (added to `home.packages` when compositor is `kde` in `Modules/skwd-wall.nix`), `apply_kde_static` silently fails at spawn and Plasma keeps its old wallpaper — the daemon log still shows a successful-looking "setting wallpaper via plasmashell evaluateScript" INFO line because it's logged before the call.

- **`matugen` must be in `home.packages`** — it's added in `skwd-wall.nix`. Without it every integration silently fails (skwd-daemon catches the error but swallows it).
- **Reload scripts must be nix profile packages, not `~/.local/bin` files.** skwd-daemon runs reload commands with a minimal shell PATH that only contains nix profile packages (`~/.nix-profile/bin`). Scripts in `~/.local/bin` produce `exit status: 127 — command not found`. Use `pkgs.writeShellScriptBin` in `home.packages` (like `noctalia-sync-wallpaper` and `spotify-apply-colors`) so the script is on PATH when the daemon runs it. Symptom in logs: `WARN command failed (exit status: 127): <script-name>`.
- **Zen integrations in config.json break matugen** — their output paths contain literal `\n` which corrupts generated TOML. The activation script strips them on every rebuild. Symptom: `matugen exited with exit status: 1` in `journalctl --user -u skwd-daemon`.
- The activation script patches `config.json` via jq on every rebuild (not just first run), so integrations/reload fields stay correct even if edited manually.
- Noctalia IPC uses `noctalia msg <command>`, not `noctalia-shell ipc call`. Never use `pkill -9 quickshell` to reload noctalia — it's not QuickShell-based in v5.

## Troubleshooting

**Matugen errors:** `journalctl --user -u skwd-daemon`

**New videos/images missing from selector:** the daemon only lists items with a generated thumbnail. Check `journalctl --user -u skwd-daemon | grep "thumb FAILED"` — thumbnail generation (ffmpeg) can fail transiently during session-startup rush and the item is skipped without retry. Fix: `skwd wall cache_rebuild` (re-processes anything missing a thumb; `skwd wall cache_status` shows progress).

**Gray screen when applying a video wallpaper:** `skwd-paper` (the renderer) opens videos with a tiny ffmpeg probe window (`probesize=65536`). On mp4s whose metadata sits at the end of the file, the pixel format probes as `unknown`, the scaler init aborts (SIGABRT, visible in `coredumpctl list`), and the daemon respawn-loops leaving a gray backdrop. It also corrupts the transition state, so subsequent wallpaper changes flash the old image. Diagnose: `ffprobe -v error -probesize 65536 -analyzeduration 500000 -select_streams v:0 -show_entries stream=pix_fmt <file>` → `unknown` = affected. Fix (lossless remux, moves metadata to front): `ffmpeg -i in.mp4 -c copy -movflags +faststart out.mp4`. Upstream bug in liixini/skwd-daemon (`VideoSource::new` should error, not abort).

**Blank/duplicated thumbnails or stale cache:**
```bash
systemctl --user stop skwd-daemon
rm -f ~/.config/skwd-wall/.bootstrapped   # Forces fresh bootstrap
rm -rf ~/.cache/skwd-wall                  # Clears all cached data
systemctl --user start skwd-daemon
skwd wall toggle                           # Triggers cache rebuild
```

**Cache behavior:**
- `.bootstrapped` file tells daemon setup is complete
- Daemon uses file modification times — touch wallpaper files to force rebuild
- Thumbnail cache at `~/.cache/skwd-wall/wallpaper/thumbs/`
- Don't put files like `wallpaper.jpg` directly in the wallpaper dir — skwd-wall may create copies causing duplicates
