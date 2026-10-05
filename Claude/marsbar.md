# MarsBar — partner-facing dashboard

**Module:** `Modules/Server/marsbar.nix` · imported by `Hosts/Asgard/system.nix`
**Styling:** `Resources/MarsBar/marsbar.css` (+ `vine.svg`, `bloom.svg`) · **shared with the admin
dashboard:** `Resources/Glance/{cards.css,dash.js,lights.js,eclipse.js,net.js}`, `Modules/Server/_livecard.nix`
**Plugs:** `Modules/Server/_plugs.nix` (the one inventory — see Safety)
**URL:** `http://marsbar:1111/` (tailnet only)
**Built:** 2026-09-19 · live lights + restyle 2026-10-03 · full Eclipse panel + vine 2026-10-04

A second, deliberately small Glance for the user's partner: house lights,
Jellyfin/Jellyseerr links, and the **full** Eclipse panel — the same one the admin
dashboard has (status, Restart Kodi, Sync library, link test, Jellyfin path, Reboot, ending
a stuck Wolf stream, what the TV is playing, the shared activity log) plus a read-only
network card. She is the one in front of the TV when it locks up. Purple, so it is never
confused with Asgard's green tech-HUD Yggdrasil dashboard.

---

## Why a second tailnet node, not a page or a path on Asgard

(This is why `marsbar` shows up in the tailnet as a device of its own.)

- **Isolation.** Tailscale ACLs filter by *machine and port* — they cannot see a URL
  path. Glance has no logins. So a page or path on `asgard:8888` (`asgard:8888/her`)
  would need her granted `asgard:8888`, and then every admin page — the terminal, the
  power relays' page, all of it — is one URL edit away. A separate node lets her
  grant be `marsbar:1111` (+ Jellyfin and Jellyseerr): she cannot open a single
  other Asgard port, and the ACL's `tests` block asserts that on every policy edit.
- **The name.** MagicDNS names come from **machines**, not services, so a URL like
  `marsbar:1111` needs a machine called `marsbar`.
- **Everything she uses is proxied onto her origin** by that node's `tailscale serve`
  (`/ha`, `/eclipse-api`, `/net-api` below), so her browser never talks to an Asgard
  port at all — the Eclipse and network cards work for her without any grant on
  :9554 / :9555.

(A port-only grant like `asgard:1111` would also isolate her, but needs the same
per-API grants or proxying, shows her Asgard in her device list, and loses the name.)

```
her browser ──► marsbar:1111 ──► tailscaled (userspace netstack, own node)
                                   ├── /             → 127.0.0.1:8890  glance-marsbar
                                   ├── /ha/*         → 127.0.0.1:9556  ha-bridge
                                   ├── /eclipse-api/* → 127.0.0.1:9554  eclipse-control
                                   └── /net-api/*    → 127.0.0.1:9555  network-panel
```

Only `glance-marsbar` binds **loopback only**. The three APIs are shared with the
admin dashboard, which calls them directly over Asgard's tailnet address, so they
listen on `0.0.0.0` and are kept off the LAN by the firewall (none is in
`allowedTCPPorts`; only `tailscale0` is trusted). Nothing here opens a port — the
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
the scalar and yields `yaml: line N: could not find expected ':'`. This forced
every card onto ONE line while the config was hand-written YAML. **The config is
now a Nix attrset serialised by `pkgs.formats.yaml`**, and the CSS/JS are real
files in Glance's assets dir, so neither problem can recur — never go back to
`readFile`-ing or interpolating anything into an indented block scalar.

### Entity ids in Glance templates need an escaped dot

Keys like `switch.colour_lamp_switch` contain dots, and Glance resolves
`.JSON.String` paths with gjson, where a dot means "nested" — so the plain key
never resolves. **Escape the dot**: `{{ .JSON.String "switch\\.colour_lamp_switch" }}`
(the Go string literal unescapes `\\` once, leaving gjson's `\.`). That is how each
light tile is server-rendered with its real state (`stateOf` in `marsbar.nix`).

### `rem` is 10px in Glance

Glance sets `:root { font-size: 10px }` (9.4px under 550px wide). The old
"bigger" labels at `1.1rem` were ~10px on her phone. Size against 10px.

### Assets are cached for 2h

Glance serves `/assets/` with a 2-hour `Cache-Control`. The scripts are linked with
`?v=<content hash>` (the `asset` helper) so a deploy reaches her phone immediately;
`custom-css-file` needs nothing because Glance stamps it with its own start time.

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

Her light tiles, ha-bridge's `ALLOWED` set and the Living Room Lights group are
all generated from **`Modules/Server/_plugs.nix`**, so the tiles can no longer
drift out of the allowlist. A plug marked `light = false` (Asgard's and Eclipse's
relays) is never drawn here and never toggleable anywhere. `ALLOWED` — not this UI
— is what stops `switch.server_power_switch` and `switch.eclipse_switch` being
toggled. Verified through the proxy: `POST /ha/toggle/switch.server_power_switch`
→ **403 `not toggleable`**, relay left `on`.

Four independent layers protect the server relay: the ACL, the bridge allowlist,
the `X-Dash` header (below), and the HA token never leaving the server — it is now
root-only too, not world-readable (`Claude/home-assistant.md`). Even a
misconfigured ACL cannot cut power to Asgard.

**Cross-site POSTs.** ha-bridge (`/toggle/*`), eclipse-control (`/act/*`) and
network-panel (`/run`) refuse a POST without an `X-Dash: 1` header, and answer CORS
only for the dashboard origins in `Modules/Server/_origins.nix` (never `*`). A
custom header forces a CORS preflight, which only those origins pass, so a random
web page open in a tailnet browser can no longer fire them with a one-line
`fetch()`. Same-origin callers (MarsBar via serve, the eclipse panel's own page)
just send the header.

**Her Eclipse controls are the admin dashboard's, all of them** (`eclipse.js`, shared):
Restart Kodi, Sync library, Test link, the Jellyfin LAN/Tailscale switch, Reboot, and
ending a Wolf stream on Sisyphus. The two that interrupt what is on screen (Reboot, the
path switch) and ending a stream need a second tap within 3 s. Ending a stream goes
`her browser → /eclipse-api → eclipse-control → wolf-bridge` — wolf-bridge only answers
Asgard, so she never needs (or gets) anything on Sisyphus. Not hers: the network card's
**Run now** (a speed test pauses SABnzbd — an admin call; `data-readonly` on net.js).

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

- **One page, three columns: Home · Eclipse · Network.** On a phone Glance shows
  ONE column at a time with a **dot per column** in the bottom bar — tap a dot,
  you are there. Separate *pages* (how it used to be) live behind the ☰ menu
  instead, which is three taps to switch. (This doc once said the opposite; the
  dots are `mobile-navigation-input`s, one per column; page links are in the ☰
  drawer.) Glance allows at most 3 columns, at most 2 of them `full`, and `width:
  slim` caps it at 2 — so the page has no width setting. It opens on the first
  full column (Home).
- **The Eclipse and network cards are the admin dashboard's own**, not a copy:
  `html` widgets (`_livecard.nix`) painted by `eclipse.js` / `net.js` from their
  `/events` streams, loaded here with `data-api="/eclipse-api"` / `"/net-api"` (her
  origin) and posters from `http://asgard:8096` (in her grant). They are styled by
  `cards.css`, which is written against colour tokens (`--ag-text`, `--s1…`, `--acc`,
  …); `marsbar.css` defines those tokens in her purple. So a fix or a new control
  lands on both dashboards, and they can never drift apart again — which is what
  happened to the old hand-built copy here (three actions, a 15 s poll, `marsbar.js`,
  now deleted). Glance's `html` widget does NOT sanitise markup (0.8.5).
- **Her Eclipse column is `ec-main · ec-tv · ec-wolf · ec-ctl · ec-log`.** ⚠️ The card
  list in `marsbar.nix` and the one in `glance.nix` are **independent by design** — a
  new card must be added to BOTH, plus the `D.ready` selector and the `.ags-skel`
  height list in `cards.css`, or one dashboard gets a collapsing card and the other
  does not. This is exactly how the two drifted before `2a831da`.
- **`ec-ctl` — controllers, network path and the subtitle default** (added 2026-10-05).
  She gets every control he does; `eclipse.js` deliberately has **no** `data-readonly`
  split (unlike `net.js`, where she has no "Run now" because a speed test pauses
  SABnzbd). Two things worth knowing about it:
  - ⚠️ A controller showing BlueZ `Connected: yes` can still be producing **no input
    at all** — the DualSense here fails to bind its driver with `-5` often enough to
    matter. The card tests for a real input node and flags that state as `stale`
    rather than showing a green dot for a dead pad.
  - ⚠️ **Subtitles are a Jellyfin *user* setting, not a Kodi one**, because the addon
    overwrites Kodi's on every playback. The toggle writes `SubtitleMode` on the
    account Eclipse logs in as — so pressing it from *either* dashboard changes the
    same (her) account.
- ⚠️ When adding a click handler to a new card, widen the `onClick` selector.
  It scopes to specific card ids (`#ec-main [data-act], #ec-ctl [data-act]`), so a
  button in a card that is not listed renders enabled and is simply never matched —
  presenting exactly like the 2026-09 dead-button bug and taking just as long to find.
- Streams, not polls: one `EventSource` per backend, opened only on a page with its
  cards, parked after 60 s hidden, reconnected with backoff, watchdogged (dash.js).
  The Pi is only polled over SSH while some page has the Eclipse stream open. A new
  event type needs its own timer reset in `Hub.poller`'s wake path, or the card lags
  an action by a full poll interval even though the action has finished.
- The **Lights** widget keeps `cache: 1s`: its `/states` answer renders each tile's
  real state server-side (no grey flash, no reflow), and the bridge answers from
  memory, so it costs nothing.

## The vine

Each card has a climbing vine down its left edge (`vine.svg`) and a blossom crowning it
(`bloom.svg`, breathing gently): a gradient stem with a thinner one twining round it,
veined leaves in two greens with young orchid-tinted ones, curling tendrils, five-petal
orchid blossoms with gold centres, buds and dew. `vine.svg` is **one seamless 240px tile**
— the stem leaves the bottom at exactly the x and slope it entered the top, so it repeats
with no join — and each card starts it at a different offset (`nth-child`), so no two
look stamped. Both are generated (positions computed along the stem), real SVG files in
the assets dir rather than a URL-encoded string in the CSS. `pointer-events: none`.
- Phone-first: one column at ~390px; on a desktop the lamps and actions flow into a
  grid (`auto-fill, minmax(250px, 1fr)`) under a `width: slim` page.

---

## Live lights (no polling)

`Resources/Glance/lights.js` — shared with the admin dashboard — holds one
`EventSource` on `ha-bridge`'s `/events` (here `/ha/events`, through serve). The
bridge keeps an in-memory snapshot from HA's websocket and pushes every change, so a
lamp flipped from her phone, the HA app, an automation or the plug's own button
shows on every open dashboard within a few hundred ms (measured ~2ms bridge →
browser locally). Details in `Claude/home-assistant.md`.

- **Tap** → the tile flips immediately (optimistic, a pulsing knob while
  unconfirmed); the group tile flips its members too. A failed toggle rolls back and
  shows "Failed".
- **Badge** next to "Everything": `Live` (green) · `Delayed` (bridge is polling HA
  because HA's websocket is down) · `Reconnecting…` (stream down — tiles go
  desaturated so stale state never looks confident) · `Home Assistant offline`.
- Works through `tailscale serve` unchanged: serve is a Go `httputil.ReverseProxy`,
  which flushes `text/event-stream` immediately, and the bridge sends a `ping` event
  every 15s (an event, not a `:` comment, so the page can detect a half-open stream
  and reconnect).
- A hidden tab parks its stream after 60s and re-syncs on return; a page without a
  light tile never opens one.
