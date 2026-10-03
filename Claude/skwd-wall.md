# SKWD Wallpaper Selector

**Two versions are live in this repo right now.**

| | v2 (Rust) | v1 (QuickShell) |
|---|---|---|
| Module | `Modules/Skwd.nix` (`nixosModules.skwd`) | `Modules/skwd-wall.nix` (`nixosModules.skwd-wall`) |
| Hosts | Sisyphus | Elektra, Odysseus |
| Config | `~/.config/skwd-wall-v2/config.json` | `~/.config/skwd-wall/config.json` |
| Cache | `~/.cache/skwd-wall-v2/` | `~/.cache/skwd-wall/` |
| Daemon | `skwd-walld.service` | `skwd-daemon.service` |
| Launch | `skwd-wall-v2` | `skwd wall toggle` |

The paths do not overlap, so the two coexist without touching each other's
state. Upstream's own unit declares `Conflicts=skwd-daemon.service`, so only
one daemon can ever be running.

---

# v2 (Rust) — Sisyphus

**Flake input:** `skwd-wall-v2` → `github:liixini/skwd-wall/nix`
**Module:** `Modules/Skwd.nix`

Upstream ships official NixOS support on the `nix` branch. `Modules/Skwd.nix`
imports its `nixosModules.default` and adds **only** the colour-pipeline wiring
(matugen integrations + templates). It builds nothing.

## What upstream's flake gives you

`nixosModules.default` exposes `services.skwd-deck.enable`, which installs the
suite system-wide, exports `SKWD_LENS_HOME`, and defines the `skwd-walld` user
unit. Packages:

| Attr | Binaries |
|---|---|
| `default` (suite) | everything below, symlinkJoin'd + wrapped |
| `deck` | `skwd-walld`, `skwd-helm`, `skwd-wall-scan`, `skwd-wall-effects` |
| `paper` | `skwd-paper-v2`, `skwd-wall-still`, `skwd-wall-vk` |
| `lens` | `skwd-lens` |
| `model` | SigLIP 2 semantic model pack (incl. `libonnxruntime.so`) |
| `plasma` | `skwd-paper-plasma` (KDE only — not used here) |

**These are prebuilt release binaries**, `autoPatchelf`'d — not built from
source. A rebuild is seconds, not the ~20 min the hand-rolled Rust build took.

### Never add `inputs.nixpkgs.follows` to this input

Upstream pins its own nixpkgs, and the binaries are patchelf'd against it.
Matching that pin is what makes our derivations **hash-identical to the store
paths upstream publishes in `channel.json`** — verified: `nix build .#…` lands
on exactly the paths listed there. Override the pin and every build becomes a
local rebuild instead of a cache hit. (Same rule as the `millennium` input, for
a different underlying reason.)

## Updating

```bash
nix flake update skwd-wall-v2
```

One input, no coordination. (Pre-2026-09-14 this was four `flake = false`
source trees — `skwd-wall-src` / `skwd-deck-src` / `skwd-lens-src` /
`skwd-paper-src` — that had to be updated together. All four are gone.)

## ⚠️ The v1 input is pinned to a rev on purpose

`liixini/skwd-wall`'s **default branch is now `v2`**, so a bare
`github:liixini/skwd-wall` resolves to the v2 flake. `skwd-wall` (v1, used by
Elektra and Odysseus) is therefore pinned to an explicit rev — without it a
routine `nix flake update` silently swaps v1 out from under two hosts.

Related trap: **v1's flake ships no `flake.lock`**, so its `quickshell` and
`skwd-daemon` inputs float and get locked by *us*. Any change that alters the
`skwd-wall` node's identity makes Nix re-lock them to today's HEAD. If you touch
that input, diff `flake.lock` for `quickshell` / `skwd-daemon` / `nixpkgs_5..7`
and restore them unless you actually meant to bump v1.

## What the migration deleted

Gone from `Modules/Skwd.nix` — do not reintroduce:

- the four `rustPlatform.buildRustPackage` derivations and their `postUnpack`
  copies (v2's crates resolve each other by *relative path*, which is why the
  source build needed them)
- `cargoLock.outputHashes` for `iced_layershell` / `iced_wgpu`
- the `--add-rpath` `postFixup`s for Vulkan/GL/Wayland `dlopen`
- the `/bin/true` and `#!/bin/sh` test patches, and `dontUseCargoParallelTests`
- `perSystem.packages.skwd-wall-v2`

**`paths.paperBin` / `paperStillBin` / `paperVkBin` were also dropped** — the
activation script now `del`s them. They pinned the renderers to our own build's
store paths; upstream puts its renderers on the daemon's `PATH` instead, and the
binary was renamed `skwd-paper` → **`skwd-paper-v2`**. The keys are still live
in beta.13, so they had to be actively deleted, not just left alone: stale
values keep the daemon exec-ing renderers out of a garbage-collected store path,
and the failure mode is *silent* — daemon healthy, wallpapers never paint.

## How the multipicker / per-display targeting works

Observed live on beta.13 via `skwd-helm ui state` (2026-09-14).

Every apply carries a **target set**. The picker's default is the wildcard:

```json
"displays": { "mode": "studio", "monitors": ["DP-2","HDMI-A-1"],
              "selected": [], "targets": ["*"] }
```

`targets: ["*"]` is why both monitors normally show the same wallpaper. The
multipicker is the UI that replaces `*` with an explicit list — it lives in the
**studio / effects workbench overlay** (`skwd-helm ui open effects`), where
`selected` is the tick list. `skwd-helm apply -o <OUT>` is the CLI equivalent.

The daemon then reconciles per output, leaving non-targets alone:

```
apply_output: target=DP-2 type=static path=… monitors=["DP-2","HDMI-A-1"]
reconcile DP-2:     static … (spawn)
reconcile HDMI-A-1: static … (unchanged, keep)
```

### ⚠️ A locked output swallows applies and still reports success

`display.outputLocks` (Settings → Wallpapers and displays → **Lock**) is what
`settings-displays-lock-desc` means by "only through the multipicker":

```json
"display": { "outputLocks": { "DP-2": false, "HDMI-A-1": true } }
```

A locked output is skipped by schedules, random rotation **and by an explicit
`-o` apply**:

```
skwd-helm apply <path> -o HDMI-A-1   →  prints "applied: <path>", exit 0
daemon log                           →  apply: skipped locked output HDMI-A-1
```

**The CLI reports success and exit 0 either way.** If an output refuses to
change, check `display.outputLocks` in `config.json` before anything else —
`skwd-helm` gives you no signal at all, and only
`~/.cache/skwd-wall-v2/skwd-walld.log` records the skip. There is no helm verb
to unlock; clear the key in `config.json` or toggle it in the settings UI.

Note the theme designer (`ui open theme`) applies recoloured variants **as you
browse**, writing `~/Pictures/Wallpapers/effects/<name>-theme-<palette>.<ext>`
and switching outputs to them. It is not a preview-only panel.

## Layer-shell namespaces

v2 uses three, and **none of them is `wallpaper`**:

| namespace | surface |
|---|---|
| `skwd-paper` | still-image renderer (`skwd-wall-still`) |
| `skwd-wall-vk` | Vulkan video / Wallpaper Engine renderer |
| `skwd-paper-backdrop` | native niri overview backdrop |

**Sisyphus uses `skwd-paper-backdrop` for the overview backdrop since 2026-09-15.**
The `^wallpaper$` layer-rule and the swaybg instance behind it are gone — see
"swaybg retired" below. Elektra and Odysseus (v1) are unaffected.

**Do NOT apply the layer-rule the v2 README gives for Niri.** It says to put
`place-within-backdrop true` on `^skwd-wall-vk$`, which is the *one-tool* setup:
the wallpaper itself becomes the backdrop and only renders in the overview.
That is the exact refactor evaluated and declined on 2026-08-02 — it costs the
workspace-switch slide and leaves ~0.4s of black at login. See
`memory/niri-wallpaper-two-tool-setup.md`.

### swaybg retired (2026-09-15)

skwd now serves the overview backdrop natively on Sisyphus. **Three moving parts
were deleted:**

| deleted | was in |
|---|---|
| `pkgs.swaybg` | `Modules/noctalia.nix` |
| `wallpaper-restore` script + its `spawn-at-startup` entry | `Modules/Desktops/niri.nix` |
| the whole `noctalia-sync-wallpaper` script + skwd's `postProcessing` entry | `Modules/noctalia.nix`, `Modules/Skwd.nix` |

plus the `^wallpaper$` layer-rule, replaced by `^skwd-paper-backdrop$`.

`noctalia-sync-wallpaper` ended up with nothing left to do: its `templates-apply`
moved to `noctalia-apply-palette`, its `wallpaper-set` became vestigial under
`theme.source = "custom"`, and the swaybg swap was this. **Nothing on Sisyphus
uses `postProcessing` any more** — the sole remaining hook is an
`integrations[].reload` that takes no arguments, so the `%path%` machinery is
gone too.

Nix pins `niri.overviewBackdrop` and `niri.backdropFollowWallpaper` to `true`
(the jq upsert in `Modules/Skwd.nix`). That is deliberate and unlike the other
skwd settings, which are left to the UI: with swaybg deleted, a fresh install or
an accidental UI toggle would otherwise leave **no backdrop at all**. The look
knobs (`overviewBackdropBlurEnabled`, `overviewBackdropBlur`, `backdropDim`,
`backdropTheme`) are *not* pinned — tune those freely.

> ⚠️ **The script moved, it did not vanish.** `Modules/noctalia.nix` is shared
> with Odysseus, which is still on v1 and still registers
> `noctalia-sync-wallpaper %path%` as its postProcessing hook. The script and
> `pkgs.swaybg` therefore moved into `Modules/skwd-wall.nix` (the v1 module), so
> the script now lives beside the code that registers it. Deleting it outright
> would have broken Odysseus silently — v1 has no `noctalia-apply-palette` and no
> native backdrop, so noctalia there still needs pointing at the image.

**Verify after a re-login** (the rule only loads when niri restarts):

```bash
niri msg layers      # skwd-paper-backdrop must be listed on each output
```

If it is listed and the desktop is blurry, the rule did not load — see the
layer-rule warning above.

### ⚠️ `niri.overviewBackdrop = true` without the layer rule blurs the desktop

Turning that key on (settings UI, or `config.json`) spawns the
`skwd-paper-backdrop` surface. **With no matching niri layer-rule it is just
another background-layer client** — and it is created *after* `skwd-paper`, so it
paints on top of the real wallpaper and the entire desktop goes blurry.

Seen 2026-09-15: `--blur 20` against `Astronaut_Watercolor_219-7.jpg`, which was
not even the current wallpaper, because `backdropFollowWallpaper` defaults to
`false`. Three surfaces were stacked on DP-2 — `skwd-paper` (sharp), then
`skwd-paper-backdrop` (blurred), then `wallpaper` (swaybg, correctly lifted into
the backdrop by the existing `^wallpaper$` rule).

`Modules/Desktops/niri.nix` now carries the paired rule permanently:

```kdl
layer-rule {
    match namespace="^skwd-paper-backdrop$"
    place-within-backdrop true
}
```

It matches nothing while the key is `false`, so it is safe to keep regardless and
it stops the settings UI from being able to break the desktop with one toggle.

Diagnose with `niri msg layers` — if `skwd-paper-backdrop` is listed under the
Background layer *and* the desktop is blurry, the rule is missing or niri has not
reloaded it. Immediate relief without a rebuild:

```bash
jq '.niri.overviewBackdrop = false' ~/.config/skwd-wall-v2/config.json > /tmp/c \
  && mv /tmp/c ~/.config/skwd-wall-v2/config.json
systemctl --user restart skwd-walld
```

If you re-enable it, set `backdropFollowWallpaper = true` too, otherwise the
backdrop stays pinned to whatever single image `niri.backdrop` names.

## Config

`~/.config/skwd-wall-v2/config.json`. **Nix does not seed a full config** the way
the v1 module did: v2's schema is far larger and it normalises its own defaults
on first run, so a hand-written seed would go stale and fight the settings UI.
The activation script writes a minimal file only if one is missing, then patches
in just the parts Nix owns:

- the five integrations below, upserted by name (hand-edits survive, rebuilds
  cannot stack duplicates)
- `postProcessing` + `postProcessOnRestore`
- a `del` of the three obsolete `paths.*Bin` pins (see above)

**`integrations`, `postProcessing`, `postProcessOnRestore` and `matugen.*` kept
the same shape as v1**, so the whole colour pipeline carried over unchanged:

| name | template | output | reload |
|------|----------|--------|--------|
| `noctalia` | `noctalia-palette.json` | `~/.config/noctalia/palettes/skwd-wall.json` | `noctalia-apply-palette` |
| `spicetify` | `spicetify-text.ini` | `~/.config/spicetify/Themes/text/color.ini` | *(none)* |
| `spicetify-live` | `spicetify-colors.json` | `~/.config/spicetify/matugen-colors.json` | `spotify-apply-colors` |
| `btop` | `btop-theme.theme` | `~/.config/btop/themes/dots.theme` | `btop-reload-theme` |
| `steam` | `steam-quick.css` | `~/.config/millennium/quick.css` | *(none)* |
| `discord` | `discord-colors.css` | `~/.config/vesktop/themes/matugen.theme.css` | *(none — Vencord hot-reloads)* |

### GTK apps are deliberately NOT in this pipeline

Wiring Thunar to the wallpaper palette (adw-gtk3-dark + Papirus + matugen
`colors.css`) was built on 2026-09-25 and **rejected on taste** — it was ripped
back out the same day. Thunar keeps its stock GTK look; its transparency comes
from the niri window-rule in `Modules/Desktops/niri.nix`, not from CSS. Don't
re-propose gtk3/gtk4 integrations without new information.

### ⚠️ Discord: colours-only, never a full theme

The `discord` integration renders **nothing but custom properties on `:root`** —
no selectors, no layout. `quickCss.css` (`Modules/discord.nix`) consumes them via
`rgba(var(--skwd-surface-rgb, 0, 0, 0), 0.4)`, with fallbacks so Discord degrades
to its old flat black if the file is missing.

That constraint exists because **Vesktop runs `transparent = true` here**. On
2026-09-15 noctalia's community `discord` template was enabled instead — a 20 KB
full redesign with opaque panels, gaps and borders — and loading it alongside a
quickCss that forces transparency with `!important` made Discord visibly glitch.

It had actually been conflicting since Sep 10; it only *became* visible once the
palette started updating again, because until then the theme file was frozen and
the conflict was static. **A frozen wrong thing looks like a working thing.**

Do not point this integration at a complete Discord theme, and do not re-enable
`community_ids = ["discord"]` in noctalia — see `Claude/noctalia.md`.

### ⚠️ The noctalia integration must write `palettes/`, not `colors.json`

**skwd-iris is the only palette generator on Sisyphus; noctalia is the fan-out
hub.** noctalia reads whatever `theme.custom_palette` names under
`~/.config/noctalia/palettes/`, and reads `colors.json` **never**.

From the v2 migration until **2026-09-15** the integration wrote
`~/.config/noctalia/colors.json`, so:

- skwd refreshed `colors.json` on every swap — a file nothing reads
- `palettes/skwd-wall.json`, the file noctalia *does* read, had not changed in
  five days
- therefore noctalia itself **and everything downstream of it** — the bar, the
  Discord theme, noctalia's own btop theme — were frozen on a stale palette

It hid the same way the template-dir bug did: every file existed and looked
themed, it just never followed the wallpaper.

**`templates-apply` is not the reload.** It re-renders from the palette noctalia
already holds in memory, so when only the file on disk changed it prints `ok` and
writes nothing at all. The command that forces a re-read is:

```bash
noctalia msg color-scheme-set custom skwd-wall
```

Re-selecting the already-selected palette is what triggers it, and it fans out to
noctalia's UI plus every enabled template on its own — no `templates-apply`
after. That is all `noctalia-apply-palette` (in `Modules/noctalia.nix`) does.

**It is an `integrations[].reload`, not a `postProcessing` hook** — the opposite
of `noctalia-sync-wallpaper`. postProcessing fires *before* the templates render,
so putting the colour fan-out there pushes the previous palette. A reload takes
no arguments, which is fine here because `color-scheme-set` needs no wallpaper
path, and it is the only hook guaranteed to run after its own file is on disk.

**No apostrophes in the jq program** in `Modules/Skwd.nix` — it is passed as a
single-quoted shell argument, so one apostrophe in a comment ends the string and
the activation script dies with `syntax error near unexpected token )`.

### Palette format

`noctalia-palette.json` emits noctalia's full schema: a `dark` and a `light`
block, each with the `mXxx` roles plus a `terminal` sub-object. skwd-iris
resolves `.dark` / `.light` independently of `matugen.mode`, and also exposes
`ansi_*` / `ansi_*_bright` / `source_color` (verified 2026-09-15), so the
terminal block uses real ANSI colours instead of deriving fake ones from Material
roles the way the old hand-built palette did.

Surfaces follow the wallpaper. They were previously pinned to flat greys
(`#0a0a0a` / `#1a1a1a` / `#333333`), which made the bar the one thing that
ignored the palette entirely.

The v1 built-in `skwd-wall` integration (`quickshell-colors.json` → `colors.json`)
is **not** carried over — v2's picker is iced/Vulkan, not QuickShell, and themes
itself through `theme.nativeTemplates`. Upstream's shipped templates are seeded
into the user template dir only where absent, so edits stick; the btop and steam
templates Nix owns are refreshed every rebuild.

### ⚠️ The user template dir is `matugen/templates`, with no `data/`

```
~/.config/skwd-wall-v2/matugen/templates/          ← the daemon reads THIS
<store>/share/skwd-wall-v2/data/matugen/templates/ ← package layout, has data/
```

The `data/` component exists **only inside the package**. The daemon's own
seeder writes to `~/.config/skwd-wall-v2/matugen/templates` and resolves
`integrations[].template` against it.

`Modules/Skwd.nix` wrote to `~/.config/skwd-wall-v2/data/matugen/templates/`
from the v2 migration until **2026-09-14**, so **the matugen colour pipeline
never actually ran on v2.** Fixed now, but note how it hid:

- Every integration logged `template not found` and rendered nothing — but to
  `~/.cache/skwd-wall-v2/skwd-walld.log`, which is *not* the journal, so
  `journalctl --user -u skwd-walld` showed nothing. 3,435 warnings had
  accumulated, growing by exactly 5 (one per integration) per apply.
- Every output file still existed and looked right, because btop, Steam,
  spicetify and noctalia all ship a **static Nix fallback** at the same path.
  So the desktop looked themed; it just never followed the wallpaper.

**To check it is actually working**, count warnings across an apply rather than
trusting that the files exist:

```bash
before=$(grep -ac "template not found" ~/.cache/skwd-wall-v2/skwd-walld.log)
skwd-helm apply <some-wallpaper> -o DP-2
grep -ac "template not found" ~/.cache/skwd-wall-v2/skwd-walld.log   # must not grow
ls -l --time-style=+%H:%M:%S ~/.config/btop/themes/dots.theme        # must be now
```

The stale `~/.config/skwd-wall-v2/data/` tree is inert and can be deleted.

## Daemon

`skwd-walld.service` — now a **NixOS-level** user unit from upstream's module at
`/etc/systemd/user/`, not a home-manager one under `~/.config/systemd/user/`.
v2 splits v1's single `skwd-daemon` into a supervisor that spawns a renderer per
output. **The picker is no longer resident**: `skwd-wall-v2` starts in ~150 ms
and exits on close.

`Modules/Skwd.nix` overrides exactly two things on upstream's unit:

- **`path` += the user profile.** NixOS renders `path` as `Environment=PATH=…`,
  which **replaces** the inherited PATH rather than extending it — so upstream
  listing `paper` and `lens` there drops the user profile off the daemon's PATH.
  Integration reload commands (`noctalia-sync-wallpaper`, `spotify-apply-colors`,
  `btop-reload-theme`) are `home.packages`, and without
  `/etc/profiles/per-user/<user>` + `/run/current-system/sw` every reload fails
  with `exit status: 127`.
- **`ExecStart` += `--wait-for-session`.** Upstream's NixOS module omits the
  flag that its *own shipped unit file* passes. Without it the daemon can come
  up before the Wayland socket exists and has to be bounced by
  `Restart=on-failure`.

Note `skwd-walld` has no `--help` (it errors on unknown args) and its flag
strings don't survive `grep` on the binary — `--wait-for-session` was confirmed
by running it, not by grepping. Generally: **verify v2 flags by execution.**

## skwd-lens (semantic search) now works

Previously unverified and expected broken: `skwd-lens` links `ort` with
`load-dynamic` and `dlopen`s `libonnxruntime.so`, which our source build never
provided. Upstream's `model` package ships
`…/share/skwd-lens/models/semantic/runtime/libonnxruntime.so.1.27.0` alongside
the SigLIP 2 weights, and the module exports `SKWD_LENS_HOME` to that directory.
No `ORT_DYLIB_PATH` wrapper needed.

## The colour engine is skwd-iris, not matugen

Resolved 2026-09-15 — the picker themes **itself**, no `theme.nativeTemplates`
wiring needed. v2 ships its own generator and logs it per apply:

```
theme apply: backend=skwd-iris dark=true src=~/.cache/skwd-wall-v2/thumbs/<wall>.webp
```

Controlled by a top-level `theme` object, which is separate from the legacy
`matugen` object carried over from v1:

```json
"theme": { "authority": "skwd", "scheme": "content",
           "style": "natural", "wallpaperProfiles": [] }
```

`matugen` is still installed and still required in `home.packages` — the
integration renderer uses matugen template *syntax* — but the palette itself
comes from skwd-iris. This is why skwd must stay the authority: the picker chrome
always themes itself from skwd-iris, so pointing noctalia at its own generator
(`theme.source = "wallpaper"`) puts two different palettes on one desktop.

`skwd-helm retheme` regenerates and re-runs every integration **without changing
the wallpaper** — the fastest way to test template changes.

## Known unverified on v2
- **Steam Workshop wallpaper import (`features.steam`).** The `skwd-steam`
  binary is no longer in the `deck` package; the daemon references a separate
  `skwd-deck-steamworks` backend, which upstream's flake does not publish (it
  is what `services.skwd-deck.extraPackages` is for). Assume `features.steam` is
  inert until proven otherwise. Unrelated to the `steam` *integration*, which is
  Millennium Quick CSS and does work — see `Claude/steam.md`.

---

# v1 (QuickShell) — Elektra, Odysseus

**Module:** `Modules/skwd-wall.nix`
**Flake input:** `github:liixini/skwd-wall`

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
| `noctalia` | `noctalia-colors.json` | `~/.config/noctalia/colors.json` | *(none — moved to `postProcessing`, see below)* |
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

**Noctalia color note:** Noctalia v5 generates its own Material You colors from its **internal wallpaper path** — it does not use the `colors.json` matugen writes. The `noctalia-sync-wallpaper` script takes the wallpaper path **as its first argument**, calls `noctalia msg wallpaper-set <path>` to point noctalia at the correct wallpaper (so it regenerates the right palette), swaps the swaybg backdrop, then calls `noctalia msg templates-apply` to push the new palette to kitty, niri, gtk, etc.

**The script lives in THIS module (`Modules/skwd-wall.nix`) as of 2026-09-15**, not in `noctalia.nix` where it used to be. It is now a v1-only concern — Sisyphus deleted it when skwd v2 took over both the palette and the overview backdrop — and `noctalia.nix` is shared with Sisyphus, so leaving it there would have meant deleting it out from under Odysseus. Script and registration now sit in one file.

### `postProcessing`, not `integrations[].reload` — the one-wallpaper-behind bug

**skwd writes `~/.cache/skwd-wall/last-wallpaper.json` *after* it runs its hooks.** Anything that reloads by reading that file therefore acts on the **previous** wallpaper, forever one swap behind.

Measured 2026-08-16: swaybg was running against `Astronaut_Watercolor_219-7.jpg`, started `12:27:01`; the cache naming `…-8.jpg` was written `12:27:02`. The desktop (skwd-paper) showed `-8`, the overview backdrop showed `-7`. Because the same stale path was passed to `noctalia msg wallpaper-set`, noctalia's entire Material You palette — and everything `templates-apply` pushes downstream (kitty, niri, gtk) — was one wallpaper behind too. This read as "the background is randomly buggy": each swap looked right on the desktop and wrong in the overview.

**Fix: use skwd's `postProcessing` hook, which substitutes placeholders.** `integrations[].reload` commands are executed with **no arguments**, so an integration reload can only ever read the racy cache. `postProcessing` entries take:

| placeholder | value |
|---|---|
| `%path%` | wallpaper file (or Wallpaper Engine folder) |
| `%thumb%` | always an image |
| `%type%` | `image` / `video` / `we` |
| `%name%` | basename |

Config shape (patched idempotently by the activation script in `Modules/skwd-wall.nix`):

```json
"postProcessing": [ { "command": "noctalia-sync-wallpaper %path%", "type": "all" } ],
"postProcessOnRestore": true
```

`type` filters by wallpaper kind (`all` / `static` / `video` / `we`). `postProcessOnRestore` makes the hook fire on session restore as well — the old reload command ran at login, and without this the palette would only resync on a manual swap.

`noctalia-sync-wallpaper` still falls back to the cache file when invoked with no argument, which is safe **only** for manual invocation (no swap in flight, so the cache is current).

**`skwd status` is not a reliable wallpaper source** — its `current_wallpaper` is `null` on a fresh session and is a bare filename otherwise. Prefer `%path%`; use `~/.cache/skwd-wall/last-wallpaper.json` (`.path`, absolute) with `jq` only outside a wallpaper-change hook.

### ✅ Done on Sisyphus (v2) — still applies to v1 hosts

**Retired on Sisyphus 2026-09-15.** See "swaybg retired" in the v2 section above for what was deleted and how it is wired now; the rest of this section is kept because it still describes **v1 hosts**, which continue to use swaybg.

Neither Elektra nor Odysseus needs this change: Elektra is KDE (no niri overview at all), and Odysseus is Hyprland. The v1 daemon does serve `skwd-paper-backdrop`, so the option exists if Odysseus ever wants it — but `place-within-backdrop` is a **niri** layer-rule, so on Hyprland there is nothing to pair it with.

Sisyphus previously painted the niri overview backdrop with **swaybg**, which cost three moving parts: `pkgs.swaybg` + the `wallpaper-restore` login script (`Modules/Desktops/niri.nix`) + a launch/sleep/kill swap block inside `noctalia-sync-wallpaper`. skwd-wall does this natively.

Verified present in the currently pinned daemon (`skwd-daemon` is a **separate flake input** of `skwd-wall`, locked 2026-07-02): the binary contains `crates/daemon/src/wall/overview_backdrop.rs`, spawns a `skwd-paper-backdrop` layer-shell surface, and writes `overview-backdrop.jpg`. **No flake update is required to try it.**

Config keys (all under a top-level `niri` object in `config.json`; UI is the selector's Niri settings card):

| key | meaning |
|---|---|
| `overviewBackdrop` | serve the backdrop surface at all (**currently `false`**) |
| `overviewBackdropBlurEnabled` / `overviewBackdropBlur` | Gaussian blur toggle + radius (1–200, default 30) |
| `backdropFollowWallpaper` | force the backdrop to track the applied wallpaper |
| `backdropDim` | darken the backdrop, 0–100 |
| `backdropAutoTheme` / `backdropTheme` | recolour the backdrop with a gowall palette |

Paired niri layer rule — replaces the `^wallpaper$` rule in `Modules/Desktops/niri.nix`:

```kdl
layer-rule {
    match namespace="^skwd-paper-backdrop$"
    place-within-backdrop true
}
```

Then delete: `pkgs.swaybg` from `noctalia.nix`, the `wallpaper-restore` script and its `spawn-at-startup` entry, and the swaybg swap block in `noctalia-sync-wallpaper` (the noctalia colour sync itself stays — it is not removable, see `memory/niri-wallpaper-two-tool-setup.md`).

**Verify before deleting anything:** `niri msg layers` must list `skwd-paper-backdrop` under the Background layer on each output. If it does not, the daemon build is not serving it and swaybg must stay.

**This is not the one-tool refactor that was declined on 2026-08-02.** That one put `place-within-backdrop` on the `skwd-paper` namespace itself, which cost the workspace-switch slide and left ~0.4s of black at login. The native backdrop keeps `skwd-paper` on the desktop and adds a *second* surface, so the slide survives — and it is the blurred-backdrop case the niri wiki names as the only real reason to run two wallpaper tools.

## Important Gotchas

- **KDE (Elektra): daemon calls `qdbus6`**, but NixOS ships the Qt6 tool as plain `qdbus`. Without the `qdbus6-shim` (added to `home.packages` when compositor is `kde` in `Modules/skwd-wall.nix`), `apply_kde_static` silently fails at spawn and Plasma keeps its old wallpaper — the daemon log still shows a successful-looking "setting wallpaper via plasmashell evaluateScript" INFO line because it's logged before the call.

- **`matugen` must be in `home.packages`** — it's added in `skwd-wall.nix`. Without it every integration silently fails (skwd-daemon catches the error but swallows it).
- **Reload *and* postProcessing scripts must be nix profile packages, not `~/.local/bin` files.** skwd-daemon runs both with a minimal shell PATH that only contains nix profile packages (`~/.nix-profile/bin`). Scripts in `~/.local/bin` produce `exit status: 127 — command not found`. Use `pkgs.writeShellScriptBin` in `home.packages` (like `noctalia-sync-wallpaper` and `spotify-apply-colors`) so the script is on PATH when the daemon runs it. Symptom in logs: `WARN command failed (exit status: 127): <script-name>`.
- **Zen integrations in config.json break matugen** — their output paths contain literal `\n` which corrupts generated TOML. The activation script strips them on every rebuild. Symptom: `matugen exited with exit status: 1` in `journalctl --user -u skwd-daemon`.
- The activation script patches `config.json` via jq on every rebuild (not just first run), so integrations, reload fields and the `postProcessing` hook stay correct even if edited manually. The postProcessing patch filters out any prior `noctalia-sync-wallpaper` entry before appending, so it is idempotent and will not stack duplicates.
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
