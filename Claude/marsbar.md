# MarsBar — partner-facing dashboard

**Module:** `Modules/Server/marsbar.nix` · imported by `Hosts/Asgard/system.nix`
**URL:** `http://marsbar:1111/` (tailnet only)
**Built:** 2026-09-19

A second, deliberately small Glance for the user's partner: house lights,
Jellyfin/Jellyseerr links, and the Eclipse TV-box controls. Purple, so it is never
confused with Asgard's green dashboard.

---

## Why a second tailnet node, not a second Glance page

MagicDNS names come from **machines**, not services, so `marsbar:1111` requires a
machine called `marsbar`. Running one also buys the isolation for free: an ACL
granting only `marsbar:*` cannot reach a single Asgard port, because they are
different nodes with different IPs. A second page on `asgard:8888` would have left
every admin page one URL edit away.

```
her browser ──► marsbar:1111 ──► tailscaled (userspace netstack, own node)
                                   ├── /             → 127.0.0.1:8890  glance-marsbar
                                   ├── /ha/*         → 127.0.0.1:9556  ha-bridge
                                   ├── /eclipse-api/* → 127.0.0.1:9554  eclipse-control
                                   └── /net-api/*    → 127.0.0.1:9555  network-panel
```

Every backend binds **loopback only**. Nothing here opens a firewall port — the
serve proxy terminates inside tailscaled, so neither the LAN nor Asgard's own
tailnet node can reach this dashboard.

**Units:** `glance-marsbar`, `tailscaled-marsbar`, `marsbar-tailscale-up`.

---

## Traps (all of these cost real time)

### `--statedir`, not `--state`

With only `--state=<file>` tailscaled has no var root to store TLS certs in:
`tailscale cert` fails `500 no TailscaleVarRoot` and every HTTPS handshake dies
`tlsv1 alert internal error`. Node identity survives the switch because tailscaled
looks for `tailscaled.state` *inside* the statedir, which is where it already was.

### `--accept-dns=false` is load-bearing

Without it the second daemon fights the host's primary tailscaled over
`/etc/resolv.conf` and can break DNS for every service on Asgard. `--port=0`
likewise, so its WireGuard port cannot collide with 41641.

### ⚠ Serve mount paths must never collide with a Glance page slug

The Eclipse API was mounted at `/eclipse` while a Glance page also had slug
`eclipse`. **Serve won**: `marsbar:1111/eclipse` returned the raw (green, unthemed)
control panel instead of her dashboard page — and that panel, loaded without its
trailing slash, resolved its relative `fetch('status')` to `/status` and reported
"cannot reach eclipse-control". Two bugs from one name clash.

Keep API mounts on an **`-api` suffix** no page slug will ever take.

Removing a mount needs an explicit `tailscale serve --http=1111 --set-path=/x off`
— serve config is **persisted in node state**, so deleting the Nix lines does not
remove a published endpoint.

### Nix `''` strings strip common indentation

Multi-line HTML interpolated into a YAML block scalar arrives with its
continuation lines at column 0 — below the scalar's indent — which silently ends
the scalar and yields `yaml: line N: could not find expected ':'`. **Emit each
card as ONE line.**

### Entity ids cannot be read from Glance templates

Keys like `switch.colour_lamp_switch` contain dots, and Glance treats a dot as a
nested path, so `.JSON.String` on them never resolves. All light cards are rendered
statically and painted by the `document.head` script.

### HTTPS was tried and reverted

An HTTPS endpoint (for a secure context, so Chrome would drop the address strip it
pins on PWAs served over HTTP) **broke Brave outright**: Brave upgrades `http://`
to `https://` but **keeps the port**, so `http://marsbar:1111` became
`https://marsbar:1111` — a port with no TLS listener — while Chrome, which does not
upgrade, kept working. Serving TLS on 1111 would not fix it either: the cert is
issued for `marsbar.<tailnet>.ts.net`, so a short-name HTTPS URL fails name
validation. The only working HTTPS URL is the **FQDN on 443 with no port**.

One cert was provisioned before the revert, so `marsbar.<tailnet>.ts.net` is now
permanently in the public Certificate Transparency log. Audit any time with
`crt.sh/?q=%.<tailnet>.ts.net` — only `marsbar` should ever appear. Enabling the
tailnet HTTPS setting publishes **nothing** on its own; only nodes that actually
provision a cert are logged, which is why the phones (whose names contain real
first names) can never leak this way — the Android client has no `tailscale cert`.

---

## Safety

The light list in `marsbar.nix` **must stay a subset of `ALLOWED`** in
`Modules/Server/home-assistant.nix`. That set — not this UI — is what stops
`switch.server_power_switch` and `switch.eclipse_switch` being toggled. Verified
through the proxy: `POST /ha/toggle/switch.server_power_switch` → **403
`not toggleable`**, relay left `on`.

Three independent layers protect the server relay: the ACL, the bridge allowlist,
and the HA token never leaving the server. Even a misconfigured ACL cannot cut
power to Asgard.

Not exposed to her: `reboot` (bounces the TV box) and `jellyfin-toggle` (changes
stream routing). Both are one line to add in `tvActions` if wanted.

---

## ⚠ Isolation lives in the Tailscale console, NOT this repo

`system-rebuild` cannot recreate it. See `Claude/next-up.md` item 6.

- Caitlin is a **separate Tailscale user**, `gamerf1169@gmail.com`; device
  `caitlins-s25-1`. Her original phone had been added under the owner's login and
  was deleted — a device under the owner's login bypasses any ACL written for her.
- This tailnet uses the newer **`grants`** syntax (`src`/`dst`/`ip`), not legacy
  `acls`; `ip` is the port field (`["tcp:8096"]`).
- **Never use `autogroup:member` for the admin rule** — she is a member too, so it
  grants her everything and silently defeats the design. The policy uses the literal
  login `JimmyTheSquirrel@github`, because Owner and Admin are distinct roles and it
  was not worth betting admin access on whether Owner counts as `autogroup:admin`.
- Her grant needs `marsbar:1111` **plus `asgard:8096` + `asgard:5055`**. A dashboard
  *link* is just a URL the browser opens — it does **not** route through marsbar.
- Use a **`tests` block**. Tailscale runs it on every save and refuses to save on
  failure, which keeps the isolation asserted on every future policy edit.

---

## Layout notes

- **Mobile nav = PAGES, not columns.** Glance renders pages as bottom pills
  (`mobile-navigation-page-links`) — that is the "tap the dots and move across"
  behaviour. Extra columns merely stack vertically on a phone.
  `hide-desktop-navigation: true` hides the desktop tab bar without affecting them.
- The Eclipse panel is rebuilt **natively** here rather than iframed like the admin
  dashboard does. The iframe exists there because Glance's `html` widget sanitises
  markup — but `custom-api` + a `document.head` script has no such limit, which buys
  the purple theme for free and a layout that works on a phone.
- `custom-api` widgets use **`cache: 1h`**. Nothing is rendered from those fetches —
  the head scripts paint every value and poll — so re-fetching per navigation bought
  only latency. The Eclipse one SSHes to the Pi and cost ~0.7s on every page load;
  caching took repeat navigation from 0.82s to 0.003s.
- Light state polls every **3s** (see `Claude/server-info.md` — the admin dashboard
  needed the same fix; it previously never auto-refreshed at all).
