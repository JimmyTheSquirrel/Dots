{ ... }: {
  # Asgard — the Glance dashboard (port 8888): its whole config (pages and
  # widgets, built as a Nix attrset), the assets it serves from
  # Resources/Glance/ (Yggdrasil banner, stylesheet, scripts), and the native
  # unit that runs it.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    # The one plug inventory — the light tiles, the power cards, Plug Health and
    # the Jinja query below are all generated from it. See Modules/Server/_plugs.nix.
    inventory = import ./_plugs.nix;

    # Short name every dashboard link and monitor uses ("asgard"). MagicDNS
    # resolves it for the browser and for Glance's own server-side monitor
    # checks alike.
    host = builtins.head (lib.splitString "." config.asgard.tailnetFqdn);
    at = port: "http://${host}:${toString port}";

    bridgePort = 9556; # ha-bridge (Modules/Server/home-assistant.nix) — light state
    netPort = 9555;    # network-panel (network.nix) — throughput + speed test
    statsPort = 9552;  # asgard-stats (stats.nix) — the live Asgard / Storage / Now Playing cards
    tsPort = 9553;     # tailscale-status-proxy (network.nix) — the tailnet list
    haPort = 8123;     # Home Assistant — the power figures (/api/template)
    sabPort = 8080;    # SABnzbd, via the socat proxy into the Mullvad namespace
    eclipsePort = 9554; # eclipse-control (eclipse.nix) — the Eclipse page
    jellyfinPort = 8096; # also where Now Playing's posters load from

    # ── Assets (served at /assets/) ─────────────────────────────────────────
    # The CSS and JS live in real files, not in Nix strings inside the YAML.
    # They used to be ~900 lines of a `document.head: |` block scalar, where a
    # single mis-indented line silently ends the scalar and breaks the whole
    # config (see Claude/marsbar.md). Same pattern as MarsBar.
    #
    # lights.js is SHARED with MarsBar — one push client, so both dashboards
    # behave the same and a fix lands on both. dash.js is the helpers the
    # live cards share (stream lifecycle, DOM morphing, sparklines).
    assetFiles = {
      "yggdrasil.png" = ../../Resources/Glance/yggdrasil-banner.png;
      "asgard.css" = ../../Resources/Glance/asgard.css;
      "cards.css" = ../../Resources/Glance/cards.css;
      "dash.js" = ../../Resources/Glance/dash.js;
      "lights.js" = ../../Resources/Glance/lights.js;
      "asgard.js" = ../../Resources/Glance/asgard.js;
      "stats.js" = ../../Resources/Glance/stats.js;
      "net.js" = ../../Resources/Glance/net.js;
      "eclipse.js" = ../../Resources/Glance/eclipse.js;
      "theme.js" = ../../Resources/Glance/theme.js;
    };
    # The HUD's artwork — the panel frame round every card, the grid that
    # tiles down the page, the misty pines pinned to the foot of the screen,
    # Yggdrasil in line art, the logo, the icon set — is GENERATED at build
    # time by hud.py (seeded, so every build draws the same; see its header).
    # Nothing generated is committed. Its hud.css hands the pieces to
    # asgard.css with this version on every URL, so a new HUD is never hidden
    # behind Glance's 2 h asset cache.
    hudVersion = builtins.substring 0 10 (builtins.hashFile "sha256" ../../Resources/Glance/hud.py);
    hud = pkgs.runCommand "asgard-hud" { } ''
      ${pkgs.python3}/bin/python3 ${../../Resources/Glance/hud.py} $out ${hudVersion}
    '';
    # Orbitron (titles, tags, the navigation), from nixpkgs — asgard.css's @font-face.
    fontFiles = {
      "fonts/orbitron-bold.ttf" = "${pkgs.orbitron}/share/fonts/truetype/Orbitron Bold.ttf";
      "fonts/orbitron-medium.ttf" = "${pkgs.orbitron}/share/fonts/truetype/Orbitron Medium.ttf";
    };
    glanceAssets = pkgs.linkFarm "glance-assets" (assetFiles // fontFiles // { inherit hud; });

    # Glance serves /assets/ with a 2h Cache-Control, so a script URL that never
    # changes would keep running the OLD code for up to two hours after a
    # deploy. The content hash makes every edit a new URL. (custom-css-file needs
    # no help: Glance stamps that one with its own start time.)
    asset = name:
      "/assets/${name}?v=${builtins.substring 0 10 (builtins.hashFile "sha256" assetFiles.${name})}";

    # ── Power page tunables ──
    #
    # Electricity tariff in $/kWh — REAL, from the GloBird GLOSAVE offer
    # (NSW / Ausgrid), replacing the earlier guess of 0.32.
    #
    # The plan is stepped, not flat:
    #   first 15.00 kWh/day   $0.28600  →  $0.27742 after discounts
    #   balance (>15/day)     $0.31350  →  $0.30410 after discounts
    # "after discounts" = the 1% direct-debit + 2% pay-on-time conditional
    # discounts, which apply to usage AND the daily supply charge.
    #
    # The BALANCE rate is the correct one here, because these figures answer
    # "what does this device cost me" — a marginal question. Billing for the
    # 28 days to 24-Aug-2026 averaged 16.81 kWh/day, comfortably over the 15
    # kWh step, so every additional kWh a plug draws is charged at the balance
    # rate. ⚠ If daily household use ever drops below 15 kWh, the marginal rate
    # becomes 0.27742 instead and this should follow it.
    powerRate = "0.3041";

    # Daily supply charge, $/day, after the same 3% conditional discounts
    # ($0.95700 before). Deliberately NOT folded into powerRate: it is billed
    # whether or not a single device is plugged in, so attributing any of it to
    # a plug's consumption would be wrong. Shown on its own row for context,
    # because per-device costs alone understate the actual bill.
    #
    # (Both are strings so they reach Jinja and the page exactly as written —
    # Nix's toString on a float pads it to six places.)
    powerSupplyDaily = "0.92829";

    # ════════════════════════════════════════════════════════════════════════
    # SERVICES — the one list behind every monitor on the dashboard
    # ════════════════════════════════════════════════════════════════════════
    # Service health used to spell each service out twice — once in "All", once
    # in its category tab — plus a third copy on the (since removed) Downloads
    # page, so adding a service meant three edits that could drift. Now:
    #   tab     its category tab (it is always in "All" too)
    # Every one of these is a live unit in Modules/Server/ or home-assistant.nix;
    # the metrics stack, Kavita and Komga were removed along with their monitors.
    #
    # There is deliberately NO bookmarks column: monitor rows are already
    # clickable, and a sidebar repeating them was most of why the page scrolled.
    # Add a service HERE, not to a sidebar.
    #
    # Icons: `sh:` (selfh.st, coloured) where it has one, a CDN URL otherwise.
    # Avoid `si:` — monochrome.
    services = [
      { title = "Jellyfin";       port = jellyfinPort; icon = "sh:jellyfin";       tab = "Media"; }
      { title = "Jellyseerr";     port = 5055;  icon = "sh:jellyseerr";     tab = "Media"; }
      { title = "Immich";         port = 2283;  icon = "sh:immich";         tab = "Media"; }
      { title = "Audiobookshelf"; port = 13378; icon = "sh:audiobookshelf"; tab = "Media"; }
      { title = "SABnzbd";        port = sabPort; icon = "sh:sabnzbd";      tab = "Downloads"; }
      { title = "Prowlarr";       port = 9696;  icon = "sh:prowlarr";       tab = "Downloads"; }
      { title = "Sonarr";         port = 8989;  icon = "sh:sonarr";         tab = "Arr"; }
      { title = "Radarr";         port = 7878;  icon = "sh:radarr";         tab = "Arr"; }
      { title = "Lidarr";         port = 8686;  icon = "sh:lidarr";         tab = "Arr"; }
      { title = "Shelfarr";       port = 5056;  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/shelfarr.svg"; tab = "Arr"; }
      { title = "Suwayomi";       port = 4567;  icon = "sh:suwayomi";       tab = "Media"; }
      { title = "FileBrowser";    port = 8081;  icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/filebrowser.svg"; tab = "Management"; }
      # Answers 302 on / until HA's onboarding is finished; add
      # `alt-status-codes = [ 302 ];` to its site if it ever shows down on a fresh box.
      { title = "Home Assistant"; port = haPort; icon = "sh:home-assistant"; tab = "Management"; }
    ];
    tabs = [ "Media" "Downloads" "Arr" "Management" ];

    # A 1m cache: these are local HTTP GETs and a minute is as fresh as "is it
    # up" needs. The "All" tab repeating the category tabs costs one more GET
    # per service per minute, and only while someone has the page open.
    monitor = title: list: {
      type = "monitor";
      inherit title;
      cache = "1m";
      sites = map (s: { inherit (s) title icon; url = at s.port; }) list;
    };

    # ════════════════════════════════════════════════════════════════════════
    # LIGHTS + POWER — markup for lights.js / asgard.js
    # ════════════════════════════════════════════════════════════════════════
    # The data-ha-* attributes are the contract with Resources/Glance/lights.js
    # (documented at the top of that file): every element carrying
    # data-ha-entity gets data-ha-state repainted live from ha-bridge's /events
    # stream; a data-ha-toggle element toggles on click. The data-ag-* ones are
    # asgard.js's (live watts, sums, projections — see the top of that file).
    #
    # Every element renders its REAL state server-side into data-ha-state, so a
    # tile is right on first paint and nothing jumps when the stream connects.
    #
    # Only `light = true` plugs ever get a data-ha-toggle. The machines'
    # relays (Asgard, Eclipse) are drawn locked — and ha-bridge's allowlist,
    # derived from the same inventory, is what actually refuses them.
    lamps = inventory.lights;
    machines = inventory.machines;
    # Each plug's data-palette slot (--s1…--s5 in asgard.css), by inventory
    # order: the colour of its band on the 24 h chart, its legend chip and the
    # stripe down its card — the same plug, visibly, in all three places.
    slotOf = p: toString (1 + lib.lists.findFirstIndex (q: q.slug == p.slug) 0 inventory.plugs);
    dev = p: ''style="--dev: var(--s${slotOf p})"'';
    sensor = p: name: "sensor.${p.slug}_${name}";
    group = inventory.group;
    spaced = lib.concatStringsSep " ";
    powerOf = ps: spaced (map (p: p.power) ps);
    lampRelays = spaced (map (p: p.entity) lamps);
    allPower = powerOf inventory.plugs;
    lampCount = toString (builtins.length lamps);

    # Keys in ha-bridge's /states map are entity ids, and Glance resolves
    # `.JSON.*` paths with gjson, where a dot means "nested". Escaping it makes it
    # a literal key; `\\.` because the Go string literal unescapes it once.
    # (Same as stateOf in Modules/Server/marsbar.nix.)
    key = entity: builtins.replaceStrings [ "." ] [ "\\\\." ] entity;
    bridgeState = entity: ''{{ .JSON.String "${key entity}" }}'';
    bridgeWatts = entity: ''(.JSON.Float "${key entity}")'';

    # The master switch's toggle moves every lamp, so lights.js flips them
    # optimistically with it.
    members = ''data-ha-members="${spaced group.members}"'';

    # One light tile — a <button>, so it is focusable and the whole tile is the
    # tap target. `state` and `sub` are Go-template snippets.
    lightTile = { entity, name, icon, sub, state, extra ? "", hero ? false }: ''
      <button type="button" class="ag-light${lib.optionalString hero " ag-hero"}" data-ha-entity="${entity}" data-ha-toggle ${extra} data-ha-state="${state}">
        <span class="ag-ico" aria-hidden="true">${icon}</span>
        <span class="ag-txt"><span class="ag-name">${name}</span><span class="ag-sub">${sub}</span></span>
        <span class="ag-right"><span class="ag-state"></span><span class="ag-sw" aria-hidden="true"></span></span>
      </button>
    '';

    # Live-link badge (lights.js paints it), parked in the widget's header row.
    liveBadge = ''
      <span class="ag-live ag-live-corner" aria-live="polite"><i></i><span data-ha-link-label>Connecting…</span></span>
    '';

    # "2 of 3 on" and the lamps' combined watts, server-rendered from the
    # bridge's snapshot; asgard.js keeps both live.
    bridgeOnCount = ''{{ $on := 0 }}${lib.concatMapStrings (p: ''{{ if eq (.JSON.String "${key p.entity}") "on" }}{{ $on = add $on 1 }}{{ end }}'') lamps}{{ $on }} of ${lampCount} on'';
    bridgeLampWatts = ''{{ printf "%.1f" ${lib.foldl (acc: p: "(add ${acc} ${bridgeWatts p.power})") "0.0" lamps} }}'';

    # The lights, first thing on the Power page — every lamp, its switch and
    # its draw in one place with the rest of the power controls.
    # Two sections, so the master switch can never be mistaken for a lamp:
    # GROUPS (the Living Room Lights group — every lamp at once) and LAMPS.
    lightsCard = ''
      ${liveBadge}
      <div class="ag-sec">Groups</div>
      <div class="ag-lights ag-groups">
        ${lightTile {
          inherit (group) entity name;
          icon = "✦";
          hero = true;
          extra = members;
          state = bridgeState group.entity;
          sub = ''<span data-ag-on="${lampRelays}">${bridgeOnCount}</span> · <span data-ag-sum="${powerOf lamps}">${bridgeLampWatts}</span> W'';
        }}
      </div>
      <div class="ag-sec">Lamps</div>
      <div class="ag-lights">
        ${lib.concatMapStrings (p: lightTile {
          inherit (p) entity name icon;
          state = bridgeState p.entity;
          sub = ''${p.room} · <span data-ag-w="${p.power}">{{ printf "%.1f" ${bridgeWatts p.power} }}</span> W'';
        }) lamps}
      </div>
    '';

    # ── The shared power query (Power page) ────────────────────────────────
    # ONE Jinja template, generated from the inventory, that every Power-page
    # widget POSTs to HA's /api/template. HA renders it server-side and answers
    # JSON: per-plug figures keyed by slug, plus the totals and projections.
    # The four widgets used to carry four hand-written copies with their own
    # plug lists, and those had drifted (three spellings of the fairy lights),
    # along with variables computed and never used — exactly the kind that
    # invite a wrong "average" back in.
    #
    # Each widget picks what it needs from the same answer; the unused fields
    # cost a few hundred bytes over localhost.
    #
    # Each plug is an Athom Plug V3 (ESPHome), every entity named off one slug:
    #   sensor.<slug>_power               — real power, W
    #   sensor.<slug>_voltage / _current  — V / A
    #   sensor.<slug>_apparent_power      — VA
    #   sensor.<slug>_power_factor        — real ÷ apparent
    #   sensor.<slug>_total_daily_energy  — kWh, resets at midnight (and on plug restart)
    #   sensor.<slug>_total_energy        — kWh since the plug booted
    #   sensor.<slug>_uptime_sensor       — plug boot timestamp
    #   sensor.<slug>_wifi_signal_*       — % and dBm
    #   binary_sensor.<slug>_status       — is the plug itself reachable
    #   switch.<slug>_switch              — THE RELAY
    #
    # ⚠ NEVER derive the daily average from `total_energy / uptime_sensor`.
    # That was the original approach and it breaks hard: the two counters do
    # NOT reset together. Rebooting Asgard on 2026-09-19 reset the uptime
    # while the energy counter kept accumulating, so the maths divided days
    # of kWh by 5 hours — 2.165 kWh / 5.5 h * 24 = 9.45 kWh/day, and a box
    # actually drawing 35.5 W (~$95/yr) was projected at $1047/yr. The error
    # is silent and plausible-looking, which is the dangerous part.
    #
    # `total_daily_energy` is NOT a safe substitute either — that was tried
    # next and also wrong. It resets on device restart as well as at midnight,
    # so after the same reboot it held 5.5 h of energy while hours-since-
    # midnight said 22 h, under-reporting Asgard at $43/yr against a true
    # ~$149/yr. Both cumulative counters reset on restart; anything derived
    # from one divided by a clock will silently break the next time the plug
    # blips.
    #
    # The projections therefore come from INSTANTANEOUS power (W * 0.024 =
    # kWh/day). It is a snapshot rather than a measured average, so it moves
    # with load — but it is always internally consistent and cannot lie by an
    # order of magnitude. Label these "at current draw", NEVER "average" or
    # "avg daily": the cards did say "Avg Daily" until 2026-10-03, with a caveat
    # claiming the figure "firms up as it runs", which it never could. A real
    # average would need HA's long-term statistics API, out of reach from
    # Jinja. The same arithmetic runs live in asgard.js; keep the two in step.
    #
    # ⚠ `total_energy` is NOT a lifetime total, despite the entity name.
    # The ESPHome counter restarts whenever the plug power-cycles. Checked
    # 2026-09-17: the plug's boot timestamp matched Asgard's `uptime` to the
    # minute, i.e. that plug restart hard-cut the server. It is labelled
    # "since plug boot" with a relative stamp for that reason — the old
    # "LIFETIME USAGE" label made a 75-minute sample read as months of data.
    #
    # Rows are serialised with HA's `to_json` rather than glued together from
    # strings, so a stray quote can never produce invalid JSON. (Display names
    # stay out of it anyway — Nix writes them straight into the markup.)
    j = builtins.toJSON; # a Nix string as a Jinja (= JSON) string literal
    plugQuery = ''
      {%- set r = ${powerRate} %}
      {%- set ns = namespace(rows=[], now=0, today=0, machines=0, lights=0, lit=0) %}
      {%- for slug, relay, light in [${lib.concatMapStringsSep ", " (p: "(${j p.slug}, ${j p.entity}, ${lib.boolToString p.light})") inventory.plugs}] %}
      {%- set s = 'sensor.' ~ slug ~ '_' %}
      {%- set p = states(s ~ 'power')|float(0) %}
      {%- set today = states(s ~ 'total_daily_energy')|float(0) %}
      {%- set pf = states(s ~ 'power_factor')|float(0) %}
      {%- set ns.now = ns.now + p %}
      {%- set ns.today = ns.today + today %}
      {%- if light %}
      {%- set ns.lights = ns.lights + p %}
      {%- set ns.lit = ns.lit + (1 if states(relay) == 'on' else 0) %}
      {%- else %}
      {%- set ns.machines = ns.machines + p %}
      {%- endif %}
      {%- set row = {
        "state": states(relay),
        "online": states('binary_sensor.' ~ slug ~ '_status'),
        "power": p|round(1),
        "voltage": states(s ~ 'voltage')|float(0)|round(1),
        "current": states(s ~ 'current')|float(0)|round(3),
        "apparent": states(s ~ 'apparent_power')|float(0)|round(1),
        "pf": pf|round(2),
        "pf_pct": (pf * 100)|round(0),
        "today_kwh": today|round(3),
        "today_cost": (today * r)|round(2),
        "total_kwh": states(s ~ 'total_energy')|float(0)|round(3),
        "kwh_day": (p * 0.024)|round(2),
        "year_cost": (p * 0.024 * r * 365)|round(0),
        "signal": states(s ~ 'wifi_signal_percent')|float(0)|round(0),
        "rssi": states(s ~ 'wifi_signal_db')|float(0)|round(0),
        "ip": states(s ~ 'ip_address'),
        "onstate": states('select.' ~ slug ~ '_power_on_state'),
        "since": states(s ~ 'uptime_sensor')
      } %}
      {%- set ns.rows = ns.rows + ['"' ~ slug ~ '": ' ~ (row|to_json)] %}
      {%- endfor %}
      {%- set day = ns.now * 0.024 %}
      {"rate": {{ r }}, "supply_year": {{ (${powerSupplyDaily} * 365)|round(0) }},
       "group": {{ states(${j group.entity})|to_json }},
       "now": {{ ns.now|round(1) }}, "machines": {{ ns.machines|round(1) }},
       "lights": {{ ns.lights|round(1) }}, "lit": {{ ns.lit }},
       "today_cost": {{ (ns.today * r)|round(2) }},
       "day": {{ (day * r)|round(2) }}, "week": {{ (day * r * 7)|round(2) }},
       "month": {{ (day * r * 30.44)|round(2) }}, "year": {{ (day * r * 365)|round(0) }},
       "month_kwh": {{ (day * 30.44)|round(1) }},
       "plugs": {{ '{' ~ ns.rows|join(', ') ~ '}' }}}
    '';

    # A custom-api widget asking HA that question. The token is Glance's
    # readFileFromEnv variable (a systemd credential — systemd.services.glance
    # below), so it never touches the Nix store.
    #
    # Widgets render server-side once per page load — Glance 0.8.5 has no
    # client-side widget refresh, so `cache:` only affects the NEXT load. What
    # moves while the page is open (relays, watts, sums, projections) is
    # lights.js + asgard.js working from ha-bridge's stream.
    powerWidget = { title, cache, template }: {
      type = "custom-api";
      inherit title cache template;
      url = "http://localhost:${toString haPort}/api/template";
      method = "POST";
      body-type = "json";
      headers.Authorization = "Bearer \${readFileFromEnv:HA_TOKEN_FILE}";
      body.template = plugQuery;
    };

    # Go-template accessors into that answer.
    pf = path: fmt: ''{{ printf "${fmt}" (.JSON.Float "${path}") }}'';
    ps = path: ''{{ .JSON.String "${path}" }}'';
    plug = p: field: "plugs.${p.slug}.${field}";

    stat = label: value: ''<div class="ag-cell"><span class="ag-k">${label}</span><span class="ag-v">${value}</span></div>'';
    unit = u: ''<span class="ag-u">${u}</span>'';

    # "1.36 kWh/day · $151/yr", live. Instantaneous draw × 24 h — see the
    # warning above plugQuery; the label beside it always says "at current draw".
    atDraw = sensors: kwh: year: ''<span data-ag-kwh="${sensors}" data-ag-days="1" data-ag-dp="2">${kwh}</span> ${unit "kWh/day"} · <span data-ag-cost="${sensors}" data-ag-days="365" data-ag-dp="0" data-ag-rate="${powerRate}">${year}</span>${unit "/yr"}'';

    # The relay's state word + switch. Lamps: a real toggle. Machines: the same
    # switch, locked — no data-ha-toggle, so lights.js never sends anything.
    relayControl = p: ''
      <span class="ag-card-ctl" data-ha-entity="${p.entity}" data-ha-state="${ps (plug p "state")}">
        <span class="ag-state"></span>
        ${if p.light
          then ''<button type="button" class="ag-sw" data-ha-entity="${p.entity}" data-ha-toggle data-ha-state="${ps (plug p "state")}" aria-label="${p.name}"></button>''
          else ''<span class="ag-sw" aria-disabled="true" role="img" aria-label="Relay locked" title="Locked — ha-bridge refuses this relay outright"></span>''}
      </span>
    '';

    # When the plug last booted, ticking client-side ("31h ago").
    sinceBoot = p: ''{{ $since := .JSON.String "${plug p "since"}" }}{{ if and (ne $since "unknown") (ne $since "unavailable") }}<span {{ $since | parseRelativeTime "rfc3339" }}></span> ago{{ else }}—{{ end }}'';

    # ── Machines: Asgard and Eclipse ──
    # Monitored in full, relay locked. Both are running computers — cutting
    # mains means an unclean stop (Asgard: its own feed, mid-write).
    # Live: every figure carrying a data-ag-* attribute is repainted by
    # asgard.js from ha-bridge's stream (it watches V, A, today's kWh and the
    # wifi signal too — _plugs.nix); the rest are slow-moving page-load values.
    live = p: name: dp: value: ''<span data-ag-val="${sensor p name}" data-ag-dp="${toString dp}">${value}</span>'';
    todayCost = p: ''<span data-ag-energy="${sensor p "total_daily_energy"}" data-ag-rate="${powerRate}" data-ag-dp="2">${pf (plug p "today_cost") "$%.2f"}</span>'';

    machineCard = p: ''
      <details class="ag-card" ${dev p} data-ha-entity="${p.entity}" data-ha-state="${ps (plug p "state")}">
        <summary class="ag-card-head">
          <span class="ag-card-top">
            <span class="ag-chev" aria-hidden="true"></span>
            <span class="ag-card-id"><span class="ag-card-name">${p.name}</span><span class="ag-card-sub">${p.sub}</span></span>
            ${relayControl p}
          </span>
          <span class="ag-card-stats">
            <span class="ag-mini"><span class="ag-k">Now</span><span class="ag-v"><span data-ag-w="${p.power}">${pf (plug p "power") "%.1f"}</span> ${unit "W"}</span></span>
            <span class="ag-mini"><span class="ag-k">At current draw</span><span class="ag-v">${atDraw p.power (pf (plug p "kwh_day") "%.2f") (pf (plug p "year_cost") "$%.0f")}</span></span>
          </span>
        </summary>
        <div class="ag-card-body">
          <div>
            <div class="ag-sec">Electrical</div>
            <div class="ag-grid">
              ${stat "Voltage" "${live p "voltage" 1 (pf (plug p "voltage") "%.1f")} ${unit "V"}"}
              ${stat "Current" "${live p "current" 3 (pf (plug p "current") "%.3f")} ${unit "A"}"}
              ${stat "Apparent" "${pf (plug p "apparent") "%.1f"} ${unit "VA"}"}
              ${stat "Power factor" (pf (plug p "pf") "%.2f")}
            </div>
          </div>
          {{ if gt (.JSON.Float "${plug p "apparent"}") 0.0 }}
          <div>
            <div class="ag-sec">Real vs apparent</div>
            <div class="pw-pf-bar"><div class="pw-pf-fill" style="width: {{ printf "%.0f" (.JSON.Float "${plug p "pf_pct"}") }}%"></div></div>
            <div class="pw-pf-legend">
              <span class="pw-lg-real">${pf (plug p "power") "%.1f"} W real</span>
              <span class="pw-lg-reactive">${pf (plug p "apparent") "%.1f"} VA drawn</span>
            </div>
          </div>
          {{ end }}
          <div>
            <div class="ag-sec">Energy</div>
            <div class="ag-grid">
              ${stat "Used today" "${live p "total_daily_energy" 3 (pf (plug p "today_kwh") "%.3f")} ${unit "kWh"}"}
              ${stat "Cost today" (todayCost p)}
              ${stat "Since plug boot" "${pf (plug p "total_kwh") "%.3f"} ${unit "kWh"}"}
              ${stat "Plug booted" (sinceBoot p)}
              ${stat "On power loss" (ps (plug p "onstate"))}
            </div>
          </div>
          <div class="ag-note"><b>Relay locked.</b> A running machine — ha-bridge refuses this entity outright, so a stray request cannot cut it mid-write either.</div>
          <div class="ag-note">
            "Since plug boot" is not a lifetime total: the plug's counter restarts on every power-cycle.
            "At current draw" is the live wattage × 24 h — a projection that moves with load, not a measured average.
          </div>
        </div>
      </details>
    '';

    # ── Lamps ──
    lampCard = p: ''
      <details class="ag-card" ${dev p} data-ha-entity="${p.entity}" data-ha-state="${ps (plug p "state")}">
        <summary class="ag-card-head">
          <span class="ag-card-top">
            <span class="ag-chev" aria-hidden="true"></span>
            <span class="ag-card-id"><span class="ag-card-name">${p.name}</span><span class="ag-card-sub">${p.sub} · <span data-ag-w="${p.power}">${pf (plug p "power") "%.1f"}</span> W now</span></span>
            ${relayControl p}
          </span>
          <span class="ag-card-stats">
            <span class="ag-mini"><span class="ag-k">At current draw</span><span class="ag-v">${atDraw p.power (pf (plug p "kwh_day") "%.2f") (pf (plug p "year_cost") "$%.0f")}</span></span>
            <span class="ag-mini"><span class="ag-k">Since plug boot</span><span class="ag-v">${pf (plug p "total_kwh") "%.3f"} ${unit "kWh"}</span></span>
          </span>
        </summary>
        <div class="ag-card-body">
          <div class="ag-grid">
            ${stat "Voltage" "${live p "voltage" 1 (pf (plug p "voltage") "%.1f")} ${unit "V"}"}
            ${stat "Used today" "${live p "total_daily_energy" 3 (pf (plug p "today_kwh") "%.3f")} ${unit "kWh"}"}
            ${stat "Cost today" (todayCost p)}
            ${stat "Signal" "${live p "wifi_signal_percent" 0 (pf (plug p "signal") "%.0f")} ${unit "%"}"}
            ${stat "Address" (ps (plug p "ip"))}
            ${stat "On power loss" (ps (plug p "onstate"))}
            ${stat "Plug booted" (sinceBoot p)}
          </div>
        </div>
      </details>
    '';

    allEnergy = spaced (map (p: sensor p "total_daily_energy") inventory.plugs);

    # ── Power: the whole house now, who is drawing it, and the last 24 h ──
    # The hero, the share bar and the chips are live (ha-bridge's stream). The
    # chart is ONE line — the house's total — drawn by asgard.js from
    # ha-bridge's GET /history; hovering it breaks any moment down by plug.
    # (It was a stacked band per plug, which read as clutter.) The legend chips
    # double as the series list (data-e / data-n / data-c, inventory order).
    shareSeg = p: ''<i data-ag-seg="${p.power}" title="${p.name}" style="--dev: var(--s${slotOf p}); flex-grow: {{ printf "%.1f" (.JSON.Float "${plug p "power"}") }}"></i>'';
    powerOverview = powerWidget {
      title = "Power";
      cache = "30s";
      template = ''
        <div class="pw">
          <div class="pw-hero">
            <div><span class="pw-big" data-ag-sum="${allPower}">{{ printf "%.1f" (.JSON.Float "now") }}</span><span class="pw-big-unit">W</span></div>
            <div class="pw-trail">
              machines <b><span data-ag-sum="${powerOf machines}">{{ printf "%.1f" (.JSON.Float "machines") }}</span> W</b> ·
              lights <b><span data-ag-sum="${powerOf lamps}">{{ printf "%.1f" (.JSON.Float "lights") }}</span> W</b><br>
              today so far <b data-ag-energy="${allEnergy}" data-ag-rate="${powerRate}" data-ag-dp="2">${pf "today_cost" "$%.2f"}</b> ·
              at this rate <b data-ag-cost="${allPower}" data-ag-days="365" data-ag-dp="0" data-ag-rate="${powerRate}">${pf "year" "$%.0f"}</b>/yr
            </div>
          </div>
          <div class="pw-share" aria-label="Share of the draw, by plug">${lib.concatMapStrings shareSeg inventory.plugs}</div>
          <div class="pw-legend">
            ${lib.concatMapStrings (p: ''<span class="pw-chip" ${dev p} data-e="${p.power}" data-n="${p.name}" data-c="var(--s${slotOf p})"><i></i>${p.short} <b><span data-ag-w="${p.power}">${pf (plug p "power") "%.1f"}</span> W</b></span>'') inventory.plugs}
          </div>
          <div class="ag-sec">Last 24 hours<span class="ag-sec-end" id="pw-stats"></span></div>
          <div class="pw-chart" id="pw-chart"><div class="ags-skel" style="height:120px"></div></div>
          <div class="pw-axis"><span>24 h ago</span><span>18 h</span><span>12 h</span><span>6 h</span><span>now</span></div>
        </div>
      '';
    };

    # ── Devices: one card per plug, machines first ──
    # The lamps' own toggles live on their cards; the all-lights master switch
    # is on the home page only (it used to be repeated here as "Power
    # Switches"). 1s cache: a stale relay position would visibly flip a moment
    # after load when the stream corrects it.
    powerDevices = powerWidget {
      title = "Devices";
      cache = "1s";
      template = ''
        ${liveBadge}
        <div class="ag-cards">
          ${lib.concatMapStrings machineCard machines}
          ${lib.concatMapStrings lampCard lamps}
        </div>
      '';
    };

    # The whole house across every plug, AT CURRENT DRAW (see plugQuery).
    costRow = { label, days, dp, value, hi ? false }: ''
      <div class="ag-row${lib.optionalString hi " ag-row-hi"}"><span class="ag-k">${label}</span><span class="ag-v" data-ag-cost="${allPower}" data-ag-days="${days}" data-ag-dp="${dp}" data-ag-rate="${powerRate}">${value}</span></div>
    '';
    costOutlook = powerWidget {
      title = "Cost Outlook";
      cache = "5m";
      template = ''
        <div class="ag-rows">
          <div class="ag-sec">At current draw</div>
          ${costRow { label = "Per year"; days = "365"; dp = "0"; value = pf "year" "$%.0f"; hi = true; }}
          ${costRow { label = "Per month"; days = "30.44"; dp = "2"; value = pf "month" "$%.2f"; }}
          ${costRow { label = "Per week"; days = "7"; dp = "2"; value = pf "week" "$%.2f"; }}
          ${costRow { label = "Per day"; days = "1"; dp = "2"; value = pf "day" "$%.2f"; }}
          <div class="ag-row"><span class="ag-k">Energy / month</span><span class="ag-v"><span data-ag-kwh="${allPower}" data-ag-days="30.44" data-ag-dp="1">${pf "month_kwh" "%.1f"}</span> ${unit "kWh"}</span></div>
          <div class="ag-sec">Measured</div>
          <div class="ag-row"><span class="ag-k">All plugs now</span><span class="ag-v"><span data-ag-sum="${allPower}">${pf "now" "%.1f"}</span> ${unit "W"}</span></div>
          <div class="ag-row"><span class="ag-k">Today so far</span><span class="ag-v" data-ag-energy="${allEnergy}" data-ag-rate="${powerRate}" data-ag-dp="2">${pf "today_cost" "$%.2f"}</span></div>
          <div class="ag-sec">Tariff</div>
          <div class="ag-row"><span class="ag-k">Rate</span><span class="ag-v">${pf "rate" "$%.4f"} ${unit "/kWh"}</span></div>
          <div class="ag-row"><span class="ag-k">Supply charge</span><span class="ag-v">${pf "supply_year" "$%.0f"} ${unit "/yr fixed"}</span></div>
        </div>
      '';
    };

    # Radio health — and whether the plug itself answers at all.
    healthRow = p: ''
      {{ $up := eq (.JSON.String "${plug p "online"}") "on" }}
      <div class="ag-hrow" ${dev p}>
        <span class="ag-dot {{ if $up }}is-up{{ else }}is-down{{ end }}" data-ag-online="binary_sensor.${p.slug}_status" title="{{ if $up }}Plug online{{ else }}Plug offline{{ end }}"></span>
        <span class="ag-name">${p.short}</span>
        <span class="ag-v">${live p "wifi_signal_percent" 0 (pf (plug p "signal") "%.0f")}% · ${live p "wifi_signal_db" 0 (pf (plug p "rssi") "%.0f")} dBm</span>
        <span class="ag-meter"><i data-ag-meter="${sensor p "wifi_signal_percent"}" style="width: ${pf (plug p "signal") "%.0f"}%"></i></span>
      </div>
    '';
    plugHealth = powerWidget {
      title = "Plug Health";
      cache = "1m";
      template = ''
        <div class="ag-health">
          ${lib.concatMapStrings healthRow inventory.plugs}
        </div>
      '';
    };

    # ════════════════════════════════════════════════════════════════════════
    # LIVE CARDS — drawn in the browser from a stream, not by Glance
    # ════════════════════════════════════════════════════════════════════════
    #   ags-host ags-storage ags-playing ags-dl   stats.js   ← asgard-stats :9552
    #   nw                                        net.js     ← network-panel :9555
    #   ec-main ec-tv ec-wolf ec-log              eclipse.js ← eclipse-control :9554
    # net.js and eclipse.js (and cards.css) are SHARED with MarsBar, which
    # draws the same cards through her serve proxy. See _livecard.nix.
    liveCard = import ./_livecard.nix lib;

    # ════════════════════════════════════════════════════════════════════════
    # YGGDRASIL — the tree banner over every device on the tailnet
    # ════════════════════════════════════════════════════════════════════════
    # tailscale-status-proxy (Resources/Glance/tailscale-status.py) answers with
    # the nodes already sorted — this machine, everything online A→Z, then the
    # offline ones most recently seen first — and named by MagicDNS name, not
    # the OS hostname (Android reports "localhost"). So the list reads top-down
    # as "what's up", and long-gone devices fold away under Show more.
    #
    # 1m cache, from 15s: tailscale's own Online flag only moves when the
    # control plane notices, on the order of a minute, so refetching it four
    # times as often bought nothing. "seen 9h ago" ticks client-side anyway.
    tailnet = {
      type = "custom-api";
      title = "Yggdrasil Network";
      cache = "1m";
      url = "http://localhost:${toString tsPort}/status";
      template = ''
        <div class="ag-ts-sum"><span class="is-up"><b>{{ .JSON.Int "online" }}</b>online</span><span><b>{{ .JSON.Int "offline" }}</b>offline</span></div>
        <ul class="list ag-ts-list collapsible-container" data-collapse-after="10">
          {{ range .JSON.Array "nodes" }}
          <li class="ag-ts-node {{ if .Bool "online" }}is-up{{ else }}is-down{{ end }}{{ if .Bool "self" }} is-self{{ end }}">
            <span class="ag-dot"></span>
            <span class="ag-ts-name">{{ .String "name" }}</span>
            <span class="ag-ts-ip">{{ .String "ip" }}</span>
            <span class="ag-ts-sub">{{ .String "os" }}{{ if .String "host" }} · {{ .String "host" }}{{ end }} · {{ if .Bool "online" }}{{ .String "link" }}{{ else if .String "seen" }}seen <span {{ .String "seen" | parseRelativeTime "rfc3339" }}></span> ago{{ else }}offline{{ end }}</span>
          </li>
          {{ end }}
        </ul>
      '';
    };

    iframe = title: port: height: { type = "iframe"; inherit title height; source = at port; };

    # Downloads used to be a page of its own: a server-rendered queue widget,
    # the same monitors as the home page, and SABnzbd's UI in an iframe (SAB's
    # own page, one tap away from its monitor row anyway). Now a live card on
    # the home page from asgard-stats — what is downloading, how fast, what
    # finished or failed — and the iframe went with the page.

    # ════════════════════════════════════════════════════════════════════════
    # The Glance config
    # ════════════════════════════════════════════════════════════════════════
    # A Nix attrset serialised by pkgs.formats.yaml, NOT hand-written YAML
    # text: a real serialiser quotes and indents for us, so markup can be
    # written as markup and generated from the lists above. (MarsBar's config
    # is built the same way.)
    #
    # No secret is ever written into this file — it lands in the world-readable
    # Nix store. The one Glance needs (the HA token) is its readFileFromEnv
    # variable, substituted when it loads the config — see
    # systemd.services.glance below.
    #
    # ⚠ Glance expands every dollar-brace variable as plain text over the WHOLE
    # file before parsing it — markup included. Nothing generated here may
    # contain one other than that.
    glanceConfig = (pkgs.formats.yaml { }).generate "glance.yml" {
      server = {
        port = 8888;
        assets-path = "${glanceAssets}";
      };

      branding = {
        # The name a phone gives the home-screen shortcut, and the tab title.
        app-name = "Asgard";
        # The world tree as the logo, the tab icon and the phone's home-screen
        # icon — the dashboard's identity, like the card it came from.
        logo-url = "/assets/hud/logo.svg?v=${hudVersion}";
        favicon-url = "/assets/hud/logo.svg?v=${hudVersion}";
        app-icon-url = asset "yggdrasil.png";
        app-background-color = "hsl(213, 14%, 7%)";
        hide-footer = true;
      };

      # `defer`: run after the document is parsed, in order — dash.js first,
      # the helpers the others use. Each waits for Glance's widget markup
      # itself (it arrives later, via innerHTML) and does nothing on a page
      # without its cards. data-api-port: each builds
      # http://<this hostname>:<port>, so the page keeps working when opened
      # by IP or FQDN (each is in _origins.nix).
      document.head = ''
        <link rel="stylesheet" href="${asset "cards.css"}">
        <link rel="stylesheet" href="/assets/hud/hud.css?v=${hudVersion}">
        <script src="${asset "theme.js"}" data-default="#3be8a8" data-hud="${hudVersion}" data-tpl="/assets/hud/tpl.js?v=${hudVersion}"></script>
        <script src="${asset "dash.js"}" defer></script>
        <script src="${asset "lights.js"}" data-api-port="${toString bridgePort}" defer></script>
        <script src="${asset "asgard.js"}" data-api-port="${toString bridgePort}" defer></script>
        <script src="${asset "stats.js"}" data-api-port="${toString statsPort}" data-jellyfin-port="${toString jellyfinPort}" defer></script>
        <script src="${asset "net.js"}" data-api-port="${toString netPort}" defer></script>
        <script src="${asset "eclipse.js"}" data-api-port="${toString eclipsePort}" defer></script>
      '';

      # The HUD: a tech/cyberpunk heads-up display on tech grey — chamfered
      # neon panels, Orbitron titles with boxed icons, angled tabs, a grid
      # that tiles down the page — in mint by default, or whatever colour the
      # viewer picks (theme.js, a per-browser preference). Glance only draws a
      # little itself (links, the monitor icons); asgard.css carries the real
      # system and hud.py draws its artwork (above). MarsBar stays purple with
      # her vine, so the two are never confused.
      theme = {
        background-color = "hsl(213, 14%, 7%)";
        primary-color = "hsl(158, 79%, 57%)";
        positive-color = "hsl(150, 100%, 65%)";
        negative-color = "hsl(355, 100%, 65%)";
        custom-css-file = "/assets/asgard.css";
      };

      pages = [
        # ══════════════════════════════════════════════════════════════════
        # Asgard — host, storage, network, services
        #          | clock, now playing, downloads, tailnet
        # ══════════════════════════════════════════════════════════════════
        {
          name = "Asgard";
          columns = [
            {
              size = "full";
              widgets = [
                # Was Glance's server-stats (three small bars, refreshed on load).
                # Now a live stream from asgard-stats — see Modules/Server/stats.nix.
                (liveCard { id = "ags-host"; title = "Asgard"; acc = "mint"; rune = "ansuz"; badge = "ags-live"; })
                (liveCard { id = "ags-storage"; title = "Storage"; acc = "teal"; rune = "othala"; })
                (liveCard { id = "nw"; title = "Network"; acc = "mint"; rune = "raidho"; badge = "nw-live"; })
                # One group rather than five stacked monitors. "All" is the
                # default tab because "is everything up" is the question this
                # page exists to answer; the category tabs isolate a red one.
                {
                  type = "group";
                  css-class = "acc-teal rune-algiz";
                  widgets = [ (monitor "All" services) ]
                    ++ map (t: monitor t (builtins.filter (s: s.tab == t) services)) tabs;
                }
              ];
            }
            {
              size = "small";
              widgets = [
                { type = "clock"; hour-format = "12h"; css-class = "acc-teal rune-jera"; }
                (liveCard { id = "ags-playing"; title = "Now Playing"; acc = "mint"; rune = "laguz"; })
                (liveCard {
                  id = "ags-dl"; title = "Downloads"; acc = "teal"; rune = "fehu";
                  link = { href = at sabPort; text = "SABnzbd"; };
                })
                (tailnet // { css-class = "ygg-widget acc-mint rune-eihwaz"; })
              ];
            }
          ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Eclipse — the TV box, live: status, actions, Wolf streams, activity
        # ══════════════════════════════════════════════════════════════════
        # Drawn natively by eclipse.js from eclipse-control's /events stream
        # (:9554, which drives the LibreELEC box over SSH and carries EVERY
        # verb — reboot, jellyfin-toggle, the link test; MarsBar's TV card has
        # only the safe three). It used to be an iframe of a page that service
        # served, polling on two timers. `slim` keeps it from floating in an
        # ultrawide.
        {
          name = "Eclipse";
          width = "slim";
          columns = [
            {
              size = "full";
              widgets = [
                (liveCard { id = "ec-main"; title = "Eclipse"; acc = "mint"; rune = "dagaz"; badge = "ec-live"; })
                (liveCard { id = "ec-wolf"; title = "Streams · Wolf on Sisyphus"; acc = "teal"; rune = "ehwaz"; })
              ];
            }
            {
              size = "small";
              widgets = [
                (liveCard { id = "ec-tv"; title = "On the TV"; acc = "teal"; rune = "perthro"; })
                (liveCard { id = "ec-log"; title = "Activity"; acc = "mint"; rune = "mannaz"; })
              ];
            }
          ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Power — the lights, and every plug: draw now and over 24 h, cost, health
        # ══════════════════════════════════════════════════════════════════
        # (Was "Monitoring", from when there was a metrics stack.) Reads Home
        # Assistant's REST API over localhost for the first frame — one Jinja
        # query, plugQuery above — and ha-bridge's stream for everything after.
        # HA tokens can't be minted declaratively (they need a logged-in
        # session), so this one was made by hand in the HA UI and stored in sops
        # as `ha-token`.
        {
          name = "Power";
          # Without this the page stretches the full 2560px of an ultrawide and
          # a single device card becomes a metre-wide band.
          width = "slim";
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "custom-api";
                  title = "Lights";
                  css-class = "acc-mint rune-kenaz";
                  # The bridge, not HA: it answers from memory, so a 1s cache
                  # costs nothing and keeps each tile's first paint honest — and
                  # the widget fails visibly when ha-bridge is down.
                  cache = "1s";
                  url = "http://localhost:${toString bridgePort}/states";
                  template = lightsCard;
                }
                (powerOverview // { css-class = "acc-teal rune-sowilo"; })
                (powerDevices // { css-class = "acc-mint rune-tiwaz"; })
              ];
            }
            { size = "small"; widgets = [ (costOutlook // { css-class = "acc-teal rune-gebo"; }) (plugHealth // { css-class = "acc-mint rune-uruz"; }) ]; }
          ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Terminal — ttyd web console (log in as rock; sudo works)
        # ══════════════════════════════════════════════════════════════════
        # Sized to the window by asgard.css (.term-widget), not the 700 px box.
        {
          name = "Terminal";
          columns = [ { size = "full"; widgets = [ ((iframe "Asgard Terminal" 7681 700) // { css-class = "term-widget acc-mint rune-isa"; }) ]; } ];
        }
      ];
    };
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD — Glance (port 8888)
# ══════════════════════════════════════════════════════════════════════════════

    # ── Glance — native systemd service ──
    #
    # Native, not a container. (It once was for the server-stats widget's
    # /proc and /sys; the host stats come from asgard-stats now.)
    #
    # The secret reaches the widgets through Glance's `readFileFromEnv` config
    # variable: LoadCredential copies the root-only (0400) sops secret into
    # this unit's private credentials dir (readable by the DynamicUser, nobody
    # else), an env var points at the copy, and Glance substitutes the file's
    # contents when it loads the config. That keeps it out of the Nix store
    # AND off every other local uid:
    #   • HA_TOKEN_FILE — an ADMIN Home Assistant token (Power page).
    #     It used to be read with Glance's ''${secret:ha-token}, which reads
    #     /run/secrets directly and so forced the secret to 0444 (later a 0440
    #     group stopgap). Anything holding it can switch.toggle Asgard's own
    #     mains feed, bypassing ha-bridge's allowlist. Declared by the
    #     home-assistant module (Modules/Server/home-assistant.nix).
    #
    # Glance substitutes these as plain text over the whole config file before
    # parsing it, so they work in any value — the HA widgets use the token
    # inside a `headers:` map.
    #
    # ⚠ Glance resolves config variables at STARTUP and refuses to start if one
    # cannot be read, so a missing credential takes the whole dashboard down,
    # not just the widgets that use it.
    systemd.services.glance = {
      description = "Glance Dashboard";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HA_TOKEN_FILE = "/run/credentials/glance.service/ha-token";
      };
      serviceConfig = {
        ExecStart = "${pkgs.glance}/bin/glance --config ${glanceConfig}";
        Restart = "on-failure";
        DynamicUser = true;
        # (It also held SABnzbd's full-control API key for the old Downloads
        # widgets; the Downloads card reads SAB through asgard-stats now.)
        LoadCredential = [
          "ha-token:${config.sops.secrets."ha-token".path}"
        ];
      };
    };

  };
}
