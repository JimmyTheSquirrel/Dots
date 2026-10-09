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
- **Her Eclipse column is `ec-main · ec-tv · ec-wolf · ec-ctl · ec-net · ec-log`.** ⚠️ The card
  list in `marsbar.nix` and the one in `glance.nix` are **independent by design** — a
  new card must be added to BOTH, plus the `D.ready` selector and the `.ags-skel`
  height list in `cards.css`, or one dashboard gets a collapsing card and the other
  does not. This is exactly how the two drifted before `2a831da`.
- **`ec-net` — Eclipse's network** (added 2026-10-09): Wired ⇄ Wi-Fi, search, join with a
  password, forget — every control, same as the admin card, since she's the one who'd take
  the box to a friend's. See `Claude/eclipse.md` → *Network · `#ec-net`*.
- **`ec-ctl` — the Bluetooth manager and the subtitle default** (added
  2026-10-05; its network rows moved to `ec-net`). She gets every control he does — pair, rename, auto-connect, forget, search —
  and `eclipse.js` deliberately has **no** `data-readonly` split (unlike `net.js`, where she
  has no "Run now" because a speed test pauses SABnzbd). **It stays in sync with the admin
  page because nothing is kept in the browser:** device names, a running search and a pair
  in progress all live in eclipse-control and arrive on both pages as `ctl` / `scan` /
  `ctlbusy` events, through her `/eclipse-api` serve path (which forwards every `/ctl/…`
  route — nothing to add there for a new one). See `Claude/eclipse.md` → *Bluetooth*. Things
  worth knowing about it:
  - ⚠️ A controller showing BlueZ `Connected: yes` can still be producing **no input
    at all** — the DualSense here fails to bind its driver with `-5` often enough to
    matter. The card tests for a real input node and flags that state as `stale`
    rather than showing a green dot for a dead pad.
  - ⚠️ **Subtitles are a Jellyfin *user* setting, not a Kodi one**, because the addon
    overwrites Kodi's on every playback. The toggle writes `SubtitleMode` on the
    account Eclipse logs in as — so pressing it from *either* dashboard changes the
    same (her) account.
- ⚠️ When adding a click handler to a new card, widen the `onClick` selector.
  It scopes to specific card ids (`#ec-main [data-act], #ec-ctl [data-act]`, and the
  `#ec-ctl [data-bt-*]` list for the Bluetooth buttons), so a
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

## Her colour picker (and the cats)

She can recolour her dashboard, per browser, from the same picker as Asgard's
(`Resources/Glance/theme.js`, loaded with `data-profile="marsbar"` — a plain, not
deferred, script first in `document.head`, so a pick is on screen before the first paint).
On a phone it is a row at the top of the ☰ menu; on a desktop (no nav bar there —
`hide-desktop-navigation`) it is a round button in the bottom-right corner (`.hud-pick.fab`,
shown only while the phone bar is hidden).

- **Every theme is a two-tone** (2026-10-09: the single colours went, at rock's request —
  "I really like those"): first **Lavender — her own** (`#ca99f5` with the vine's green; it
  picks the default, `hsl(272, 82%, 78%)`), then seventeen softer ones — Plum and gold,
  Twilight, Bluebell, Moonlight, Lagoon, Mermaid, Seafoam and coral, Meadow, Honeydew,
  Lemonade, Peaches and cream, Tangerine and teal, Sorbet, Sunset, Strawberries and mint,
  Cherry blossom, Cotton candy (her list is her own; Asgard's are named for the Nine
  Realms) — then **Just for fun** (Cats, Snow, Sakura, Starry night, Spooky, Ocean, and her
  garden switches), **Your own** (two wells: her colour and the vine's) and Reset. Stored
  in `marsbar-colour` (and the redrawn artwork in `marsbar-art`, keyed to `data-art-v` — a
  hash of vine.svg, bloom.svg and theme.js).
- **Only hues move.** marsbar.css is written against two numbers: `--mb-h` (her purple,
  272) and `--mb-h2` (the vine's green, 150) — every colour there is
  `hsl(var(--mb-h) ± n, …)` or `--mb-h2`. A pick sets those, Glance's own `--bgh`,
  `--color-primary` and `--color-positive`, and nothing else, so every colour sits as
  softly on the glass as her purple does. One colour moves the purple; a two-tone pick
  also moves the vine's green to its second colour. ⚠ **A new colour in marsbar.css must
  be written the same way** — a literal purple stays purple whatever she picks. Status
  colours (`--mb-bad`, `--mb-warn`) and the shared data palette don't move.
- **The vine and the blossom follow.** theme.js fetches vine.svg and bloom.svg once per
  pick, turns every purple in them (hue 240–345) by the pick and every green (110–175) by
  the second colour (gold and greys stay), and hands them back as `--mb-vine` /
  `--mb-bloom` data-URIs. marsbar.css uses `var(--mb-vine, url("/assets/vine.svg"))` — the
  fallback is absolute on purpose (a relative `url()` inside `var()` can resolve against
  the page, not the stylesheet).
- **Cats** put cats all over it — living ones: they blink, twitch, yawn, groom, duck
  behind her cards and peek back, answer a tap with a "mrrp?" or a purr (and hide if she
  keeps poking them), curl up asleep on the Lights card when every light is off, bat at
  the playhead on "On the TV", scatter when Eclipse goes down and nap on its SoC
  temperature when the Pi runs hot. Plus paw prints, paw glyphs on the headings, and
  kitten faces in place of the blossoms
  (`html[data-cats][data-dash="marsbar"]` — on Asgard that spot is the Yggdrasil tree).
  Details in `Claude/server-info.md` → The colour picker → Cats.
- **Snow, Sakura, Starry night, Spooky, Ocean** — the other fun themes (fx.css + fx.js,
  shared with Asgard; details in `Claude/server-info.md` → The colour picker): snowfall,
  drifting petals, a night sky with shooting stars, bats and a spider, bubbles and fish.
  Her crowns become the theme's mark (a snowflake, a moon, a bat, a fish), swaying —
  except in **Sakura**, where her living blossoms stay (they already are the theme). Her
  cards are frosted glass, so behind them (the sky, the mist, the light) nothing moves;
  everything alive is in front. The tip under the row says what the theme does on a tap,
  plus "Butterflies like a tap too" while her butterflies are on.

## The garden (garden.js)

Her vine is alive, whatever colour she has picked (`Resources/MarsBar/garden.js`, loaded
deferred after dash.js; styles at the end of marsbar.css) — in **three parts, each on unless
she turns it off**: her colour picker's *Just for fun* section has a switch for each —
**Blossoms**, **Butterflies**, **Fireflies** (theme.js, MarsBar profile only) — kept in her
browser as `localStorage["marsbar-blossoms" | "marsbar-butterflies" | "marsbar-fireflies"] =
"off"`. garden.js reads those keys when it starts and exposes `window.Garden.set(part, on)` for
the switches; each part comes and goes live, no reload. Blossoms off puts the static bloom.svg
flower back on every card; with blossoms and fireflies both off, the `data-mb-night` /
`data-mb-dark` attributes go too (nothing else reads them). (2026-10-09: first one **Garden**
switch, `marsbar-garden = "off"`, then split into three the same day at rock's request — an old
`marsbar-garden = "off"` is read once as all three off and removed.)

- **Blossoms open and close.** Each card's crowning blossom is redrawn as inline SVG
  (`.mb-crown` in the `.widget-header`, same spot and drawing as bloom.svg) with its five
  petals rigged: every crown slowly folds into a bud and opens again on its own 20–28 s
  cycle, petals a beat apart, swaying on its stem. From **20:00 to 06:00 they stay shut**
  (`html[data-mb-night]`, re-checked every minute) and ease open in the morning. Once
  the crowns are in, `html.mb-garden` hides the old `::before` blossom. Colours are
  `--mb-h`/`--mb-h2` offsets via one hidden `svg.mbg-defs` of gradients, so her picker
  recolours them live. Cats hides the crowns (its kitten faces are on `::before`), and so
  do the other fun themes bar Sakura (their marks are on `::before`, fx.css).
- **Butterflies.** One at a time, now and then (first ~6–15 s in, then 25–70 s after the
  last leaves; never in a hidden tab): it flutters in from the left or top, lands on a
  card's vine rail, fans its wings for 9–22 s, then visits another card or flies off.
  **Tap it** and it bolts. Six hues off her purple. It sits in `.mb-sky`, a zero-size box
  at the page origin, placed by transform in page coordinates and only ever crossing the
  left/top edges — so it can never widen or lengthen the page. If its card disappears
  (her phone shows one column at a time) or moves, it flies off.
- **Fireflies** — a dozen drifting, blinking gold dots (`.mb-fireflies`) at night or when
  every light is off (the All Lights switch reads "off" → `html[data-mb-dark]`).
- ⚠ **Glance replaces `HTMLElement.prototype.animate`** (templating.js: its own
  `animate({keyframes, options}, callback)` that returns the element). Called the
  standard way it throws "callback is not a function" and the animation never
  finishes — the butterfly never landed. garden.js calls `Element.prototype.animate`,
  which is still the browser's own. Do the same in any new script that animates an
  HTML element with the Web Animations API.
- Reduced motion: crowns stand still, no butterflies or fireflies are ever made.

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
