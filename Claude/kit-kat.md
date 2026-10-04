# Kit-Kat — her machine

`Hosts/Kit-Kat/system.nix`, flake attr **`kitkat-Kit-Kat`**, login `kitkat`
("Kit Kat"), tailnet node `kit-kat`. Runs **Hyprland** (`Modules/Desktop/hyprland.nix`
— she is its only host now that Odysseus is retired) with noctalia and skwd v2, on
her own NVIDIA hardware.

This replaced **Elektra**, which was a KDE boot profile on *Sisyphus's own disk* —
all three local profiles shared one root UUID, one ESP and one swap, selected from
the GRUB "System Select" submenu. Elektra is therefore gone from
`Modules/Boot/grub.nix` and from the `system-rebuild` local menu, and
`kde.nix` / `Claude/kde.md` have since been deleted.

## Deploy / rebuild

```bash
apollo-deploy --vm-test kitkat-Kit-Kat   # prove the disk layout first
apollo-deploy kitkat-Kit-Kat             # first install — ERASES the disk
system-rebuild kitkat Kit-Kat            # every rebuild after that
```

See `Claude/deploy.md` for the Apollo USB side.

## Before the first install

1. **Confirm `installDisk`** in `Hosts/Kit-Kat/_disko.nix`. It is `/dev/nvme0n1`
   by default and it is the one value that must be right — everything on that
   device is destroyed. Check from the booted stick: `apollo-connect`, then
   `lsblk -o NAME,SIZE,MODEL`.
2. ~~Pre-generate her ssh host key~~ ✅ **DONE 2026-10-02.** The key lives at
   `~/.local/share/apollo/Kit-Kat/etc/ssh/ssh_host_ed25519_key` (outside the repo —
   this repo is public), its age identity
   `age185mqahaq2pac7szxvzkmlg5mdv4lcjgvtjkwu2ly24cc3mva3pssh4yuw2` is in `.sops.yaml`
   as `&kitkat`, and `Secrets/kit-kat.yaml` has been re-encrypted to include it.
   `apollo-deploy` now finds `~/.local/share/apollo/<Host>/` automatically and plants
   it — no env var to remember, and it refuses to proceed silently if it is missing.
3. ✅ `Hosts/Kit-Kat/facter.json` has been generated and committed. Without it the
   host still evaluates (and warns), but **must not be switched onto real hardware**
   — there is no microcode, no detected kernel modules and no firmware without it.

## Her password

From `Secrets/kit-kat.yaml` → `user-password-hash` →
`users.users.kitkat.hashedPasswordFile`. **Not** from `Secrets/secrets.yaml`.

That separation is deliberate: sops encrypts a whole file to every recipient, so
adding her machine to `secrets.yaml` would hand it `mullvad-wg-private-key`,
`cloudflare-tunnel`, `eclipse-ssh-key`, `anthropic-api-key` and
`tailscale-api-key` — an **admin** key that can rewrite tailnet ACLs and mint auth
keys. Her file holds one secret and nothing else.

With `users.mutableUsers` at its default (`true`), the hash is applied only when
the account is **created** — it is what gives a fresh install a working login.
After that `passwd` works and survives rebuilds, and editing the secret changes
nothing on an existing machine.

`rock` works the same way since 2026-10-03: the `sops` module sets his
`hashedPasswordFile` from `Secrets/secrets.yaml`'s `user-password-hash`, so a fresh
Sisyphus or Asgard gets his password, and the existing machines are untouched.

## Her look

| Piece | Module | Source |
|---|---|---|
| Greeter | `Modules/Boot/sddm.nix`, `my.sddm.theme = "women-umbrella"` | qylock `women-umbrella` (Totoro) |
| Bootloader | `Modules/Boot/grub-celeste.nix` | CelesteGRUB 1080p |

- **The greeter is a theme choice on the shared SDDM module.** It used to be its own
  `sddm-umbrella.nix` beside rock's `sddm-nier.nix`; both called qylock's
  `mkSddmThemes {}` (all ~40 themes, 526 MB) and could collide if imported
  together. Since 2026-10-03 one `Modules/Boot/sddm.nix` copies just the chosen
  theme directory (3.3 MB for hers), and the enum makes two greeters impossible.
- Unlike the NieR theme, hers needs **no font patching** — upstream ships
  `font/Itim-Regular.ttf` inside the theme directory, which is exactly where its
  `FontLoader` looks. The FOT-Rodin step in `sddm.nix` runs for `nier-automata` only.
- **`grub-celeste` is a separate module, not an option on `Modules/Boot/grub.nix`:**
  that one is Sisyphus's multi-profile loader and hardcodes Sisyphus's
  `rootFsUuid` plus a System Select submenu for profiles that do not exist on her disk.
- `useOSProber = false`: her only disk is disko's, so the one thing os-prober could
  find is the Apollo stick (or any drive) left plugged in during a rebuild — a boot
  entry that dangles once it is removed.
- The theme is pinned to a **commit**, not a branch: upstream is a handful of release
  tarballs with no tags, so `main` moving would silently change her boot screen.
- CelesteGRUB ships **one tarball per resolution** and is not scalable. The 1080p
  build matches her two 1920x1080 panels (read off the machine over SSH). On a
  different resolution the layout is mispositioned, not broken — swap the filename
  and hash in the module. `gfxmodeEfi` is pinned for the same reason: left to EFI's
  choice GRUB often picks 1024x768 and the background is cropped.

## NVIDIA

`Modules/Core/nvidia.nix`, imported only here. Every other machine is AMD:

- `services.xserver.videoDrivers = [ "amdgpu" ]` is set by Sisyphus's own
  `Hosts/Sisyphus/_hardware.nix` (it used to be in both compositor modules), so
  nothing shared hardcodes it any more; nvidia.nix's `lib.mkForce [ "nvidia" ]`
  is now just belt-and-braces.
- `Modules/Boot/plymouth.nix` defaults its initrd GPU module to `amdgpu` → the host sets
  `my.plymouth.initrdGpuModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ]`.

`hardware.nvidia.modesetting.enable = true` is **required** — Hyprland renders
through GBM. It is also what adds `nvidia-drm.modeset=1`, so that param is not
repeated in `boot.kernelParams`.

`hardware.nvidia.open` is not optional in the code sense: on driver >= 560 the
option defaults to `null` and the nvidia module *asserts* that you have chosen. Her
RTX 3070 is Ampere (Turing or later), where upstream recommends the open modules,
so it is `true`.

If Hyprland black-screens from a TTY, in order of likelihood:
1. plymouth's early KMS — drop `plymouth` from her imports to rule it out.
2. the GBM/GLX env vars listed in the comment at the bottom of `Modules/Core/nvidia.nix`.

The Apollo stick is the recovery path for all of these. Keep it to hand.

## Deliberately left out

| Module | Why |
|---|---|
| `grub` | hardcodes Sisyphus's `rootFsUuid` and emits Sisyphus's profile entries. She is single-boot on `grub-celeste`. |
| `sops` | that module is keyed to rock's hand-copied age key at `/home/rock/.config/sops/age/keys.txt` |
| `wolf` | pulls full Docker and hardcodes `WOLF_RENDER_NODE=/dev/dri/renderD128` (Sisyphus's RX 9060 XT) |
| `sunshine` | pins `output_name=HDMI-A-1`, re-patches it every activation, grabs the desktop cursor whenever it runs |
| `rpcs3` | large, needs firmware she may never want |

## Known-wrong-but-harmless

Her skwd wallpaper library starts **empty** — `~/Pictures/Wallpapers` is not in the
repo. See `Claude/next-up.md`.

## Hyprland, not niri

She was briefly configured for niri (a straight clone of Sisyphus) and moved to
Hyprland before ever being installed. The swap is clean because everything the
two compositors share — the X server for SDDM's greeter, keymap, `XCURSOR_*` /
`NIXOS_OZONE_WL`, Bluetooth, `hardware.graphics` — lives in
`Modules/Desktop/desktop.nix`, the greeter in `Modules/Boot/sddm.nix`, and each
compositor module only sets its own `defaultSession`, portal routing and cursor
bits. `steam-open` / `spotify-open` / `wrappedNiri` are internal to `niri.nix` and
exist only to work around a niri spawn bug.

**Portals:** `xdg.portal.config.hyprland.default = [ "hyprland" "gtk" ]`. Until
2026-10-03 the module set `config.common.default = "gtk"`, and because
xdg-desktop-portal reads `/etc/xdg/xdg-desktop-portal/portals.conf` before the
`hyprland-portals.conf` Hyprland ships in `share/`, **everything** went to the gtk
portal — screen sharing and screenshots included, which gtk does not implement.

**Window rules mirror niri's app-ids:** `^steam$`, `^(discord|vesktop)$`,
`^brave-browser$`, `^[Tt]hunar$`. The old `^(Steam)$` / `^(discord)$` / `^(brave)$`
/ `^(thunar)$` never matched (wrong case, or the wrong client), so those windows
were opaque whatever `opacityStrong` / `opacityLight` said. Media keys use the
same `--ignore-player=skwd-music` playerctl string as niri.

**One real difference, and it matters here.** niri silently ignores `output` blocks
for connectors that do not exist, so a wrong monitor name is harmless. Hyprland is
not so forgiving: a config naming only `DP-2` and `HDMI-A-1` gives a machine with
`DP-3`/`DP-4` no matching rule at all. So:

- `Modules/Desktop/hyprland.nix` takes `my.hyprland.monitors` (default `[ ]` — the
  old Odysseus default and the never-read `primaryMonitor` / `secondaryMonitor` /
  `secondaryWorkspace` options are gone).
- It appends `",preferred,auto,1"` unconditionally **after** the host's rules, so an
  unlisted output still lights up. A specific rule always wins over the catch-all.
- Her host names `DP-3` (the pivoted Dell, `transform,3`) and `DP-2` (the Philips),
  read with `hyprctl monitors` on the installed system. **Not** the names the
  Apollo ISO reported (`DP-3` / `DP-4`): nouveau on the stick enumerates the
  connectors differently from the proprietary driver.

`Modules/Core/nvidia.nix` also sets `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`,
`LIBVA_DRIVER_NAME` and `NVD_BACKEND`. Hyprland is noticeably fussier about these
than niri — without `GBM_BACKEND` it commonly starts and renders nothing. If the
desktop misbehaves in a GL-ish way, comment those out first.

skwd forces `niri.overviewBackdrop = false` in her config (it used to force it
`true` on every host): there is no niri overview on Hyprland and no
`place-within-backdrop` rule to keep a backdrop surface out of the way. Her skwd
config also has no `steam` integration (no Millennium) and no `spicetify*` ones
(she runs the Sleek theme) — see `Claude/skwd-wall.md`.
