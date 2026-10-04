# Architecture — layout, module pattern, hosts, boot

## Repository layout

```
flake.nix            inputs + flake-parts; import-tree loads Hosts/ and Modules/
Hosts/<Host>/
  system.nix         flake.nixosConfigurations.<user>-<Host> = self.lib.mkHost { … }
  _hardware.nix      plain NixOS module (kernel modules, filesystems / facter)
  _disko.nix         plain NixOS module (disk layout), only on disko hosts
  facter.json        nixos-facter hardware report (Kit-Kat)
Modules/
  Core/              base, locale, audio, polkit, sops, nvidia, tailscale, flake-lib
  Boot/              grub, grub-celeste, plymouth, sddm
  Desktop/           desktop (shared GUI bits), niri, hyprland, noctalia, skwd, thunar, screenshot
  Shell/             zsh, starship, kitty, fastfetch, btop, git, navi, deploy-tools, sleepy-cat
  Apps/              helium, brave, vscodium, discord, spicetify
  Gaming/            steam, rpcs3, sunshine, wolf
  Server/            Asgard: the media stack split by service, home-assistant, marsbar
Resources/           static files the modules reference (fonts, themes, scripts, images)
Secrets/             sops-encrypted YAML (rules in the root .sops.yaml)
Claude/              topic docs
```

The folder a module lives in is only for humans. Every module is addressed by
the name it defines (`self.nixosModules.<name>`), never by its path, so moving a
file between folders changes nothing a host sees.

## The module pattern (dendritic)

Every `.nix` under `Modules/` and `Hosts/` is a **flake-parts module**, loaded
automatically by import-tree. A module defines `flake.nixosModules.<name>`, and
that one NixOS module carries both the system config and the Home Manager config
for the feature:

```nix
{ ... }: {
  flake.nixosModules.kitty = { activeUser, pkgs, ... }: {
    # system config, if any

    home-manager.users.${activeUser} = {
      programs.kitty.enable = true;
    };
  };
}
```

Rules that follow from that:

- **New files need `git add`.** import-tree reads the flake source, and a git
  flake only contains tracked files — an untracked module is silently ignored.
- **`_`-prefixed paths are skipped.** import-tree ignores any path containing
  `/_` (its filter is `hasInfix "/_"`). That is how a host gets plain NixOS
  modules next to its `system.nix` (`_hardware.nix`, `_disko.nix`) and how a
  folder gets private helpers (`Modules/Server/_lib.nix`), imported by path.
  Before this was used, every extra `.nix` in a host folder was read as a
  flake-parts module, which is why hardware config used to be inlined into
  `system.nix` behind a no-op `hardware.nix` stub.
- **One feature can span several files.** `flake.nixosModules.<name>` is a
  `deferredModule`, so several files may each define the same name and they
  merge — `Modules/Server/*.nix` all contribute to `nixosModules.server`.
- **`flake.lib.<name>`** is declared mergeable in `Modules/Core/flake-lib.nix`,
  so modules can export shared values there (matugen templates from btop / steam
  / discord, `sshKeys`, `mkHost`).

## Hosts and `mkHost`

```nix
{ self, ... }: {
  flake.nixosConfigurations.rock-Sisyphus = self.lib.mkHost {
    activeUser = "rock";
    hostName = "Sisyphus";
    stateVersion = "25.05";        # homeStateVersion defaults to the same
    modules = [ ./_hardware.nix self.nixosModules.base … ];
  };
}
```

`mkHost` (`Modules/Core/flake-lib.nix`) does what every host used to copy-paste:
`nixosSystem`, the Home Manager wiring, `networking.hostName` (as `mkDefault`, so
Apollo can use its tailnet name) and `system.stateVersion`. It also instantiates
**one** `pkgs-unstable` per host and passes it, with `inputs`, `activeUser` and
`hostName`, as a module argument to NixOS and Home Manager modules alike —
`import nixpkgs { … }` is not memoised, so modules importing it themselves cost a
full nixpkgs evaluation each.

| Host | Hardware | Disks | Boot |
|------|----------|-------|------|
| Sisyphus | `_hardware.nix` (hand-written, by UUID) | `_hardware.nix` | GRUB named profile `sisyphus` |
| Kit-Kat | `_hardware.nix` → nixos-facter `facter.json` | `_disko.nix` | GRUB (Celeste theme), default profile |
| Asgard | `_hardware.nix` (+ it87 fan driver) | `_disko.nix` (never run the format script) | systemd-boot, default profile |
| Apollo | live ISO | — | ISO |

nixos-facter + disko is the path for any new machine (see `Claude/deploy.md`).

## GRUB on Sisyphus — named profiles

`system-rebuild` builds Sisyphus into the named profile
`/nix/var/nix/profiles/system-profiles/sisyphus` (`nixos-rebuild -p sisyphus`).
`Modules/Boot/grub.nix` has an activation script that writes
`/boot/grub/custom-profiles.cfg` with a **"NixOS - System Select"** submenu
pointing at that profile's current kernel/initrd, and GRUB sources it via
`extraConfig`.

This machinery dates from when three desktops (Sisyphus, Odysseus, Elektra) were
boot profiles on this one disk. Sisyphus is the only one left, so the submenu has
a single entry. It is kept because the plain top-level "NixOS" entry boots the
*default* `system` profile, which `-p sisyphus` never updates — the submenu is
the entry that boots what you last built.

⚠️ Old `odysseus` / `elektra` profiles may still sit in `system-profiles/` holding
GC roots. Nothing builds them any more:
`sudo nix-env -p /nix/var/nix/profiles/system-profiles/<name> --delete-generations old`,
then remove the symlink.

## Plymouth boot splash

`Modules/Boot/plymouth.nix` — Sisyphus and Kit-Kat. Early KMS so the splash gets a
real framebuffer: the initrd GPU modules come from `my.plymouth.initrdGpuModules`
(default `[ "amdgpu" ]`; Kit-Kat sets the four nvidia modules in its host file,
because that option is declared here and `nvidia.nix` must stay importable without
plymouth). Theme `spinner`; kernel params `quiet splash loglevel=3
rd.udev.log_level=3`. NixOS ships `bgrt`, `spinner`, `fade-in`, `solar`, `tribar`;
for more, add `pkgs.adi1090x-plymouth-themes` to `boot.plymouth.themePackages`.

## wrapper-modules (niri)

`Modules/Desktop/niri.nix` uses `wrapper-modules` to build a niri package with
its config baked in (a `perSystem` package the NixOS module installs). Noctalia
does **not** — it uses the noctalia flake's own NixOS module.

- Settings use wrapper-modules syntax (`spawn-sh` vs `spawn`, `Mod` vs `Super`).
- Actions with no argument are `_: {}`, not `null`.
- Raw KDL that Nix can't express (window rules with `match`) goes in `extraConfig`.

## Remote machines

Kit-Kat and Asgard are separate hardware on the tailnet, deployed with
`nixos-rebuild --target-host` and the default system profile (no `-p`).
Apollo is an ISO (`nix build .#apollo-iso`). `system-rebuild` and the `apollo-*`
helpers handle all of it — see `Claude/deploy.md`.
