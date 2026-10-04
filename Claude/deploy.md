# Deploying — the Apollo USB

One ISO, carried on the Ventoy stick (`Apollo`, exfat, 233 GB), that joins the
tailnet by itself and then waits. Everything is initiated from Sisyphus.

Built from `Hosts/Apollo/system.nix` — still the rescue disk (full Niri desktop,
gparted, claude-code), now also the deployment target.

## The whole workflow

```bash
apollo-iso                        # build + copy the ISO onto the stick
apollo-key                        # put the tailnet auth key on the stick
# boot the stick on the target machine
apollo-connect                    # waits for it to appear, then SSHes in
apollo-deploy --vm-test kitkat-Kit-Kat    # prove the disk layout, touch nothing
apollo-deploy kitkat-Kit-Kat              # install (ERASES the target's disks)
```

Afterwards, ongoing rebuilds go over the tailnet:

```bash
system-rebuild kitkat Kit-Kat     # from Sisyphus: nixos-rebuild --target-host kitkat@kit-kat
                                  # on Kit-Kat itself: the same command rebuilds in place
```

## Why this works at all

`nixos-anywhere` checks the target's `/etc/os-release` for `VARIANT_ID=installer`
and, when it finds it, **skips the kexec phase**. The Apollo ISO has that marker,
so nothing re-boots mid-install and the SSH session — along with the tailnet link
carrying it — survives from start to finish. Without that, kexec would drop the
connection the moment the install began.

`nixos-anywhere` is already in `Modules/Desktop/desktop.nix` (Sisyphus, Kit-Kat) and on the
Apollo ISO, so it needs no flake input.

## The auth key lives on the stick, not in the ISO

The key file lives at **`<stick>/keys/ts-authkey`** (next to the age backup that was
already there), and the boot unit also accepts it at the stick root.

`apollo-tailscale-up` (in `Hosts/Apollo/system.nix`, modelled on
`marsbar-tailscale-up` in `Modules/Server/marsbar.nix`) mounts the stick read-only at boot,
pulls the key out of that file — **skipping comment lines, and requiring at least 8
characters after `tskey-`** — and runs
`tailscale up --authkey=file:… --hostname=apollo --ssh`.

Both of those guards are load-bearing, and the second was found the hard way. The
placeholder template shipped on the stick *explains the key format*, so it contains
the literal string `tskey-` in its own comments. A plain `grep -m1 -o tskey-…`
matched that comment instead of the pasted key and produced a 6-character "key",
which would have failed at `tailscale up` with a thoroughly unhelpful error. Skipping
`^#` lines also means a **commented placeholder is safe**: until the template is
filled in the unit finds nothing, logs, and exits 0.

Three reasons it is not baked into the image:

1. An ISO's Nix store is world-readable and **this repo is public** — a key in the
   store is a key on GitHub's doorstep if the image is ever shared.
2. It keeps the repo's eval pure. There is no `builtins.getEnv` anywhere in this
   tree and no `--impure` build.
3. Auth keys expire at 90 days max. Rotating means re-running `apollo-key`, not
   rebuilding and re-copying a 2 GB image.

exFAT has no Unix permissions, so **physical possession of the stick is the
control** — the same trust model as the age key already kept on Apollo.

If the key is missing the unit logs and exits 0. It never fails the boot; you can
always `sudo tailscale up` at the console.

Source of record: sops `tailscale-installer-key`. Mint it
**ephemeral + reusable + pre-approved + tagged `tag:installer`** so each boot is a
throwaway node that self-removes when it goes offline.

## Things that will bite

- **Secure Boot must be off**, or Ventoy's shim MOK-enrolled — Microsoft revoked
  Ventoy's signed shim in mid-2024.
- **Keep a `dd`'d fallback stick.** NixOS-ISO-under-Ventoy is a known-flaky
  combination (nixpkgs#245101, still open; "Find NixOS closure" stage-1 failures).
  `dd if=apollo-deployer.iso of=/dev/sdX bs=4M conv=fdatasync` is the supported
  path and always works.
- **The ISO regenerates its SSH host key on every boot** (read-only root). A plain
  `ssh rock@apollo` therefore trips `REMOTE HOST IDENTIFICATION HAS CHANGED` every
  single time. `apollo-connect` and `apollo-deploy` pass
  `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` for exactly this
  reason — a new identity each boot is expected, and the tailnet already
  authenticates the node.
- **`nix.settings.trusted-users` must include `rock` on the ISO.**
  `profiles/installation-device.nix` trusts only `nixos`, so `--build-on local`
  (build on Sisyphus, `nix copy` over) fails on the copy without it.
- **`isoImage.isoName` does not set the ISO filename.** It was renamed to
  `image.fileName` in 25.05, and `iso-image.nix` passes
  `"${config.image.baseName}.iso"` to `make-iso9660-image` regardless. The old
  `isoImage.isoName = "nixos-rescue-rock.iso"` here was a silent no-op for years —
  the image actually came out as `nixos-minimal-<label>-x86_64-linux.iso`. The
  working knob is `image.baseName`, and it is set unconditionally upstream, so it
  needs `lib.mkForce`.
- **`nixos-rebuild --store-path --target-host` dies on `<nixpkgs/nixos>` (hit 2026-10-04).**
  A remote switch to Kit-Kat failed during *activation*, after a clean build, with
  `error: file 'nixos-config' was not found in the Nix search path`, from
  `nix-build '<nixpkgs/nixos>' --attr config.system.build.nixos-rebuild`. Nothing was
  wrong with the config. `nixos-rebuild-ng` **re-execs itself** at startup to pick up a
  newer copy (`reexec()` in `nixos_rebuild/services.py`): given `--flake` it resolves that
  through the flake, but with only `--store-path` it falls back to the legacy
  `<nixpkgs/nixos>` path and needs a `nixos-config` entry in `NIX_PATH`, which rock's user
  environment does not have. ⚠️ **`system-rebuild.sh` still builds the command this way**
  (`--store-path … --target-host … --ask-sudo-password`), so this will recur.
  There is an `_NIXOS_REBUILD_REEXEC=1` guard at the top of `reexec()` that returns before
  the probe, but it was **never tested on the failing path** — don't present it as proven.
  The route verified to work is to skip `nixos-rebuild` and activate the already-copied
  closure directly:

  ```bash
  ssh -t <user>@<host> 'sudo nix-env -p /nix/var/nix/profiles/system --set <storepath> \
      && sudo <storepath>/bin/switch-to-configuration switch'
  ```

  That is what `nixos-rebuild` does internally — it registers the generation and updates
  the bootloader. `ssh -t` is required so sudo has a TTY to prompt on; the second `sudo`
  reuses the cached timestamp, so it is one password entry.
  ⚠️ **`nixos-rebuild list-generations` cannot test this** — it succeeds with *and* without
  the env var, because it never reaches the failing probe.
- **No password on the ISO, by design.** `users.users.*.password` is written
  verbatim into `/nix/store/*-users-groups.json` (mode 0444), so on an ISO it is
  greppable out of the squashfs without booting it. Combined with sshd, passwordless
  sudo, and a tailnet join, a baked password hands root to every tailnet node.
  Console access does not need one: greetd autologins into niri.

## `--build-on local` vs `remote`

`apollo-deploy` uses `local`: Sisyphus builds the closure and copies it over. Good
on a LAN, several GB over a slow link. `--build-on remote` makes the target fetch
from `cache.nixos.org` and build there instead — cheaper on bandwidth, and it works
because the flake is public, so the target needs no credentials.

## Asgard is not deployable from here

`system-rebuild` refuses `Asgard` without an explicit `--target`. This repo's
`Modules/Server/` can drift from the copy on Asgard (`Claude/server-info.md`), so a
push would overwrite the live config with a stale copy. Edit it on Asgard.

What the menu offers instead (Remote → Asgard) runs **on Asgard, from its own
`~/Dots`**: *Pull & switch* (`git pull --ff-only`, which refuses rather than
merges if Asgard has diverged, then `nixos-rebuild switch --flake .#rock-Asgard`)
and *Switch there* (no pull). *Compare* builds this checkout's Asgard locally and
diffs it against what is live, deploying nothing. *Push ours…* is the old
override, behind a confirm.

## Checking a disk layout before you wipe anything

Two commands, and the useful one is probably not the one you'd reach for.

### `apollo-deploy --dry-run <attr>` — works for any layout

Builds the host's `system.build.diskoScript` and prints it. Nothing is executed. You
see the literal `sgdisk --clear /dev/nvme0n1`, every `--change-name=` partlabel, and
every `mkfs`. **Read the device name in that output before installing** — it is the
single value most likely to be wrong.

### `apollo-deploy --vm-test <attr>` — limited, and it lies

It boots a throwaway VM and actually applies the layout, which is a stronger check —
but two traps:

1. **It exits 0 even when the test fails.** A failure appears only as text:
   ```
   !!! RequestedAssertionFailed: command `…/disko-format` failed (exit code 4)
   machine # Error encountered; not saving changes.
   ```
   `apollo-deploy --vm-test` therefore greps the output and fails loudly itself.
   Never read a bare exit 0 from `nixos-anywhere --vm-test` as a pass.
2. **The test disk is a hardcoded 4 GiB.** disko's harness sets
   `emptyDiskImages = builtins.genList (_: 4096) num-disks` in `lib/tests.nix`, with no
   option to change it. So any layout with more than ~4 GiB of **fixed-size** partitions
   can never pass — Kit-Kat's 16 G swap puts it over, and the failure looks like bad
   partitioning when it is purely the harness.

   `disko.devices.disk.<n>.imageSize` does **not** help here: that only sizes
   `make-disk-image` output (building a raw/qcow image), not the test VM.

So: `--dry-run` for a layout like Kit-Kat's, `--vm-test` only for layouts that fit in
4 GiB of fixed partitions.

## Never pass `--ssh` to `tailscale up` on a node you SSH into

**Tailscale SSH takes over port 22 on the Tailscale IP.** With `--ssh` enabled,
`tailscaled` — not OpenSSH — answers `ssh rock@apollo`. A normal SSH client gets a
TCP accept and then **nothing at all**: no banner, no error, it just hangs until it
times out. `apollo-connect` and `nixos-anywhere` both break.

The node looks perfectly healthy while this is happening, which is what makes it
expensive to diagnose:

```
$ tailscale ping apollo
pong from apollo (100.104.23.7) via 192.168.0.147:41641 in 0s     # fine
$ </dev/tcp/100.104.23.7/22                                        # "port 22 OPEN"
$ ssh rock@apollo                                                  # hangs forever
```

The giveaway is **a TCP connect that succeeds with no SSH banner**. Grab the banner
explicitly when diagnosing:

```bash
exec 3<>/dev/tcp/<ip>/22; timeout 5 head -c 80 <&3     # silence => not OpenSSH
tailscale ssh rock@apollo                              # "requires an additional check" => Tailscale SSH is on
```

It was added here as a belt-and-braces "second way in" and was precisely what removed
the first way in. The ISO now runs plain
`tailscale up --authkey=file:… --hostname=apollo`, and access is OpenSSH plus the
authorized key from `Modules/Core/base.nix`.

## The console is text, deliberately

The ISO used to greetd-autologin straight into niri. On unknown hardware a graphical
session is the most fragile thing you can autostart, and when it fails you get black
screens and no way to tell whether the machine is alive, still booting, or wedged —
which is exactly what happened on the first real boot.

It now autologins to a text console and prints `apollo-status`: tailnet state and IP,
the exact ssh command, the disk list (which is what `installDisk` in `Hosts/<Host>/_disko.nix` needs), the GPU
(which is what `hardware.nvidia.open` needs) and RAM. If the tailnet is down it says
so in red along with the `journalctl` command and the fix. It prints on ssh login too.

`desktop` starts niri by hand when the graphical rescue tools are actually wanted.

## Ventoy scans the whole partition, including the trash

Deleting an old ISO in a file manager does **not** remove it from the Ventoy boot
menu. It moves it to `.Trash-1000/files/` on the same stick, and Ventoy lists hidden
directories too — so the "deleted" image keeps showing up, and you end up with two
`apollo-deployer.iso` entries and no way to tell which is which from the menu.

Hit on 2026-10-02: a stale copy sat in the trash for hours while the real one was
being replaced in `ISOs/`. Check with:

```bash
find /run/media/rock/Apollo -iname "*.iso" -printf "%10s  %TH:%TM  %p\n"
```

and empty `.Trash-1000/{files,info}` properly. The trash had ~12 GB of old images in
it, all of them still in the boot menu.

## One command, not six

`system-rebuild` is the single entry point — an inline terminal UI that draws in
normal scrollback and never takes over the screen. The home screen is the DOTS
wordmark (branch, dirty state, ahead/behind, nixpkgs lock age beside it) and a
MACHINES panel: this machine's generation, every other machine's tailnet state
(online / direct or relay / last seen). Below it, four sections:

```
  Rebuild     this machine: Switch · Boot · Build, or build any Other host here
  Remote      every other machine, live status; per machine its generation,
              uptime and (Asgard) its checkout, probed over ssh, then
                Kit-Kat / Sisyphus   Switch · Boot · Build · SSH
                Asgard               Pull & switch · Switch there · SSH · Compare · Push ours…
  Utilities   Git sync · Update inputs (changelog, then offers a rebuild) ·
              Garbage collect · Check hosts (the four-host drvPath eval)
  Apollo      Deploy (host → Dry run / VM test / INSTALL) · SSH · Build ISO · Tailnet key
```

Keys: ↑↓ or j/k, ⏎ (or →/l) to pick, the digit picks directly, esc/←/h goes back,
q quits. After a job, ⏎ returns to the same menu with the home screen refreshed.

**Host-aware.** It matches the hostname against its machine list (`DOTS_HOST`
overrides), so "local" is wherever it runs. On Sisyphus, `system-rebuild kitkat
Kit-Kat` pushes to her; on Kit-Kat the same command — and Rebuild in the menu —
rebuilds Kit-Kat in place, never trying to reach itself over the tailnet. Kit-Kat
imports `deploy-tools` with `my.deploy-tools.admin = false`: system-rebuild,
git-sync and nix-gc, none of the Apollo commands (rock's sops key), so its menu has
no Apollo section. Without a `~/Dots` it builds `github:JimmyTheSquirrel/Dots`
(main), and Utilities offers *Get the repo* in place of sync/update.

Every rebuild is build → diff → activate: `nom build` of the toplevel, `dix`
against what's running (over ssh for a remote machine), then
`nixos-rebuild <switch|boot> --no-reexec --store-path <built>` (`-p sisyphus` for
Sisyphus's own profile, `--target-host` for a remote) — so the flake is evaluated
once and activation is still nixos-rebuild's own. **`--no-reexec` is load-bearing:**
before switch/boot, nixos-rebuild-ng rebuilds *itself* from the new config — from
`--flake` if given, else from `<nixpkgs/nixos>` + `nixos-config` on NIX_PATH, which a
flake system doesn't have — and it does so even with `--store-path`. Without the flag
every activation fails with `file 'nixos-config' was not found in the Nix search path`. Ends in a summary box (time, closure size
and delta, generation) or a red box saying nothing was activated.

**Where things live.** `Resources/Scripts/lib/ui.sh` is the look and the engine:
palette (Gruvbox brights to match kitty), the gradient wordmark, framed panels,
pills, and the keyboard menu (`ui_menu_new` / `ui_item` / `ui_menu`). It is
prepended to each tool by `Modules/Shell/deploy-tools.nix`; plain text when piped
or with `NO_COLOR`. `Resources/Scripts/system-rebuild.sh` holds the machine list
(`host_info` — a new machine is one line), the jobs, and one `menu_*` function per
section: a new job is one `ui_item` line plus one case arm calling `job <fn>`.
Block glyphs, box drawing and the round pill caps are drawn by kitty itself; the
icons are Nerd Font (FantasqueSansM Nerd Font Mono).

The `apollo-*` commands still exist and still work standalone — `apollo-connect` in
particular is worth keeping in muscle memory — they just don't all need to be
remembered. The navi cheatsheet (`dots.cheat`, shipped by `Modules/Shell/deploy-tools.nix`) is down to `system-rebuild`, `nix-gc`, `git-sync`,
and, with admin, `sops` and three SSH targets.

CLI form is unchanged: `system-rebuild USER SYSTEM [--boot|--build] [--target HOST]` —
no menus, same build → diff → activate output.

## The blank screen on a booted stick — two separate causes

Both hit on her RTX 3070 the first time the stick was used on real hardware, and
both looked identical from the outside: monitors dark, machine apparently dead.

**1. The ISO autostarted a graphical session.** Fixed by booting to a text console
(see above). But fixing that alone was not enough.

**2. The display-manager framework claimed tty1 and then had nothing to run.**
`Modules/Desktop/niri.nix` sets `services.xserver.enable = true`, which switches on
`services.displayManager`. That framework reserves tty1 for a display manager. Force
`sddm` and `greetd` off but leave the framework on, and you get the worst case:
`display-manager.service` **fails** (nothing to launch) *and* `getty@tty1` is never
started, so nothing paints. The machine is booted, networked and SSH-able the whole
time.

The fix needs all of:

```nix
services.xserver.enable            = lib.mkForce false;
services.displayManager.enable     = lib.mkForce false;
services.displayManager.sddm.enable = lib.mkForce false;
services.greetd.enable             = lib.mkForce false;
services.getty.autologinUser       = lib.mkForce activeUser;
systemd.services."getty@tty1" = { enable = true; wantedBy = [ "getty.target" ]; };
```

That last block is not redundant. `services.getty` only adds `autovt@tty1` to
`getty.target.wants` when `displayManager.enable` is false — and on this ISO that
want **still did not materialise**: `getty.target` came out as a bare symlink to
systemd's upstream unit with nothing wanting a getty on it. Verified by checking for
the symlink in the built system:

```bash
ls $(nix eval --raw .#nixosConfigurations.rock-Apollo.config.system.build.toplevel)/etc/systemd/system/getty.target.wants/
# must list getty@tty1.service
```

Check that, not the option value, when the console is dead.
