# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build and switch to a system configuration
sudo nixos-rebuild switch --flake .#rock-Sisyphus   # Hyprland desktop
sudo nixos-rebuild switch --flake .#rock-Elektra    # KDE Plasma 6
sudo nixos-rebuild switch --flake .#rock-Odysseus   # Niri compositor

# Test a configuration without switching
sudo nixos-rebuild test --flake .#rock-Sisyphus

# Build without activating (for dry-run validation)
sudo nixos-rebuild build --flake .#rock-Sisyphus

# Update flake inputs
nix flake update
```

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
    │   ├── hyprland.nix     # Hyprland WM config (native HM module)
    │   ├── kde.nix          # Plasma config via plasma-manager
    │   ├── noctalia.nix     # Desktop shell (wrapper-modules + home packages)
    │   ├── skwd.nix         # Custom wallpaper manager (Quickshell)
    │   ├── kitty.nix, brave.nix, git.nix, vscodium.nix, etc.
    │   └── screenshot.nix, navi.nix, gtk.nix, fastfetch.nix
    └── nixos/               # NixOS system modules
        ├── base.nix         # Common packages and settings
        ├── grub.nix         # GRUB with Yorha theme
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
| **Sisyphus** | Hyprland | `hosts/Sisyphus/system.nix` | hyprland (nixos+home), skwd, noctalia, screenshot |
| **Elektra** | KDE Plasma 6 | `hosts/Elektra/system.nix` | kde (plasma-manager), screenshot |
| **Odysseus** | Niri | `hosts/Odysseus/system.nix` | niri (wrapper-modules), noctalia |

All systems share: base, grub, sddm, audio, locale, steam, polkit, zsh, kitty, brave, git, navi

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
- Monitor/output config is omitted (niri auto-detects); cursor theme set via environment variables
- Niri config lives entirely in `modules/nixos/niri.nix` (no separate home module)

### Display Configuration

All systems use dual monitors:
- **DP-2**: 2560x1080 @ 144Hz (primary)
- **HDMI-A-1**: 1920x1080 @ 60Hz (secondary)

### Flake Inputs of Note

- `nixpkgs@nixos-25.11` (stable) and `nixpkgs-unstable`
- `home-manager@release-25.11`
- `flake-parts` + `import-tree` - Modular flake organization
- `wrapper-modules` - Wraps packages with settings baked in (used for niri, noctalia)
- `noctalia` - Custom desktop shell with widgets
- `quickshell` - QML framework for SKWD
- `plasma-manager` - KDE Plasma declarative config
- `niri` - Tiling compositor (niri-flake)
- `silentSDDM` - Login screen theme
- `nix-citizen` / `nix-gaming` - Gaming packages (Star Citizen, Proton)
