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

The `system-rebuild` helper (defined in `modules/home/zsh/scripts/zsh-helpers.sh`) supports both interactive and CLI modes. Uses named profiles (`-p ${system}`) so each desktop environment has its own profile at `/nix/var/nix/profiles/system-profiles/`.

**Note:** The script uses `echo -n` + `read` (not `read -p`) for zsh compatibility.

## Architecture

This is a NixOS Flake-based dotfiles repository using **flake-parts** + **import-tree** for automatic module discovery. Manages three desktop environment configurations for user `rock` on AMD/Wayland hardware.

### Directory Structure

```
flake.nix                    # Entry point using flake-parts + import-tree
├── hosts/                   # System configurations (auto-imported)
│   ├── Sisyphus/            # Hyprland desktop
│   │   └── system.nix       # NixOS config + Home Manager setup
│   ├── Elektra/             # KDE Plasma 6
│   │   └── system.nix
│   └── Odysseus/            # Niri compositor
│       └── system.nix
└── modules/                 # Reusable modules (auto-imported)
    ├── flake-outputs.nix    # Custom flake option for homeModules
    ├── home/                # Home Manager modules
    │   ├── zsh/             # Shell config with helper scripts
    │   ├── starship.nix     # Starship prompt (Gruvbox Rainbow theme, requires Nerd Font)
    │   ├── fastfetch.nix    # System info display with custom logo
    │   ├── hyprland.nix     # Hyprland WM config (native HM module)
    │   ├── kde.nix          # Plasma config via plasma-manager
    │   ├── noctalia.nix     # Desktop shell/bar (wrapper-modules)
    │   ├── skwd.nix         # SKWD shell (launcher, wallpaper selector, matugen theming)
    │   ├── skwd-wallpaper.nix # SKWD wallpaper-only module (for Hyprland)
    │   ├── spicetify.nix    # Spotify theming with static blue color scheme
    │   ├── discord.nix      # Vesktop (Discord + Vencord) with transparency
    │   ├── kitty.nix, brave.nix, git.nix, vscodium.nix, etc.
    │   └── screenshot.nix, navi.nix, gtk.nix
    └── nixos/               # NixOS system modules
        ├── base.nix         # Common packages and settings
        ├── grub.nix         # GRUB with Yorha theme + multi-system boot menu
        ├── sddm/            # SDDM with SilentSDDM video theme
        ├── audio.nix        # Pipewire audio
        ├── steam.nix        # Gaming (Steam, Proton, gamemode)
        ├── hyprland.nix     # Hyprland system config (native NixOS)
        ├── kde.nix          # KDE system config
        ├── niri.nix         # Niri config (wrapper-modules with perSystem)
        ├── thunar.nix       # File manager + icon themes
        ├── locale.nix       # Australia/Sydney, en_AU
        └── polkit.nix       # Polkit + authentication agent
```

### The Three Systems

| System | Desktop | Entry Point | Key Modules |
|--------|---------|-------------|-------------|
| **Sisyphus** | Hyprland | `hosts/Sisyphus/system.nix` | hyprland (nixos+home), skwd-wallpaper, noctalia, screenshot, spicetify |
| **Elektra** | KDE Plasma 6 | `hosts/Elektra/system.nix` | kde (plasma-manager), skwd-wallpaper, thunar, spicetify, discord, screenshot |
| **Odysseus** | Niri | `hosts/Odysseus/system.nix` | niri (wrapper-modules), noctalia (bar + power menu + notifications), skwd (launcher + wallpaper only), spicetify (static blue theme), discord |

All systems share: base, grub, sddm, audio, locale, steam, polkit, zsh, kitty, brave, git, navi, starship, fastfetch

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

### SKWD Modules

Two variants of SKWD exist for different use cases:

- **skwd.nix** (full shell): Launcher, wallpaper selector, window switcher. Used on Niri with bar, power menu, and notifications disabled (Noctalia provides these). Clones from `github.com/liixini/skwd` to `~/.config/skwd/`. Controlled via **FIFO** at `$XDG_RUNTIME_DIR/skwd/cmd`.

- **skwd-wallpaper.nix** (wallpaper only): Just the wallpaper selector component. Used on Hyprland and KDE. Clones from `github.com/liixini/skwd-wall` to `~/.config/skwd-wall/`. Uses `awww` daemon for wallpapers (compositor-agnostic). Controlled via **quickshell IPC** (not FIFO): `quickshell ipc -p ~/.config/skwd-wall/daemon.qml call wallpaper toggle`.

**NixOS compatibility patches** (applied via `home.activation`):
- SKWD's app launcher searches standard Linux paths (`/usr/share/applications`) which don't exist on NixOS
- The module patches `scripts/python/build-app-cache` to add NixOS paths:
  - `/run/current-system/sw/share/applications/` (system packages)
  - `/etc/profiles/per-user/rock/share/applications/` (home-manager packages)
  - Corresponding icon paths in `/run/current-system/sw/share/icons/`
- Also patches `qml/launcher/AppLauncherService.qml` inotifywatcher for live updates

**App customization** (`~/.config/skwd/data/apps.json`):
- Keys match `.desktop` file `Name` fields (case-insensitive)
- Optional fields: `background` (image path), `icon` (nerd font glyph), `displayName`, `hidden`, `tags`
- Steam game thumbnails auto-generated from library cache when `paths.steam` is set in config.json

**Rebuild app cache manually:**
```bash
cd ~/.config/skwd && python3 scripts/python/build-app-cache
```

### Matugen Integration

SKWD uses **matugen** (v3.0.0+) to generate Material You color schemes from wallpapers. Colors update dynamically when wallpaper changes.

**How it works:**
1. When wallpaper changes, `scripts/bash/apply-static-wallpaper` runs matugen
2. Matugen reads templates from `~/.config/skwd/ext/matugen/templates/`
3. Generates color files based on `~/.cache/skwd/matugen-config.toml`
4. SKWD's `Colors.qml` watches `~/.cache/skwd/colors.json` for hot-reload

**Config files:**
- `~/.config/skwd/data/config.json` - contains `matugen.schemeType` and `integrations` paths
- `~/.cache/skwd/matugen-config.toml` - generated config mapping templates to output paths
- `~/.config/skwd/ext/matugen/config.toml.in` - template for matugen config

**NixOS fix** (in `skwd.nix`):
- Matugen doesn't expand `~` in paths - the `skwdFixMatugen` activation hook patches `config.toml.in` to use absolute paths
- Also expands `~` in all integration paths from `config.json` before writing to `matugen-config.toml`
- Removes empty template sections from generated config

**Important:** Matugen 3.0.0 removed the `--source-color-index` flag. SKWD scripts have been patched to not use this flag.

**Adding integrations:**
1. Add output path to `config.json` under `integrations` (e.g., `"kitty": "~/.config/kitty/colors.conf"`)
2. The `skwdFixMatugen` hook will include it in the generated matugen config
3. Template must exist in `ext/matugen/templates/`

**Test matugen manually:**
```bash
matugen -c ~/.cache/skwd/matugen-config.toml image -t scheme-fidelity ~/Pictures/Wallpapers/some-image.jpg
```

### Spicetify Theme

Custom **"text" theme** with static blue color scheme:
- JetBrains Mono font throughout
- ASCII art banners and pane border labels ("Nav", "Main", "Playing", etc.)
- Custom Unicode icons for player controls
- Transparent background for compositor transparency
- Hidden right sidebar
- Fixed connect bar positioning and clickability (CSS fixes in additionalCss)
- Marketplace app + adblock/shuffle extensions

Theme files in `modules/home/spicetify-text-theme/`.

**Note on dynamic colors:** Spicetify-nix bakes themes into the Nix store at build time, so runtime color updates (e.g., from matugen) don't work without a rebuild. The theme uses a static "Blue" color scheme defined in `color.ini`.

### Discord Setup

Uses Vesktop (Discord + Vencord) instead of regular Discord for:
- Better Wayland/Linux support
- CSS injection for transparent theme
- Native transparency support

**Cache clearing:** The module clears Vesktop cache directories (`Cache`, `Code Cache`, `GPUCache`) on each rebuild to prevent EPIPE errors. Login session is preserved.

Config in `modules/home/discord.nix`.

### KDE Plasma (Elektra)

Configured via `plasma-manager` in `modules/home/kde.nix`:

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

**SKWD on KDE:** Uses `skwd-wall` (the lightweight wallpaper-only variant) with quickshell IPC instead of the FIFO-based full SKWD shell. The daemon (`skwd-wall-daemon`) autostarts via XDG autostart entry, and `skwd-wallpaper-toggle` sends IPC commands: `quickshell ipc -p ~/.config/skwd-wall/daemon.qml call wallpaper toggle`.

**Monitor config:** Plasma-manager doesn't support `displays` option. Configure monitors manually in KDE System Settings on first boot (persists after).

### Starship Prompt

Custom Gruvbox Rainbow theme in `modules/home/starship.nix`:
- Sharp powerline arrows (`` U+E0B0, `` U+E0B2) for segment separators
- Format: `user @ hostname` → `directory` → `git` → `language` → `docker/conda`
- Command prompt uses `➜` arrow (green for success, red for error)
- Time display disabled
- Requires a Nerd Font (configured via kitty.nix: `FantasqueSansM Nerd Font Mono`)

**Important:** The powerline glyphs are special Unicode characters that can get stripped during editing. If the prompt renders with plain rectangles instead of arrows, check the hex values in starship.nix:
- Line 14 should contain `ee 82 b2` (U+E0B2) for start cap
- Transition lines should contain `ee 82 b0` (U+E0B0) for arrows

### Fastfetch

Custom system info display in `modules/home/fastfetch.nix`:
- Uses kitty image protocol for logo display (`assets/terminal-logo-small.png`)
- Grouped sections: Hardware, Graphics, Software, Session
- Gruvbox color scheme with box-drawing borders

### Navi Cheats

Custom cheatsheet in `modules/home/navi.nix` at `~/.config/navi/cheats/rhys.cheat`:
- **System Cleanup** - `nix-gc` (GC, store optimise, journal vacuum)
- **System Rebuild** - Interactive menu via `system-rebuild`
- **Git Sync** - `git-sync "message"` for quick commits

Also provides wrapper scripts:
- `system-rebuild` - Interactive or CLI system rebuild
- `git-sync` - Stash, pull --rebase, push workflow
- `nix-gc` - Full cleanup (GC + optimise + journal + podman prune)

### How import-tree Works

The flake uses `import-tree` for automatic module discovery:
- `(inputs.import-tree ./hosts)` - auto-imports all `*.nix` files in hosts/
- `(inputs.import-tree ./modules)` - auto-imports all `*.nix` files in modules/

Each module defines itself as `flake.nixosModules.{name}` or `flake.homeModules.{name}`, and system configs select which modules to enable.

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
- Niri config lives entirely in `modules/nixos/niri.nix` (no separate home module)
- Hot corners disabled via `gestures { hot-corners { off } }` in extraConfig
- Sharp corners (no border radius) with thin dark border (`width = 2`, `#333333`)
- Border config uses hyphenated syntax: `layout.border.active-color` and `layout.border.inactive-color` (not nested objects)
- Focus ring disabled (`layout.focus-ring.width = 0`), using border instead for window outlines
- Cursor theme configured via `cursor.xcursor-theme` and `cursor.xcursor-size` in wrapper-modules settings
- Window opacity rules for transparency (spotify 0.90, vesktop 0.85, etc.)
- `skwd-daemon` wrapper script in systemPackages for spawn-at-startup (niri needs single executable, not command with args)
- `skwd-wallpaper-restore` waits for SKWD FIFO to exist before restoring (polls every 100ms, no fixed sleep)
- Spotify wrapper uses D-Bus to navigate to Liked Songs: `qdbus6 org.mpris.MediaPlayer2.spotify / org.freedesktop.MediaPlayer2.OpenUri "spotify:collection:tracks"` (the `--uri` flag only works on fresh launch, not when Spotify is already running)
- Power menu keybind (`Mod+Shift+Delete`) triggers Noctalia's session menu via IPC: `noctalia-shell ipc call sessionMenu toggle`
- `kdePackages.qttools` provides `qdbus6` for D-Bus calls to Spotify
- Startup optimization: D-Bus environment commands run in background (`sh -c '... &'`) so visual elements load first
- Session startup delay: niri binary is wrapped with a 2-second sleep to allow SDDM/session to fully initialize before rendering

### Display Configuration

All systems use dual monitors:
- **DP-2**: 2560x1080 @ 144Hz (primary)
- **HDMI-A-1**: 1920x1080 @ 60Hz (secondary)

### Secrets Management (sops-nix)

Uses **sops-nix** with age keys for encrypted secrets. Secrets are decrypted at system activation and available at `/run/secrets/`.

**Files:**
- `.sops.yaml` - Lists age public keys and path rules
- `secrets/secrets.yaml` - Encrypted secrets file (safe to commit)
- `modules/nixos/sops.nix` - sops-nix module config

**Key locations:**
- PC key: `~/.config/sops/age/keys.txt`
- Apollo USB backup: wherever you store it

**Adding a secret:**
1. Edit the encrypted file: `sops secrets/secrets.yaml`
2. Add your secret: `my-api-key: "the-actual-key"`
3. Save and exit (auto re-encrypts)
4. Reference in `sops.nix`:
   ```nix
   sops.secrets.my-api-key = { };
   ```
5. Available at `/run/secrets/my-api-key` after rebuild

**Useful commands:**
```bash
# Edit secrets (decrypts in editor, re-encrypts on save)
sops secrets/secrets.yaml

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
- `noctalia` - Custom desktop shell with widgets/bar
- `quickshell` - QML framework for SKWD
- `awww` - Wayland wallpaper daemon (used by SKWD instead of swww)
- `spicetify-nix` - Declarative Spotify theming
- `plasma-manager` - KDE Plasma declarative config
- `niri` - Scrollable tiling Wayland compositor (niri-flake)
- `silentSDDM` - Login screen theme
- `nix-citizen` / `nix-gaming` - Gaming packages (Star Citizen, Proton)
- `sops-nix` - Encrypted secrets management with age keys
