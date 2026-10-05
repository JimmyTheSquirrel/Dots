# Asgard — Media Server Reference

## Overview

Asgard is a NixOS media server running on dedicated hardware (Intel i5-14400, 1TB NVMe, 8TB + 12TB HDDs pooled by mergerfs).
Configuration lives in `Modules/Server/` — one NixOS module (`flake.nixosModules.server`) split
by area, every file defining that same module and flake-parts merging them. Host in
`Hosts/Asgard/system.nix` (+ `_hardware.nix`, `_disko.nix`).

| File | What |
|------|------|
| `default.nix` | the **only** nixflix import, `options.asgard` (tailnet IP/FQDN, LAN NIC, veth IPs — the shared facts), podman, firewall, media group, shared admin secrets, sysctls, system packages |
| `storage.nix` | mergerfs pool, bind mounts, `RequiresMountsFor` guards, every tmpfiles rule |
| `arr.nix` | Sonarr/Radarr/Lidarr/Prowlarr (nixflix), missing-search timers, `arr-policy` |
| `recyclarr.nix` | Recyclarr config + sync, and the Seerr-after-sync ordering |
| `jellyfin.nix` | Jellyfin + Jellyseerr (nixflix), `seerr-library-setup`, `jellyfin-providers`, QSV graphics |
| `downloads.nix` | SABnzbd (nixflix) + the Mullvad namespace, Decluttarr |
| `books.nix` / `manga.nix` / `photos.nix` / `files.nix` | ABS + Shelfarr + `books-setup` / Suwayomi + FlareSolverr / Immich / FileBrowser |
| `network.nix` | Tailscale, status proxy, speed test, network panel, Cloudflare tunnel, WAN shaping |
| `eclipse.nix` / `glance.nix` / `ttyd.nix` | Eclipse control endpoint / the whole Glance config + unit / web terminal |
| `_lib.nix` | `waitForHttp` — imported by path (the `_` keeps import-tree off it) |
| `home-assistant.nix`, `marsbar.nix` | separate modules, separate docs |

Until 2026-10-03 all of it was one ~5,000-line `server.nix`; the split was a pure move — the system
derivation was byte-identical before and after. **Gotcha found doing it:** a *list* option defined
in several of these files concatenates in the order the files are merged (reverse-alphabetical
here), not reading order — splitting `environment.systemPackages` across three files reordered
`system-path`. Keep a list option in one file when its order matters.

Everything is declarative. A fresh deploy needs only the sops secrets populated before building.

---

## Fans and sensors (added 2026-09-19)

Board is a **Gigabyte B760M H DDR4** — 1× CPU_FAN + 2× SYS_FAN, in a **Jonsbo N5** case.

⚠️ **The N5's drive-cage fans are physically uncontrollable where the case puts them.** They hang
off the case backplane on raw 12V from a Molex power port — **no PWM wire, no tach wire**. No
driver can ever see or control them; they run 100% forever, and fitting quieter fans only lowers
the noise floor of a full-speed fan. The only fix is moving them onto a motherboard SYS_FAN header
(a Y-splitter works; the header does 24W and two 120mm fans draw ~2–3W). Detection ≠ control —
making Linux read drive temps does nothing if there is no channel to act on them.

### Getting Linux to see the fans at all

Config lives in `Hosts/Asgard/_hardware.nix`. Without it the box reports **zero** fans — hwmon shows
only temperatures and not one `fan*_input` or `pwm*`, not even the CPU fan. Two separate blockers,
and **both** must be handled or the fix silently no-ops:

1. The **in-tree `it87` does not support the IT8689E** on this board. It fails `No such device`
   *even with the resource conflict bypassed* — so the widely-cited
   `acpi_enforce_resources=lax` fix **alone is not sufficient**. Only the out-of-tree driver works
   (`it87: Found IT8689E chip at 0xa40, revision 2`).
2. ACPI claims the region (`/proc/ioports: 0a40-0a4f : pnp 00:00`), so even the working driver is
   refused `Device or resource busy`.

⚠️ **`boot.extraModulePackages` is not enough.** Both copies land in the merged module tree and
depmod registers only `it87.ko.xz` (in-tree), so `modprobe it87` loads the **broken** one. Check
with `modprobe --show-depends it87`. Hence: `boot.blacklistedKernelModules = [ "it87" ]` plus a
systemd oneshot that `insmod`s the out-of-tree `.ko` **by absolute path** with
`ignore_resource_conflict=1` — chosen over the global `acpi_enforce_resources=lax` kernel param
because it is scoped to one driver and **needs no reboot**.

⚠️ **`insmod` does not resolve dependencies** — `it87` needs `hwmon_vid`, so the unit has
`ExecStartPre = modprobe hwmon_vid`. Without it the unit dies `Unknown symbol in module` **only on
a cold boot**: after a `nixos-rebuild switch` hwmon_vid is already resident, so the bug hides until
the machine actually reboots. Test module units by `rmmod`-ing the whole dependency chain, not just
the module.

**Monitoring only.** BIOS Smart Fan 6 drives the curves (`pwm*_enable=2`). Do **not** also enable
`fancontrol` — two controllers on the same PWM registers makes fans oscillate. The curves
themselves are BIOS state this repo cannot reproduce; see `Claude/next-up.md` item 6.

`lm_sensors` and `smartmontools` are installed here too — `smartctl` was missing entirely, so drive
temperatures could not be read at all.

---

## Current Status (as of 2026-06-25)

### Deployed on dedicated Asgard hardware
- Nixflix arr stack (Sonarr/Radarr/Lidarr/Prowlarr) — Forms auth via `hostConfig.password._secret` → `admin-password`
- Jellyfin, Jellyseerr, SABnzbd — all healthy
- Prowlarr — 3 indexers pre-configured (Miatrix, NZBgeek, NzbPlanet) via sops secrets, app sync configured to push to all arrs
- SABnzbd — FrugalUsenet (primary) + Newshosting (backup), dual Usenet backbone, running inside Mullvad VPN namespace with kill switch
- Glance dashboard (port 8888) — every card live (pushed): Asgard / Storage / Now Playing / Downloads, network + speed test, Eclipse panel, Power (lights, 24 h chart, devices), tabbed service monitors, Yggdrasil Network — see *Dashboard — Glance*
- FileBrowser, Immich, Audiobookshelf, Shelfarr — running
- Decluttarr — running, config auto-generated from individual arr/sabnzbd API key secrets
- Recyclarr — runs on boot + daily. **Only four quality profiles exist** (2026-08-23): "Asgard - Movies" (Radarr), "Asgard - TV" / "Asgard TV - 1080p" / "Asgard - Anime" (Sonarr). All TRaSH stock profiles were deleted so Jellyseerr shows a short list
- `arr-policy.service` — applies what recyclarr cannot: series→profile mapping, `seriesType`, release profiles, Radarr collection repointing, profile deletion, Jellyfin per-user audio settings
- **Tailscale** — stock Tailscale (free plan), tailnet `tailb54b82.ts.net`. Asgard (100.126.205.100), Sisyphus (100.70.29.3), rhys-s25 (100.68.29.23)
- **Networking** — stock Tailscale, `tailscale0` trusted in firewall, all services reachable via `asgard:port` from tailnet devices
- **Mullvad VPN** — SABnzbd confined to WireGuard network namespace (`/var/run/netns/vpn`), Mullvad Sydney exit, socat proxy host:8080 → namespace
- **asgard-stats** — `Resources/Asgard-Stats/asgard-stats.py` (port 9552, Tailscale only), unit in `Modules/Server/stats.nix`. Pushes host stats over SSE every 2 s for the dashboard's Asgard, Storage and Now Playing cards. Its root companion `asgard-smart.timer` (every 5 min) runs `smartctl -n standby,3 -i -H -A -l selftest` per disk into `/var/lib/asgard-smart/smart.json` (temp, health, identity, wear counters, last self-test, kernel name) — **never wakes a sleeping drive**; an asleep one keeps its last-known details
- **tailscale-status-proxy** — `Resources/Glance/tailscale-status.py` (port 9553, loopback) reads tailscaled's LocalAPI over its Unix socket and serves the Yggdrasil widget a sorted device list (MagicDNS names, online/offline, last seen, direct/relay)
- **No metrics/log stack** — Prometheus, the exporters (node, Exportarr ×4, SABnzbd), cAdvisor, Loki, Alloy and Grafana were all **removed 2026-10-03** — unused. asgard-stats covers host CPU/RAM/temps/disks, its Downloads widgets ask SABnzbd's API directly, and logs are `journalctl -u <unit>`. Kavita, Komga and the tailnet NFS export of `/data/media` (the Eclipse "Native mode" trial) went in the same pass

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
| **Suwayomi**       | 4567 | Tailscale only | Manga server (native NixOS service). **Package pinned to 2.3.x on purpose — nixpkgs' 2.1 finds ZERO sources.** See *Manga* below |
| ~~Homepage~~       | ~~3000~~ | — | Removed — replaced by Glance |
| File Browser       | 8081 | Tailscale only | Quantum fork. Credentials synced from sops |
| asgard-stats       | 9552 | Tailscale only | `GET /stream` (SSE: 3 min of CPU/memory history on connect, then a snapshot every 2 s), `GET /snapshot`. Read-only: no verbs. CPU per thread, temps, fans, memory, every disk + the pool (`ismount`-checked, fs type, inodes), per-drive read/write rate (`/proc/diskstats`), SMART + drive identity/wear/self-test from `asgard-smart`; Jellyfin now-playing and SABnzbd queue/history only while a dashboard is connected. CORS only for `_origins.nix` |
| tailscale-status-proxy | 9553 | **loopback only** | `GET /status` — the tailnet device list behind Glance's Yggdrasil widget (read server-side by Glance; no CORS) |
| **Glance**         | 8888 | Tailscale only | Main dashboard (native systemd service, not container). Pages Asgard / Eclipse / Power / Terminal — see *Dashboard — Glance* |
| network-panel      | 9555 | Tailscale only | `GET /events` (SSE: LAN + tailnet throughput every second, latency, speed tests + history summary), `GET /api` (snapshot), `GET /history[?day=]`, `GET /history.csv`, `POST /run` and `POST /history/clear` (need `X-Dash: 1`). Backs the Network card on both dashboards; CORS only for `_origins.nix` |
| eclipse-control    | 9554 | Tailscale only | Eclipse TV box API — `GET /events` (SSE: status, TV now-playing, Wolf streams, shared activity, busy), `GET /status`, `/act/<name>` verbs (incl. `reboot`) and `/wolf/stop/<id>` (POSTs need `X-Dash: 1`). Both dashboards draw the same panel from it. **Deliberately off the LAN**; that is why the LAN speed test needed 9557 |
| eclipse speedtest sink | 9557 | **LAN + Tailscale** | Zero-filled payload only, no control surface. Opened via `networking.firewall.interfaces."enp3s0"` so the Pi can measure LAN throughput. Safe to expose *because* it has no verbs |
| **glance-marsbar** | 8890 | **loopback only** | Partner dashboard. Reachable solely via the `marsbar` tailnet node's serve proxy — see `Claude/marsbar.md` |
| ha-bridge          | 9556 | Tailscale only | Holds the HA token server-side. `GET /events` (SSE push of every plug relay + its power, V, A, kWh today, signal, online), `GET /states` (snapshot, from memory), `GET /history` (24 h of power per plug, 10-min buckets), `POST /toggle/<entity>` (needs `X-Dash: 1`) against a hard allowlist — see `Claude/home-assistant.md` |
| **ttyd**           | 7681 | Tailscale only | Web terminal (Glance "Terminal" page). Login prompt (root `login` entrypoint) — log in as `rock`, passwordless sudo for reboot/shutdown |
| FlareSolverr       | 8191 | Tailscale only | Podman container — Cloudflare challenge solver for Suwayomi + Shelfarr |
| Home Assistant     | 8123 | Tailscale only | Smart plugs — see `Claude/home-assistant.md` |

Nothing listens on 3001 / 3100 / 9090 / 9100 / 9101 / 9387 / 9708–9711 (the removed metrics
stack), 5000 (Kavita), 25600 (Komga) or 2049/111 (NFS) any more.

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
- **WAN egress shaping** — `wan-egress-shaping.service` (in `Modules/Server/network.nix`) caps WAN-bound upload on enp3s0 at 30 Mbit via HTB + fq_codel. Home uplink is 50 Mbit; Jellyfin transcode segments burst at full line rate every ~3s, spiking latency ~180ms and rubber-banding LAN game sessions. RFC1918 destinations bypass the cap (LAN direct-play unaffected). Inspect with `tc -s qdisc show dev enp3s0`.

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
  they only cluttered Jellyseerr's dropdown. Jellyseerr's defaults are set **by name** through
  `nixflix.seerr.{radarr,sonarr}` — see *Jellyseerr default profiles* under Nixflix Notes.

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
     the sync never even started. Renamed to `RECYCLARR_CONFIG_DIR` (now in `Modules/Server/recyclarr.nix`).
  2. **Fixed:** TRaSH's config-templates repo dropped `includes.json` entirely and renamed every
     template, so `include: - template: …` resolves **nothing** — there are no include templates
     any more, and all 10 ids the config used were dead. The replacements are *whole-config*
     templates (`radarr-remux-web-1080p`, `radarr-remux-web-2160p`, sonarr `web-1080p`,
     `web-2160p`) which **cannot be used with `include:` at all**. Their contents are now inlined
     in `Modules/Server/recyclarr.nix` by `trash_id` — trash_ids are stable content hashes, whereas template
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

  #### ✅ The two clones were RECONCILED on 2026-09-16 — check before assuming divergence

  **This used to say "the Sisyphus copy is materially WRONG, edit on Asgard only". That is no
  longer true and following it would now be the mistake.** Asgard's 878 lines of uncommitted work
  were committed (`30c3ac6`, `b985c36`, `f83c52f`), pushed to `origin/main`, and merged into
  Sisyphus's `steam-ricing`. `server.nix` (as it was then) was **byte-identical on both clones**
  (3786 lines). Editing either copy and patching across works again.

  **How the divergence happened, so it can be avoided:** server work is done directly on Asgard,
  whose clone builds from `~/Dots` on `main`. Sisyphus cut `steam-ricing` from `ac62333`, *before*
  Asgard's `db72868`/`dc228c8` landed, so its `server.nix` sat ~1400 lines behind while looking
  perfectly valid. **Nothing warns you** — it builds fine, it is just the wrong config.

  ✅ **This whole class of problem was removed on 2026-10-05: Asgard's `~/Dots` is deleted.**
  Every machine is deployed from Sisyphus, this repo is the only checkout in existence, and the
  `H_MODE=managed` mode (*Pull & switch* / *Switch there* / *Push ours…*) is gone from
  `system-rebuild` — see `Claude/deploy.md`. The convergence hash-check that used to live here,
  the `git remote add asgard asgard:Dots` push dance, and the note about Asgard's invalid
  `Rock <Rock>` git identity are all obsolete: there is nothing on Asgard to diverge, commit or
  push from. Deploy with `system-rebuild rock Asgard`.

  Radarr's live profile is **`Asgard - Movies`** (id 9). The history above is kept because the
  failure mode is instructive, not because it can recur — see `memory/asgard-clone-diverged.md`.

  #### Dolby Vision Profile 5 blocked (2026-09-08)

  `Asgard - Movies` scored audio heavily (`TrueHD ATMOS` +5000) but had **no video-range custom
  formats at all**. Given two releases from the same group off the same WEB source — identical
  except one carried Dolby Vision — nothing could tell them apart, so it grabbed the DV one. That is
  **Profile 5**, which plays *green* on Eclipse (see `Claude/eclipse.md`).

  Fixed by adding to the existing `-10000` block in the recyclarr config (`recyclarr.nix`):

  ```yaml
  - 923b6abef9b17f937fab56cfcf89e1f1  # DV (w/o HDR fallback)
  ```

  The CF matches `Dolby Vision AND WEBDL AND NOT HDR` — exactly P5. Releases named `DV.HDR`
  (Profile 8.1) carry an HDR10 base layer, direct-play correctly, and are deliberately **not** hit.

  **Verified against a live search** rather than assumed — the discrimination is what matters:

  | Release | Score before | after |
  |---|---|---|
  | `…Atmos.**DV**.H.265-SasukeducK` (green) | +5005 | **−4995** |
  | `…Atmos.H.265-SasukeducK` (non-DV twin) | +5005 | +5005 |
  | `…DDP5.1.**DV.HDR**…-WKS` (P8.1) | +1750 | +1750 |

  A 10,000-point swing on the only pair that was ambiguous.

  **Never reuse a remembered DV trash_id.** `58d6a88f13e2db7f5059c41047876f00` is stale — TRaSH
  restructured these into `dv-wo-hdr-fallback.json` / `dv-disk.json` / `dv-boost.json`. Fetch the id:

  ```bash
  curl -s https://raw.githubusercontent.com/TRaSH-Guides/Guides/master/docs/json/radarr/cf/dv-wo-hdr-fallback.json
  ```

  `recyclarr list custom-formats radarr` prints **ids only, no names** — it cannot be grepped for a
  format by name. Go to the Guides JSON instead.

  **Deliberately not done: no library-wide HDR penalty.** Eclipse cannot display HDR, but Ben's
  Chrome, the LG TV, the Android TV and the phones all can, and Jellyfin tone-maps for those that
  cannot. Fixing one weak client by degrading acquisition for everyone is the wrong layer.

### Mullvad VPN Namespace (SABnzbd)
- `netns-vpn.service` — creates `/var/run/netns/vpn`
- `wg-mullvad.service` — WireGuard interface inside vpn namespace, Mullvad Sydney endpoint (146.70.200.2:51820)
- `veth-vpn.service` — veth pair bridging host ↔ vpn namespace (10.200.1.1/24 ↔ 10.200.1.2/24)
- SABnzbd: `NetworkNamespacePath = "/var/run/netns/vpn"`, `bindsTo = wg-mullvad.service` (kill switch)
- `sabnzbd-proxy.service` — socat TCP proxy, host 0.0.0.0:8080 → 10.200.1.2:8080
- DNS: Mullvad 10.64.0.1 via bind-mounted resolv.conf + `/etc/hosts` for Usenet server IPs
- VPN IP: 10.66.10.54, private key in sops: `mullvad-wg-private-key`

### Podman containers
- Audiobookshelf, Shelfarr, FlareSolverr, File Browser Quantum, Decluttarr
- Backend: `virtualisation.oci-containers.backend = "podman"`. No Docker-compat socket — its only
  consumer was cAdvisor, and it is root-equivalent for the `podman` group
- **Decluttarr:** `decluttarr-config.service` generates `/var/lib/decluttarr/config/config.yaml` from individual arr + sabnzbd sops secrets before the container starts. No separate `decluttarr-env` secret — reuses existing API key secrets directly. `remove_orphans: false` — do NOT enable this, it kills newly queued downloads before SABnzbd picks them up (within 2 minutes).
- **Glance is NOT a container** — it runs as a native systemd service (`pkgs.glance`). Config built as a Nix attrset and serialised by `pkgs.formats.yaml` into the store. Uses `DynamicUser = true`.

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

Ordered **after** nixflix's `seerr-sonarr` / `seerr-radarr` on purpose — Jellyseerr pointed at the
stock "Any" profile, which this service deletes. Repoint first, then delete. (It used to be ordered
after the hand-written `seerr-*-profile` units, which only a timer ever started — so at boot that
ordering did nothing.)

**Best-effort by design, and now explicitly so.** The script runs under `set +e`: NixOS prepends
`set -e` to every unit `script`, which had silently turned "log FAILED and carry on" into "abort at
the first unguarded failed curl". It still fails loudly if Sonarr never answers at all.
`jellyfin-providers` is the same. `books-setup` is the opposite — deliberately fail-fast, because each
step feeds the next and `Restart=on-failure` (5 tries / 30 min) turns an early exit into a retry.

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

## Books — Audiobookshelf + Shelfarr, wired by `books-setup.service`

**Shelfarr (`:5056`) is the Jellyseerr-for-books**: search a title, request it, Prowlarr
finds it, SABnzbd fetches it, Audiobookshelf (`:13378`) serves it.

### It had never worked — and looked perfectly healthy

Until **2026-09-17** this whole pipeline was dead. Shelfarr had run since June 2026 with
`0 acquisition_providers` and `0 download_clients`, and **Audiobookshelf had never been
initialised at all** — `isInit: false`, no root user, no libraries. `/data/media/books`
was empty. Both containers were `active`, both answered HTTP, both showed green on Glance.

The cause was the "Post-boot (one-time)" comment in the old `server.nix` telling you to
click through two web UIs. Nobody ever did. **A running container is not a working
pipeline** — check what's wired *between* services, not whether each one is up.

### `books-setup.service` now does it declaratively

Idempotent, runs every rebuild, converges a fresh install:

1. Audiobookshelf — `POST /init` to create the root user from sops `admin-username`/`admin-password`
2. Audiobookshelf — create the **Ebooks** (`/ebooks`) and **Audiobooks** (`/audiobooks`) libraries, keyed by name so re-runs don't duplicate
3. Audiobookshelf — mint an API key for Shelfarr
4. Shelfarr — set the indexer, download client and ABS connection from sops secrets

### ⚠️ Four traps, all of which fail silently

**1. Shelfarr config MUST go through `bin/rails runner`, never `sqlite3`.**
`AcquisitionProvider` and `DownloadClient` both declare `encrypts :api_key`. A raw SQL
insert writes the key in **plaintext** and Rails throws on decrypt later. `sqlite3` is
present in the container, which makes the wrong approach look available.

**2. `bin/rails` will not boot without two generated secrets.** Both live in the storage
volume and are created by the container entrypoint on first run:

```bash
podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; \
  export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); \
  cd /rails && ./bin/rails runner "..."'
```

Without them you get `KeyError: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, then
`Missing secret_key_base`. Neither is in sops — they're per-install volume state.

**3. Prowlarr is NOT an `AcquisitionProvider`.** That model is for *custom* direct-download
providers; its `test_connection` returns **false** for a Prowlarr URL. Prowlarr is
configured through `Setting` rows instead — `indexer_provider`, `prowlarr_url`,
`prowlarr_api_key`. Using the wrong model gives you a config that looks populated and
finds nothing.

**4. Containers cannot reach host services on `localhost`.** Use
**`http://host.containers.internal:<port>`** — verified working for 9696, 8080 and 13378.

### Verifying it

```bash
sudo podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "
  puts %(indexer=#{IndexerClient.provider} ok=#{IndexerClient.test_connection})
  puts %(results=#{Array(IndexerClient.search(%q(Project Hail Mary))).size})"'
```

Verified 2026-09-17: `indexer=prowlarr ok=true`, SABnzbd `true`, search returned **14
results**. Note `IndexerClient.search` is a **class** method and takes no `media_type:`
keyword — calling it on an instance raises `NoMethodError`.

**Not yet proven end-to-end:** no request has actually completed a download into
`/data/media/books`. The SAB category (`books`) and the post-processing hand-off to ABS are
configured but untested.

---

## Manga — Suwayomi (port 4567)

Headless Tachiyomi/Mihon server. Tracks ongoing series from web sources and
auto-downloads new chapters; Mihon on the phone/tablet reads from it over the tailnet.

Native `services.suwayomi-server`, **not** a container — so everything except the
per-library source/series picks is declarative. Those live in Suwayomi's own DB and are
genuine UI state, like noctalia's `settings.toml`.

### Two paths on purpose

```
dataDir        /var/lib/suwayomi-server   H2 database + config   (NVMe)
downloadsPath  /data/media/manga          the chapters           (mergerfs pool)
```

The database must **not** sit on `/data/media`. That is mergerfs/FUSE, and SQLite-on-FUSE
is the same locking-corruption trap this repo already dodges for the arrs via the
`/data/.state` bind mount. Only media goes on the pool. `suwayomi-server` also carries
`RequiresMountsFor = /data/media`, without which a boot with the pool missing would
re-download the entire library onto the NVMe root.

### ⚠️ Three traps, each of which fails SILENTLY

**1. nixpkgs' version is unusable — the pin is load-bearing.**
nixpkgs ships **2.1.1867** (Jul 2025), which only understands the legacy flat
`index.min.json` repo format. Keiyoushi — effectively the only source repo that matters —
migrated to the Mihon 0.20.1+ manifest (`index.pb`, protobuf) and now serves the old path
as a **two-entry deprecation stub**: `"Outdated App"` and `"Update to Mihon 0.20.1+"`.

On 2.1 the unit is `active`, the port answers HTTP 200, the web UI loads — and there are
**zero real sources**. Confirmed live, not inferred:

```bash
curl -s http://localhost:4567/api/v1/extension/list   # 2.1 → exactly 2 stub entries
```

`manga.nix` therefore pins **2.3.2243** via `overrideAttrs`. Jar sha256 `821141b3…` was
cross-checked against upstream's published `Checksums.sha256`. Drop the override only once
nixpkgs ships ≥ 2.3 — and read trap 2 when you do.

**2. The config key was renamed in that same jump.** `server.extensionRepos` (2.1) →
**`server.extensionStores`** (2.3). `server.conf` is HOCON and **unknown keys are silently
ignored**, so the old name costs you a debugging round with no error anywhere. The NixOS
module still declares the *old* option (it targets 2.1), so that key is emitted too, as a
harmless empty list.

**3. Two upstream defaults each disable auto-download for exactly the series you want.**

| key | upstream default | set to | why |
|---|---|---|---|
| `excludeEntryWithUnreadChapters` | `true` | `false` | skips auto-download for any entry with an unread chapter — i.e. every ongoing series |
| `excludeNotStarted` | `true` | `false` | a series you added but haven't opened counts as "not started" and is never updated |
| `excludeUnreadChapters` | `true` | `false` | same problem for anything with a backlog |
| `excludeCompleted` | `true` | `true` | kept — finished series genuinely have nothing to fetch |

Left at defaults, `autoDownloadNewChapters = true` does almost nothing.

### Other settings worth knowing

- `port = 4567` — Suwayomi's own default. **The NixOS module defaults to 8080**, which on
  this box is SABnzbd's socat proxy. Leaving it at the module default collides with a live
  service.
- `downloadAsCbz = true` — keeps files portable; Mihon, Komga, Kavita and plain readers all
  open CBZ. The default (loose images in a folder) does not travel.
- `globalUpdateInterval = 6` — hours; 6 is the minimum the server accepts.
- `openFirewall = false` — `tailscale0` is already in `trustedInterfaces`.

### FlareSolverr (`:8191`) — deployed, but not the fix you'd expect

Headless-Chrome proxy that clears Cloudflare interstitials. Added 2026-09-17, shared by
Suwayomi (`http://localhost:8191` — native host service) and Shelfarr
(`http://host.containers.internal:8191` — container). Prowlarr could also use it as an
indexer proxy; that is **not** configured.

**It works.** Verified directly:

```bash
curl -s -X POST http://localhost:8191/v1 -H 'Content-Type: application/json' \
  -d '{"cmd":"request.get","url":"https://comick.io/","maxTimeout":60000}'
# → {"status":"ok","message":"Challenge not detected!", ...}  6.4 MB of HTML
```

**But Comick and Manganato still fail in Suwayomi.** Their error moved from
*"Cloudflare bypass currently disabled"* to plain **HTTP 403** — i.e. FlareSolverr *is*
engaged and those extensions are broken for their own reasons. `comick.io` now redirects to
`comick.dev`, and Manganato's domain has churned repeatedly. **Treat those two as stale
extensions, not a Cloudflare problem — do not re-debug FlareSolverr for them.** MangaDex
and MangaFire both work.

### Repo URL

```
https://github.com/keiyoushi/extensions/raw/repo/index.pb
```

The legacy `…/repo/index.min.json` also resolves on 2.3 — it reads `repo.json` and follows
its `index_v2` pointer to the same file — but pointing straight at the real index skips a
redirect that exists only for old clients.

---

## Dashboard — Glance

There is no metrics or log pipeline any more (see *Current Status*). Glance reads everything
live: host stats from asgard-stats on `:9552`, the network panel from `:9555`, SABnzbd's queue from its own
API, power from Home Assistant, light state from ha-bridge. For logs, use `journalctl -u <unit>`.

### Glance Dashboard (port 8888)

**Pages:** Asgard · Eclipse · Power · Terminal (rebuilt 2026-10-04 — the Downloads page
was folded into a live card, Monitoring became Power and took the lights).

**Files:** `Modules/Server/glance.nix` (config + unit) · `Resources/Glance/`:
`asgard.css` (this dashboard's theme + home/Power cards), `hud.py` (the HUD's artwork and
icons — generated at build time, see The look), `theme.js` (the **UI colour picker**),
`cards.css` (the cards
**shared with MarsBar**: Eclipse panel, network card, now playing), `dash.js` (helpers every
live card uses: stream lifecycle, DOM morphing, sparklines, hover read-outs), `lights.js`
(**shared with MarsBar**), `asgard.js` (Power page), `stats.js` (home live cards), `net.js`
and `eclipse.js` (**shared with MarsBar**), `tailscale-status.py`, `yggdrasil-banner.png`.
`Modules/Server/_livecard.nix` builds the card frame both dashboards use. Plugs come from
`Modules/Server/_plugs.nix`, services from the `services` list in `glance.nix`.

#### How it is built

- **The config is a Nix attrset serialised by `pkgs.formats.yaml`**, not hand-written YAML —
  same as MarsBar. Markup is generated: light tiles and power cards from `_plugs.nix`, every
  monitor from one `services` list (`tab` = category tab). Add a service or a plug in ONE place.
  ⚠ Never `readFile`/interpolate content into an indented YAML block scalar — see
  `Claude/marsbar.md` for how that silently ends the scalar.
- **CSS and JS are real files** served from Glance's assets dir (`pkgs.linkFarm`). Linked with
  `?v=<content hash>` because Glance sends `/assets/` with a 2h `Cache-Control`;
  `custom-css-file` is stamped by Glance itself. `cards.css` is a `<link>` in `document.head`.
- **Live cards are `html` widgets**, not `custom-api`: Glance 0.8.5 emits an html widget's source
  raw (it does NOT sanitise it — the old belief that it did is why Eclipse was an iframe), so each
  carries Glance's own `.widget` markup and a skeleton, and a script paints it from a stream.
- **Glance expands `${…}` config variables as plain text over the whole file before parsing**
  (`parseConfigVariables`, 0.8.5) — comments and markup included. Only the secret below may
  appear that way.

#### Secret — via `readFileFromEnv`

`LoadCredential` copies the root-only (0400) sops secret into `glance.service`'s private
credentials dir; an env var points at the copy; Glance substitutes it at startup:

- `HA_TOKEN_FILE` — the Power widgets' `Authorization: Bearer …` header (first frame only;
  everything after comes from ha-bridge). It used to be `${secret:ha-token}` (a direct
  `/run/secrets` read), which forced the admin token to 0444. Now plain root-only 0400.

Glance **no longer holds SABnzbd's full-control API key**: the old Queue widget was its only
user, and the Downloads card reads SAB through asgard-stats instead.

⚠ Glance **refuses to start** if a variable can't be read — a missing credential takes the whole
dashboard down. A rotated token restarts `glance.service` (`restartUnits`).

#### Live, not polled

Glance renders each widget server-side **once per page load** (0.8.5 has no client-side
refresh). Everything that moves is a stream, opened only on a page that has its cards, parked
after 60 s in a hidden tab, reconnected with backoff, and watchdogged (every backend sends
something at least every 15 s, so 40 s of silence = a half-open link → reconnect):

| Cards | Script | Stream | Backend |
|---|---|---|---|
| Lights, relay states | `lights.js` | `/events` | ha-bridge :9556 |
| Power: watts, V, A, kWh today, cost today, signal, plug online, projections | `asgard.js` | lights.js's `ha:state` events | ha-bridge (watches all of them — `_plugs.nix`) |
| Power: 24 h chart | `asgard.js` | `GET /history` every 5 min | ha-bridge (2 min cache) |
| Asgard, Storage, Now Playing, Downloads | `stats.js` | `/stream` | asgard-stats :9552 |
| Network | `net.js` | `/events` | network-panel :9555 |
| Eclipse, On the TV, Streams, Activity | `eclipse.js` | `/events` | eclipse-control :9554 |

Every card **morphs** its new HTML into the DOM (dash.js — attributes and text only) rather than
swapping `innerHTML`: that is what lets rings and bars animate between ticks and keeps posters
from being re-fetched. Every browser-side URL is built from `location.hostname`, so the page
works opened as `asgard`, the FQDN or the IP (each is in `Modules/Server/_origins.nix`). Every
POST carries `X-Dash: 1`; the backends refuse a POST without it and answer CORS only for
`_origins.nix`.

**Caches** (server-side, first frame only): Lights 1s and Devices 1s (they render switch
positions) · Power 30s · Cost Outlook 5m · Plug Health 1m · Yggdrasil 1m · monitors 1m.

#### The look — the HUD (asgard.css + hud.py)

A tech/cyberpunk heads-up display on a neutral **tech-grey** ground (grey grid, grey pines
in grey mist), the same on every page — rock's mockup, 2026-10-04, after the
overgrown-forest themes, which are in git history. It ships **mint**; the **colour picker**
(below) recolours the whole HUD for whoever is looking. Only the HUD carries colour — the
ground, the glass and the text stay grey whatever is picked:
- **every card is a panel**: a chamfered neon outline (top-left and bottom-right corners
  cut) with bright corner brackets and small readout marks, over dark glass with faint
  scanlines. The outline is a 9-slice `border-image` (`--h-frame`, 56px corners, straight
  edges that **stretch**, so any card size is exact) on `.widget::after`; the glass is
  `.widget::before`, chamfered by `clip-path`. Both sit over the card's box and under its
  content (`isolation` + `z-index: -1`), so text always wins;
- each **title**: a boxed line icon, the name in **Orbitron** (`pkgs.orbitron`, served
  from Glance's assets), a small **tag** after it ("Server overview", "Media pool",
  "Uplink"…), and a rule under it that starts bright. The card's rune class (`rune-*`, one
  per card) picks its icon and tag in asgard.css; tags drop in the narrow column;
- the **host's facts** each sit beside a boxed icon (`stats.js` marks them `data-k`), the
  **gauges** wear a ring of ticks, inner tiles and controls are squared off and edged in
  the HUD's colour, buttons and section headings are in Orbitron, numbers stay JetBrains Mono;
- the **navigation** is a HUD bar of angled tabs, the current page lit solid; the logo is
  a **Yggdrasil emblem** — a symmetric tree, forking crown and spread roots with a lit
  node at every tip, in a ring (also the tab icon; the phone home-screen icon is still
  `yggdrasil.png`). rock asked for Norse over the first angular "A" (2026-10-05);
- the **Yggdrasil card** (the tailnet list) carries the full tree (`--h-ygg`, 252px): a
  trunk of six strands twisting round each other, a dome of arching branches — balanced
  in mirrored pairs, lit tips, side twigs and leaves filling the canopy, motes and an
  aura behind it — three great roots through the **three wells**, the **nine realms** as
  hexagon nodes joined like a network (Asgard at the crown, Midgard on the trunk, Hel
  below the roots), and a HUD ring banded with the **24 runes of the Elder Futhark**.
  Branches in the HUD's colour; roots, wells and runes in its second light (so a
  two-tone theme splits the tree in two);
- **the backdrop never runs out**: the ground is a grid with circuit traces (`--h-grid`),
  one 480px tile **repeated down the page** — it scrolls with the content, so a page of
  any length is covered. Misty **pines** (`--h-forest`) are pinned to the foot of the
  *screen* by a `position: fixed` layer (phones honour that; they ignore
  `background-attachment: fixed`, which is what made the old full-page backdrop "cut
  off"). A vignette and scanlines over the backdrop; nothing animates.

**How it is made — `Resources/Glance/hud.py`.** A seeded generator, run by Nix **at build
time** (`hud` in `glance.nix`, a `runCommand` linked into the assets as `hud/`), so no
generated SVG is committed: `frame.svg`, `grid.svg`, `forest.svg`, `ygg.svg`, `logo.svg`,
`tpl.js` (the coloured pieces as templates, for the picker) and `hud.css` — the URLs (with `?v=<hash of hud.py>`, so Glance's 2 h asset cache never
serves an old piece) and the **icon set** (`--ic-server`, `--ic-storage`, … `--ic-fan`:
24px line icons, used as CSS masks). To add a card: give it a rune class and map it to an
icon and a tag in asgard.css's "Accents, icons and tags". Everything is small — the frame
1.4 KB, the grid 2 KB, the pines ~80 KB, the card's tree ~90 KB, `tpl.js` ~95 KB.

**The colour picker — `Resources/Glance/theme.js`.** A swatch button at the right end of
the nav bar (on a phone: a row at the top of the ☰ menu) opens **twelve light colours** —
Mint (the default), Aqua, Sky, Periwinkle, Lavender, Orchid, Rose, Coral, Peach, Butter,
Pistachio, Frost — **six two-tone themes** — Aurora (mint + lavender), Bifröst (sky +
pink), Fjord (aqua + periwinkle), Muspel (peach + rose), Midgard (sage + wheat), Niflheim
(ice + lilac) — a **Custom** colour input, and **Reset**. rock found the first, saturated
set "a lot" and asked for lighter colours with more variation (2026-10-05). It replaces
Glance's own theme picker, which asgard.css hides (its presets fight the HUD's tokens).
- **A pick in, the whole palette out**: `--hud`, `--hud2`, `--hud-hot`, `--hud-deep`,
  `--hud-rgb`/`--hud2-rgb` and the data slots `--s1…--s6`. A pick is `#rrggbb`, or
  `#rrggbb+#rrggbb` for a two-tone theme (stored as such). One colour: the second light
  and the other series are neighbours a fair way round the wheel (hue +30, +48 and a
  paler −34). Two-tone: the second colour is the second light and the second series, the
  third sits between the two. Lightness is held in a **light band, 0.6–0.84**, and
  saturation capped at 0.9, so even a custom pick comes out soft on the glass (and a
  near-black one doesn't vanish). Everything else follows because it is written in those tokens: ⚠ **a new rule
  that colours the HUD must use `var(--hud…)` / `rgb(var(--hud-rgb) / a)` / `--s*`, never
  a literal mint** (or it stays mint under every other pick). Status colours (good / warn /
  bad) deliberately don't move.
- **The artwork** (frame, the Yggdrasil card, logo — the only SVGs with the HUD's colour in them)
  is redrawn from `tpl.js`: hud.py writes each with its colours swapped for `__A__` (mint),
  `__H__` (hot), `__B__` (teal) and `__D__` (the logo's dark), and theme.js fills them in
  as data-URIs (`--h-frame`, `--h-ygg`, the `.logo img`). Grid and pines are grey, so they
  never need it. A new coloured piece in hud.py must be added to that loop in `main()`.
- **No flash**: theme.js is a plain (not deferred) script in `<head>`, so the stored
  colour's palette is on `:root` before the first paint, and the redrawn artwork is cached
  in localStorage beside it (`asgard-hud-colour`, `asgard-hud-art`, the latter keyed to the
  HUD's build so a new hud.py redraws once). `tpl.js` is fetched only when a colour is
  picked — a browser on the default never downloads it.
- **Per browser, not per server**: the pick lives in that browser's localStorage. Nothing
  is stored on Asgard and nothing in Nix changes; the default for a fresh browser is
  `data-default` on the script tag in `glance.nix`. A private window still recolours for
  the visit.
- **MarsBar has it too** — the same file, `data-profile="marsbar"` (see
  `Claude/marsbar.md` → Her colour picker). Shared base styles for the button, panel and
  swatches are in `cards.css`, as weak as CSS allows (`:where()`, and `button:where(…)` for
  the buttons — Glance's own `button { background: none; border: 0 }` would otherwise
  blank every swatch); asgard.css restyles them into the HUD and takes the base's
  rounding back off (`border-radius: 0`; the HUD cuts corners with `clip-path`).
- **Cats** — the "Just for fun" row: a ginger-and-pink theme (`#ffb36b+#ff9ec4` through
  the normal palette) that also sets `html[data-cats]` and pulls in
  `Resources/Glance/cats.css` + `cats.js` (`data-cats` / `data-cats-js` on the script tag;
  fetched only when picked — theme.js only switches them on and off: `Cats.on()` /
  `Cats.off()`, and off takes every cat, timer and listener back out). ⚠ theme.js marks
  the `<script>` it adds with `data-cats-loaded`, not `data-cats-js` — its own tag carries
  `data-cats-js`, so checking for that would match itself and never load the cats.
  - **The cats** are inline SVG with their parts rigged (each part drawn round its own
    pivot, so cats.css can turn an ear about its base, a tail about the rump, a leg
    about the shoulder; right-hand parts are the left ones under `scale(-1 1)`). One per
    top-level card, alternating pose, side and coat (ginger, `.coat1` cream, `.coat2`
    grey, `.coat3` pink): `.cat-peek` (head and paws over the card's top edge — the head
    is clipped at the edge so it can duck behind it), `.cat-sit` (sitting on the edge,
    tail hanging down the front), `.cat-loaf` (a sleeper, tail round its paws). A
    `.cat-walk` strolls along the foot of the screen (above the phone's bottom bar —
    `--cat-floor`, from `.mobile-navigation-icons`), paw prints sit behind everything,
    the section headings get paws and the logo a cat face.
  - **Idle**: CSS keeps them blinking (each its own rhythm), a sitter's tail swishing, a
    loaf breathing. One ticker (1.1 s, only cats on screen, only in a shown tab) hands
    out "acts" — a class for as long as its animation runs: ear twitch, head tilt,
    yawn, a look round, a peeker ducking behind the card and peeking back, kneading, a
    sitter grooming (paw to mouth, then a face rub), a tail flick, a sleeper stirring or
    dreaming (paws twitching).
  - **You**: tap a cat → "mrrp?"/"meow" with a head tilt, or a purr (hearts, and a buzz
    on Android). Three taps in five seconds → it hides (a peeker ducks behind its card, a
    sitter jumps off) for 12–22 s. A sleeper stirs and mumbles. Bubbles near the top of
    the screen go to the side. With a mouse, every cat's eyes follow the pointer (the
    pupil slides across the iris) and ears perk as it comes close. **Laser pointer**: a
    double-click on the page itself (not a card or control) — the nearest cat jumps down
    and a runner in its coat chases the red dot, pouncing when it catches it; Esc, another
    double-click, the pointer leaving the window or 20 s of stillness sends it home.
  - **The dashboard** (read from the cards' own markup — no card script knows the cats
    exist): all-lights switch `off` → the Lights card's cat curls up asleep (a loaf); on →
    it wakes ("mrrp!") and is its old self (never a loaf while lit). `.ags-play` progress
    bar (On the TV, Now Playing) → a kitten sits on it with a paw on the playhead,
    batting while it plays. `#ec-main` going unreachable or rebooting → every cat
    scatters, then they come home one at a time when it's back (only on a change seen
    on the page, never as first loaded). `.ags-ring.hue-temp.warn|bad` (Asgard's CPU
    ≥ 75°) or `.ec-temp b.warn|bad` (the Pi ≥ 70°) → a cat naps on the gauge with heat
    shimmering off it (above the SoC number, never on it). A name at the top of the
    Downloads card's Recent list that the page has never shown → a cat trots across the
    card with a mouse in its mouth.
  - **Taps never get eaten**: only a cat's painted body takes one (never the tail), and
    only when `layout()` has found it covers no button/link/toggle (`.tap`) — a cat
    sitting over a light tile lets the tap through to the light.
  - Cats only ever go *into* a `.widget` or `<body>` — never inside a `Dash.paint` target,
    which would morph them away. Reduced motion: no acts, no chase, no scattering (they
    just vanish), no trotting; they still answer a tap with a word.

**The colour system** — the default the picker starts from (table and reasoning at the
top of `asgard.css`): **mint** `#3be8a8`
is the HUD itself, **teal** `#1fc8c4` its second light (`acc-mint` / `acc-teal` cards),
**lime** `#b8f04a` "the other series". Data `--s1…--s6`: mint, lime, cyan-teal, moss, pale
mint, deep emerald — one family, told apart by hue/lightness steps and, for the six plugs,
by a label on each. CPU mint, memory lime; Disk 1 mint, Disk 2 lime; download mint, upload
lime; **ping** in the weave (mint → teal, `#ag-weave` from `dash.js`). The **CPU-temperature
ring** runs teal → amber with the heat. **Status** (good `#4dffa6` / warn `#ffc247` / bad
`#ff4f5e`) is reserved and always paired with a word. ⚠ **Glance's rem is 10px** (9.4px
under 550px): nothing read is under 1.1rem.

⚠️ **Glance frames widget content itself** (`.widget-content:not(.widget-content-frameless),
.widget-content-frame` get a background, border and shadow). Styling `.widget` as a card
produces a **box inside a box** — keep the outer card and flatten the inner frame; a group's
tabs are `.widget`s too, so `.widget .widget` is reset. Find Glance's rules with
`curl <glance>/static/<hash>/css/bundle.css`.

⚠ A hidden hover read-out must be `display: none`, not `opacity: 0` — an invisible absolutely
positioned box still widens the page on a phone, which zooms the whole page out and puts the
bottom navigation off its tap targets.

#### Page 1 — Asgard

Full column: **Asgard** (CPU / memory / CPU-temp rings, facts, per-thread bars, 3-minute CPU +
memory chart) · **Storage** (pool, a segment per data disk, a row per disk with age, temperature,
spin state, SMART — it opens as an **overview** (the pool, its segments, and one chip
per drive: health dot, name, temperature, a word if anything's wrong) and **the arrow**
drops the full rows down, each of which **opens into the drive**, below; open/closed is
remembered per browser, `asgard-storage-open`) · **Network** (below) · **Service health** group (All / Media / Downloads /
Arr / Management, generated from `services`; no bookmarks column — rows are clickable).

Small column: Clock · **Now Playing** (every Jellyfin stream, poster from Jellyfin's anonymous
image endpoint on :8096) · **Downloads** (speed, queue, ETA, the current item with progress, up
next, the last few finished or failed with sizes and SAB's day/week totals; release names are
prettified — `Dune.Part.Two.2024.1080p…` → `Dune Part Two (2024)`; header links to SABnzbd) ·
**Yggdrasil Network** (the tree banner over every tailnet device, sorted by the proxy).

**A drive, opened** (stats.js; each row is a `<details>`, kept open across the 2 s repaints):
- a verdict: Healthy, or Needs attention with what is wrong;
- **Drive**: model, family, serial, firmware, capacity, type (rpm / form factor / NVMe), link speed;
- **Health**: temperature, power-on time, power cycles;
  - a spinning disk adds the failure predictors — reallocated, pending and uncorrectable
    sectors, CRC errors (cable, not disk), head loads;
  - NVMe adds its health log instead — life used, spare left, data written and read, media
    errors, unsafe shutdowns;
  - any non-zero counter is called out with a word;
- the **last self-test**, the **filesystem** (type, use, inodes), **read/write MB/s right
  now**, when it was read, and its `/dev` name.

All of it comes from `asgard-smart`, which never wakes a sleeping drive. An asleep drive keeps
what it reported when it was last awake.

**Network card** (net.js):
- LAN down/up (each on its own scale — they differ by an order of magnitude);
- the tailnet's share (tailscale0);
- latency to the internet and the router (TCP handshake every 5 s, only while watched);
- the speed test — last result, the last 7 days as one sparkline per figure (hover any tile
  for each run), and Run now.

Under it, **History** (a toggle; remembered per browser):
- every run kept on Asgard, as per-day averages: a bar chart with one bar per calendar day (a
  missed day is a gap) and a min–max whisker, hover for the day;
- below the chart, the days as rows that **open into that day's runs** — time, figures,
  jitter, loss, background traffic, server, and a MANUAL tag for "Run now";
- range 7 d / 30 d / 90 d / All; measure ↓ down / ↑ up / ◷ ping;
- **Export CSV**, and **Clear** (two taps within 4 s; admin only — MarsBar shows the history
  read-only).

#### Page 2 — Eclipse

Drawn natively by `eclipse.js` from eclipse-control's `/events` (it was an iframe). **The same
file runs on MarsBar** — she has every control here. Eclipse card (status, SoC temperature,
under-voltage/throttle alerts, Kodi / display / Jellyfin path / link-test tiles, Restart Kodi ·
Sync library · Test link · Reboot, and a LAN / Tailscale path switch) · Streams (Wolf on
Sisyphus, End a stuck one) | On the TV (Jellyfin, filtered to the Kodi addon) · Activity (the
last actions from EITHER dashboard, from eclipse-control's memory). Reboot, the path switch and
End need a second tap within 3 s. See `Claude/eclipse.md`.

#### Page 3 — Power (was Monitoring)

Full column: **Lights** — two sections, **Groups** (the Living Room Lights master switch, full
width) and **Lamps** (one warm tile each); moved here from the home page so every switch and
every watt is in one place · **Power** — total draw, machines vs lights, today's cost so far
and the yearly rate, a **share bar** (who is drawing it right now, one segment per plug,
live), legend chips with live watts, and **the last 24 hours as ONE smooth line** — the house's
total, green ripening into red towards now, with peak · average · kWh beside it; hover any moment for
every plug's share of it. (It was a stacked band per plug, which read as clutter.) ·
**Devices** — one card per plug, machines first, relay locked on machines; expand for V, A,
apparent power, power factor, kWh and cost today. Small column: **Cost Outlook**, **Plug
Health** (online dot + Wi-Fi, live).

All first frames POST the **same generated Jinja query** to HA's `/api/template` — `plugQuery`
in `glance.nix`. Projections are **instantaneous draw × 24 h, labelled "at current draw"** —
never "average"; see `Claude/home-assistant.md` for why.

#### Page 4 — Terminal

ttyd (:7681), sized to the window (`.term-widget`) instead of a fixed 700 px box.

**Theme:** background `hsl(213, 14%, 7%)` (tech grey, a faint blue cast), primary
`hsl(158, 79%, 57%)` (the default mint — Glance's own uses only; the HUD's colour is the
picker's), positive `hsl(150, 100%, 65%)`, negative `hsl(355, 100%, 65%)`. `branding.app-name = "Asgard"`, footer hidden.

**Icons:** `sh:` (selfh.st, coloured); a CDN URL where selfh.st has none. Avoid `si:` — monochrome.

### Network panel + speed test (port 9555)

`Resources/Network-Panel/network-panel.py`, run by `systemd.services.network-panel`.
One process, three jobs:

- **Live throughput** — a thread samples `/proc/net/dev` once a second for `enp3s0` AND
  `tailscale0`, keeping 60 s of history so the sparklines are full on the first request.
- **Latency** — while an `/events` client is connected, a TCP handshake to `1.1.1.1:443` and to
  the default gateway (`:80`) every 5 s. A handshake, not ICMP, so no raw socket; a refused port
  answers as fast as an open one.
- **Speed test** — serves the last result written by `speedtest.service` and the history it
  appends, and `POST /run` starts a fresh one (touching `.manual` first, so the run is tagged).
- **Speed-test history** — `/var/lib/speedtest/history.jsonl`, one JSON line per run:
  - t, down, up, ping, plus jitter, loss, server, isp, bg (background Mb/s at test start)
    and manual — older lines have only the first four;
  - it is the unit's **StateDirectory, so it survives reboots and rebuilds**;
  - capped at 5000 runs (~3½ years at four a day, under 1 MB).

  Endpoints:
  - `GET /history` — every day's count + avg/min/max of down, up and ping (local days);
  - `GET /history?day=YYYY-MM-DD` — that day's runs in full;
  - `GET /history.csv` — all of it, as a download;
  - `POST /history/clear` (needs `X-Dash: 1`) — empties the file; `latest.json` stays, so
    the tiles keep the last result.

`GET /events` streams it to the dashboards (`init` once — with the last 120 days' summary — a
`tick` a second, `latency`, and `speedtest` when a run starts or lands or the history is
cleared) — `net.js` on both dashboards; MarsBar's goes through
her `/net-api` serve mount and is read-only (no Run now). `GET /api` is the same as one JSON
snapshot (kept; add fields, never rename). CORS for the `_origins.nix` dashboards only, `0.0.0.0`
bind, still tailnet-only (9555 not in `allowedTCPPorts`). `POST /run` needs `X-Dash: 1`.

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
- `host_whitelist` — `asgard`, the MagicDNS name, the tailnet IP, `host.containers.internal`, the VPN
  namespace IP. Built from `config.asgard.*`; it carried the **pre-re-key** tailnet IP
  (100.119.193.77) until then
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
- Seerr: `nixflix.seerr.apiKey._secret` (no `config` wrapper). Package left at nixflix's default
  `pkgs.seerr` — naming `pkgs.jellyseerr` only produced a rename warning on every eval

**nixflix systemd services:**
- `seerr.service` — the Jellyseerr process (NOT `jellyseerr.service`)
- `seerr-setup.service` — nixflix's initial wiring script
- `seerr-env.service` — writes API key header file
- `jellyfin-setup-wizard.service` — Jellyfin initial setup (creates admin user + libraries)

**Jellyseerr default profiles — set by name, through nixflix (2026-10-03):**

```nix
nixflix.seerr.radarr = lib.mkOptionDefault { Radarr.activeProfileName = "Asgard - Movies"; };
nixflix.seerr.sonarr = lib.mkOptionDefault { Sonarr = {
  activeProfileName = "Asgard - TV";
  activeAnimeProfileName = "Asgard - Anime";   # Jellyseerr keeps a SEPARATE anime profile
  animeSeriesType = lib.mkForce "anime";
}; };
```

- **Why:** nixflix's `seerr-radarr` / `seerr-sonarr` units PUT the whole instance config on *every*
  boot and rebuild, and with no name set they pick `.profiles[0]`. The two hand-written
  `seerr-radarr-profile` / `seerr-sonarr-profile` timer units that used to "fix" this ran once, 12 min
  after boot — so after any `nixos-rebuild switch` nixflix had the last word and **anime requests used
  the TV profile**. Both units are gone; nixflix's own PUT now writes the right names.
- ⚠️ **`mkOptionDefault` is load-bearing.** nixflix builds the instance (hostname, apiKey, root
  folder, `isDefault`…) as the option's *default*. A normal definition replaces that default
  wholesale; one at the same `mkOptionDefault` priority merges with it. `animeSeriesType` needs
  `mkForce` because the default instance pins `"standard"` at that same priority.
- Both units are ordered **after `recyclarr-sync`** (and `wants` it — otherwise only a timer starts
  it, and `after` would order nothing), because recyclarr is what creates the profiles. nixflix exits
  1 if a named profile is missing: on a fresh install that means "recyclarr hasn't synced yet", and it
  converges on the next boot/rebuild. Note `seerr-sonarr` *requires* `seerr-radarr`.
- `arr-policy` still decides which profile each **existing** series uses; an anime it doesn't list is
  put back on `Asgard - TV`.

> ### ⚠️ The old profile units failed silently for three weeks — the fix is not the error you see
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
Our `seerr-library-setup.service` handles this (see below). Once Jellyseerr is initialised — i.e. on
the live box, every boot — that unit exits at its first check; it is kept only as the fresh-install
fallback, since `seerr-setup` cannot recover from that half-done state on its own.

---

## Jellyseerr Setup — Declarative Fix

### The problem
Nixflix's `seerr-setup.service` connects Jellyfin → Jellyseerr but fails at library activation.
Jellyseerr's setup wizard stays open until libraries are toggled and setup is marked initialized.

### Our fix: `seerr-library-setup.service`
Defined in `Modules/Server/jellyfin.nix`, runs after `seerr-setup.service`.

**What it does:**
1. Waits for Jellyseerr to be responsive
2. Checks `GET /api/v1/settings/public` → skips everything if `initialized == true` (idempotent)
3. Logs in via `POST /api/v1/auth/jellyfin` with `{username, password}` only (no server config fields)
4. Syncs libraries: `GET /api/v1/settings/jellyfin/library?sync=true`
5. Enables all: `GET /api/v1/settings/jellyfin/library?enable=id1,id2,...`
6. Marks done: `POST /api/v1/settings/initialize`

### Critical API notes
- **Session cookie** for the wizard flow below (login → libraries → initialize). The *settings*
  endpoints also accept `X-Api-Key` — see the "failed silently for three weeks" note above; an older
  version of this bullet claimed otherwise
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

All service monitoring is now done via Glance — the live asgard-stats cards, the network panel on :9555 and the `monitor` widgets generated from `services` in `glance.nix`.

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
mullvad-wg-private-key             # WireGuard private key from Mullvad (SABnzbd VPN namespace)
usenet/newshosting/username        # Newshosting NNTP username
usenet/newshosting/password        # Newshosting NNTP password
user-password-hash                 # bcrypt password hash ($ signs get mangled by sops --set)
eclipse-ssh-key                    # Asgard → Eclipse SSH key (eclipse-control), mode 0400
tailscale-auth-key                 # joins Asgard (authKeyFile) AND the marsbar node — Core/sops.nix
ha-token                           # Home Assistant ADMIN token, root-only 0400; ha-bridge + glance get credential copies — home-assistant.nix
```

**Still in `secrets.yaml` but no longer declared** (safe to delete from the file):
`sabnzbd-username` / `sabnzbd-password` (never read — SAB's UI auth is off, tailnet-only),
`grafana-admin-password` (Grafana removed), `kavita-token-key` (Kavita removed).

**Cloudflare tunnel UUID:** `804d54a8-e7ad-4f34-812d-3052cf862c47` (in `network.nix`)

Each `sops.secrets.*` declaration lives in the file of the service that owns it; only the shared
`admin-username` / `admin-password` are in `default.nix`.
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

### Pool options (`Modules/Server/storage.nix`)

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
  Use the dashboard's Storage card for pool capacity, not the arr UIs.
- **Dashboards must read `/data/media`, not `/data`.** `/data` stopped being a mountpoint, so a
  disk readout keyed on `/data` silently goes blank. asgard-stats reads `POOL_MOUNT=/data/media`
  explicitly for this reason, and the per-disk mounts come from the disko layout.
- **`/mnt/disk2/media` must exist before the pool can mount** — mergerfs errors on a missing branch
  and tmpfiles runs too late to help. Created by hand at install time.
- **Nix merge rule:** `systemd.services = lib.genAttrs ... ` collides with any
  `systemd.services.<name> = { ... }` definition *in the same file*. Dotted paths merge into attrset
  *literals* only, never into a computed expression. That forced the mount guards into individual
  `systemd.services.<name>.unitConfig.RequiresMountsFor = ...` lines while everything was one
  `server.nix`; `storage.nix` defines no other services, so genAttrs would work now — the explicit
  lines are kept because each can carry its own comment.
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

- `nofail` alone is dangerous: `systemd.tmpfiles.rules` in `Modules/Server/storage.nix` creates `/data`,
  `/data/media` and `/data/.state/services` unconditionally, so a boot that continues without the
  disk creates them *empty on the NVMe* and the arrs re-initialise on top.
- `RequiresMountsFor` alone is what makes `nofail` safe: services **fail closed** instead of
  running against an empty library.

Guarded units (`Modules/Server/storage.nix`, plus the missing-search units and `books-setup` in
their own files): `sonarr`, `radarr`, `lidarr`, `jellyfin`, the three
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
Disko partitioning declared in `Hosts/Asgard/_disko.nix`. **Never reference `/dev/sdX`** —
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
```

---

## Shared Media Group

**GID 169** — the group and its gid are **nixflix's** (`mkForce`d in its jellyfin module). All
services that need `/data/media` access are in this group:
- rock and jellyfin (`extraGroups`), the arr services (nixflix's `SupplementaryGroups`), suwayomi
  (primary group)
- Containers: Shelfarr's `PGID` and its `/var/lib/shelfarr` tmpfiles owner are both
  `config.users.groups.media.gid` — never a literal

⚠️ **This doc and the config used to say "GID 1001"**, from a `users.groups.media.gid = 1001` that
never took effect — nixflix's `mkForce` won silently. Shelfarr ran with `PGID=1001`, a gid with no
group on the host, which is why `/data/media/books` and `/data/media/audiobooks` are `0777` where
every sibling is `0775`. **Follow-up:** `chgrp -R media` those two trees (files written under gid
1001), then drop them to `0775` in the tmpfiles rules.

---

## Fresh Deploy Checklist

1. Populate sops secrets: `sops ~/Dots/Secrets/secrets.yaml`
2. Install NixOS: `nixos-install --flake .#rock-Asgard` (nixos-anywhere had issues, manual install worked)
3. Set partition labels to match disko: `disk-nvme-ESP`, `disk-nvme-root`, `disk-hdd-data`,
   `disk-hdd2-data`, and create `/mnt/disk2/media` by hand (mergerfs will not mount a missing branch)
4. On first boot, all of these happen by themselves — listed so nobody goes looking for a step:
   - Tailscale joins the tailnet from the sops `tailscale-auth-key` (`services.tailscale.authKeyFile`
     → `tailscaled-autoconnect.service`, a no-op once logged in)
   - Immich admin account is created by `immich-admin-seed.service`
   - FileBrowser credentials are synced from sops by `filebrowser-credentials.service`
   - Audiobookshelf + Shelfarr are wired by `books-setup.service`
   - Jellyfin's branding CSS (hides the seek-bar chapter tick marks) is
     `nixflix.jellyfin.branding.customCss` — it used to be a hand-run curl here, and nixflix wiped it
     on every boot because the option defaulted to `""`
   - Jellyfin's remote bitrate cap is `nixflix.jellyfin.system.remoteClientBitrateLimit` (40 Mbps)
   - rock's password comes from the sops `user-password-hash` (Core/sops.nix) — there is no
     `initialPassword` fallback on Asgard any more
5. Everything else (arr wiring, Jellyseerr setup, Glance dashboard) is automatic

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
