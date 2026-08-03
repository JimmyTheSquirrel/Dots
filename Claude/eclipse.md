# Eclipse — Raspberry Pi 5 TV Box (LibreELEC + Kodi)

**Host:** Eclipse · Raspberry Pi 5 · `192.168.0.184` (LAN) · `100.80.62.3` (tailnet, as `eclipse`)
**OS:** LibreELEC 12.2.1 aarch64 (Kodi 21 Omega)
**Purpose:** Jellyfin playback on the TV, driven by the TV remote; also a Moonlight client.

> **NOT MANAGED BY NIX.** Everything here is imperative state on an SD card. A rebuild means
> re-flashing and redoing these steps by hand — this file is the recipe. Built 2026-08-02,
> replacing Raspberry Pi OS Trixie (its desktop was too laggy on a TV and had no CEC).

## Access

```bash
ssh root@192.168.0.184          # LAN;     key auth; pubkey at /storage/.ssh/authorized_keys
ssh root@100.80.62.3            # tailnet; same key
```

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

`sqlite3` is **not** on LibreELEC — copy DBs to Sisyphus and use `nix shell nixpkgs#sqlite`.
Kodi rewrites its DBs on exit, so **stop Kodi before editing them**.

```bash
kodi-send --action="ActivateWindow(Home)"       # /usr/bin/kodi-send — drives Kodi remotely
kodi-send --action="TakeScreenshot"             # → /storage/screenshots/ ; scp back and LOOK
kodi-send --action="ReloadSkin()"
systemctl restart kodi
```

Screenshots are the fastest way to verify UI work — don't infer from logs. Main log:
`/storage/.kodi/temp/kodi.log`.

**`kodi-send` silently fails on `RunScript(...)` actions with `&` parameters** — no error, no log
line. Skin Shortcuts' `buildxml` could not be triggered this way. Simple builtins work fine.

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
ssh root@192.168.0.184 'systemctl stop kodi'
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

## Skin — Arctic Zephyr Mod

Home menu is **Movies / TV Shows / Other**, full-bleed rotating backdrop, no poster row.

**Menu** is Skin Shortcuts (`script.skinshortcuts`), data in
`userdata/addon_data/script.skinshortcuts/`:
- `mainmenu.DATA.xml` — the three items
- `x1113.DATA.xml` — the "Other" submenu (Settings, Add-ons, Programs/Moonlight, Music, Power)

**Hubs are positional**: `x1111` = menu item 1, `x1112` = item 2, `x1113` = item 3. That's how a
main-menu item gets a submenu in this skin.

**To rebuild the menu after editing those files** (`kodi-send` + `buildxml` does *not* work):

```bash
systemctl stop kodi
rm -f /storage/.kodi/addons/skin.arctic.zephyr.mod/1080i/script-skinshortcuts-includes.xml
rm -f /storage/.kodi/userdata/addon_data/script.skinshortcuts/skin.arctic.zephyr.mod.hash
systemctl start kodi     # regenerates on load; needs a SECOND restart to actually display
```

Backup of the original includes: `/storage/skinshortcuts-includes.xml.bak`.

**The poster row was a layout, not a widget.** Four layout expressions exist; the wanted one is
`HomeIsCleanMinimal` = `home.modernwidgets` + `home.vertical.widgets` + `homemenu.netflix` +
`homemenu.clean.flix`, all true. Plus `hidewidgettitle` to drop the "Spotlight" label.

Optional: `home.hide.netflix.plot` (drop synopsis), `home.slideshowpath` (control what the
backdrop cycles through; empty = default Spotlight playlist, movies only).

## Moonlight

`plugin.program.moonlight-qt` 0.5.2 installed. **Set EGL card to `card1`** in its settings or it
won't start on Pi 5. Remotes don't work inside Moonlight — needs the DualSense. It downloads the
moonlight-qt binary on first run.

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

## Known noise

`script.litebox` spams `module 'PIL.Image' has no attribute 'ANTIALIAS'` every ~10s — dead Pillow
10 API, addon unmaintained. Harmless to playback; disable it if the log noise matters.
