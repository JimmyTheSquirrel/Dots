# Eclipse — Raspberry Pi 5 TV Box (LibreELEC + Kodi)

**Host:** Eclipse · Raspberry Pi 5 · `100.80.62.3` (tailnet, as `eclipse`)
**LAN (DHCP):** `192.168.0.182` (eth0) · `192.168.0.183` (wlan0) — two MACs, two leases
**Link:** wired ethernet since 2026-08-23, with 2.4 GHz wifi as an automatic hot standby. See *Network*.
**OS:** LibreELEC 12.2.1 aarch64 (Kodi 21 Omega)
**Purpose:** Jellyfin playback on the TV, driven by the TV remote; also a Moonlight client.

> **NOT MANAGED BY NIX.** Everything here is imperative state on an SD card. A rebuild means
> re-flashing and redoing these steps by hand — this file is the recipe. Built 2026-08-02,
> replacing Raspberry Pi OS Trixie (its desktop was too laggy on a TV and had no CEC).

## ⚠️ 2026-10-05 — audit, her UX list, and what is now in the repo

The box was audited and reworked. **Two directories in the repo now mirror it** — nothing here
is applied automatically, they are what you restore *from*:

| Repo path | What |
|---|---|
| `Resources/Eclipse-Skin/` | The Bingie layout overlay + `eclipse-skin-push.sh`. **Re-run that script after any skin update** or her layout reverts. `bingie-history/` holds the 15 superseded `.bak` files. |
| `Resources/Eclipse-Box/` | Custom units, the Moonlight fork, the three addon patch scripts, keymaps, and the evidence logs. Has its own README explaining each. |

**Fixed:**

- 🔴 **`hdmi-hotplug.service` had never once survived a reboot.** `After=`/`Wants=kodi.service`
  closed an ordering cycle (`multi-user → hdmi-hotplug → kodi → graphical → multi-user`) and
  systemd deleted the job from every boot transaction. The unit sat `enabled` + `inactive (dead)`
  with no failure to notice. Both lines removed; verified across a real reboot.
- **Playback sluggishness was `filecache.readfactor=2000`** — 20× read-ahead with a 512 MB buffer
  on a path that is entirely wireless. Now **500** / **160 MB**.
- **`docker.service` reported `failed` while dockerd ran** — `kodi.target.wants/` held *both*
  `docker.service` and `service.system.docker.service` pointing at the same unit, which also
  declares `Alias=docker.service`. Dropped the duplicate; single clean `active (running)`.
- **`act_reboot` in eclipse-control.py never rebooted the Pi.** `(sleep 1; reboot) &` is killed
  when sshd SIGHUPs the process group, but ssh exited 0 so the button reported success. Now
  `systemctl --no-block reboot`.
- **Her layout:** info panel 600px (55.6%) → **276px (26%)**, grid **12 → 6 posters per row**
  (tile 131×186 → 279×396), two full rows. Buffer bar → `ff4B2882`.
- **Removed:** `skin.aeon.tajo` + its helper (which ran 7751-image library scans 22× in 46h with a
  100% zero-result rate), `skin.arctic.zephyr.mod`, `skin.bello.10`, 11 unused uisounds, the
  341 MB package cache. **~700 MB; /storage is now 1.5 G.**

**Two things that must NOT be removed**, both verified the hard way:

- `resource.images.studios.coloured` — `skin.bingie/addon.xml:10` has a hard `<import>` on it and
  `IncludesFooter.xml` draws studio logos from it. Removing it breaks the active skin.
- **Docker** — the Moonlight addon's first launch is a Docker *build*; there is a
  `debian:bookworm-slim` image on the box for it.

**New dashboard card** (`#ec-ctl`, both dashboards): controllers, network path, and the subtitle
default. See *Control panel* below.

## Access

```bash
ssh root@100.80.62.3            # tailnet; key auth; pubkey at /storage/.ssh/authorized_keys
ssh root@192.168.0.182          # LAN;     same key  (was .183, moved again 2026-09-28)
```

**Use the tailnet address.** The LAN lease is not reserved and has now moved **twice** —
`.184` until 2026-08-04, `.183` until 2026-09-28, now `.182`. The first move produced a
confusing `No route to host` mid-session. Find the current one with
`tailscale status | grep eclipse`, which prints the direct LAN endpoint.

⚠️ **This address drift is worth fixing properly with a DHCP reservation on the router.**
Both Eclipse and Sisyphus are on DHCP, and Sisyphus's `192.168.0.13` is what Moonlight
stores as the stream host — if *that* one moves, streaming breaks with no obvious cause.
Do **not** "fix" it by streaming over the tailnet: the tailnet path between these two is
already direct over the same LAN wire, so it only adds WireGuard CPU on the Pi and a
1280 vs 1500 MTU (~17% more packets). See `Claude/wolf.md`.

Root fs is **read-only**; `/storage` is the writable home. Root password was set in the
first-boot wizard to the `admin-password` sops secret.

## Tailscale (added 2026-08-03)

**There is no Tailscale addon for LibreELEC** — the official 12.2 repo has zero mentions of it
(`service.system.*` offers only docker, podman, syncthing, tinc). Don't go looking again. It runs
from the official static aarch64 binaries plus a custom systemd unit.

```
/storage/tailscale/{tailscale,tailscaled}     # static binaries, v1.98.10
/storage/.config/system.d/tailscaled.service  # LibreELEC's supported custom-unit dir
/storage/.config/tailscale/                   # --statedir, survives OS updates
```

`/storage/.config/system.d/` is the documented LibreELEC mechanism for user units — it ships
`wireguard.service.sample` and `openvpn.service.sample` alongside. Everything lives under
`/storage`, so **a LibreELEC OS update does not wipe this**; only a card re-flash does.

Two non-obvious flags are **required** on this platform, both already persisted in
`tailscaled.state`:

| Flag | Why |
|---|---|
| `--netfilter-mode=off` | LibreELEC's kernel has **no connmark module** (`find /lib/modules -name "*connmark*"` → nothing). Without this, tailscaled spams `CONNMARK revision 0 not supported` / `unknown option "--nfmask"`. Fine here — Eclipse is a plain client, no exit node or subnet routes. |
| `--accept-dns=false` | `/etc` is read-only squashfs, so Tailscale cannot write `resolv.conf` (`open /etc/resolv.pre-tailscale-backup.conf: read-only file system`). **No MagicDNS** — address tailnet hosts by IP. ConnMan keeps owning DNS, which works fine. |

Reinstall/upgrade:

```bash
curl -sfL -o ts.tgz https://pkgs.tailscale.com/stable/tailscale_<ver>_arm64.tgz
tar -xzf ts.tgz && cp tailscale_<ver>_arm64/tailscale{,d} /storage/tailscale/
chmod +x /storage/tailscale/tailscale*
systemctl daemon-reload && systemctl restart tailscaled
```

The CLI needs the socket path when called by full path:

```bash
/storage/tailscale/tailscale --socket=/run/tailscale/tailscaled.sock status
```

Verify healthy with `tailscale status` — the `# Health check:` block should be absent entirely.

Eclipse was enrolled interactively (`tailscale up` prints a login URL to visit). For the next node,
sops already holds a **`tailscale-auth-key`** — `tailscale up --authkey=...` skips the browser
round-trip entirely.

## Control panel (both dashboards)

`eclipse-control` on Asgard (`:9554`) is an API with a live event stream; **both dashboards
draw the same panel from it** with the same script, `Resources/Glance/eclipse.js` — the admin
Glance's **Eclipse** page directly, MarsBar's Eclipse page through her `/eclipse-api` serve
mount. She has every control he has (`Claude/marsbar.md`).

- Service: `systemd.services.eclipse-control` in `Modules/Server/eclipse.nix`
- Implementation: `Resources/Eclipse-Control/eclipse-control.py`
- Auth: dedicated keypair, private half in sops as `eclipse-ssh-key`, public half appended to
  Eclipse's `/storage/.ssh/authorized_keys` (backup at `authorized_keys.bak`)

| Endpoint | What |
|---|---|
| `GET /events` | SSE: `status`, `tv`, `wolf`, `activity`, `busy` — pushed on change. The Pi is only polled (SSH every 5 s, one channel on the shared ControlMaster) while a page has this open; Wolf every 3 s; Jellyfin every 5 s |
| `GET /status` | the Pi's state as JSON (cached 5 s, in-flight de-duplicated) |
| `POST /act/<name>` | `restart-kodi`, `sync-library` (Movies then TV Shows), `sync-movies`, `sync-shows`, `speedtest` (the Pi→Asgard link test), `jellyfin-toggle`, `reboot`, `ctl-scan`, `subs-on`, `subs-off`. One run per action at a time (409 otherwise); every result lands in the shared activity log |
| `POST /ctl/connect/<MAC>` · `/ctl/disconnect/<MAC>` | Connect or drop a paired controller. The MAC is checked against `MAC_RE` **and** the Pi's own `bluetoothctl devices` list before it reaches a root shell — same precedent as `wolf_stop`'s `isdigit()` |
| `POST /ctl/sublang/<iso639-2>` | Subtitle language, whitelisted against `SUB_LANGS` |
| `POST /wolf/stop/<id>` | end a Moonlight stream on Sisyphus, via wolf-bridge (`Claude/wolf.md`) |

Every POST needs `X-Dash: 1`; CORS answers only `_origins.nix`.

### Controllers · `#ec-ctl` (added 2026-10-05)

A `ctl` event on the same `/events` stream (8 s, slower than the rest because it shells out to
`bluetoothctl`, whose daemon has form for burning CPU). Both dashboards draw it.

⚠️ **`connected` is not the same as working, and this is the whole point of the card.** The
DualSense here fails to bind its kernel driver with **`-5` (EIO)** often enough to matter — 17
reconnect cycles and 3 probe failures in the logs. In that state BlueZ reports `Connected: yes`
while `/proc/bus/input/devices` has no node for it: a bonded device producing **no input at all**.
So the payload reports `connected` (BlueZ) and `live` (has an input node) separately, and flags
the combination as `stale`. **A helper that trusted BlueZ alone would show a working controller in
exactly the broken case.** Recovery from `-5` needs remove + re-pair, not `connect`.

Pairing a *new* pad cannot be fully automated: a DualSense only advertises while physically held
in **PS + Create**, so Scan is a bounded `bluetoothctl --timeout` window and the card says so.
Scan also issues `pairable off` in the same breath rather than leaving the Pi open to radio range.

⚠️ Connecting a pad to Eclipse **steals it from Sisyphus** — a DualSense only ever talks to its
last host — so Connect is arm/confirm like Reboot.

**Subtitles are a Jellyfin USER setting, not a Kodi one.** `jellyfin-kodi` runs `set_audio_subs()`
~2 s into every playback and calls `showSubtitles(False)` when no track resolves, so anything set
Kodi-side is overwritten on every single play. The toggle writes `SubtitleMode`
(`Always`/`Default`) on the user Eclipse logs in as — `JELLYFIN_TV_USER` in `eclipse.nix`.
Jellyfin wants the **whole** Configuration object back, so it is read-modify-write; POSTing one
key silently resets the rest.

**Status** now also carries the SoC temperature, `vcgencmd get_throttled` decoded into
what is wrong *now* and what has happened *since boot* (under-voltage is the Pi 5's classic
silent problem — the panel raises a banner for it), load and memory. **On the TV** is
Jellyfin's session list filtered to the Kodi addon (client `Kodi`), with the poster — not Kodi's
JSON-RPC, which is loopback-only and is exactly what a wedged Kodi cannot answer.

**Driven over SSH, not Kodi JSON-RPC** — deliberately. The headline action is restarting a *wedged*
Kodi, and a wedged Kodi cannot answer its own API. Kodi's HTTP server is disabled here anyway
(`services.webserver=false`; JSON-RPC binds `127.0.0.1:9090`).

The status encodes the "no signal on a healthy box" trap: HDMI `connected` + Kodi `active` +
**no output mode** raises a banner and highlights Restart Kodi. Re-flashing the SD card means
re-appending the public key, or the panel shows `reachable: false`.

The panel used to be an HTML page this service served, iframed into Glance at a fixed height,
with its own copy of JetBrains Mono so it matched — on the belief that Glance's `html` widget
sanitises markup. It does not (0.8.5 emits it raw), so the page, the fonts and the iframe are gone.

## Rebuild from scratch

```bash
curl -LO https://releases.libreelec.tv/LibreELEC-RPi5.aarch64-12.2.1.img.gz   # RPi5 image, not RPi4
gzip -dc LibreELEC-RPi5.aarch64-12.2.1.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Then: boot → wizard (hostname `Eclipse`, enable SSH) → push SSH key → install addons → Jellyfin
login → sync libraries → skin config. Details below.

- **Do not pre-stage files on the STORAGE partition before first boot.** LibreELEC repopulates
  `/storage` from its own skeleton and wipes them (dir timestamps revert to the image build date).
  Copy over SSH after boot.
- `/storage` auto-expands to fill the card on first boot.

## Headless control (how to work on this box)

`sqlite3` **is** on LibreELEC 12.2.1 (`/usr/bin/sqlite3`) — query DBs in place. (Older note said it
wasn't; it is now.) Kodi rewrites its DBs on exit, so **stop Kodi before editing them**.

**Installing a repo addon headlessly**: `kodi-send --action="InstallAddon(<id>)"` opens a
`DialogConfirm` on the TV and waits. Accept it blind with `kodi-send --action="SendClick(11)"`
(11 = the affirmative button); the addon then downloads. Confirm with
`ls /storage/.kodi/addons/<id>` and `grep <id> /storage/.kodi/temp/kodi.log`. `repository.xbmc.org`
is bundled in the LibreELEC image (not under `/storage/.kodi/addons`), so official-repo addons install.

```bash
kodi-send --action="ActivateWindow(Home)"       # /usr/bin/kodi-send — drives Kodi remotely
kodi-send --action="TakeScreenshot"             # → /storage/screenshots/ ; scp back and LOOK
kodi-send --action="ReloadSkin()"
systemctl restart kodi
```

Screenshots are the fastest way to verify UI work — don't infer from logs. Main log:
`/storage/.kodi/temp/kodi.log`.

**Screenshots do not capture video during playback.** On GBM the video sits on a separate DRM
plane, so a shot taken mid-playback shows the OSD over a black frame. That is a capture artifact,
not a playback fault — don't chase it.

### Kodi settings over JSON-RPC

The HTTP server is off, but JSON-RPC listens on `127.0.0.1:9090` (raw TCP). Driving settings this
way beats editing `guisettings.xml` — it validates against the real option list and applies live,
with no restart and no risk of writing a value Kodi will reject:

```python
s = socket.create_connection(("127.0.0.1", 9090), 5)
s.sendall(json.dumps({"jsonrpc":"2.0","id":1,"method":"Settings.SetSettingValue",
                      "params":{"setting":"locale.timezone","value":"Australia/Sydney"}}).encode())
```

Useful methods: `Settings.GetSettings` (with `filter`, returns the valid `options`),
`Settings.SetSettingValue`, `Application.SetMute` / `SetVolume`, `VideoLibrary.GetMovies`,
`Player.Open` / `Seek` / `Stop`, `Input.ShowOSD`.

**Read the reply defensively** — Kodi interleaves async notifications on the same socket, so a
naive `json.loads` of everything received can hit `JSONDecodeError: Extra data`. Parse
incrementally and stop at the first complete object.

**`kodi-send` silently fails on `RunScript(...)` actions with `&` parameters** — no error, no log
line. Skin Shortcuts' `buildxml` could not be triggered this way. Simple builtins work fine.
(`RunPlugin(...)` with `&` *does* work — that's how the Jellyfin sync is triggered.)

**`kodi-send` exit code only means "message delivered", never "action ran."** It returns 0 while
the addon throws. Anything automated must confirm the outcome in `kodi.log` — the control panel
watches for `Full sync completed` vs `PythonToCppException`.

**Transient `synclib` failure:** after a dropped server connection the Jellyfin addon's
`library_thread` is `None`, so a sync raises
`AttributeError: 'NoneType' object has no attribute 'add_library'`. The exception path reconnects
by itself, so **retrying once recovers it** — the panel does this automatically.

## Jellyfin

**Server, as of 2026-09-11: `http://100.126.205.100:8096`** (Asgard's Tailscale IP). Eclipse moved
to a second house and is no longer on Asgard's LAN (`192.168.0.226:8096`, still correct if it ever
comes back). Signed in as **Caitlin**.

### Switching between LAN and remote

The addon's server address lives in **two places that must be kept in sync**:
`addon_data/plugin.video.jellyfin/data.json` (`Servers[0].address`, what the addon actually
connects with) and `addon_data/plugin.video.jellyfin/settings.xml` (`id="server"`, cosmetic — shows
in the addon's own settings screen). Both, then `systemctl restart kodi` so the addon re-reads
`data.json`.

**There's a button for this now** — Glance → Eclipse page → "Jellyfin: switch to …". Backed by
`act_jellyfin_toggle()` in `Resources/Eclipse-Control/eclipse-control.py`, which reads the current
address out of `data.json`, flips it to whichever of `JELLYFIN_LAN` /`JELLYFIN_REMOTE` it *isn't*,
sed-replaces both files, and restarts Kodi. The status row's "Jellyfin" cell (also new) reads the
same field, so the button's label always reflects the actual current state rather than assuming one.

**Bundled with the addon's own `maxBitrate` cap, not just the server address** (2026-09-12) — the
same toggle also sed-replaces `settings.xml`'s `maxBitrate` between `JELLYFIN_BITRATE_LAN` (`"23"`
= uncapped) and `JELLYFIN_BITRATE_REMOTE` (`"10"` = 8 Mbps). This addon has zero ABR —
confirmed absent in its source and upstream's tracker — so on the remote link direct play at full
bitrate just stalls; an addon-side cap is what actually makes it watchable (distinct from and *on top
of* the server-side `RemoteClientBitrateLimit` below, which only fires the moment the client no
longer looks local).

**LAN is uncapped because the path measures 196 Mbps**, not because "LAN means gigabit" — see
*Known-good baseline* below. Verified 2026-09-27: the heaviest file in the library (*The Drama*,
51 GB, 68.9 Mbps 4K remux) direct-plays at **1.00× realtime with zero stalls**, decoder
`HEVC` with no CPU fallback.

⚠️ **Because the toggle rewrites `maxBitrate` on every press, a value hand-edited on Eclipse is
undone the next time anyone touches that button.** The durable place to change it is
`Resources/Eclipse-Control/eclipse-control.py`, then rebuild Asgard.

If the repeater ever regresses to 2.4 GHz and cannot be fixed promptly, `"17"` (20 Mbps) makes
playback watchable again. Verify a cap is actually firing by playing an oversized title and
checking the URL the addon builds:

```bash
/usr/bin/grep -a -oE "master\.m3u8[^\" ]{0,400}" /storage/.kodi/temp/kodi.log | tail -1
#   &TranscodeReasons=ContainerBitrateExceedsLimit      ← the cap fired
```

Healthy uncapped direct play instead shows `static=true` + `PlayMethod: DirectStream` and **no**
`master.m3u8` line at all.

**Speed Test button, same page** — `act_speedtest()` has Eclipse SSH-curl a 25MB zero-filled blob,
chunked so it never buffers 25MB in RAM. Reads `curl -w '%{speed_download}'`, caches the last result
in-process (resets on `eclipse-control.service` restart, by design — it's a point-in-time reading,
not history). Confirmed the WiFi regdom bug's ceiling this way: consistently ~10-16 Mbps.

#### Reworked 2026-09-19 — it now measures the path playback ACTUALLY uses

It was hardcoded to `ASGARD_TAILSCALE_IP`, so with Jellyfin on LAN it reported ~19 Mbps of
**WireGuard overhead** rather than the real link. It now picks the target from the current
Jellyfin mode (`lan` → LAN, `remote` → Tailscale) and the result says which.

⚠️ **A LAN test needs its own port.** `9554` is deliberately absent from `allowedTCPPorts`
(tailnet-only) because it carries every `/act/` verb including `reboot` — opening it to the LAN
to enable the test would expose those to anything on the wifi. So there is a second listener,
`SPEEDTEST_LAN_PORT` **9557**, with a `SpeedtestHandler` that has **no control surface at all**,
opened via `networking.firewall.interfaces."enp3s0".allowedTCPPorts`. Verified after: 9557
reachable on LAN, **9554 still HTTP 000 on LAN**.

Upload was added too — `dd | curl -T -` streamed into `do_PUT`, so nothing is written to the
Pi's SD card. LAN path only. Result: **44.1 down / 41.0 up Mbps**.

#### 🔍 The link runs through an ASUS RP-BE58 repeater — and its backhaul band is everything

> ⚠️ **This section previously concluded "Eclipse is the bottleneck, not the network."
> That was wrong.** It is the network. Corrected 2026-09-26 — the evidence below supersedes it.
> The old conclusion cost real time, because every subsequent stutter got filed under
> "the Pi is just slow" and the link was never re-measured.

## ✅ Known-good baseline — RP-BE58 on its 5 GHz backhaul

**This is what the link should look like. Measure against these numbers before theorising.**
Captured 2026-09-26 immediately after power-cycling the repeater onto 5 GHz:

| Test | 2.4 GHz backhaul (bad) | **5 GHz backhaul (correct)** | Ratio |
|---|---|---|---|
| Download, single stream | 47.6 Mbps | **196 Mbps** | 4.1× |
| Download, 4 parallel | 57 Mbps | **201 Mbps** | 3.5× |
| Upload | 43.4 Mbps | **115 Mbps** | 2.6× |
| Eclipse → gateway, avg | 30.2 ms | **6.65 ms** | 4.5× |
| Eclipse → gateway, max | 146 ms | **11.7 ms** | 12× |
| Eclipse → gateway, loss | **2%** | **0%** | — |
| Asgard → Eclipse, max | **471 ms** | **9.96 ms** | **47×** |

A single stream already saturates the path (196 vs 201 Mbps across four), so one `curl` against
the 9557 sink is a sufficient test — no need to parallelise.

**Regression signature — the repeater silently dropping to its 2.4 GHz backhaul:**

- throughput collapses to **~45 Mbps symmetric** (not one-directional — that matters)
- ping to the gateway goes from ~6 ms avg to **~30 ms avg with 100–470 ms spikes**
- **packet loss appears** (~2%), where 5 GHz shows exactly 0%
- everything on the Pi still looks perfect: `1000Mb/s full duplex`, zero error counters

It sat in this state for roughly ten days before anyone measured it, because Kodi merely
stutters rather than failing, and the Pi's own diagnostics stay green throughout. **A power cycle
of the repeater is what fixed it** — it re-scanned and re-associated on 5 GHz. Suspect this after
any power interruption in that room; a repeater that falls back to 2.4 GHz will happily stay
there indefinitely rather than re-evaluating.

```bash
# one-command health check, from Eclipse
curl -s -o /dev/null -m 25 -w '%{speed_download}\n' http://192.168.0.226:9557/
#   ~24000000 B/s (196 Mbps) = healthy 5 GHz
#   ~6000000  B/s (48 Mbps)  = fallen back to 2.4 GHz, power-cycle the repeater
```

### How the repeater was identified

Eclipse's ethernet does not run to the router. It goes through an **ASUS RP-BE58** WiFi 7
repeater at **`192.168.0.68`** (admin UI: ASUSWRT, `Main_Login.asp`, `Server: httpd/3.0`), so one
hop of the "wired" path is wireless. The Pi cannot see this — the repeater presents a clean
auto-negotiated gigabit port.

**The giveaway is a MAC mismatch.** The repeater does MAC translation for its downstream client,
so the rest of the LAN resolves Eclipse's IP to the *repeater's* MAC:

```bash
# on Asgard
ip neigh | grep 192.168.0.182     # → lladdr 30:c5:99:98:76:54   ← the repeater
# on Eclipse
ip link show eth0                 # → link/ether 88:a2:9e:d6:53:dd ← the actual Pi
```

Same MAC `30:c5:99:98:76:54` holds **two** addresses — `192.168.0.68` (its own management IP) and
`192.168.0.182` (Eclipse's, proxied). Find any such bridge with a ping sweep plus `ip neigh`;
a MAC holding two IPs is the fingerprint. Translation is one-directional: Eclipse still sees the
real MACs of Asgard and the gateway, which is why it looks normal from the Pi's side.

For reference, the five ESPHome smart plugs are the `8c:fd:49:*` block
(`.14`, `.49`, `.58`, `.150`, `.206`).

### Why "all the checks pass" is not evidence of a healthy link

Every local check comes back clean even when the backhaul is bad:

| Checked | Result | What it actually proves |
|---------|--------|-------------------------|
| Interface | `eth0` up, `wlan0` **down** | genuinely on the cable — and irrelevant |
| Link speed | negotiated **1000Mb/s full duplex** | only to the *extender*, not end to end |
| Errors | **zero** rx/tx/crc/frame/dropped | the wireless hop is transparent to the Pi's NIC |
| Throttling | `0x0`, 62.6°C, full clocks | not thermal |
| CPU during test | **75.6% idle** | ⬅ **kills the "Pi under load" theory outright** |

Always measure against `SPEEDTEST_LAN_PORT` (9557), which serves zeros **from memory** — no disk
in the path, so a slow result cannot be blamed on the array. Don't measure through Jellyfin and
then draw conclusions about the network.

**The latency comparison is the cheapest decisive test.** Same gateway, two sources, while the
backhaul was on 2.4 GHz:

| Path | min / avg / max | Loss |
|---|---|---|
| Asgard → gateway | 0.43 / **0.59** / 0.89 ms | 0% |
| Eclipse → gateway | 2.3 / **30.2** / 146 ms | **2%** |
| Asgard → Eclipse | 2.5 / **51.0** / **471 ms** | 0% |

Asgard's leg is textbook wired gigabit. Eclipse's leg to the *same* gateway was 50× worse and
dropping packets. ARP confirms one L2 segment, no router hop — so the only variable is the run
to the Pi. It needs nothing installed and rules the host in or out in one command.

**How to tell this apart from a genuinely slow host**, since the symptoms overlap:

- Measure with Kodi **idle**. If the ceiling holds while the CPU is 75% idle, it is not the Pi.
- Test **both directions**. A host-side limit is usually asymmetric; a shared medium is not.
- Test **parallel streams**. A single-flow TCP limit scales out; a medium ceiling does not.
- Compare **ping to the gateway from two different hosts**. This is the cheapest and most
  decisive test, and it needs nothing installed.

> The old table's last row — "same sink from Sisyphus: 872 Mbps" — was already pointing at the
> Eclipse leg. It got misread as "the Pi is slow" instead of "Sisyphus has a real cable and
> Eclipse does not." Same trap as [[eclipse-diagnosis-order]]: **confirm the physical run before
> accepting a host-side theory.** Ask what the far end of the cable plugs into.

**Practical impact.** A 4K remux direct-playing wants 60–100 Mbps:

- **On 5 GHz (196 Mbps):** fine — ~2.8× headroom even for the heaviest file in the library
  (*The Drama*, 51 GB, **68.9 Mbps**). No cap needed.
- **On 2.4 GHz (~45 Mbps):** impossible. This is what `JELLYFIN_BITRATE_LAN` in
  `eclipse-control.py` exists to cap (see *Switching between LAN and remote*).

So the cap is a **fallback for the degraded state, not the steady state**. If playback starts
stuttering, measure the link *first* — if it reads ~45 Mbps, power-cycle the repeater rather
than reaching for the cap.

⚠️ **A cap between ~45 and ~196 Mbps buys nothing.** Either it is above the degraded ceiling
(so it fails anyway when the backhaul drops) or below what the healthy link easily carries (so
it forces pointless 4K transcodes). The only two meaningful settings are **`23` (uncapped) for
the healthy 5 GHz state** and **`17` (20 Mbps) to ride out a regression** — don't split the
difference.

**Do not bring back an NFS export for Kodi's "Native mode" to fix this** (Asgard's NFS export was removed 2026-10-03). Direct paths bypass Jellyfin's
transcoder, so an oversized file then demands its full source bitrate — strictly worse on a
capped link, not better.

### 🐛 Every button on the panel was dead — `var history` shadowing

Fixed 2026-09-19. `logAdd()` did `history.unshift(...)` against a top-level `var history = []`.
**`window.history` is a read-only Window attribute, so a global `var history` never overrides
it** — `history` stayed the History object and `.unshift` threw `TypeError`. `run()` died at
`logAdd()` **before the fetch**, so clicking any button applied the busy class, disabled the
others, and then silently did nothing. Renamed to `logHistory`.

**Fingerprint:** button goes busy + others disable + Activity log never changes + no request in
flight ⇒ the handler threw between the DOM updates and the fetch. Never name a global `history`,
`location`, `name`, `status`, `top` or `self` in browser JS.

### Remote playback was capped to 12 Mbps and stuttering — fixed 2026-09-11

Switching Eclipse's address off a `192.168.x.x` LAN IP onto the Tailscale IP has a side effect
**server-side**: Jellyfin's `IsInLocalNetwork` check no longer matches
(`RemoteClientBitrateLimit: 12000000, RemoteIP: "100.80.62.3", IsInLocalNetwork: False` in
`log_YYYYMMDD.log`), so every stream now goes through Jellyfin's **remote client bitrate limit**
(Dashboard → Playback), which was still at its 12 Mbps default. A 19.5 Mbps HEVC remux blew straight
through that, forcing an HLS transcode (audio EAC3→AAC, video copy) instead of direct play. HLS's
segment-by-segment delivery is what produced the "builds a chunk, plays it, stalls, builds the next
chunk" pattern — direct play's progressive-HTTP + the filecache tuning above never sees that failure
mode.

**Fix applied:** raised `RemoteClientBitrateLimit` to 40,000,000 (40 Mbps) via
`POST /System/Configuration` — comfortably above real-world remux bitrates, while still under the
`wan-egress-shaping` 30 Mbit htb cap so the number isn't a promise the WAN link can't keep.
**This is imperative Jellyfin state, not declared in Nix** — nixflix has no option for it. A fresh
Jellyfin deploy needs this reapplied by hand (same category as the branding CSS in the Fresh Deploy
Checklist, `Claude/server-info.md`):

```bash
KEY=$(sops -d --extract '["jellyfin-api-key"]' Secrets/secrets.yaml)
curl -s -H "X-Emby-Token: $KEY" http://localhost:8096/System/Configuration \
  | jq '.RemoteClientBitrateLimit = 40000000' \
  | curl -s -X POST -H "X-Emby-Token: $KEY" -H "Content-Type: application/json" \
      --data @- http://localhost:8096/System/Configuration
```

**Considered and rejected:** marking Tailscale's CGNAT range (`100.64.0.0/10`) as a
`LocalNetworkSubnets` entry, which would have made `IsInLocalNetwork` true again and bypassed the
remote cap entirely (closer to how it behaved on the old LAN). Left as the *raise-the-cap* fix
instead — deliberate choice, not oversight — which keeps the cap meaningful for the actually-public
CF-tunnel clients (`jellyfin.bifrost-vault.com`) rather than exempting all of the tailnet.

### Still stuttered after the above — `wan-egress-shaping`'s burst was the real bug

Raising the bitrate limit got `PlayMethod` to `DirectStream`, but playback kept pausing. Root cause
was one level down: `wan-egress-shaping.service`'s 30 Mbit htb class had **no explicit burst**, so
tc auto-computed one from the rate — **~1600 bytes, one packet**. `tc -s class show dev enp3s0` had
190M cumulative overlimits and a token count sitting in permanent deficit. Kodi's aggressive
read-ahead (filecache `readfactor` 20x, see *Cache* above) bursts far past one packet on every read,
so the shaper itself was throttling every burst, not just capping the long-run average. Fixed by
giving class `1:20` an explicit `burst 300k cburst 300k` (~80ms at 30 Mbit) — see the comment in
`Modules/Server/network.nix` next to `wan-egress-shaping`. Confirmed live: overlimits went from thousands
per 15s to near-zero.

**This alone didn't fully fix it either.** Live Kodi telemetry (`Player.GetProperties` →
`cachepercentage`) showed the buffer climbing at almost exactly the playback consumption rate — no
safety margin — while `tailscale ping eclipse` from Asgard's side showed RTT jumping 96–314ms. Same
signature as the *old* house's 2.4 GHz congestion writeup above, on a **different** SSID
(`QB-Guest`, 2.4 GHz, -57 dBm) — strongly points at Eclipse's own WiFi at the new house (a guest
network) as the remaining bottleneck, not anything server-side. Not yet resolved from that end;
mitigated for now by capping the addon's `maxBitrate` to index `10` (~8 Mbps) so Jellyfin transcodes
down to something that reliably fits a jittery link instead of attempting a ~20 Mbps direct stream.
**This is imperative Eclipse-side state** (`addon_data/plugin.video.jellyfin/settings.xml`), raised
if Eclipse ever gets a better link (5 GHz / non-guest network / ethernet).

> ⚠️ **"Ethernet" arrived and did not deliver.** Eclipse is wired today and still only gets
> ~45 Mbps, because the run goes through a **WiFi extender bridge** — see *The ~45 Mbps ceiling*
> above. Do not read "it's on ethernet now" as "the link problem is solved"; measure it.
> Going uncapped needs a genuine cable run, not a port that reports gigabit.

**`plugin.video.jellyfin` is a sync backend, NOT an app.** It copies server metadata into Kodi's
own DB so content appears under Kodi's native Movies/TV Shows. There is no Jellyfin screen to
open. Playback streams from the server (`playFromStream=true`, `useDirectPaths=0`); watched state
and resume points sync back. `plugin.video.jellycon` (same repo) is the browsable-app alternative.

- Repo zip: `https://kodi.jellyfin.org/repository.jellyfin.kodi.zip` — **not** the
  `repo.jellyfin.org/files/...` path.
- The repo index **404s for normal user agents**; it only 302s to the mirror with a Kodi UA.
  Test with `curl -A "Kodi/21.0"` before concluding it's dead.
- Jellyfin is **not** in Kodi's official repo (that has Plex). Beware `service.jellyfin` in the
  LibreELEC repo — that's the *server*, not the client.
- Install the client **from the repo**, not the zip, so its four deps resolve
  (`script.module.requests`, `dateutil`, `addon.signals`, `websocket`).

### Addons dropped in over SSH land DISABLED

Extracting into `/storage/.kodi/addons/` registers an addon but leaves `enabled=0`, and a disabled
repo never appears under "Install from repository". Registered ≠ enabled.

```bash
ssh root@100.80.62.3 'systemctl stop kodi'
# scp /storage/.kodi/userdata/Database/Addons33.db down, then:
sqlite3 Addons33.db "update installed set enabled=1, disabledReason=0 where addonID in (…);"
# scp back, systemctl start kodi
```

### Library sync

Permissions only make libraries *available*; nothing syncs until they're on the addon's whitelist
(`addon_data/plugin.video.jellyfin/sync.json`). An empty whitelist shows as
`Full sync completed in: 0:00:00`.

Trigger a sync headlessly, **one library at a time** — concurrent calls raise
`Exception: Sync is already running`:

```bash
kodi-send --action="RunPlugin(plugin://plugin.video.jellyfin/?mode=synclib&id=f137a2dd21bbc1b99aa5c0f6bf02a805)"  # Movies
sleep 45
kodi-send --action="RunPlugin(plugin://plugin.video.jellyfin/?mode=synclib&id=a656b907eb3a73532e40e44b968d0225)"  # Shows
```

Verify against Kodi's DB, not the log: `select count(*) from movie/tvshow/episode` in
`MyVideos131.db`. Should match Jellyfin's `/Items/Counts`.

### Forcing a login without the UI

The addon's dialogs do nothing when it has no server configured. Session state is
`addon_data/plugin.video.jellyfin/data.json` — authenticate via the API and write it directly:

```bash
curl -X POST http://192.168.0.226:8096/Users/AuthenticateByName \
  -H 'Content-Type: application/json' \
  -H 'X-Emby-Authorization: MediaBrowser Client="Kodi", Device="Eclipse", DeviceId="<jellyfin_guid>", Version="2.1.0"' \
  -d '{"Username":"…","Pw":"…"}'
```

Use the existing `addon_data/plugin.video.jellyfin/jellyfin_guid` as DeviceId. Write `AccessToken`,
`UserId`, server `Id`/`address` into `data.json`, set `username`/`server` in `settings.xml`,
restart Kodi. Server Id: `5eaa975f36724125ab4f49a4a9da00a2`.

### Jellyfin user permissions

Empty library list in the addon = server-side permissions, not a Kodi fault. In Jellyfin's Access
tab the master *"Enable access to all libraries"* is unchecked for all non-admin users — that's
normal; access comes from the individual tick-boxes (`EnabledFolders`). Don't read the unchecked
master box as "access was removed".

```bash
KEY=$(sops -d --extract '["jellyfin-api-key"]' Secrets/secrets.yaml)
curl -H "X-Emby-Token: $KEY" http://192.168.0.226:8096/Users/<id> | grep -oE '"EnabledFolders":\[[^]]*\]'
```

Library IDs: Movies `f137a2dd21bbc1b99aa5c0f6bf02a805`, Shows `a656b907eb3a73532e40e44b968d0225`,
Music `7e64e319657a9516ec78490da03edccb`.

**Missing: Kodi Sync Queue** server plugin (`kodi.log` 404s on
`Jellyfin.Plugin.KodiSyncQueue/GetPluginSettings`). Without it, changes made while Eclipse is off
may be missed on reconnect; the `dbSyncScreensaver` catch-up covers it lazily. Install from
Jellyfin Dashboard → Plugins → Catalog.

### Dolby Vision Profile 5 plays GREEN — patched 2026-09-07

**Symptom:** the picture is a solid green wash. The same title on a phone looks perfect, which
makes it read like an Eclipse display/HDMI fault. It is neither — it is the file.

DV **Profile 5** encodes its base layer in Dolby's **IPT-C2** colour space and ships **no HDR10
fallback** (`DvBlSignalCompatibilityId: 0`). Kodi on the Pi 5 has no Dolby Vision support at all,
so a direct-played P5 file decodes fine as HEVC Main 10 and then gets interpreted as YCbCr — IPT
read as YUV is exactly the green wash.

The discriminator, straight from Jellyfin's `MediaStreams` (the addon dumps the whole blob into
`kodi.log` at `playutils.py:83`, so it is always available after a failed watch):

| `VideoRangeType` | DV profile | Base layer | On Eclipse |
|---|---|---|---|
| `DOVI` | 5 | IPT-C2, no fallback | **green** |
| `DOVIWithHDR10` | 8.1 | plain HDR10 | fine |
| `DOVIWithHDR10Plus` | 8.1 + HDR10+ | plain HDR10 | fine |
| `HDR10` / `HDR10Plus` / `HLG` / `SDR` | — | — | fine |

A P5 stream also carries **no** `ColorSpace` / `ColorTransfer` / `ColorPrimaries` fields at all,
unlike every other file — a quick way to spot one.

As of 2026-09-07 the library held **38** P5 items out of ~3150 (Ted Lasso, all of White Lotus S1,
Loki, Rings of Power, Shrinking, Our Flag Means Death, Andor, Fallout, Foundation, plus the films
*Tomorrowland*, *Finch*, *The Adam Project*).

**The phone is not "better" — the server tone-maps for it.** Don't read a working phone as
evidence the Pi is broken. The server log shows the whole story side by side:

```
15:48:36  Kodi         — Tomorrowland stopped at 131s          ← the green watch
15:49:07  Jellyfin Web — TranscodeManager: ffmpeg ...
          tonemap_opencl=...:p=bt709:t=bt709:m=bt709:tonemap=bt2390
15:49:21  Jellyfin Web — stopped at 7s                         ← the phone check
```

**Fix: refuse direct play for `VideoRangeType == DOVI`** so Asgard tone-maps it instead. Added to
`get_device_profile()` in
`/storage/.kodi/addons/plugin.video.jellyfin/jellyfin_kodi/helper/playutils.py`, immediately before
the `if self.info["ForceTranscode"]:` block:

```python
profile["CodecProfiles"].append(
    {
        "Type": "Video",
        "Codec": "hevc",
        "Conditions": [
            {
                "Condition": "NotEquals",
                "Property": "VideoRangeType",
                "Value": "DOVI",
                "IsRequired": True,
            }
        ],
    }
)
```

Only P5 is affected — HDR10, HDR10+ and DV 8.1 keep direct-playing at full quality, so the
transcode load is limited to those 38 items.

**This is an addon file. A Jellyfin-addon update will clobber it** — same class of hazard as the
Moonlight `start.sh` hook. Original saved alongside as `playutils.py.orig`; the patch script is
idempotent (it bails if `VideoRangeType` is already present) and lives at `/storage/patch_dv.py`.
The anchor string `if self.info["ForceTranscode"]:` appears **twice** in the file — the one inside
`get_device_profile` is the second; patch by searching forward from `def get_device_profile`.

**Verifying it took effect** — play a P5 title and check the transcode URL the addon builds:

```bash
grep -a "master.m3u8" /storage/.kodi/temp/kodi.log | tail -1
#   &TranscodeReasons=VideoRangeTypeNotSupported        ← the server was told
#   &hevc-rangetype=Unknown,SDR,HDR10,HLG,DOVIWithHDR10,...   ← note: no bare DOVI
```

Server side, confirm the filter chain actually tone-maps (`pgrep -af "ffmpeg.*<Title>"` on Asgard):
`tonemap_opencl=format=nv12:p=bt709:t=bt709:m=bt709:tonemap=bt2390` → **`hevc_qsv`**.

> **The output codec is load-bearing.** It must be `hevc_qsv`, never `h264_qsv` — see
> *[Video decode: HEVC only](#video-decode-this-box-has-no-h264-hardware-decoder)*. The addon's
> stock `videoPreferredCodec` is `H264/AVC`, which is the single worst target for this box; it
> has been changed to `H265/HEVC` here. An earlier version of this section claimed a smooth
> `h264_qsv` transcode — that was wrong, and the drifting audio it caused is documented below.

Two things that look like failures during the first play of a P5 title and are not:

- **`CCurlFile::Open ... Failed with code 404` on `master.m3u8`.** Kodi probes the HLS playlist
  before the server has finished spawning ffmpeg. It retries and playback starts. A 404 here is
  only real if playback never begins.
- **A long stall before the picture appears, once per file.** Switching to transcode makes the
  addon pull every embedded text subtitle as an external (`enableExternalSubs=true`), and Jellyfin
  extracts them serially from the source. *Tomorrowland* has **28** subtitle tracks and took ~3
  minutes on the first play. Jellyfin caches them under
  `/data/.state/services/jellyfin/data/subtitles/`, so subsequent plays start immediately —
  confirmed by a second play that was up in under 6 s.

**Also fixed at acquisition (2026-09-08).** Radarr now scores TRaSH's **`DV (w/o HDR fallback)`**
(`923b6abef9b17f937fab56cfcf89e1f1`) at **-10000** in `Asgard - Movies`, so it can never grab a
P5 movie again. Details and the verification in `Claude/server-info.md`. This does nothing for the
38 files already on disk — the addon patch above is what covers those.

> An earlier version of this section said acquisition was "deliberately not fixed" and quoted
> trash_id `58d6a88f13e2db7f5059c41047876f00`. **Both are wrong** — it is now fixed, and that
> trash_id is stale (TRaSH restructured the DV formats). Never reuse a remembered DV trash_id;
> fetch it from `docs/json/radarr/cf/dv-wo-hdr-fallback.json` in the Guides repo.

**Per-title escape hatch, no config needed:** the addon's context menu already offers **Transcode**
(`enableContext` and `enableContextTranscode` both default `true` and are not overridden here). That
sets `ForceTranscode`, which empties `DirectPlayProfiles` entirely. Useful for any other
direct-play-related fault on the remote.

## Video decode: this box has NO H.264 hardware decoder

**The Pi 5 has exactly one video decode block, and it is HEVC-only.** The Pi 4's H.264 decoder is
gone — it was not carried over to the Pi 5. Anything H.264 is decoded on the **CPU**.

```bash
ls /dev/video*                              # → /dev/video19, and nothing else
dmesg | grep -i codec
#  rpi-hevc-dec 1000800000.codec: Device registered as /dev/video19
```

Kodi tries hardware first and silently falls back. **All three lines are logged at `info`, so the
failure does not look like an error:**

```
CDVDVideoCodecDRMPRIME::Open - using decoder V4L2 mem2mem H.264 decoder wrapper
CDVDVideoCodecDRMPRIME::Open - unable to open codec                       ← hardware refused
CDVDVideoCodecDRMPRIME::Open - using decoder H.264 / AVC / MPEG-4 AVC …   ← now on the CPU
```

A healthy HEVC open is a single line with no fallback:
`CDVDVideoCodecDRMPRIME::Open - using decoder HEVC (High Efficiency Video Coding)`.

**Symptom of getting this wrong: audio drifts away from video**, and nudging Kodi's audio offset
gets *close* but never fixes it — because it is drift, not a constant offset. The renderer is
starving, so video falls progressively further behind:

```
OutputPicture - timeout waiting for buffer     # ~6 per minute on 4K H.264
```

Measured contrast on the same box: 4K HEVC **direct play** ran 82 minutes with **3** such warnings
total; 4K H.264 **transcode** produced ~6 **per minute**.

**So: never let the server transcode to H.264 for this box.** The Jellyfin addon's stock
`videoPreferredCodec` is `H264/AVC` — the worst possible choice here. Set to `H265/HEVC`:

```bash
systemctl stop kodi     # the addon caches settings in memory and rewrites the file on exit
#   userdata/addon_data/plugin.video.jellyfin/settings.xml
#   <setting id="videoPreferredCodec">H265/HEVC</setting>
systemctl start kodi
```

`get_transcoding_video_codec()` in `playutils.py` puts `hevc` **first** in the codec list when this
is set, so Jellyfin picks `hevc_qsv`. Backup of the pre-change file: `settings.xml.bak-h264`.

1080p H.264 in software is fine on a Pi 5 — it is specifically **4K** H.264 that cannot keep up.

> **This is also why game streaming must use HEVC.** Sunshine used to force H.264, so Moonlight
> software-decoded every frame at **54.5% CPU**; on HEVC the Pi hardware-decodes at **20%** while
> carrying *more* bitrate. See `Claude/streaming.md` → *HEVC is the correct codec here*.

## ⚠️ Two independent audio paths — Kodi uses ALSA, Moonlight uses PulseAudio

This box runs **both**, and only one of them is reliably configured. It explains the otherwise
baffling "Jellyfin has sound but the game stream is silent".

| Consumer | Path | State |
|---|---|---|
| **Kodi** | **ALSA direct** — `hdmi:CARD=vc4hdmi0,DEV=0` | ✅ works, never touches PulseAudio |
| **Moonlight** | **PulseAudio** (`SDL audio driver: pulseaudio`) | ❌ falls back to `auto_null` |

PulseAudio never claims the vc4hdmi card, so its only sink is the null one and audio is discarded:

```bash
pactl list short sinks     # 0  auto_null  module-null-sink.c   ← the bug
aplay -l                   # card 0: vc4hdmi0 ... card 1: vc4hdmi1   ← the real outputs, unclaimed
```

Live fix (`pactl load-module module-alsa-sink device=hdmi:CARD=vc4hdmi0,DEV=0 sink_name=hdmi_out`)
works but is **in-memory only**. The durable fix is to make Moonlight skip PulseAudio entirely with
`SDL_AUDIODRIVER=alsa` — the same path Kodi already proves works. Full detail in
`Claude/streaming.md` → *No stream audio*.

**Don't debug this as a network or Sunshine problem.** The client log will happily report
`Received first audio packet after N ms` while playing it into the void.

## The Kodi GUI renders at 1080p on a 4K panel — that is CORRECT

`kodi.log` reports `GUI format 1920x1080, Display 3840x2160 @ 60.000000 Hz`. The interface is
rendered at 1080p and upscaled by the TV. This is Kodi's own shipped default —
`videoscreen.limitguisize = 3` ("1080"), with `default: 3` — **not** something misconfigured here.
A 4K GUI is expensive on a Pi, hence the cap. **Video playback is unaffected**: it bypasses the
GUI layer entirely and plays at source resolution on its own DRM plane.

Raise it with `videoscreen.limitguisize = 4` ("Unlimited / 1080 >30Hz") for a native-4K UI, but
expect sluggish scrolling and skin animations on a Pi 5. Revert to `3` if so.

> ⚠️ **A GUI at `1280x720` is a different thing and IS a fault.** It means Kodi started while
> something else still held DRM (typically Moonlight) and misdetected the display. 720p upscaled
> to 4K looks obviously soft. Fix: make sure nothing else holds `card1`, then restart Kodi — see
> the DRM-owner check in `Claude/streaming.md`. Confirm with:
> `grep -a "GUI format" /storage/.kodi/temp/kodi.log | tail -1`

## Moonlight's own UI text is too small on the TV — enlarge via fake DPI

Done 2026-10-01. The addon's launcher picks `QT_SCALE_FACTOR` from the detected
resolution (`0.6` @720p, `0.64` @1080p, `1.17` @1440p, **`1.28` @2160p**) and
upstream warns in the script itself: *"QT_SCALE_FACTOR higher than 1.28 corrupts the
layout."* **So raising the scale factor is not the lever.**

The lever is the *physical* screen size, which upstream sets right after and
documents as the TV knob: *"This setting makes the fonts conveniently large on a TV,
the lower the size the bigger the fonts."* Qt derives DPI from pixels ÷ mm, so
shrinking it enlarges fonts without touching layout scale:

```sh
QT_QPA_EGLFS_PHYSICAL_WIDTH  = QT_SCALE_FACTOR * 437 / FONT_BOOST
QT_QPA_EGLFS_PHYSICAL_HEIGHT = QT_SCALE_FACTOR * 250 / FONT_BOOST
# FONT_BOOST=1.5 @4K: 559x320mm -> 372x213mm,  ~174 DPI -> ~262 DPI
```

Stream resolution is unaffected — this only changes reported DPI. One number to
retune; back off if text starts clipping.

**Where it lives.** `launch_moonlight-qt.sh` prefers
`$ADDON_PROFILE_PATH/bootstrap_moonlight-qt.local.sh` over the addon's own
bootstrap, so the override sits in `addon_data` and survives addon updates. It is a
**fork** of the upstream script (the hook replaces, it does not source), so pristine
copy kept as `bootstrap_moonlight-qt.upstream.bak` — re-sync after an addon update;
only `FONT_BOOST` and the two `QT_QPA_EGLFS_PHYSICAL_*` lines differ.

### 🔑 Two `$0` traps when forking that bootstrap — both break it badly

A naive copy fails, and the second failure is nasty because Moonlight *appears* to
start:

1. **`launch_moonlight-qt.sh` invokes the local script by ABSOLUTE path**, so
   upstream's `cd "$(dirname "$0")"` lands in `addon_data` instead of the addon bin
   dir. Symptom: `can't open './get-platform.sh'`, Moonlight never starts at all.
2. **`get-platform.sh` is SOURCED and itself does `cd "$(dirname "$0")"`** — and in a
   sourced script `$0` is the *caller*. So it silently moves cwd **after** step 1's
   fix, and the later `ADDON_BIN_PATH=$(realpath ".")` resolves wrong. Upstream never
   trips this because the launcher passes its bootstrap by *relative* name, making
   `dirname` a harmless `.`.

Trap 2's consequence is the dangerous one: `$ADDON_BIN_PATH/kodi_hooks/libreelec`
is then not found, so **`systemctl stop kodi` never runs**, Kodi keeps DRM master,
and Moonlight spams `Could not queue DRM page flip on screen HDMI1 (Permission
denied)` onto a dead screen.

**Fingerprint — two processes holding `card1`:**

```bash
for p in $(ls /proc | grep -E '^[0-9]+$'); do for fd in /proc/$p/fd/*; do
  case "$(readlink $fd 2>/dev/null)" in */dri/card1) echo "$p $(cat /proc/$p/comm)";; esac
done; done | sort -u
# healthy = exactly ONE holder (kodi.bin, or moonlight-qt while streaming)
```

**Fix: make the fork independent of `$0`** — an absolute `cd` at the top, and set
`ADDON_BIN_PATH` to a literal path instead of `realpath "."` (then `cd` back to it,
since `get-platform.sh` will have moved cwd).

**Also check `Using Kodi hooks for libreelec...` is present** in
`$ADDON_PROFILE_PATH/moonlight-qt.log`. Its *absence* is the whole tell — and the
log is written by `tee` from the launcher, so it exists even when nothing appears
on screen.

Safe way to test without taking the TV: truncate a copy of the script just before
the `Check for distro specific hooks` block and run that — it exercises all the path
and env logic but stops short of stopping Kodi or launching Moonlight.

## Closing the Wolf session when Moonlight exits (2026-10-01, verified)

**The problem.** Wolf keeps a lobby *and the running game* alive long after the client
disconnects — measured **2 h 08 m** between `Moonlight stream over, leaving lobby` and
`stopping lobby / Stopped container`. Backing out of a stream therefore left the game
burning GPU on Sisyphus and holding the shared `steamapps`.

**The fix**, in `bootstrap_moonlight-qt.local.sh`:

```sh
_moonlight_quit_wolf() {
  H=$(sed -n 's/^1\\localaddress=//p' "$HOME/.config/.../Moonlight.conf" | head -1)
  QT_QPA_PLATFORM=offscreen "$MOONLIGHT_PATH/bin/moonlight-qt" quit "$H"
}
trap '_moonlight_quit_wolf; _moonlight_restart_kodi' EXIT
```

**Measured result: lobby torn down in 2 seconds** (hook at `12:28:39` →
`Stopped container: /Wolf-UI_… 12:28:41`), Kodi back at the correct
`GUI format 1920x1080, Display 3840x2160`, one process holding `card1`.

### 🔑 Four things that make this non-obvious

1. **Code placed after `./moonlight-qt "$@"` is NEVER reached.** Proven with a marker
   writing *directly to a file* (bypassing the `tee` pipeline): it never appeared,
   while the EXIT trap demonstrably ran. The transient `systemd-run` service tears
   its cgroup down when the stream process dies. **The EXIT trap is the only
   dependable hook** — the first attempt put the teardown after the launch line and
   it silently never executed.
2. **`quit` only works once the stream has ENDED.** Firing
   `moonlight-qt quit <host>` while your own client is mid-stream exits 0 and does
   **nothing** — Wolf logs not a line. Two test cycles were wasted on this.
3. **`QT_QPA_PLATFORM=offscreen` does NOT stop it touching the display.** The quit
   invocation still logs `Sharing DRM FD with SDL`, `GPU driver: vc4`,
   `Enabled 36-bit HDMI Deep Color` — Qt's platform plugin is offscreen but SDL still
   initialises DRM. What keeps it safe is the trap *ordering*: quit runs before
   `_moonlight_restart_kodi`, so it never overlaps Kodi grabbing DRM back.
4. **moonlight-qt ignores SIGTERM while streaming** — it needs `SIGKILL`. Any test
   harness that assumes TERM ends a stream will conclude the hook is broken when it
   is merely never invoked.

⚠️ **Trade-off:** this gives up Wolf's resume-later behaviour — disconnecting now kills
the running game instead of leaving it to rejoin. Delete the trap block to restore it.

Each session appends one timestamp line to `/storage/moonlight-hook-debug.log`
(moonlight-qt's own ~20 lines of SDL/Qt noise go to `/dev/null`). Also expect a burst
of `Could not queue DRM page flip … (Permission denied)` at *stream start* — that is
the Kodi→Moonlight DRM handover and is transient; a *continuous* stream of them is the
real two-holders fault described above.

## HDR output does not work — HDR content looks desaturated and grainy

**Symptom:** washed-out colour *and* visible grain, especially in dark scenes. It reads like a bad
encode or an AI upscale; it is neither. Both symptoms come from one cause.

The TV is capable — EDID reports HDR10 support:

```
[display-info] supports hdr static metadata type1: true
[display-info]   pq:              true
[display-info]   bt2020_cycc:     true
```

And Kodi sets the colorimetry, at 12-bit 4:2:2:

```bash
cat /sys/kernel/debug/dri/*/state | sed -n '/^connector/,/^plane/p'
#  connector[33]: HDMI-A-1
#      colorspace=BT2020_YCC        ← BT.2020 IS signalled
#      output_bpc=12
#      output_format=YUV 4:2:2
```

**But the PQ EOTF infoframe is never sent.** The DRM property exists and is simply never populated:

```bash
modetest -M vc4 -c | grep -A3 HDR_OUTPUT_METADATA
#  7 HDR_OUTPUT_METADATA:
#      flags: blob
#      blobs:            ← empty
```

Nothing HDR-related appears in `kodi.log` at playback start either. So the TV is told "this is
BT.2020" but never "this is HDR", and applies **SDR gamma to PQ-encoded video**. PQ packs enormous
detail into the shadows, so SDR gamma stretches the dark end wide open — which desaturates colour
**and** amplifies sensor noise into visible grain. One fault, both symptoms.

**Kodi cannot tone-map its way out of this on the Pi.** `videoplayer.useprimerenderer` is `0`
(*Direct To Plane*), where video goes straight to a DRM plane and bypasses Kodi's shaders entirely.
Switching it to `1` (*EGL*) does **not** help: no `videoplayer.tonemapmethod` setting appears
either way — this build has no tone-mapping at all. Don't spend time on it; revert to `0`, since
EGL is slower for no gain.

That leaves two real options:

| Approach | Cost |
|---|---|
| **Prefer SDR sources** for anything watched here | 4K SDR exists but is uncommon; most 4K is HDR |
| **Let Jellyfin tone-map** (force a transcode, as the DV P5 patch does) | a live 4K transcode per stream; must target `hevc_qsv` |

Do **not** "fix" this by penalising HDR in Radarr. Eclipse is one client; Ben's Chrome, the LG TV,
the Android TV and the phones all handle HDR, and Jellyfin tone-maps for those that cannot.
Degrading acquisition library-wide to suit the weakest client is the wrong layer — the fix belongs
in the Kodi device profile, exactly like the P5 patch.

> ⚠️ **UNVERIFIED and potentially large.** If HDR output is genuinely never signalled, then *every*
> HDR item plays washed-out here — ~450 files as of 2026-09-08 (300 DV 8.1, 93 HDR10, 61 HDR10+),
> not just the P5 ones. This was found late on 2026-09-08 and has **not** been confirmed against a
> known-good HDR10 title. Confirm before acting on it.

## Network — wired since 2026-08-23; wifi is now an automatic standby

**Ethernet is connected and owns the default route.** Everything below about the 2.4 GHz link is
still accurate for *whenever the cable is out* — that path is unchanged, it is just no longer the
normal one. Address the box by its tailnet IP `100.80.62.3`, which is interface-independent.

### Ethernet → wifi failover

ConnMan does this natively and needed no new config. `/etc/connman/main.conf` already ships
`PreferredTechnologies = ethernet,wifi,cellular` and does **not** set `SingleConnectedTechnology`
(defaults false), so both technologies stay connected simultaneously and ethernet simply wins the
route. The `Kandy Cane` profile in `/storage/.cache/connman/` was intact all along
(`Favorite=true`, `AutoConnect=true`, passphrase, `IPv4.method=dhcp`).

**The only blocker was that the wifi radio had been switched off**, persisted in
`/storage/.cache/connman/settings` as `[WiFi] Enable=false`, and visible as `phy0` soft-blocked in
`rfkill list`. With the technology unpowered there is no wifi *service* in `connmanctl services` at
all — so there is nothing for ConnMan to fail over *to*, and no amount of profile-checking shows the
problem. **Check `connmanctl technologies` for `Powered` before anything else.**

```bash
connmanctl enable wifi     # writes Enable=true under /storage → survives reboots and OS updates
connmanctl technologies    # wifi → Powered = True
connmanctl services        # "*AO Wired" + "*AR Kandy Cane"
```

Read the flag column: `*` favourite, `A` autoconnect, then `O` online / `R` ready / blank idle. Wifi
sitting at **`*AR` while the cable is in is the correct steady state** — it is associated and
holding a DHCP lease, so failover is instant with no re-association or DHCP delay. It only becomes
`*AO` when ethernet goes away.

**Verified end-to-end 2026-08-23** by downing `eth0` from a self-restoring `systemd-run` script:
default route moved to `wlan0` within 25 s, `Kandy Cane` went `*AR` → `*AO`, gateway and Asgard both
pinged at 0% loss; bringing `eth0` back moved the route straight back and demoted wifi to `*AR`.

Two things that look wrong and are not:
- `ip route` prints wlan0's standby default as `metric -3073`. That is busybox rendering a large
  *unsigned* metric as signed — it is the worst-priority route, not a negative one. eth0's metric 0 wins.
- Power-save survives the radio toggle: `iw dev wlan0 get power_save` still reports `off` after
  `connmanctl enable wifi`, so `wlan0-powersave.service` does not need re-running.

### The 2.4 GHz path (what you fall back to)

Historically `eth0` had never carried a byte and everything went over `wlan0`, associated to
`Kandy Cane` on **2457 MHz (ch 10)** at ~-60 dBm, 57.7 Mbit/s PHY.

"It's on the local network, so there shouldn't be any buffering" is the trap here — *Asgard* is on
the LAN at gigabit, but Eclipse reaches it through a congested 2.4 GHz link. Measured 2026-08-05
against the same file, same server, same minute, at deep uncached offsets:

| Client | Throughput |
|---|---|
| Sisyphus (wired) | **99 MB/s — 792 Mbps** |
| Eclipse (wifi) | **1.1 MB/s — 9 Mbps** (≈2.4 MB/s aggregate incl. Kodi's own stream) |

A 1080p WEB-DL remux runs ~10 Mbps, so the margin is roughly 2x on a link whose rate adaptation
swings. That is what "played one second, stopped, no cache" is — not a server or disk fault.
**Always measure before theorising**: the wired baseline exonerates Asgard in one command.

```bash
# live rate during playback
a=$(grep -E "^ *wlan0" /proc/net/dev | awk '{print $2}'); sleep 20
b=$(grep -E "^ *wlan0" /proc/net/dev | awk '{print $2}'); echo $(( (b-a)*8/20/1000000 )) Mbps
iw dev wlan0 link                 # freq / signal / bitrate
```

Kodi's own view of the buffer, over JSON-RPC — `cachepercentage` stuck in single digits and creeping
by ~0.1%/4s means the link is delivering barely more than realtime:

```
Player.GetProperties {"playerid":1,"properties":["cachepercentage","percentage","speed"]}
```

### It is jitter, not packet loss — don't go looking for a bad internet connection

Measured 2026-08-05, 100 pings to the **same** gateway (`192.168.0.1`):

| Source | Loss | min/avg/max |
|---|---|---|
| Sisyphus (wired) | 0% | 0.35 / **0.48** / 0.78 ms |
| Eclipse (wifi) | 0% | 1.4 / **20.2** / **140 ms** |

Eclipse loses **no packets at all** — 802.11 retransmits at layer 2, so a contended link never shows
up as loss, only as latency spikes and collapsed throughput. Looking for packet loss here finds
nothing and proves nothing. The house WAN is healthy and is not involved: 0% loss to 1.1.1.1 and
8.8.8.8 at ~10.6 ms, 376 Mbps down from Cloudflare. **Jellyfin playback never leaves the LAN
anyway** — Asgard is at `192.168.0.226`.

**The layer-2 counters agree with this** — they are the same phenomenon seen one layer down, not a
contradiction. `iw dev wlan0 station dump` shows `tx failed` climbing steadily even at idle
(thousands of failed/retried frames, +1 every few seconds), signal a mediocre `-58 dBm`, and the
negotiated PHY rate bouncing 52-72 Mbit/s rather than holding steady. That is chronic low-grade RF
loss being hidden from IP by 802.11 retransmission — exactly why ping shows 0% loss but 140 ms
spikes. The link never actually drops: there are no reconnect/reset events in `dmesg` or the journal.

### Wi-Fi power-save was on, and it was starving the read-ahead cache (fixed 2026-08-09)

`dmesg` showed `brcmfmac: brcmf_cfg80211_set_power_mgmt: power save enabled` — the onboard BCM4345/6
SDIO chip was sleeping between beacon intervals, which starves Kodi's read-ahead cache under
sustained high-bitrate playback. Disable live with:

```bash
iw dev wlan0 set power_save off
```

**Persisted** via `/storage/.config/system.d/wlan0-powersave.service` — a oneshot unit
(`RemainAfterExit=yes`, `ExecStart=/usr/sbin/iw dev wlan0 set power_save off`) modelled on the same
custom-unit mechanism as `tailscaled.service`, symlinked into
`/storage/.config/system.d/multi-user.target.wants/`. Verified with `systemctl is-enabled` /
`is-active` after a reload.

**Result:** the recurring `CVideoPlayerAudio::Process - stream stalled` lines — previously every
~6-8 min during high-bitrate playback — stopped after enabling it.

If stalls ever return on the heaviest files, the router's 2.4 GHz channel (currently 10) overlaps 6
and 11 and could be moved, though that is a router-side change outside this repo. **Ethernet was the
definitive fix and it is now in place (2026-08-23)** — these stalls should only be reachable while
running on the wifi standby.

### Forcing 5 GHz *is* possible — the SSIDs must stay merged

The same AP broadcasts `Kandy Cane` on 5 GHz (ch 36 / 5180 MHz, BSSID `…d9:9b:2e` vs 2.4 GHz
`…d9:9b:2f`) at -68 dBm. **The bands must not be split into separate SSIDs** — the TV's connection
randomly drops when they are. That is a hard constraint, not a preference.

A merged SSID does **not** stop the *client* choosing a band, though. LibreELEC does not use
wpa_supplicant at all (there is no such binary on the image) — ConnMan drives **`iwd` 3.10** via its
iwd plugin, and iwd ranks BSSes within a network using `[Rank] BandModifier5GHz` /
`BandModifier2_4GHz`. Raising the 5 GHz modifier biases association toward the 5 GHz BSS with no
router change at all.

`/etc` is read-only squashfs and `/etc/iwd/` does not exist, but iwd honours the
**`CONFIGURATION_DIRECTORY`** env var, so a drop-in under `/storage/.config/system.d/` can point it
at a writable config — the same supported mechanism Tailscale uses here, and it survives OS updates.

Leave `BandModifier2_4GHz` alone: iwd refuses to start if no band is allowed
(`No bands are allowed, check BandModifier* settings!`), and keeping 2.4 GHz ranked lower but
available means it can still fall back if the weaker 5 GHz signal degrades.

**Not yet applied, and now largely moot** — ethernet arrived 2026-08-23 and is the primary link, so
band selection only affects the fallback path. 5 GHz is 8 dB down here and the Pi is far from the
router, so it would still need measuring rather than assuming.

### Cache — the real fix, and `advancedsettings.xml` is NOT how you set it

**Kodi 21 replaced the `advancedsettings.xml` `<cache>` block with GUI settings.** Writing that file
is silently useless; the log even says so:

```
New Cache GUI Settings (replacement of cache in advancedsettings.xml) are:
   Buffer Mode: 1 / Memory Size: 512 MB / Read Factor: 20.00 x
```

Watch that block after a restart to confirm what actually took effect — the file's contents are
echoed into the log just above it, which makes it look applied when it isn't.

Set them over JSON-RPC instead (applies live, no restart, validates against the option list):

| Setting | Default here | Now |
|---|---|---|
| `filecache.buffermode` | **4** — network filesystems: SMB, NFS | **1** — all filesystems |
| `filecache.memorysize` | 20 (MB) | **512** |
| `filecache.readfactor` | 400 (4x) | **2000** (20x) |

**`buffermode` 4 was the actual bug.** It buffers SMB/NFS but *not* `http://`, and the Jellyfin addon
streams over http — so playback was running essentially unbuffered, which is why it died one second
in rather than merely stuttering. Fixing this mattered far more than the link speed did.

All three are enums — `Settings.GetSettings {"level":"expert"}` returns the valid `options` list;
`memorysize` accepts only 16/20/24/32/48/64/96/128/192/256/384/512/768/1024, `readfactor` only
0 (Adaptive)/110/125/…/5000. Values persist in `guisettings.xml` across restarts.

Startup is still the weak point — Kodi begins playing before the cache has banked anything, which is
why pausing for ~30s after pressing play works. There is no prebuffer-size setting in Kodi 21.

Demand-side lever if it regresses: the Jellyfin addon's `maxBitrate`, currently **`23` = uncapped**
(correct — the 5 GHz path carries 196 Mbps). Capping makes Asgard transcode down instead of
direct-playing a remux the link cannot carry; **`17` = 20 Mbps is the value to use if the
repeater falls back to 2.4 GHz.** Values are indexes into the addon's own list — the full
mapping, straight from `resources/language/*/strings.po` (ids `#33214`+):

| idx | Mbps | idx | Mbps | idx | Mbps | idx | Mbps |
|----|------|----|------|----|------|----|------|
| 0 | 0.5 | 7 | 5 | 13 | 12 | 19 | 30 |
| 1 | 1.0 | 8 | 6 | 14 | 14 | 20 | 35 |
| 2 | 1.5 | 9 | 7 | 15 | 16 | 21 | 40 |
| 3 | 2.0 | 10 | 8 | 16 | 18 | 22 | 100 |
| 4 | 2.5 | 11 | 9 | **17** | **20** | 23 | 1000 *(default)* |
| 5 | 3.0 | 12 | 10 | 18 | 25 | 24 | Maximum |
| 6 | 4.0 | | | | | | |

Editing this by hand needs `systemctl stop kodi` first — the addon caches its settings in memory
and **rewrites `settings.xml` on exit**, so a live edit is silently clobbered. Drop the
`default="true"` attribute when writing a non-default value.

## Skin — Bingie (current, since 2026-09-12)

> ⚠️ **Do not hand-edit the skin on the box.** Two files are owned by
> `Resources/Eclipse-Skin/` in the repo and pushed with `eclipse-skin-push.sh`:
> `1080i/IncludesBingie.xml` and `1080i/View_526_BingieMainPoster.xml`. A skin update
> replaces the whole `skin.bingie` tree and reverts them — **re-run the script after
> any update.** It refuses to push if the installed version is not 2.0.2, validates
> the XML first (an XML comment may not contain `--`, which bit once), and backs up
> what it replaces. The 15 superseded `.bak-*` files that used to sit *inside* the
> live `1080i/` directory are now in `Resources/Eclipse-Skin/bingie-history/` and
> `/storage/skin-baks-archive/` — Kodi globs `1080i/*.xml`, so one careless rename in
> there loads a stale window definition and breaks the skin untraceably.

Replaced Arctic Zephyr Mod. Titan Bingie Mod (`skin.bingie`), a Netflix-style skin. Installed via
`kodi-send --action="InstallAddon(skin.bingie)"` + blind Left+Select confirm dance (matches the
"Addons.InstallAddon JSON-RPC doesn't exist" pattern below). Automatic dependency resolution
cascaded version-mismatch failures (`resource.images.studios.coloured`,
`plugin.program.autocompletion`, …) — fixed by downloading each dependency's zip directly from the
repo's `addons.xml`-listed URL and installing manually, one at a time, same "extract zip, enable via
sqlite `installed.enabled`" method documented for KodiSeerr below.

**Sidebar is Home / Movies / TV / Games / Requests only** — `shortcuts/mainmenu.DATA.xml`, same
skinshortcuts mechanism as Zephyr (see historical section below for the general mechanics: rebuild
after edits with `systemctl stop kodi; rm .../1080i/script-skinshortcuts-includes.xml;
rm .../addon_data/script.skinshortcuts/skin.bingie.hash; systemctl start kodi` twice). Movies/TV go
straight to `ActivateWindow(Videos,library://video/movies|tvshows/titles.xml,return)` — no Netflix-
style category rows, direct to a scrollable poster grid (user preference: "just want all my stuff
going down the page, I don't need categories"). No Trending/Categories/Music items.

**Movies/TV grid forced to `View_526_BingieMainPoster.xml`** ("Bingie Poster", set via
`skin.forcedview.movies` / `.tvshows` in `addon_data/skin.bingie/settings.xml`, same forced-views
mechanism as Zephyr). Default tile size (240×340) only fit ~1.4 rows in the 474px grid area below the
hero. Fixed by adding a **local, file-scoped copy** of the tile layout —
`PosterPanelBingieLayoutCompact` / `PosterThumbBingieLayoutCompact` /
`PosterPanelBingieLayoutFocusCompact`, defined inside `View_526_BingieMainPoster.xml` itself rather
than editing the shared `PosterPanelBingieLayout` in `IncludesViewsLayoutPoster.xml` (which every
*other* poster view — home widgets, seasons, etc. — also uses at full size). The compact version
drops `Poster_New_Episodes_Tag_Overlay` entirely (a fixed 150px-wide ribbon sized for a 240px tile —
would overflow onto the neighbouring poster at a smaller size) and scales `WatchedIndicatorLayoutBingie`
down proportionally (44×44 inset 4px, vs default 80×80 inset 8px — that one *is* already
parametrized by the skin, safe to just pass smaller numbers). Current tile: 132×187 content /
131×186 cell, itemgap 0, giving ~2.5 rows in the same 474px space. **Tried pushing further** (moving
the grid's `top` from 600→500 to steal 100px from the hero, tiles up to 145×206) — collided visibly
with the hero's tagline row ("Titles" header overlapping "Come undone."); reverted. Safe headroom
above the existing tile size is only ~7% (40px), nowhere near the 20% that would need — not attempted
since 7% wasn't judged worth the added complexity.

**TV show unwatched-episode-count badge removed** — `Skin.HasSetting(WatchedIndicator.Episodes)`
gates the "Episodes count Overlay" block in `WatchedIndicatorLayoutBingie` (`IncludesViews.xml`), a
normal toggleable skin setting, not a code change: `kodi-send --action="Skin.Reset(WatchedIndicator.Episodes)"`.

**Home is minimal** (user: "basically just an entry screen, almost nothing" — then corrected to
"not nothing at all, I still want a poster/colour" after a too-aggressive first pass). New skin
setting `HomeMinimal`, gating six elements in `IncludesHomeBingie.xml`'s `HomeBingie` include as
*additional* `<visible>` tags (Kodi ANDs multiple `<visible>` on one control) rather than restructuring
anything: Widgets BG tint, Details Section (logo/plot/cast/buttons/footer, all nested inside one
group), and the MPAA flags group are hidden. **Left un-hidden:** Spotlight BG (the actual rotating
backdrop image/video preview) and its diffuse vignette — hiding those was the first-pass mistake,
because the backdrop's data source (`BingieSpotlightWidget`, control id 1508) lives *inside* the
same `grouplist id="77777"` as the browsable widget rows, so blanket-hiding that whole grouplist also
killed the backdrop, producing a plain black screen. Fix: leave `77777` itself visible, and instead
add the `HomeMinimal` exclusion only to the specific row-template includes inside it
(`skinshortcuts-template-Widgets` etc.) — keeps the ambient rotating backdrop+colour, drops the
Continue-Watching/Recently-Added row carousels and all text/logo/buttons. Also had to redirect
`Home.xml` control 1000's default-focus fallback from `SetFocus(77777)` to `SetFocus(900)` (the
sidebar) when `HomeMinimal` is set, since focusing into the now-row-less widget container had nowhere
sensible to land.

**Bingie logo removed**: `Skin.ToggleSetting(DisableBingieLogo)` — `Skin.SetBool` does *not* work for
this one, has to be `ToggleSetting`. Needs a full `systemctl restart kodi` after, not just the
builtin call, for the `<visible>` conditions gating the logo images to re-evaluate.

**Accent colour is red** (`ffe50914`, Netflix red) — was changed red→blue→purple during the initial
build-out, then reverted back to red per user request. Colour lives in **two layers that both had to
be fixed**: (1) 17 `Skin.SetString` keys persisted in `addon_data/skin.bingie/settings.xml`
(`BingieProgressBarColor`, `LineUnderMenuIconsColor`, `WatchedIndicator.*.Color`, etc. — full list
worth grepping for `8a2be2` if this happens again) — these are what's actually live, fixed via
`kodi-send --action="Skin.SetString(<id>,ffe50914)"` per key; and (2) the **addon's own default-value
files** (`IncludesDefaultSkinSettings.xml`, `Custom_1101/1102_StartUp*.xml`,
`Custom_1159_MPAATopBar.xml`, `IncludesVariables.xml`, `SettingsScreenCalibration.xml`,
`extras/skinthemes/Reset.theme`) had the purple hex hard-baked into their `onload`
`Skin.SetString(...,ff8a2be2)` fallback lines and inline `colordiffuse="ff8a2be2"` attributes — these
only matter for a fresh profile/theme-reset, but were restored from their `.bak-red` backups anyway
for consistency. **Gotcha**: the `.bak-red` backups for `Reset.theme` turned out to be misleading —
their `.name` label fields said `"Red"` while the hex was already `8a2be2`, because the original
find/replace only touched hex strings, not the adjacent human-readable name text; don't trust a
`.name` field to identify which colour a backup actually contains, diff the hex against a known-good
value instead.

**Profile renamed to the signed-in Jellyfin user's name** (`profiles.xml`, `<name>` +
`<thumbnail>` pointing at a `special://masterprofile/<file>.png`). **Critical gotcha: Kodi rewrites
`profiles.xml` from its in-memory state on its own shutdown.** Editing the file while Kodi is running
(even if you stop it *afterward*) gets silently clobbered — the running process flushes its stale
in-memory profile name back over your edit the moment `systemctl stop kodi` runs. Correct order:
`systemctl stop kodi` **first**, edit `profiles.xml`, *then* `systemctl start kodi`.

**Second gotcha, same rename**: skinshortcuts bakes `String.IsEqual(System.ProfileName,<name>)` onto
*every single menu item* in the generated `script-skinshortcuts-includes.xml` (its own per-profile
menu-scoping feature — irrelevant here since the box only ever has one profile, but the skin's build
process adds it unconditionally). Renaming the profile without also forcing a menu regen makes the
*entire sidebar disappear* (every item's visibility condition now references the old name). Cached in
`addon_data/script.skinshortcuts/skin.bingie.hash`'s `"::PROFILELIST::"` entry, which only picks up
the new name on the *next full regen* — same stop-kodi / rm generated-includes+hash / start-twice
dance as any other skinshortcuts template change.

### Requests — KodiSeerr (Jellyseerr integration)

`plugin.video.kodiseerr` + `repository.kodiseerr`, installed manually (LibreELEC has no Chromium/
browser, so an embedded web view of Jellyseerr's own UI isn't an option — this addon is genuinely the
only maintained Kodi↔Jellyseerr integration). Zips from
`github.com/yocksers/KodiSeerr/releases`: extract, **rename the `Kodiseerr/` folder to
`plugin.video.kodiseerr/`** (matches `addon.xml`'s `id`, the zip's own top-level folder name doesn't),
drop both into `/storage/.kodi/addons/`, restart Kodi so `CAddonMgr::FindAddons` picks them up.

**Addons dropped in over SSH land disabled** (see the general note below) — this one's no exception.
Fixed via the same sqlite `UPDATE installed SET enabled = 1 WHERE addonID IN (...)` against
`userdata/Database/Addons33.db` with Kodi stopped.

**Sidebar entry must use `ActivateWindow(Videos,plugin://plugin.video.kodiseerr/,return)`, not
`RunPlugin`.** `RunPlugin` is correct for program addons with no browsable UI (Moonlight) but doesn't
switch to a Videos window for a `<provides>video</provides>` plugin — button just silently did
nothing. Matches the Movies/TV hub pattern exactly.

**Settings reachable via `kodi-send --action="Addon.OpenSettings(plugin.video.kodiseerr)"`** if
navigating there on-screen is inconvenient (no in-addon settings entry in its own menu; the generic
Kodi path is Settings → Add-ons → My Add-ons → Video add-ons → KodiSeerr → gear icon).
`seerr_username` / `seerr_password` = the Jellyfin login (Jellyseerr's set up with Jellyfin sign-in,
so it's the same credentials, not a separate Seerr-only account) — `seerr_url` =
`http://100.126.205.100:5055` (Asgard's Tailscale IP, port 5055, same reasoning as the Jellyfin
address).

**`disable_browse_pagination` setting fixes the "next page" UX complaint** — off by default, each
category shows one API page (~20 items) with "Page X of Y" / "Jump to Page..." tiles mixed into the
grid. Turning it on makes `default.py` fetch and combine ~10 API pages (~200 items) into one
continuous scrollable grid per category instead — addon-native fix, not a skin/theme workaround.

**"Request entire collection" can pull in phantom unreleased entries** — TMDB collections include
announced-but-unreleased placeholder movies (no release date). Jellyseerr auto-approves and forwards
all of them to Radarr; Radarr adds them fine (`minimumAvailability: released` means it won't actually
search until a real release date exists, so it's inert, not harmful) — but watch for genuine adds
failing alongside it with `409 — UNIQUE constraint failed: MovieMetadata.TmdbId`. That's a Radarr-
internal leftover-metadata collision (looking up the collection pre-populates `MovieMetadata` rows
that then collide on the real add), **nothing to do with quality profiles** — confirmed the profile
ID Jellyseerr sends matches Radarr's actual profile both times this happened. Fix: retry the failed
request via Jellyseerr (`POST /api/v1/request/{id}/retry`) — succeeded on retry both times without
any other change.

## Skin — Arctic Zephyr Mod (historical — replaced by Bingie, 2026-09-12)

Kept for the general Kodi-skinning lessons (skinshortcuts mechanics, forced views, per-path view
memory) — none of the specific file paths below are live anymore. See "Skin — Bingie" above for the
skin actually running on the box.

Home menu is **Movies / TV Shows / Search / Other** as an icon-only rail down the left, a hero
fanart panel with title/plot/year/runtime/rating, and a poster row of *all* items below
(reworked 2026-08-04 — was a bottom text menu with no poster row).

**Menu** is Skin Shortcuts (`script.skinshortcuts`), data in
`userdata/addon_data/script.skinshortcuts/`:
- `mainmenu.DATA.xml` — the four items
- `x1113.DATA.xml` — the "Other" submenu (Settings, Add-ons, Programs/Moonlight, Music, Power)
- `skin.arctic.zephyr.mod.properties` — **the widgets** (JSON, not XML; see below)

**Hubs are positional**: `x1111` = menu item 1, `x1112` = item 2, `x1113` = item 3. That's how a
main-menu item gets a submenu in this skin.

**To rebuild the menu after editing those files** (`kodi-send` + `buildxml` does *not* work):

```bash
systemctl stop kodi
rm -f /storage/.kodi/addons/skin.arctic.zephyr.mod/1080i/script-skinshortcuts-includes.xml
rm -f /storage/.kodi/userdata/addon_data/script.skinshortcuts/skin.arctic.zephyr.mod.hash
systemctl start kodi     # regenerates on load; needs a SECOND restart to actually display
```

Backups on the box, from before each change:

```
/storage/skinshortcuts-includes.xml.bak                                 # original includes
/storage/mainmenu.DATA.xml.bak-netflix  ·  .bak-search                  # menu items
…/addon_data/skin.arctic.zephyr.mod/settings.xml.bak-netflix  ·  .bak-icons
/storage/.kodi/userdata/guisettings.xml.bak-preres                      # pre forced-mode
```

### Home layout — read the skin's own picker, don't guess

`1080i/Custom_SetHomeViewtype.xml` is the authoritative mapping of layout → setting combination:
each button runs `ResetViewtypes` (which clears `home.classicwidgets`, `home.vertical`,
`home.modernwidgets`, `home.vertical.widgets`, `homemenu.netflix`, `homemenu.clean.flix`) and then
sets its own. Reading it beats guessing which of six booleans matters.

| Layout | Settings set after the reset |
|---|---|
| **Vertical + Multi-Widgets + Netflix** ← current | `home.vertical` + `home.vertical.widgets` + `homemenu.netflix` |
| Modern + Multi-Widgets + Netflix | `home.modernwidgets` + `home.vertical.widgets` + `homemenu.netflix` |
| Clean and minimal *(was current until 2026-08-04)* | the above + `homemenu.clean.flix` + `no.homemenu.clear` |

**Icon-only left rail needs BOTH `home.showicons` and `homemenu.only.icons`.** `HomeVerticalMenuWidgets`
(`Includes_Home.xml`) only slides the list left by 296px and hides the text label when both are set;
either alone does nothing useful. Note `HomeContentIcon` / `HomeContentNoIcon` are the *horizontal*
bottom menus (`orientation>horizontal`, fixed `top`) — not this rail.

Optional: `hidewidgettitle` (drop the row label), `home.hide.netflix.plot` (drop synopsis),
`home.slideshowpath` (what the backdrop cycles through; empty = Spotlight playlist, movies only).

### Widgets live in a JSON properties file, not the DATA xml

`userdata/addon_data/script.skinshortcuts/skin.arctic.zephyr.mod.properties` — a flat JSON list of
`[group, labelID, property, value]`. The menu *items* are in `mainmenu.DATA.xml`; their *widgets*
are only here. Available widget definitions come from the skin's `shortcuts/overrides.xml`
`<widget-groupings>` block — "all movies" is `library://video/movies/titles.xml`, all shows is
`library://video/tvshows/titles.xml`.

```json
["mainmenu", "20342", "widget",       "MoviesTitles"],
["mainmenu", "20342", "widgetName",   "Movies"],
["mainmenu", "20342", "widgetType",   "movies"],
["mainmenu", "20342", "widgetTarget", "video"],
["mainmenu", "20342", "widgetPath",   "library://video/movies/titles.xml"],
["mainmenu", "20342", "widgetaspect", "Poster"]
```

**The labelID trap.** skinshortcuts derives labelID by slugifying the *localized* label, and it
resolves inconsistently: TV Shows → `tvshows`, but Movies stays as the raw string id **`20342`**.
Keying both on their `defaultID` silently applies the TV widget and drops the Movies one, with no
error anywhere. Write **both spellings** for each item — an unmatched key is simply ignored.
Verify in the regenerated `script-skinshortcuts-includes.xml`: two `widgetPath` lines, not one.
(`RunScript(...)` actions without a comma get labelID = the addon id, e.g. `script.globalsearch`.)

**Gaming (Moonlight) item had no widget → home panel fell back to showing Movies (2026-08-08).**
Menu item 4 is `Gaming` (`defaultID`/`labelID` = `gaming`, action `RunPlugin(plugin://plugin.program.moonlight-qt/?mode=launch)`). With no widget rows for `gaming` in the properties JSON, hovering it left the previous item's Movies widget on screen. Fixed by giving it the program-add-ons widget from `<widget-groupings>` (`widget=addon`, `widgetType=program`, `widgetTarget=programs`, path `addons://sources/executable/`) — shows Moonlight and other program add-ons instead of films. Written under both `gaming` and `Gaming` keys per the labelID trap; the Python edit that appends them is idempotent (strips old `gaming` rows first). Rebuild the menu via the stop/rm-includes+hash/start dance (needs a second restart to display).

### Search

`script.globalsearch` was already installed, and the skin ships `extras/icons/search.png`. Added as
menu item 3 with action `RunScript(script.globalsearch)`. Scope is set in
`addon_data/script.globalsearch/settings.xml` — its defaults also switch on `musicvideos`,
`artists`, `albums` and `songs`, which pollutes results; only `movies`, `tvshows`, `episodes` are on.

**globalsearch logs nothing at all** — an empty log is not evidence it failed. Screenshot it.

### Library browse view — Netflix style (view 504, 2026-08-08)

Movies, TV Shows, seasons and episodes all use the skin's **`View_504_Netflix`**: clearlogo/title +
plot + art across the top, a horizontal thumbnail row of every item along the bottom (episode stills
for episodes). The skin ships views `50…527`; 504's picker button is `Container.SetViewMode(504)`.

**Use the skin's "Forced Views" feature — it applies to every path of a content type, including
per-show episode/season folders.** This is the mechanism in use (movies/tvshows/seasons/episodes).
Two skin settings in `addon_data/skin.arctic.zephyr.mod/settings.xml`:
```xml
<setting id="enable.forcedviews" type="bool">true</setting>
<setting id="skin.forcedview.episodes" type="string">Netflix</setting>   <!-- also movies/tvshows/seasons -->
```
- **The value is the view's DISPLAY NAME, not its id** — `Netflix` (= `$LOCALIZE[31014]`), not `504`.
  Every view file wraps its container in `<include content="forced_view"><param name="string"
  value="$LOCALIZE[<viewname>]"/>`; the `forced_view` include (`Includes.xml`) shows the view when
  `String.IsEqual(Skin.String(Skin.ForcedView.<content>), <that name>)` — or when the string is empty
  (falls back to the normal selected view). So no `SetViewMode` and no helper service applies it.
- **`enable.forcedviews` is a *load-time* include condition** — toggling it needs a skin reload
  (`ReloadSkin()`) or a Kodi restart. Editing the two strings alone is runtime-live. Cleanest is to
  set both in `settings.xml` while Kodi is stopped, then start. Revert: `settings.xml.bak-forcedviews`.
- Earlier belief that forced views were a "dead end" because `script.skin.info.service` wasn't
  installed was **wrong** — that service is unrelated to view forcing (it's an info/artwork daemon the
  skin optionally launches). It got installed while chasing this; harmless, left in place.

**Episode list — tried a vertical list, kept the row (2026-08-08).** The row layout was queried; a
vertical list *with a per-episode still* turns out not to exist workably on this skin:
- Only views whose panel `<visible>` includes `Container.Content(episodes)` render at all for episodes.
  Of those, **only 504 (Netflix) shows the actual episode still** — and it's horizontal.
- The vertical still-views (500 "Thumbnail", 513 "Vertical Shifted", 57 "Extra Info") render **blank**
  for episodes on this box (500 excludes episodes content; 513/57 came up empty even after long waits +
  navigating to force image load — likely want per-episode fanart the Jellyfin library doesn't carry).
- **56 "Media info"** is a clean vertical list that renders fine, but its large image is the **show
  poster**, not the episode still (item image is `$VAR[PosterImage]`, no landscape/thumb slot).

So it's a real either/or: episode *stills* ⇒ the Netflix **row**; a vertical *list* ⇒ show poster + plot,
no still. User chose stills, so `skin.forcedview.episodes` stays `Netflix`. To switch to the list
instead: `Skin.SetString(Skin.ForcedView.episodes,Media info)`. Forced-view names are per view file's
`$LOCALIZE[...]`: 504=`Netflix`, 56=`Media info` (core #544), 57=`Extra Info` (#31147),
513=`Vertical Shifted` (#31099), 500=`Thumbnail` (#21371).

Kodi's own per-path view memory (`userdata/Database/ViewModes6.db`, `CViewDatabase`) was set first
for the two title lists and still sits there (harmless; forced views override). Its `viewMode` column
is `(viewType<<16)|controlId` — 504 = `66040` (`(1<<16)|504`). Only useful for pinning a single exact
path; it can't cover per-show episode folders, which is why forced views is the right tool here.
Revert those rows: `ViewModes6.db.bak-netflix`.

## Playback OSD

`VideoOSD.xml` picks one of three layouts, defined in `Includes_OSD.xml`:

| Skin setting | Include | Look |
|---|---|---|
| *(neither)* | `OSD1` | solid black bar across the bottom |
| `osd.usethemeNewOSD` ← current | `OSD2` | same content, floating, no backdrop panel |
| `osd.usethemeNewOSDSide` | `OSD3` | full side panel: poster, clearlogo, stars, tagline, genres, plot |

Two traps here, both of which make a correct change look like a no-op:

- **`<include condition="...">` is resolved at skin *load*, not at window activation.** `Skin.SetBool`
  alone changes nothing visible; it needs `kodi-send --action="ReloadSkin()"` (~15s, survives playback).
- **Skin setting names are case-insensitive.** The skin XML says `osd.usethemeNewOSD`; Kodi stores
  it lowercased as `osd.usethemenewosd`. Don't "fix" the casing mismatch — it isn't one.

`osd.showclearlogotitle` and `osd.showplot` have **no effect on OSD1/OSD2** — both still show
"Now playing…" rather than the title. Only OSD3 resolves real metadata, so the title is available;
whichever info label OSD1/OSD2 bind there is unresolved. Not chased down yet.

**OSD auto-close after inactivity: skin string `OSD_Timeout`.** The skin ships the feature
(`Custom_AutoClose_OSD_Helper.xml`, window 1110, instantiated by `Custom_Overlay.xml`): a hidden
dialog whose `<visible>` fires `Dialog.Close(videoosd)` once `System.IdleTime(N)` matches the string.
Only the discrete values it hard-codes work — **3, 5, 10, 15, 20, 25, 30** seconds; empty = never
auto-close (stock default). Set to `10` (2026-08-08) via the skin's own settings action, or directly:
```bash
kodi-send --action="Skin.SetString(OSD_Timeout,10)"      # live, or
# stop kodi; edit addon_data/skin.arctic.zephyr.mod/settings.xml id="osd_timeout"; start
```
Stored lowercased as `osd_timeout` in the skin `settings.xml`; `Skin.String(OSD_Timeout)` reads it
case-insensitively. Sibling `OSD_Info` (values 3/5/7/10) times out the seek/info bar separately.

## Remote keymap — up/down during playback

Stock Kodi binds fullscreen-video up/down to `ChapterOrBigStepForward` / `ChapterOrBigStepBack`, so
the TV remote's arrows jump minutes instead of opening the seek bar. Overridden in
`/storage/.kodi/userdata/keymaps/eclipse-osd.xml` → `OSD`.

**Override both `<remote>` and `<keyboard>`** — stock binds the big-step in *both* files and CEC
input can arrive down either path. Confirm it loaded:

```bash
grep "profile/keymaps" /storage/.kodi/temp/kodi.log
#  Loading special://profile/keymaps/eclipse-osd.xml
```

**`kodi-send` cannot test a keymap** — it dispatches actions directly and bypasses key handling
entirely. Only a physical button press exercises it.

**Back stops playback (2026-08-08).** Same keymap now maps `FullscreenVideo` Back → `Stop`
(`<remote><back>`, `<keyboard><backspace>`/`<escape>`). Stock Back leaves the video *playing behind
the menu* when you return to the movie/TV list; `Stop` ends it. Safe against the OSD: when the OSD
(up/down) or a seek/info dialog is open it consumes Back to close itself, so `Stop` only fires from
plain fullscreen. Keymaps load at kodi start (or `Action(reloadkeymaps)`).

## Timezone / regional

Was UTC until 2026-08-04; now `Australia/Sydney`, verified across a cold boot.

`locale.timezone` is a **dependent list** — it has zero options until `locale.timezonecountry` is
set, so it takes two ordered JSON-RPC calls (country first). Kodi then rewrites
`/var/run/localtime` itself, so the *system* clock follows for free; `/var/run` is tmpfs but Kodi
re-creates the symlink at startup from `guisettings.xml`.

```
locale.timezonecountry = Australia
locale.timezone        = Australia/Sydney
locale.country         = USA (12h)      # still 12-hour clock + US date order
```

## Moonlight

`plugin.program.moonlight-qt` 0.5.2 installed (2026-08-05). **Set EGL card to `card1`** or it won't
start on Pi 5 — pre-write it to `userdata/addon_data/plugin.program.moonlight-qt/settings.xml`
(`display_egl_card` = `card1`) rather than using the addon's settings UI, because that addon_data
dir does not exist at all until first launch. Remotes don't work inside Moonlight — needs the
DualSense.

### First launch is a Docker build, not a download

The addon ships **no binary**. `moonlight.launch()` calls `update()` when
`moonlight-qt/bin/moonlight-qt` is missing under the addon's profile dir, which runs
`resources/build/build.sh` → `resources/build/libreelec/build.sh` → `docker build` against
`Dockerfile.rpi`. **On LibreELEC/RPi this is fast** — the Dockerfile just `apt-get install`s a
prebuilt `.deb` from Cloudsmith's moonlight-qt raspbian repo rather than compiling. Under 5 minutes
on the Pi 5, most of it `apt-get`.

**Docker had to be installed first.** `service.system.docker` is not in the box by default despite
being an optional dep in `addon.xml`:

```bash
kodi-send --action="InstallAddon(service.system.docker)"
# DialogConfirm defaults focus to NO — accept it headlessly:
kodi-send --action="Left"; kodi-send --action="Select"
```

Once enabled the addon runs `dockerd` **itself, outside systemd** (own process, own data-root under
its `addon_data`), so `systemctl start docker` fails with *"PID N still running"* fighting over the
same pidfile. Harmless — `docker version` / `docker ps` already work against the addon's daemon.

**To trigger the build without the Kodi GUI dialog** (bypassing `mode=update`'s `yesno` confirm,
which needs the same Left+Select dance), run `build.sh` over SSH — it auto-detects platform from
`/etc/os-release`, no faking needed:

```bash
export ADDON_PROFILE_PATH="/storage/.kodi/userdata/addon_data/plugin.program.moonlight-qt"
bash /storage/.kodi/addons/plugin.program.moonlight-qt/resources/build/build.sh
```

**Pairing:** as of 2026-08-05 there was no `Moonlight.conf` with a saved host — Sisyphus (the
Sunshine host) was offline at setup. Add it manually by its **Tailscale IP**, as in
`Claude/streaming.md`; mDNS discovery doesn't cross the tailnet. First launch's empty PC-list screen
has an "add PC" option.

### How launch/exit works (and the stuck-on-exit fix, 2026-08-08)

Kodi does **not** run moonlight in-process. `moonlight.py` fires a detached **system-mode**
`systemd-run` unit (system, not `--user`: Kodi's env has no `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS`,
so the `--user` branch — which fails here with *"Failed to connect to bus: No medium found"* — is
never taken). That unit runs `bootstrap_moonlight-qt.sh`, which sources the `kodi_hooks/libreelec/`
hooks: `stop.sh` (`systemctl stop kodi`, frees DRM) and `start.sh` (a `trap … EXIT` that restarts
Kodi when moonlight-qt quits).

**Stuck returning to the Kodi menu = a DRM-master handoff race.** The stock `start.sh` was just
`trap "systemctl start kodi" EXIT`, which restarts Kodi the instant moonlight-qt returns — before
the kernel reaps moonlight's DRM master fd. Kodi's GBM backend then fails to init (`failed to
initialize Atomic/Legacy DRM`, see the "No signal" section) and comes up on a dead/dummy display,
which reads as a hang. Fixed by hardening `start.sh` to wait for the `moonlight-qt` process to be
gone, then `sleep 3` before `systemctl start kodi`. Original saved as `start.sh.orig` alongside it.
**This is an addon file — a Moonlight-addon reinstall will clobber it; re-apply from `start.sh.orig`
or this doc.**

**Verified end-to-end 2026-08-08.** Launched via `RunPlugin(plugin://plugin.program.moonlight-qt/?mode=launch)`,
Kodi went `deactivating`→`inactive`, the wrapper ran (`moonlight-qt.log` shows `--- Starting Moonlight ---`,
Qt/SDL init, KMS `card1`), moonlight-qt (`./moonlight-qt`) ran. `kill -TERM $(pgrep moonlight-qt)`
(stands in for an in-app quit) fired the trap: exit-log logged `waiting for DRM release` → 3 s →
`starting kodi (drm status: connected)`, Kodi was `active` ~6 s later and rendered the home screen
(log: `GUI format 1920x1080, Display 3840x2160 @ 60Hz` — the good-init line, **no** GBM DRM failure).

- **busybox `pgrep -x` returns nothing here** — the hook's wait-loop used `-x`, so it was a no-op
  (harmless: the trap only fires *after* `./moonlight-qt` returns, so the process is already gone, and
  the `sleep 3` is what actually protects the DRM handoff). Changed to plain `pgrep moonlight-qt`.
- The launched process is `./moonlight-qt` (relative), so match it with `pgrep moonlight-qt`, **not**
  `pgrep -x` or a full-path `ps` grep.

Logs (both on persistent `/storage`, survive reboot — LibreELEC's journal is volatile RAM and is
wiped on the box's frequent cold-boots, so don't rely on `journalctl` for a past session):
- `/storage/moonlight-exit.log` — written by the hardened hook: exit time + DRM status at restart.
- `/storage/.kodi/temp/kodi.log` (rotates to `kodi.old.log`) — shows the GBM init result on restart.

## CEC — FIXED (2026-08-03) by replacing the adapter with a proper cable

TV remote controls Kodi. The diagnosis was right: the old passive micro-HDMI adapter omitted
**pin 13**, so picture and EDID worked but CEC was dead. A single-piece micro-HDMI→HDMI cable
fixed it with no software change.

```
cec-ctl -d /dev/cec0 --to 0 --give-device-power-status
  → REPORT_POWER_STATUS (0x90): pwr-state: on (0x00)     # was: Tx, Not Acknowledged, Max Retries

cec-ctl -d /dev/cec0 -S
  0.0.0.0: TV
      1.0.0.0: Recording Device 1     # the Pi
      2.0.0.0: Playback Device 2      # PlayStation 3
      3.0.0.0: Playback Device 3      # NintendoSwitch
      4.0.0.0: Playback Device 1      # Chromecast
```

Kodi picks it up as `Register - new cec device registered on cec->Linux: CEC Adapter`.

For the record, this was never the Pi 5 kernel bug (raspberrypi/linux#7485) — that leaves the
adapter stuck at `f.f.f.f`, never acquiring an address. Here it always had `1.0.0.0`.

`config.txt` still carries `hdmi_ignore_cec_init=1` (legacy firmware option, inert under KMS).
Hisense brands CEC as "Anyview Link" / "CEC Control".

### TV standby tells Kodi to suspend a box that can't suspend — LEFT AS IS, deliberately

`userdata/peripheral_data/cec_CEC_Adapter.xml` carries `standby_pc_on_tv_standby = 13011`
(Kodi string 13011 = **Suspend**), with `standby_devices = 36037` (TV). Switching the TV off
broadcasts CEC standby, and Kodi tries to suspend a kernel whose `/sys/power/state` is empty.

**Fixing CEC armed this.** It was inert for months only because the pin-13 adapter meant the TV's
standby message never arrived; the 2026-08-03 cable swap made it live.

**Decision 2026-08-23: leave it at `13011`.** Changing it to `36028` (Ignore) was offered and
declined — the behaviour is not causing a problem in practice. Don't re-propose this.

## "No signal" on the TV while the Pi is clearly up

**Kodi does not re-probe for a display after it starts.** If Kodi boots with nothing connected —
TV off, TV on another input, cable not seated — it logs

```
CWinSystemGbm::InitWindowSystem - failed to initialize Atomic DRM
CWinSystemGbm::InitWindowSystem - failed to initialize Legacy DRM
```

and falls back to a headless 1280x720 dummy. Connecting the TV afterwards brings the *connector*
up but Kodi keeps driving the dummy, so the TV shows "no signal" forever. Fix is just
`systemctl restart kodi` once the link is up; a good init logs
`GUI format 1920x1080, Display 3840x2160 @ 60.000000 Hz`.

### Use the HDMI port next to the USB-C — and restart Kodi if the cable ever moves (2026-08-23)

The Pi 5 has two HDMI ports and they are **not** interchangeable here:

| Physical port | DRM connector | CEC device |
|---|---|---|
| nearest the USB-C power jack | `card1-HDMI-A-1` | `/dev/cec0` (`vc4-hdmi-0`) ← **use this one** |
| the other one | `card1-HDMI-A-2` | `/dev/cec1` (`vc4-hdmi-1`) |

**Kodi picks its output connector once, at startup, and never re-probes** — the same root cause as
the dummy-display trap above, but it bites differently with two ports: boot Kodi while the cable is
in the *second* port and it binds `HDMI-A-2` and keeps painting there, so moving the cable back to
the first port leaves the TV on "no signal" even though that link is perfect.

Kodi registers a **single** CEC adapter, and in practice CEC only works on the USB-C-side port
(libcec's Linux backend takes `/dev/cec0`). So the second port gives the very confusing combination
of **picture but no remote control**. That pairing — working video, dead CEC — is the fingerprint of
being on the wrong port; it is not a CEC fault to go debugging.

Which connector Kodi actually took:

```bash
grep FindConnector /storage/.kodi/temp/kodi.log     # "using connector: HDMI-A-1"
cat /sys/class/drm/card1-HDMI-A-1/enabled           # enabled = this is the one being driven
```

**`enabled` is the useful field, not `status`.** During this fault `HDMI-A-1` read
`connected` + 256-byte EDID + `enabled=disabled`, while the abandoned `HDMI-A-2` read
`disconnected` + `enabled=enabled`. Note a *disconnected* connector keeps its last EDID cached, so
"both ports show a HISENSE EDID" proves nothing about where the cable is.

Prove the good port is genuinely live before suspecting hardware — this answers in one command and
needs a real electrical link end to end:

```bash
cec-ctl -d /dev/cec0 --to 0 --give-device-power-status   # TV replies REPORT_POWER_STATUS → link is fine
```

Fix is `systemctl restart kodi` with the cable in the USB-C-side port. The Glance panel at
`asgard:9554` has a button for it.

Check the link itself from the kernel, not from Kodi:

```bash
cat /sys/class/drm/card1-HDMI-A-1/status    # connected / disconnected
wc -c < /sys/class/drm/card1-HDMI-A-1/edid  # 0 = no DDC; 256 = TV read fine
```

`disconnected` + 0-byte EDID means no HPD (pin 19) and no DDC (pins 15–16) — electrical, never
software. But note a TV that is **off or on another input often de-asserts HPD**, which reads
identically to a broken cable. Confirm the TV is on and on the right input before blaming hardware.
To watch for flapping while reseating a connector:

```bash
prev=""; for i in $(seq 1 300); do s=$(cat /sys/class/drm/card1-HDMI-A-1/status); \
  [ "$s" != "$prev" ] && echo "$(date +%H:%M:%S) -> $s" && prev=$s; sleep 1; done
```

`timeout` is **not** on LibreELEC — wrap long-running commands from the client side instead.

### Auto-recovery: `hdmi-hotplug.service` (added 2026-08-30)

Kodi's never-re-probe behaviour is now handled automatically, so a restored link brings the picture
back on its own instead of needing the Glance button or an SSH restart.

```
/storage/hdmi-hotplug.sh                              # the watcher
/storage/.config/system.d/hdmi-hotplug.service        # unit (same mechanism as tailscaled)
/storage/hdmi-hotplug.log                             # persistent, survives the volatile journal
```

Polls `card1-HDMI-A-1/status` every 2 s. On a `disconnected → connected` edge it waits 5 s for HPD
and the EDID read to settle, then restarts Kodi **only** if all of these hold:

| Guard | Why |
|---|---|
| still `connected` after the settle wait | rejects flapping while a plug is being reseated |
| `enabled` != `enabled` | `enabled` is what says Kodi is *driving* this connector; `status` only says a cable is present. Already-driving ⇒ do nothing, so TV sleep/wake never causes a pointless restart |
| `pgrep moonlight-qt` finds nothing | Moonlight deliberately stops Kodi and owns DRM — restarting Kodi mid-stream would fight it for the display |
| `kodi.service` is active | if Kodi is stopped on purpose, leave it stopped |

Note `pgrep -x` returns nothing on this box (busybox), so the moonlight check uses a plain match —
the same trap already documented for the Moonlight exit hook.

**Verified 2026-08-30** against fake sysfs files rather than the real connector, because `echo on >
status` poisons Kodi's persisted `videoscreen.resolution` and then needs a full reboot to get 4K
back. All three paths confirmed: link-up-while-on-dummy → `restarting kodi`; link-up-while-already-
driving → `no action`; brief flap → `bounced back … ignoring`.

### The micro-HDMI plug backs out of the Pi (2026-08-04, recurred 2026-08-30)

Reported as "when the TV sleeps and we turn it back on, HDMI won't show up" — which sounds exactly
like the Kodi-doesn't-re-probe trap above, and isn't. **The Pi cannot sleep at all**:

```bash
cat /sys/power/state ; cat /sys/power/mem_sleep    # both EMPTY — no sleep states in this kernel
```

So "it went to sleep" is always the TV, never the Pi, and there is no Pi-side sleep to disable.
The actual fault was the micro-HDMI plug working loose at the **Pi** end after two days. Reseating
it fixed it instantly — the link came back within one poll and CEC re-acquired `1.0.0.0`.

**The fast discriminator is the TV's own input list.** A TV greys out an HDMI input when it sees no
+5V presence (pin 18) from the source. So with the Pi powered and driving output:

| TV input list | Pi sees | Meaning |
|---|---|---|
| input greyed out / missing | `disconnected`, edid 0 | dead **both** directions — cable or seating |
| input selectable | `disconnected`, edid 0 | TV-side HPD only — input/eco setting |
| input selectable | `connected`, edid 256 | link fine, blame Kodi (restart it) |

Pins 15/16/18/19 are adjacent at the end of the connector, so a partly-withdrawn plug kills exactly
that group while leaving the TMDS lanes (1–12) intact. Same failure *class* as the pin-13 adapter,
one pin group over.

**This recurred on 2026-08-30 and presented identically.** Both connectors read `disconnected` +
`enabled=disabled` + **0-byte EDID**, `dmesg` logged `[drm] Cannot find any crtc or sizes` ×3, and
Kodi fell back to `GUI format 1280x720`. The TV's input list had the Pi's input **greyed out**,
which is the discriminator that settles it — no +5V presence, so the link was dead in both
directions. Reseating at the Pi end is the fix; nothing over SSH can help.

Worth ruling out first, because it reads *identically* to a dead cable and costs one command — a
connector left forced `off`:

```bash
echo detect > /sys/class/drm/card1-HDMI-A-1/status   # clears any stale force; safe, unlike `echo on`
```

Also note Kodi's early log lines can carry a **pre-NTP clock** (they were stamped 2025-06-26 on a
box whose `date` was correct), so a stale-looking timestamp is not evidence the log is old — check
`date -r /storage/.kodi/temp/kodi.log` and the tail instead.

To prove TMDS is alive without touching the cable, force the connector on — it ignores HPD and
synthesises a fallback VESA mode list (no EDID, so 1024x768 max):

```bash
echo on > /sys/class/drm/card1-HDMI-A-1/status   # force; 'detect' restores normal behaviour
systemctl restart kodi                            # picture now = TMDS fine, only HPD/DDC dead
```

**Undo this with `echo detect`** before diagnosing further, or you mask real detection. It also
poisons Kodi: it persists the fallback mode as `videoscreen.resolution`, and because the GBM
backend re-adopts whatever mode is already programmed on the CRTC, restarting Kodi is *not* enough
to get 4K back — it takes a reboot.

CEC `Physical Address: f.f.f.f` in this state is a **consequence, not the kernel bug**. The address
is derived from EDID, so no EDID always means `f.f.f.f`. The RPi5 bug (raspberrypi/linux#7485)
looks the same but with a healthy link.

## `script.litebox` — was silently hammering Asgard, FIXED 2026-09-07

Earlier notes called this "harmless log noise". **It was not.** litebox is the daemon the skin runs
to produce its blurred-backdrop effect (`Startup.xml` → `RunScript(script.litebox,daemon=True)`,
gated on the skin's `EnableEffects`). For every item you highlight it downloads that item's
backdrop **at full resolution** and blurs it:

```
script.litebox --> 5err: module 'PIL.Image' has no attribute 'ANTIALIAS'
   img: http://192.168.0.226:8096/Items/<id>/Images/Backdrop/0?Format=original
```

Two independent Pillow-10 breakages meant it failed on every single image while still doing all the
downloading — roughly **300 full-size fetches a minute, forever**, for an effect that never once
appeared. It was **26% of the entire Kodi log** (367 of 1419 lines).

| # | Break | Fix |
|---|---|---|
| 1 | `Image.ANTIALIAS` removed in Pillow 10 (`resources/lib/utils.py`, 2 uses) | → `Image.LANCZOS`. Not an approximation: they were the *same constant*, just renamed |
| 2 | `ImagingCore.gaussian_blur` now wants an `(x, y)` radius pair, not a scalar — `argument 1 must be 2-item sequence, not int` (`resources/lib/imageoperations.py`) | `MyGaussianBlur` now subclasses **`ImageFilter.GaussianBlur`** instead of `ImageFilter.Filter` |

Fixing #1 alone is not enough — it just uncovers #2, which had been masked because nothing ever got
that far. Confirm the exact signature empirically rather than guessing, since it is a private C API:

```python
im.im.gaussian_blur(30)          # TypeError: argument 1 must be 2-item sequence, not int
im.im.gaussian_blur((30,30), 3)  # OK
```

Inheriting Pillow's own `GaussianBlur` is deliberate: it tracks whatever signature Pillow uses, and
because it is a `MultibandFilter` it blurs RGB in **one** C call instead of splitting into three
bands and merging (which is what the old `ImageFilter.Filter` base forced).

**How to tell a real blur from the broken passthrough — compare file sizes, don't eyeball it.**
When the filter threw, the `except` still saved the *unmodified* source, so a "blurred" file was
byte-identical to its input:

```
1344487 bytes  fd75b8625f0432c71712a5229551ac04.png            ← source
1344487 bytes  fd75b8625f0432c71712a5229551ac041.0-blur304.png ← "blurred", identical = broken
  21159 bytes  f11a1c686a91c120af5cbabba3dfffdc1.0-blur304.png ← after the fix
```

A real gaussian blur is smooth and compresses ~60x smaller. Equal sizes = the blur is silently
failing. Cache lives in `userdata/addon_data/script.litebox/` and is keyed by image hash, so
already-cached artwork generates nothing new — browse to something fresh when testing.

Result: litebox log lines went **367/1419 (26%) → 9/487 (1.8%)**, zero `ANTIALIAS` errors, and the
blur effect works for the first time.

**Both are addon files — a litebox update clobbers them.** Originals kept as `utils.py.orig` and
`imageoperations.py.orig`; idempotent patchers at `/storage/patch_litebox.py` and
`/storage/patch_litebox2.py` (the second refuses to run if its anchor is missing rather than
patching blindly). **Delete `__pycache__/*.pyc` after editing** or the stale bytecode shadows the
change and the fix looks like it did nothing.

### Remaining, benign

A few lines per session when the highlighted item has no artwork — the skin passes its
`common/null.png` placeholder, litebox can't open it, and its `else` branch then trips over an
unbound `img`:

```
co: [Errno 2] No such file or directory: '.../fa645dc466a124f0a550e76191ae02f6.png'
go_mapop: cannot access local variable 'img' where it is not associated with a value  cmarg: blur
```

Latent upstream bug in litebox's error handling, exercised only in the no-artwork case. A handful of
lines, not the old 300/minute — left alone.
