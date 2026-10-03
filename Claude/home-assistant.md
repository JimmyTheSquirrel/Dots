# Home Assistant (Asgard)

**Module:** `Modules/Server/home-assistant.nix` (standalone — deliberately **not** in `server.nix`)
**Host:** Asgard only. **Port:** 8123, tailnet-only (`http://asgard:8123`)
**Version:** home-assistant 2026.5.4 (nixpkgs), deployed 2026-09-16
**State dir:** `/var/lib/hass`

Home automation — smart plugs, sensors, automations. Not to be confused with Nix
**home-manager**, which is also on Asgard (`home-manager-rock.service`) and is a completely
different thing.

## Why it isn't in `server.nix`

Asgard's `Modules/Server/server.nix` carries hundreds of lines of uncommitted local work and is
**materially divergent** from the Sisyphus copy — see `memory/asgard-clone-diverged.md`. A
standalone module avoids ever having to patch that file.

## ⚠ The declarative limit — read this before "fixing" it

`services.home-assistant.config` makes `configuration.yaml` a **read-only store symlink**.
That covers the base config, but **device pairings, credentials, the entity registry and the
recorder DB are runtime state in `/var/lib/hass/.storage`** and cannot be declared. Every
integration added through the UI ("Add integration" → config flow) lands there.

This is a genuine exception to the repo's "if it's not in Nix, it doesn't exist" rule: a fresh
install reproduces Home Assistant itself, but **not** the paired devices. Back up
`/var/lib/hass` before a wipe. Cf. `memory/fresh-wipe-reproducibility-gaps.md`.

## `extraComponents` is load-bearing

NixOS builds HA with **only** the Python dependencies of the components listed in
`extraComponents`. An integration that isn't listed **does not appear in the UI at all** — the
"Add integration" search simply won't find it. New hardware usually means adding its component
and rebuilding, not just clicking around.

Currently included: `default_config`, `met`, `radio_browser`, `backup`, discovery
(`zeroconf`, `ssdp`, `dhcp`), and plug integrations `tplink` (Kasa/Tapo), `shelly`, `tasmota`,
`esphome`, `tuya`, `smartlife`, `mqtt`, `switchbot`, `wiz`.

## Discovery needs the firewall open on the LAN side

Plugs live on `192.168.0.0/24` (`enp3s0`), not the tailnet. mDNS/SSDP are **unsolicited
multicast**, so the firewall drops them unless allowed:

```nix
networking.firewall.interfaces."enp3s0".allowedUDPPorts = [5353 1900];
```

Without this, auto-discovery finds nothing and every device must be added by IP by hand.
`openFirewall = false` is deliberate — `tailscale0` is already trusted, so the UI is reachable
over the tailnet without exposing 8123 to the LAN.

## Cloud vs local plugs

- **Local push** (best): Shelly, ESPHome, Tasmota, TP-Link Kasa — work entirely on the LAN, no
  account, keep working if the internet drops.
- **Cloud polled**: Tuya / SmartLife — needs a Tuya IoT developer account and the plugs already
  registered in the vendor app. Slower, and breaks when the vendor API changes.

Brand matters: if the plugs are Tuya-based, expect the vendor-app + cloud-credential dance.

## Deploying changes

Asgard builds from **its own clone** at `~/Dots` on `main`. Never push/pull — patch across:

```bash
git diff Modules/Server/home-assistant.nix > /tmp/x.patch
cat /tmp/x.patch | ssh asgard 'cat > /tmp/x.patch'
ssh asgard 'cd ~/Dots && git apply --check /tmp/x.patch'   # always --check first
ssh asgard 'cd ~/Dots && git apply /tmp/x.patch'
ssh asgard 'cd ~/Dots && NIXOS_INSTALL_BOOTLOADER=0 sudo nixos-rebuild switch --flake .#rock-Asgard'
```

**New files must be `git add`-ed on Asgard too** — import-tree only sees tracked files,
so an unstaged module is silently ignored, and a flake build cannot see an untracked
`Resources/…` file or `Modules/Server/_plugs.nix` at all (eval fails "path does not
exist"). `git apply` creates new files untracked.

## ha-bridge — live plug state for the dashboards

**Code:** `Resources/HA-Bridge/ha-bridge.py` · **unit:** `ha-bridge` · **port:** 9556 (tailnet only)
**Config:** generated from `Modules/Server/_plugs.nix` into a JSON file (`HA_BRIDGE_CONFIG`)

| Verb | What |
|---|---|
| `GET /events` | Server-Sent Events: `snapshot` on connect, then one `state` event per change, `link` when the HA connection changes, `ping` every 15s |
| `GET /states` | the snapshot as `{entity: state}` — from memory, so free to call |
| `POST /toggle/<entity>` | toggle an `ALLOWED` entity; needs `X-Dash: 1`; waits (≤2s) for HA to report the new state and returns it plus the whole snapshot |

**Push, not poll.** One websocket to HA (`/api/websocket`, `subscribe_entities`
filtered to the watched entities, so HA only sends what we care about) feeds the
snapshot; every dashboard holds one EventSource (`Resources/Glance/lights.js`).
Before this, every open page polled `/states` every 3s and **each poll made the
bridge download HA's entire `/api/states`**. If the websocket drops, the bridge
reconnects with backoff (1s → 30s) and meanwhile polls `/api/states/<entity>` for
the watched entities only, every 10s, telling the pages (`link: polling`, shown as
"Delayed").

**Watched** = every plug relay (machines too — read-only is still worth seeing), the
Living Room Lights group, and each plug's `sensor.<slug>_power`. **Allowed** = the
group and the `light = true` plugs. Both come from `_plugs.nix`; adding a plug there
updates the bridge, the HA group and MarsBar's tiles together.

Python deps: `python3.withPackages (ps: [ps.aiohttp])` — the stdlib has no
websocket client. aiohttp also serves the HTTP side.

Test it from Asgard:

```bash
curl -sN http://localhost:9556/events          # snapshot, then live events
curl -s  http://localhost:9556/states | jq
curl -s -XPOST -H 'X-Dash: 1' http://localhost:9556/toggle/switch.colour_lamp_switch
journalctl -u ha-bridge -n 50                  # link transitions + websocket errors
```

## The `ha-token` secret

An **admin** long-lived token: anything holding it can call any HA service, including
`switch.toggle` on `switch.server_power_switch`. It was mode `0444` (any local uid
could read it and bypass the bridge's allowlist entirely). Now:

- `ha-bridge` gets it as a systemd credential (`LoadCredential=ha-token:…`, read
  from `$CREDENTIALS_DIRECTORY/ha-token`) — systemd copies the root-only file into a
  directory only that unit's DynamicUser can read.
- The main Glance still reads `/run/secrets/ha-token` itself (`${secret:ha-token}`
  in its HA widgets), so the file is `0440 root:ha-token` and `glance.service` has
  `SupplementaryGroups=ha-token`. **To finish:** give Glance its own credential
  (`LoadCredential` + Glance's `${readFileFromEnv:VAR}`, or a `sops.templates` env
  file), then drop the group and leave the secret at the default root-only `0400`.
- `restartUnits = ["ha-bridge.service"]`: a credential is copied at unit start, so a
  rotated token needs a restart to reach the bridge.

## Troubleshooting

```bash
ssh asgard 'systemctl status home-assistant'
ssh asgard 'journalctl -u home-assistant -n 100 --no-pager'
ssh asgard 'curl -sI http://localhost:8123 | head -3'
```

First start is slow (it builds its initial DB). Onboarding is at `http://asgard:8123` — create
the owner account there; it is **not** declarable.

## Living Room Lights group

`switch.living_room_lights` is a `group` platform switch declared in
`home-assistant.nix`; its members are generated from the `light = true` plugs in
`Modules/Server/_plugs.nix`. HA derives the entity id from the group's `name`, so
renaming it renames the entity — change `group.entity` in `_plugs.nix` in the same
edit.

## Glance

Added to `Modules/Server/server.nix` **on Asgard directly** (backup: `server.nix.bak-ha-20260916-1949`),
in **both** the `All` and `Management` monitor groups. That config has **no bookmarks column by
design** — a comment near line 322 says new services go in the *monitors*, because monitor rows
are already clickable and a sidebar made the page scroll.

⚠️ HA returns **302** on `/` until onboarding is finished. If Glance shows it down, either
complete onboarding (after which `/` is 200) or add `alt-status-codes: [302]` to the site entry.

## ⚠ Power cost maths — never divide an ESPHome counter by a wall clock

Fixed 2026-09-19 after a reboot made every cost on the Monitoring page absurd:
Asgard was projected at **$1047/yr** while drawing 35.5 W (true ~$95/yr). Wrong by
~11×, and plausible-looking enough that it did not read as a bug.

**Both cumulative counters reset on device restart.** Neither is a safe divisor:

1. `total_energy ÷ hours-since-uptime_sensor` — the original approach. The reboot
   reset the uptime but **not** the energy counter, so days of kWh were divided by
   5.5 h: `2.165 / 5.5 * 24 = 9.45 kWh/day` → $1047/yr.
2. `total_daily_energy ÷ hours-since-midnight` — tried next, **also wrong**. That
   counter resets on device restart *as well as* at midnight, so it held 5.5 h of
   energy while the clock said 22 h → under-reported at **$43/yr**.
   (`0.356 kWh / 5.5 h = 64 W`, matching the real draw — the counter was fine, the
   assumed window was not.)

**The fix:** project from **instantaneous power**, `avg_kWh_per_day = W * 0.024`.
A snapshot rather than a measured average, so it moves with load, but it is always
internally consistent and cannot be wrong by an order of magnitude. Label these
**"at current draw"**, never "average". Verified against hand calculation after
deploying: Asgard 56.7 W → $151/yr, all five plugs 69.6 W → $186/yr.

A true average would need HA's long-term statistics API, which is out of reach from
the Jinja template Glance runs.

**Rule of thumb:** if a projection must use a cumulative counter, sanity-check it
against `W * 0.024` and distrust it when they diverge.

Tunables live in the `let` block of `Modules/Server/server.nix`: `powerRate` (0.3041 $/kWh,
the GloBird *balance* rate), `powerRefW` (150 W draw-bar ceiling),
`powerSupplyDaily`.

## Not done yet

- No Cloudflare tunnel route; tailnet-only by design.
- No backup of `/var/lib/hass` — and it is the *only* place device pairings exist.
- `upnp` and `cast` components not built in, so discovery logs a harmless `UnknownHandler` for
  the router and any Chromecast device. Add them to `extraComponents` to silence it.
