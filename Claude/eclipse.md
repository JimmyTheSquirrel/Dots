# Eclipse — Raspberry Pi 5 TV Box (LibreELEC + Kodi)

**Host:** Eclipse · Raspberry Pi 5 · `100.80.62.3` (tailnet, as `eclipse`)
**LAN (DHCP):** `192.168.0.182` (eth0) · `192.168.0.183` (wlan0) — two MACs, two leases
**Link:** wired ethernet since 2026-08-23, with 2.4 GHz wifi as an automatic hot standby. See *Network*.
**OS:** LibreELEC 12.2.1 aarch64 (Kodi 21 Omega)
**Purpose:** Jellyfin playback on the TV, driven by the TV remote; also a Moonlight client.

> **NOT MANAGED BY NIX.** Everything here is imperative state on an SD card. A rebuild means
> re-flashing and redoing these steps by hand — this file is the recipe. Built 2026-08-02,
> replacing Raspberry Pi OS Trixie (its desktop was too laggy on a TV and had no CEC).

## Access

```bash
ssh root@100.80.62.3            # tailnet; key auth; pubkey at /storage/.ssh/authorized_keys
ssh root@192.168.0.183          # LAN;     same key
```

**Use the tailnet address.** The LAN lease is not reserved and has already moved once — it was
`.184` until 2026-08-04, which produced a confusing `No route to host` mid-session. Find the
current one with `tailscale status | grep eclipse`, which prints the direct LAN endpoint.

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

## Glance control panel

Asgard serves a button panel at **`http://asgard:9554`**, embedded as an iframe on Glance's
**Eclipse** page. Buttons: restart Kodi, sync Jellyfin Movies, sync TV Shows, reboot (double-tap to
confirm). A status row polls every 10s — Eclipse reachable, Kodi state, HDMI link, active output
mode, uptime. `/status` also returns `edid` and `needs_kodi_restart`.

- Service: `systemd.services.eclipse-control` in `Modules/server.nix`
- Implementation: `Resources/Eclipse-Control/eclipse-control.py`
- Auth: dedicated keypair, private half in sops as `eclipse-ssh-key`, public half appended to
  Eclipse's `/storage/.ssh/authorized_keys` (backup at `authorized_keys.bak`)

**Driven over SSH, not Kodi JSON-RPC** — deliberately. The headline action is restarting a *wedged*
Kodi, and a wedged Kodi cannot answer its own API. Kodi's HTTP server is disabled here anyway
(`services.webserver=false`; JSON-RPC binds `127.0.0.1:9090`).

The status row encodes the "no signal on a healthy box" trap: HDMI `connected` + Kodi `active` +
**no output mode** lights an amber hint to restart Kodi. Re-flashing the SD card means re-appending
the public key, or the panel goes dark with `reachable: false`.

### Making an iframe widget look native in Glance

Glance renders in **JetBrains Mono**, but the font is embedded in its Go binary — there is no file
to point at in `${pkgs.glance}` — and the panel is a *different origin* (9554 vs 8888), so the font
cannot be borrowed cross-origin. The service therefore serves its own copy from
`pkgs.jetbrains-mono` (`ECLIPSE_FONT_DIR` → `share/fonts/WOFF2`, routes `/font/{regular,medium,bold}.woff2`).
Without this the panel silently falls back to the device's mono font and reads subtly foreign,
especially on a phone.

Design tokens are lifted from the custom CSS in `Modules/server.nix`, not eyeballed — border
`hsla(160,40%,40%,.15)`, radius `12px`, hover glow `hsla(160,50%,40%,.10)`, title letter-spacing
`0.08em`. Theme accents are `positive-color hsl(142,72%,39%)` / `negative-color hsl(0,84%,60%)`.

**Glance iframes are a fixed height** (`height: 300`) and cannot self-size — cross-origin means no
resize handshake. Pick a height that fits the *phone* layout, where the button grid drops to two
columns and the status cells wrap; desktop then carries some slack. Buttons use a centred
`auto-fit, minmax(150px, 1fr)` grid inside a `max-width: 1020px` wrapper, otherwise they stretch
into full-width bars on a 2560px display.

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

**Server:** `http://192.168.0.226:8096` (Asgard, LAN — Asgard's WAN egress shaping exempts
RFC1918, so direct play is unthrottled). Signed in as **Caitlin**.

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

Demand-side lever if it regresses: the Jellyfin addon's `maxBitrate` is `23` = *1000 Mbps [default]*,
i.e. uncapped. Values are indexes into a list (`6`=4 Mbps, `8`=6 Mbps, `10`=8 Mbps); capping makes
Asgard transcode down instead of direct-playing a ~10 Mbps remux.

## Skin — Arctic Zephyr Mod

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
