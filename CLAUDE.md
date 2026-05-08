# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Principles

**Everything must be declarative and fully reproducible.** This repository should be the single source of truth for the entire system configuration. A fresh NixOS install should be fully configured by cloning this repo and running a single rebuild command.

Key requirements:
- **No manual configuration** - If it's not in Nix, it doesn't exist. Any manual tweak must be captured in a module.
- **No imperative state** - Avoid runtime config files that aren't generated or seeded by Nix. When unavoidable (e.g., `outOfStoreConfig` for matugen integration), use home-manager activation scripts to declaratively manage the initial state.
- **Reproducible builds** - Running `system-rebuild` on a fresh system should produce an identical environment.
- **Self-contained modules** - Each module includes all related config (NixOS + Home Manager) in one file.

When making changes, always ask: "Will this work on a fresh install without manual steps?"

## Build Commands

```bash
# Interactive menu (recommended)
system-rebuild
# Prompts for:
#   1) System: Sisyphus/Odysseus/Elektra
#   2) Action: Switch (now) / Boot (GRUB menu)

# Direct CLI usage
system-rebuild rock Sisyphus         # Build and switch immediately
system-rebuild rock Elektra --boot   # Build for GRUB, don't switch

# Update flake inputs
nix flake update
```

The `system-rebuild` helper (defined in `Resources/zsh-scripts/zsh-helpers.sh`) supports both interactive and CLI modes. Uses named profiles (`-p ${system}`) so each desktop environment has its own profile at `/nix/var/nix/profiles/system-profiles/`.

**Note:** The script uses `echo -n` + `read` (not `read -p`) for zsh compatibility.

## Architecture

This is a NixOS Flake-based dotfiles repository using **flake-parts** + **import-tree** for automatic module discovery. Manages three desktop environment configurations for user `rock` on AMD/Wayland hardware.

### Directory Structure

```
flake.nix                    # Entry point using flake-parts + import-tree
├── Hosts/                   # System configurations (auto-imported)
│   ├── Sisyphus/            # Hyprland desktop
│   │   └── system.nix       # NixOS config with module imports
│   ├── Elektra/             # KDE Plasma 6
│   │   └── system.nix
│   └── Odysseus/            # Niri compositor
│       └── system.nix
├── Modules/                 # Self-contained modules (auto-imported)
│   ├── Desktops/            # Desktop environment configs
│   │   ├── hyprland.nix     # Hyprland (system + home config combined)
│   │   ├── kde.nix          # KDE Plasma (system + home config combined)
│   │   └── niri.nix         # Niri (wrapper-modules with perSystem)
│   ├── noctalia.nix         # Desktop shell/bar (wrapper-modules)
│   ├── skwd-wall.nix        # Wallpaper selector with systemd service
│   ├── helium.nix           # Helium browser (policies, Bitwarden, bookmarks)
│   ├── kitty.nix            # Terminal emulator
│   ├── zsh.nix              # Shell config
│   ├── spicetify.nix        # Spotify theming
│   ├── discord.nix          # Vesktop with transparency
│   ├── rain-effect.nix      # GLSL rain overlay (Odysseus, wlr-layer-shell bottom layer)
│   ├── controller.nix       # DualSense desktop nav daemon (Odysseus, Moonlight/Sunshine)
│   ├── sddm.nix             # SDDM video login theme
│   ├── base.nix             # Common packages and settings
│   ├── grub.nix             # GRUB with multi-system boot menu
│   └── ... (audio, steam, sops, locale, polkit, etc.)
├── Resources/               # Static files (not Nix modules)
│   ├── Noctalia-Plugins/    # Custom Noctalia plugins
│   │   └── desktop-clock/   # Desktop clock widget
│   ├── Spicetify-Text-Theme/  # Spicetify CSS/color theme
│   ├── Zsh-Scripts/         # Shell helper scripts
│   ├── Terminal-Images/     # Fastfetch logos
│   └── Sddm/                # SDDM video background
└── Secrets/                 # Encrypted secrets
    ├── .sops.yaml           # Age key config
    └── secrets.yaml         # Encrypted values
```

### The Three Systems

| System | Desktop | Entry Point | Key Modules |
|--------|---------|-------------|-------------|
| **Sisyphus** | Hyprland | `Hosts/Sisyphus/system.nix` | hyprland (nixos+home), skwd-wall, noctalia, screenshot, spicetify |
| **Elektra** | KDE Plasma 6 | `Hosts/Elektra/system.nix` | kde (plasma-manager), skwd-wall, thunar, spicetify, discord, screenshot |
| **Odysseus** | Niri | `Hosts/Odysseus/system.nix` | niri (wrapper-modules), noctalia (bar + launcher + power menu + notifications), skwd-wall, spicetify, discord, rain-effect |

Sisyphus + Elektra share with above: brave, helium
Odysseus only: helium (default browser, brave removed)

All systems share: base, grub, sddm, audio, locale, steam, polkit, sops, zsh, kitty, git, navi, starship, fastfetch

### Multi-Boot System

All three desktop environments are bootable from GRUB without rebuilding. The setup uses **named profiles** stored at `/nix/var/nix/profiles/system-profiles/`:

```
NixOS - System Select           <- GRUB submenu
  Sisyphus (Hyprland)
  Elektra (KDE Plasma 6)
  Odysseus (Niri)
Windows                         <- Detected by os-prober
```

**How it works:**
- Each system is built to a named profile (e.g., `-p sisyphus`)
- `grub.nix` has an activation script that generates `/boot/grub/custom-profiles.cfg`
- The script reads kernel, initrd, and kernel-params from each profile symlink
- GRUB sources this file via `extraConfig`

**Profile management:**
- Profiles are GC roots - garbage collection won't delete them
- Each profile maintains its own generations for rollback
- `nix-collect-garbage -d` removes old generations but keeps current builds
- Profiles at `/nix/var/nix/profiles/system-profiles/{sisyphus,elektra,odysseus}`

**Workflow:**
```bash
# Update the system you're working on
system-rebuild rock Odysseus

# Build another system without switching (safe)
system-rebuild rock Sisyphus --boot

# After rebuilding any system, the GRUB menu auto-updates on next switch
```

### SKWD Wallpaper Selector

All systems use **skwd-wall** - a wallpaper selector with matugen integration for Material You color schemes.

**Module:** `Modules/skwd-wall.nix`

**How it works:**
- Uses the `skwd-wall` flake input (github:liixini/skwd-wall)
- Installs the package which provides `skwd`, `skwd-wall`, and `skwd-daemon` executables
- Enables a systemd user service (`skwd-daemon`) that auto-starts with the graphical session
- Seeds `~/.config/skwd-wall/config.json` on first run

**Usage:**
```bash
# Toggle wallpaper selector (bind to Meta+W in all compositors)
skwd wall toggle

# Other commands
skwd wallpaper set /path/to/image.jpg
skwd wallpaper random
```

**Config file:** `~/.config/skwd-wall/config.json`
- `compositor`: "niri", "hyprland", or "kde"
- `monitor`: Target monitor (e.g., "DP-2")
- `paths.wallpaper`: Wallpaper directory
- `features.matugen`: Enable Material You color generation
- `matugen.schemeType`: Color scheme type (use `"scheme-tonal-spot"` for colorful Material You colors)
- `integrations`: Array of matugen template integrations (see below)

**Matugen → Noctalia Integration:**

When wallpaper changes, skwd-wall runs matugen to generate Material You colors. These colors are output to noctalia via a template integration:

1. **Template:** `~/.config/skwd-wall/data/matugen/templates/noctalia-colors.json`
   - Always synced by the activation script (Nix managed, not just seeded once)
   - **Surface colors are static** (neutral dark `#0a0a0a`, `#1a1a1a`) so bar background stays neutral
   - **Accent colors are dynamic** (primary, secondary, tertiary) from wallpaper for text/icons

2. **Integration config** in `config.json` (patched on every activation via jq):
   ```json
   "integrations": [
     {
       "name": "skwd-wall",
       "template": "quickshell-colors.json",
       "output": "colors.json"
     },
     {
       "name": "noctalia",
       "template": "noctalia-colors.json",
       "output": "~/.config/noctalia/colors.json",
       "reload": "noctalia-shell ipc call colorScheme refresh"
     }
   ]
   ```
   The `skwd-wall` built-in integration (`quickshell-colors.json`) is required for the wallpaper selector UI's own colors - without it the selector stays pink/default.

3. **Noctalia setting:** `colorSchemes.useWallpaperColors = true` in `Modules/noctalia.nix`

**Flow:** Wallpaper change → matugen generates colors → writes to `~/.config/noctalia/colors.json` → `reload` triggers `noctalia-shell ipc call colorScheme refresh` automatically

**Important:**
- Noctalia must use `outOfStoreConfig = "/home/rock/.config/noctalia"` in wrapper-modules. Without this, noctalia reads from the Nix store instead of the user config directory where matugen writes.
- Noctalia color refresh is now **automatic** via the `reload` field in the integration. No manual restart needed.
- Do NOT use `pkill -9 quickshell` to reload colors — it kills skwd-wall's quickshell UI too. Use `noctalia-shell ipc call wallpaper refresh` instead.
- **`colorScheme refresh` was removed** from noctalia's IPC in a newer version — the reload command is now `noctalia-shell ipc call wallpaper refresh`.
- **Zen integrations in config.json break matugen** — their output paths contain literal `\n` which corrupts the generated TOML. The activation script now strips them on every rebuild. Symptom: `matugen exited with exit status: 1` in `journalctl --user -u skwd-daemon`.
- The `matugen.schemeType` should be `"scheme-tonal-spot"` for colorful Material You colors and `matugen.mode` should be `"dark"`.
- The activation script patches the existing `config.json` via jq on every rebuild (not just first run), so integrations/reload fields stay correct even if the user edits the file.

**Troubleshooting skwd-wall:**

If thumbnails are blank, duplicated, or the cache seems stale:

```bash
# Full cache reset (nuclear option)
systemctl --user stop skwd-daemon
rm -f ~/.config/skwd-wall/.bootstrapped  # Forces fresh bootstrap
rm -rf ~/.cache/skwd-wall                 # Clears all cached data
systemctl --user start skwd-daemon
skwd wall toggle                          # Triggers cache rebuild
```

**Cache behavior:**
- `.bootstrapped` file in `~/.config/skwd-wall/` tells daemon setup is complete
- Daemon uses file modification times to detect changes - touch wallpaper files to force rebuild
- Thumbnail cache at `~/.cache/skwd-wall/wallpaper/thumbs/`
- Don't put files like `wallpaper.jpg` in the wallpaper directory - skwd-wall may create copies that cause duplicates

**Keybinds:**
- All systems: `Meta+W` toggles the wallpaper selector
- Niri: `Meta+D` uses Noctalia's app launcher (via IPC: `noctalia-shell ipc call launcher toggle`)

### Spicetify Theme

Custom **"text" theme** with matugen dynamic colors:
- JetBrains Mono font throughout
- ASCII art banners and pane border labels ("Nav", "Main", "Playing", etc.)
- Custom Unicode icons for player controls
- Transparent background for compositor transparency
- Hidden right sidebar
- Fixed connect bar positioning and clickability (CSS fixes in additionalCss)
- Marketplace app + adblock/shuffle + matugen-colors extensions

Theme files in `Resources/Spicetify-Text-Theme/`.

**Dynamic colors via matugen:**
Colors update live in Spotify the moment skwd-wall changes the wallpaper — no restart or rebuild needed.

**How it works:**
1. skwd-wall runs matugen on wallpaper change, writing two files:
   - `~/.config/spicetify/matugen-colors.json` — CSS custom property values (`--spice-*`) for runtime use
   - `~/.config/spicetify/Themes/text/color.ini` — `[Matugen]` section for bake-in on next rebuild
2. The `spicetify-live` integration in skwd-wall config has `"reload": "spotify-apply-colors"` — after matugen writes the JSON, skwd-wall runs this script automatically
3. `spotify-apply-colors` (in `home.packages` in `spicetify.nix`) connects to Spotify's CDP debug port (9222), reads `matugen-colors.json`, and injects each `--spice-*` variable via `Runtime.evaluate` → `document.documentElement.style.setProperty()`
4. Spotify must be launched with `--remote-debugging-port=9222` (set in both `spotify-startup` and `spotify-open` in `niri.nix`)
5. The baked-in `matugen-colors.js` extension hooks `Spicetify.Platform.History.listen` to re-apply the injected `<style>` element after SPA navigation wipes inline styles

**Why not `fs.watch` or `fetch()`?** Spotify uses CEF (Chromium Embedded Framework), not Electron. The renderer has no Node.js `require('fs')` and blocks all localhost HTTP connections. CDP is the only reliable way to inject JS into the running renderer from outside.

**Color scheme:** `colorScheme = "Matugen"` in `spicetify.nix` — the `[Matugen]` section in `color.ini` is the baked-in fallback (used until the first wallpaper change writes `matugen-colors.json`).

**Templates** (synced by `skwd-wall.nix` activation script):
- `spicetify-colors.json` → outputs `~/.config/spicetify/matugen-colors.json` (runtime CSS vars)
- `spicetify-text.ini` → outputs `~/.config/spicetify/Themes/text/color.ini` (rebuild-time color.ini)

**If colors stop updating:** check `journalctl --user -u skwd-daemon` for matugen errors and verify `~/.config/spicetify/matugen-colors.json` is being written on wallpaper change.

### Rain Effect Overlay

GLSL rain-on-glass overlay rendered on the Wayland `bottom` layer — above the wallpaper, below all windows. Fully independent of skwd-wall; changing wallpaper while rain is active has no effect.

**Module:** `Modules/rain-effect.nix` (Odysseus only)

**How it works:**
- C program using `wlr-layer-shell` (`ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM`) + EGL + OpenGL ES 2
- Empty input region so all mouse/keyboard events pass through
- `exclusive_zone = -1` so it doesn't push other surfaces
- Creates one layer surface per monitor (handles dual-monitor setup)
- Shader: adapted "Heartfelt" by Martijn Steinrucken (BigWings) 2017 — rain-on-glass drops with trails, static droplets, specular highlights. CC BY-NC-SA 3.0.
- Binary compiled at Nix build time via `stdenv.mkDerivation` with `wayland-scanner` generating xdg-shell + wlr-layer-shell protocol bindings

**Usage:**
```bash
rain-toggle          # toggle on/off
rain-toggle on       # explicit on (for weather automation)
rain-toggle off      # explicit off
```
Keybind: `Mod+Shift+R` in Niri

**Future:** auto-trigger based on weather API (Noctalia has Sydney weather enabled)

**Shader tuning notes:**
- `rain` variable (0.0–1.0) controls intensity — currently `0.7`
- `u_time*0.2` controls animation speed
- Alpha: `dropA*0.50 + trailA*0.20*(1.0-dropA) + spec*0.35*dropA` — lower `dropA` multiplier for subtler drops
- Drop color: `mix(vec3(0.52,0.70,0.94), vec3(0.72,0.86,1.00), dropA)` — light blue water tones

### Discord Setup

Uses Vesktop (Discord + Vencord) instead of regular Discord for:
- Better Wayland/Linux support
- CSS injection for transparent theme
- Native transparency support

**Cache clearing:** The module clears Vesktop cache directories (`Cache`, `Code Cache`, `GPUCache`) on each rebuild to prevent EPIPE errors. Login session is preserved.

Config in `Modules/discord.nix`.

### KDE Plasma (Elektra)

Configured via `plasma-manager` in `Modules/Desktops/kde.nix`:

**Panel:** Bottom of DP-2 (primary monitor), floating, height 32
- Widgets: Kickoff, Pager, Icon Tasks, Separator, System Tray, Digital Clock

**Keybinds:**
| Key | Action |
|-----|--------|
| `Meta+Q` | Close window |
| `Meta+Shift+F` | Fullscreen |
| `Meta+A` | Overview |
| `Meta+Return` | Kitty terminal |
| `Meta+E` | Thunar file browser |
| `Meta+F` | Brave browser |
| `Meta+W` | SKWD wallpaper selector |

**Monitor config:** Plasma-manager doesn't support `displays` option. Configure monitors manually in KDE System Settings on first boot (persists after).

### Niri (Odysseus)

Niri is a scrollable-tiling Wayland compositor. Configured via wrapper-modules in `Modules/Desktops/niri.nix`.

**Current version:** 26.04 (via niri-flake)

**Key features:**
- Scrollable tiling - windows arranged in infinite horizontal strip
- Blur support (new in 26.04) - can be enabled in window rules
- Custom window open/close animations using GLSL shaders (fluid/dissolve effect)
- Per-window transparency via opacity rules

**Layout settings:**
- `layout.gaps = 4` - Gap between windows
- `layout.border.width = 2` with `#333333` color
- `layout.focus-ring.width = 0` - Disabled, using border instead
- `layout.default-column-width.proportion = 1.0` - Windows fill monitor width

**Window rules** (in `extraConfig` as raw KDL):
- Global: `corner-radius 12`, `clip-to-geometry true`
- Opacity: spotify 0.90, vesktop 0.85, helium 0.85, codium 0.80, thunar 0.90
- Floating: pavucontrol, Picture-in-Picture
- Spotify opens on HDMI-A-1 (secondary monitor)

**Keybinds:**
| Key | Action |
|-----|--------|
| `Mod+Return` | Kitty terminal |
| `Mod+E` | Thunar |
| `Mod+F` | Helium browser |
| `Mod+D` | Noctalia app launcher |
| `Mod+W` | SKWD wallpaper selector |
| `Mod+Q` | Close window |
| `Mod+A` | Toggle overview |
| `Mod+V` | Toggle floating |
| `Mod+Shift+F` | Fullscreen |
| `Mod+Shift+Delete` | Noctalia power menu |
| `Mod+Left/Right` | Focus column |
| `Mod+Up/Down` | Focus workspace |
| `Mod+Shift+S` | Screenshot region to clipboard |
| `Mod+S` | Screenshot full screen to clipboard |

**Startup sequence:**
1. Noctalia shell launches first for instant visual feedback
2. D-Bus environment setup runs in background
3. Spotify launches via `spotify-startup` (3-second delay, opens to Liked Songs)

**Spotify launcher:** Two scripts in `environment.systemPackages` handle Spotify launch:
- `spotify-startup` — used by niri `spawn-at-startup`, sleeps 3s then launches with GPU flags + `--uri` for playlist
- `spotify-open` — used by the app launcher `.desktop` entry, no sleep, handles fresh launch (`--uri`) and already-running (D-Bus MPRIS `OpenUri`)

The `spotify` binary is never replaced (avoids infinite recursion with spicetify's wrapper). Instead, `home-manager.users.rock.xdg.desktopEntries.spotify` overrides the `.desktop` file to call `spotify-open %U`.

**Monitor config** (in `extraConfig`):
```kdl
output "DP-2" { position x=0 y=1080 }
output "HDMI-A-1" { position x=320 y=0 }
```

### Starship Prompt

Custom Gruvbox Rainbow theme in `Modules/starship.nix`:
- Sharp powerline arrows (`` U+E0B0, `` U+E0B2) for segment separators
- Format: `user @ hostname` → `directory` → `git` → `language` → `docker/conda`
- Command prompt uses `➜` arrow (green for success, red for error)
- Time display disabled
- Requires a Nerd Font (configured via kitty.nix: `FantasqueSansM Nerd Font Mono`)

**Important:** The powerline glyphs are special Unicode characters that can get stripped during editing. If the prompt renders with plain rectangles instead of arrows, check the hex values in starship.nix:
- Line 14 should contain `ee 82 b2` (U+E0B2) for start cap
- Transition lines should contain `ee 82 b0` (U+E0B0) for arrows

### Fastfetch

Custom system info display in `Modules/fastfetch.nix`:
- Uses kitty image protocol for logo display (`assets/terminal-logo-small.png`)
- Grouped sections: Hardware, Graphics, Software, Session
- Gruvbox color scheme with box-drawing borders

### Navi Cheats

Custom cheatsheet in `Modules/navi.nix` at `~/.config/navi/cheats/rhys.cheat`:
- **System Cleanup** - `nix-gc` (GC, store optimise, journal vacuum)
- **System Rebuild** - Interactive menu via `system-rebuild`
- **Git Sync** - `git-sync "message"` for quick commits
- **Edit Secrets** - `sops ~/Dots/Secrets/secrets.yaml` (decrypts in editor)

Also provides wrapper scripts:
- `system-rebuild` - Interactive or CLI system rebuild
- `git-sync` - Stash, pull --rebase, push workflow
- `nix-gc` - Full cleanup (GC + optimise + journal + podman prune)

### Dendritic Module Pattern

Each module is **self-contained** - it includes both NixOS system config AND Home Manager user config in one file. This follows the dendritic pattern where related code is co-located.

**Example module structure:**
```nix
{ ... }: {
  flake.nixosModules.kitty = { activeUser, pkgs, ... }: {
    # System config (if needed)
    # ...

    # Home Manager config embedded
    home-manager.users.${activeUser} = {
      programs.kitty = {
        enable = true;
        # ...
      };
    };
  };
}
```

**How import-tree works:**
- `(inputs.import-tree ./Hosts)` - auto-imports all `*.nix` files in Hosts/
- `(inputs.import-tree ./Modules)` - auto-imports all `*.nix` files in Modules/

Each module defines `flake.nixosModules.{name}`. Host configs only need one import list - no separate `homeModules` imports.

### wrapper-modules Pattern

Niri and Noctalia use `wrapper-modules` to create wrapped packages with settings baked in. This avoids module conflicts and follows the pattern from the noctalia documentation.

**Structure:**
```nix
{ self, inputs, ... }: {
  flake.nixosModules.example = { pkgs, ... }: {
    programs.example.package = self.packages.${pkgs.stdenv.hostPlatform.system}.wrappedExample;
  };

  perSystem = { pkgs, lib, self', ... }: {
    packages.wrappedExample = inputs.wrapper-modules.wrappers.example.wrap {
      inherit pkgs;
      settings = { /* config here */ };
    };
  };
}
```

**Key differences from direct module imports:**
- Settings use wrapper-modules syntax (e.g., `spawn-sh` instead of `spawn`, `Mod` instead of `Super`)
- Actions use `_: {}` instead of `null` for empty arguments
- Package is provided via `package = inputs.flake.packages.${system}.default` if not in nixpkgs
- Use `extraConfig` for raw KDL that can't be expressed in Nix (e.g., niri window-rules with `match` syntax)

**Niri-specific notes:**
- Window rules require `extraConfig` with raw KDL because the `match app-id="pattern"` syntax doesn't translate correctly from Nix
- Monitor/output config uses `extraConfig` for positioning
- Niri config lives entirely in `Modules/Desktops/niri.nix`
- Hot corners disabled via `gestures { hot-corners { off } }` in extraConfig
- Rounded corners (`corner-radius = 12`) with thin dark border (`width = 2`, `#333333`), using `clip-to-geometry` and `geometry-corner-radius` in window rules
- Border config uses hyphenated syntax: `layout.border.active-color` and `layout.border.inactive-color` (not nested objects)
- Focus ring disabled (`layout.focus-ring.width = 0`), using border instead for window outlines
- Cursor theme configured via `cursor.xcursor-theme` and `cursor.xcursor-size` in wrapper-modules settings
- Window opacity rules for transparency (spotify 0.90, vesktop 0.85, etc.)
- Spotify opens to Liked Songs on launch via `LIKED_SONGS="spotify:collection:tracks"` in both `spotify-startup` and `spotify-open` scripts. Fresh launch uses `--uri` flag (processed before UI renders, most reliable). Already-running uses `dbus-send --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.OpenUri string:URI`. To change the target, update `LIKED_SONGS` in both scripts in `niri.nix`. If `spotify:collection:tracks` stops working, replace with a real `spotify:playlist:ID` URI (right-click playlist → Share → Copy Spotify URI).
- Spotify binary is never wrapped directly — spicetify owns the `spotify` binary. Instead, `spotify-open` and `spotify-startup` call `spotify` (spicetify's version) with extra flags. The app launcher uses a custom `.desktop` entry (`xdg.desktopEntries.spotify`) pointing to `spotify-open`.
- Power menu keybind (`Mod+Shift+Delete`) triggers Noctalia's session menu via IPC: `noctalia-shell ipc call sessionMenu toggle`
- App launcher keybind (`Mod+D`) uses Noctalia: `noctalia-shell ipc call launcher toggle`
- Wallpaper keybind (`Mod+W`) uses skwd-wall: `skwd wall toggle`
- `kdePackages.qttools` provides `qdbus6` for D-Bus calls to Spotify
- Startup optimization: D-Bus environment commands run in background (`sh -c '... &'`) so visual elements load first
- Niri binary is wrapped (via `pkgs.symlinkJoin`) to add `providedSessions` passthru — no startup delay. The old `sleep 2` was removed because it applied to `niri msg` too, causing every IPC call (and all app launches from Noctalia) to take 2 seconds.

### Noctalia Desktop Shell

Noctalia is the desktop shell used on Sisyphus (Hyprland) and Odysseus (Niri). Configured via wrapper-modules in `Modules/noctalia.nix`.

**Key settings:**
- Bar: top position, floating with 8px margins, capsule style, 70% background opacity
- Widgets: ControlCenter, Workspace, MediaMini, Volume, Network, Bluetooth, Clock, Tray
- Color scheme: Dynamic from wallpaper (`useWallpaperColors = true`) via skwd-wall matugen integration
- Desktop widgets enabled on both monitors
- `outOfStoreConfig = "/home/rock/.config/noctalia"` - Required for matugen colors to work (reads from user dir, not Nix store)

**IPC Commands:**
```bash
# App launcher
noctalia-shell ipc call launcher toggle

# Power/session menu
noctalia-shell ipc call sessionMenu toggle

# List all available IPC targets
noctalia-shell ipc show
```

**Note:** The IPC target for the app launcher is `launcher`, not `appLauncher`.

**Desktop Clock Plugin:**
Custom plugin at `Resources/Noctalia-Plugins/desktop-clock/`:
- `manifest.json` - Plugin metadata
- `DesktopWidget.qml` - Clock widget showing day, date, and time
- `Anurati-Regular.otf` - Futuristic geometric display font (bundled with plugin)
- Uses **Anurati** font loaded via QML `FontLoader` from the plugin directory
- Anurati only has uppercase letters (A-Z), so numbers/symbols fall back to system font
- Black text outline (`style: Text.Outline`) for visibility on any wallpaper
- Centered on both monitors with no background

**Declarative Widget Configuration:**
Because `outOfStoreConfig` is used (required for matugen colors), noctalia ignores the Nix-generated widget config and reads from user config files. A home-manager activation script handles setup on each rebuild:

1. Creates `~/.config/noctalia/` directory structure if missing (fresh install)
2. Creates default `settings.json` and `plugins.json` if they don't exist
3. Patches config to enable the desktop-clock widget on both monitors
4. Syncs plugin files (QML, font, manifest) from nix store to `~/.config/noctalia/plugins/desktop-clock/`

This ensures the clock widget works automatically on fresh installs without manual configuration.

**Custom Font Packaging:**
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

**Plugin development notes:**
- Plugins must extend `DraggableDesktopWidget`
- All dimensions must be multiplied by `widgetScale` for proper scaling
- Use `Color.mOnSurface` and `Color.mOnSurfaceVariant` for theme-aware colors
- Custom fonts should be bundled in the plugin directory and loaded via `FontLoader { source: "FontName.otf" }`
- Plugin files are synced to `~/.config/noctalia/plugins/<name>/` by the activation script
- Restart noctalia after changes: `pkill -9 quickshell; rm -rf /run/user/1000/quickshell; noctalia-shell &`

### Display Configuration

All systems use dual monitors:
- **DP-2**: 2560x1080 @ 144Hz (primary)
- **HDMI-A-1**: 1920x1080 @ 60Hz (secondary)

### Secrets Management (sops-nix)

Uses **sops-nix** with age keys for encrypted secrets. Secrets are decrypted at system activation and available at `/run/secrets/`.

**Files:**
- `Secrets/.sops.yaml` - Lists age public keys and path rules
- `Secrets/secrets.yaml` - Encrypted secrets file (safe to commit)
- `Modules/sops.nix` - sops-nix module config

**Key locations:**
- PC key: `~/.config/sops/age/keys.txt`
- Apollo USB backup: `/run/media/rock/Apollo/keys/age-keys.txt`

**Adding a secret:**
1. Edit the encrypted file: `sops Secrets/secrets.yaml`
2. Add your secret: `my-api-key: "the-actual-key"`
3. Save and exit (auto re-encrypts)
4. Reference in `sops.nix`:
   ```nix
   sops.secrets.my-api-key = { };
   ```
5. Available at `/run/secrets/my-api-key` after rebuild

**Editor:** `EDITOR` is set to `codium --wait` in `zsh.nix`, so sops opens VSCodium.

**Useful commands:**
```bash
# Edit secrets (decrypts in editor, re-encrypts on save)
sops Secrets/secrets.yaml

# Rotate keys (after adding new key to .sops.yaml)
sops updatekeys secrets/secrets.yaml

# View decrypted secrets (read-only)
sops -d secrets/secrets.yaml
```

### Helium Browser

Chromium-based privacy browser (de-googled, built on ungoogled-chromium) used alongside Brave. Configured in `Modules/helium.nix`.

**Flake input:** `github:amaanq/helium-flake` (not in nixpkgs)

**App-id on Wayland:** `helium` (used for Niri opacity rule)

**What the module manages declaratively:**

- **Package** — wrapped binary via `pkgs.symlinkJoin` + `makeWrapper` (not installed directly)
- **Dark theme** — custom Chrome theme extension (`helium-dark-theme` derivation) loaded via `--load-extension`. Sets exact colors for frame, toolbar, omnibox, and tabs. Loaded alongside Bitwarden as a comma-separated `--load-extension` list. If the theme doesn't apply after rebuild, go to `helium://settings/appearance` and reset the theme there once.
- **Bitwarden** — loaded via `--load-extension` pointing to a Nix-fetched derivation (ungoogled-chromium blocks Google's CWS, so `force_installed` doesn't work). The extension zip is fetched from Bitwarden's GitHub releases, source maps stripped, and Bitwarden's RSA public key injected into `manifest.json` so `--load-extension` assigns the correct extension ID (`nngceckbapebfimnlniiiahkandclblb`) instead of a random one. Key was extracted from the signed CRX and verified by computing SHA256 → extension ID.
- **Bitwarden pinned** — `ExtensionSettings` policy with `toolbar_pin = "force_pinned"` targets the correct ID
- **Bookmarks** — two managed folders (Work: Outlook, Personal: GitHub/Reddit/ProtonDB) via `ManagedBookmarks` policy
- **New tab page** — blank via `NewTabPageLocation = "about:blank"`

**Theme colors** (in `helium-dark-theme` derivation manifest):
- `frame`: `[42, 42, 42]` — tab strip background
- `toolbar`: `[48, 48, 48]` — address bar area
- `omnibox_background`: `[38, 38, 38]` — search bar input (darker than toolbar for depth)
- `tab_text` / `tab_background_text`: `[230]` / `[150]` — active/inactive tab text
- To adjust: edit the color arrays in `helium-dark-theme` inside `helium.nix` and rebuild
- GTK/QT theme options in settings do nothing useful on Niri without a GTK theme configured — use the custom theme extension instead

**Policy setup:**
- Policies go in `/etc/chromium/policies/managed/helium.json` via `environment.etc`
- Helium reads from `/etc/chromium/policies/managed/` (standard ungoogled-chromium path)
- Verify policies loaded at `helium://policy` — all entries should show Status: OK
- Bitwarden extension ID: `nngceckbapebfimnlniiiahkandclblb` (locked by key in manifest)
- Bitwarden version is pinned — update URL + hash in `helium.nix` when upgrading. The RSA key stays the same across versions.
- `BookmarksBarEnabled` policy removed — Helium sets this internally, adding it causes a policy Error

**Transparency:**
- Niri opacity rule (`app-id="^helium$"`, opacity 0.96) handles compositor-level transparency
- **Niri opacity rule requires logout/login** — Niri's config is baked into the wrapper-modules binary, not hot-reloaded
- Wallpaper colors bleed through at lower opacity values — keep at 0.95+ to avoid tinting web content
- No CSS-level transparency (Chromium doesn't support userChrome equivalent)

**ManagedBookmarks format:**
```nix
ManagedBookmarks = [
  { toplevel_name = "Bookmarks"; }          # parent folder name on bar
  { name = "Work"; children = [
    { name = "Outlook"; url = "..."; }
  ]; }
  { name = "Personal"; children = [
    { name = "GitHub"; url = "..."; }
  ]; }
];
```
All managed bookmarks live under one parent folder on the bar — can't split into two independent top-level folders via policy.

**New modules need `git add`:**
Import-tree only sees git-tracked files. A new `*.nix` file in `Modules/` will be silently ignored (missing from `self.nixosModules`) until staged with `git add`.

### Flake Inputs of Note

- `nixpkgs@nixos-25.11` (stable) and `nixpkgs-unstable`
- `home-manager@release-25.11`
- `flake-parts` + `import-tree` - Modular flake organization
- `wrapper-modules` - Wraps packages with settings baked in (used for niri, noctalia)
- `noctalia` - Custom desktop shell with widgets/bar/launcher
- `skwd-wall` - Wallpaper selector with matugen integration (bundles quickshell + awww)
- `helium` - Helium browser (github:amaanq/helium-flake, not in nixpkgs)
- `spicetify-nix` - Declarative Spotify theming
- `plasma-manager` - KDE Plasma declarative config
- `niri` - Scrollable tiling Wayland compositor (niri-flake)
- `silentSDDM` - Login screen theme
- `nix-citizen` / `nix-gaming` - Gaming packages (Star Citizen, Proton)
- `sops-nix` - Encrypted secrets management with age keys

### Game Streaming (Sunshine + Moonlight + Tailscale)

Odysseus runs **Sunshine** as a game streaming host, accessible remotely via **Tailscale**, streamed to an Android phone using **Moonlight**.

**Modules:**
- `Modules/sunshine.nix` — Sunshine user service (Odysseus only)
- `Modules/tailscale.nix` — Tailscale VPN (Odysseus only, auth key via sops)
- `Modules/controller.nix` — DualSense desktop navigation daemon (Odysseus only)

**How it works:**
- Sunshine runs as a systemd user service (`systemctl --user start sunshine`)
- `capSysAdmin = true` enables KMS display capture on Wayland
- `hardware.uinput.enable = true` allows Sunshine to send virtual controller/keyboard/mouse input to Linux
- `openFirewall = true` + `trustedInterfaces = [ "tailscale0" ]` means Sunshine is reachable over Tailscale without extra firewall rules
- Tailscale auth key is stored in sops (`secrets.yaml` → `tailscale-auth-key`) and auto-authenticates on rebuild

**Setup notes:**
- Sunshine is a **user service** — it doesn't auto-start until login. Start manually with `systemctl --user start sunshine` if needed after boot
- Sunshine web UI: `https://localhost:47990` (self-signed cert, accept the warning) — set credentials here on first run
- Tailscale IP: `100.119.193.77` (check current IP with `tailscale ip`)
- Moonlight on Android: add PC manually by IP (mDNS auto-discovery doesn't work over Tailscale tunnels) — Moonlight saves it permanently
- Pairing: Moonlight shows PIN on phone → enter it in Sunshine web UI → paired permanently
- DualSense controller: pair to Android via Bluetooth, Sunshine translates inputs to uinput on the PC side

**Display selection:**
In Sunshine web UI → Configuration → Audio/Video → Display Number. Available outputs:
- `card1-DP-2` — 2560x1080 @ 144Hz (primary ultrawide)
- `card1-HDMI-A-1` — 1920x1080 @ 60Hz (secondary, better aspect ratio for phone streaming)

**sops.nix path fix:**
`defaultSopsFile` must use `../Secrets/secrets.yaml` (one level up from `Modules/`), NOT `../../` which resolves to `/nix/store/Secrets` and breaks pure evaluation.

**DualSense controller desktop navigation:**

`Modules/controller.nix` runs a Python evdev daemon (`controller-mapper`) as a systemd user service. It reads Sunshine's virtual uinput gamepad and emits events via a virtual UInput keyboard device.

The DualSense touchpad handles mouse movement natively through Sunshine — no cursor emulation in the daemon.

**Button mapping (desktop mode only):**

| Input | Action |
|---|---|
| Left stick | Arrow keys (menu/list navigation, with auto-repeat) |
| D-Pad | `Super+Arrow` → Niri window/workspace focus |
| X (South) | Enter |
| Circle (East) | Escape |
| Triangle (North) | `niri msg action close-window` |
| Square (West) | `noctalia-shell ipc call launcher toggle` |
| L1 | `skwd wall toggle` |
| R1 | `niri msg action toggle-overview` |
| Options | `noctalia-shell ipc call sessionMenu toggle` |
| PS button | Toggle desktop mode on/off |

**Desktop mode toggle:**
- Default: **on** (ready for desktop nav when Moonlight connects)
- PS button toggles to **game mode** — all mappings suppressed so controller input goes cleanly to the game
- A `notify-send` notification confirms the mode change

**Implementation notes:**
- Uses Python `evdev` + `UInput` — no process spawning per frame, direct kernel input writes
- `find_gamepad()` retries every 3s so the service stays alive when no Moonlight client is connected
- Left stick auto-repeat: fires immediately on deflection, 400ms initial delay, then repeats every 120ms (dominant axis wins to prevent diagonal misfires)
- D-Pad Super+Arrow is run in a thread to avoid blocking the event loop during the 50ms key hold
- Requires user in `input` group (read `/dev/input/event*`) and `uinput` group (write `/dev/uinput`)
- `hardware.uinput.enable` (from `sunshine.nix`) already provides udev rules for the `uinput` group
