# Asgard — Media Server Reference

## Overview

Asgard is a NixOS media server running on dedicated hardware (Intel i5-14400, 1TB NVMe, 8TB HDD).
Configuration defined in `Modules/server.nix`, host in `Hosts/Asgard/system.nix`.
Everything is declarative. A fresh deploy needs only the sops secrets populated before building.

---

## Current Status (as of 2026-06-25)

### Deployed on dedicated Asgard hardware
- Nixflix arr stack (Sonarr/Radarr/Lidarr/Prowlarr) — Forms auth via `hostConfig.password._secret` → `admin-password`
- Jellyfin, Jellyseerr, SABnzbd — all healthy
- Prowlarr — 3 indexers pre-configured (Miatrix, NZBgeek, NzbPlanet) via sops secrets, app sync configured to push to all arrs
- SABnzbd — FrugalUsenet (primary) + Newshosting (backup), dual Usenet backbone, running inside Mullvad VPN namespace with kill switch
- Glance dashboard (port 8888) — native `server-stats` widget, live network panel + speed test (JS-driven, see below), tabbed service monitors, Yggdrasil Network widget
- FileBrowser, Immich, Audiobookshelf, Shelfarr — running
- Decluttarr — running, config auto-generated from individual arr/sabnzbd API key secrets
- Recyclarr — runs on boot + daily. **Only four quality profiles exist** (2026-08-23): "Asgard - Movies" (Radarr), "Asgard - TV" / "Asgard TV - 1080p" / "Asgard - Anime" (Sonarr). All TRaSH stock profiles were deleted so Jellyseerr shows a short list
- `arr-policy.service` — applies what recyclarr cannot: series→profile mapping, `seriesType`, release profiles, Radarr collection repointing, profile deletion, Jellyfin per-user audio settings
- **Tailscale** — stock Tailscale (free plan), tailnet `tailb54b82.ts.net`. Asgard (100.126.205.100), Sisyphus (100.70.29.3), rhys-s25 (100.68.29.23)
- **Networking** — stock Tailscale, `tailscale0` trusted in firewall, all services reachable via `asgard:port` from tailnet devices
- **Mullvad VPN** — SABnzbd confined to WireGuard network namespace (`/var/run/netns/vpn`), Mullvad Sydney exit, socat proxy host:8080 → namespace
- **tailscale-status-proxy** — Python HTTP service (port 9553) queries tailscaled Unix socket, serves simplified JSON for Glance Yggdrasil widget
- **Observability stack** — Glance (8888, native systemd service), Prometheus (9090, node scrape 5s, CORS enabled), Loki (3100), Grafana (3001, anonymous viewing + iframe embedding), Alloy, Exportarr, cAdvisor, SABnzbd exporter

---

## Port Reference

| Service            | Port | Access         | Notes |
|--------------------|------|----------------|-------|
| Jellyfin           | 8096 | Tailscale + CF tunnel | jellyfin.bifrost-vault.com |
| Jellyseerr         | 5055 | Tailscale + CF tunnel | requests.bifrost-vault.com |
| Immich             | 2283 | Tailscale + CF tunnel | photos.bifrost-vault.com |
| Sonarr             | 8989 | Tailscale only | |
| Radarr             | 7878 | Tailscale only | |
| Lidarr             | 8686 | Tailscale only | |
| Prowlarr           | 9696 | Tailscale only | |
| SABnzbd            | 8080 | Tailscale only | Inside Mullvad VPN namespace. socat proxy from host. Dark theme: `web_color = "Night"` |
| Audiobookshelf     | 13378 | Tailscale only | Podman container |
| Shelfarr           | 5056 | Tailscale only | Podman container — book request portal |
| ~~Homepage~~       | ~~3000~~ | — | Removed — replaced by Glance |
| File Browser       | 8081 | Tailscale only | Quantum fork. Credentials synced from sops |
| tailscale-status-proxy | 9553 | internal only | HTTP proxy for Glance Yggdrasil widget |
| **Glance**         | 8888 | Tailscale only | Main dashboard (native systemd service, not container). Native server-stats + network panel + tabbed service monitors + Yggdrasil Network widget |
| network-panel      | 9555 | Tailscale only | Live throughput from `/proc/net/dev` + last speed-test result; `POST /run` triggers a test. Backs the Glance Network group |
| **ttyd**           | 7681 | Tailscale only | Web terminal (Glance "Terminal" page iframe + Management bookmark). Login prompt (root `login` entrypoint) — log in as `rock`, passwordless sudo for reboot/shutdown |
| **Grafana**        | 3001 | Tailscale only | System stats (bar gauge panels) + logs. Anonymous viewing enabled for iframe embedding |
| **Prometheus**     | 9090 | Tailscale only | Metrics collection. CORS enabled (`--web.cors.origin=.*`) for Glance JS polling |
| **Loki**           | 3100 | Tailscale only | Log storage. Health: `:3100/ready` |
| node_exporter      | 9100 | internal only  | Host system metrics |
| cAdvisor           | 9101 | internal only  | Per-container metrics (Podman socket) |
| sabnzbd-exporter   | 9387 | internal only  | SABnzbd queue/speed metrics |
| exportarr-sonarr   | 9708 | internal only  | Sonarr arr metrics |
| exportarr-radarr   | 9709 | internal only  | Radarr arr metrics |
| exportarr-lidarr   | 9710 | internal only  | Lidarr arr metrics |
| exportarr-prowlarr | 9711 | internal only  | Prowlarr arr metrics |

---

## Stack Architecture

### Native NixOS services (via nixflix v1.2.0)
- Sonarr, Radarr, Lidarr, Prowlarr, Jellyfin, Jellyseerr (seerr), SABnzbd
- Nixflix auto-wires: Prowlarr ↔ arr services, Jellyseerr ↔ Jellyfin/Sonarr/Radarr
- All API keys pre-seeded from sops — no manual UI wiring needed

### Native NixOS services (not nixflix)
- Immich — `services.immich`, manages its own PostgreSQL + Redis. `host = "0.0.0.0"` required — default `localhost` binds to `[::1]` (IPv6 only) making it unreachable. `ExecStartPre` script creates `.immich` marker files in all subdirs of `/data/photos/` (encoded-video, thumbs, upload, backups, library, profile) — Immich refuses to start without these.
- Tailscale — `services.tailscale` (stock, no login-server flag)
- Cloudflared — `services.cloudflared`
- **WAN egress shaping** — `wan-egress-shaping.service` (in `Modules/server.nix`) caps WAN-bound upload on enp3s0 at 30 Mbit via HTB + fq_codel. Home uplink is 50 Mbit; Jellyfin transcode segments burst at full line rate every ~3s, spiking latency ~180ms and rubber-banding LAN game sessions. RFC1918 destinations bypass the cap (LAN direct-play unaffected). Inspect with `tc -s qdisc show dev enp3s0`.

### Native NixOS service (background sync)
- **Recyclarr** — `recyclarr-config.service` generates `/var/lib/recyclarr/recyclarr.yml` with API keys from sops. `recyclarr-sync.service` runs via a systemd timer (5min after boot, then daily). Check with `journalctl -u recyclarr-sync`.

  **Four profiles, all custom (non-trash_id).** They merge the resolution tiers into one ladder and exclude remux entirely (Eclipse's Pi decoder chokes on 4K HDR remuxes, and remux size saturates WAN for remote streams):

  | Profile | Service | Tops out at | Used by |
  |---|---|---|---|
  | Asgard - Movies | Radarr | Bluray-2160p | all 237 movies |
  | Asgard - TV | Sonarr | WEB 2160p | 42 series |
  | Asgard TV - 1080p | Sonarr | WEB 1080p | Game of Thrones only |
  | Asgard - Anime | Sonarr | Bluray-1080p | 5 anime series |

  **The TRaSH stock profiles were deleted 2026-08-23** and their `trash_id` entries REMOVED from the
  recyclarr config. Do not put them back — recyclarr recreates any profile it is told to manage, and
  they only cluttered Jellyseerr's dropdown. Jellyseerr defaults are set by
  `seerr-radarr-profile`/`seerr-sonarr-profile`.

  **`Asgard TV - 1080p` exists only for Game of Thrones.** Its sole 4K source is a Blu-ray remaster,
  ~17 GB/ep against 3.4 GB on disk — a 5x jump that would have added ~1 TB on its own, where the
  other seven shows with real 4K cost only +1.6 to +8.8 GB/ep. Reusable for any show where 4K isn't
  wanted; assign per-series in `arr-policy`.

  **`Asgard - Anime` has no 2160p tier, deliberately.** TV anime is mastered at 1080p, so 2160p anime
  releases are upscales — B-Global's "2160p" JJK files were 2.03 GB against 1.54 GB for the native
  1080p Crunchyroll rips. TRaSH's own anime profile also tops out at Bluray-1080p. See *Anime must be
  English dub* below.

  **Was BROKEN 2026-07-11 → 2026-08-11, now FIXED.** Last successful sync had been 2026-07-10
  22:10; it failed every nightly run for a month (36 failures of 40 runs) before being found while
  verifying the storage work. Two separate upstream breaks:

  1. **Fixed:** `RECYCLARR_APP_DATA` was removed upstream and recyclarr now hard-errors on it, so
     the sync never even started. Renamed to `RECYCLARR_CONFIG_DIR` in `Modules/server.nix`.
  2. **Fixed:** TRaSH's config-templates repo dropped `includes.json` entirely and renamed every
     template, so `include: - template: …` resolves **nothing** — there are no include templates
     any more, and all 10 ids the config used were dead. The replacements are *whole-config*
     templates (`radarr-remux-web-1080p`, `radarr-remux-web-2160p`, sonarr `web-1080p`,
     `web-2160p`) which **cannot be used with `include:` at all**. Their contents are now inlined
     in `Modules/server.nix` by `trash_id` — trash_ids are stable content hashes, whereas template
     names have churned twice. Scores and CF definitions still come live from the guide on every
     sync; only the selection is pinned.

  **Debugging trap:** recyclarr 8.6 moved its data from `repositories/` to
  `resources/config-templates/git/`. The stale `repositories/` copy still lists the **old** ids, so
  grepping it "proves" a template exists while recyclarr correctly reports it missing. Always read
  `resources/config-templates/git/official/templates.json`. Handy: `recyclarr config create -t <id>`
  writes a starter config to `configs/`, and `recyclarr sync --preview` is a dry run.

  **The outage did no damage** — both failures happened during startup/config parsing, *before any
  API call*, so nothing was ever partially applied or zeroed.

  **Migration verified 2026-08-11 by diffing every profile before and after.** Allowed qualities,
  cutoffs, `cutoffFormatScore` (10000), `minUpgradeFormatScore` (1) and `upgradeAllowed` are all
  **identical** — the profiles did not get looser, which matters because Radarr's are deliberately
  strict (see `memory/feedback_quality_profiles.md`). The only change was a month of TRaSH audio
  scoring (TrueHD ATMOS +5000, DTS X +4500, FLAC/PCM/DD+/DTS) plus new negatives (Bad Dual Groups,
  Line/Mic Dubbed, Black and White Editions at -10000): Radarr 22→39 and 23→40 scored CFs, Sonarr
  31→37 and 33→38. Sonarr's manual "Any 1080p" profile was not recyclarr-managed and was untouched
  at the time — **it has since been deleted (2026-08-23)** along with every other stock profile.
  All queues were 0 afterwards — no upgrade wave.

### Mullvad VPN Namespace (SABnzbd)
- `netns-vpn.service` — creates `/var/run/netns/vpn`
- `wg-mullvad.service` — WireGuard interface inside vpn namespace, Mullvad Sydney endpoint (146.70.200.2:51820)
- `veth-vpn.service` — veth pair bridging host ↔ vpn namespace (10.200.1.1/24 ↔ 10.200.1.2/24)
- SABnzbd: `NetworkNamespacePath = "/var/run/netns/vpn"`, `bindsTo = wg-mullvad.service` (kill switch)
- `sabnzbd-proxy.service` — socat TCP proxy, host 0.0.0.0:8080 → 10.200.1.2:8080
- DNS: Mullvad 10.64.0.1 via bind-mounted resolv.conf + `/etc/hosts` for Usenet server IPs
- VPN IP: 10.66.10.54, private key in sops: `mullvad-wg-private-key`

### Podman containers
- Audiobookshelf, Shelfarr, File Browser Quantum, Decluttarr, cAdvisor, SABnzbd exporter
- Backend: `virtualisation.oci-containers.backend = "podman"`
- Docker compat socket (`podman.socket` at `/run/podman/podman.sock`) enabled for cAdvisor
- **Decluttarr:** `decluttarr-config.service` generates `/var/lib/decluttarr/config/config.yaml` from individual arr + sabnzbd sops secrets before the container starts. No separate `decluttarr-env` secret — reuses existing API key secrets directly. `remove_orphans: false` — do NOT enable this, it kills newly queued downloads before SABnzbd picks them up (within 2 minutes).
- **SABnzbd exporter:** `docker.io/msroest/sabnzbd_exporter:latest` (NOT ghcr.io — that's a private 403). Env file written by `sabnzbd-exporter-env.service` with `SABNZBD_BASEURLS` + `SABNZBD_APIKEYS`.
- **Glance:** Moved from container to native systemd service (`pkgs.glance`) — needed for `server-stats` widget to access host `/proc`/`/sys`. Config baked into Nix store via `pkgs.writeText "glance.yml"`. Uses `DynamicUser = true`.
- **cAdvisor:** `gcr.io/cadvisor/cadvisor:latest`, `--privileged`, mounts Podman socket. Port 9101.

---

## `arr-policy.service` — per-item state recyclarr can't express

Recyclarr owns quality profiles and custom-format *scores*. It has no concept of which series uses
which profile, series type, release profiles, Radarr collections, or Jellyfin user settings. Those
are per-record database state, so `arr-policy.service` applies them over the APIs — idempotently, on
every rebuild, so a fresh install converges. Config lives in Nix; nothing is clicked in a UI.

What it does: series→profile mapping · `seriesType=anime` on the 5 anime · the
`Asgard - fake dual audio` release profile · repoints Radarr collections · deletes stock quality
profiles · sets Jellyfin `AudioLanguagePreference=eng` + `PlayDefaultAudioTrack=false` for every
user except Rhys.

Ordered **after** `seerr-*-profile` on purpose — Jellyseerr pointed at the stock "Any" profile,
which this service deletes. Repoint first, then delete.

Two things that block a profile delete and cost time if you don't know them:

- **Radarr collections carry their own `qualityProfileId`.** Two profiles with **zero movies** still
  refused to delete — 29 and 19 collections referenced them. Repoint collections first.
- Profile deletion uses an explicit **NAME list**, never "everything unused", so a profile created
  later on purpose is never silently destroyed.

---

## Anime — English dub is a HARD requirement

Audited 2026-08-23: **28 of 162 anime files had no English track at all.** JUJUTSU KAISEN S1 was a
**French** Blu-ray rip (`MULTi...SHiNiGAMi`); SAKAMOTO DAYS had 6 **Portuguese** (`DUAL-sh4down`)
and 2 raw-Japanese files.

`Asgard - Anime` now carries `Anime Dual Audio` = **2000**, `Dubs Only` = **2000**, and
**`min_format_score: 2000`**.

> **Scoring a custom format highly is NOT enough. Sonarr ranks QUALITY TIER ahead of custom-format
> score.** Proved empirically: a Japanese `Bluray-1080p` (score 0) beat a `WEBDL-720p` dual-audio
> release (score **4100**) and was grabbed. CF score only breaks ties *within* one quality tier.
> `min_format_score` is the only lever that rejects non-dubs outright — and it is TRaSH's own
> documented recipe: *"If you must have Dual Audio releases set the Minimum Custom Format Score to
> 2000."* Their ladder: 0 = neutral (default), 10 = same-tier preference, 101 = above one tier,
> 2000 = beats resolution tiers.

**2000 works because of an arithmetic gap.** Best possible non-dub = WEB Tier 01 1700 + streaming
boosts 150 + repack 7 = **1857**. Any dub starts at **2000**. ⚠️ **Raising tier scores above ~1990
closes that gap and silently breaks the whole policy.**

**Accepted consequence:** no dub available = the episode stays **MISSING**. There is no sub
fallback. For a currently-airing season the dub can lag the sub by weeks.

### Four rules that each silently defeated this

1. **`Language: Not Original` (-10000) was applied to anime.** It rejects releases whose language
   isn't the series' *original* — for anime the original IS Japanese, so it penalised the English
   dub. Correct for live-action TV. Now TV-profiles-only.
2. **`x265 (HD)` (-10000) was applied to anime.** TRaSH's anime unwanted list is only
   `Anime Raws / Anime LQ Groups / AV1 / Dubs Only / VOSTFR / v0` — **no x265**. 10-bit x265 is the
   normal format for anime groups. This scored genuine 1080p dual-audio releases at -8000 and forced
   a 720p grab. Now TV-profiles-only.
3. **`Anime Dual Audio` matches the release TITLE, not the audio.** A Portuguese
   `...H.264.DUAL-sh4down` matched its `1080p.*DUAL` alternation and scored as if English.
   `sh4down` is **not** in TRaSH's `Bad Dual Groups` (all 34 checked).
4. **Dub-only releases don't match `Anime Dual Audio` at all** — e.g.
   `Sakamoto Days - 03 [English Dub][1080p]` scored 0 and was rejected by the minimum. Fixed with
   TRaSH's **`Dubs Only`** CF (`9c14d194486c4014d422adc64092d794`) at **+2000** — TRaSH scores it
   **-10000** because their guide is written for sub-watchers; the sign is deliberately inverted.

### `Asgard - fake dual audio` release profile

Ignored terms: **`sh4down`, `AV1`**. A *release profile*, not a custom format, because recyclarr's
`reset_unmatched_scores` zeroes locally-scored CFs on its next sync.

**AV1 is blocked here as well as by the AV1 custom format, because the CF has a gap:** its regex is
`\bAV1\b`, which does **not** match `[Breeze].Sakamoto.Days-S01E13.1080p.AV1Dual.Audio.weekly` —
there's no word boundary between `AV1` and `Dual`. That release scored +2000 on `Anime Dual Audio`
alone and was grabbed despite the CF sitting at -10000. Release-profile terms are plain substring
matches, so they have no such gap. AV1 matters here because **Eclipse is a Pi 5 — HEVC hardware
decode but no AV1 decoder**.

### No 2160p tier — and don't re-add it

TV anime is mastered at 1080p (often 720p); native 4K anime is essentially nonexistent, and a WEB-DL
cannot exceed what the platform streamed. The B-Global "2160p" JJK files were **2.03 GB** against
**1.54 GB** for the native 1080p Crunchyroll rips already on disk — 4x the pixels for 32% more data,
i.e. an upscale. TRaSH's anime profile has no 2160p tier either.

2160p was briefly added on 2026-08-23 because JJK *looked* like it only had dubs at 4K — that was an
artefact of the x265 penalty (rule 2 above) suppressing the real 1080p releases. Once fixed, S01E02
alone had 150 dual-audio releases including Bluray-1080p. **Don't re-add 2160p because a show "only
has dubs at 4K" — check whether a scoring rule is hiding the 1080p ones first.**

### Useful

**You don't need to delete bad files.** Once they score below `min_format_score`, Sonarr treats them
as cutoff-unmet and replaces them itself.

```bash
# what audio does each file actually have?
curl -s -H "X-Api-Key: $KEY" "http://localhost:8989/api/v3/episodefile?seriesId=$ID" \
  | jq -r '[.[]|.mediaInfo.audioLanguages]|group_by(.)[]|"\(length) x \(.[0])"'
```

Note `Dubs Only` releases are English-**only** (no Japanese track), unlike dual-audio. JJK S1 is
mixed: 4 dual-audio Kitsune files, 20 English-only DSNP.

---

## Observability Stack

### Architecture
```
journald (all units) → Alloy → Loki (3100)
node_exporter / cAdvisor / Exportarr / SABnzbd exporter → Prometheus (9090)
Glance (8888) — reads Prometheus via custom-api widgets
Grafana (3001) — reads Loki + Prometheus, provisioned datasources
```

### Glance Dashboard (port 8888)
2-column layout: **Stats + network + service health** (full) | **Clock + Yggdrasil** (small)

**Glance renders each widget server-side exactly ONCE per page load.** `page.js`
calls `fetchPageContent()` a single time from `setupPage()` — there is no
client-side widget refresh in 0.8.5. Anything that has to move on screen must be
driven by JavaScript injected through `document.head`. Don't add a `custom-api`
widget with a short `cache:` expecting it to tick; the cache only affects the
next page load.

**Page 1 — Asgard (main):**

There is deliberately **no bookmarks column**. Every link it held was also a
monitor row, and monitor rows are already clickable — the page was listing the
same thirteen services twice. Add new services to the monitors, not a sidebar.

Full column:
- Native `server-stats` widget: CPU/RAM/Disk bars, `/data/media` shown as "Media Pool", others hidden
- **Network** `group` (tabs: Network / Speed test) — see below
- **Service health** `group` (tabs: All / Media / Downloads / Arr / Management).
  "All" is the default tab and repeats every site from the category tabs; the
  duplicated checks are local HTTP GETs on a 1m cache and cost nothing.

Small column:
- Clock widget (12h format)
- Yggdrasil tree banner (split CSS: Norse rune ring SVG as `::before`, tree PNG as `::after` via `/assets/yggdrasil.png` from `glanceAssets` derivation + `assets-path`)
- Yggdrasil Network `custom-api` widget: queries `tailscale-status-proxy` (port 9553) which reads tailscaled Unix socket, 15s cache, shows device names + online/offline dots + IPs.

**Custom CSS (injected via `document.head` `<style>`):**
- Widget borders: subtle green-tinted rounded corners, hover glow effect
- Yggdrasil banner: ring SVG as `::before` data URI, tree PNG as `::after` via `/assets/yggdrasil.png`
- Active page tab + clock text glow
- Widget title letter-spacing
- `.np-*` — the network panel (numbers, SVG sparklines, "Run now" button)
- The section divider is `.column-full > .widget + .widget`. The child combinator
  is load-bearing: as a descendant selector it drew a rule between group tab panes.

**Page 2 — Downloads:**
- SABnzbd iframe: `type: iframe`, `source: http://asgard:8080`, `height: 700`
- SABnzbd auth removed — iframe loads without login (tailnet-only access)
- UI prefs (compact/fullscreen/tabbed) set server-side via `web_compact/web_fullscreen/web_tabbed = true`, but iframe needs "Use global interface settings" ticked within its own browser context

**Theme:** `positive-color: hsl(142, 72%, 39%)` (green ticks for online), `negative-color: hsl(0, 84%, 60%)`

**Icons:** Use `sh:` prefix (selfh.st colored icons). For apps not in selfh.st, use direct CDN URLs. Avoid `si:` — monochrome.

**SABnzbd iframe requirements:** `x_frame_options = 0` in nixflix SABnzbd misc settings. Dark mode: `web_color = "Night"` (NOT "Dark").

### Network panel + speed test (port 9555)

`Resources/Network-Panel/network-panel.py`, run by `systemd.services.network-panel`.
One process, two jobs:

- **Live throughput** — a thread samples `/proc/net/dev` for `enp3s0` once a second
  and keeps a 60s history, so the numbers *and* the sparklines are populated on the
  first request rather than filling in over the next minute.
- **Speed test** — serves the last result written by `speedtest.service`, and
  `POST /run` starts a fresh one.

`GET /api` is consumed twice: by Glance over localhost to server-render the first
frame, and by the poller in `document.head` over the tailnet (every 2s) to keep it
moving. Hence `Access-Control-Allow-Origin: *` and the `0.0.0.0` bind. Still
tailnet-only — 9555 is not in `allowedTCPPorts` and `tailscale0` is trusted.
The poller derives its base URL from `location.hostname`, so it survives being
opened by IP instead of by name. It matches elements by `id` (`np-down`,
`np-spark-up`, `np-st-*`, `np-run`) — **renaming an id in the widget template
without editing the script silently breaks the live half.**

Runs as root only so `POST /run` can `systemctl start speedtest.service`.

**This replaced `flow` inside a second read-only ttyd on :7682.** That panel worked,
but ttyd kills its child whenever the websocket drops — a backgrounded tab was
enough — and xterm.js then painted its reconnect banner over the widget, which is
what it spent most of its life showing. Don't reintroduce a terminal-in-an-iframe
for this.

#### speedtest.service / speedtest.timer

Ookla's official CLI (`ookla-speedtest`, unfree — `allowUnfree` is already on),
every 6h with `Persistent = true` and a 15m randomised delay. Two traps, both
already handled, both of which cost a debugging round:

- **`HOME` must be set.** The CLI does `std::string(getenv("HOME"))` unguarded and
  aborts on `basic_string::_M_construct null not valid`, dumping core before it
  touches the network. Set to `/var/lib/speedtest` (its `StateDirectory`), where it
  also keeps its license-acceptance flag.
- **The EULA goes to stdout ahead of the JSON on a fresh machine**, so the script
  takes the first line matching `^{` rather than the whole stream — otherwise
  `latest.json` is a licence notice. Result is written to a temp file and renamed,
  so a failed run never replaces a good one.

**Upload reads ~28-30 Mb/s and that is correct**, not a broken uplink:
`wan-egress-shaping` puts every WAN-bound packet in a 30 Mbit htb class. The widget
footnote says "shaped to 30" for exactly this reason. It shapes Asgard's own egress
only, so a test from the desktop will legitimately show a much higher upload.
Download is unshaped (~420 Mb/s measured 2026-08-22).

**The run pauses SABnzbd first (added 2026-08-24).** Ookla measures spare capacity,
not link capacity, so before this the timer fired mid-download and published the
leftovers — one run read 47.8 Mb/s where the same link measured 421 twenty seconds
later with the queue paused. The script pauses via `mode=config&name=set_pause&value=6`,
waits 8s for in-flight NNTP connections to drain, and `ExecStopPost` resumes.

Three details that matter if you touch it:

- The resume lives in **`ExecStopPost`, not a trap in the script**, so it also runs
  when the unit is killed on `TimeoutStartSec` — the one case a trap would miss.
- `set_pause` takes **minutes** and is a pause with a deadline. It is set to 6, one
  past the 5m `TimeoutStartSec`, so even a hard kill can't strand the queue.
- The `/var/lib/speedtest/.sab-paused` marker is what authorises the resume, so a
  queue you paused by hand is never silently restarted. The script deliberately does
  **not** clear it on entry: a marker left behind means the last run died before
  `ExecStopPost`, and carrying it forward is what gets the queue un-paused.

The script logs `background traffic at test start: N Mb/s down` to the journal.
SAB is the only thing it can pause — if that line isn't near zero, something else
(a Jellyfin stream, an arr import) was running and the result is a headroom figure
again. Check it before believing a bad number.

**IPv6 is not a factor**, despite `enableIPv6 = false`: `enp3s0` still takes an RA
and the test binds the GUA by default (`net.ipv6.conf.all.disable_ipv6 = 1` but
`enp3s0` is `0`). Measured v4 vs v6 within 1.5% of each other. Note `speedtest -i
<addr>` cannot be used to force a family — it fails `bind(3, …)` because the config
fetch picks its family from DNS first; toggle
`sysctl net.ipv6.conf.enp3s0.disable_ipv6` instead.

Running the CLI by hand does **not** update the panel — only `speedtest.service`
writes `latest.json`.

### Grafana (port 3001)
- Admin password from sops `grafana-admin-password` (owner = grafana)
- `allow_embedding = true` + anonymous auth (Viewer role) — enables Glance iframe embedding
- Loki + Prometheus datasources auto-provisioned via `provision.datasources.settings`
- **CRITICAL:** NixOS Grafana module does NOT support `uid` field in datasource provisioning (generates `uid: null` → crash). Always use name strings: `datasource = "Prometheus"`
- **System Stats dashboard** (uid: `asgard-system`, provisioned via `pkgs.writeTextDir`):
  - 4 bar gauge panels (Retro LCD display mode) in 2x2 grid, refresh 1s
  - CPU (panelId=1, dark-green), Disk /data (panelId=4, dark-red), Network (panelId=3, dark-purple), Memory (panelId=2, dark-yellow)
  - Prometheus node scrape interval: 5s for near-real-time data
- **Logs dashboard:** `{job="journald", unit=~"$unit"}` with `$unit` variable
  - Variable type: Query, Label values for label `unit`, filter `{job="journald"}`
  - Regex: `/^(sonarr|radarr|lidarr|prowlarr|sabnzbd|jellyfin|seerr|recyclarr|decluttarr|immich|podman|loki|grafana|prometheus|alloy)/`
  - Multi-value + Include All option enabled
- **DB path:** `/var/lib/grafana/data/grafana.db` — wipe when fundamentally changing datasource/dashboard provisioning

### Alloy journald → Loki pipeline
Config in Nix store (`pkgs.writeText "config.alloy"`). Labels extracted: `unit` (systemd unit), `host`, `level`. Alloy service needs `SupplementaryGroups = ["systemd-journal"]` to read the journal.

---

## Arr Stack — Auth

Auth is fully declarative via nixflix's `hostConfig.password._secret`. Each arr service uses
Forms auth with the `admin-password` sops secret. No manual wizard step needed on fresh deploy.

**Prowlarr indexers** are pre-configured via `nixflix.prowlarr.config.indexers`: Miatrix, NZBGeek, NzbPlanet. Each has an `apiKey._secret` pointing to `indexer-api-keys/<Name>` in sops.

**SABnzbd usenet servers (both priority 0, load-balanced):**
- **FrugalUsenet**: `aunews.frugalusenet.com:563`, SSL, 60 connections, UsenetExpress backbone. Creds: `usenet/frugalusenet/username` + `/password`
- **Newshosting**: `news.newshosting.com:563`, SSL, 30 connections, Highwinds backbone. Creds: `usenet/newshosting/username` + `/password`
- Both at priority 0 = parallel load-balancing. NOT priority-1 backup — user confirmed this preference (backup only fills 430-missing articles anyway, doesn't help with corrupt bytes).

**SABnzbd misc settings (all in `nixflix.usenetClients.sabnzbd.settings.misc`):**
- `par2_multicore = 1` + `par2_threads = 12` — par2cmdline-turbo uses all cores
- `abort_max_missing = 10` + `fail_hopeless_jobs = 1` — fail (not pause) hopeless jobs so decluttarr + arrs can blocklist and re-search
- `pause_on_pwrar = 2` — abort on encrypted RAR (prevents stalls)
- `delete_failed = 1` + `history_retention = "30" days-archive` — cleanup + retention
- `article_cache_size = "1G"` — RAM cache
- `direct_unpack = false` + `direct_unpack_tested = true` — **BOTH keys required.** SAB's `directunpacker.py:test_disk_performance()` auto-enables direct_unpack on any disk >100 MB/s unless `tested=true`. Direct unpack races with obfuscated-NZB deobfuscation (SAB forum t=27128) → mislabeled _FAILED_ folders.
- `pre_check = 0` — skips SAB's pre-download article verification (the slow "Checking" phase in the queue UI). **Applied via SAB HTTP API, NOT nix** — nixflix's override for this specific key doesn't land in the generated template (mystery, TBD).
- `host_whitelist` — asgard, container.internal, VPN namespace IP
- `inet_exposure = 4` — safe because tailnet-only
- `x_frame_options = 0` — needed for Glance iframe
- `web_color = "Night"`, `web_compact`, `web_fullscreen`, `web_tabbed` — UI

**KNOWN DO-NOT-ADD keys (from 2026-06 incident, see [memory/sab-corruption-postmortem.md](../.claude/projects/-home-rock-Dots/memory/sab-corruption-postmortem.md)):**
- ❌ `par_option = "N=A"` — invalid syntax, silently breaks par2 verify
- ❌ `ssl_ciphers = "AES128-SHA256"` — no benefit, breaks TLS with newer Usenet providers
- ❌ Direct Unpack on (default) — the auto-enable bug requires both `direct_unpack = false` AND `direct_unpack_tested = true`

**When SAB corruption reappears:** run `sudo nix-store --verify --check-contents` + `memtester` BEFORE touching SAB config. The 2026-06 "corrupt RAR" saga was actually failing RAM, not any SAB knob.

**CRITICAL — do NOT use `settings.auth` env vars:**
Setting `SONARR__AUTH__METHOD=None` (or any Disabled/None combo) via nixflix `settings.auth`
causes a .NET DI container crash (`Unable to cast DryIoc.ScopedItemException to IAuthorizationHandler`).
Use `hostConfig.password._secret` only.

---

## Nixflix Notes

**Flake input:** `github:kiriwalawren/nixflix/v1.2.0`, follows `nixpkgs-unstable`

**Option paths differ by service:**
- Arr services: `nixflix.sonarr.config.apiKey._secret`
- Jellyfin: `nixflix.jellyfin.apiKey._secret` (no `config` wrapper)
- Jellyfin users: `nixflix.jellyfin.users.admin.password._secret`
- Seerr: `nixflix.seerr.apiKey._secret` (no `config` wrapper), requires `package = pkgs.jellyseerr`

**nixflix systemd services:**
- `seerr.service` — the Jellyseerr process (NOT `jellyseerr.service`)
- `seerr-setup.service` — nixflix's initial wiring script
- `seerr-env.service` — writes API key header file
- `jellyfin-setup-wizard.service` — Jellyfin initial setup (creates admin user + libraries)

**Custom Jellyseerr quality profile services (in server.nix):**
- `seerr-radarr-profile.service` + timer — sets Radarr default quality profile to "Asgard - Movies"
- `seerr-sonarr-profile.service` + timer — sets Sonarr default to "Asgard - TV" **and the separate
  `activeAnimeProfileId` to "Asgard - Anime"**. Jellyseerr keeps a distinct anime profile setting;
  it previously pointed at the TV profile, so anime requests never got the fansub tier scoring.
- Both run after `seerr-setup.service`, `Restart = on-failure` + `RestartSec = 30`, plus
  `StartLimitBurst = 5` so a persistent failure gives up instead of looping.
- **Auth is the `jellyseerr-api-key`, NOT a Jellyfin session cookie.** The older cookie flow is what
  broke them — see below.

> ### ⚠️ These failed silently for three weeks — the fix is not the error you see
>
> From 2026-07-31 to 2026-08-23 both units failed every 30s (**restart counter 2665**), which also
> made every `nixos-rebuild switch` exit 4.
>
> The visible error was `jq: Cannot index object with number (0)` — misleading. The real cause: they
> logged into Jellyseerr as the Jellyfin **`admin`** account, which Jellyseerr imported as an
> ORDINARY user (`permissions: 32` = REQUEST only, **not** ADMIN). Login returned HTTP 200, then
> every `/api/v1/settings/` call returned a 403 **object**, and `.[0]` on an object threw.
>
> **The API key works fine on settings endpoints.** Any earlier note saying they require session
> cookies is wrong. Verify with:
> ```bash
> curl -s -H "X-Api-Key: $(sudo cat /run/secrets/jellyseerr-api-key)" \
>   http://localhost:5055/api/v1/settings/sonarr
> ```
>
> Consequence while broken: Jellyseerr sat on the stock **"Any"** profile for everything.

**Known nixflix bug (v1.2.0):** `seerr-setup.service` fails on library fetch step (`curl -sf` exits 22).
The Jellyfin connection IS established on first run — only the library activation fails.
Our `seerr-library-setup.service` handles this (see below).

---

## Jellyseerr Setup — Declarative Fix

### The problem
Nixflix's `seerr-setup.service` connects Jellyfin → Jellyseerr but fails at library activation.
Jellyseerr's setup wizard stays open until libraries are toggled and setup is marked initialized.

### Our fix: `seerr-library-setup.service`
Defined in `Modules/server.nix`, runs after `seerr-setup.service`.

**What it does:**
1. Waits for Jellyseerr to be responsive
2. Checks `GET /api/v1/settings/public` → skips everything if `initialized == true` (idempotent)
3. Logs in via `POST /api/v1/auth/jellyfin` with `{username, password}` only (no server config fields)
4. Syncs libraries: `GET /api/v1/settings/jellyfin/library?sync=true`
5. Enables all: `GET /api/v1/settings/jellyfin/library?enable=id1,id2,...`
6. Marks done: `POST /api/v1/settings/initialize`

### Critical API notes
- **Session cookie required** for all settings endpoints — API key (`X-Api-Key`) does NOT work
- **Login endpoint:** `POST /api/v1/auth/jellyfin`
  - Fresh setup (no Jellyfin configured): send full payload `{username, password, hostname, port, useSsl, urlBase, email, serverType}`
  - After setup (Jellyfin already wired): send ONLY `{username, password}` — full payload returns HTTP 500 "already configured"
- **Library endpoint:** `/api/v1/settings/jellyfin/library` (singular, not `libraries`)
  - `?sync=true` — fetches from Jellyfin and returns array
  - `?enable=id1,id2,...` — enables specified libraries (comma-separated IDs)
- **`POST /api/v1/settings/jellyfin/sync`** requires `Content-Type: application/json` header or returns 415 — skip it, not needed
- **`POST /api/v1/settings/initialize`** — marks setup complete, returns `{"initialized":true}`
- `/api/v1/settings/public` — public endpoint, no auth needed, has `initialized` field

### Manual recovery (if service fails)
```bash
# Login
sudo bash -c 'P=$(cat /run/secrets/jellyfin-admin-password); curl -s -c /tmp/t.txt -X POST -H "Content-Type: application/json" -d "{\"username\":\"admin\",\"password\":\"$P\"}" http://localhost:5055/api/v1/auth/jellyfin'

# Sync + enable libraries
curl -s -b /tmp/t.txt "http://localhost:5055/api/v1/settings/jellyfin/library?sync=true"
# Note the IDs returned, then:
curl -s -b /tmp/t.txt "http://localhost:5055/api/v1/settings/jellyfin/library?enable=ID1,ID2"

# Initialize
curl -s -b /tmp/t.txt -X POST "http://localhost:5055/api/v1/settings/initialize"
```

---

## Homepage Dashboard — REMOVED

Homepage (`services.homepage-dashboard`) has been removed and replaced by Glance (port 8888).
Glances (`services.glances`) was also removed — it was only used as a Homepage widget backend.

All service monitoring is now done via Glance native `server-stats` widget + the network panel on :9555.

---

## Sops Secrets Reference

All in `Secrets/secrets.yaml`. Generate API keys with: `od -An -tx1 -N16 /dev/urandom | tr -d ' \n'`

```
sonarr-api-key
radarr-api-key
lidarr-api-key
prowlarr-api-key
jellyseerr-api-key
sabnzbd-api-key
sabnzbd-nzb-key
sabnzbd-username                   # SABnzbd web UI username
sabnzbd-password                   # SABnzbd web UI password
usenet/frugalusenet/username       # FrugalUsenet NNTP username
usenet/frugalusenet/password       # FrugalUsenet NNTP password
indexer-api-keys/Miatrix           # Prowlarr indexer API key
indexer-api-keys/NZBGeek           # Prowlarr indexer API key
indexer-api-keys/NZBPlanet        # Prowlarr indexer API key
jellyfin-api-key
jellyfin-admin-password
cloudflare-tunnel                  # full credentials JSON from cloudflared tunnel create
admin-username                     # shared admin username for FileBrowser, Immich seed (e.g. admin)
admin-password                     # shared admin password for FileBrowser, Immich seed
grafana-admin-password             # Grafana admin password — sops owner = "grafana"
mullvad-wg-private-key             # WireGuard private key from Mullvad (SABnzbd VPN namespace)
usenet/newshosting/username        # Newshosting NNTP username
usenet/newshosting/password        # Newshosting NNTP password
user-password-hash                 # bcrypt password hash ($ signs get mangled by sops --set)
```

**Cloudflare tunnel UUID:** `804d54a8-e7ad-4f34-812d-3052cf862c47` (in server.nix)
**Tunnel created with:** `cloudflared tunnel create asgard` on Sisyphus

---

## Storage Expansion — 12TB (installed & tested 2026-08-10)

`/data` hit **98% full (142G free of 7.3T)**, so a second HDD was fitted.

**New drive:** WD Red Pro 12TB, `WD122KFBX-68CCHN0`, serial `WD-B01NL0DD` — SATA 6Gb/s, CMR,
7200rpm, 512e/4096p, firmware `83.00A83`, 12,000,138,625,024 bytes (10.9 TiB).

**Status: LIVE.** Partitioned, formatted, and pooled with the 8TB via mergerfs into a single
`/data/media` (~19 TB, 12 TB free). See "Media Pool" below.
Stable path: `/dev/disk/by-id/ata-WDC_WD122KFBX-68CCHN0_WD-B01NL0DD`.

**Root cause of the initial no-show: the SATA data cable was never connected.**
The drive sits in a hot-swap cage, and **the bay LED lights from backplane power alone** — it
indicates nothing about a data link. That LED is exactly what made the drive look connected. On a
hot-swap cage one power feed lights the whole cage, while **each bay needs its own SATA data cable**
run to a motherboard port. `SATA link down` on every free port is the signature of this.

### SATA topology (established 2026-08-10)

Single controller: `00:17.0 Intel Raptor Lake SATA AHCI [8086:7a62]`

```
AHCI vers 0001.0301, 4/4 ports implemented (port mask 0xf0)
ata1-ata4:  DUMMY          — not in the port mask, never probed
ata5:       link up 6 Gbps — WD122KFBX  (12TB) = /dev/sda
ata6:       link up 6 Gbps — ST8000VN002 (8TB) = /dev/sdb, /dev/sdb1 = /data
ata7:       link down      — free
ata8:       link down      — free
```

**2 free SATA ports remain.** A port reporting `SATA link down (SStatus 4)` means the PHY sees
nothing on the wire — the drive is not electrically present (no data cable, no power, or dead).

**Device letters shuffled when the 12TB was added** — the 8TB moved `sda` → `sdb`. `/data` mounted
correctly regardless because the mount is by partition label (`disk-hdd-data`), not `/dev/sdX`.
**Always target these disks by `/dev/disk/by-id/...` for anything destructive.**

### Re-probe SATA without rebooting

```bash
sudo sh -c 'for h in /sys/class/scsi_host/host*; do echo "- - -" > $h/scan; done'
sudo dmesg | grep -iE "SATA link|\.00: ATA-"
```

Confirmed working — a live re-probe re-reports every port's link state. No reboot needed to
re-test after reseating cables.

### Diagnosis notes (for next time a disk doesn't appear)

Check in this order — cheapest and most likely first:

1. **Is a SATA data cable actually run to that drive/bay?** This was the answer. A lit bay LED is
   not evidence of one.
2. **Power** — link down looks identical whether power or data is missing.
3. **Not SAS?** `WD122KFBX` (KFBX suffix) is the SATA Red Pro. SAS 12TB drives are common
   secondhand, need an HBA, and are told apart by the connector: SATA has a **gap** between the
   7-pin and 15-pin sections, SAS bridges them with solid plastic.
4. **3.3V PWDIS trap** — only applies to *shucked* drives. Pin 3 of the SATA power connector held
   high keeps the drive in permanent reset. Fix is Kapton over power pins 1-3, or a Molex→SATA
   adapter (no 3.3V line). Check whether the PSU lead even *has* an orange wire first — many
   modern PSUs omit 3.3V entirely, in which case this cannot be the fault.
5. **BIOS-masked port** — a masked port shows as `DUMMY` and is never probed. Here all 4
   implemented ports are probed every boot, so this was never in play.

### Acceptance test results (2026-08-10)

| Check | Result |
|-------|--------|
| `smartctl -H` overall-health | **PASSED** |
| Power_On_Hours | **0** — genuinely new, not resold/shucked |
| Power_Cycle_Count / Load_Cycle_Count | 5 / 1 (all from this install) |
| Reallocated / Pending / Offline_Uncorrectable | 0 / 0 / 0 |
| UDMA_CRC_Error_Count | 0 — clean data cable |
| SMART short self-test | Completed without error |
| Sequential write, 8 GB `oflag=direct` | **275 MB/s** |
| Sequential read, 8 GB `iflag=direct` | **275 MB/s** |
| Temperature under load | 23°C → 25°C |
| SMART re-check after 16 GB I/O | all counters still 0 |

275 MB/s is at spec for this drive (rated ~272 MB/s sustained on outer tracks).

**No surface scan was run** — the quick check was chosen deliberately over `smartctl -t long`
(~24h) or a `badblocks -wsv` burn-in (4-7 days). If this drive ever misbehaves, run the long test
before assuming a software cause.

**8TB health after the same power-cycling:** `PASSED` — 0 reallocated, 0 pending,
**0 UDMA_CRC errors**, 43 power cycles, 22°C. Unharmed.

---

## Media Pool — mergerfs (live since 2026-08-10)

The two HDDs are pooled into one `/data/media` so Jellyfin and the arrs see a single location.

```
/mnt/disk1   8TB  ext4  (partlabel disk-hdd-data)  ─┐
                                                    ├─ mergerfs ──> /data/media   ~19 TB
/mnt/disk2   12TB ext4  (partlabel disk-hdd2-data) ─┘

/data/photos  <- bind mount /mnt/disk1/photos   (Immich)
/data/.state  <- bind mount /mnt/disk1/.state   (arr SQLite DBs)
/data itself is a plain directory on the NVMe root — no longer a mountpoint.
```

**mergerfs is a UNION filesystem — it merges the directory tree, not blocks.** Every file lives
whole on exactly one disk, and the pool is a single namespace so each file appears exactly once.
Losing a drive costs only that drive's files; the survivor keeps serving. This is why mergerfs and
**not** LVM/btrfs-single/RAID0, which span one filesystem across both spindles and lose everything
if either disk dies.

**Only media is pooled.** `/data/.state` (arr SQLite, 3.6G) and `/data/photos` (Immich, 234M) stay
on real ext4 via bind mounts — **SQLite on FUSE is a known source of locking corruption**, and
there is no capacity reason to pool 3.8G.

**No service paths changed.** `nixflix.mediaDir`, `stateDir`, the container bind mounts,
`immich.mediaLocation` and the tmpfiles rules all still point at `/data/...`. No data was copied —
the 8TB's `/data` simply became `/mnt/disk1`.

**No redundancy — this is a deliberate choice.** A dead drive loses its own files, which are
re-downloadable via the arrs. **Immich photos are NOT re-downloadable and still have no backup.**
SnapRAID parity would need a third drive ≥12TB.

### Pool options (`Modules/server.nix`)

| Option | Why |
|--------|-----|
| `category.create=mfs` | New files go to the branch with most free space — i.e. the 12TB, until they converge. Matches the "let it fill naturally, no rebalance" decision. |
| `moveonenospc=true` | A branch filling mid-write relocates the file instead of ENOSPC. |
| `minfreespace=50G` | Stop choosing a branch below this. Replaces the ext4 root reserve as the "don't fill completely" guard. |
| `allow_other` | **Required** — podman containers and non-root services must read the pool. Needs `programs.fuse.userAllowOther = true`. |
| `cache.files=partial`, `dropcacheonclose=true` | Standard media-serving cache behaviour. |

Omit `use_ino` — default and deprecated in mergerfs 2.x.

### Gotchas discovered while building this

- **Device letters shuffle constantly.** The 8TB has been `sda`, then `sdb`, then `sda` again
  across three boots today. Nothing broke because every mount is by **partlabel**. Always address
  these disks by `/dev/disk/by-partlabel/...` or `/dev/disk/by-id/...` — **never `/dev/sdX`**.
  The old `device = "/dev/sda"` in disko silently came to point at the wrong disk.
- **Sonarr/Radarr report `freeSpace: null`** for root folders on the pool, and the `/api/v3/diskspace`
  endpoint returns empty. This is .NET's `DriveInfo` not classifying `fuse.mergerfs` as a fixed
  drive. Harmless — `accessible: true` and imports work — but free-space pre-checks are skipped.
  Use Glance/Grafana for pool capacity, not the arr UIs.
- **Dashboards must query `/data/media`, not `/data`.** `/data` stopped being a mountpoint, so
  `node_filesystem_*{mountpoint="/data"}` silently returns empty and the Glance disk readout
  plus the Grafana disk panel go blank. Both were repointed at `/data/media`.
- **`/mnt/disk2/media` must exist before the pool can mount** — mergerfs errors on a missing branch
  and tmpfiles runs too late to help. Created by hand at install time.
- **Nix merge rule:** `systemd.services = lib.genAttrs ... ` collides with the many
  `systemd.services.<name> = { ... }` definitions in `server.nix`. Dotted paths merge into attrset
  *literals* only, never into a computed expression. The mount guards are therefore written as
  individual `systemd.services.<name>.unitConfig.RequiresMountsFor = ...` lines.
- **ext4 root reserve reclaimed:** `tune2fs -m 0` on the 8TB freed **373 GB** (142G → 515G, 98% →
  94%). The 12TB was formatted `-m 0` from the start. A pure data disk needs no root reserve.

### Verified after a cold boot

All five mounts correct; pool 19T with 12T free; 160 movies / 13 series / 461 episodes in Jellyfin
matching the on-disk counts exactly; Sonarr and Radarr queues both 0 (**no re-downloads**);
filebrowser container reads the pool (confirms `allow_other`); zero failed units.

---

## ⚠ Missing-disk behaviour — `nofail` + `RequiresMountsFor`, never one without the other

**The hazard (confirmed the hard way on 2026-08-10):** with the 8TB disconnected and no `nofail`,
Asgard **would not finish booting** — systemd waited ~90s for the partition, `local-fs.target`
failed, and it dropped to **emergency mode, which runs before networking**. No SSH,
`No route to host` indefinitely, physical recovery only.

**Current state: both HDD mounts are `nofail`, and every consuming service has
`RequiresMountsFor`.** These two must always travel together:

- `nofail` alone is dangerous: `systemd.tmpfiles.rules` in `Modules/server.nix` creates `/data`,
  `/data/media` and `/data/.state/services` unconditionally, so a boot that continues without the
  disk creates them *empty on the NVMe* and the arrs re-initialise on top.
- `RequiresMountsFor` alone is what makes `nofail` safe: services **fail closed** instead of
  running against an empty library.

Guarded units (`Modules/server.nix`): `sonarr`, `radarr`, `lidarr`, `jellyfin`, the three
`*-rootfolders`, `jellyfin-libraries`, `podman-{audiobookshelf,shelfarr,filebrowser}`,
`immich-server`, and critically **`sonarr-missing-search` / `radarr-missing-search`** — those two
would otherwise see an empty `/data/media`, conclude the whole library was missing, and trigger a
mass re-download of everything.

Net effect of a missing disk now: the box boots, stays reachable, and the media services refuse to
start — diagnosable remotely instead of needing hands on the machine.

---

## Data Layout

**NVMe** (`nvme0n1`): ESP (`/boot`) + root (`/`). Fast storage for OS + downloads.
**HDD1** (8TB, partlabel `disk-hdd-data`): `/mnt/disk1` — mergerfs branch + photos + arr state.
**HDD2** (12TB, partlabel `disk-hdd2-data`): `/mnt/disk2` — mergerfs branch.
Disko partitioning declared inline in `Hosts/Asgard/system.nix`. **Never reference `/dev/sdX`** —
the letters shuffle between boots.

```
/data/                       # plain dir on the NVMe root, NOT a mountpoint
  media/                     # ← mergerfs pool of /mnt/disk{1,2}/media (~19 TB)
    tv/        movies/        music/        books/        audiobooks/
  photos/                    # ← bind mount of /mnt/disk1/photos (Immich)
  .state/services/           # ← bind mount of /mnt/disk1/.state (nixflix state, arr SQLite)

/downloads/                  # On NVMe for fast SABnzbd unpacking
  usenet/
    complete/
      sonarr/  radarr/  lidarr/

/var/lib/
  filebrowser/               # File Browser state
  grafana/data/              # Grafana DB + state
```

---

## Shared Media Group

GID 1001. All services that need `/data/media` access are in this group:
- `users.groups.media = { gid = 1001; }`
- rock user, jellyfin user, readarr user
- Containers use `PGID=1001`

---

## Fresh Deploy Checklist

1. Populate sops secrets: `sops ~/Dots/Secrets/secrets.yaml`
2. Install NixOS: `nixos-install --flake .#rock-Asgard` (nixos-anywhere had issues, manual install worked)
3. Set partition labels to match disko: `disk-nvme-ESP`, `disk-nvme-root`, `disk-hdd-data`
4. On first boot:
   - Join Tailscale: `sudo tailscale up` on Asgard (stock Tailscale, no Headscale)
   - Immich admin account is auto-created by `immich-admin-seed.service`
   - FileBrowser credentials auto-synced from sops by `filebrowser-credentials.service`
   - Jellyfin branding CSS (hides seek-bar chapter tick marks; lives in Jellyfin state, not Nix):
     `curl -X POST http://localhost:8096/System/Configuration/branding -H "Authorization: MediaBrowser Token=$(sudo cat /run/secrets/jellyfin-api-key)" -H "Content-Type: application/json" -d '{"LoginDisclaimer":"","CustomCss":".sliderMarker { display: none !important; }","SplashscreenEnabled":false}'`
5. Everything else (arr wiring, Jellyseerr setup, Glance dashboard, Grafana) is automatic

---

## Cloudflare Tunnel Setup (one-time)

```bash
cloudflared login                          # authenticate (creates ~/.cloudflared/cert.pem)
cloudflared tunnel create asgard          # creates credentials JSON
# Copy the credentials JSON into sops as cloudflare-tunnel
# DNS records auto-created by: cloudflared tunnel route dns <uuid> <hostname>
```

Public routes: jellyfin.bifrost-vault.com, requests.bifrost-vault.com, photos.bifrost-vault.com

---

## Mullvad VPN for SABnzbd — Working

SABnzbd is now fully confined to a WireGuard network namespace. See the "Mullvad VPN Namespace" subsection under Stack Architecture for service details. Private key in sops: `mullvad-wg-private-key`. `/etc/hosts` entries for FrugalUsenet and Newshosting server IPs are used for DNS inside the namespace.
