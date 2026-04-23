# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

All systems share: base, grub, sddm, audio, locale, steam, polkit, sops, zsh, kitty, brave, git, navi, starship, fastfetch

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
   - Maps matugen color tokens to noctalia's format (`mPrimary`, `mOnPrimary`, etc.)
   - **Surface colors are static** (neutral dark `#0a0a0a`, `#1a1a1a`) so bar background stays neutral
   - **Accent colors are dynamic** (primary, secondary, tertiary) from wallpaper for text/icons

2. **Integration config** in `config.json`:
   ```json
   "integrations": [
     {
       "name": "noctalia",
       "template": "noctalia-colors.json",
       "output": "~/.config/noctalia/colors.json"
     }
   ]
   ```

3. **Noctalia setting:** `colorSchemes.useWallpaperColors = true` in `Modules/noctalia.nix`

**Flow:** Wallpaper change → matugen generates colors → writes to `~/.config/noctalia/colors.json` → restart noctalia to apply

**Important:**
- Noctalia must use `outOfStoreConfig = "/home/rock/.config/noctalia"` in wrapper-modules. Without this, noctalia reads from the Nix store instead of the user config directory where matugen writes.
- Noctalia does NOT hot-reload colors. After changing wallpaper, restart noctalia: `pkill -9 quickshell; rm -rf /run/user/1000/quickshell; noctalia-shell &`

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
- Bar: top position, capsule style, 70% background opacity
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

### Flake Inputs of Note

- `nixpkgs@nixos-25.11` (stable) and `nixpkgs-unstable`
- `home-manager@release-25.11`
- `flake-parts` + `import-tree` - Modular flake organization
- `wrapper-modules` - Wraps packages with settings baked in (used for niri, noctalia)
- `noctalia` - Custom desktop shell with widgets/bar/launcher
- `skwd-wall` - Wallpaper selector with matugen integration (bundles quickshell + awww)
- `spicetify-nix` - Declarative Spotify theming
- `plasma-manager` - KDE Plasma declarative config
- `niri` - Scrollable tiling Wayland compositor (niri-flake)
- `silentSDDM` - Login screen theme
- `nix-citizen` / `nix-gaming` - Gaming packages (Star Citizen, Proton)
- `sops-nix` - Encrypted secrets management with age keys
