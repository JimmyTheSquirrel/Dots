# Luciole — the file manager on Sisyphus

`Modules/Desktop/luciole.nix` · flake input `luciole` · **Sisyphus only**

[noctalia-dev/luciole](https://github.com/noctalia-dev/luciole) — the file
manager from the same project as the shell. Replaced Thunar on Sisyphus on
**2026-11-20**. Elektra kept Thunar (`Claude/misc.md` → Thunar).

C++23 drawing straight onto **Wayland + GLES**. No Qt, no GTK, no Quickshell,
no QML. Grid / list / Miller-column views, tabs, split view, side preview.

## ⚠️ It is version 0.1.0

Upstream's README says in as many words that settings, shortcuts and behaviour
may change between releases. The practical consequence for this repo:

- **Unknown keys only warn** and are ignored at runtime — an obsolete setting
  never blocks startup.
- **A key whose type or accepted values changed is a hard error**, and it will
  surface as a *build* failure, not a runtime one, because
  `programs.luciole.checkConfig = true` runs the package's own
  `luciole config validate` over the generated TOML during the rebuild.
  `validate` is deliberately stricter than the running app and rejects unknown
  keys too. **Leave checkConfig on** — it is the only thing that catches a
  schema change after `nix flake update`, and it fails loudly and early.

So: after a flake update that bumps Luciole, a rebuild failure naming
`luciole-config.toml` means the `settings` block needs revisiting, not that
anything is broken.

## Config ownership — Luciole has a real seam, unlike noctalia

Precedence, lowest first:

| | Path | Owner |
|---|---|---|
| 1 | built-in defaults | upstream |
| 2 | `~/.config/luciole/config.toml` | **Nix** (the `settings` block) |
| 3 | `~/.config/luciole/settings.toml` | **the GUI**, and it stays writable |

Luciole *never writes through* `config.toml`. That is a designed seam and it is
the opposite of noctalia, where Nix force-writes `settings.toml` and a rebuild
reverts any GUI change (`Claude/noctalia.md`).

What that means in practice:

- A GUI tweak **wins** over the Nix value and **survives rebuilds**.
- *Reset* in Settings drops the override, and the Nix value applies again.
- Nothing is clobbered in either direction. **Don't reflexively edit Nix for a
  situational tweak** — change it in the GUI; edit the module for the baseline
  you want a fresh install to come up with.

Other writable state, none of it Nix's: user bookmarks in
`~/.config/gtk-3.0/bookmarks` (shared with Nautilus/Nemo and GTK file
choosers), Places layout and last-window tabs in
`~/.local/state/luciole/state.toml`, thumbnails in the shared
`~/.cache/thumbnails/`, scripts in `~/.local/share/luciole/scripts/`.

## Mod+E goes through a `file-manager` shim, and that is deliberate

niri's keybinds are **baked into the wrapped niri package at `perSystem`** (see
the header of `Modules/Desktop/niri.nix`; the baked store config is the only
keybind file the compositor ever reads), and that one package is shared by
**Sisyphus and Apollo**.

A `lib.getExe pkgs.luciole` in that bind would put Luciole in the **rescue
ISO's** closure and make `apollo-iso` compile a C++ file manager plus a Rust
librsvg rebuild it has no use for. Verified: Apollo's closure has **0** luciole
derivations, Sisyphus's has 3.

So niri spawns a bare `file-manager`, and each host that imports niri says what
that is:

| Host | `file-manager` → | Defined in |
|---|---|---|
| Sisyphus | Luciole | `Modules/Desktop/luciole.nix` |
| Apollo | Thunar | `Hosts/Apollo/system.nix` |
| Elektra | *n/a* — Hyprland, `$fileManager = "thunar"` | `Modules/Desktop/hyprland.nix` |

**Add a new niri host and it needs a `file-manager`**, or Mod+E does nothing
there.

## Transparency is client-side now — no niri rule

There is deliberately **no** `window-rule` for `^dev\.noctalia\.luciole$`.
`background_opacity` is a **client-side** background alpha: it fades the
background *alone* and leaves text crisp. niri's `opacity` is uniform and fades
text with it, which is exactly why the old Thunar rule read as "dim" rather
than "glassy" and why the `gtk.css` route was built and rejected on taste
(`Claude/misc.md`). Setting both would multiply them.

⚠️ **The live value is rock's, not the module's.** The Nix baseline in
`config.toml` is `0.9`, but he dialled it in through the GUI and
`settings.toml` **wins** — on 2026-11-21 it held:

```toml
background_opacity = 0.54      # much more wallpaper than the Nix baseline
corner_radius_scale = 0.1      # near-square corners
grid_icon_size = 80
always_show_tab_bar = false
hidden_last = true
show_preview = false
sidebar_width = 176
miller_column_width = 212
```

That is the seam working as designed, not drift — **don't "fix" it by editing
Nix.** But note the consequence: those are the values that make the window look
the way it does, and **a wipe loses all of them** (see the fresh-wipe note in
`Claude/next-up.md`). Promoting them into `programs.luciole.settings` is the
only way a fresh install comes up looking like this.

## Colours — it is a first-class member of the existing pipeline

**skwd generates, noctalia fans out** (`Claude/noctalia.md`,
`Modules/Desktop/skwd.nix`). Luciole plugs into the *second* half of that
**natively**: it reads a `colors.toml` written in noctalia's own `{{ }}` token
syntax and reloads it live. So the whole integration is **one template entry** —
no reload hook, no matugen template to keep in sync:

```nix
my.noctalia.lockedSettingsExtra.theme.templates.user.luciole = {
  input_path  = "${colorsTemplate}";                     # Resources/Luciole/colors.toml
  output_path = "$XDG_CONFIG_HOME/luciole/colors.toml";
};
```

### ⚠️ We use OUR template, not the one Luciole ships

Luciole ships a ready-made one in `share/luciole/templates/`. It takes **every**
token straight from the palette, surfaces included — and the skwd palettes are
strongly tinted. On 2026-11-21 the live palette was `primary #c2d000` with
`surface #131408`, an olive dark, and the result was that the **toolbar, the
search field and the file area behind the icons all went olive**. rock's verdict
looking at it on the monitor: *the colour belongs in the sidebar, not washed over
the top bar and the background.*

So `Resources/Luciole/colors.toml` runs the **surface family** through
noctalia's **`grayscale`** filter and leaves the accents untouched:

| Family | Treatment | Why |
|---|---|---|
| `primary` `secondary` `tertiary` `hover` | **from the palette** | the sidebar's selected row and focus accents still follow the wallpaper |
| `error` | **from the palette** | red is a signal, not decoration |
| `surface` `surface_container*` `on_surface*` `outline_variant` | **`\| grayscale`** | toolbar, search field, sidebar panel, file area — the chrome |
| `surface_container_high` | also **+ alpha** | the search field and breadcrumb pill — `my.luciole.chromeOpacity`, below |

`grayscale` converts by **luminance weighting**, so each step keeps its
*lightness* and only loses its hue — the `surface → container → container_high`
ramp still reads as depth. Rendered against the live palette, the olive becomes
a clean neutral ramp while the accent survives:

```
surface                   #131408  ->  #121212      primary    #c2d000  (unchanged)
surface_container         #1f2113  ->  #1f1f1f      tertiary   #abd19a  (unchanged)
surface_container_highest          ->  #373737      error      #ffb4ab  (unchanged)
```

To go back to a fully tinted window, drop every `| grayscale`. For a partial
tint instead of full neutral, swap it for `desaturate 70`.

⚠️ **Keep the token set in step with upstream after a Luciole bump.** A token
added upstream is simply missing from ours, and Luciole falls back to its
built-in value rather than erroring — so it fails quietly. The header of
`Resources/Luciole/colors.toml` carries the `diff` one-liner that checks parity.

### ⭐ `my.luciole.chromeOpacity` — the search field and the breadcrumb pill

Second pass over the same screenshot, 2026-11-21. With the tint gone, rock's
remaining objection was *"the dark searchbar and the navigation bar thing"*.
Measured off the screenshot rather than guessed:

| Element | Fill | |
|---|---|---|
| toolbar strip | **no fill at all** | it is the window showing through — never the problem |
| window background | `surface_container_low` **at `background_opacity`** | `#0f1518` composited, i.e. mostly wallpaper |
| breadcrumb pill (x126–1463) | `surface_container_high` **opaque** | flat `#2b2b2b` |
| search field (x1472–1691) | `surface_container_high` **opaque** | flat `#2b2b2b` |

So the two pills were the **only fully opaque things in a translucent window**.
`my.luciole.chromeOpacity` (**0.40** here) gives that one role an alpha, so
they settle into the bar instead of floating on it. Comparison page, built by
recompositing his actual screenshot:
<https://claude.ai/artifact/8Ptf3WHdz569X4UUE9pewG>

```
1.00  #2b2b2b   what upstream does        0.55  #1f272d   = the window's own 0.54
0.85  #272a2c   barely moves              0.40  #1b252d   ← CHOSEN 2026-11-21
0.70  #23282c
```

**⚠️ The alpha has to be two literal hex digits appended in the template.**
Noctalia *has* a `set_alpha` filter, but `.hex` formats through
`Color.to_hex()`, which is `#{r}{g}{b}` and drops alpha on the floor — only the
`rgba`/`hsla` formats carry it, and Luciole's `colors.toml` parser takes hex
strings only (`lib/render/core/color.h` `hex()`, which accepts 4, 5, 7 or 9
characters). The two are mutually exclusive. Hence `@chromeAlpha@` in
`Resources/Luciole/colors.toml` and `toHex2` in the module — Nix has no hex
formatter, so the float→`#RRGGBBAA` conversion is written out by hand.

Because the template is now substituted, `input_path` is a `pkgs.writeText`
derivation rather than the repo path. Everything about the `lockedSettingsExtra`
rule below is unchanged — it was always a store path.

**⚠️ `surface_container_high` is not only those two pills.** Also drawn with it:
context menus and submenus (`menu_controller.cpp`, `submenu_controller.cpp` —
**no opaque plate underneath**), the status-bar pill, the row-hover highlight,
and the view-mode segmented control. Below ~0.6 the file grid starts reading
through an open right-click menu. That is why the neighbouring
`surface_container*` steps are left fully opaque, and it is the thing to check
after changing this.

### ⚠️ Why it is set in `lockedSettingsExtra`, not noctalia.nix's shared lock

`Modules/Desktop/noctalia.nix` is imported by Elektra and Apollo, and neither
has Luciole. This mattered *more* when `input_path` pointed into the Luciole
package — that would have dragged the whole from-source build into her closure
and the rescue ISO's, exactly the Mod+E trap. It now points at our own small
TOML so the closure risk is gone, but the rule stands: **a per-host template
belongs in `lockedSettingsExtra`.** Verified: Elektra, Apollo and Asgard each
hold **0** luciole derivations.

The merge is `lib.recursiveUpdate`, so `builtin_ids` and `community_ids` keep
their (deliberately empty) values and `user.luciole` is added beside them.

### ⚠️ Nix must not manage `colors.toml`

**noctalia** writes `~/.config/luciole/colors.toml`. An `xdg.configFile` entry
for it would put a read-only store symlink in the way and make every render
fail. Three files, three owners — confirmed live on 2026-11-21:

| File | Written by |
|---|---|
| `config.toml` | **Nix** — a store symlink |
| `settings.toml` | the **GUI**, and it **wins** |
| `colors.toml` | **noctalia**, from the skwd palette |

### ⭐ The first render needs `noctalia-apply-palette`, not `templates-apply`

`noctalia msg templates-apply` re-renders from the palette noctalia already
holds **in memory** and can report "ok" while writing nothing — the trap
measured on 2026-09-15 and written up on `noctalia-apply-palette` in
`Modules/Desktop/noctalia.nix`. Re-selecting the already-selected palette is
what forces the fan-out. So after a switch that changes the template, once:

```sh
noctalia-apply-palette     # or just change the wallpaper
```

### How to verify it, rather than trusting the file

Every consumer in this pipeline has a **static fallback**, so a themed-looking
Luciole proves nothing (`frozen-output-looks-healthy`). Render the template
against the live palette by hand — read-only, `noctalia theme` is a pure
generator and does **not** apply anything to the running desktop:

```sh
noctalia theme --theme-json ~/.config/noctalia/palettes/skwd-wall.json \
  -r "$PWD/Resources/Luciole/colors.toml:/tmp/out.toml"
```

Then check `/tmp/out.toml` has real hex values and **no `{{ … }}` left**.

## Folder shape — `my.luciole.iconTheme`

rock didn't like Adwaita's **soft** folder corners and asked for sharper and
squarer (2026-11-20). The folder drawing comes from the **desktop icon theme**,
which Luciole reads from GSettings `org.gnome.desktop.interface icon-theme`
(its wrapper carries dconf + gsettings-desktop-schemas for exactly that),
falling back to `gtk-3.0/settings.ini`. This repo set neither, so it drew the
Adwaita bundled in its own wrapper.

So there is now one knob, an enum, and swapping it is **one word + a rebuild +
a re-login**:

```nix
my.luciole.iconTheme = "papirus";   # default
```

### The table, by measured corner radius

Measured from each theme's own `places/folder` SVG — the `rx` on the folder
body, or the arc radius in its path data — over the icon's viewBox size, so the
figures compare across themes drawn at different sizes. **Lower = sharper.**

| Value | Theme | Radius | Follows palette? |
|---|---|---|---|
| `zafiro` | `Zafiro-icons-Dark` | **1.6%** — effectively square | ✗ keeps its own hue |
| `flat-remix` | `Flat-Remix-Blue-Dark` | **2.8%** | ✓ |
| `papirus` | `Papirus-Dark` | **4.4%** | ✓ |
| `colloid` | `Colloid-Dark` | 6.8% | ✓ |
| `adwaita` | `Adwaita` | 7.8% — *the soft look* | ✗ |
| `kora` | `kora` | 7.8% | ✓ |

**Follows palette** = the theme declares `FollowsColorScheme=true`, so Luciole
tints its folders from the primary colour in `colors.toml` and they track the
skwd wallpaper palette like the rest of the desktop.

**Papirus is the default** because it is clearly sharper than Adwaita, already
installed (so it costs nothing in the closure), and follows the palette. rock
chose to judge it on the monitor before going sharper — if it still reads soft,
`zafiro` is the square one.

### ⛔ Two traps

**`numix-icon-theme-square` is deliberately absent from the enum.** Its own
index.theme says *"square **apps** icons design"* and it `Inherits=Numix` for
everything else, so its folders are plain Numix at **10.2% — softer than
Adwaita**. The name is actively misleading for this job.

**A theme name in dconf with no package installed falls back silently** — which
is the most likely way this looks like "the setting did nothing". That is why
the enum carries the package alongside the name and the module installs it.

### ⚠️ It is not a Luciole-only setting

`icon-theme` is read by **every GTK app on the host**. It lives in
`Modules/Desktop/luciole.nix` because Luciole is the reason it is set and
because that module is **Sisyphus-only** — putting it in `desktop.nix` would
have taken Elektra with it. A full adw-gtk3-dark + Papirus pass over the
desktop was **rejected on taste** on 2026-09-25 (`Claude/misc.md`,
`gtk-thunar-colour-pipeline`); this is *only* the icon theme, no widget theme,
but if the look is wrong the fix is this one word — **not** a reason to rebuild
that.

Already-running GTK apps pick it up on the **next login**. Luciole itself
refreshes on a theme change while open.

## Settings carried across from Thunar

Key for key against the old `thunar.xml`, so the swap was not also a behaviour
change:

| Thunar (`thunar.xml`) | Luciole (`[browser]`) |
|---|---|
| `default-view = ThunarIconView` | `view_mode = "grid"` |
| `misc-show-hidden-files = true` | `show_hidden = true` |
| `misc-show-free-space = true` | `always_show_status_bar = true` |
| `misc-folders-first = true` | `directories_first` — already the default |
| `misc-single-click = false` | `activation_mode` — already the default |
| `misc-thumbnail-max-file-size = 0` | `thumbnail_max_file_mib = 1024` (its ceiling) |

Plus two that have no Thunar equivalent:

- **`terminal_command = "kitty"`** — explicit on purpose. Empty means Luciole
  tries `xdg-terminal-exec`, then `x-terminal-emulator`, then a hardcoded list
  **starting at Foot**, and it *cannot* infer a favourite from the fact that
  several are installed.
- `thumbnail_policy = "local"` — skips network shares and diskless FUSE mounts
  (rclone, sshfs). **Asgard's `/data` pool is reached over the network from
  here, so it gets no thumbnails** under this policy; `"all"` permits any path
  with a filesystem presence.

## Build cost

Not in nixpkgs, so this is a **from-source meson build with no binary cache**,
and upstream's `nix/package.nix` additionally rebuilds **gdk-pixbuf** (pinned
to 2.44.6 for the Glycin 2.1 API) and **librsvg** on top of it. The first
rebuild after adding it is long.

⚠️ The `luciole` flake input deliberately carries **no `nixpkgs.follows`** —
that gdk-pixbuf override is only correct against the glycin in the nixpkgs
upstream pins. Point it at ours and the image loaders are a coin toss. Same
class of reason as `skwd-wall-v2` and `millennium`.

## GVfs

Trash, and `sftp://` / `smb://` / `dav://` in the location bar, need GVfs.
Upstream's install guide calls this out because its own modules deliberately
don't enable it. **Already covered**: `Modules/Core/polkit.nix` sets
`services.gvfs.enable` unconditionally and every host importing this module
imports that one.

## `org.freedesktop.FileManager1`

The module drops the package's service file at
`~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service`, which is
upstream's documented way to pick a winner (`PACKAGING.md` → D-Bus
activation): the bus keys off the `Name=` *inside* the file (which is
`org.freedesktop.FileManager1`), not the filename, and `~/.local/share` beats
every system directory. This is what makes "Show in folder" / "Reveal in file
explorer" from other apps (VSCodium, browsers) open Luciole.

## Not done — the file *picker* portal

Luciole also ships a **FileChooser portal backend** (`luciole.portal` +
`org.freedesktop.impl.portal.desktop.luciole`), which would make it the
Open/Save dialog for every app. **Not wired up**, on purpose: at 0.1.0 that is
a much larger blast radius than a file manager, and the portal file has no
`UseIn` key so it would have to be selected explicitly. If you want it:

```ini
[preferred]
org.freedesktop.impl.portal.FileChooser=luciole;gtk
```

in `portals.conf`, and restart `xdg-desktop-portal` — the frontend only
discovers backends at startup. Note an *installed* backend that fails does not
fall back; only a listed *absent* one does.

## Fonts

Luciole follows the system font: GNOME's `font-name` dconf key, else
`gtk-font-name` from `~/.config/gtk-3.0/settings.ini`. This repo sets neither
(the `/etc/gtk-3.0/settings.ini` block was dead and was deleted —
`Claude/misc.md`), so Luciole falls back to Fontconfig `sans-serif` at 14px
rather than the shell's 42dot Sans. The one-line fix, if it ever matters, is a
`font-name` beside the existing `color-scheme` key in
`Modules/Desktop/desktop.nix` — but that key is read by every GTK app, so it
changes more than Luciole.

Folder/file icons: see **Folder shape — `my.luciole.iconTheme`** above.
