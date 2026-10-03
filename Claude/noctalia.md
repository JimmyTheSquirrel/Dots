# Noctalia — Desktop Shell

**Module:** `Modules/Desktop/noctalia.nix`
**Used on:** Sisyphus (Niri) and Odysseus (Hyprland)

## Architecture (v5)

Noctalia v5 is a **native C++ application** (not QuickShell). The binary is **`noctalia`**.

Config loading (merge order, lowest → highest priority):
1. Built-in defaults
2. All `*.toml` files in `~/.config/noctalia/` (sorted alphabetically — `nix-config.toml` goes here)
3. `~/.local/state/noctalia/settings.toml` — GUI changes land here, **wins at runtime**

## Settings Files

| File | Who writes it | What it controls |
|------|--------------|-----------------|
| `~/.config/noctalia/nix-config.toml` | Nix (`home.file`) | TOML defaults — merged **under** GUI state, so any key here is a fresh-install default the GUI can override |
| `~/.local/state/noctalia/settings.toml` | noctalia GUI **and Nix** | TOML runtime state: bar layout, widget slots, capsule groups, theme source, `background_opacity`. Wins the runtime merge — but **every rebuild rewrites it**, see below |
| `~/.config/noctalia/settings.json` | noctalia GUI | Legacy JSON. Still written, **not read** at startup — see below |

**Only TOML is live.** `settings.json` is a v4 leftover that noctalia still rewrites on GUI changes but does not load; editing it changes nothing. Don't write it from Nix and don't reason about it as a second config system.

### ⚠️ Nix owns `settings.toml` (since 2026-09-30)

The merge order above is upstream's, and it makes `nix-config.toml` structurally unable to control anything the GUI has ever touched — which is *most of the desktop*: bar position, widget slots, capsule groups, lockscreen layout, template lists. Before this, a rebuild changed none of it and a fresh install came up with noctalia's defaults.

So `noctalia.nix` stops fighting the merge order and writes `settings.toml` directly:

- **`lockedSettings`** in `Modules/Desktop/noctalia.nix` is the canonical desktop state.
- **`home.activation.noctaliaSettingsLock`** deep-merges it *over* the live file on every rebuild — locked keys forced, undeclared keys passed through — then runs `noctalia msg config-reload`.

**Tune in the GUI freely; the next rebuild reverts it.** That is the intended workflow: GUI for testing, `lockedSettings` for keeping.

Deliberately **not** locked, because they are genuine runtime state:

| Key | Owner |
|---|---|
| `config_version` | noctalia's own schema migrations — pinning it would fight them |
| `[wallpaper.last]`, `[wallpaper.default]`, `[wallpaper.monitors.*]` | skwd, rewritten on every wallpaper swap |

(`wallpaper.enabled = false` *is* locked — noctalia must keep painting nothing.)

Arrays are replaced wholesale, never appended: a locked `start` or `capsule_group` is the complete list.

**To re-snapshot after a round of GUI tuning,** read `~/.local/state/noctalia/settings.toml` and fold the changed keys back into `lockedSettings`. Write floats clean — a slider produces `0.54999998770654202`, noctalia stores float32, and `0.55` is not distinguishable on screen.

`config-reload` really does re-read `settings.toml`, so no re-login is needed. Verified 2026-09-30 by changing a value on disk and confirming it **survived** a subsequent noctalia-initiated write of the same file — impossible if the shell were still holding its old copy in memory. (noctalia's stdout/stderr go to `/dev/null`, so there is no log to check this from; it has to be done behaviourally.)

### Which file does a given key belong in?

- **Has the GUI ever written it?** → `lockedSettings`. Check with `grep -A5 '\[shell.panel\]' ~/.local/state/noctalia/settings.toml`.
- **Untouched by the GUI?** → `nix-config.toml` is fine and simpler. `[widget.clock] format`, `[shell.mpris] blacklist` and `[idle]` live there and are live precisely because the GUI has never set them.

Keys may appear in both; `settings.toml` then decides, and Nix controls both sides anyway.

## IPC Commands

```bash
noctalia msg panel-toggle launcher      # App launcher
noctalia msg panel-toggle session       # Power/session menu
noctalia msg templates-apply            # Re-apply theme templates after color change
noctalia msg config-reload              # Reload *.toml config files (hot-reload via inotify is automatic)
noctalia msg wallpaper-set <path>       # Update noctalia's internal wallpaper path (triggers color regen)
noctalia msg wallpaper-get              # Print current internal wallpaper path
noctalia msg color-scheme-get           # Print active color scheme source and name
noctalia msg dpms-off / dpms-on         # Monitors off/on via the compositor's own IPC
noctalia msg caffeine-toggle            # Idle inhibitor on/off (also a bar widget)
```

`noctalia config …` is a separate command family from `noctalia msg …` — it reads
and checks config files rather than talking to the running shell. See
[Verifying](#verifying) under Idle.

**Restarting noctalia:** it is launched by niri via `spawn-at-startup`, not a systemd service. There is no `noctalia.service`. To restart after a hard crash:
```bash
pkill -f 'noctalia$' && noctalia &
```

## Declarative Config (Nix)

Two mechanisms, and the difference matters — see [Which file does a given key belong in?](#which-file-does-a-given-key-belong-in) above:

| | `nix-config.toml` (`home.file`) | `lockedSettings` (activation) |
|---|---|---|
| Writes | `~/.config/noctalia/nix-config.toml` | `~/.local/state/noctalia/settings.toml` |
| Precedence | merged **under** the GUI | **overwrites** the GUI each rebuild |
| Use for | keys the GUI has never set | anything the GUI can touch |

`home.file.".config/noctalia/nix-config.toml"` sets baseline TOML defaults. The GUI (`settings.toml`) overrides any conflicting keys, so a key here is only live while the GUI has not set it.

Current managed keys:
- `[widget.clock] format` / `tooltip_format` — strftime-style format strings (live; the GUI has not set these)
- `[shell.panel] transparency_mode` — fresh-install default; GUI already sets the same value
- `[idle]` + `[idle.behavior.screen-off]` — monitors DPMS off after 5 min idle (see below)
- `[plugins] enabled` + `[[plugins.source]]` — plugin registry and git sources

**Do NOT add a `[plugins."<author>/<name>"]` table** to configure a plugin. Per-plugin subtables are silently dropped: `settings.toml`'s own top-level `[plugins]` wins the merge outright, so the subtable never reaches the plugin's `getConfig()`. TOML has no `~` expansion either. Plugins fall back to their built-in defaults — for the keybind cheatsheet that means `~/.config/niri/config.kdl`, which `niri.nix` generates. See `Claude/niri.md`.

On a fresh install noctalia creates `~/.local/state/noctalia/settings.toml` on first launch. The `nix-config.toml` applies immediately.

**Plugin sources are fetched from GitHub at runtime**, not pinned by the flake — `[[plugins.source]]` points at `noctalia-dev/official-plugins` and `community-plugins` HEAD. This is the one unpinned input in an otherwise fully-pinned config: a fresh install needs network access and gets whatever is current. Pinning would mean vendoring the plugins as a flake input.

## Idle / monitor power-save (`[idle]`)

Screens DPMS off after **5 minutes** of no input, and back on at the first key or
mouse event. Noctalia runs this itself (`src/idle/idle_manager.cpp`) — **there is no
swayidle or hypridle on any host, and none is needed.** It takes idle notifications
from the compositor over `ext-idle-notify-v1` and drives DPMS through the
compositor's own IPC: `PowerOffMonitors` / `PowerOnMonitors` on niri, the
equivalent dispatcher on Hyprland.

```toml
[idle]
pre_action_fade_seconds = 2.0      # fullscreen dim warning; activity cancels it. 0 = no warning

[idle.behavior.screen-off]
enabled = true
timeout = 300                      # seconds
action  = "screen_off"
```

**This is DPMS, not an output disable.** Outputs stay configured, so unlike
`niri msg output … off` nothing relocates windows or workspaces onto the surviving
monitor. (That distinction is exactly what made the old `Mod+G` game-lock bind
unacceptable — see `Claude/niri.md`.)

`screen_off` auto-pairs a `ScreenOn` resume action, so no `resume_command` is
needed and there is no way to be left with black screens.

**What stops it blanking mid-film** — all three are honoured:
- `zwp_idle_inhibitor_v1` — noctalia binds the *inhibitor-aware*
  `get_idle_notification`, not the input-only variant, so mpv/browser video holds it off
- `org.freedesktop.ScreenSaver` D-Bus inhibits (Steam, most games)
- Caffeine — the bar toggle, or `noctalia msg caffeine-toggle` / `caffeine-enable`

**⚠️ Sunshine does not inhibit idle.** Moonlight's injected keyboard and mouse
events are real uinput devices and do reset the timer, but a **controller-only**
session sends nothing libinput sees — five minutes in, the screens DPMS off and the
wlr capture goes dark with them. Enable Caffeine before a couch-gamepad stream.
See `Claude/streaming.md`.

### Schema gotchas

Upstream schema: `src/config/schema/config_schema.cpp`, defaults in
`src/config/config_types.cpp` (`defaultIdleBehaviors`).

- Behaviours are a **`namedMap`**: `[idle.behavior.<name>]`. `[[idle.behavior]]`
  parses as an array, `namedMap` reads it with `as_table()`, gets null, and
  **skips it silently** — and `noctalia config validate` still prints "Config is
  valid". Validation does not catch this one; check the effective config instead.
- The key is `timeout` (seconds), **not** `timeout_seconds`. That typo *is*
  caught: `WARN idle.behavior.screen-off.timeout_seconds: unknown setting`.
- Actions: `lock` | `screen_off` | `suspend` | `lock_and_suspend`. Any other
  string falls through to running `command` / `resume_command` as a shell action.
- **Declaring any behaviour replaces the built-in default list** (`lock` 600s,
  `screen-off` 660s, `lock-and-suspend` 900s). All three ship `enabled = false`,
  so nothing is lost. An *empty* list is what restores them.
- `[idle]` lives in `nix-config.toml`, **not** in `lockedSettings`, because the GUI
  has never written it. So this is the one area still exposed to the old failure
  mode: touching the Idle page in the Settings GUI writes `[idle]` into
  `settings.toml`, which wins, and no rebuild will take it back. If that happens,
  move the `[idle]` tables into `lockedSettings` rather than trying to fix it in
  `nix-config.toml`.

### Verifying

```bash
noctalia config validate <file|dir>    # TOML syntax + unknown keys + bad values
noctalia config export merged          # user config as noctalia actually merged it
noctalia config export full            # same, including every built-in default
noctalia msg dpms-off; sleep 5; noctalia msg dpms-on   # prove the DPMS path by hand
```

`config validate` takes a **path**, so a rendered file can be checked before any
rebuild:

```bash
nix eval --raw '.#nixosConfigurations.rock-Sisyphus.config.home-manager.users.rock.home.file.".config/noctalia/nix-config.toml".text' > /tmp/probe.toml
noctalia config validate /tmp/probe.toml
```

No re-login needed after a rebuild — noctalia watches `~/.config/noctalia/*.toml`
with inotify and reloads. (Contrast niri, whose config is baked into the wrapper.)

## Bar Configuration

**The bar is locked** — edit `lockedSettings.bar.main` in `Modules/Desktop/noctalia.nix` and rebuild. GUI changes to the bar survive only until the next rebuild.

### Visual settings (TOML — `settings.toml` or `nix-config.toml`)

```toml
[bar.main]
background_opacity = 0.55   # "Shadow" slider in GUI — darkness of bar bg (0=transparent, 1=opaque)
                            # NOTE: "opacity" is NOT a valid key — noctalia logs "unknown setting"
radius = 80                 # Overall bar corner radius
start = [ "workspaces" ]    # Left slot widget IDs
center = [ "group:g1" ]     # Center slot (capsule group reference)
end = [ "volume", "network", "bluetooth", "notifications", "tray", "clock" ]

[[bar.main.capsule_group]]
id = "g1"
members = [ "media", "audio_visualizer" ]
fill = "surface_variant"
opacity = 0.45
radius = 7.0
```

**Note on `background_opacity`:** dark-mode Material You surfaces are near-black, so `background_opacity = 0.55` still looks dark — it gives a shadow/overlay effect rather than visible transparency. This is intentional and called "Shadow" in the noctalia GUI.

### Launcher panel opacity

Use `[shell.panel] transparency_mode` — `"solid"` (default), `"soft"`, or `"glass"`. Currently `"soft"`.

There is no *numeric* launcher opacity: `settings.json` keys like `ui.panelBackgroundOpacity` are silently ignored (that file isn't read at all), and arbitrary numeric keys under `[shell.launcher]` return "unknown setting". `transparency_mode` is the only supported control.

> An earlier revision of this doc claimed the whole `[shell.panel]` table was rejected. That was wrong — `transparency_mode` is valid and applied.

### Widget content (`settings.json` — legacy, not read)

Widget definitions live in `bar.widgets.left/center/right`. **Noctalia v5 does not load this file** — it's a v4 leftover that the GUI still rewrites. Bar layout is driven by the TOML `start`/`center`/`end` slot lists above. The IDs below are kept for reference when reading old `settings.json` dumps:

| ID | Slot | Description |
|----|------|-------------|
| `Workspace` | left | Workspace indicator dots/numbers |
| `ControlCenter` | left | Noctalia logo — opens launcher/control panel |
| `MediaMini` | center | Now-playing track + audio visualizer |
| `Volume` | right | Volume control |
| `Network` | right | Network status |
| `Bluetooth` | right | Bluetooth toggle |
| `Clock` | right | Clock |
| `NotificationHistory` | right | Notification bell |
| `Tray` | right | System tray |

Editing `settings.json` has **no effect**. Change the bar in `lockedSettings.bar.main` (`Modules/Desktop/noctalia.nix`), or in the GUI if you only want it until the next rebuild.

Note `jq` is not on the interactive PATH here; use a full store path (`${pkgs.jq}/bin/jq` in Nix, or `nix run nixpkgs#jq` ad hoc).

## Audio Visualizer — source is the PipeWire graph, not a setting

The `audio_visualizer` bar widget has **no source option**. `noctalia config export full` shows
its entire schema:

```toml
[widget.audio_visualizer]
bands = 30
centered = false
scale = 1.1
width = 170
```

It opens one PipeWire capture stream — `media.name = "Noctalia Spectrum"`, `application.name`
the same, `node.name = ".noctalia-wrapped"` — with `stream.capture.sink = true` and
`target.object` set to **the default sink**. So out of the box it renders the monitor of the
speakers: Discord voice, game audio and browser tabs all drive the bars.

Fixing that means changing the graph. `noctalia.nix` adds a loopback sink `spotify_tap` that
Spotify plays into and which forwards to whatever the default sink currently is:

```
spotify ─→ spotify_tap ─→ spotify_tap_out ─→ default sink (speakers)
                └ monitor ─→ Noctalia Spectrum
Chromium/games ────────────→ default sink        (never seen by the visualizer)
```

Three drop-ins, and **which file each rule goes in is the whole trick**:

| File | Section | Target | Why there |
|------|---------|--------|-----------|
| `pipewire.conf.d/91-spotify-visualizer-sink` | `context.modules` | creates `spotify_tap` | `libpipewire-module-loopback` |
| `pipewire-pulse.conf.d/91-spotify-visualizer-route` | `pulse.rules` | Spotify → `spotify_tap` | Spotify is a Pulse client (`client.api = "pipewire-pulse"`, binary `.spotify-wrapped`) |
| `client.conf.d/91-spotify-visualizer-capture` | `stream.rules` | Spectrum → `spotify_tap` | noctalia is a **native** libpipewire client, so its props come from `client.conf` |

**WirePlumber also has a `stream.rules` section, and it is the wrong one.** Its copy is read only
by `scripts/node/state-stream.lua` for save/restore bookkeeping (`match_rules_update_properties`
on a local table). The linking policy reads `target.object` off the *real* node props in
`scripts/linking/find-defined-target.lua`, and only PipeWire's own `client.conf` /
`pipewire-pulse.conf` rules rewrite those. A `node.rules` section does not exist in WP 0.5.14 —
`grep -rho '"[a-z._-]*\.rules"' $wireplumber/share/wireplumber` lists every valid one.

Useful side effect: setting `target.object` in props also defeats WirePlumber's saved per-stream
target, since restore-target skips any stream that already has one (`state-stream.lua:95`).

Notes:
- The loopback's **playback side is deliberately untargeted** so it follows the default sink —
  output switches (headset ↔ HDMI) need no extra wiring.
- `priority.session = 100` keeps `spotify_tap` from ever being auto-picked as the default sink.
  It feeds back into the default sink, so default = `spotify_tap` would be a graph cycle.
- Spotify's per-app volume now lives on the `spotify_tap` sink; master volume still works
  normally because `wpctl set-volume @DEFAULT_AUDIO_SINK@` acts downstream of the loopback.

Verify the wiring (not the settings) when something looks wrong:

```bash
pw-link -l | grep -A2 '^\.noctalia-wrapped:input'   # want spotify_tap:monitor_*, not alsa_output…:monitor_*
pw-link -l | grep -A2 '^spotify:output'             # want spotify_tap:playback_*
```

## MPRIS blacklist — `skwd-music`

`[shell.mpris] blacklist` (matched on the D-Bus session name) excludes players from noctalia's
media widget and `noctalia msg media`. `nix-config.toml` sets it to `["skwd-music"]`: skwd-daemon
registers an inert `org.mpris.MediaPlayer2.skwd-music` that carries no metadata but claims
`CanControl`/`CanPlay`/`CanGoNext`, so it can win the active-player pick and swallow commands.
The niri media keys dodge the same stub with `playerctl --ignore-player` — see `Claude/niri.md`.

The GUI has not written `[shell.mpris]`, so the Nix value is live.

## Clock Format (strftime tokens)

Bar clock uses `strftime`-style percent tokens inside `[widget.clock] format`:

```toml
[widget.clock]
format = "%-I:%M %p"        # 12-hour, no leading zero: 9:34 PM  ← current
# format = "%I:%M %p"       # 12-hour, zero-padded: 09:34 PM
# format = "%-I:%M %P"      # lowercase meridiem: 9:34 pm
# format = "%H:%M"          # 24-hour: 21:34
# format = "%H:%M\n%d/%m"   # two-line: "21:34" / "30/07"
tooltip_format = "%A, %B %d %Y"
```

The glibc `-` flag suppresses the leading zero. This is live config — the GUI has not set `[widget.clock] format`, so the Nix value applies (`capsule`/`capsule_opacity` are the only clock keys in `settings.toml`).

**WRONG formats** (all render literally, not as time):
- `"hh:mm a"` — not strftime syntax
- `"h:mm AP"` — not strftime syntax

The `{:%H:%M}` C++ chrono style also works (noctalia strips `{:` and `}` then passes to strftime).

## Color Theming

**Sisyphus: skwd generates, noctalia fans out** (since 2026-09-15). skwd-iris is the only palette generator; noctalia consumes its palette and pushes it to every template it has enabled.

```
wallpaper change
  → skwd-iris                                        (scheme=content, style=natural)
  → ~/.config/noctalia/palettes/skwd-wall.json       skwd `noctalia` integration
  → noctalia-apply-palette                           its reload command
      = noctalia msg color-scheme-set custom skwd-wall
  → noctalia UI + every enabled template (Discord, …)
```

Three traps, all of which fail *silently* because each output file still exists and still looks themed:

1. **noctalia reads `palettes/<custom_palette>.json`, never `colors.json`.** Writing to `colors.json` is inert. That was the wiring until 2026-09-15, so the bar and everything downstream of it sat on a five-day-old palette.
2. **`templates-apply` is not a re-read.** It renders from the palette already in memory — with only the file on disk changed it prints `ok` and writes nothing. `color-scheme-set` (re-selecting the already-selected palette) is what forces the re-read, and it fans out on its own.
3. **`source` must stay `custom`.** With `source = "wallpaper"` noctalia runs its own generator off its internal wallpaper path and skwd's palette is ignored — two palettes on one desktop, because skwd's picker chrome always themes itself from skwd-iris.

### Templates

`[theme.templates]` in `settings.toml` / `nix-config.toml`:

| | |
|---|---|
| `builtin_ids` | **empty on purpose.** 20 available; the kitty / starship / btop ones write a theme file then run an `apply.sh` that appends an include to the app's main config — but `kitty.conf`, `starship.toml` and `btop.conf` are read-only Nix store symlinks here, so the append cannot land. btop is already covered by skwd's own integration, which renders the `Modules/Shell/btop.nix` mapping into the `dots` theme `btop.conf` actually selects. |
| `community_ids` | `["discord"]` — writes `~/.config/vesktop/themes/noctalia.theme.css`, the theme vesktop has enabled. 65 available, fetched from git at runtime into `~/.local/state/noctalia/community-templates` (same trust model as plugin sources; not pinned by the flake). |

**The `spicetify` and `steam` community templates do not fit this host.** spicetify's targets `Themes/Comfy/` + `Themes/Colorful/` and shells out to `spicetify apply` (which fights spicetify-nix); this host uses the `text` theme. steam's targets the SFP `Material-Theme` skin; this host uses Millennium + Zehn. Both stay on their own skwd integrations — see `Claude/steam.md` and `Claude/spicetify.md`.

Noctalia re-renders a template only when the content changes (it content-hashes into `.noctalia-cache.json`), so an unchanged mtime after `color-scheme-set` means "already current", not "failed".

---

On **Elektra / Odysseus (v1)** the older behaviour still applies: noctalia v5 generates Material You colors from its own **internal wallpaper path** when `[theme] source = "wallpaper"` is set, and does **not** read the `colors.json` matugen writes.

**Critical:** noctalia tracks its own wallpaper path (`[wallpaper.last]` in `settings.toml`), separate from skwd-wall. On a fresh install it defaults to the bundled noctalia wallpaper in the nix store, producing a flat/wrong palette for the bar.

**Fix (v1 hosts only — Odysseus):** `noctalia-sync-wallpaper` runs after each skwd-wall wallpaper change. It lives in **`Modules/skwd-wall.nix`**, the v1 module, beside the `postProcessing` entry that registers it.

1. Takes the wallpaper's **absolute** path as `$1` — skwd's `%path%` placeholder (falls back to `~/.cache/skwd-wall/last-wallpaper.json` only when called manually with no argument)
2. `noctalia msg wallpaper-set <path>` — points noctalia at the right image so its own generator produces the right palette. Skipped if noctalia is <10s old; `wallpaper-set` blocks rendering ~5s at startup
3. Swaps the `swaybg` backdrop that niri's overview uses
4. `noctalia msg templates-apply`

### ⚠️ Sisyphus deleted this script entirely (2026-09-15)

Each of its three jobs disappeared in turn, and it was moved out of `noctalia.nix` — which is **shared with Odysseus** — rather than deleted outright:

| call | why it went |
|---|---|
| `templates-apply` | wrong hook. `postProcessing` fires *before* the integrations render, so it pushed the previous palette. Moved to `noctalia-apply-palette`, an integration **reload**, which runs after its own file is written. |
| `wallpaper-set` | vestigial under `theme.source = "custom"` (palette comes from skwd) and `[wallpaper] enabled = false` (noctalia paints nothing). Also caused a **visible flicker** — it repainted with the old palette, then `color-scheme-set` repainted with the new one. Reported as the bar "taking on the old colour then changing". |
| swaybg swap | skwd v2 serves the overview backdrop natively via `skwd-paper-backdrop`. |

**Nothing on Sisyphus uses `postProcessing` any more,** so the `%path%` machinery is gone with it. The one remaining hook takes no arguments.

**Diagnostic note:** counting `settings.toml` mtime changes *under*counts — `wallpaper-set` and `color-scheme-set` both write it, ~150 ms apart, and coalesce under typical polling. To prove `wallpaper-set` is running, check whether `[wallpaper.default] path` tracks the swaps.

### Wallpaper path: take `%path%`, never parse `skwd status`

**The cache file is not a valid source inside a wallpaper-change hook.** skwd writes `~/.cache/skwd-wall/last-wallpaper.json` *after* running its hooks, so reading it there yields the **previous** wallpaper — which silently put the overview backdrop and noctalia's whole palette one swap behind until 2026-08-16. The path arrives as `%path%` from the `postProcessing` hook instead; `integrations[].reload` commands get no arguments at all, which is why this script no longer lives there. Full measurement in `Claude/skwd-wall.md`.

`~/.cache/skwd-wall/last-wallpaper.json` (`{"path":"/abs/path.jpg","type":"static"}`) remains correct at rest — it was what `wallpaper-restore` read at login (now deleted), and remains the fallback when this script is run by hand on v1.

**Do not re-derive it from `skwd status`.** That field is `null` on a fresh session and carries no directory component. A `grep`/`sed` version of this script shipped briefly and mis-parsed the unquoted `null` — sed's pattern didn't match, so it passed the line through and `$WALL` became the literal string `"current_wallpaper": null,`, which then passed the `-n` guard and launched swaybg against a nonexistent path. Use `jq -r '.path // empty'`, which is null-safe.

### swaybg backdrop — v1 hosts only

**Gone from Sisyphus (2026-09-15)**, along with `wallpaper-restore` and the `^wallpaper$` layer rule. skwd v2 serves a native `skwd-paper-backdrop` surface with blur/dim/theming instead. See `Claude/skwd-wall.md` and `Claude/niri.md`.

On v1, `noctalia-sync-wallpaper` (in `Modules/skwd-wall.nix`) starts swaybg on every wallpaper change. The swap records existing PIDs, starts the replacement, **then** kills the recorded ones — no black frame, and no risk of a blanket `pkill` racing the new instance.

**Match with `pgrep -f 'swaybg -m fill -i'`, not `pgrep -x swaybg`.** nixpkgs wraps swaybg, so its `comm` is `.swaybg-wrapped` and `-x swaybg` matches nothing — which silently leaves stale instances stacked.

### Why `home.packages`, and why store paths

The skwd daemon runs reload commands with a trimmed PATH covering `/etc/profiles/per-user/$USER/bin` and `/run/current-system/sw/bin` (so `noctalia` and the `home.packages` scripts resolve), but `pkgs.writeShellScriptBin` sets no PATH of its own — so anything less common (`jq`, `pgrep`, `ps`, `sleep`, `tr`) must be referenced by full store path. Scripts in `~/.local/bin` are not on PATH at all (exit 127); use `home.packages` so the script itself is found, as with `spotify-apply-colors`.

**On v2 that PATH is ours, not upstream's.** NixOS renders `systemd.user.services.<n>.path` as `Environment=PATH=…`, which **replaces** the inherited PATH — upstream's module lists only its own renderer packages, which would drop the user profile entirely and make every reload exit 127. `Modules/Desktop/skwd.nix` re-adds both dirs. See `Claude/skwd-wall.md`.

This script is wired as a skwd-wall `postProcessing` command — `noctalia-sync-wallpaper %path%` — **not** as the `noctalia` integration's reload command (managed in `skwd-wall.nix`). Only postProcessing substitutes the wallpaper path; see `Claude/skwd-wall.md`.

## Desktop Clock Plugin

Custom plugin at `Resources/Noctalia-Plugins/desktop-clock/`:
- `manifest.json` — Plugin metadata
- `DesktopWidget.qml` — Clock widget showing day, date, and time
- `Anurati-Regular.otf` — Futuristic geometric display font (bundled with plugin)
- Uses **Anurati** font loaded via QML `FontLoader` from the plugin directory
- Anurati only has uppercase letters (A-Z), so numbers/symbols fall back to system font
- Black text outline (`style: Text.Outline`) for visibility on any wallpaper
- Centered on both monitors with no background

## Custom Font Packaging

Anurati font is stored locally at `Resources/Fonts/Anurati-Regular.otf` and packaged in `noctalia.nix`:
```nix
anuratiFont = "${self}/Resources/Fonts/Anurati-Regular.otf";

packages.anurati-font = pkgs.stdenvNoCC.mkDerivation {
  pname = "anurati-font";
  src = anuratiFont;
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/share/fonts/opentype
    cp $src $out/share/fonts/opentype/Anurati-Regular.otf
  '';
};
```
