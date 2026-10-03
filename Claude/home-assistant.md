# Home Assistant (Asgard)

**Module:** `Modules/home-assistant.nix` (standalone — deliberately **not** in `server.nix`)
**Host:** Asgard only. **Port:** 8123, tailnet-only (`http://asgard:8123`)
**Version:** home-assistant 2026.5.4 (nixpkgs), deployed 2026-09-16
**State dir:** `/var/lib/hass`

Home automation — smart plugs, sensors, automations. Not to be confused with Nix
**home-manager**, which is also on Asgard (`home-manager-rock.service`) and is a completely
different thing.

## Why it isn't in `server.nix`

Asgard's `Modules/server.nix` carries hundreds of lines of uncommitted local work and is
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
git diff Modules/home-assistant.nix > /tmp/x.patch
cat /tmp/x.patch | ssh asgard 'cat > /tmp/x.patch'
ssh asgard 'cd ~/Dots && git apply --check /tmp/x.patch'   # always --check first
ssh asgard 'cd ~/Dots && git apply /tmp/x.patch'
ssh asgard 'cd ~/Dots && NIXOS_INSTALL_BOOTLOADER=0 sudo nixos-rebuild switch --flake .#rock-Asgard'
```

**New `.nix` files must be `git add`-ed on Asgard too** — import-tree only sees tracked files,
so an unstaged module is silently ignored.

## Troubleshooting

```bash
ssh asgard 'systemctl status home-assistant'
ssh asgard 'journalctl -u home-assistant -n 100 --no-pager'
ssh asgard 'curl -sI http://localhost:8123 | head -3'
```

First start is slow (it builds its initial DB). Onboarding is at `http://asgard:8123` — create
the owner account there; it is **not** declarable.

## Glance

Added to `Modules/server.nix` **on Asgard directly** (backup: `server.nix.bak-ha-20260916-1949`),
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

Tunables live in the `let` block of `Modules/server.nix`: `powerRate` (0.3041 $/kWh,
the GloBird *balance* rate), `powerRefW` (150 W draw-bar ceiling),
`powerSupplyDaily`.

## Not done yet

- No Cloudflare tunnel route; tailnet-only by design.
- No backup of `/var/lib/hass` — and it is the *only* place device pairings exist.
- `upnp` and `cast` components not built in, so discovery logs a harmless `UnknownHandler` for
  the router and any Chromecast device. Add them to `extraComponents` to silence it.
