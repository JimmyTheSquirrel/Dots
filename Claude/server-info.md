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
- Glance dashboard (port 8888) — native `server-stats` widget + "System Info" custom-api (auto-refreshing via injected JS), service monitors, bookmarks, Yggdrasil Network widget
- FileBrowser, Immich, Audiobookshelf, Shelfarr — running
- Decluttarr — running, config auto-generated from individual arr/sabnzbd API key secrets
- Recyclarr — runs on boot + daily, syncs TRaSH Guides quality profiles to Sonarr + Radarr
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
| **Glance**         | 8888 | Tailscale only | Main dashboard (native systemd service, not container). Native server-stats + auto-refreshing System Info widget + Yggdrasil Network widget |
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
- **Recyclarr** — `recyclarr-config.service` generates `/var/lib/recyclarr/recyclarr.yml` with API keys from sops. `recyclarr-sync.service` runs via a systemd timer (5min after boot, then daily). Profiles: Sonarr WEB-1080p + WEB-2160p, Radarr Remux-1080p + Remux-2160p (best quality first, works down). Check with `journalctl -u recyclarr-sync`. Radarr templates use `radarr-quality-profile-remux-*` / `radarr-custom-formats-remux-*` (no `-v9-` prefix — that naming was dropped from TRaSH Guides).

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

## Observability Stack

### Architecture
```
journald (all units) → Alloy → Loki (3100)
node_exporter / cAdvisor / Exportarr / SABnzbd exporter → Prometheus (9090)
Glance (8888) — reads Prometheus via custom-api widgets
Grafana (3001) — reads Loki + Prometheus, provisioned datasources
```

### Glance Dashboard (port 8888)
3-column layout: **Bookmarks** (left, small) | **System stats + Service monitors** (center, full) | **Clock + Network** (right, small)

**Page 1 — Asgard (main):**

Left column (small): Bookmarks grouped by Watch & Browse / Downloads / Arr Stack / Management

Center column (full):
- Native `server-stats` widget: CPU/RAM/Disk bars, `/data` mountpoint shown, others hidden
- "System Info" `custom-api` widget: Disk /data GB free, Download Mbps, Upload Mbps — queries Prometheus with combined PromQL (`node_filesystem_free_bytes` + `rate(node_network_*_bytes_total{device=~"enp.*|wlp.*"}[15s])`). Auto-refreshed every 5s via injected JavaScript in `document.head` that polls Prometheus directly (requires CORS enabled on Prometheus)
- Service monitor groups: Downloads (SABnzbd, Prowlarr), Arr Stack (Sonarr, Radarr, Lidarr, Shelfarr), Media (Jellyfin, Jellyseerr, Immich, Audiobookshelf), Management (FileBrowser, Prometheus, Loki, Grafana)

Right column (small):
- Clock widget (12h format)
- Yggdrasil tree banner (split CSS: Norse rune ring SVG as `::before`, tree PNG as `::after` via `/assets/yggdrasil.png` from `glanceAssets` derivation + `assets-path`)
- Yggdrasil Network `custom-api` widget: queries `tailscale-status-proxy` (port 9553) which reads tailscaled Unix socket, 15s cache, shows device names + online/offline dots + IPs.

**Custom CSS (injected via `document.head` `<style>`):**
- Widget borders: subtle green-tinted rounded corners, hover glow effect
- Yggdrasil banner: ring SVG as `::before` data URI, tree PNG as `::after` via `/assets/yggdrasil.png`
- Active page tab + clock text glow
- Widget title letter-spacing

**Page 2 — Downloads:**
- SABnzbd iframe: `type: iframe`, `source: http://asgard:8080`, `height: 700`
- SABnzbd auth removed — iframe loads without login (tailnet-only access)
- UI prefs (compact/fullscreen/tabbed) set server-side via `web_compact/web_fullscreen/web_tabbed = true`, but iframe needs "Use global interface settings" ticked within its own browser context

**Theme:** `positive-color: hsl(142, 72%, 39%)` (green ticks for online), `negative-color: hsl(0, 84%, 60%)`

**Icons:** Use `sh:` prefix (selfh.st colored icons). For apps not in selfh.st, use direct CDN URLs. Avoid `si:` — monochrome.

**SABnzbd iframe requirements:** `x_frame_options = 0` in nixflix SABnzbd misc settings. Dark mode: `web_color = "Night"` (NOT "Dark").

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
- `seerr-radarr-profile.service` + timer — sets Radarr default quality profile to "Remux + WEB 1080p" in Jellyseerr
- `seerr-sonarr-profile.service` + timer — sets Sonarr default quality profile to "WEB-1080p" in Jellyseerr
- Both run after `seerr-setup.service`, have `Restart = on-failure` + `RestartSec = 30` for boot timing
- Uses Jellyseerr session cookie auth (not API key) — logs in then PUTs to `/api/v1/settings/radarr/0` / `/api/v1/settings/sonarr/0`

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

All service monitoring is now done via Glance native `server-stats` widget + auto-refreshing "System Info" custom-api widget (Prometheus-backed).

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

## Data Layout

**NVMe** (`/dev/nvme0n1`): ESP (`/boot`) + root (`/`). Fast storage for OS + downloads.
**HDD** (`/dev/sda`): `/data` (8TB ext4). All media, photos, and service state.
Disko partitioning declared inline in `Hosts/Asgard/system.nix`.

```
/data/
  media/
    tv/        movies/        music/        books/
  photos/                    # Immich
  .state/services/           # nixflix state (arr configs, API keys)

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
