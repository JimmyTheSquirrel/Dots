# Niri — Sisyphus Compositor

**Module:** `Modules/Desktops/niri.nix`
**Pattern:** wrapper-modules with `perSystem`
**Version:** 26.04 (via niri-flake)

## Layout & Window Rules

**Layout settings:**
- `layout.gaps = 4`
- `layout.border.width = 2`, color `#333333`
- `layout.focus-ring.width = 0` — disabled, using border instead
- `layout.default-column-width.proportion = 1.0` — windows fill monitor width
- Border config uses hyphenated syntax: `layout.border.active-color` / `layout.border.inactive-color` (not nested objects)

**Window rules** (in `extraConfig` as raw KDL — `match app-id` syntax can't be expressed in Nix):
- Global: `corner-radius 12`, `clip-to-geometry true`, `geometry-corner-radius`
- Opacity: spotify 0.90, vesktop 0.85, helium 0.85, codium 0.80, thunar 0.90
- Floating: pavucontrol, Picture-in-Picture
- Spotify opens on HDMI-A-1 (secondary monitor)

**Hot corners:** disabled via `gestures { hot-corners { off } }` in extraConfig

**Monitor config** (in `extraConfig`):
```kdl
output "DP-2" { position x=0 y=1080 }
output "HDMI-A-1" { position x=320 y=0 }
```

**Cursor:** configured via `cursor.xcursor-theme` and `cursor.xcursor-size` in wrapper-modules settings

**Niri binary:** wrapped via `pkgs.symlinkJoin` to add `providedSessions` passthru — no startup delay. The old `sleep 2` was removed because it applied to `niri msg` too, causing every IPC call and all app launches from Noctalia to take 2 seconds.

**Opacity changes require logout/login** — Niri's config is baked into the wrapper-modules binary, not hot-reloaded.

## Keybinds

| Key | Action |
|-----|--------|
| `Mod+Return` | Kitty terminal |
| `Mod+E` | Thunar |
| `Mod+F` | Helium browser |
| `Mod+D` | Noctalia app launcher |
| `Mod+W` | SKWD wallpaper selector |
| `Mod+Q` | Close window |
| `Mod+A` | Toggle overview |
| `Mod+V` | Toggle floating |
| `Mod+Shift+F` | Fullscreen |
| `Mod+Shift+Delete` | Noctalia power menu |
| `Mod+M` | Noctalia desktop widget edit mode |
| `Mod+Shift+R` | Toggle rain effect |
| `Mod+Left/Right` | Focus column |
| `Mod+Up/Down` | Focus workspace |
| `Mod+Shift+S` | Screenshot region to clipboard |
| `Mod+S` | Screenshot full screen to clipboard |

IPC actions used by keybinds:
- App launcher: `noctalia-shell ipc call launcher toggle`
- Power menu: `noctalia-shell ipc call sessionMenu toggle`
- Widget edit mode: `noctalia-shell ipc call desktopWidgets edit`
- Wallpaper: `skwd wall toggle`

## Startup Sequence

1. Noctalia shell launches first (instant visual feedback)
2. D-Bus environment setup runs in background (`sh -c '... &'`)
3. Stale Spotify singleton locks cleared (`~/.cache/spotify/SingletonLock`, `SingletonSocket`) — cause Spotify to silently exit if not cleaned
4. Spotify launches via `spotify-startup` (3-second delay, opens to Liked Songs)

Startup optimization: D-Bus environment commands run in background so visual elements load first.

**Noctalia startup delay on Sisyphus:** Noctalia is launched via niri `spawn-at-startup` (NOT systemd), so it's not queued behind server services. However, the server stack (Jellyfin, Immich, arr services) causes CPU/IO contention at login time which slows QML startup. Fixed in `Hosts/Sisyphus/system.nix` — heavy server services are delayed with `after = [ "graphical.target" ]` so they don't start until SDDM is up. Do NOT put this in `server.nix` — Asgard is headless and `graphical.target` is never reached there.

## Spotify Launcher

Two scripts in `environment.systemPackages`:

- **`spotify-startup`** — used by niri `spawn-at-startup`. Sleeps 3s, launches with GPU flags + `--uri` for playlist. Also runs `spotify-apply-colors` on boot: background subshell polls CDP port until ready, then injects saved matugen colors.
- **`spotify-open`** — used by the app launcher `.desktop` entry. No sleep, handles fresh launch (`--uri`) and already-running (D-Bus MPRIS `OpenUri`).

The `spotify` binary is never replaced (avoids infinite recursion with spicetify's wrapper). `home-manager.users.rock.xdg.desktopEntries.spotify` overrides the `.desktop` to call `spotify-open %U`.

**Spotify opens to Liked Songs:** `LIKED_SONGS="spotify:collection:tracks"` in both scripts. Fresh launch uses `--uri` flag. Already-running uses `dbus-send --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.OpenUri string:URI`. To change target, update `LIKED_SONGS` in both scripts. If `spotify:collection:tracks` stops working, replace with a real `spotify:playlist:ID` URI.

`kdePackages.qttools` provides `qdbus6` for D-Bus calls to Spotify.

## Steam Launcher

Steam has niri spawn issue (niri issue #2463 — apps launched via `niri msg action spawn` fail silently without delay). Fixed with `steam-open` script:
- Checks if steam is already running (`pgrep -x steam`); if so, opens library (`steam steam://open/games`); if not, `sleep 1 && steam "$@"` in background
- `xdg.desktopEntries.steam` overrides the `.desktop` to call `steam-open %U`
- Plain `steam` wrapper (with `-no-cef-sandbox`) remains for direct terminal use

## Bluetooth (for RPCS3 / controller)

Configured in `niri.nix`:
- `hardware.bluetooth.powerOnBoot = true`
- `hardware.bluetooth.settings.Policy.AutoEnable = "true"`
- `services.blueman.enable = true`
- After pairing, run `bluetoothctl trust <MAC>` once for auto-reconnect on PS button press
