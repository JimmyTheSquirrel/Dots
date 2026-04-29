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
│   ├── zen.nix              # Zen browser (transparency, Bitwarden, matugen)
│   ├── kitty.nix            # Terminal emulator
│   ├── zsh.nix              # Shell config
│   ├── spicetify.nix        # Spotify theming
│   ├── discord.nix          # Vesktop with transparency
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
| **Odysseus** | Niri | `Hosts/Odysseus/system.nix` | niri (wrapper-modules), noctalia (bar + launcher + power menu + notifications), skwd-wall, spicetify, discord |

All systems share: base, grub, sddm, audio, locale, steam, polkit, sops, zsh, kitty, brave, zen, git, navi, starship, fastfetch

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
- Do NOT use `pkill -9 quickshell` to reload colors — it kills skwd-wall's quickshell UI too. Use `noctalia-shell ipc call colorScheme refresh` instead.
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

Custom **"text" theme** with static blue color scheme:
- JetBrains Mono font throughout
- ASCII art banners and pane border labels ("Nav", "Main", "Playing", etc.)
- Custom Unicode icons for player controls
- Transparent background for compositor transparency
- Hidden right sidebar
- Fixed connect bar positioning and clickability (CSS fixes in additionalCss)
- Marketplace app + adblock/shuffle extensions

Theme files in `Resources/spicetify-text-theme/`.

**Note on dynamic colors:** Spicetify-nix bakes themes into the Nix store at build time, so runtime color updates (e.g., from matugen) don't work without a rebuild. The theme uses a static "Blue" color scheme defined in `color.ini`.

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
- Opacity: spotify 0.90, vesktop 0.85, brave 0.85, zen 0.85, codium 0.80, thunar 0.90
- Floating: pavucontrol, Picture-in-Picture
- Spotify opens on HDMI-A-1 (secondary monitor)

**Keybinds:**
| Key | Action |
|-----|--------|
| `Mod+Return` | Kitty terminal |
| `Mod+E` | Thunar |
| `Mod+F` | Brave browser |
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
1. Niri binary is wrapped with 2-second sleep (allows SDDM to fully initialize)
2. Noctalia shell launches first for instant visual feedback
3. D-Bus environment setup runs in background
4. Spotify launches via `spotify-startup` (3-second delay, opens to Liked Songs)

**Spotify wrapper:** Custom wrapper at system level handles GPU sandbox issues and D-Bus navigation to Liked Songs on launch.

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
- Spotify wrapper uses D-Bus to navigate to Liked Songs: `qdbus6 org.mpris.MediaPlayer2.spotify / org.freedesktop.MediaPlayer2.OpenUri "spotify:collection:tracks"` (the `--uri` flag only works on fresh launch, not when Spotify is already running)
- Power menu keybind (`Mod+Shift+Delete`) triggers Noctalia's session menu via IPC: `noctalia-shell ipc call sessionMenu toggle`
- App launcher keybind (`Mod+D`) uses Noctalia: `noctalia-shell ipc call launcher toggle`
- Wallpaper keybind (`Mod+W`) uses skwd-wall: `skwd wall toggle`
- `kdePackages.qttools` provides `qdbus6` for D-Bus calls to Spotify
- Startup optimization: D-Bus environment commands run in background (`sh -c '... &'`) so visual elements load first
- Session startup delay: niri binary is wrapped with a 2-second sleep to allow SDDM/session to fully initialize before rendering

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

### Zen Browser

Firefox-based browser used as a secondary browser alongside Brave. Configured in `Modules/zen.nix`.

**Flake input:** `github:youwen5/zen-browser-flake` (not in nixpkgs)

**App-id on Wayland:** `zen` (used for Niri opacity rule)

**Profile location:** `~/.zen/` — profiles found via:
```bash
grep "^Path=" ~/.zen/profiles.ini | head -1 | cut -d= -f2-
```
**Important:** Profile directory name may contain spaces and capital letters (e.g., `m7n38kve.Default Profile`). Do NOT use `*.default*` glob — it won't match. Always use `grep` on `profiles.ini`.

**What the module manages declaratively:**

- **Bitwarden** — auto-installed via enterprise `~/.zen/policies/policies.json` (force_installed mode)
- **userChrome.css** — always synced on activation; makes toolbar/sidebar transparent
- **userContent.css** — always synced; targets `about:newtab`/`about:home`/`about:blank`
- **user.js** — prefs managed on every activation (stale entries removed then re-appended):
  - `toolkit.legacyUserProfileCustomizations.stylesheets = true` — enables userChrome/userContent
  - `widget.transparent-background = true` — ARGB window visual for compositor transparency
  - `browser.newtabpage.enabled = false` — disables Zen's new tab page
  - `browser.startup.homepage = "about:blank"` — blank/transparent start page
- **skwd-wall matugen** — patches skwd-wall `config.json` to add `zen` and `zen-content` integrations pointing to the profile's chrome directory

**Transparency setup:**
- Niri opacity rule (`app-id="^zen$"`, opacity 0.85) handles compositor-level transparency
- `widget.transparent-background` + CSS removes browser's own background colors
- New tab set to `about:blank` so the content area is transparent (Zen's custom new tab has its own solid background that can't be easily overridden)
- **Niri opacity rule requires logout/login** — Niri's config is baked into the wrapper-modules binary, not hot-reloaded

**Activation gotchas:**
- HM activation runs with `set -euo pipefail` — any `ls` glob that matches nothing returns exit code 1 and kills the script. Always add `|| true` to glob-based fallbacks
- Profile must exist (Zen launched at least once) before chrome files can be written
- After writing user.js, Zen must be fully quit and relaunched (not just window closed)

**New modules need `git add`:**
Import-tree only sees git-tracked files. A new `*.nix` file in `Modules/` will be silently ignored (missing from `self.nixosModules`) until staged with `git add`.

### Flake Inputs of Note

- `nixpkgs@nixos-25.11` (stable) and `nixpkgs-unstable`
- `home-manager@release-25.11`
- `flake-parts` + `import-tree` - Modular flake organization
- `wrapper-modules` - Wraps packages with settings baked in (used for niri, noctalia)
- `noctalia` - Custom desktop shell with widgets/bar/launcher
- `skwd-wall` - Wallpaper selector with matugen integration (bundles quickshell + awww)
- `zen-browser` - Zen browser (github:youwen5/zen-browser-flake, not in nixpkgs)
- `spicetify-nix` - Declarative Spotify theming
- `plasma-manager` - KDE Plasma declarative config
- `niri` - Scrollable tiling Wayland compositor (niri-flake)
- `silentSDDM` - Login screen theme
- `nix-citizen` / `nix-gaming` - Gaming packages (Star Citizen, Proton)
- `sops-nix` - Encrypted secrets management with age keys
