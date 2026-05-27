# Asgard — Media Server Reference

## Overview

Asgard is a NixOS media server configuration defined in `Modules/server.nix`.
Currently running on Sisyphus hardware for testing — will move to a dedicated machine via nixos-anywhere.
Everything is declarative. A fresh deploy needs only the sops secrets populated before building.

---

## Port Reference

| Service       | Port | Access         | Notes |
|---------------|------|----------------|-------|
| Jellyfin      | 8096 | Tailscale + CF tunnel | jellyfin.bifrost-vault.com |
| Jellyseerr    | 5055 | Tailscale + CF tunnel | requests.bifrost-vault.com |
| Immich        | 2283 | Tailscale + CF tunnel | photos.bifrost-vault.com |
| Sonarr        | 8989 | Tailscale only | |
| Radarr        | 7878 | Tailscale only | |
| Lidarr        | 8686 | Tailscale only | |
| Prowlarr      | 9696 | Tailscale only | |
| Readarr       | 8787 | Tailscale only | Native NixOS service, not nixflix |
| SABnzbd       | 8080 | Tailscale only | |
| Homepage      | 3000 | Tailscale only | Declarative dashboard |
| Kavita        | 5000 | Tailscale only | Podman container |
| Dozzle        | 8888 | Tailscale only | Container log viewer |
| File Browser  | 8081 | Tailscale only | Default login: admin/admin — change on first boot |

---

## Stack Architecture

### Native NixOS services (via nixflix v1.2.0)
- Sonarr, Radarr, Lidarr, Prowlarr, Jellyfin, Jellyseerr (seerr), SABnzbd
- Nixflix auto-wires: Prowlarr ↔ arr services, Jellyseerr ↔ Jellyfin/Sonarr/Radarr
- All API keys pre-seeded from sops — no manual UI wiring needed

### Native NixOS services (not nixflix)
- Readarr — `services.readarr`, user added to `media` group manually
- Immich — `services.immich`, manages its own PostgreSQL + Redis
- Tailscale — `services.tailscale`
- Cloudflared — `services.cloudflared`

### Podman containers
- Homepage, Kavita, Dozzle, File Browser
- Backend: `virtualisation.oci-containers.backend = "podman"`
- Docker compat socket enabled for Dozzle

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

## Homepage Dashboard

**Declarative approach:** Static YAML files built in Nix store, written to `/var/lib/homepage/config/` by `homepage-config.service` on every boot before the container starts.
API keys injected via `/var/lib/homepage/homepage.env` using `{{HOMEPAGE_VAR_*}}` substitution.

**Services with live widgets (API keys in sops):**
Jellyfin, Jellyseerr, Sonarr, Radarr, Lidarr, Prowlarr, SABnzbd

**Services as links only (no API key in sops):**
Immich, Kavita, Readarr, Dozzle, File Browser

**To add a widget for Immich/Kavita later:** add `immich-api-key` / `kavita-api-key` to sops, update the YAML in `homepageServices` and the env script in `homepage-config.service`.

**Container image:** `ghcr.io/gethomepage/homepage:latest`
**Config mount:** `/var/lib/homepage/config:/app/config`

---

## Sops Secrets Reference

All in `Secrets/secrets.yaml`. Generate keys with: `od -An -tx1 -N16 /dev/urandom | tr -d ' \n'`

```
sonarr-api-key
radarr-api-key
lidarr-api-key
prowlarr-api-key
jellyseerr-api-key
sabnzbd-api-key
sabnzbd-nzb-key
jellyfin-api-key
jellyfin-admin-password
cloudflare-tunnel          # full credentials JSON from cloudflared tunnel create
tailscale-auth-key         # tskey-auth-... from Tailscale admin panel
```

**Cloudflare tunnel UUID:** `804d54a8-e7ad-4f34-812d-3052cf862c47` (in server.nix)
**Tunnel created with:** `cloudflared tunnel create asgard` on Sisyphus

---

## Data Layout

```
/data/
  media/
    tv/        movies/        music/        books/
  downloads/
    usenet/
  photos/                    # Immich
  .state/services/           # nixflix state (arr configs, API keys)

/var/lib/
  kavita/                    # Kavita container state
  homepage/config/           # Homepage YAML (written by homepage-config.service)
  filebrowser/               # File Browser state
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
2. Build: `system-rebuild rock Asgard`
3. On first boot:
   - Run `sudo tailscale up` to authenticate Tailscale
   - Create Immich admin at `http://localhost:2283`
   - Change File Browser password (default: admin/admin) at `http://localhost:8081`
4. Everything else (arr wiring, Jellyseerr setup, Homepage dashboard) is automatic

---

## Cloudflare Tunnel Setup (one-time)

```bash
cloudflared login                          # authenticate
cloudflared tunnel create asgard          # creates credentials JSON
# Copy the credentials JSON into sops as cloudflare-tunnel
# Add DNS CNAME records in Cloudflare dashboard pointing to <tunnel-uuid>.cfargotunnel.com
```

Public routes: jellyfin.bifrost-vault.com, requests.bifrost-vault.com, photos.bifrost-vault.com
