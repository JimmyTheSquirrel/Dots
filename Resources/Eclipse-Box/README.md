# Eclipse-Box — the hand-made state on the Pi

Eclipse is a Raspberry Pi 5 running **LibreELEC 12.2.1 / Kodi 21.3**. It is **not** a NixOS host
and never will be — there is no module to evaluate. `Claude/eclipse.md` is the recipe; this
directory is the **versioned copy of the files that recipe produces**, captured 2026-10-05.

**Why this exists.** An audit found two months of hand-editing with no record of what was changed
or why: 55 `.bak` files, ~20 loose scripts in `/storage`, and addon patches whose only
documentation was the patch script itself. An addon or skin update silently reverts several of
these. Nothing here is applied automatically — it is the reference you restore *from*.

**Disaster recovery is a card image, not this directory.** A `dd | zstd` clone of the SD card
(~2 GB compressed, from 2.2 GB used) captures the things these files cannot: bluez bonds, the Kodi
SQLite databases, Jellyfin's auth token, `tailscaled.state`. Take it with the box **powered down
and the card in a reader** — `/storage` is mounted `rw` with ordered data mode, so a live `dd`
catches the SQLite files mid-write. Restore to a **≥64 GB** card; a different-brand 64 GB can be
slightly smaller than this one (58.9 GiB).

---

## `system.d/` — custom systemd units

LibreELEC's supported user-unit directory is `/storage/.config/system.d/` (it ships
`wireguard.service.sample` etc. alongside). Everything under `/storage` survives an OS update;
only a re-flash loses it.

### `hdmi-hotplug.service` — ⚠️ fixed 2026-10-05, had NEVER survived a reboot

Kodi picks its DRM connector once at startup and never re-probes, so if it starts with the TV off
it latches onto a headless 1280x720 dummy and paints "no signal" forever. `hdmi-hotplug.sh` is the
watcher that restarts Kodi when the link comes up.

It carried `After=kodi.service` + `Wants=kodi.service`, which closed a systemd ordering cycle:

```
multi-user.target --wants--> hdmi-hotplug.service
                  --after--> kodi.service
                  --after/requires--> graphical.target
                  --after/requires--> multi-user.target
```

systemd breaks a cycle by **deleting a job from the boot transaction**, and it chose this one. The
unit sat `enabled` + `inactive (dead)` with no failure to notice. `/storage/hdmi-hotplug.log` held
exactly **one** `watcher started` line — 2026-08-30, from a manual start — so across every reboot
since, the box's only "no signal" protection had never run. It is also the backstop for the
Moonlight exit path, so that path had no backstop either.

Fix: drop both lines. The dependency bought nothing — `hdmi-hotplug.sh` polls the connector in a
loop and already handles *"kodi is not active (deliberate?)"* and *"moonlight-qt is running"*.

### `tailscaled.service`

Tailscale from the static aarch64 binaries in `/storage/tailscale/`, `--statedir` under `/storage`.
Two flags are **required** on this platform and are persisted in `tailscaled.state`:
`--netfilter-mode=off` (LibreELEC's kernel has no connmark module) and `--accept-dns=false`
(`/etc` is read-only squashfs, so **no MagicDNS** — address tailnet hosts by IP).

### `wlan0-powersave.service` — ⚠️ reports success but has never worked

A `oneshot` running `iw dev wlan0 set power_save off` at boot, to stop power-save starving Kodi's
read-ahead. **wlan0 is down at boot**, so it runs against a non-existent interface, and
`RemainAfterExit=yes` leaves it showing a green `active (exited)` forever. The protection its
description claims is not in force. A oneshot at boot cannot do this job — it needs to fire on an
association event (a ConnMan hook) or be set at driver level via `modprobe.d`.

Only matters on the day the wired path fails and wifi takes over as the intended hot standby —
which is exactly the day power-save stalls would bite.

---

## `patches/` — addon source patches

All three are **idempotent** and back up to `.orig` before touching anything. An addon update
reverts the patched file silently, so re-run after any update to `plugin.video.jellyfin` or
`script.litebox`. `litebox/*.orig` are the pristine upstream copies.

| Script | Target | What and why |
|---|---|---|
| `patch_dv.py` | `plugin.video.jellyfin/.../helper/playutils.py` | Refuses direct play for `VideoRangeType` **DOVI**. Dolby Vision Profile 5 has no HDR10 fallback — its base layer is **IPT-C2, not YCbCr** — and the Pi 5 has no DV support, so direct-playing one decodes IPT as though it were YUV and **the picture comes out green**. Forcing a server transcode fixes it. |
| `patch_litebox.py` | `script.litebox/.../utils.py` | `Image.ANTIALIAS` → `Image.LANCZOS`. Pillow 10 removed `ANTIALIAS`; LANCZOS is the same filter under its modern name, so this is behaviour-identical. |
| `patch_litebox2.py` | `script.litebox/.../imageoperations.py` | `MyGaussianBlur` now inherits `ImageFilter.GaussianBlur`. Pillow ≥10 changed the private `ImagingCore.gaussian_blur` signature to take an `(xradius, yradius)` pair, so the old scalar call raised *"argument 1 must be 2-item sequence, not int"* on **every image**. Also blurs RGB in one C call instead of three. Refuses to patch if its anchor is missing rather than guessing. |

These two litebox patches are what stopped `script.litebox` hammering Asgard. The audit confirmed
it is now quiet.

---

## `moonlight/` — the Moonlight addon fork

`bootstrap_moonlight-qt.sh` and `libreelec-start.sh` (the addon's
`resources/bin/kodi_hooks/libreelec/start.sh`) are **forked from upstream**. The launch path stops
Kodi, runs Moonlight under `systemd-run`, and restarts Kodi from a bash `EXIT` trap.

Two things the audit established:

- **Stream audio is durably fixed, not a live hack.** The launch passes
  `--setenv=SDL_AUDIODRIVER="alsa"` and writes its own `asoundrc`, bypassing PulseAudio (which on
  this box only ever has `auto_null`). ⚠️ The mechanism keys off Kodi's
  `audiooutput.audiodevice` starting with `"ALSA"` — switching Kodi to a PULSE device silently
  takes the other code path.
- **The EXIT trap has worked 15/15 times** since being hardened. Its residual risk is structural:
  a bash trap is a single point of failure for getting the UI back, and its backstop
  (`hdmi-hotplug.service`) was dead until 2026-10-05.

---

## `evidence/` — logs kept because they are the only copy

`journald` on this box is **volatile**, so nothing survives a reboot. These were retained
deliberately.

### The 2026-10-01 Kodi crash — what it actually was

Previously described as the Moonlight exit trap failing unprovoked. The crashlog shows something
different: **Kodi segfaulted on the way *down*, not on the way back up.**

```
19:14:58  DualSense connects — joysticks 0 (motion sensors) and 1 (pad) registered
19:15:01  Moonlight addon launches: EGL forced to /dev/dri/card1, asoundrc written,
          systemd-run ... SDL_AUDIODRIVER=alsa launch_moonlight-qt.sh
19:15:02  "Quitting due to POSIX signal"  — Kodi told to stop, exitCode 65 saved
          clean shutdown begins: settings saved, event server stopped
          Jellyfin's service.py raises ExitService
   ⇒      SIGSEGV in XBMCAddon::RetardedAsyncCallbackHandler::~RetardedAsyncCallbackHandler()
```

So it is a **shutdown-path crash in Kodi's Python addon callback teardown**, almost certainly a
race with Jellyfin's service thread exiting. Kodi was being stopped anyway, so the user-visible
effect is small — but the shutdown was not clean, which can leave systemd's view of
`kodi.service` inconsistent and is a plausible cause of a trap-restart misfiring.

Core dumps are **not** accumulating (`/storage/.cache/cores` is empty).

### `dualsense-repair.log`

The record of the controller's real failure mode: BlueZ reports `Connected: yes` while
`input nodes: 0 match(es)`. The kernel driver fails to bind with **`-5` (EIO)**, so the pad is a
bonded Bluetooth device producing no input at all — it looks connected and does nothing.
**A helper that trusts BlueZ `Connected` reports a working controller in exactly the broken case.**
Recovery needs remove + re-pair, not `connect`.

---

## `diagnostics/` — one-off investigation scripts

Kept for reference, not for re-running. `agg.sh`, `apply.sh`, `lantest.sh`, `par.sh`, `post.sh`,
`probe.py`, `verify.py`, `final.py`, `scan.sh`, `scan2.sh`, `uncap.sh` are from the September
network/bitrate investigation; `pair.sh` is from the original controller pairing. They reference
absolute paths on the Pi and assume state that may no longer exist — read them, don't run them.

---

## `keymaps/eclipse-osd.xml`

User keymaps live in `/storage/.kodi/userdata/keymaps/` and **survive skin, addon and Kodi
updates** — the stock keymaps in `/usr/share/kodi/system/keymaps/` are on the read-only squashfs
and user keymaps layer on top. This is the most durable place to change behaviour on this box.

⚠️ **A long-press on the TV remote is not achievable.** The remote reaches Kodi **only through
HDMI-CEC** (there is no kernel-level remote or keyboard in `/proc/bus/input/devices` — just the two
HDMI jacks and the power button), so it lands in the keymap's `<remote>` section, and Kodi 21's
`CIRTranslator::TranslateButton` takes plain strings with no access to XML attributes:
`mod="longpress"` is **silently ignored** there. Only `<keyboard>` and joystick `holdtime` support
hold actions. CEC is configured with `button_repeat_rate_ms=0` and `double_tap_timeout_ms=300`, so
holding OK produces exactly one Select event.
