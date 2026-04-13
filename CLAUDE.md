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

This is a NixOS Flake-based dotfiles repository managing three desktop environment configurations for user `rock` on AMD/Wayland hardware.

### System Hierarchy

```
flake.nix (entry point - defines mkSystem helper and all system configs)
├── Machines/Systems/{SystemName}/
│   ├── configuration.nix  # NixOS system config (services, packages, hardware settings)
│   └── home.nix           # Home Manager imports for this system
├── Machines/Users/rock/
│   └── hardware-configuration.nix  # Shared hardware config
├── Modules/
│   ├── Config-Manager-Modules/     # NixOS-level modules (Grub, SDDM, Steam, arrr media stack)
│   └── Home-Manager-Modules/       # User-level modules (Zsh, Kitty, Brave, Noctalia, SKWD)
└── Environments/
    ├── Hyprland/  # Hyprland WM config (keybinds, workspaces, animations)
    ├── KDE/       # Plasma 6 config (panel, shortcuts, themes)
    └── Niri/      # Niri compositor config (columns, rules, gaps)
```

### The Three Systems

| System | Desktop | Entry Points |
|--------|---------|--------------|
| **Sisyphus** | Hyprland | `Machines/Systems/Sisyphus/{configuration,home}.nix` + `Environments/Hyprland/` |
| **Elektra** | KDE Plasma 6 | `Machines/Systems/Elektra/{configuration,home}.nix` + `Environments/KDE/` |
| **Odysseus** | Niri | `Machines/Systems/Odysseus/{configuration,home}.nix` + `Environments/Niri/` |

### Key Module Patterns

- **flake.nix `mkSystem`**: Helper function that wires together system config, hardware config, and Home Manager
- **Home Manager modules** import environment configs and reusable modules (e.g., `home.nix` imports `../../Environments/Hyprland/Hyprland.nix`)
- **arrr.nix**: Docker-based media server stack (Jellyfin, Sonarr, Radarr, SABnzbd, etc.) using `virtualisation.oci-containers`
- **SKWD (Skwd.nix)**: Custom wallpaper manager using Quickshell - auto-clones from GitHub and generates config

### Display Configuration

All systems use dual monitors:
- **DP-2**: 2560x1080 @ 144Hz (primary)
- **HDMI-A-1**: 1920x1080 @ 60Hz (secondary)

### Flake Inputs of Note

- `nixpkgs@nixos-25.11` (stable) and `nixpkgs-unstable`
- `home-manager@release-25.11`
- `noctalia` - Custom desktop shell with widgets
- `quickshell` - QML framework for SKWD
- `plasma-manager` - KDE Plasma declarative config
- `niri` - Tiling compositor
- `nix-citizen` / `nix-gaming` - Gaming packages (Star Citizen, Proton)
