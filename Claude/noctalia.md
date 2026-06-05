# Noctalia — Desktop Shell

**Module:** `Modules/noctalia.nix`
**Pattern:** wrapper-modules
**Used on:** Sisyphus (Niri) and Odysseus (Hyprland)

## Key Settings

- Bar: top position, floating with 8px margins, capsule style, 70% background opacity
- Widgets: ControlCenter, Workspace, MediaMini, Volume, Network, Bluetooth, Clock, Tray
- Color scheme: Dynamic from wallpaper (`useWallpaperColors = true`) via skwd-wall matugen integration
- Desktop widgets enabled on both monitors
- `outOfStoreConfig = "/home/rock/.config/noctalia"` — **required** for matugen colors to work (reads from user dir, not Nix store)

## IPC Commands

```bash
noctalia-shell ipc call launcher toggle       # App launcher
noctalia-shell ipc call sessionMenu toggle    # Power/session menu
noctalia-shell ipc show                       # List all IPC targets
```

**Note:** The IPC target for the app launcher is `launcher`, not `appLauncher`.

To restart noctalia after plugin changes:
```bash
pkill -9 quickshell; rm -rf /run/user/1000/quickshell; noctalia-shell &
```

## Declarative Widget Configuration

Because `outOfStoreConfig` is used, noctalia ignores the Nix-generated widget config and reads from user config files. A home-manager activation script handles setup on each rebuild:

1. Creates `~/.config/noctalia/` directory structure if missing (fresh install)
2. Creates default `settings.json` and `plugins.json` if they don't exist
3. Patches config to enable the desktop-clock widget on both monitors
4. Patches `sessionMenu.powerOptions` to only show: Lock, Reboot, Logout, Shutdown (removes Suspend, Hibernate, Reboot to UEFI)
5. Syncs plugin files (QML, font, manifest) from nix store to `~/.config/noctalia/plugins/desktop-clock/`

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

The font is also bundled directly in the plugin directory and loaded via QML FontLoader for reliable rendering.

## Plugin Development Notes

- Plugins must extend `DraggableDesktopWidget`
- All dimensions must be multiplied by `widgetScale` for proper scaling
- Use `Color.mOnSurface` and `Color.mOnSurfaceVariant` for theme-aware colors
- Custom fonts: bundle in plugin dir, load via `FontLoader { source: "FontName.otf" }`
- Plugin files are synced to `~/.config/noctalia/plugins/<name>/` by the activation script
