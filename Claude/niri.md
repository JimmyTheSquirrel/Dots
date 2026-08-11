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
- Opacity: spotify 0.75, steam 0.85, vesktop 0.85, helium 0.85, discord 0.80, codium 0.80, thunar 0.90
- Floating: pavucontrol, Picture-in-Picture
- Spotify opens on HDMI-A-1 (secondary monitor)

**These opacity rules are load-bearing, not decoration.** For Steam and Spotify the
window rule is the *only* thing producing the glass effect — both are CEF/Electron
apps whose surface has no alpha channel, so their CSS themes cannot make them
see-through. Removing the rule doesn't dim the app, it removes the effect the theme
was designed around. See `Claude/steam.md` and `Claude/spicetify.md`.

`^steam$` deliberately matches the Steam *client* only — in-game windows get
`app-id "steam_app_<id>"`, so games are never faded.

**The hiPrio `steam` wrapper must track `config.programs.steam.package`.** The
`writeShellScriptBin "steam"` in `environment.systemPackages` (adds
`-no-cef-sandbox`) is `lib.hiPrio`, so it wins the `steam` name in the system
path, and the `.desktop` override routes every launch through it via
`steam-open`. It wrapped bare `pkgs.steam` until 2026-08-10, which silently
discarded everything `Modules/steam.nix` configures — Millennium *and* the
PipeWire audio fix. `nix eval` looked correct the whole time. See `Claude/steam.md`.

**Hot corners:** disabled via `gestures { hot-corners { off } }` in extraConfig

**The left screen edge yanking the view sideways is focus-follows-mouse, NOT hot
corners.** Moving the pointer to the edge lands it on the sliver of the
neighbouring column, focus follows it, and niri scrolls that column into view —
so a stray mouse movement silently changes what you're looking at. Fixed
2026-08-10 with `max-scroll-amount = "0%"`, which keeps focus-follows-mouse for
windows already fully on screen and refuses any focus change that needs
scrolling. Check hot-corners in the *running* config before believing it's them:

```bash
grep -A2 hot-corners "$(tr '\0' '\n' < /proc/$(pgrep -x niri)/environ | grep -oP '(?<=^NIRI_CONFIG=).*')"
```

**KDL properties can't be written as a Nix attrset.** `input.focus-follows-mouse
= { max-scroll-amount = "0%"; }` serialises to *child nodes*, and niri rejects it
(`unexpected node max-scroll-amount`). The `_: { … }` function form emits KDL
**properties** on the node — `focus-follows-mouse max-scroll-amount="0%"` — which
is what niri wants. `_: {}` is the same idiom for a bare no-property node.

**Monitor config** (in `extraConfig`):
```kdl
output "DP-2" {
  mode "2560x1080@144.001"
  position x=0 y=1080
}
output "HDMI-A-1" { position x=320 y=0 }
```

**DP-2 needs an explicit `mode` or it runs at 60 Hz.** The LG ULTRAWIDE's EDID declares
`2560x1080@59.938` as its *preferred* mode (DTD 1 in the base block, with the "first detailed
timing is the preferred refresh rate" flag set). 144 Hz is DTD 5, off in the CTA-861 extension
block. With no `mode` line niri does the standards-correct thing, honours the preferred flag,
and you silently get 60 Hz — which is how it ran until 2026-08-05. Verify with:

```bash
niri msg outputs | grep -A1 DP-2     # want "@ 144.001 Hz", not "59.938 Hz (preferred)"
```

Decode the EDID with `edid-decode /sys/class/drm/card1-DP-2/edid` (in `v4l-utils`; note
`nix run nixpkgs#edid-decode` fails — the binary is under the `v4l-utils` derivation, so run
it by store path). Panel facts worth knowing before chasing colour problems:

- **8 bits per primary colour channel** — it is an 8-bit panel, 10-bit is not achievable at any
  refresh rate. Confirm the driver side with `sudo cat /sys/kernel/debug/dri/*/DP-2/output_bpc`
  (root-only; `drm_info`'s `max bpc` is just the connector ceiling, not the negotiated value).
- Range limits 50–144 Hz, max dotclock 450 MHz. 144 Hz needs 442.6 MHz — inside the limit, but
  only just.
- Bandwidth is not a constraint: 144 Hz at 8bpc RGB is 10.6 Gbps against DP HBR2's ~17.3 Gbps
  effective, so high refresh costs no colour depth or chroma subsampling here.

If 144 Hz ever fails to apply, suspect the monitor's OSD defaulting to DisplayPort 1.1, which
caps link bandwidth below what the mode needs. That is an on-monitor setting, not a Nix one.

**KDL comments are `//`, not `#`.** `#` starts a keyword/raw-string in KDL v2, so a `#` comment
inside `extraConfig` fails the build with a parse error pointing at the comment text. The niri
package runs `niri validate` during its install phase, so a malformed config breaks the *build*
rather than your session — a config typo can't lock you out.

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
| `Mod+B` | Keybind cheatsheet (kenn/keybind-cheatsheet) |
| `Mod+Q` | Close window |
| `Mod+A` | Toggle overview |
| `Mod+V` | Toggle floating |
| `Mod+Shift+F` | Fullscreen |
| `Mod+Shift+Delete` | Noctalia power menu |
| `Mod+M` | Noctalia desktop widget edit mode |
| `Mod+Shift+R` | Toggle rain effect |
| `Mod+J` / `Mod+R` | Cycle column width / reset window height |
| `Mod+Left/Right` | Focus column |
| `Mod+Up/Down` | Focus workspace |
| `Mod+1`–`Mod+5` | Focus workspace 1–5 |
| `Mod+Shift+Left/Right` | Move column left/right |
| `Mod+Shift+Up/Down`, `Mod+Shift+1`–`5` | Move column to workspace |
| `Mod+WheelScrollUp/Down` | Scroll columns left/right |
| `Mod+Shift+S` | Screenshot region to clipboard |
| `Mod+Shift+Slash` | Niri's native hotkey overlay |

Removed deliberately: `Mod+F11` (duplicate of `Mod+Shift+F`) and `Mod+S` (full-screen capture — region only).

### Media keys must name the player — `skwd-music` swallows them otherwise

The play/pause/next/prev binds use `playerctlCmd` (a `let` binding in `niri.nix`):

```
playerctl --player=spotify,%any --ignore-player=skwd-music
```

**Bare `playerctl` is a no-op on this system.** skwd-daemon registers an inert
`org.mpris.MediaPlayer2.skwd-music` player that sorts before `spotify`, and it advertises
`CanControl` / `CanPlay` / `CanPause` / `CanGoNext` = `true` while doing nothing. playerctl
picks it, fires the method at it, and exits 0 — so every media key silently did nothing.

Note the asymmetry that makes this confusing to diagnose: `playerctl metadata` *looks* correct,
because skwd-music exposes no metadata so playerctl falls through to Spotify for property reads.
Only **commands** land on the stub. Test with the command, never the property:

```bash
playerctl -a status                        # per-player truth
playerctl play-pause                       # bare: nothing changes
playerctl --player=spotify play-pause      # works
```

`%any` keeps browser video working when Spotify isn't running; `--ignore-player` is what stops
the stub winning that fallback.

**Don't name the binding `playerctl`.** `environment.systemPackages` uses a `with pkgs;` list
containing a bare `playerctl`, so a top-level `let playerctl = "…"` shadows the package and the
build fails with *"is not of type `package`"*.

**Niri's native overlay is on-demand only.** By default niri pops the "Important Hotkeys" window at *every* session start, so it appeared on each login out of SDDM. Suppressed 2026-08-08 with `hotkey-overlay.skip-at-startup = _: {};` in the wrapper `settings` (renders as `hotkey-overlay { skip-at-startup }` in the baked config). This is niri's own overlay — not the `kenn/keybind-cheatsheet` panel on `Mod+B`, which has no autostart behaviour.

### Locking the mouse to one monitor for games — use gamescope

**Niri cannot force pointer confinement.** Verified on 26.04:
- `niri msg action` lists no pointer/confine/grab action
- a `confine-pointer` window rule fails `niri validate` — *unexpected node*
- a Wayland client cannot grab the pointer for another client, so no external helper works either

(Don't try to confirm this with `strings` on the niri binary — it's stripped, and greps for even known rule names like `open-floating` return nothing. Use `niri validate` on a throwaway config instead.)

Niri **does** advertise `zwp_pointer_constraints_v1` and `zwp_relative_pointer_manager_v1` (`nix run nixpkgs#wayland-utils`), so a game that requests pointer lock itself already works. **If the mouse escapes, check the game is in true fullscreen first** — borderless-windowed is the usual cause.

For games that still escape, use **gamescope** — a nested compositor that owns the pointer outright. Already installed via `programs.steam.gamescopeSession` (`Modules/steam.nix`). Set per-game Steam launch options:

```
gamescope -W 2560 -H 1080 -f --force-grab-cursor -- %command%
```

`--force-grab-cursor` forces relative mouse mode so the cursor cannot leave the game. `-g/--grab` additionally grabs the keyboard (toggle in-session with `Super+G`).

**REMOVED 2026-08-05 — `Mod+G` → `game-lock`.** This confined the pointer by turning every *other* output off. The monitor-disabling was never wanted: it blanked the second screen with no warning, and (per niri's behaviour) relocated that output's windows and workspaces onto the remaining monitor **without moving them back** on restore. Don't reintroduce an output-disabling approach — use gamescope.

If a monitor ever goes dark unexpectedly, `niri msg outputs` distinguishes the cases: `Disabled` with a full mode list = something turned the output off in software; a missing/empty entry = a real link or hardware fault.

**Keybind definitions: one source of truth — `mkKeybinds` in `Modules/Desktops/niri.nix`.**

Each entry is `{ key; title; category; action; }`. The list is consumed twice:

| Consumer | Via | Result |
|----------|-----|--------|
| Wrapped niri package | `mkNiriBinds` → `binds = { … }` | The baked config the compositor actually runs |
| Cheatsheet plugin | `mkKeybindsKdl` → `niriCheatsheet` activation | `~/.config/niri/niri-keybinds.kdl`, with `hotkey-overlay-title` + `// #"Category"` groupings |

`title` and `category` are cheatsheet-only; the wrapper-modules `binds` schema takes `action` alone. **Add or change a bind in `mkKeybinds` and both outputs stay in step — never hand-edit the generated KDL.**

This replaced a hand-maintained parallel heredoc that had already drifted: `Mod+Shift+Slash` was missing from the cheatsheet, and its `Mod+Shift+S` read `grim -g $(slurp) | wl-copy` — no `-` operand and an unquoted `$(slurp)`, which word-splits so grim takes the `WxH` half as an output filename.

## Niri reads ONE config — the baked one

**Niri never reads `~/.config/niri/config.kdl`.** The `…/bin/niri` wrapper pins the store path, and it wins even with the env var cleared:

```bash
env -u NIRI_CONFIG niri validate   # → loaded config from "/nix/store/…-niri-26.04/niri-config.kdl"
```

So `config.kdl`, `niri-keybinds.kdl` and `noctalia.kdl` exist **purely as plugin input**. Editing them cannot change a live keybind, and noctalia's matugen-generated `noctalia.kdl` focus-ring/border colours never reach the compositor either (moot in practice — the baked config sets `focus-ring width 0`). Any window rule that must actually apply — e.g. the `place-within-backdrop` wallpaper layer-rule — belongs in the baked config in `niri.nix`.

> Earlier revisions of this doc claimed niri merged the baked config with the user config and that user binds won. That was never true; the local files were inert all along.

## Keybind Cheatsheet Plugin (kenn/keybind-cheatsheet)

The `kenn/keybind-cheatsheet` noctalia community plugin (v0.2.1) shows a categorised hotkey overlay panel, toggled via `Mod+B`.

**How it's wired (working solution, 2026-08-02):**

The plugin reads `~/.config/niri/config.kdl` (its `niri_config` **default**) and follows `include` directives, so it lands on `niri-keybinds.kdl`. Rather than fight the plugin's config resolution, `niri-keybinds.kdl` is made to *be* the decorated file.

A single `niriCheatsheet` HM activation installs both files from the store, unconditionally, so they can never drift from the baked config:

```nix
# after = ["writeBoundary"];   ← keeps `--dry-run` read-only
install -m 644 ${mkKeybindsKdl {…}} "$HOME/.config/niri/niri-keybinds.kdl"
install -m 644 ${niriIncludesKdl pkgs} "$HOME/.config/niri/config.kdl"
[ -e "$HOME/.config/niri/noctalia.kdl" ] || : > "$HOME/.config/niri/noctalia.kdl"
rm -f "$HOME/.local/state/noctalia/plugins/data/kenn/keybind-cheatsheet/bindings-cache.json"
```

Notes:
- Real files, not `home.file` symlinks — the plugin snapshots paths, and a store-symlink swap can race its reader.
- `noctalia.kdl` is seeded empty if absent so a fresh install has no dangling `include`; noctalia overwrites it from its niri theme template on first run.
- `keybinds-for-cheatsheet.kdl` is **gone**. It only ever existed to feed the dead `niri_config` TOML override below; the activation removes stale copies.
- `after = ["writeBoundary"]` is the raw form of `lib.hm.dag.entryAfter` — `lib.hm` is only in scope inside `home-manager.users.<name>` submodules, and this is a NixOS module.

**Gotcha: `[plugins."kenn/keybind-cheatsheet"] niri_config = …` in nix-config.toml does NOT work.** Noctalia's `settings.toml` has its own top-level `[plugins]` table that wins the merge, so the per-plugin subtable never reaches the plugin's `getConfig()`. Confirmed by inspecting `bindings-cache.json` — its `request.root` stayed at the default `~/.config/niri/config.kdl`. Don't waste time on that path again.

**Gotcha: `Mod+B` needs the fully-qualified panel ID.** `noctalia msg panel-toggle cheatsheet` fails with `unknown panel`. The correct command is:
```
noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet
```

**Category structure.** The plugin takes the category from a `// #"Name"` comment when one precedes the bind, and only falls back to its own action-name heuristic (`niriCategoryFor`) otherwise — so the `category` field in `mkKeybinds` fully controls the grouping. Order in `keybindCategories` is the panel's column order.

| Category | Contents |
|----------|----------|
| `Applications` | Launchers plus the panel/toggle actions — Power Menu, Rain Effect, Hotkey Overlay |
| `Window Management` | Acts on the focused window: Close, Overview, Toggle Float, Fullscreen |
| `Workspace - Navigation` | Moving *focus* — Mod+arrows, Mod+1–5, WheelScroll |
| `Workspace - Movement` | Moving the *focused column* — Mod+Shift+arrows, Mod+Shift+1–5 |
| `Workspace - Management` | Column sizing within a workspace — Cycle Width, Reset Height |
| `Screenshots` | grim region capture |
| `Media` | Volume/playback keys |

**Ordering convention inside each category:** plain `Mod` binds first, then `Mod+Shift`, then `Mod+WheelScroll` last. The generator emits binds in list order, so keep `mkKeybinds` sorted that way.

### Debugging the plugin

The plugin caches parsed binds at `~/.local/state/noctalia/plugins/data/kenn/keybind-cheatsheet/bindings-cache.json`. Inspect it to see exactly what was parsed and from where:

```bash
grep -o '"description":"[^"]*"' ~/.local/state/noctalia/plugins/data/kenn/keybind-cheatsheet/bindings-cache.json
grep -o '"category":"[^"]*"'   ~/.local/state/noctalia/plugins/data/kenn/keybind-cheatsheet/bindings-cache.json | sort -u
grep -o '"root":"[^"]*"'       ~/.local/state/noctalia/plugins/data/kenn/keybind-cheatsheet/bindings-cache.json
```

Empty `description` fields = plugin is reading a file without `hotkey-overlay-title` decorations.

Force a re-parse without restarting noctalia (service-style entries need target `all`):
```bash
noctalia msg plugin kenn/keybind-cheatsheet:data all refresh
noctalia msg plugin kenn/keybind-cheatsheet:data all self-test   # writes selftest.json
```

**After changing niri.nix:** Run `nixos-rebuild switch --flake '.#rock-Sisyphus' --no-eval-cache`. The `--no-eval-cache` flag is required — the niri wrapper-modules derivation output is aggressively cached and rebuilds will silently serve stale DRVs without it.

IPC actions used by keybinds:
- App launcher: `noctalia msg panel-toggle launcher`
- Power menu: `noctalia msg panel-toggle session`
- Widget edit mode: `noctalia msg desktop-widgets-edit`
- Wallpaper: `skwd wall toggle`

## Startup Sequence

1. Noctalia shell launches first (instant visual feedback)
2. **`wallpaper-restore`** paints the wallpaper immediately (see below)
3. D-Bus environment setup runs in background (`sh -c '... &'`)
4. Stale Spotify singleton locks cleared (`~/.cache/spotify/SingletonLock`, `SingletonSocket`) — cause Spotify to silently exit if not cleaned
5. Spotify launches via `spotify-startup` (3-second delay, opens to Liked Songs)

Startup optimization: D-Bus environment commands run in background so visual elements load first.

### Black background on login — `wallpaper-restore`

**Symptom:** wallpaper missing (black) on some/all workspaces right after login.

**Cause:** `skwd-daemon` is a systemd user service gated on `After = ["graphical-session.target"]`, so it only paints once the session target is reached — well after niri has drawn its first frame. This got worse after noctalia's startup was sped up, since there's now less incidental delay masking the gap.

**Fix:** a `wallpaper-restore` script in `environment.systemPackages`, spawned from niri's `spawn-at-startup` right after `noctalia`. It reads the cached last wallpaper and paints it with swaybg immediately — no waiting on systemd:

```nix
(writeShellScriptBin "wallpaper-restore" ''
  CACHE="$HOME/.cache/skwd-wall/last-wallpaper.json"
  [ -f "$CACHE" ] || exit 0
  WALL=$(${pkgs.jq}/bin/jq -r .path "$CACHE" 2>/dev/null)
  [ -n "$WALL" ] && [ -f "$WALL" ] || exit 0
  exec ${pkgs.swaybg}/bin/swaybg -m fill -i "$WALL"
'')
```

Absolute nix store paths are required — `spawn-at-startup` does not get a full `PATH`. `skwd-daemon` takes over the layer-shell surface once it starts; swaybg sits on the plain background layer underneath, so there's no conflict.

**This only takes effect after a rebuild AND re-login** — `spawn-at-startup` is baked into the niri wrapper binary.

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
