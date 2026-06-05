# Game Streaming — Sunshine, Moonlight, Tailscale, Controller

## Overview

Sisyphus runs **Sunshine** as a game streaming host, accessible remotely via **Tailscale**, streamed to Android phone or TV (via Eclipse Pi) using **Moonlight**.

**Modules (Sisyphus only):**
- `Modules/sunshine.nix` — Sunshine user service
- `Modules/tailscale.nix` — Tailscale VPN (auth key via sops)
- `Modules/controller.nix` — DualSense desktop navigation daemon

`moonlight-qt` is in `base.nix` and available on all three systems.

## Sunshine

- Runs as a **user service** (`autoStart = true`) — starts automatically on Niri login
- `hardware.uinput.enable = true` — allows Sunshine to send virtual input to Linux
- `openFirewall = true` + `trustedInterfaces = [ "tailscale0" ]` — reachable over Tailscale without extra firewall rules
- Tailscale auth key stored in sops (`tailscale-auth-key`), auto-authenticates on rebuild

**Web UI:** `https://localhost:47990` (self-signed cert, accept warning) — set credentials on first run

**Display selection** (Sunshine web UI → Configuration → Audio/Video → Display Number):
- `card1-DP-2` — 2560x1080 @ 144Hz (primary ultrawide)
- `card1-HDMI-A-1` — 1920x1080 @ 60Hz (secondary, better for phone streaming)

**`sunshine.conf` seeded** via home-manager activation. Initial write happens when the file is empty/missing; web UI changes survive rebuilds — EXCEPT two values that are **always patched**:
- `hevc_mode = 0` — H.264 only (**not** H.265). AMD VAAPI HEVC has an alignment bug that produces a green bar at the bottom of the stream. Always enforced to prevent regression.
- `output_name = 1` — HDMI-A-1 (1920x1080). Always enforced so streaming targets the 1080p monitor.
- `encoder = vaapi` — force AMD hardware encoding (initial write only)
- `fec_percentage = 20` — Forward Error Correction for packet loss recovery (initial write only)

**5G streaming optimisations (server-side):**
- Kernel UDP buffers: `net.core.rmem_max` and `wmem_max` set to 25 MB (default ~212 KB too small for bursty 5G)
- `netdev_max_backlog = 5000`

## Tailscale

- Tailscale IP: `100.119.193.77` (check current with `tailscale ip`)
- Auth key in sops, auto-applied on rebuild

## Moonlight Setup (Android)

- Add PC manually by Tailscale IP (mDNS auto-discovery doesn't work over Tailscale tunnels)
- Pairing: Moonlight shows PIN on phone → enter it in Sunshine web UI → paired permanently
- DualSense: pair to Android via Bluetooth, Sunshine translates inputs to uinput on PC side
- Recommended settings: 1080p, 10–20 Mbps bitrate, 30fps (half bandwidth of 60fps), H.265 enabled

Disconnect from stream: `Ctrl+Alt+Shift+Q`

## Eclipse — Raspberry Pi 5 (TV client)

Eclipse is a Pi5 running **Raspberry Pi OS (64-bit graphical)** — not managed by this repo. Used as a Moonlight client connected to the TV.

- **OS:** Raspberry Pi OS Trixie 64-bit graphical
- **Tailscale:** authenticated to jimmythesquirrel.github tailnet, IP `100.78.125.37`
- **Moonlight:** installed natively on Pi OS, connects to Sisyphus
- SSH in: `ssh pi@100.78.125.37`

**TV streaming settings:** 1080p, 30-50 Mbps, 60fps, H.265 enabled

## DualSense Controller Desktop Navigation

**Module:** `Modules/controller.nix`

Runs a Python evdev daemon (`controller-mapper`) as a systemd user service. Reads Sunshine's virtual uinput gamepad and emits events via a virtual UInput keyboard device. The DualSense touchpad handles mouse movement natively through Sunshine.

**Button mapping (desktop mode):**

| Input | Action |
|---|---|
| Left stick | Arrow keys (menu navigation, with auto-repeat) |
| D-Pad | `Super+Arrow` → Niri window/workspace focus |
| X (South) | Enter |
| Circle (East) | Escape |
| Triangle (North) | `niri msg action close-window` |
| Square (West) | `noctalia-shell ipc call launcher toggle` |
| L1 | `skwd wall toggle` |
| R1 | `niri msg action toggle-overview` |
| Options | `noctalia-shell ipc call sessionMenu toggle` |
| PS button | Toggle desktop/game mode |

**Desktop mode toggle:**
- Default: **on** (ready for desktop nav)
- PS button → **game mode** — all mappings suppressed so controller input goes cleanly to the game
- `notify-send` notification confirms mode change

**Implementation notes:**
- Python `evdev` + `UInput` — no process spawning per frame, direct kernel input writes
- `find_gamepad()` retries every 3s — service stays alive when no Moonlight client connected
- `find_gamepad()` skips real Bluetooth devices (`dev.phys` contains `XX:XX:XX:XX:XX:XX` MAC) — prevents grabbing a directly-connected DualSense used by RPCS3
- Left stick auto-repeat: fires immediately, 400ms initial delay, then every 120ms (dominant axis wins)
- D-Pad Super+Arrow runs in a thread to avoid blocking event loop during 50ms key hold
- Requires user in `input` group (read `/dev/input/event*`) and `uinput` group (write `/dev/uinput`)
- `hardware.uinput.enable` (from `sunshine.nix`) provides udev rules for `uinput` group

## sops.nix Path Note

`defaultSopsFile` must use `../Secrets/secrets.yaml` (one level up from `Modules/`), NOT `../../` which resolves to `/nix/store/Secrets` and breaks pure evaluation.
