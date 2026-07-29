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

## Matugen → Noctalia Integration

**Flow:** Wallpaper change → matugen generates colors → writes to `~/.config/noctalia/colors.json` → `reload` triggers noctalia refresh automatically

**Template:** `~/.config/skwd-wall/data/matugen/templates/noctalia-colors.json`
- Always synced by the activation script (not just seeded once)
- **Surface colors are static** (neutral dark `#0a0a0a`, `#1a1a1a`) — bar background stays neutral
- **Accent colors are dynamic** (primary, secondary, tertiary) from wallpaper

**Integration config** in `config.json` (patched on every activation via jq):
```json
"integrations": [
  {
    "name": "skwd-wall",
    "template": "quickshell-colors.json",
    "output": "colors.json"
  },
  {
    "name": "noctalia",
    "template": "noctalia-colors.json",
    "output": "~/.config/noctalia/colors.json",
    "reload": "noctalia-shell ipc call colorScheme refresh"
  }
]
```

The `skwd-wall` built-in integration (`quickshell-colors.json`) is **required** — without it the selector UI stays pink/default.

## Important Gotchas

- **KDE (Elektra): daemon calls `qdbus6`**, but NixOS ships the Qt6 tool as plain `qdbus`. Without the `qdbus6-shim` (added to `home.packages` when compositor is `kde` in `Modules/skwd-wall.nix`), `apply_kde_static` silently fails at spawn and Plasma keeps its old wallpaper — the daemon log still shows a successful-looking "setting wallpaper via plasmashell evaluateScript" INFO line because it's logged before the call.

- Noctalia must use `outOfStoreConfig = "/home/rock/.config/noctalia"` — without this, noctalia reads from the Nix store instead of where matugen writes.
- Do NOT use `pkill -9 quickshell` to reload colors — it kills skwd-wall's quickshell UI too. Use `noctalia-shell ipc call wallpaper refresh` instead.
- **`colorScheme refresh` was removed** from noctalia's IPC — the reload command is now `noctalia-shell ipc call wallpaper refresh`.
- **Zen integrations in config.json break matugen** — their output paths contain literal `\n` which corrupts generated TOML. The activation script strips them on every rebuild. Symptom: `matugen exited with exit status: 1` in `journalctl --user -u skwd-daemon`.
- The activation script patches `config.json` via jq on every rebuild (not just first run), so integrations/reload fields stay correct even if edited manually.

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
