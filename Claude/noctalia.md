# Noctalia — Desktop Shell

**Module:** `Modules/Desktop/noctalia.nix`
**Used on:** Sisyphus (Niri), Kit-Kat (Hyprland), and the Apollo ISO's rescue niri session

## Architecture (v5)

Noctalia v5 is a **native C++ application** (not QuickShell). The binary is **`noctalia`**.

Config loading (merge order, lowest → highest priority):
1. Built-in defaults
2. All `*.toml` files in `~/.config/noctalia/` (sorted alphabetically). Nix writes nothing here any more — the `nix-config.toml` it used to write was retired 2026-10-03, see below
3. `~/.local/state/noctalia/settings.toml` — GUI changes land here, **wins at runtime**

## Settings Files

| File | Who writes it | What it controls |
|------|--------------|-----------------|
| `~/.local/state/noctalia/settings.toml` | noctalia GUI **and Nix** | TOML runtime state: bar layout, widget slots, capsule groups, theme source, `background_opacity`. Wins the runtime merge — but **every rebuild rewrites it**, see below |
| `~/.config/noctalia/settings.json` | noctalia GUI | Legacy JSON. Still written, **not read** at startup — see below |

**Only TOML is live.** `settings.json` is a v4 leftover that noctalia still rewrites on GUI changes but does not load; editing it changes nothing. Don't write it from Nix and don't reason about it as a second config system.

### ⚠️ Nix owns `settings.toml` (since 2026-09-30)

The merge order above is upstream's, and it made the old `nix-config.toml` structurally unable to control anything the GUI has ever touched — which is *most of the desktop*: bar position, widget slots, capsule groups, lockscreen layout, template lists. Before this, a rebuild changed none of it and a fresh install came up with noctalia's defaults.

So `noctalia.nix` stops fighting the merge order and writes `settings.toml` directly:

- **`lockedSettings`** in `Modules/Desktop/noctalia.nix` is the canonical desktop state.
- **`home.activation.noctaliaSettingsLock`** deep-merges it *over* the live file on every rebuild — locked keys forced, undeclared keys passed through — then runs `noctalia msg config-reload`.
- That reload is called **by absolute store path** (`lib.getExe config.programs.noctalia.package`). Home Manager runs activation with an empty PATH (`home.emptyActivationPath`), so the bare `noctalia msg config-reload` it used to be was "command not found" on every switch — hidden by its own `>/dev/null 2>&1 || true`. Fixed 2026-10-03; before that, a rebuild's lock only took effect at the next noctalia start.

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

**`lockedSettings`, always.** There used to be a second home: `nix-config.toml`
(`home.file`, merged *under* the GUI), meant for keys the GUI had never written.
By 2026-10-03 half its keys (`[shell.panel] transparency_mode`, `[theme]`,
`[theme.templates]`, `[plugins]`) were already restated in `lockedSettings`, which
wins, and the rest (`[widget.clock] format`/`tooltip_format`, `[shell.mpris]
blacklist`, `[idle]`) were one GUI click away from being silently overridden for
good. All of it now lives in `lockedSettings` and the file is gone.

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

**Restarting noctalia:** it is launched by the compositor (niri's `spawn-at-startup`, Hyprland's `exec-once`), not a systemd service. There is no `noctalia.service`. To restart after a hard crash:
```bash
pkill -f 'noctalia$' && noctalia &
```

## Declarative Config (Nix)

One mechanism: `lockedSettings` in `noctalia.nix`, rendered to TOML and merged
**over** `~/.local/state/noctalia/settings.toml` on every rebuild (see above).
Per-host differences go in `my.noctalia.lockedSettingsExtra`, deep-merged over it
(Kit-Kat's squared-off bottom bar) — restate only what differs; lists replace
wholesale, so a changed list has to be given in full.

Among the locked keys, the ones that came over from the retired `nix-config.toml`:
- `widget.clock.format` / `tooltip_format` — strftime-style format strings
- `shell.mpris.blacklist` — see [MPRIS blacklist](#mpris-blacklist--skwd-music)
- `idle` + `idle.behavior.screen-off` — monitors DPMS off after 5 min idle (see below)

**Do NOT add a `[plugins."<author>/<name>"]` table** to configure a plugin. Per-plugin subtables are silently dropped: `settings.toml`'s own top-level `[plugins]` wins the merge outright, so the subtable never reaches the plugin's `getConfig()`. TOML has no `~` expansion either. Plugins fall back to their built-in defaults — for the keybind cheatsheet that means `~/.config/niri/config.kdl`, which `niri.nix` generates. See `Claude/niri.md`.

On a fresh install there is no `settings.toml` yet; the lock script starts from an empty document and writes the whole lock out, so noctalia's first launch already comes up with the declared desktop.

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
- `[idle]` is in `lockedSettings` (moved from `nix-config.toml` 2026-10-03). It
  used to be the one area exposed to the old failure mode — touching the Idle page
  in the Settings GUI would have written `[idle]` into `settings.toml`, which won,
  and no rebuild could take it back. Now a GUI change there lasts until the next
  rebuild, like everything else.

### Verifying

```bash
noctalia config validate <file|dir>    # TOML syntax + unknown keys + bad values
noctalia config export merged          # user config as noctalia actually merged it
noctalia config export full            # same, including every built-in default
noctalia msg dpms-off; sleep 5; noctalia msg dpms-on   # prove the DPMS path by hand
```

`config validate` takes a **path**. The merged result is the live file, so check
it after a switch:

```bash
noctalia config validate ~/.local/state/noctalia/settings.toml
```

(The rendered lock itself is the `*-noctalia-settings-lock.toml` store path named
in `home.activation.noctaliaSettingsLock.data`, if it needs checking on its own.)

No re-login needed after a rebuild — the lock activation ends with
`noctalia msg config-reload`. (Contrast niri, whose config is baked into the wrapper.)

## Bar Configuration

**The bar is locked** — edit `lockedSettings.bar.main` in `Modules/Desktop/noctalia.nix` and rebuild. GUI changes to the bar survive only until the next rebuild.

### Visual settings (TOML — `settings.toml`, i.e. `lockedSettings`)

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
media widget and `noctalia msg media`. `lockedSettings` sets it to `["skwd-music"]`: skwd-daemon
registers an inert `org.mpris.MediaPlayer2.skwd-music` that carries no metadata but claims
`CanControl`/`CanPlay`/`CanGoNext`, so it can win the active-player pick and swallow commands.
The niri and Hyprland media keys dodge the same stub with `playerctl --ignore-player` — see `Claude/niri.md`.

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

The glibc `-` flag suppresses the leading zero. Locked in `lockedSettings.widget.clock`, next to `capsule`/`capsule_opacity`.

**WRONG formats** (all render literally, not as time):
- `"hh:mm a"` — not strftime syntax
- `"h:mm AP"` — not strftime syntax

The `{:%H:%M}` C++ chrono style also works (noctalia strips `{:` and `}` then passes to strftime).

## Color Theming

**skwd generates, noctalia fans out** (Sisyphus since 2026-09-15; Kit-Kat runs the same module). skwd-iris is the only palette generator; noctalia consumes its palette and pushes it to every template it has enabled.

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

`theme.templates` in `lockedSettings`:

| | |
|---|---|
| `builtin_ids` | **empty on purpose.** 20 available; the kitty / starship / btop ones write a theme file then run an `apply.sh` that appends an include to the app's main config — but `kitty.conf`, `starship.toml` and `btop.conf` are read-only Nix store symlinks here, so the append cannot land. btop is already covered by skwd's own integration, which renders the `Modules/Shell/btop.nix` mapping into the `dots` theme `btop.conf` actually selects. |
| `community_ids` | **empty too.** The `discord` community template was enabled on 2026-09-15 and pulled the same day: a full opaque redesign layered under Vesktop's transparency quickCss made Discord glitch. Discord gets a colours-only file from skwd instead (`Modules/Apps/discord.nix`). Community templates are fetched from git at runtime into `~/.local/state/noctalia/community-templates` (same trust model as plugin sources; not pinned by the flake). |

**The `spicetify` and `steam` community templates do not fit this host.** spicetify's targets `Themes/Comfy/` + `Themes/Colorful/` and shells out to `spicetify apply` (which fights spicetify-nix); this host uses the `text` theme. steam's targets the SFP `Material-Theme` skin; this host uses Millennium + Zehn. Both stay on their own skwd integrations — see `Claude/steam.md` and `Claude/spicetify.md`.

Noctalia re-renders a template only when the content changes (it content-hashes into `.noctalia-cache.json`), so an unchanged mtime after `color-scheme-set` means "already current", not "failed".

---

### `noctalia-sync-wallpaper` — retired

The older wiring was a `noctalia-sync-wallpaper` script registered as a skwd
`postProcessing` hook. With `[theme] source = "wallpaper"`, noctalia generates
its palette from its **own** internal wallpaper path (`[wallpaper.last]`), so the
script took the new path as `%path%`, ran `noctalia msg wallpaper-set <path>`,
swapped a `swaybg` overview backdrop, then ran `noctalia msg templates-apply`.

Sisyphus deleted it on 2026-09-15. It lived on in the v1 module
(`Modules/skwd-wall.nix`) for Odysseus until that host and the v1 module were
both removed; nothing in the repo now uses it, `postProcessing`, or swaybg.
Each of its three jobs disappeared in turn:

| call | why it went |
|---|---|
| `templates-apply` | wrong hook. `postProcessing` fires *before* the integrations render, so it pushed the previous palette. Moved to `noctalia-apply-palette`, an integration **reload**, which runs after its own file is written. |
| `wallpaper-set` | vestigial under `theme.source = "custom"` (palette comes from skwd) and `[wallpaper] enabled = false` (noctalia paints nothing). Also caused a **visible flicker** — it repainted with the old palette, then `color-scheme-set` repainted with the new one. Reported as the bar "taking on the old colour then changing". |
| swaybg swap | skwd v2 serves the overview backdrop natively via `skwd-paper-backdrop`. |

**Diagnostic note:** counting `settings.toml` mtime changes *under*counts — `wallpaper-set` and `color-scheme-set` both write it, ~150 ms apart, and coalesce under typical polling. To prove `wallpaper-set` is running, check whether `[wallpaper.default] path` tracks the swaps.

### Wallpaper path: take `%path%`, never parse `skwd status`

**The cache file is not a valid source inside a wallpaper-change hook.** skwd writes `~/.cache/skwd-wall/last-wallpaper.json` *after* running its hooks, so reading it there yields the **previous** wallpaper — which silently put the overview backdrop and noctalia's whole palette one swap behind until 2026-08-16. The path arrives as `%path%` from the `postProcessing` hook instead; `integrations[].reload` commands get no arguments at all, which is why this script no longer lives there. Full measurement in `Claude/skwd-wall.md`.

`~/.cache/skwd-wall/last-wallpaper.json` (`{"path":"/abs/path.jpg","type":"static"}`, v1's cache) was correct at rest — it was what `wallpaper-restore` read at login (now deleted).

**Do not re-derive it from `skwd status`.** That field is `null` on a fresh session and carries no directory component. A `grep`/`sed` version of this script shipped briefly and mis-parsed the unquoted `null` — sed's pattern didn't match, so it passed the line through and `$WALL` became the literal string `"current_wallpaper": null,`, which then passed the `-n` guard and launched swaybg against a nonexistent path. Use `jq -r '.path // empty'`, which is null-safe.

### swaybg backdrop — gone

Retired on Sisyphus 2026-09-15 along with `wallpaper-restore` and the `^wallpaper$` layer rule; skwd v2 serves a native `skwd-paper-backdrop` surface with blur/dim/theming instead. See `Claude/skwd-wall.md` and `Claude/niri.md`. (If swaybg ever comes back: match it with `pgrep -f 'swaybg -m fill -i'`, not `pgrep -x swaybg` — nixpkgs wraps it, so its `comm` is `.swaybg-wrapped`.)

### Why `home.packages`, and why store paths

The skwd daemon runs reload commands with a trimmed PATH covering `/etc/profiles/per-user/$USER/bin` and `/run/current-system/sw/bin` (so `noctalia` and the `home.packages` scripts resolve), but `pkgs.writeShellScriptBin` sets no PATH of its own — so anything less common (`jq`, `pgrep`, `ps`, `sleep`, `tr`) must be referenced by full store path. Scripts in `~/.local/bin` are not on PATH at all (exit 127); use `home.packages` so the script itself is found, as with `spotify-apply-colors`.

**On v2 that PATH is ours, not upstream's.** NixOS renders `systemd.user.services.<n>.path` as `Environment=PATH=…`, which **replaces** the inherited PATH — upstream's module lists only its own renderer packages, which would drop the user profile entirely and make every reload exit 127. `Modules/Desktop/skwd.nix` re-adds both dirs. See `Claude/skwd-wall.md`.

## Desktop Clock Plugin — removed

**The plugin's files were deleted** (`Resources/Noctalia-Plugins/desktop-clock/` is gone); what follows describes what it was. The Anurati font it used is still packaged (below) and installed via `home.packages`.

It lived at `Resources/Noctalia-Plugins/desktop-clock/`:
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
anuratiFont = ../../Resources/Fonts/Anurati-Regular.otf;

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
