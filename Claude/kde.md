# KDE Plasma — Elektra

**Module:** `Modules/Desktops/kde.nix`
**Pattern:** `plasma-manager` (direct module, not wrapper-modules)

## Panel

Bottom of DP-2 (primary monitor), locked to edge (`floating = false`), height 32.
Widgets: Kickoff, Pager, Icon Tasks, Separator, System Tray, Digital Clock

- Pager is minimal: no desktop numbers (`displayedText = "None"`), no window icons
- System tray: only volume + network shown on the bar; all other plasmoids declared `hidden` (collapse into the arrow popup). App SNI icons with random IDs (e.g. LocalSend) can't be pre-hidden declaratively.

## Keybinds

| Key | Action |
|-----|--------|
| `Meta+Q` | Close window |
| `Meta+Shift+F` | Fullscreen |
| `Meta+A` | Overview |
| `Meta+Return` | Kitty terminal |
| `Meta+E` | Thunar file browser |
| `Meta+F` | Brave browser |
| `Meta+W` | SKWD wallpaper selector |
| `Meta+D` | KRunner search (Show Desktop unbound to free it) |
| `Meta+1-6` | Switch to desktop N (task-manager entry shortcuts unbound to free them) |
| `Meta+Shift+1-6` | Move window to desktop N |

## Monitor Config

`plasma-manager` doesn't support the `displays` option. Configure monitors manually in KDE System Settings on first boot — it persists after.

## Notes

- skwd-wall uses `compositor = "kde"` on Elektra — set declaratively in `Modules/skwd-wall.nix` via per-host mapping (Sisyphus=niri, Elektra=kde, Odysseus=hyprland), enforced on every activation
- No Noctalia on Elektra — KDE has its own panel/shell
- screenshot module used instead of Noctalia screenshot widget
