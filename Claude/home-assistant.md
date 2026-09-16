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

## Not done yet

- Not added to the Glance dashboard (bookmarks/monitors live in `server.nix` — the file to avoid).
- No Cloudflare tunnel route; tailnet-only by design.
- No backup of `/var/lib/hass`.
