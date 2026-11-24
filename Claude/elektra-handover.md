# Elektra — handover from her Claude

Set up 2026-11-22, after her local clone was found to be a separate fork of the
repo carrying work that existed nowhere else.

## The arrangement

Her machine runs a **Claude session of its own**, against a local clone at
`/home/kitkat/Dots`. That clone is **not** this repo — see "The two forks" below.
Her Claude is now told, in `HANDOVER.md` at that clone's root and in a ⛔ block at
the top of its `CLAUDE.md`:

- **Never deploy.** No `system-rebuild`, no `nixos-rebuild switch`/`boot`. (It
  cannot anyway — her `sudo` needs a password.)
- **Building to check work is fine** — `nix build .#nixosConfigurations.kitkat-Kit-Kat…`
  or `nix eval …drvPath` for a quick check.
- **Leave work for review** in `/home/kitkat/Dots/Handover/`, two files per change:
  `<date>-<slug>.md` (what broke, the actual Nix option lines quoted in full, which
  file in *this* repo they belong in, how it was verified, what was left out) and
  `<date>-<slug>.patch` (the diff).

The prose matters more than the patch: her tree has diverged far enough that a
`git diff` from it usually **will not apply here**.

## Collecting it

From Sisyphus:

```bash
ssh kitkat@kit-kat 'ls -lt ~/Dots/Handover/'
scp kitkat@kit-kat:'~/Dots/Handover/*' /tmp/handover/
```

⚠️ Her tailnet node is **`kit-kat`**, not `elektra` — see `Claude/elektra.md`.

## The two forks

| | this repo | her clone |
|---|---|---|
| the box is | `Hosts/Elektra/` | `Hosts/Kit-Kat/` |
| flake attr | `kitkat-Elektra` | `kitkat-Kit-Kat` |
| OS hostname | `Elektra` (never deployed) | `Kit-Kat` (what it actually runs) |
| `origin/main` | current | pinned weeks back, never fetched |

The 2026-10-09 rename was never pushed to her, so the hostname never changed, so
Tailscale never renamed the node, so `elektra` does not resolve, so the push that
would fix it cannot be addressed. `--target kit-kat` is the way out of that loop.

## Her USB/BT fix — PORTED 2026-11-22

Her commit `69990c9` (2026-11-22) exists only on her disk. The part worth keeping:

```nix
boot.kernelParams = [ "btusb.enable_autosuspend=0" ];
services.udev.extraRules = ''
  ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="13d3", ATTR{idProduct}=="3570", TEST=="power/control", ATTR{power/control}="on"
  ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0610", TEST=="power/control", ATTR{power/control}="on"
  ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05e3", ATTR{idProduct}=="0620", TEST=="power/control", ATTR{power/control}="on"
'';
```

`13d3:3570` is the onboard RTL8852BU Bluetooth radio (its A2DP link dropped under
USB autosuspend); `05e3:0610`/`0620` are the two chained Genesys chips in her desk
hub, behind which her TH99 keyboard's 2.4G dongle goes deaf after idle and only a
physical replug recovers it.

Her `my.audio.bluetooth = true` needs **no port**. That option is from an older
design her clone still carries, where `audio.nix` disabled WirePlumber's bluez
monitor by default and the option opted back in. This repo deleted that mechanism
on 2026-10-03 — the monitor is on by default — and our Elektra imports `desktop`,
which hers does not; that sets `hardware.bluetooth.enable`, `powerOnBoot` and
`AutoEnable`. Strictly better than her opt-in, so her headset is covered.

**Done** — this now lives in `Hosts/Elektra/system.nix` and the push carries it. It was
ported by hand, never merged: her commit also deletes `Hosts/Elektra/system.nix`.
