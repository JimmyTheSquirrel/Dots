# Kit-Kat — her machine

`Hosts/Kit-Kat/system.nix`, flake attr **`kitkat-Kit-Kat`**, login `kitkat`
("Kit Kat"), tailnet node `kit-kat`. Runs **Hyprland** (the same module as
Odysseus) with noctalia and skwd v2, on her own NVIDIA hardware.

This replaced **Elektra**, which was a KDE boot profile on *Sisyphus's own disk* —
all three local profiles shared one root UUID, one ESP and one swap, selected from
the GRUB "System Select" submenu. Elektra is therefore gone from
`Modules/Boot/grub.nix` and from the `system-rebuild` local menu;
`Modules/Desktop/kde.nix` and `Claude/kde.md` are retained but unused.

## Deploy / rebuild

```bash
apollo-deploy --vm-test kitkat-Kit-Kat   # prove the disk layout first
apollo-deploy kitkat-Kit-Kat             # first install — ERASES the disk
system-rebuild kitkat Kit-Kat            # every rebuild after that
```

See `Claude/deploy.md` for the Apollo USB side.

## Before the first install

1. **Confirm `installDisk`** in `Hosts/Kit-Kat/system.nix`. It is `/dev/nvme0n1`
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
3. `facter.json` does not exist yet. The host evaluates without it (and warns), but
   **do not switch it onto real hardware** until `apollo-deploy` has generated and
   you have committed it — there is no microcode, no detected kernel modules and no
   firmware without it.

## Her password

From `Secrets/kit-kat.yaml` → `user-password-hash` →
`users.users.kitkat.hashedPasswordFile`. **Not** from `Secrets/secrets.yaml`.

That separation is deliberate: sops encrypts a whole file to every recipient, so
adding her machine to `secrets.yaml` would hand it `mullvad-wg-private-key`,
`cloudflare-tunnel`, `eclipse-ssh-key`, `anthropic-api-key` and
`tailscale-api-key` — an **admin** key that can rewrite tailnet ACLs and mint auth
keys. Her file holds one secret and nothing else.

Because the hash is declarative, `passwd` will not survive a rebuild. Changing her
password means `sops Secrets/kit-kat.yaml`.

Note: `rock`'s own password is **not** managed this way. `Modules/Core/sops.nix`
declares `user-password-hash` but nothing in the repo consumes it, so Sisyphus's
login hash lives only in `/etc/shadow`, set by `passwd`.

## Her look

| Piece | Module | Source |
|---|---|---|
| Greeter | `Modules/Boot/sddm-umbrella.nix` | qylock `women-umbrella` (Totoro) |
| Bootloader | `Modules/Boot/grub-celeste.nix` | CelesteGRUB 1080p |

Both are deliberately separate modules rather than options on the shared ones:

- **`sddm-umbrella` cannot coexist with `sddm-nier`.** Both put a package providing
  `share/sddm/themes/...` into `environment.systemPackages` and would collide in the
  profile, and only one `services.displayManager.sddm.theme` can win. Sisyphus keeps
  `nier-automata`; she gets `women-umbrella`.
- Unlike the NieR theme, this one needs **no font patching** — upstream ships
  `font/Itim-Regular.ttf` inside the theme directory, which is exactly where its
  `FontLoader` looks. That is the entire reason `sddm-nier.nix` has to override the
  derivation and this one does not.
- **`grub-celeste` replaces systemd-boot** on her host. It is NOT `Modules/Boot/grub.nix`:
  that one is this machine's multi-profile loader and hardcodes Sisyphus's
  `rootFsUuid` plus a System Select submenu for profiles that do not exist on her disk.
- The theme is pinned to a **commit**, not a branch: upstream is a handful of release
  tarballs with no tags, so `main` moving would silently change her boot screen.
- CelesteGRUB ships **one tarball per resolution** and is not scalable. The 1080p
  build matches her two 1920x1080 panels (read off the machine over SSH). On a
  different resolution the layout is mispositioned, not broken — swap the filename
  and hash in the module. `gfxmodeEfi` is pinned for the same reason: left to EFI's
  choice GRUB often picks 1024x768 and the background is cropped.

## NVIDIA

`Modules/Core/nvidia.nix`, imported only here. Every other machine is AMD, and two
shared modules hardcode that:

- `Modules/Desktop/niri.nix:402` sets `videoDrivers = ["amdgpu"]` → overridden
  with `lib.mkForce ["nvidia"]`.
- `Modules/Boot/plymouth.nix` defaults its initrd GPU module to `amdgpu` → the host sets
  `my.plymouth.initrdGpuModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ]`.

`hardware.nvidia.modesetting.enable = true` is **required** — niri is wlroots-style
and renders through GBM. It is also what adds `nvidia-drm.modeset=1`, so that param
is not repeated in `boot.kernelParams`.

`hardware.nvidia.open = false` is not optional in the code sense: on driver >= 560
the option defaults to `null` and the nvidia module *asserts* that you have chosen.
`false` works on every supported card. **Revisit once `facter.json` names the
GPU** — upstream suggests `open = true` on Turing or later (RTX, GTX 16xx).

If niri black-screens from a TTY, in order of likelihood:
1. plymouth's early KMS — drop `plymouth` from her imports to rule it out.
2. the GBM/GLX env vars listed in the comment at the bottom of `Modules/Core/nvidia.nix`.
3. `rain-effect` is a GLES2 `wlr-layer-shell` overlay — expected to work on NVIDIA
   but unverified. Nothing depends on it; drop it if it misbehaves.

The Apollo stick is the recovery path for all of these. Keep it to hand.

## Deliberately left out

| Module | Why |
|---|---|
| `grub` | hardcodes Sisyphus's `rootFsUuid` and emits the three local profile entries. She is single-boot on systemd-boot. |
| `kde` | she's on Niri now |
| `skwd-wall` (v1) | conflicts with `skwd` (v2) by design — `Conflicts=skwd-daemon.service` |
| `sops` | that module is keyed to rock's hand-copied age key at `/home/rock/.config/sops/age/keys.txt` |
| `wolf` | pulls full Docker and hardcodes `WOLF_RENDER_NODE=/dev/dri/renderD128` (Sisyphus's RX 9060 XT) |
| `sunshine` | pins `output_name=HDMI-A-1`, re-patches it every activation, grabs the desktop cursor whenever it runs |
| `rpcs3` | large, needs firmware she may never want |

## Known-wrong-but-harmless

The wrapped niri config is a **`perSystem`** package
(`Modules/Desktop/niri.nix:626-633`) — one store path shared by every host. So her
monitor layout falls through to niri's auto-placement, and the `output "DP-2"` /
`"HDMI-A-1"` blocks plus the `open-on-output "HDMI-A-1"` window rules silently
no-op on her machine. Making outputs per-host means moving the wrapper out of
`perSystem`; it is in `Claude/next-up.md`.

Her skwd wallpaper library starts **empty** — `~/Pictures/Wallpapers` is not in the
repo. See `Claude/next-up.md`.

## Hyprland, not niri

She was briefly configured for niri (a straight clone of Sisyphus) and moved to
Hyprland before ever being installed. The swap is clean because
`Modules/Desktop/hyprland.nix` enables SDDM, XWayland, the portals and
`defaultSession` exactly as `niri.nix` does, and nothing outside `niri.nix` depends
on it — `steam-open` / `spotify-open` / `wrappedNiri` are all internal to that module
and exist only to work around a niri spawn bug.

**One real difference, and it matters here.** niri silently ignores `output` blocks
for connectors that do not exist, so a wrong monitor name is harmless. Hyprland is
not so forgiving: a config naming only `DP-2` and `HDMI-A-1` gives a machine with
`DP-3`/`DP-4` no matching rule at all. So:

- `Modules/Desktop/hyprland.nix` now takes `my.hyprland.{monitors,primaryMonitor,secondaryMonitor}`,
  defaulting to Odysseus's values so that host is unchanged.
- It appends `",preferred,auto,1"` unconditionally **after** the host's rules, so an
  unlisted output still lights up. A specific rule always wins over the catch-all.
- Her host sets `DP-3` / `DP-4` — read from `/sys/class/drm` over SSH while she was
  booted from the Apollo stick. `DP-1`, `DP-2` and both HDMI ports reported
  `disconnected`.
- Her modes are `preferred`, not pinned: the refresh rates were never measured, EDID
  picks correctly, and a wrong hardcoded mode is a black screen.

`Modules/Core/nvidia.nix` also sets `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`,
`LIBVA_DRIVER_NAME` and `NVD_BACKEND`. Hyprland is noticeably fussier about these
than niri — without `GBM_BACKEND` it commonly starts and renders nothing. If the
desktop misbehaves in a GL-ish way, comment those out first.

skwd v2 still writes `niri.overviewBackdrop` / `niri.backdropFollowWallpaper` into
her config; those keys are simply inert under Hyprland. The paired niri layer-rule
lives in `niri.nix`, which she does not import, so nothing dangles.
