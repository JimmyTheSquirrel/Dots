# Dolphin — trialled and REJECTED

**Status: REJECTED 2026-09-26, same day it was adopted.** `Modules/dolphin.nix`
is deleted, the Sisyphus import is gone, `Mod+E` is back to Thunar, and the
`~/.config/Kvantum` + `kdeglobals`/`dolphinrc` changes were reverted. **Thunar is
the file manager. Do not re-propose Dolphin.**

Kept as a decision record, because everything below was measured and the traps
are real — but the user's verdict after living with it was simply that they did
not like it, plus two specific complaints:

- **Purple.** Catppuccin Mocha's base is `#1e1e2e` — the whole UI reads purple.
- **"The top bar is super dark and looks cursed."** Correct, and it was
  structural: Kvantum draws the toolbar **opaque** (`interior=true`/`frame=true`
  in the theme's `[Toolbar]` section) while the window body is translucent, so
  the bar reads as a solid black strip over the wallpaper. Setting
  `interior=false`/`frame=false` for `[Toolbar]` and `[MenuBar]` fixes it —
  verified: toolbar, body and sidebar all landed at exactly
  `srgba(46,46,46,0.86)` with `KvGnomeDark`. The fix worked; the answer was
  still no.

Neutral alternatives measured, if this ever comes up again: `KvGnomeDark`
(42/46 grey, no tint), `KvDark` (54/52), `KvAdaptaDark` (teal tint),
`KvSimplicityDark` (57/48).

Read `Claude/misc.md` first for why the GTK theming round was reverted — the
whole reason Dolphin is on the table is that Qt has a theming path GTK did not.

## Why consider it

Thunar does everything that is strictly required (drives, right-click extract,
declarative xfconf config) and its only weakness is looks. The GTK route to
fixing that was built on 2026-09-25 and rejected. Qt is a different story:

| | Thunar (GTK) | Dolphin (Qt) |
|---|---|---|
| Drives sidebar | gvfs + udisks2 | Solid + udisks2 |
| Right-click extract | `thunar-archive-plugin` + xarchiver | Ark service menu |
| Declarative config | `thunar.xml` (xfconf), already in the repo | `dolphinrc` / `kdeglobals`, plain INI |
| Wallpaper colours | none — needs a gtk.css, **rejected** | `qt6ct-colors.conf` + `kde-colors.colors`, **skwd already ships both templates** |
| Background-only transparency | needs gtk.css alpha, **rejected** | Kvantum theme can do translucency |
| Extras | custom actions, toolbar | split view, terminal panel, service menus, tabs, filter bar |

The two skwd templates are the real argument: `~/.config/skwd-wall-v2/matugen/
templates/{qt6ct-colors.conf,kde-colors.colors}` are seeded by upstream and
currently unused. Wiring them is one integration entry each, the same shape as
the `btop` one in `Modules/Desktop/skwd.nix`.

## What has to be true before adopting

Non-negotiables carried over from Thunar — if any of these fail, the trial ends:

1. **Drives visible and mountable** without a KDE session running. Dolphin uses
   Solid, which talks to udisks2 over D-Bus (`udisks2.service` is already
   active). Mounting a removable disk needs the polkit agent — `Modules/
   polkit.nix` provides one.
2. **Right-click → Extract**. Provided by Ark's KIO service menu, discovered
   through `$XDG_DATA_DIRS/kio/servicemenus`. In a `nix shell` that path is set
   by the shell; as a real module it comes from `environment.systemPackages`.
3. **No KDE session services required.** Dolphin outside Plasma usually wants
   `kded`/`kwallet` for some features; the trial records what actually breaks
   rather than assuming.
4. **It is not a huge closure for one app.** Recorded below.

## Cost

KDE Frameworks pull in a substantial dependency chain, which is the main
argument against. Measure before deciding — `nix path-info -Sh` on the built
paths (see findings).

## Declarative shape, if adopted

Would become `Modules/dolphin.nix`, self-contained like every other module:

- `environment.systemPackages`: `kdePackages.dolphin`, `ark`, `kio-extras`
  (thumbnails, extra protocols), `dolphin-plugins` (git/svn menus)
- `home.file.".config/dolphinrc"` — view mode, sidebar, split view, tabs
- `home.file.".config/kdeglobals"` — colour scheme + icon theme for Qt apps
- `xdg.mime.defaultApplications`: `inode/directory` → `org.kde.dolphin.desktop`
  (currently `thunar.desktop`, set in `Modules/Desktop/thunar.nix`)
- niri: `Mod+E` currently spawns `lib.getExe pkgs.xfce.thunar`
  (`Modules/Desktop/niri.nix:59`)

⚠️ `Modules/Desktop/thunar.nix` is imported by **all three hosts**, and the old Elektra profile's KDE
already has Dolphin. Check the host matrix before moving anything shared.

## Theming — do NOT repeat the GTK mistake

If Dolphin is adopted, colours come from the skwd pipeline or not at all. No
hand-set palettes, no per-app themes. The order to do it in:

1. Adopt Dolphin plain first. Live with default Breeze for a while.
2. Only then wire `qt6ct-colors.conf` → `~/.config/qt6ct/colors/skwd.conf`, and
   set `QT_QPA_PLATFORMTHEME=qt6ct`.
3. Kvantum translucency last, if wanted at all.

Each step separately, each one reversible. The GTK round failed because theme,
icons, font and colours all landed at once.

## Trial findings (2026-09-26)

Run from the store with `QT_PLUGIN_PATH` / `XDG_DATA_DIRS` pointed at dolphin,
ark, kio-extras and dolphin-plugins. Dolphin 26.04.3, on niri, no Plasma.

**Works, verified:**

- **Starts clean on Wayland** — app-id `org.kde.dolphin`, zero output on stderr,
  no complaints about missing `kded`/`kwallet`/Plasma session services.
- **Drives are there.** The Devices section listed *Basic data partition* and
  *root* with capacity bars, and a *Remote → Network* entry, all from Solid
  talking to udisks2 over D-Bus. This is the thing that had to work outside a
  KDE session, and it does.
- **Right-click archive integration exists** as KF6 `kfileitemaction` plugins,
  which is the modern replacement for the old `kio/servicemenus` `.desktop`
  files — do not go looking for those, Ark no longer ships them:
  - `ark/…/kf6/kfileitemaction/extractfileitemaction.so` → Extract
  - `ark/…/kf6/kfileitemaction/compressfileitemaction.so` → Compress
  - `dolphin-plugins/…/kf6/kfileitemaction/mountisoaction.so` → mount an ISO
  - plus `dolphin/vcs/fileviewgitplugin.so` and friends for VCS columns
- **Out of the box it also has** tabs, split view, a filter bar, Recent
  Files/Locations, and capacity bars in the sidebar — none of which Thunar does.

**Cost: 279 MB.** The union closure is 2.1 GiB across 486 paths, but 415 of
those are already on this system (shared Qt6/KF6 with the rest of the desktop),
so the genuinely new content is 71 paths / 279 MB. The "KDE drags in the world"
objection does not apply here.

**⚠️ Trap for the module: `QT_PLUGIN_PATH` is unset on Sisyphus and the NixOS
`qt` module is not enabled.** Dolphin is wrapped with its *own* plugin dirs, but
Ark is a separate package it does not depend on — so simply adding both to
`environment.systemPackages` would very likely give a Dolphin **with no
right-click Extract**, failing silently and looking like the feature does not
exist. The module has to set it, e.g.

```nix
environment.profileRelativeSessionVariables.QT_PLUGIN_PATH = [ "/lib/qt-6/plugins" ];
```

(or `qt.enable = true`, which sets this plus a platform theme). The old KDE Elektra profile did not
hit this — Plasma sets it there. Test by right-clicking a `.zip` after adopting;
if Extract is missing, this is why.

**Looks wrong by default.** With no Qt platform theme configured, Dolphin comes
up in **Breeze light** — a white window on a dark desktop. Expected, and the
reason the adoption order above starts with "live with default Breeze": fixing
it means `qt6ct` + `QT_QPA_PLATFORMTHEME=qt6ct`, or a `kdeglobals` colour
scheme. Not attempted during the trial, deliberately.

**Not yet tested:** right-click Extract actually executing (needs a real
archive and a human click), thumbnails for video/RAW via kio-extras, and
whether mounting a removable drive prompts correctly through the polkit agent.

## Dark mode + transparency (solved in trial, 2026-09-26)

Three env vars and one Kvantum theme, no GTK-style flailing:

| need | mechanism |
|------|-----------|
| dark | `QT_QPA_PLATFORMTHEME=kde` + `kdePackages.plasma-integration` |
| style + translucency | `QT_STYLE_OVERRIDE=kvantum` + `kdePackages.qtstyleplugin-kvantum` |
| icons | `[Icons] Theme=` in `kdeglobals` |

**`~/.config/kdeglobals` was already a dark scheme** (Breeze Twilight, window
`32,35,38`). Dolphin came up *light* anyway because nothing applies kdeglobals
to Qt outside Plasma — that is exactly what the `kde` platform theme plugin
does. Without it the colour scheme is inert, which is the single most confusing
part of running KDE apps on niri.

**Kvantum gives real background-only translucency** — unlike niri's `opacity`,
text and icons stay at full alpha. Three keys in the theme's `.kvconfig`:

```ini
translucent_windows=true
reduce_window_opacity=14      # → 0.86 alpha, verified by pixel sampling
transparent_dolphin_view=true # ⚠️ without this the FILE VIEW stays opaque
```

`transparent_dolphin_view` is the non-obvious one: with only the first two, the
chrome goes translucent at 0.859 while the file area stays at alpha 1.0.

### De-bluing

Blue comes from three independent places — changing one and expecting the blue
to go is a trap:

1. **Window tint** — the Kvantum theme. KvArcDark is a blue-grey (`#303440`).
2. **Selection / focus `#3daee9`** — the `kdeglobals` colour scheme, *not* the
   Kvantum theme. Survives a Kvantum theme swap unless the theme overrides the
   palette (Catppuccin does; the bundled Kv* themes mostly do not).
3. **Folder icons** — Breeze. `papirus-icon-theme.override { color = "grey"; }`
   builds Papirus with grey folders at build time via `papirus-folders`; the
   valid colours include grey, black, adwaita, brown, carmine, teal, yaru…

Two variants rendered and measured in the trial:

| variant | Kvantum theme | window | selection |
|---------|---------------|--------|-----------|
| **A — neutral grey** | `KvGnomeDark` + translucency | `46,46,46` @ 0.86 | still blue (kdeglobals) |
| **B — Catppuccin Mocha** | `catppuccin-kvantum` mocha/mauve | `26,26,40` @ 0.86 | mauve |

Both with `papirus-icon-theme.override { color = "grey"; }`. All declarative:
the icon override and `catppuccin-kvantum.override { variant; accent; }` are
package args; the Kvantum theme dir is a `home.file`; the env vars are
`environment.sessionVariables`.

Option not yet tried: point skwd's existing `kde-colors.colors` template at the
colour scheme so the accent follows the wallpaper. Lower risk than the GTK
attempt — it is one colour file and touches no icons or fonts.

## Disk space readout

`ShowStatusBar=1` in `dolphinrc` is the enum value for **FullWidth** (0 = Small,
the floating tooltip Dolphin ships with; 2 = Disabled). FullWidth is what puts
`311.8 GiB free` in the bottom-right. The Places panel additionally draws a
capacity bar under each mounted device on its own, no setting needed.

⚠️ **Sizes are always IEC — GiB/TiB, never GB/TB.** The base-10/base-2 toggle
existed in KDE 4 Regional Settings and was dropped in Plasma 5; there is no
`kdeglobals` key for it in Plasma 6 and `BinaryUnitDialect` does not appear in
any KF6 library here. A 2 TB disk reads "1.8 TiB". Nothing to configure — do not
go looking for it again.

## Icons: blue, not grey

The trial briefly used `papirus-icon-theme.override { color = "grey"; }`.
**Rejected — folders should be normal blue.** The module uses stock
`papirus-icon-theme` (whose default folder variant is `folder-blue.svg`) and
sets `[Icons] Theme=Papirus-Dark` in kdeglobals.

Worth keeping straight: the "too blue" complaint that started the theming work
was about the *window tint* (KvArcDark is a blue-grey theme, `#303440`), not the
icons. Blue folders were never the problem.

## Trial files written to `$HOME` (delete to back out)

- `~/.config/Kvantum/` — entire dir is new (`kvantum.kvconfig`, `KvArcDarkTrans/`,
  `GreyTrans/`, `MochaTrans/`)
- `~/.config/kdeglobals` — **pre-existing**, `[Icons] Theme=` changed from
  `breeze-dark` to `Papirus-Dark`
- `~/.config/dolphinrc` — pre-existing, Dolphin rewrites its own state

## Backing out

The trial leaves no trace: it runs from `nix shell`, writes only
`~/.config/dolphinrc` and `~/.local/share/dolphin/` if the app is used, and
those can be deleted. Thunar is untouched throughout.
