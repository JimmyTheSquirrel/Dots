# KDE Plasma — Elektra

**Module:** `Modules/Desktops/kde.nix`
**Pattern:** `plasma-manager` (direct module, not wrapper-modules)

## Panel

Bottom of DP-2 (primary monitor), floating, height 32.
Widgets: Kickoff, Pager, Icon Tasks, Separator, System Tray, Digital Clock

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

## Monitor Config

`plasma-manager` doesn't support the `displays` option. Configure monitors manually in KDE System Settings on first boot — it persists after.

## Notes

- skwd-wall uses `compositor = "kde"` on Elektra
- No Noctalia on Elektra — KDE has its own panel/shell
- screenshot module used instead of Noctalia screenshot widget
