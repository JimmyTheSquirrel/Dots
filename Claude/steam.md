# Steam Theming (Millennium)

**Module:** `Modules/steam.nix`
**Theme source:** `Resources/Steam-Glass-Theme/`
**Flake input:** `github:SteamClientHomebrew/Millennium?dir=packages/nix`
**Used on:** All three desktops (Millennium); the glass effect itself is Niri-only

## The one thing to understand first

**Steam's CEF surface has no alpha channel.** A `background: transparent` rule in
a Millennium theme does *not* show the wallpaper — it reveals Steam's own base
surface underneath. The see-through comes entirely from the Niri window rule:

```kdl
window-rule {
  match app-id="^steam$"
  opacity 0.85
}
```

Same arrangement as Spotify (0.75) and Helium (0.85). So the split of
responsibilities is:

| Layer | Job |
|-------|-----|
| Niri `opacity 0.85` | Makes the window see-through. This is the glass. |
| Millennium theme | Makes Steam *look right at 85%* — flattens the opaque blue-grey panel stack onto one near-black base. |

Chasing transparency in CSS instead of the window rule is a dead end. Don't.

The regex `^steam$` matches the client window only — in-game windows get
`steam_app_<id>`, so games are never faded.

## Millennium

Millennium is a CSS/JS injector for the Steam client. It hooks Steam by
**replacing `libXtst.so.6`**: the bootstrap `.so` re-exports the real libXtst
symbols and spawns Millennium alongside Steam.

`Modules/steam.nix` does this via three `steam.override` knobs:

- `extraLibraries` — Millennium + both openssl ABIs, **merged with** the existing
  `libpulseaudio`/`pipewire` audio fix (see below — don't drop it)
- `extraEnv` — `MILLENNIUM_RUNTIME_PATH`
- `extraProfile` — the two `libXtst.so.6` symlinks

The symlinks live in `extraProfile` (re-run on *every* Steam launch) rather than
a home-manager activation script, because Steam's self-updater rewrites
`ubuntu12_{32,64}` and would clobber a one-shot symlink. This is the
"unavoidable imperative state" case from `CLAUDE.md` — it just self-heals.

**Upstream ships a `millennium-steam` package — we deliberately don't use it.**
It is built against upstream's own pinned nixpkgs, which would pull a second
Steam into the closure and silently drop the audio-library override. The
injection is reproduced against our nixpkgs instead.

**Never add `inputs.nixpkgs.follows` to the millennium input.** Upstream pins an
exact nixpkgs commit because the Bun dependency is a fixed-output derivation
whose hash is sensitive to version drift. Overriding it changes the bun version
and breaks the FOD hash.

Millennium is currently **3.4.0-beta.7** — a beta patching the live Steam
client. If it breaks Steam, roll back the generation.

## Paths (Linux — they are NOT under a common root)

| What | Where |
|------|-------|
| Themes | `~/.steam/steam/millennium/themes/<name>/` (`~/.steam/steam` → `~/.local/share/Steam`) |
| Config | `~/.config/millennium/config.json` |
| Plugins | `~/.local/share/millennium/plugins` |
| Logs | `~/.local/state/millennium/logs` |

Themes hang off the Steam dir (hardcoded `get_steam_path()`), everything else
off XDG. Easy to get wrong.

## Themes

Three are installed; `activeTheme` in `Modules/steam.nix` picks which renders.

| Theme | Source | Role |
|-------|--------|------|
| **SpaceTheme** | `github:SpaceTheme/Steam`, pinned to commit `cbf0213` | **Active.** Dark, modular; the most-downloaded Millennium theme |
| Zehn | `github:yurisuika/Zehn`, pinned to tag `2026.8.9` | Alternative — Windows 10 Fluent Design |
| `dots-glass` | `Resources/Steam-Glass-Theme/` | Minimal fallback, see below |

Switch by editing `activeTheme`, or live in Steam via Millennium → Settings →
Themes (the activation script forces `activeTheme` back on the next rebuild).

**One Quick CSS drives all of them.** The generator emits SpaceTheme's variables
*and* Zehn's, plus a theme-neutral `--dots-accent-rgb` used by our own rules
(window glow, blue overrides). Setting variables an inactive theme doesn't read
is harmless, so switching themes keeps the matugen colours either way.

### Theme options are forced per theme

`conditionsForced` in `Modules/steam.nix` is keyed by theme name, because each
theme names its options differently — a setting forced for Zehn does nothing
under SpaceTheme. Currently forced:

| Theme | Option | Value | Why |
|-------|--------|-------|-----|
| SpaceTheme | `What's New` | `Hide` | default `Compact` still shows it |
| SpaceTheme | `Always show sidebar` | `no` | keeps the game list out of Store/Community |
| SpaceTheme | `Sidebar on right` | `no` | game list on the left |
| SpaceTheme | `Scrollbars` | `yes` | **reads backwards** — see below |
| Zehn | `Color Mode` | `Dark` | default `Auto` can land on light |
| Zehn | `Show What's New` | `no` | |
| Zehn | `Foreground Color Mix` | `0` | had drifted to 81, greying the whole UI |

Only declared options are forced; everything else stays yours to change in the
Steam UI and survives rebuilds.

**`Scrollbars` reads backwards.** Upstream's description is *"Hides the
scrollbars in the SteamUI"*, so `yes` **hides** and the default `no` shows them.

### SpaceTheme

**Pinned to a COMMIT, not a tag.** Upstream stopped tagging — the newest tag is
`v202505024` from May 2025 while development ships straight to `main` — so a tag
would pin something 15 months stale.

```bash
nix-prefetch-git --url https://github.com/SpaceTheme/Steam --rev <sha>
```

Its colour system is **much better suited to matugen than Zehn's**: the whole
palette is bare `R, G, B` triplets in an 18-line `src/css/root.css`, which is
exactly matugen's output shape. No Windows-DWM indirection, no seven-variable
ramp to reconstruct — just `--st-accent-1` and `--st-accent-2`.

`--st-accent-2` (the hover/lighter variant) must come from matugen's
`primary_fixed`, **not** `primary_fixed_dim`: for many wallpapers the latter
resolves to the same value as `primary`, leaving hover states indistinguishable.

49 options, vs Zehn's 24. Ones worth knowing: `Sidebar only on hover`,
`Border radius`, `Window Controls` (Hide / Show / Show only on hover),
`Max Width` (default 1200 — low for an ultrawide), `Game cover shiny effect`.
Leave **`System accent colors` off** — it fights the matugen accent.

### The "SpaceTheme" label in the title bar

That is **Millennium**, not the theme — `SpaceTheme` appears nowhere in the
theme's CSS or JS, only in `skin.json`, the LICENSE and the README. Millennium
renders the active theme's name into Steam's title area, which is why no theme
option turns it off.

Two ways to deal with it, neither implemented yet:
- **Hide it** in `quick.css`. Live, no restart, but needs a live probe to get
  the selector (`steam -dev` makes this trivial).
- **Colour it** via Millennium's own `general.accentColor` in `config.json`
  (default `DEFAULT_ACCENT_COLOR`; it derives a light1..3 / dark1..3 ramp).
  Downside: that file is written at rebuild, so the colour would be static and
  would drift out of sync the first time the wallpaper palette changes.

### Zehn

**Pinned to a tag on purpose — do not track a branch.** Steam theming depends on
Steam's per-build hashed class names, so Zehn retags whenever a Steam update
breaks them (five tags in the first week of Aug 2026). An unpinned fetch would
silently restyle the client on an unrelated rebuild and make the build
non-reproducible. To bump:

```bash
nix-prefetch-git --url https://github.com/yurisuika/Zehn --rev refs/tags/<tag>
```

`UseDefaultPatches: false` — Zehn declares its own patch list, including
`https://.*.steampowered.com` and `https://steamcommunity.com`, so it themes
store and community pages too, not just the client chrome.

Zehn has ~24 options ("Conditions") under Millennium → Settings → Themes:
Color Mode, Transparency Effects, Content/Panel Roundness, Navbar/Titlebar Size,
Scrollbar Style, Background/Foreground Color Mix, and a Waifu overlay (off by
default). Millennium persists them to `themes.conditions.Zehn` in `config.json`.

**Nix only *seeds* those conditions, it does not force them** — Millennium writes
UI tweaks back to the same file, so forcing would revert your tweaks on every
rebuild. Only `Color Mode` is seeded (to `Dark`; Zehn's default is `Auto`, which
can land on the light variant). Tweak the rest freely in the Steam UI.

Zehn's "Transparency Effects" description mentions behind-window blur via the
**DWMX plugin — that is Windows-only** and does nothing here. The in-CEF
translucency still works and layers under the Niri opacity rule fine.

### dots-glass (fallback)

Kept because it targets *only* Steam's stable design-system classes, so it still
works on a Steam release Zehn hasn't caught up with yet. Deliberately minimal.

`Resources/Steam-Glass-Theme/` → installed to
`~/.steam/steam/millennium/themes/dots-glass/`.

Files are **copied, not symlinked** — Millennium serves theme files over its own
HTTP hook, and a dangling store symlink survives a GC worse than a plain copy.

| File | Purpose |
|------|---------|
| `skin.json` | `UseDefaultPatches: true` + `RootColors: colors.css` |
| `colors.css` | `:root` hex variables |
| `libraryroot.custom.css` | Main client window |
| `friends.custom.css` | Friends list / chat (separate document) |

`UseDefaultPatches` pulls in Millennium's built-in map of Steam window titles →
target CSS file (`^Steam$`, `.ModalDialogPopup`, `.friendsui-container`, …), so
the theme doesn't have to declare patches itself.

There is intentionally **no `bigpicture.custom.css`** — Big Picture is fullscreen
gaming and glass there is wrong. Millennium's default patches reference the file;
a missing target just 404s harmlessly.

### Why dots-glass only styles dialogs and chrome

(This constraint is why Zehn is the active theme — Zehn accepts the maintenance
burden described here, and retags to keep up. dots-glass refuses it.)

**Steam exposes no global colour-token set.** Its `:root` blocks contain only
~156 layout variables and a handful of `--gp*` tokens — the actual UI colours are
hardcoded hex (`#1b2838`, `#23262e`, `#3d4450`) inside per-build **hashed class
names** like `._2H7sBdIRIS9AbCJmYyEMbz`, which change on every client update.

So the theme targets only Steam's **stable design-system classes**:
`.DesktopUI`, `.Dialog*`, `.Modal*`, `.title-*`, `.friendsui-container`,
`.FullModalOverlay`. The library grid keeps Steam's stock dark palette — it is
already dark, so it reads fine at 85%.

Verify the stable-class list against a new client with:

```bash
cd ~/.local/share/Steam/steamui/css
grep -ohE '\.[a-zA-Z][a-zA-Z0-9_-]{3,40}' library.css \
  | sort | uniq -c | sort -rn \
  | grep -vE '\.[a-zA-Z0-9_-]*[0-9A-Z]{4,}'   # drop hashed names
```

### colors.css must be hex-only

Millennium parses `RootColors` and exposes each variable in its in-Steam theme
editor (Settings → Themes → Edit). The parser only recognises **colour
literals** — an `rgba()` or `calc()` there is silently dropped. Translucent
overlays therefore live in `libraryroot.custom.css`, not `colors.css`.

The parsed values are cached into `config.json` under
`themes.themeColors.dots-glass`, and **the cached value wins over the file**
(Millennium only seeds from the file when the config key is null). So editing
`colors.css` after first run appears to do nothing — clear that config key first.

## Quick CSS — the local-tweak layer

`~/.config/millennium/quick.css`, **managed by Nix** (`Modules/steam.nix`,
via `xdg.configFile`). Millennium injects it into every Steam document on top of
whatever theme is active.

This is the right layer for local tweaks, confirmed by upstream: Zehn's own
`custom.css` says *"If you are using Millennium, use the Quick CSS feature
instead, as Millennium overwrites the Zehn folder during updates"* — and here Nix
overwrites the theme folder on every rebuild too, so anything put in the theme
directory is lost.

Millennium has a Quick CSS **editor** in its settings UI that writes to this same
path. Because Nix points it at a read-only store symlink, edits there fail by
design — Nix owns the file.

## Zehn has no accent colour on Linux (fixed via Quick CSS)

Zehn's whole accent system resolves from a single variable:

```css
--zehn-rgb-accent: var(--SystemAccentColor-RGB, 210, 115, 138)
--zehn-color-accent: rgb(var(--zehn-rgb-accent))
/* + ~30 derived shades: accent-10..100, darken/lighten/negative-* */
```

`--SystemAccentColor-RGB` is a **Windows DWM value**. Nothing sets it on Linux,
and Steam does not define it either (verified: no hit for `SystemAccentColor`
anywhere in `~/.local/share/Steam/steamui/css`). Result: selections, borders and
status highlights render flat/black instead of coloured.

**Supplying `--SystemAccentColor-RGB` does NOT fix it.** That was the obvious
route and it was tried and verified not to work — Steam still rendered a
colourless accent. Don't re-attempt it. What is confirmed:

- Quick CSS *does* load — forcing `--zehn-rgb-accent: 255, 0, 0 !important`
  visibly turned the nav underline red.
- No other rule defines `--SystemAccentColor-RGB` (0 definitions across
  `variables.css`, `bootstrap.css` and the whole `option/` tree), and the only
  other `--zehn-rgb-accent` definition is inside
  `@media (prefers-contrast: more)`.
- So the indirection simply does not resolve in Steam's CEF. Reason unknown;
  the direct override works and that is what's used.

**The fix** is to set the seven derived triplets directly, with `!important`:

```css
:root {
  --zehn-rgb-accent-lighten-major:  255, 222, 174 !important;
  --zehn-rgb-accent-lighten-medium: 241, 190, 109 !important;
  --zehn-rgb-accent-lighten-minor:  241, 190, 109 !important;
  --zehn-rgb-accent:                241, 190, 109 !important;
  --zehn-rgb-accent-darken-minor:   125,  87,  14 !important;
  --zehn-rgb-accent-darken-medium:   96,  65,   0 !important;
  --zehn-rgb-accent-darken-major:    96,  65,   0 !important;
}
```

All seven, not just the base — Zehn uses the lighten/darken ramp for hover and
pressed states, and overriding only `--zehn-rgb-accent` leaves those on their
pink fallbacks. Values are bare `R, G, B` triplets, never hex: Zehn consumes
them as `rgb(var(--…))`.

**`Foreground Color Mix` also matters.** It blends
`--option-rgb-blend-foreground` (a cream) into every foreground colour. It had
drifted to `81`, which desaturates the whole UI toward grey-cream and was a large
part of why Steam looked colourless next to Zehn's own screenshots. Forced back
to Zehn's default of `0` in `zehnConditionsForced`.

### Debugging Steam's DOM

There isn't an easy way. Millennium launches steamwebhelper with
`--remote-debugging-pipe`, so the usual `.cef-enable-remote-debugging` marker
gives you **no TCP CDP port** to attach to. The practical loop is instead:

1. edit `~/.config/millennium/quick.css` by hand with an unmistakable value
2. `steam -shutdown`, relaunch, and screenshot with `grim -o DP-2 out.png`

That is how the accent behaviour above was established. Quick CSS is read at
Steam start, so every iteration needs a full restart.

## matugen (wired)

Steam follows the wallpaper like btop, noctalia and Spotify. The whole surface is
**one accent triplet** — Zehn derives ~30 shades from it.

`Modules/steam.nix` uses the same two-instantiation trick as `Modules/btop.nix`,
so the seed and the template can't drift:

| | |
|---|---|
| `mkQuickCss` | the shared generator |
| static seed | literal hex (`fallbackAccent`), written by the activation script |
| `flake.lib.steam.matugenTemplate` | same file with matugen tokens; installed by `skwd-wall.nix` |

**Getting a bare `R, G, B` out of matugen:** use the integer channel accessors —

```
{{colors.primary.default.red}}, {{colors.primary.default.green}}, {{colors.primary.default.blue}}
```

`rgb` gives `rgb(128, 213, 211)` (parens included) which Zehn cannot use, and
matugen's engine is **not Tera** — `replace(from=…, to=…)` is a parse error; its
filters take colon args (`| lighten: 20.0`). Verified against matugen 4.0.0.

Filters also **do not chain into the channel accessors** — `{{colors.primary.default
| lighten: 20.0 | red}}` fails to parse. So the light→dark ramp Zehn wants comes
from distinct Material You roles instead, which are already tonal steps of the
same hue: `primary_fixed` → `primary_fixed_dim` → `primary` → `inverse_primary`
→ `primary_container`.

**Do not route this through `RootColors`.** Millennium caches parsed `RootColors`
into `themes.themeColors` and the cache wins over the file, so a matugen-rendered
`colors.css` is ignored after first run. Quick CSS has no such cache.

**No reload command** — Steam cannot re-read Quick CSS from outside (Millennium's
watcher is an editor-only toggle), so a new accent applies at the next Steam
start. Unlike Spicetify, which has CDP injection.

### TRAP: a rebuild updates the template, NOT the rendered file

This one bit three times in a single session — the border vanishing, the accent
not applying, and SpaceTheme rendering blue.

`quick.css` is **matugen-owned**. A rebuild copies the new template to
`~/.config/skwd-wall/data/matugen/templates/steam-quick.css`, but the rendered
`~/.config/millennium/quick.css` is only rewritten when matugen next runs — i.e.
**on a wallpaper change**. So edits to the generator look like they did nothing,
and it is tempting to go debugging CSS that is not actually loaded.

Check which is which before assuming anything is broken:

```bash
grep -c st-accent ~/.config/skwd-wall/data/matugen/templates/steam-quick.css  # template
grep -c st-accent ~/.config/millennium/quick.css                              # rendered
```

Mismatch = stale render, not a CSS bug. Change the wallpaper to force it.

Worth fixing properly: a rebuild should re-render from the current palette
(matugen can read a saved palette via its `json` subcommand) instead of waiting
for a wallpaper change.

### quick.css must not be a home-manager symlink

matugen rewrites that exact path on every wallpaper change and store symlinks are
read-only. It is seeded as a plain writable file using btop's refresh rule: write
the seed only when the file is missing, or when it is still byte-identical to the
seed installed last time (i.e. matugen hasn't taken ownership yet). Once matugen
owns it, editing the generator stops clobbering live colours — to force a reseed,
delete `~/.config/millennium/quick.css` and rebuild.

## Live reload (working)

`Modules/steam.nix` installs a tiny Millennium plugin, `quickcss-watcher`, whose
only job is to call `Core_WatchQuickCss` at startup. That registers Millennium's
file watcher on `quick.css`; on change it runs `UpdateStylesLive`, which walks
every open Steam window and swaps the stylesheet contents in place. Wallpaper
change → Steam recolours instantly, no restart. Confirmed working.

**The ffi call must use the two-argument overload**,
`ffi("core", "Core_WatchQuickCss")`. Millennium's own settings panel uses the
one-arg form because it *is* the core plugin; from a third-party plugin that
fails with `Millennium Error: plugin not running`.

**Writes must preserve the inode.** `printf >>` and `cat >` are fine; **`sed -i`
is not** — it writes a temp file and renames, which swaps the inode and the
watcher never fires. Relevant when hand-testing.

Plugin loading is logged to `~/.local/share/Steam/logs/` (not
`~/.local/state/millennium/logs`, which never gets created):

```bash
grep -ih "quickcss-watcher" ~/.local/share/Steam/logs/*.txt | tail -3
```

## Steam's own hardcoded blues

Zehn does not recolour these; they are literal hex gradients in Steam's
`library.css`. Overridden in the Quick CSS generator against Steam's **stable**
design-system classes, so they survive client updates:
`DialogButton.Primary`, `DialogToggleField_Option.Active`, `DialogSlider_Value`,
`div.ModalPosition_TopBar`. More will exist on store/community pages — add them
the same way.

## Debugging: use `steam -dev`

**Start here next time.** `steam -dev` adds a Console entry to Steam's menu bar
and enables inspect-element on the client — element picker, DOM tree, live CSS
editing. Steam runs **CEF 85**, so treat it as Chrome 85 devtools (no modern
`:has()` behaviour).

This session was done without it, by grepping minified CSS and screenshotting
with `grim`, which was slow and produced two wrong conclusions. Don't repeat that.

**A pixel diff between screenshots is NOT a valid check.** The Steam window is
translucent over an animated wallpaper; a control diff with no change at all
measured 5.6e7 against a real change's 6.9e7. Compare crops visually instead.

## Sidebar / game list

Steam ships a **CSS-module map inside its JS**, which is how to get real
selectors instead of guessing:

```bash
grep -ohE '"?GameIcon"?: *"[A-Za-z0-9_-]+"' ~/.local/share/Steam/steamui/chunk~2dcc5aaf7.js
```

Known keys: `GameIcon`, `GameListEntryContainer`, `GameListEntryName`. As of
2026-08-11 `GameIcon` was `_3wJBzhlh-X4xC3GHyKmDQ1`.

**These hashes change on every Steam update.** Deliberately NOT hardcoded in
`steam.nix`. The idea worth building: extract them at activation time and
generate the rules, so the styling self-heals — something even SteamUI-OldGlory
doesn't do (it has a manual "Remake JS" button for exactly this churn).

Unresolved:
- **Sidebar width.** `.DesktopUI > div > div:first-child` highlights the sidebar
  exactly, but setting `width` on it does nothing, and without `:not(:last-child)`
  it also matches the account dropdown and collapses the game grid. The real
  sizing element is elsewhere — find it with `steam -dev`. Try dragging the
  divider first; Steam may resize natively and persist it.
- **Cover art per row.** Not possible in CSS: rows carry no `data-appid`, no
  app-id attribute and no `/library/app/` href (all three probed, zero matches).
  The art *is* on disk (`~/.local/share/Steam/appcache/librarycache/`, 210 ×
  `library_600x900.jpg`, 465 × `header.jpg`). Would need a Millennium plugin
  reading each row's app id from React state.

Reference: [SteamUI-OldGlory](https://github.com/Jonius7/SteamUI-OldGlory) —
modular SCSS + JS tweaks for exactly this area, good source of working selectors.

### flake.lib needed declaring

`Modules/flake-lib.nix` declares `flake.lib` as `lazyAttrsOf raw`. flake-parts
leaves undeclared flake outputs as `types.raw`, which refuses to merge, so
`steam.nix` exporting `flake.lib.steam` alongside `btop.nix`'s `flake.lib.btop`
failed eval with *"Define the value only once"*. Any future module exporting
`flake.lib.<name>` now just works.

## Applying changes

```bash
sudo nixos-rebuild switch -p Sisyphus --flake .#rock-Sisyphus --option eval-cache false
```

- **Theme CSS changes** need only a Steam restart (or Millennium's "Reload UI").
- **Niri opacity changes need a re-login** — the compositor reads only the baked
  store config.

## TRAP: the hiPrio `steam` wrapper in niri.nix

`Modules/Desktops/niri.nix` puts a `lib.hiPrio (writeShellScriptBin "steam" …)`
in `environment.systemPackages` to add `-no-cef-sandbox`. Because it is hiPrio it
**wins the `steam` name in the system path**, and the Steam `.desktop` override
in the same file routes through `steam-open` → `steam`, so *every* launch goes
through it.

It must wrap **`config.programs.steam.package`**, never `pkgs.steam`. Wrapping
bare `pkgs.steam` silently discards everything `Modules/steam.nix` configures.
It did exactly that until 2026-08-10, shadowing both the Millennium injection and
the libpulseaudio/pipewire audio fix.

**Why this is nasty:** `nix eval …config.programs.steam.package` shows the
override applied, and the FHS profile genuinely contains `MILLENNIUM_RUNTIME_PATH`
— the package is built correctly and is in the closure. It just isn't the one
that runs. Verify what actually launches, not what evaluates:

```bash
cat "$(readlink -f /run/current-system/sw/bin/steam)"   # which package does it exec?
ls -l ~/.local/share/Steam/ubuntu12_32/libXtst.so.6     # must be a store symlink
```

A missing `libXtst.so.6` means Millennium's `extraProfile` never ran, which means
the wrong Steam launched. Anything else you add to `programs.steam.package` in
future is subject to the same trap.

## Troubleshooting

**Millennium not loading:** first check the hiPrio wrapper trap above. Then check
the symlink actually points into the store —
`ls -l ~/.local/share/Steam/ubuntu12_32/libXtst.so.6`. If it points at a real
libXtst, Steam updated and the profile hasn't re-run; relaunch Steam.

**Logs:** `~/.local/state/millennium/logs`

**Theme not listed in Steam:** `skin.json` failed to parse. Millennium marks the
theme `failed` and silently falls back to `default`.

**Steam broken after an update:** roll back the generation. Millennium is beta
and patches the live client.

**Colour edits in `colors.css` ignored:** the cached `themes.themeColors` entry
is shadowing the file — see above.
