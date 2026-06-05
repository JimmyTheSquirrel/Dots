# Architecture — Multi-Boot, GRUB, Plymouth

## Multi-Boot System

All three desktop environments are bootable from GRUB without rebuilding. Uses **named profiles** at `/nix/var/nix/profiles/system-profiles/`:

```
NixOS - System Select           <- GRUB submenu
  Sisyphus (Niri)
  Elektra (KDE Plasma 6)
  Odysseus (Hyprland)
Windows                         <- Detected by os-prober
```

**How it works:**
- Each system is built to a named profile (e.g., `-p sisyphus`)
- `grub.nix` has an activation script that generates `/boot/grub/custom-profiles.cfg`
- The script reads kernel, initrd, and kernel-params from each profile symlink
- GRUB sources this file via `extraConfig`

**Profile management:**
- Profiles are GC roots — garbage collection won't delete them
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

## Plymouth Boot Splash

**Module:** `Modules/plymouth.nix` (Sisyphus only)

Displays an animated boot splash screen instead of kernel log text.

- `boot.initrd.kernelModules = [ "amdgpu" ]` — early KMS so Plymouth gets a real GPU framebuffer from the start (without this it renders in low-res VGA mode)
- `boot.plymouth.theme = "spinner"` — clean minimal spinner (built-in, no extra package needed)
- Kernel params: `quiet splash loglevel=3 rd.udev.log_level=3` — suppress kernel/udev log spam during boot

**Changing the theme:** NixOS ships `bgrt` (UEFI logo), `spinner`, `fade-in`, `solar`, `tribar` out of the box. For fancier themes add `pkgs.adi1090x-plymouth-themes` to `boot.plymouth.themePackages` and set `boot.plymouth.theme` to any theme name from that package.

## Dendritic Module Pattern

Each module is **self-contained** — it includes both NixOS system config AND Home Manager user config in one file.

```nix
{ ... }: {
  flake.nixosModules.kitty = { activeUser, pkgs, ... }: {
    # System config (if needed)

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
- `(inputs.import-tree ./Hosts)` — auto-imports all `*.nix` files in Hosts/
- `(inputs.import-tree ./Modules)` — auto-imports all `*.nix` files in Modules/

Each module defines `flake.nixosModules.{name}`. Host configs only need one import list — no separate `homeModules` imports.

**New modules need `git add`:** Import-tree only sees git-tracked files. A new `*.nix` file in `Modules/` will be silently ignored until staged.

## wrapper-modules Pattern

Niri and Noctalia use `wrapper-modules` to create wrapped packages with settings baked in.

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
- Use `extraConfig` for raw KDL that can't be expressed in Nix (e.g., niri window-rules with `match` syntax)
