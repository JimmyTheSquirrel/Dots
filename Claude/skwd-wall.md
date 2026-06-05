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

- Noctalia must use `outOfStoreConfig = "/home/rock/.config/noctalia"` — without this, noctalia reads from the Nix store instead of where matugen writes.
- Do NOT use `pkill -9 quickshell` to reload colors — it kills skwd-wall's quickshell UI too. Use `noctalia-shell ipc call wallpaper refresh` instead.
- **`colorScheme refresh` was removed** from noctalia's IPC — the reload command is now `noctalia-shell ipc call wallpaper refresh`.
- **Zen integrations in config.json break matugen** — their output paths contain literal `\n` which corrupts generated TOML. The activation script strips them on every rebuild. Symptom: `matugen exited with exit status: 1` in `journalctl --user -u skwd-daemon`.
- The activation script patches `config.json` via jq on every rebuild (not just first run), so integrations/reload fields stay correct even if edited manually.

## Troubleshooting

**Matugen errors:** `journalctl --user -u skwd-daemon`

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
