# SKWD Wallpaper Selector

**One version: v2 (Rust)**, on Sisyphus (niri) and Elektra (Hyprland), from
`Modules/Desktop/skwd.nix`. Config `~/.config/skwd-wall-v2/config.json`, cache
`~/.cache/skwd-wall-v2/`, daemon `skwd-walld.service`, launched as
`skwd-wall-v2` (Mod+W on both machines).

v1 (QuickShell, `Modules/skwd-wall.nix`, the `skwd-wall` flake input) was retired
on 2026-10-03 together with the old KDE Elektra profile and Odysseus, the last hosts that used it —
see the short [v1 section](#v1-quickshell--retired-2026-10-03) at the end for what
is worth remembering from it. Its `~/.config/skwd-wall/` and `~/.cache/skwd-wall/`
are not read by v2 and can be deleted wherever they are left over.

---

# v2 (Rust) — Sisyphus, Elektra

**Flake input:** `skwd-wall-v2` → `github:liixini/skwd-wall/nix`
**Module:** `Modules/Desktop/skwd.nix`

Upstream ships official NixOS support on the `nix` branch. `Modules/Desktop/skwd.nix`
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

If v1 is ever re-added: `liixini/skwd-wall`'s **default branch is `v2`**, so a
bare `github:liixini/skwd-wall` resolves to the v2 flake. v1 had to be pinned to
an explicit rev, and because v1's flake ships no `flake.lock`, its `quickshell`
and `skwd-daemon` inputs float and get locked by *us* — diff `flake.lock` after
touching it.

## What the migration deleted

Gone from `Modules/Desktop/skwd.nix` — do not reintroduce:

- the four `rustPlatform.buildRustPackage` derivations and their `postUnpack`
  copies (v2's crates resolve each other by *relative path*, which is why the
  source build needed them)
- `cargoLock.outputHashes` for `iced_layershell` / `iced_wgpu`
- the `--add-rpath` `postFixup`s for Vulkan/GL/Wayland `dlopen`
- the `/bin/true` and `#!/bin/sh` test patches, and `dontUseCargoParallelTests`
- `perSystem.packages.skwd-wall-v2`

**`paths.paperBin` / `paperStillBin` / `paperVkBin` were also dropped** — the
activation script `del`ed them on every rebuild until 2026-10-03, when the
one-off migration was removed (every machine was past it). They pinned the renderers to our own build's
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
"swaybg retired" below. Elektra is on Hyprland: no niri overview, so no backdrop
surface either (see below).

**Do NOT apply the layer-rule the v2 README gives for Niri.** It says to put
`place-within-backdrop true` on `^skwd-wall-vk$`, which is the *one-tool* setup:
the wallpaper itself becomes the backdrop and only renders in the overview.
That is the exact refactor evaluated and declined on 2026-08-02 — it costs the
workspace-switch slide and leaves ~0.4s of black at login.

### swaybg retired (2026-09-15)

skwd now serves the overview backdrop natively on Sisyphus. **Three moving parts
were deleted:**

| deleted | was in |
|---|---|
| `pkgs.swaybg` | `Modules/Desktop/noctalia.nix` |
| `wallpaper-restore` script + its `spawn-at-startup` entry | `Modules/Desktop/niri.nix` |
| the whole `noctalia-sync-wallpaper` script + skwd's `postProcessing` entry | `Modules/Desktop/noctalia.nix`, `Modules/Desktop/skwd.nix` |

plus the `^wallpaper$` layer-rule, replaced by `^skwd-paper-backdrop$`.

`noctalia-sync-wallpaper` ended up with nothing left to do: its `templates-apply`
moved to `noctalia-apply-palette`, its `wallpaper-set` became vestigial under
`theme.source = "custom"`, and the swaybg swap was this. **Nothing on Sisyphus
uses `postProcessing` any more** — the sole remaining hook is an
`integrations[].reload` that takes no arguments, so the `%path%` machinery is
gone too.

Nix pins `niri.overviewBackdrop` and `niri.backdropFollowWallpaper` to `true`
on niri hosts (the jq program in `Modules/Desktop/skwd.nix`, gated on
`programs.niri.enable`). That is deliberate and unlike the other skwd settings,
which are left to the UI: with swaybg deleted, a fresh install or an accidental
UI toggle would otherwise leave **no backdrop at all**. The look knobs
(`overviewBackdropBlurEnabled`, `overviewBackdropBlur`, `backdropDim`,
`backdropTheme`) are *not* pinned — tune those freely.

Everywhere else — Elektra — it forces `niri.overviewBackdrop = false`: there is
no niri overview and no `place-within-backdrop` rule, so a backdrop surface could
only paint over the wallpaper. (Until 2026-10-03 the module forced it **on** for
every host, so Elektra's config.json had it on.)

> The script and `pkgs.swaybg` lived on for a while in `Modules/skwd-wall.nix`
> (the v1 module), because Odysseus still registered it as its postProcessing
> hook. Both went with v1 on 2026-10-03.

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

`Modules/Desktop/niri.nix` now carries the paired rule permanently:

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

- the integrations below, upserted by name (hand-edits survive, rebuilds
  cannot stack duplicates) — or deleted by name where a host does not want one
- the `niri.*` backdrop keys (above)
- taste defaults (`theme.*`, `transition.shader`, `postProcessOnRestore`, …),
  written with a `setdefault` only when absent, so the settings UI still wins

The seed and every Nix-owned template are `pkgs.writeText` files `install`ed from
the store (they used to be `cat <<EOF` heredocs inside the activation script).
`postProcessing` is left alone and empty — see "swaybg retired" above.

**`integrations`, `postProcessOnRestore` and `matugen.*` kept the same shape as
v1**, so the whole colour pipeline carried over unchanged:

| name | template | output | reload |
|------|----------|--------|--------|
| `noctalia` | `noctalia-palette.json` | `~/.config/noctalia/palettes/skwd-wall.json` | `noctalia-apply-palette` |
| `spicetify` | `spicetify-text.ini` | `~/.config/spicetify/Themes/text/color.ini` | *(none)* |
| `spicetify-live` | `spicetify-colors.json` | `~/.config/spicetify/matugen-colors.json` | `spotify-apply-colors` |
| `btop` | `btop-theme.theme` | `~/.config/btop/themes/dots.theme` | `btop-reload-theme` |
| `steam` | `steam-quick.css` | `~/.config/millennium/quick.css` | *(none)* — only where `my.steam.millennium` (Sisyphus); deleted elsewhere |
| `discord` | `discord-colors.css` | `~/.config/vesktop/themes/matugen.theme.css` | *(none — Vencord hot-reloads)* |

The two `spicetify*` rows exist only while `my.spicetify.theme` is `null` (the
local Text theme — Sisyphus); a host on an upstream theme (Elektra's Sleek) has
them deleted. Same for `steam` and Millennium: Elektra runs plain Steam, so it
has no `steam` integration.

### GTK apps are deliberately NOT in this pipeline

Wiring Thunar to the wallpaper palette (adw-gtk3-dark + Papirus + matugen
`colors.css`) was built on 2026-09-25 and **rejected on taste** — it was ripped
back out the same day. Thunar keeps its stock GTK look; its transparency comes
from the niri window-rule in `Modules/Desktop/niri.nix`, not from CSS. Don't
re-propose gtk3/gtk4 integrations without new information.

### ⚠️ Discord: colours-only, never a full theme

The `discord` integration renders **nothing but custom properties on `:root`** —
no selectors, no layout. `quickCss.css` (`Modules/Apps/discord.nix`) consumes them via
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
after. That is all `noctalia-apply-palette` (in `Modules/Desktop/noctalia.nix`) does.

**It is an `integrations[].reload`, not a `postProcessing` hook** — the opposite
of `noctalia-sync-wallpaper`. postProcessing fires *before* the templates render,
so putting the colour fan-out there pushes the previous palette. A reload takes
no arguments, which is fine here because `color-scheme-set` needs no wallpaper
path, and it is the only hook guaranteed to run after its own file is on disk.

**No apostrophes in the jq program** in `Modules/Desktop/skwd.nix` — it is passed as a
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

Both blocks come from one Nix function (`paletteFor "dark"` / `paletteFor "light"`)
serialised with `builtins.toJSON`, so the file is a single line with sorted keys —
same JSON as the hand-written heredoc it replaced, checked with `jq -S`.

The v1 built-in `skwd-wall` integration (`quickshell-colors.json` → `colors.json`)
is **not** carried over — v2's picker is iced/Vulkan, not QuickShell, and themes
itself through `theme.nativeTemplates`. Upstream's shipped templates are seeded
into the user template dir only where absent, so edits stick; the templates Nix
owns (btop, steam, discord, noctalia-palette, the two spicetify ones) are
refreshed every rebuild.

### ⚠️ The user template dir is `matugen/templates`, with no `data/`

```
~/.config/skwd-wall-v2/matugen/templates/          ← the daemon reads THIS
<store>/share/skwd-wall-v2/data/matugen/templates/ ← package layout, has data/
```

The `data/` component exists **only inside the package**. The daemon's own
seeder writes to `~/.config/skwd-wall-v2/matugen/templates` and resolves
`integrations[].template` against it.

`Modules/Desktop/skwd.nix` wrote to `~/.config/skwd-wall-v2/data/matugen/templates/`
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

`Modules/Desktop/skwd.nix` overrides exactly two things on upstream's unit:

- **`path` += the user profile.** NixOS renders `path` as `Environment=PATH=…`,
  which **replaces** the inherited PATH rather than extending it — so upstream
  listing `paper` and `lens` there drops the user profile off the daemon's PATH.
  Integration reload commands (`noctalia-apply-palette`, `spotify-apply-colors`,
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

# v1 (QuickShell) — retired 2026-10-03

`Modules/skwd-wall.nix` and the `skwd-wall` input were deleted along with the old KDE Elektra profile
and Odysseus. Lessons from it that are still worth having:

- **The one-wallpaper-behind bug.** v1 wrote `~/.cache/skwd-wall/last-wallpaper.json`
  *after* running its hooks, so anything that read it from inside a hook acted on
  the **previous** wallpaper (measured 2026-08-16: desktop on `…-8.jpg`, overview
  backdrop and noctalia's palette still on `…-7.jpg` — it read as "the background
  is randomly buggy"). `integrations[].reload` commands get **no arguments**; only
  `postProcessing` entries get placeholders (`%path%`, `%thumb%`, `%type%`,
  `%name%`). Nothing on v2 needs the wallpaper path any more.
- **`skwd status` is not a wallpaper source** — `current_wallpaper` is `null` on a
  fresh session and a bare filename otherwise.
- **Reload commands must be on a Nix profile PATH**, not `~/.local/bin` (`exit
  status: 127`). Still true on v2 — see Daemon above.
- **Gray screen on a video wallpaper:** the renderer's tiny ffmpeg probe window
  (`probesize=65536`) mis-probes mp4s whose metadata sits at the end, aborts, and
  respawn-loops. Diagnose with
  `ffprobe -v error -probesize 65536 -analyzeduration 500000 -select_streams v:0 -show_entries stream=pix_fmt <file>`
  (`unknown` = affected); fix losslessly with
  `ffmpeg -i in.mp4 -c copy -movflags +faststart out.mp4`. Not re-checked against
  v2's `skwd-paper-v2`.
- **KDE needed a `qdbus6` shim** — NixOS ships Qt6's tool as plain `qdbus`. Only
  relevant if a Plasma host ever comes back.
