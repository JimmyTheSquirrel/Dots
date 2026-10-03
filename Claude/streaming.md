# Game Streaming — Sunshine, Moonlight, Tailscale

## Overview

Sisyphus runs **Sunshine** as a game streaming host, accessible remotely via **Tailscale**, streamed to Android phone or TV (via Eclipse Pi) using **Moonlight**.

**Modules (Sisyphus only):**
- `Modules/Gaming/sunshine.nix` — Sunshine user service
- `Modules/Core/tailscale.nix` — Tailscale VPN. **Enable only; no auth key.** The module is 15 lines of `services.tailscale.enable` + firewall. Joining is `sudo tailscale up` by hand, except on the Apollo installer ISO and the marsbar node, which read a key from elsewhere.

`moonlight-qt` is in `base.nix` and available on all three systems.

## Sunshine

- Runs as a **user service** (`autoStart = true`) — starts automatically on Niri login
- `hardware.uinput.enable = true` — allows Sunshine to send virtual input to Linux
- `openFirewall = true` + `trustedInterfaces = [ "tailscale0" ]` — reachable over Tailscale without extra firewall rules

**Web UI:** `https://localhost:47990` (self-signed cert, accept warning) — set credentials on first run

**Display selection** (Sunshine web UI → Configuration → Audio/Video → Display Number):
- `card1-DP-2` — 2560x1080 @ 144Hz (primary ultrawide)
- `card1-HDMI-A-1` — 1920x1080 @ 60Hz (secondary, better for phone streaming)

**`sunshine.conf` seeded** via home-manager activation. Initial write happens when the file is empty/missing; web UI changes survive rebuilds — EXCEPT three values that are **always patched**:
- `hevc_mode = 2` — advertise HEVC Main. **Changed from `1` (H.264-only) on 2026-09-27.**
- `output_name = HDMI-A-1` — the 1080p monitor. Always enforced so streaming targets it.
- `capture = wlr` — force the wlroots capture backend. Always enforced (see below).

### ✅ HEVC is the correct codec here — H.264 was costing a LOT

**The Pi 5 has NO H.264 hardware decoder.** Its single decode block is HEVC-only
(`/dev/video19`, see `Claude/eclipse.md`). Forcing H.264 meant Eclipse decoded every frame in
**software**. Measured on a live 1080p60 stream, same session, same link:

| | H.264 (software) | **HEVC (hardware)** |
|---|---|---|
| Eclipse CPU | **54.5%** | **20.0%** |
| Bitrate carried | 15 Mbps | **23 Mbps** |
| Encoder | `h264_vaapi` | `hevc_vaapi` |

**2.7× less CPU while carrying 50% more bitrate** — and HEVC is ~30–50% more efficient per bit
on top of that, so 23 Mbps HEVC ≈ 30–35 Mbps of H.264. Confirm the hardware path in the client
log (`$ADDON_PROFILE_PATH/moonlight-qt.log`):

```
Hwaccel V4L2 HEVC stateless V4; devices: /dev/media0,/dev/video19; buffers: src DMABuf, dst DMABuf
```

⚠️ The later line `FFmpeg-based video decoder chosen` is just Moonlight's wrapper label — it does
**not** mean software decode. Check for the `Hwaccel V4L2` line instead.

> **The green bar is gone.** `hevc_mode` was pinned to `1` from 2026-08-08 because `hevc_vaapi`
> produced a green bar along the bottom of the stream. Retested 2026-09-27 on the **RX 9060 XT**
> with **Sunshine 2026.516** — artifact does not reproduce, confirmed on the TV. It was an older
> Sunshine on a different GPU. **If a green bar ever returns, set `hevc_mode = 1`** — that is the
> only value which truly forces H.264.

**`hevc_mode = 0` does NOT mean "off" — it means auto** (advertise whatever the encoder supports).
This was wrong in this doc and in `Modules/Gaming/sunshine.nix` until 2026-08-08. It went unnoticed for
months because the Android client never requested HEVC; the Pi 5 *does* request it.

- **Not `3` (Main10):** Eclipse cannot output HDR at all, so 10-bit only adds decode cost.
- **Not AV1:** the GPU advertises `av1_vaapi`, but the Pi 5 has no AV1 hardware decoder, so AV1
  would land straight back in software.

**`output_name` must be the CONNECTOR NAME, not a numeric index.** With `output_name = 1`, the
startup and encoder-probe paths honour the index and log `Selected monitor [... HDMI-A-1]`, but the
real capture initialiser — the selection made immediately *after* `CLIENT CONNECTED` — ignores it and
falls back to monitor 0 (DP-2). The stream silently showed the ultrawide desktop while the startup
logs looked perfectly correct. Fixed 2026-08-08 by using `output_name = HDMI-A-1`.
**When verifying, only trust the `Selected monitor` line that comes AFTER `CLIENT CONNECTED`** —
the earlier ones are probes and will happily report the right monitor while the stream uses another.

**Sunshine captures a fixed monitor — it does NOT move the game there.** `output_name` grabs
HDMI-A-1, so a game only appears on the stream if it actually opens on HDMI-A-1. Games default to the
primary (DP-2 ultrawide), which would stream the wrong (empty) monitor. Cult of the Lamb has no
in-game monitor picker, so it's pinned with a **niri window rule** (`Modules/Desktop/niri.nix`,
alongside the Spotify one):
```kdl
window-rule {
  match app-id="^steam_app_1313140$"   // Xwayland/Steam app-id = steam_app_<appid>
  open-on-output "HDMI-A-1"
  open-fullscreen true
}
```
Compositor-enforced, so it always lands on the captured output. Also set the game's own resolution to
**1920x1080** (in-game video settings — resolution is selectable even though the monitor isn't) so the
render matches the output and niri isn't upscaling. Same recipe works for any game: get its app-id
from `niri msg windows` while it runs, add a rule. Needs a rebuild + **re-login** (niri only reads the
baked store config).
- `encoder = vaapi` — force AMD hardware encoding (initial write only)
- `fec_percentage = 20` — Forward Error Correction for packet loss recovery (initial write only)

**"Share Screen" dialog on every boot — fixed by `capture = wlr`.**
With `capture` unset (auto), Sunshine probes every capture backend at startup, including
XDG Portal — `[portalgrab] RemoteDesktop CreateSession` — and xdg-desktop-portal-gnome
answers that with the "An app wants to share your screen" dialog on the desktop. It is
purely a probe: it fails (`response code: 2`) and Sunshine falls through to `wlgrab`,
which is what streams either way. Niri implements `zwlr_screencopy_manager_v1`, so pinning
`capture = wlr` picks the working backend directly and no portal call is ever made.

Valid Linux values for `capture`: `nvfbc`, `wlr`, `kms`, `x11`, `kwin`, `portal`.
Diagnose with `journalctl --user -u sunshine -b | grep -i portal` — clean startup has no hits.

**5G streaming optimisations (server-side):**
- Kernel UDP buffers: `net.core.rmem_max` and `wmem_max` set to 25 MB (default ~212 KB too small for bursty 5G)
- `netdev_max_backlog = 5000`

### ⚠️ Idle screen-off vs a controller-only stream

Sisyphus DPMS's its monitors off after 5 minutes idle (noctalia `[idle]`, see
`Claude/noctalia.md`), and **Sunshine takes no idle inhibitor**. Moonlight's
injected keyboard and mouse events arrive as real uinput devices, so they reset
the idle timer — but a **gamepad-only** session does not: niri's libinput seat
never sees the pad, the timer runs out, the screens power off, and the wlr
capture goes dark with them.

Before a couch/controller stream, hold idle off with the bar's Caffeine toggle or:

```bash
noctalia msg caffeine-enable     # ... caffeine-disable when done
```

A cleaner fix, if this becomes a nuisance, is Sunshine's own `global_prep_cmd`
(do/undo at stream start/end) calling `caffeine-enable` / `caffeine-disable` —
not wired up, because `sunshine.conf` is web-UI-owned here and only three keys
are sed-enforced by `Modules/Gaming/sunshine.nix`.

## Tailscale

- Stock Tailscale (no Headscale)
- Sisyphus IP: `100.70.29.3`, Asgard IP: `100.126.205.100` (verify current with `tailscale ip`)
- Auth on this host is handled **interactively** (`sudo tailscale up`). A `tailscale-auth-key` DOES exist in sops, but `Modules/Core/tailscale.nix` does not read it — its only consumer is the second tailscaled on Asgard (`Modules/Server/marsbar.nix`). The Apollo installer uses a separate `tailscale-installer-key` delivered on the USB stick, not from sops at runtime — see `Claude/deploy.md`.

## Moonlight Setup (Android)

- Add PC manually by Tailscale IP (mDNS auto-discovery doesn't work over Tailscale tunnels)
- Pairing: Moonlight shows PIN on phone → enter it in Sunshine web UI → paired permanently
- DualSense: pair to Android via Bluetooth, Sunshine translates inputs to uinput on PC side
- Recommended settings: 1080p, 10–20 Mbps bitrate, 30fps (half bandwidth of 60fps), H.265 enabled

Disconnect from stream: `Ctrl+Alt+Shift+Q`

## Eclipse — Raspberry Pi 5 (TV client)

**See `Claude/eclipse.md` for the full box** (LibreELEC/Kodi, Jellyfin, skin, CEC, headless workflow).

Rebuilt 2026-08-02 from Raspberry Pi OS to **LibreELEC 12.2.1**. Moonlight is now the
`plugin.program.moonlight-qt` Kodi addon rather than a native install.

- `ssh root@100.80.62.3` — **tailnet, joined 2026-08-03.** Prefer this: the LAN address is DHCP
  and has already moved once (`.184` → `.183` on 2026-08-04). The old `100.78.125.37` /
  "jimmythesquirrel.github" values were Headscale-era residue from before the June 2025 migration
  to stock Tailscale.
- Moonlight addon needs **EGL card = card1** on Pi 5, and a gamepad — remotes don't work inside it.

**TV streaming settings:** 1080p, 30-50 Mbps, 60fps, **H.265 on** — since 2026-09-27 the host
advertises HEVC (`hevc_mode = 2`) and the Pi hardware-decodes it. See *HEVC is the correct codec*
above for the measured difference.

⚠️ **The client had NO resolution/bitrate settings stored at all**, so it silently defaulted to
**720p @ 7.3 Mbps** — the numbers in this doc were aspirational, not actual. Rather than editing
`Moonlight.conf` (which the client rewrites on exit), pass them per-launch:

```bash
... stream 192.168.0.13 "<App>" --1080 --fps 60 --bitrate 30000 --display-mode fullscreen
```

**Moonlight reserves ~25% of the requested bitrate for FEC** — ask for 30000 and Sunshine
negotiates ~23 Mbps of actual video. Not a fault; scale the request up accordingly.

⚠️ **Use the LAN IP (`192.168.0.13`), not the tailnet IP**, now that both are on the same subnet.

### Headless pairing and remote launch (no TV navigation needed)

The whole flow can be driven over SSH. Useful when the box is unattended or the GUI is stuck.

`launch_moonlight-qt.sh` passes its args straight through to `moonlight-qt`, and stops/restarts Kodi
via its distro hooks:
```bash
ssh root@100.80.62.3 'systemd-run --unit=moonlight-test \
  --setenv=ADDON_PROFILE_PATH=/storage/.kodi/userdata/addon_data/plugin.program.moonlight-qt \
  /bin/bash /storage/.kodi/addons/plugin.program.moonlight-qt/resources/bin/launch_moonlight-qt.sh \
  stream 100.70.29.3 "Cult of the Lamb"'
```

**Pass an IP, never a bare hostname.** `stream Sisyphus` makes Moonlight create a *new* PC record from
that string, fail to resolve it (`HostNotFoundError`), and then report the misleading
`Computer Sisyphus has not been paired` — even though pairing is perfectly fine. `100.70.29.3` works.

**Pairing headlessly** — `moonlight-qt pair <host> --pin <pin>` lets you choose the PIN instead of
reading it off a GUI dialog, so it can be paired with Sunshine's API in one go. It still starts the QML
engine, so it needs the full Qt env that `bootstrap_moonlight-qt.sh` normally sets
(`QT_PLUGIN_PATH`, `QML_IMPORT_PATH`/`QML2_IMPORT_PATH`, `LD_LIBRARY_PATH`, `XDG_RUNTIME_DIR=/var/run`,
`HOME=$ADDON_PROFILE_PATH/moonlight-home`). With `QT_QPA_PLATFORM=offscreen` it needs no DRM, so **Kodi
can keep running**. Then submit the same PIN to the host:
```bash
curl -sk -u 'USER:PASS' -X POST https://localhost:47990/api/pin \
  -H 'Content-Type: application/json' -d '{"pin":"4721","name":"Eclipse-TV"}'
```
Confirm with `GET /api/clients/list`. Missing `QT_PLUGIN_PATH` produces
`No functional TLS backend was found` → `Newly generated certificate is unreadable` — that is a
**broken invocation env, not a broken addon**; the addon's own bootstrap sets it and TLS works fine.

### ⚠️ Getting back to Kodi — read this before "fixing" anything

**`systemctl stop` on the unit kills the Kodi-restart trap.** The `start.sh` hook restores Kodi
via a bash `trap ... EXIT`, which only runs when *moonlight-qt itself* exits. Stopping the systemd
unit SIGTERMs the whole cgroup, the trap dies mid-flight, and the TV is left black. Recover with
`systemctl start kodi`.

**The LibreELEC hook is customised** (not upstream's one-liner) and deliberately waits before
restarting Kodi — up to 10 s for `moonlight-qt` to exit, then a 3 s settle so the kernel reaps the
DRM master fd. Grabbing the GPU too early makes Kodi's GBM backend fail to init and come up on a
dead display, *which looks exactly like a hang*. **So expect ~15 s of black screen. Do not
intervene during it** — that is how the trap gets killed.

**It logs every run — this file is the ground truth:**

```bash
cat /storage/moonlight-exit.log
#  <ts> moonlight exited, waiting for DRM release
#  <ts> starting kodi (drm status: connected)      ← BOTH lines = trap completed
```

A first line with no second line means the trap was interrupted (almost always by someone
stopping the unit).

**Backing out of a stream does NOT exit Moonlight.** It goes stream → app list → PC list, which
is the addon's own GUI; Kodi only returns when **moonlight-qt exits**. Back out past the PC list.
The in-stream quit combo is **`Start+Select+L1+R1`** (DualSense: **Options + Create + L1 + R1** —
Create is the small button *left* of the touchpad, **not** the PS button).

⚠️ **Diagnose with the DRM owner, never `systemctl is-active kodi`.** Kodi's service can be
active while Moonlight renders on top — both hold `card1` simultaneously and the service state
tells you nothing about what is on screen:

```bash
for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -q card1 && \
  echo "$(basename $p): $(cat $p/comm)"; done
```

Also check for a **second** Moonlight unit: launching from Kodi's Games tab creates its own
transient `run-<hash>.service`, so stopping `moonlight-test` may be killing nothing.

### 🔇 No stream audio — PulseAudio falls back to `auto_null`

Sunshine and the network are innocent: the client log will show
`Received first audio packet after N ms`. The problem is that **PulseAudio on Eclipse never claims
the HDMI card** and falls back to the null sink, so audio plays into the void.

```bash
pactl list short sinks        # 0  auto_null  module-null-sink.c   ← the bug
pactl load-module module-alsa-sink device=hdmi:CARD=vc4hdmi0,DEV=0 sink_name=hdmi_out
pactl set-default-sink hdmi_out
pactl move-sink-input <id> hdmi_out       # move the already-running stream
```

**Kodi is unaffected because it opens ALSA directly** (`hdmi:CARD=vc4hdmi0,DEV=0`) and never uses
PulseAudio — which is why Jellyfin has sound while Moonlight doesn't. Two audio paths, one box.

⚠️ The fix above is **in-memory only and dies on reboot.** Durable options: add
`--setenv=SDL_AUDIODRIVER=alsa` to the launch so Moonlight skips PulseAudio entirely (preferred —
same path Kodi proves works), or persist the module in Eclipse's PulseAudio config.

### 🎮 DualSense only auto-reconnects to its LAST host

Moonlight reads the gamepad on the **client** (Eclipse), not the host. A DualSense paired to both
machines reconnects to whichever it used last — usually Sisyphus — so the stream sees no pad at
all. Untrusting it on Sisyphus is **not** enough; the stale bond on Eclipse has to go:

```bash
# Sisyphus
bluetoothctl disconnect <MAC>; bluetoothctl untrust <MAC>
# Eclipse — remove the bond, then make the adapter pairable (it defaults to NO)
bluetoothctl remove <MAC>
bluetoothctl pairable on; bluetoothctl agent on; bluetoothctl default-agent
bluetoothctl --timeout 180 scan on &     # hold PS + Create until the light bar flashes fast
bluetoothctl pair <MAC> && bluetoothctl trust <MAC> && bluetoothctl connect <MAC>
```

Success = **`/dev/input/js0` and `js1`** (two nodes is normal: gamepad + motion sensor). SDL
hotplug works, so Moonlight picks it up mid-session — no restart needed. Whichever host pairs last
becomes the default; moving it back needs the same PS+Create dance.

### 🖱️ Sunshine leaves a virtual ABSOLUTE pointer on the host

Sunshine creates uinput devices to inject client input, and keeps them for its whole lifetime —
not just during a session:

```
N: Name="Mouse passthrough"
N: Name="Mouse passthrough (absolute)"     ← mapped to the CAPTURED output's coordinate space
N: Name="Keyboard passthrough"
```

The absolute one is mapped to `output_name` (HDMI-A-1, 1920×1080), so a stray event yanks the
cursor into that region — presenting as **"my mouse is locked to the top monitor"** on the desktop
long after streaming ended. **Confirmed 2026-09-27:** the pointer freed the instant Sunshine was
stopped.

```bash
grep "^N: Name" /proc/bus/input/devices | grep -i passthrough   # are they present?
systemctl --user stop sunshine                                  # the only thing that removes them
```

⚠️ **Restarting Sunshine does NOT help** — the devices are recreated at startup. Only stopping it
works. Sunshine only needs to be running when you actually want to stream; leaving it up idle
costs you the desktop pointer.

### ⚠️ Only Cult of the Lamb has a niri output rule

Sunshine captures **HDMI-A-1**. Any game without a rule opens on DP-2 and the TV shows the
desktop instead of the game (hit with Stray, 2026-09-27). Fix live with
`niri msg action move-window-to-monitor --id <id> HDMI-A-1`, but that is not durable.

- Stray reports a clean `app_id` **`steam_app_1332010`** → a normal rule works.
- Cult of the Lamb runs under **gamescope**, so its `app_id` is `(unset)` and its rule matches on
  **`title="^Cult Of The Lamb$"`** — that line is load-bearing.

### Sunshine app list is cached — a new app needs a service restart

Adding an entry to `~/.config/sunshine/apps.json` (plain imperative state, **not** Nix-managed) is
not picked up live. The client reports `Qt Critical: Failed to find application <name>`, which
looks client-side but is the host not advertising it. `systemctl --user restart sunshine`.
A **still-running app also blocks launching a different one** — the new request attaches to the
existing session instead. Close the old game first.

## sops.nix Path Note

`defaultSopsFile` must use `../Secrets/secrets.yaml` (one level up from `Modules/`), NOT `../../` which resolves to `/nix/store/Secrets` and breaks pure evaluation.
