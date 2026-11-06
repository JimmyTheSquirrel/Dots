# Home Assistant (Asgard)

**Module:** `Modules/Server/home-assistant.nix` (its own `nixosModules.home-assistant`, **not** part of `nixosModules.server`)
**Host:** Asgard only. **Port:** 8123, tailnet-only (`http://asgard:8123`)
**Version:** home-assistant 2026.5.4 (nixpkgs), deployed 2026-09-16
**State dir:** `/var/lib/hass`

Home automation — smart plugs, sensors, automations. Not to be confused with Nix
**home-manager**, which is also on Asgard (`home-manager-rock.service`) and is a completely
different thing.

## Why it is its own module

It started as a standalone file because Asgard's old monolithic `server.nix` carried uncommitted
local work and had diverged from the Sisyphus copy, and a separate module avoided patching it.
That file is gone (split into `Modules/Server/*.nix`, 2026-10-03), but the separation stays
useful: the automation side can be dropped from, or added to, a host on its own. It does lean
on `nixosModules.server` for `config.asgard` (the dashboard origins) and for `glance.service`.

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

Asgard is an **ordinary push target** — deployed from Sisyphus like every other machine:

```bash
system-rebuild rock Asgard
```

**Asgard has no clone of its own.** It used to be self-managed (`H_MODE=managed`,
building from `~/Dots` on the box, patched across with `git apply`), and that is gone:
`~/Dots` on Asgard was **deleted** 2026-10-05 and this repo is the only copy. See
`Claude/deploy.md`.

**New files still need `git add` here** — import-tree only sees git-tracked files, so an
unstaged module is silently ignored, and a flake build cannot see an untracked
`Resources/…` file or `Modules/Server/_plugs.nix` at all (eval fails "path does not
exist").

Check it evaluates first, without building:

```bash
nix eval --raw .#nixosConfigurations.rock-Asgard.config.system.build.toplevel.drvPath
```

### Validating a config change before it lands

`services.home-assistant.config` is schema-checked by HA, not by Nix, so a bad
automation evaluates and builds fine and only fails at runtime. HA's own checker will
say so first — point it at the generated file:

```bash
CFG=$(nix eval --raw '.#nixosConfigurations.rock-Asgard.config.environment.etc."home-assistant/configuration.yaml".source')
scp "$CFG" asgard:/tmp/hacheck/configuration.yaml      # in a scratch dir, not /var/lib/hass
ssh asgard '… hass --script check_config --config /tmp/hacheck --info all'
```

⚠ Two traps. It needs the **service's own `PYTHONPATH`**
(`systemctl show -p Environment home-assistant`) or every integration reports its
requirements missing; and **`colorlog` is absent from that path** while HA pins an exact
version, so the script aborts trying to `pip install` it before it parses its arguments.
Prepend a `colorlog` from the store plus a stub `colorlog-<pinned version>.dist-info`
holding just a `METADATA` with that `Version:`, and it runs. Warnings about a handful of
optional requirements (`Pillow`, `file-read-backwards`, the frontend) are artefacts of
running outside the unit — **config errors are what you are reading for**, and they name
the file and line.

## ha-bridge — live plug state for the dashboards

**Code:** `Resources/HA-Bridge/ha-bridge.py` · **unit:** `ha-bridge` · **port:** 9556 (tailnet only)
**Config:** generated from `Modules/Server/_plugs.nix` into a JSON file (`HA_BRIDGE_CONFIG`)

| Verb | What |
|---|---|
| `GET /events` | Server-Sent Events: `snapshot` on connect, then one `state` event per change, `link` when the HA connection changes, `ping` every 15s |
| `GET /states` | the snapshot as `{entity: state}` — from memory, so free to call |
| `POST /toggle/<entity>` | toggle an `ALLOWED` entity; needs `X-Dash: 1`; waits (≤2s) for HA to report the new state and returns it plus the whole snapshot |
| `POST /light/<entity>` | set a **bulb**'s colour preset and/or brightness; likewise `X-Dash: 1`. Bounded by `lights`/`presets` in the config, not by `ALLOWED` — see *The bedside bulbs* below |

**Push, not poll.** One websocket to HA (`/api/websocket`, `subscribe_entities`
filtered to the watched entities, so HA only sends what we care about) feeds the
snapshot; every dashboard holds one EventSource (`Resources/Glance/lights.js`).
Before this, every open page — MarsBar and the main Glance alike — polled `/states` every 3s
and **each poll made the bridge download HA's entire `/api/states`**. If the websocket drops, the bridge
reconnects with backoff (1s → 30s) and meanwhile polls `/api/states/<entity>` for
the watched entities only, every 10s, telling the pages (`link: polling`, shown as
"Delayed").

**Watched** = every plug relay (machines too — read-only is still worth seeing), the
Living Room Lights group, and each plug's `sensor.<slug>_power`. **Allowed** = the
group, the `light = true` plugs and the two bedside bulbs. Both come from
`_plugs.nix`; adding a plug there updates the bridge, the HA group and MarsBar's
tiles together, and adding a `bulbs` entry updates the bridge, the HA helpers and
both dashboards' swatches.

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
could read it and bypass the bridge's allowlist entirely), then briefly `0440` with a
group only Glance was in. Now it is **sops' default, root-only `0400`**, and neither
consumer reads the file itself — each gets a private copy as a systemd credential
(`LoadCredential`: systemd, as root, copies it into a per-unit directory only that unit's
DynamicUser can read):

- `ha-bridge` reads `$CREDENTIALS_DIRECTORY/ha-token`.
- `glance.service` (`Modules/Server/glance.nix`) has `HA_TOKEN_FILE` pointing at its copy,
  and the Power page's widgets send `Authorization: Bearer ${readFileFromEnv:HA_TOKEN_FILE}`
  — Glance's own config variable, expanded as text over the whole config file at startup,
  so it works inside a `headers:` map (verified against Glance 0.8.5).
- `restartUnits = ["ha-bridge.service" "glance.service"]`: a credential is copied at unit
  start (and Glance reads its config only then), so a rotated token needs both restarted.

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


## The bedside bulbs — a touch lamp, and why warm wasn't warm

Two Athom RGBCW bulbs on ESPHome, in the **bedroom touch lamps**:
`light.caitlin_bedside_lamp_rgbcw_bulb` and `light.rhys_bedside_table_rgbcw_bulb`.
Declared in `Modules/Server/_plugs.nix` under **`bulbs`** — deliberately *not* in `plugs`.

**They are not plugs.** No relay, and **no power/voltage/current/energy sensors at all**.
Everything power-related on the Glance Power page (the 24 h chart, the per-device cards,
Plug Health, the Jinja `plugQuery`) iterates `inventory.plugs`, so a bulb added to that
list would render blank rows. Added 2026-10-31.

### ⚠ Three separate problems, three different fixes

They arrived as what sounded like one bug ("it won't keep its settings", "I can't get a
deeper yellow"). It was three unrelated faults — one in a select, one in the LED dies,
one in the firmware — and fixing any one of them alone would have looked like no
progress:

**1. It came back dark.** Each bulb has a `select.<slug>_power_on_state` with options
`Always Off` / `Always On` / `Restore Power Off State`, and it **ships as "Always Off"**.
A touch lamp cuts mains at the base, so the bulb reboots on every switch-on, reads
"Always Off" and deliberately boots the light off. Nothing in HA can fix that after the
fact — the bulb is making the decision before it has a network.

Fixed by parking every one of them on **"Restore Power Off State"**, which makes the
bulb come back on, by itself, as it was — no HA involved, no delay. That value lives in
the bulb's own flash and so cannot be declared, so the `holdPowerOn` automation
re-asserts it on every HA start and any time one drifts, including after a factory reset.

**2. "Warm" was a white, and no slider could change that.**
`min_color_temp_kelvin` is **3000** — 3000 K *is* a warm white, and it is as far as the
colour-temperature scale goes on this hardware. Chasing amber with a warmth slider
cannot work; the bulb has no warmer white to give. That is not a software limit:
Athom's config sets `warm_white_color_temperature: 3000 K` because the warm **die** is a
3000 K white.

**3. The oranges were dark, and there was nothing between them and the whites.**
Found 2026-10-31, after the first two were fixed. This one was firmware.

The bulb has five dies — R, G, B, a 6500 K cold white and a 3000 K warm white — and
Athom ship it with **`color_interlock: true`**, which [per the ESPHome
docs](https://esphome.io/components/light/rgbww.html) "prevent[s] white leds being on at
the same time as RGB leds". So the bulb had two mutually exclusive modes, and HA showed
two separate pickers:

| mode | dies lit | reaches amber? | bright? |
|---|---|---|---|
| `cwww` | the two whites | **no** — 3000 K is its warmest | yes, these carry the rated 1000 lm |
| `rgb` | the three colours | yes | **no** — both white dies are switched OFF |

That is the whole of "too dark, and no in-between": there *was* no in-between, by
design. No service call could bridge it, because the firmware refused the mix. The
two-tabs UI was a symptom of this, not a UI choice.

**Fixed by reflashing with `color_interlock: "false"`** —
`Resources/ESPHome/bedside-bulb.yaml`, flashed to both bulbs 2026-10-31. All five
channels now run together, HA sees **one** combined mode
(`supported_color_modes: ["rgbww"]`), and a soft amber is warm-white-at-full with red
laid *over* it: bright and deep at once. Verified on the hardware — the bulb's own web
server reports `"color":{"r":255,"g":120,"b":0,"c":0,"w":255}`, all five channels live,
which the interlock made impossible.

See **Reflashing the bedside bulbs** below. ⚠ These presets only work on the reflashed
firmware; on a factory bulb HA silently converts them back into one mode or the other
and the darkness returns. Reflash any replacement bulb before debugging its colour.

### The presets, and where a colour is defined

`inventory.presets` in `_plugs.nix` is **the one place**. Each has a `name`, a `css`
swatch colour, and `rgbww` — the five channel values, `[r, g, b, cold, warm]`, 0-255:

| Preset | `rgbww` | |
|---|---|---|
| Candle | `255 96 0 0 35` | deepest, dim — it is a candle |
| Ember | `255 104 0 0 155` | the "super warm": redder than Amber but still bright |
| **Amber** | `255 122 0 0 110` | **the default.** Tuned on the lamps, see below |
| Honey | `255 138 0 0 140` | a touch more yellow, brighter |
| Gold | `255 152 15 0 175` | yellower again |
| Warm | `255 168 70 0 215` | warm white with a gold wash |
| Neutral | `0 0 0 120 255` | ~4300 K |
| Cool | `0 0 0 255 50` | ~6200 K, off clinical |
| **Custom** | *the five sliders* | mix your own — see below |

### ⚠⚠⚠ These were tuned on the lamps. Every attempt to derive them failed.

Three separate attempts to calculate these numbers produced three different wrong
answers, and each failure looked like a different bug. What worked was bisecting against
rock's own eyes, one variable at a time, on the real hardware. **The measured anchors**,
white removed so hue was the only variable, all at `r = 255`:

```
green 110  →  "dark orange"
green 122  →  AMBER — the one he picked
green 140  →  past it
green 160  →  "a really light green colour"
green 189  →  "yellow kinda green"
```

Then the lift, judged separately once hue was fixed: `ww 85` too dark, `ww 135` too
washed, **`ww 110`** right.

Note how violently it turns — 110 is orange, 160 is green. Two compounding reasons:

1. **`gamma_correct: 2.8`** in the firmware: `duty = (value/255)^2.8`. Mid-range values
   collapse. `g = 122` is not "about half", it drives ~12 %.
2. **The green die is several times more luminous than the red** at equal drive — green
   LEDs are efficient and the eye peaks near 555 nm. So ~12 % green already balances
   100 % red. This is the one that defeated the arithmetic: the maths was radiometric,
   the problem is perceptual.

⭐ **To retune: change ONE channel, set it on a real lamp, and look at it.** The two
bulbs are identical, so putting a different value on each and comparing side by side is
worth ten minutes of arithmetic. The whole warm range lives in **green 96–160**.

### Custom — mix your own

A ninth swatch whose colour is not fixed anywhere: it is whatever five `input_number`
sliders currently say (`bedroom_custom_red/green/blue/cold/warm`, 0–255, declared as
`customChannels` in `_plugs.nix`).

- **One shared mix, not one per bulb.** Two lamps either side of the same bed want the
  same colour, and ten sliders is not a control panel anyone would use. Tapping *Custom*
  on either lamp applies the current mix.
- ⚠ **The channel list IS an rgbww tuple** — red, green, blue, **cold**, **warm**.
  Everything zips against it positionally, so listing warm before cold silently swaps
  those two channels everywhere at once. It was written that way first, and only an ad hoc
  endpoint harness caught it. ⚠ **There is no committed test for ha-bridge** — that
  harness was a scratchpad throwaway, so the comment above `customChannels` is the only
  thing holding the order. Re-derive a harness before touching the mix path.
- **`POST /mix`** stores the five and previews on any lamp already showing *Custom*. It
  deliberately **never switches a lamp on** — moving a slider must not light the room.
  So the flow is: tap *Custom* on the lamp you want, then dial it in and watch it move.
- The sliders are ordinary HA helpers, so the mix persists across reboots, appears in the
  HA app, and rides the same stream as everything else.
- ⚠ They are **raw 0–255 channel values and are not perceptually linear** — the gamma
  above means the interesting part of the range is bunched low.

The white pair is also capped by the firmware's `constant_brightness: True` so the two
together never exceed one channel's output. The RGB three are **not** capped — that
asymmetry is what lets amber sit on top of white rather than replacing it. ⚠ Athom's own
notes advise against driving the whites and the RGB flat out together; none of these
presets does.

One service key (`rgbww_color`) for every preset is worth more than it looks. The old
table mixed `hs_color` with `color_temp_kelvin`, and because a Jinja template can choose
a *value* but never a *key*, the restore automation needed a two-branch `choose` to pick
between them. One key deleted the branch.

`name` is the key in all four consumers — the `input_select`'s options, both dashboards'
`data-ha-preset`, ha-bridge's `PRESETS`, and the restore automation's Jinja map — so one
edit moves everything. Adding a preset needs nothing else.

⚠ `css` is a **literal colour**, and it is the one exception to "HUD colours must be
`var(--hud…)`" / "marsbar.css colours are `hsl(var(--mb-h)…)`". A swatch shows what the
**lamp** will look like; recolouring it to the viewer's theme would make it a lie.

### Two layers of memory, and both were measured

The question "will it remember across a power cut?" has two answers here, and it is
worth knowing which is doing the work.

**Layer 1 — the bulb's own flash.** `restore_mode: RESTORE_DEFAULT_ON` plus
`power_on_state` = *Restore Power Off State* makes the bulb write its state to NVS and
restore it on boot, with **no network and no HA at all**. Measured 2026-10-31 by
disabling the HA automation, setting a colour the bulb had never booted into, and
rebooting it:

```
before: "brightness":158,"color":{"r":255,"g":95,"b":0,"c":0,"w":160}
after:  "brightness":158,"color":{"r":255,"g":95,"b":0,"c":0,"w":160}   ← byte-identical
```

This is the primary mechanism, and it is instant. It survived the reflash (NVS is not
touched by an OTA — the select still read *Restore Power Off State* afterwards).

**Layer 2 — Home Assistant.** A touch lamp's light is `unavailable` half the time, and an
unavailable entity has no attributes, so HA cannot read back a colour it is meant to
restore. The choice is therefore stored in HA, per bulb:

- `input_select.<slug>_preset` — the remembered colour, by name
- `input_number.<slug>_brightness` — the remembered brightness, %

Both declared in `home-assistant.nix`, generated from the inventory. They are also what
both dashboards *read* to light the right swatch and place the slider — an
`input_select`'s state is a plain string, so it rides ha-bridge's ordinary state stream
and the bridge never has to stream light attributes.

`bedroom_restore_<slug>` re-applies them 4 s after the bulb reappears (trigger: the light
leaving `unavailable`, which **is** the touch lamp being switched on; a dashboard
turn-off leaves it available, so the automation never fights someone turning a lamp off).
Also measured the same day — it fired on a reboot and restored *Warm* at exactly 51 %
(brightness 130/255, matching `input_number`).

**Why both.** They cover each other's only gaps. ESPHome defers its flash write a little,
so a cut within a second or two of a change can lose that last change — the bulb comes
back as the *previous* setting and HA corrects it 4 s later. Conversely if HA is down or
restarting when the lamp is flicked, layer 1 has already got it right on its own. Neither
needs the other to be working.

### ⚠ No `initial:` on either helper — on purpose

`initial` is re-applied on **every HA start**, which would throw the chosen colour away
on every rebuild of this module. Without it HA restores the last value from `.storage`.
The cost: a **fresh install** starts at the first option and at `min`, not at
`defaultPreset` / `defaultBrightness`. That is cosmetic, self-corrects on the first tap,
and the restore automation substitutes the proper defaults for `unknown` anyway. This is
the same class of exception as the device pairings above.

### `POST /light/<entity>` (ha-bridge)

The colour verb, alongside `/toggle`. Body `{"preset": "<name>"}`, or
`{"channels": [r, g, b, cold, warm]}` to mix one by hand, and/or
`{"brightness_pct": 1..100}`; needs `X-Dash: 1` like a toggle. It sets the bulb with
`light.turn_on` (so a swatch tapped on a dark lamp lights it), then writes the two helper
entities so the choice survives the next power cut and every open dashboard repaints.

`preset` and `channels` are **mutually exclusive** (sending both is a 400). `channels` is
the one place a caller supplies a colour rather than naming one: the five values are
validated as integers 0-255, an all-zero mix is rejected (it is just "off" by another
route), and the bulb's own preset is then set to *Custom* so the restore automation and
both dashboards agree about what is lit. `{"preset": "Custom"}` applies the five sliders
as they currently stand.

⚠ **The boundary is `lights` in the bridge config** (from `inventory.colourable`), the
same way `allowed` is the boundary for power — and it is the **only** boundary that
matters now that `channels` exists. Only those light entities accept a colour at all; a
preset must name something in `PRESETS`; and the helper ids named in the config are the
**only** `input_select`/`input_number` this process will ever write. An arbitrary colour
*can* be sent (that is the point of Custom), so do not re-derive safety from "the caller
can only pick a preset" — adding an entity to `colourable` is what grants the right to
drive its dies.

```bash
curl -s -XPOST -H 'X-Dash: 1' -H 'Content-Type: application/json' \
  -d '{"preset":"Amber","brightness_pct":70}' \
  http://localhost:9556/light/light.rhys_bedside_table_rgbcw_bulb

# the shared mix: stores the five values, previews on any lamp already on Custom,
# and deliberately never switches a lamp on
curl -s -XPOST -H 'X-Dash: 1' -H 'Content-Type: application/json' \
  -d '{"channels":[255,122,0,0,110]}' http://localhost:9556/mix
```

### Reflashing the bedside bulbs

`Resources/ESPHome/bedside-bulb.yaml` + `Resources/ESPHome/flash.sh`. The yaml is a
**six-line override** of Athom's own package — one substitution, `color_interlock:
"false"` — and the flash is an OTA over the house LAN.

#### ⚠⚠⚠ FIRST: match the config to the HARDWARE, not to its filename

`athom-tech/esp32-configs` carries **two** files for what looks like the same product,
and their GPIO-to-die maps are **different**:

| die | `athom-rgbcw-bulb.yaml` | `athom-rgbcw-light.yaml` ← **ours** |
|---|---|---|
| red | GPIO3 | GPIO6 |
| green | GPIO4 | GPIO7 |
| blue | GPIO5 | GPIO5 |
| cold white | GPIO6 | GPIO3 |
| warm white | GPIO7 | GPIO4 |

Flashing the wrong one produces a bulb that **works perfectly and is completely wrong**,
with nothing anywhere reporting an error. It connects, dims, obeys Home Assistant and
logs sensible values — while lighting the wrong LEDs. Asking for pure red drove GPIO3,
which on this hardware is the **cold white** die, so the lamp lit bright white; presets
carrying warm white drove GPIO7, the **green** die, so some came out green. ESPHome
cheerfully reported `r:255 g:0 b:0 c:0 w:0` the whole time. Done 2026-10-31, and it cost
several rounds of tuning colour values that were never the problem.

⭐ **The bulb tells you which it is.** Its `comment` is the tell and it is one curl away:

```bash
curl -sN http://192.168.0.152/events | grep -m1 comment
#  "athom esp32c3 12w rgbcw bulb"  → athom-rgbcw-light.yaml   ← these bulbs
#  "athom esp32c3 rgbcw bulb"      → athom-rgbcw-bulb.yaml
```

**Check that before flashing anything, including a replacement bulb.** If a reflashed
bulb's colours are wrong in a way that looks like bad tuning — white where you asked for
a colour, or green out of nowhere — suspect the profile before touching the values.

```bash
Resources/ESPHome/flash.sh compile          # build only
Resources/ESPHome/flash.sh flash <ip>       # one bulb
Resources/ESPHome/flash.sh flash-all        # both
```

Things worth knowing before touching it:

- **It must run somewhere on the house LAN.** The bulbs are on `192.168.0.0/24`, not the
  tailnet. Sisyphus and Asgard both reach them; `ssh asgard` works too.
- **Both bulbs take the same binary.** Athom set `name_add_mac_suffix: true`, so the node
  name is derived from each bulb's own MAC at runtime. ⚠ **Never set `name:` or
  `friendly_name:` in our override** — either would rename the node and HA would adopt it
  as a *new* device, changing every entity id in `_plugs.nix`.
- **The revision is pinned, and it has to be.** Athom's `main` bumped `min_version` to
  **2026.10.0** on 2026-10-29; the newest esphome in *any* nixpkgs is 2026.9.1 and ours
  is 2026.5.1, so `main` cannot be built here at all. The pin is **v3.2.2**
  (`43939c18…`), which asks for 2026.5.0. It is also the last revision before Athom added
  the `update:`/`http_request:` managed-update platform — don't bump the pin without
  checking what new entities arrive, since that platform lets the bulb pull firmware from
  Athom on its own.
- **It is not a Nix derivation, and cannot be.** `esphome compile` downloads its ESP-IDF
  toolchain from PlatformIO at build time. The declarative part is the yaml; the toolchain
  cache lives in `~/.cache/esphome-bedside-bulb/`.
- **Wi-Fi credentials come from sops** (`wifi-ssid`, `wifi-password`, added 2026-10-31).
  Athom's config carries none — a factory bulb is onboarded through its captive portal and
  keeps them in NVS — but an OTA replaces the whole app image, so the network is spelled
  out explicitly rather than trusting that saved copy. `flash.sh` writes a `secrets.yaml`
  into a mktemp build dir and deletes it on exit; ⚠ **the compiled binary contains the
  Wi-Fi password.**
- **What a bad flash costs:** the bulb comes up in AP mode and needs re-onboarding from a
  phone, standing at the lamp. That is the only real failure mode. Flash one bulb, confirm
  it rejoins, then do the second.
- **`power_on_state` survives** — an OTA does not touch NVS. Verified. And `holdPowerOn`
  re-asserts it 10 s later regardless.

To prove a flash landed, ask the bulb rather than HA (HA caches the old colour modes
until it reconnects, which takes ~30 s):

```bash
curl -s -N http://192.168.0.152/events | grep -m1 RGBCW_Bulb
# "color_mode":"rgbww"  and r/g/b/c/w all present = interlock is off
```

### On the dashboards

Admin Glance → **Power** page → Lights widget, under a **Bedroom** heading
(`glance.nix` → `bulbCard`). MarsBar → the Lights card, same section
(`marsbar.nix` → `bulbCard`). Each bulb gets a tile, the nine swatches and a brightness
slider; the **Mix your own** panel (`.ag-mix` / `.mb-mix`) sits once at the foot of the
section, shared by both bulbs. ⚠ The two dashboards are separate markup against the same
`data-ha-*` contract in `Resources/Glance/lights.js` — **add a control to one and it must
go in the other**, like every other shared card.

**Live on Asgard since 2026-11-01** — the colour ladder, the Custom swatch, the mix panel
and the room ring all went out in one `system-rebuild rock Asgard`; verified in the
deployed `glance.yml` and `configuration.yaml`, not just in the build.

The bedroom bulbs are **not** members of the Living Room Lights group, and should not
become members: an "All Lights" tap at 11pm must not come on in the bedroom.

## The room sensor — `sensor.asgard_temp_humidity_sensor_*`

An ESPHome temp/humidity sensor in the room **Asgard itself is in**
(`sensor.asgard_temp_humidity_sensor_temperature`, `…_humidity`; 23.7 °C / 60 % on
2026-10-31). `light.asgard_temp_humidity_sensor_light` is its own status LED, **not a
lamp** — keep it off the light tiles, and it is deliberately absent from `colourable`
so `POST /light` returns 403 for it.

**Why it exists:** Asgard is going into a **cupboard**. The point is to see how hot that
enclosed space gets and cross-reference it against the CPU and drive temps, so a thermal
problem can be caught — or something shut down — before the hardware is cooked.

### On the dashboard

Declared as **`room`** in `Modules/Server/_plugs.nix` (temp, humidity, online, plus the
ring's `floor`/`ceiling`/`warn`/`bad`), and drawn by `stats.js` as a **fourth ring in the
Asgard page's host card**, beside the CPU temperature, with **humidity** as a fact row
underneath. Written 2026-10-31, **deployed 2026-11-01** — before that it was in HA but on
no dashboard at all, which is simply why it was invisible.

Three decisions worth keeping:

- **Not a card of its own**, so the room sits beside the CPU temperature and the two can
  be read in one glance.
- ⚠ **It appears TWICE, on purpose.** As the ring, and as a plain `room temp` fact row
  immediately beside `humidity`. That is not clutter — it is how **memory** is already
  presented on this card (a ring for the proportion, a fact for the raw figure). rock went
  looking for the room temperature *in the fact list* three times running, because
  humidity is there; the two room readings belong next to each other. **Don't "tidy" one
  of them away.**
- ⚠ **The ring's label is "Room temp", not "Room".** It was "Room" at first, directly
  beside "CPU temp", and simply did not read as a temperature. Keep the labels parallel.
- ⚠ **The room's own numbers, and nothing derived.** A `cpu over room` delta row was
  added here and **removed the same day at rock's request** — he asked for the room
  temperature, not a computed figure. Don't reintroduce it on the dashboard. The delta is
  still the right thing to reason about when the cupboard move happens, but that belongs
  in `Claude/next-up.md`, not on the card.
- **It rides the ha-bridge stream, it does not poll.** The three entities are in
  `inventory.watched`, so they arrive on the SSE connection `lights.js` already holds
  open, and `stats.js` picks them up from the `ha:state` event it dispatches.

  ⚠ **TWO things have to be true, and missing either leaves the ring at "–":**
  1. The entity is in **`inventory.watched`** — ha-bridge publishes nothing else.
  2. The page carries **`data-ha-watch`** — `lights.js` only opens its EventSource on a
     page where something asks for it, and its start gate used to be light tiles only
     (`[data-ha-entity],[data-ha-toggle]`). **The Asgard page has no light tile**, so the
     stream never opened there and the ring sat stale even though the sensor was in
     `watched`. Fixed by widening the gate and giving `liveCard` an **`haStream = true`**
     flag, which puts `data-ha-watch` on the outer widget div (no script repaints that,
     so it cannot be morphed away). Both bugs were hit in sequence on 2026-10-31 — the
     second looked exactly like the first.

  `SELECTOR` in lights.js is the start gate and **only** the start gate; it is never
  used to choose elements to paint, which is why widening it is safe.
  This also means **asgard-stats never gets an HA token**: it reads the machine, HA reads
  the room, and the page puts them side by side. One fewer holder of an admin token.
- **Read-only, by construction.** `room` is in `watched` and nothing else. It must never
  reach `toggleable` or `colourable`.

Its own axis is 10-40 °C rather than the CPU ring's 25-100 °C — on the CPU's scale a room
sits motionless at the bottom. `warn`/`bad` are **30/35 °C and are a first guess**, to be
replaced by measurement once Asgard is actually in the cupboard; see `Claude/next-up.md`.
A reading that is not a number nulls the ring rather than drawing 0 — a 0 °C cupboard
would be a lie — and a sensor reporting offline is drawn with the word *stale* under it,
never as a cold room.

## Glance

HA is a monitor in the main Glance's **All** and **Management** tabs — one entry in the
`services` list in `Modules/Server/glance.nix`. The **Power** page (was Monitoring) renders its
first frame from HA's `/api/template` with one generated Jinja query (`plugQuery`); after that
everything on it is live from ha-bridge's stream — `lights.js` for the switches, `asgard.js`
for the figures (it listens to lights.js's `ha:state` events).

**What ha-bridge watches** (`watched` in `_plugs.nix`): every relay, and per plug its power,
voltage, current, today's energy, wifi signal (% and dBm) and `binary_sensor.<slug>_status`
— so V, A, kWh/cost today, signal and "plug online" move live, not just the watts. Watched is
read-only; `toggleable` (ALLOWED) is still only the lamps and their group.

**`GET /history`** (ha-bridge) — the Power page's 24 h chart: HA's
`/api/history/period/…` for every plug's power sensor (`history` in the bridge config),
bucketed to 10-minute **time-weighted** averages (a reading holds until the next, so a
1-minute blip in an hour barely moves the bucket; unknown/unavailable is a gap, never a
zero). Fetched only when a page asks, cached 2 minutes, one HA query however many tabs ask.

⚠️ HA returns **302** on `/` until onboarding is finished. If Glance shows it down, either
complete onboarding (after which `/` is 200) or add `alt-status-codes = [ 302 ];` to its entry.

## ⚠ Power cost maths — never divide an ESPHome counter by a wall clock

Fixed 2026-09-19 after a reboot made every cost on the (then) Monitoring page absurd:
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

Tunables live in the `let` block of `Modules/Server/glance.nix`: `powerRate` (0.3041 $/kWh,
the GloBird *balance* rate), `powerRefW` (150 W draw-bar ceiling),
`powerSupplyDaily`. The same `W * 0.024` arithmetic runs twice — in the Jinja (first paint)
and in `Resources/Glance/asgard.js` (live, from the bridge's power sensors) — keep them in step.
Until 2026-10-03 the cards were labelled **"Avg Daily"** with a caveat that the figure "firms
up as it runs"; it never could, and both are gone.

## Not done yet

- No Cloudflare tunnel route; tailnet-only by design.
- No backup of `/var/lib/hass` — and it is the *only* place device pairings exist.
- `upnp` and `cast` components not built in, so discovery logs a harmless `UnknownHandler` for
  the router and any Chromecast device. Add them to `extraComponents` to silence it.
