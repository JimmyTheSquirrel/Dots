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
    tsPort = 9553;     # tailscale-status-proxy (network.nix) — the tailnet list
    haPort = 8123;     # Home Assistant — the power figures (/api/template)
    sabPort = 8080;    # SABnzbd, via the socat proxy into the Mullvad namespace

    # ── Assets (served at /assets/) ─────────────────────────────────────────
    # The CSS and JS live in real files, not in Nix strings inside the YAML.
    # They used to be ~900 lines of a `document.head: |` block scalar, where a
    # single mis-indented line silently ends the scalar and breaks the whole
    # config (see Claude/marsbar.md). Same pattern as MarsBar.
    #
    # lights.js is SHARED with MarsBar — one push client, so both dashboards
    # behave the same and a fix lands on both.
    assetFiles = {
      "yggdrasil.png" = ../../Resources/Glance/yggdrasil-banner.png;
      "asgard.css" = ../../Resources/Glance/asgard.css;
      "asgard.js" = ../../Resources/Glance/asgard.js;
      "lights.js" = ../../Resources/Glance/lights.js;
    };
    glanceAssets = pkgs.linkFarm "glance-assets" assetFiles;

    # Glance serves /assets/ with a 2h Cache-Control, so a script URL that never
    # changes would keep running the OLD code for up to two hours after a
    # deploy. The content hash makes every edit a new URL. (custom-css-file needs
    # no help: Glance stamps that one with its own start time.)
    asset = name:
      "/assets/${name}?v=${builtins.substring 0 10 (builtins.hashFile "sha256" assetFiles.${name})}";

    # ── Power dashboard tunables (Monitoring page) ──
    #
    # Reference ceiling for the draw bar, in watts. Deliberately NOT the plug's
    # 3680 W rating: against that scale an idling server sits at ~1% and the bar
    # never visibly moves. Set it near this box's realistic peak instead.
    powerRefW = 150;
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
    # in its category tab — plus a third copy on the Downloads page, so adding a
    # service meant three edits that could drift. Now:
    #   tab     its category tab (it is always in "All" too)
    #   alsoOn  other pages that show it ("downloads" → the Downloads page Status)
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
      { title = "Jellyfin";       port = 8096;  icon = "sh:jellyfin";       tab = "Media"; }
      { title = "Jellyseerr";     port = 5055;  icon = "sh:jellyseerr";     tab = "Media"; }
      { title = "Immich";         port = 2283;  icon = "sh:immich";         tab = "Media"; }
      { title = "Audiobookshelf"; port = 13378; icon = "sh:audiobookshelf"; tab = "Media"; }
      { title = "SABnzbd";        port = sabPort; icon = "sh:sabnzbd";      tab = "Downloads"; alsoOn = [ "downloads" ]; }
      { title = "Prowlarr";       port = 9696;  icon = "sh:prowlarr";       tab = "Downloads"; alsoOn = [ "downloads" ]; }
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
    onPage = page: builtins.filter (s: builtins.elem page (s.alsoOn or [ ])) services;

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

    # Home page: the lights, first thing on the page — the controls that get used
    # most, reachable without leaving the landing page, on a phone too.
    homeLights = ''
      ${liveBadge}
      <div class="ag-lights">
        ${lightTile {
          inherit (group) entity name;
          icon = "✦";
          hero = true;
          extra = members;
          state = bridgeState group.entity;
          sub = ''<span data-ag-on="${lampRelays}">${bridgeOnCount}</span> · <span data-ag-sum="${powerOf lamps}">${bridgeLampWatts}</span> W'';
        }}
        ${lib.concatMapStrings (p: lightTile {
          inherit (p) entity name icon;
          state = bridgeState p.entity;
          sub = ''${p.room} · <span data-ag-w="${p.power}">{{ printf "%.1f" ${bridgeWatts p.power} }}</span> W'';
        }) lamps}
      </div>
    '';

    # ── The shared power query (Monitoring page) ───────────────────────────
    # ONE Jinja template, generated from the inventory, that every Monitoring
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
    machineCard = p: ''
      <details class="ag-card" data-ha-entity="${p.entity}" data-ha-state="${ps (plug p "state")}">
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
              ${stat "Voltage" "${pf (plug p "voltage") "%.1f"} ${unit "V"}"}
              ${stat "Current" "${pf (plug p "current") "%.3f"} ${unit "A"}"}
              ${stat "Apparent" "${pf (plug p "apparent") "%.1f"} ${unit "VA"}"}
              ${stat "Power factor" (pf (plug p "pf") "%.2f")}
            </div>
          </div>
          {{ if gt (.JSON.Float "${plug p "apparent"}") 0.0 }}
          <div>
            <div class="ag-sec">Real vs apparent</div>
            <div class="pw-pf-bar"><div class="pw-pf-fill" style="width: {{ printf "%.0f" (.JSON.Float "${plug p "pf_pct"}") }}%"></div></div>
            <div class="pw-legend">
              <span class="pw-lg-real">${pf (plug p "power") "%.1f"} W real</span>
              <span class="pw-lg-reactive">${pf (plug p "apparent") "%.1f"} VA drawn</span>
            </div>
          </div>
          {{ end }}
          <div>
            <div class="ag-sec">Energy</div>
            <div class="ag-grid">
              ${stat "Used today" "${pf (plug p "today_kwh") "%.3f"} ${unit "kWh"}"}
              ${stat "Cost today" (pf (plug p "today_cost") "$%.2f")}
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
      <details class="ag-card" data-ha-entity="${p.entity}" data-ha-state="${ps (plug p "state")}">
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
            ${stat "Voltage" "${pf (plug p "voltage") "%.1f"} ${unit "V"}"}
            ${stat "Used today" "${pf (plug p "today_kwh") "%.3f"} ${unit "kWh"}"}
            ${stat "Signal" "${pf (plug p "signal") "%.0f"} ${unit "%"}"}
            ${stat "Address" (ps (plug p "ip"))}
            ${stat "On power loss" (ps (plug p "onstate"))}
            ${stat "Plug booted" (sinceBoot p)}
          </div>
        </div>
      </details>
    '';

    powerMonitoring = powerWidget {
      title = "Power Monitoring";
      # The headline watts and relay states are live; this renders the first
      # frame and the slow figures (V, A, kWh today), so 30s is plenty.
      cache = "30s";
      template = ''
        <div class="pw">
          <div class="pw-hero">
            <div><span class="pw-big" data-ag-sum="${powerOf machines}">{{ printf "%.1f" (.JSON.Float "machines") }}</span><span class="pw-big-unit">W</span></div>
            <div class="pw-trail">combined draw · ${toString (builtins.length machines)} machines<br>{{ printf "$%.4f" (.JSON.Float "rate") }}/kWh balance rate</div>
          </div>
          {{ $pct := mul (div (.JSON.Float "machines") ${toString powerRefW}.0) 100.0 }}
          <div class="pw-bar"><div class="pw-bar-fill" data-ag-bar="${powerOf machines}" data-ag-ref="${toString powerRefW}" style="width: {{ if gt $pct 100.0 }}100{{ else }}{{ printf "%.1f" $pct }}{{ end }}%"></div></div>
          <div class="pw-scale"><span>0 W</span><span>${toString powerRefW} W ref</span></div>
          <div class="ag-cards">
            ${lib.concatMapStrings machineCard machines}
          </div>
        </div>
      '';
    };

    powerSwitches = powerWidget {
      title = "Power Switches";
      # 1s, not 30s: this renders each switch's position, and a stale one would
      # visibly flip a moment after load when the stream corrects it. HA renders
      # the template from memory in milliseconds.
      cache = "1s";
      template = ''
        ${liveBadge}
        <div class="pw">
          ${lightTile {
            inherit (group) entity name;
            icon = "✦";
            hero = true;
            extra = members;
            state = ''{{ .JSON.String "group" }}'';
            sub = ''<span data-ag-on="${lampRelays}">{{ .JSON.Int "lit" }} of ${lampCount} on</span> · <span data-ag-sum="${powerOf lamps}">{{ printf "%.1f" (.JSON.Float "lights") }}</span> W together'';
          }}
          <div class="ag-cards">
            ${lib.concatMapStrings lampCard lamps}
          </div>
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
          <div class="ag-row"><span class="ag-k">Today so far</span><span class="ag-v">${pf "today_cost" "$%.2f"}</span></div>
          <div class="ag-sec">Tariff</div>
          <div class="ag-row"><span class="ag-k">Rate</span><span class="ag-v">${pf "rate" "$%.4f"} ${unit "/kWh"}</span></div>
          <div class="ag-row"><span class="ag-k">Supply charge</span><span class="ag-v">${pf "supply_year" "$%.0f"} ${unit "/yr fixed"}</span></div>
        </div>
      '';
    };

    # Radio health — and whether the plug itself answers at all.
    healthRow = p: ''
      {{ $up := eq (.JSON.String "${plug p "online"}") "on" }}
      <div class="ag-hrow">
        <span class="ag-dot {{ if $up }}is-up{{ else }}is-down{{ end }}" title="{{ if $up }}Plug online{{ else }}Plug offline{{ end }}"></span>
        <span class="ag-name">${p.short}</span>
        <span class="ag-v">${pf (plug p "signal") "%.0f"}% · ${pf (plug p "rssi") "%.0f"} dBm</span>
        <span class="ag-meter"><i style="width: ${pf (plug p "signal") "%.0f"}%"></i></span>
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
    # NETWORK — live throughput + speed test (network-panel.py, :9555)
    # ════════════════════════════════════════════════════════════════════════
    # A group so the live readout and the speed test share one widget slot.
    # Both tabs render from the same /api call, over localhost, server-side.
    #
    # That render is only the FIRST frame: asgard.js polls the same /api every
    # 2s (only on this page, only while the tab is visible) and repaints by id —
    # don't rename an id without editing it. It draws the sparklines too; their
    # boxes have a fixed height, so nothing moves when the traces appear.
    # This replaced a `flow` TUI in a read-only ttyd, which spent most of its
    # life showing xterm.js's reconnect banner.
    netCell = dir: arrow: label: ''
      <div class="np-cell">
        <div class="np-head">
          <span class="np-arrow np-${dir}">${arrow}</span>
          <span class="np-num" id="np-${dir}">{{ printf "%.1f" (.JSON.Float "live.${dir}") }}</span>
          <span class="np-unit">Mb/s</span>
          <span class="np-label">${label}</span>
        </div>
        <svg class="np-spark np-${dir}" id="np-spark-${dir}" viewBox="0 0 240 44" preserveAspectRatio="none" aria-hidden="true">
          <path class="np-fill" d=""></path>
          <path class="np-line" d=""></path>
        </svg>
        <div class="np-foot">peak <span id="np-peak-${dir}">{{ printf "%.1f" (.JSON.Float "live.peak_${dir}") }}</span> Mb/s over {{ .JSON.Int "live.window" }}s</div>
      </div>
    '';

    stCell = { id, arrow ? "", unitText, foot }: ''
      <div class="np-cell">
        <div class="np-head">
          ${lib.optionalString (arrow != "") ''<span class="np-arrow np-${arrow}">${if arrow == "down" then "↓" else "↑"}</span>''}
          <span class="np-num" id="np-st-${id}">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.${id}") }}{{ else }}--{{ end }}</span>
          <span class="np-unit">${unitText}</span>
        </div>
        <div class="np-foot">${foot}</div>
      </div>
    '';

    network = {
      type = "group";
      widgets = [
        {
          type = "custom-api";
          title = "Network";
          # Was 5s. Nothing on screen depends on this fetch being fresh — the
          # poller repaints every figure within a second of load — it only has
          # to have the right shape. A minute spares a fetch on most loads.
          cache = "1m";
          url = "http://localhost:${toString netPort}/api";
          template = ''
            <div class="np">
              <div class="np-row">
                ${netCell "down" "↓" "download"}
                ${netCell "up" "↑" "upload"}
              </div>
              <div class="np-meta"><span>{{ .JSON.String "live.iface" }} · sampled every second · each trace scaled to its own peak</span></div>
            </div>
          '';
        }
        # Upload reads ~30 Mb/s on a 50 Mb/s uplink and that is correct:
        # wan-egress-shaping puts every WAN-bound packet in a 30 Mbit htb class.
        # The footnote says so, because this otherwise looks exactly like a
        # broken uplink.
        {
          type = "custom-api";
          title = "Speed test";
          # Was 30s. The result changes every 6 hours (or on "Run now", which
          # the poller picks up live), so 5 minutes is still far fresher than
          # the data.
          cache = "5m";
          url = "http://localhost:${toString netPort}/api";
          template = ''
            {{ $ok := .JSON.Bool "speedtest.ok" }}
            <div class="np">
              <div class="np-row">
                ${stCell { id = "down"; arrow = "down"; unitText = "Mb/s"; foot = "download"; }}
                ${stCell { id = "up"; arrow = "up"; unitText = "Mb/s"; foot = "upload · shaped to 30"; }}
                ${stCell { id = "ping"; unitText = "ms"; foot = ''ping · <span id="np-st-jitter">{{ if $ok }}{{ printf "%.1f" (.JSON.Float "speedtest.jitter") }}{{ else }}--{{ end }}</span> ms jitter''; }}
              </div>
              <div class="np-meta">
                <span>Ookla, every 6h · {{ if $ok }}<span id="np-st-when" {{ .JSON.String "speedtest.timestamp" | parseRelativeTime "rfc3339" }}></span> ago · <span id="np-st-server">{{ .JSON.String "speedtest.server" }}</span>{{ else }}<span id="np-st-when">never run</span><span id="np-st-server"></span>{{ end }}</span>
                <button class="np-btn" id="np-run" type="button">Run now</button>
              </div>
            </div>
          '';
        }
      ];
    };

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
      css-class = "ygg-widget";
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

    # ════════════════════════════════════════════════════════════════════════
    # DOWNLOADS — SABnzbd's own queue API
    # ════════════════════════════════════════════════════════════════════════
    # One widget, one fetch: "Queue" and "Remaining" used to be two widgets
    # making the identical call. They once queried Prometheus for an exporter's
    # sabnzbd_queue_*; that metrics stack is gone and SAB serves the numbers
    # itself. localhost:8080 is the socat proxy into the Mullvad namespace —
    # the same path speedtest.service uses.
    #
    # The apikey is Glance's readFileFromEnv variable (a systemd credential),
    # never written here. It sits in the URL rather than in `parameters:` on
    # purpose: Glance substitutes it into the YAML text before parsing, and the
    # serialiser leaves `''${…}` unquoted, so as a value of its own an all-digit
    # key would parse as a NUMBER (and a 32-digit one comes back as 1.2e+31).
    # Inside a longer string it can only ever be a string.
    #
    # `mbleft` and `kbpersec` are JSON *strings*; .Float parses them. 30s, not
    # 15s: SAB's own live UI is right beside it.
    sabQueue = {
      type = "custom-api";
      title = "Queue";
      cache = "30s";
      url = "http://localhost:${toString sabPort}/api?mode=queue&output=json&apikey=\${readFileFromEnv:SABNZBD_API_KEY_FILE}";
      template = ''
        <div class="ag-stats">
          <div class="ag-stat"><span class="ag-k">In queue</span><span class="ag-v">{{ .JSON.Int "queue.noofslots_total" }} ${unit "items"}</span></div>
          <div class="ag-stat"><span class="ag-k">Remaining</span><span class="ag-v">{{ printf "%.2f" (div (.JSON.Float "queue.mbleft") 1024.0) }} ${unit "GB"}</span></div>
          <div class="ag-stat ag-stat-wide"><span class="ag-k">{{ .JSON.String "queue.status" }}</span><span class="ag-v">{{ printf "%.1f" (div (.JSON.Float "queue.kbpersec") 1024.0) }} MB/s · {{ .JSON.String "queue.timeleft" }} left</span></div>
        </div>
      '';
    };

    iframe = title: port: height: { type = "iframe"; inherit title height; source = at port; };

    # ════════════════════════════════════════════════════════════════════════
    # The Glance config
    # ════════════════════════════════════════════════════════════════════════
    # A Nix attrset serialised by pkgs.formats.yaml, NOT hand-written YAML
    # text: a real serialiser quotes and indents for us, so markup can be
    # written as markup and generated from the lists above. (MarsBar's config
    # is built the same way.)
    #
    # No secret is ever written into this file — it lands in the world-readable
    # Nix store. The two Glance needs (the HA token, the SABnzbd key) are its
    # readFileFromEnv variables, substituted when it loads the config — see
    # systemd.services.glance below.
    #
    # ⚠ Glance expands every dollar-brace variable as plain text over the WHOLE
    # file before parsing it — markup included. Nothing generated here may
    # contain one other than those two.
    glanceConfig = (pkgs.formats.yaml { }).generate "glance.yml" {
      server = {
        port = 8888;
        assets-path = "${glanceAssets}";
      };

      branding = {
        # The name a phone gives the home-screen shortcut, and the tab title.
        app-name = "Asgard";
        hide-footer = true;
      };

      # `defer`: run after the document is parsed, in order. Both wait for
      # Glance's widget markup themselves (it arrives later, via innerHTML).
      # data-api-port: lights.js builds http://<this hostname>:9556, so the
      # page keeps working when opened by IP or FQDN (each is in _origins.nix).
      document.head = ''
        <script src="${asset "lights.js"}" data-api-port="${toString bridgePort}" defer></script>
        <script src="${asset "asgard.js"}" defer></script>
      '';

      # Mint-green — the "mission control" homelab look this dashboard has
      # always had (an orange experiment was tried and rejected), and the
      # opposite of MarsBar's purple so the two are never confused. Colour
      # variety comes from the ambient orbs and secondary accents in
      # asgard.css, not from repainting everything.
      theme = {
        background-color = "hsl(170, 14%, 8%)";
        primary-color = "hsl(158, 58%, 64%)";
        positive-color = "hsl(152, 62%, 52%)";
        negative-color = "hsl(0, 84%, 60%)";
        custom-css-file = "/assets/asgard.css";
      };

      pages = [
        # ══════════════════════════════════════════════════════════════════
        # Asgard — lights, host stats, network, service health | clock, tailnet
        # ══════════════════════════════════════════════════════════════════
        {
          name = "Asgard";
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "custom-api";
                  title = "Lights";
                  # The bridge, not HA: it answers from memory, so a 1s cache
                  # costs nothing and keeps each tile's first paint honest — and
                  # the widget fails visibly when ha-bridge is down.
                  cache = "1s";
                  url = "http://localhost:${toString bridgePort}/states";
                  template = homeLights;
                }
                {
                  type = "server-stats";
                  servers = [
                    {
                      type = "local";
                      name = "Asgard";
                      hide-mountpoints-by-default = true;
                      # The pool is the DISK bar, so there is no separate storage
                      # widget. (One existed, with a browser-side poller that
                      # fetched localhost:<port> — the VIEWER's machine — so it
                      # had never updated anywhere but on the server itself. Any
                      # browser-side fetch must use location.hostname.)
                      mountpoints."/data/media" = { name = "Media Pool"; hide = false; };
                    }
                  ];
                }
                network
                # One group rather than five stacked monitors. "All" is the
                # default tab because "is everything up" is the question this
                # page exists to answer; the category tabs isolate a red one.
                {
                  type = "group";
                  widgets = [ (monitor "All" services) ]
                    ++ map (t: monitor t (builtins.filter (s: s.tab == t) services)) tabs;
                }
              ];
            }
            {
              size = "small";
              widgets = [
                { type = "clock"; hour-format = "12h"; }
                tailnet
              ];
            }
          ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Downloads — SABnzbd queue + its own UI
        # ══════════════════════════════════════════════════════════════════
        {
          name = "Downloads";
          columns = [
            {
              size = "small";
              widgets = [ sabQueue (monitor "Status" (onPage "downloads")) ];
            }
            # x_frame_options = 0 in SAB's config is what lets it be framed.
            { size = "full"; widgets = [ (iframe "SABnzbd" sabPort 700) ]; }
          ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Terminal — ttyd web console (log in as rock; sudo works)
        # ══════════════════════════════════════════════════════════════════
        {
          name = "Terminal";
          columns = [ { size = "full"; widgets = [ (iframe "Asgard Terminal" 7681 700) ]; } ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Eclipse — TV box: fix-it buttons + live status
        # ══════════════════════════════════════════════════════════════════
        # The panel is served by eclipse-control (:9554), which drives the
        # LibreELEC box over SSH, and carries EVERY verb (reboot,
        # jellyfin-toggle, speed test) — MarsBar's native rebuild exposes only
        # the safe three. An iframe because Glance's html widget sanitises
        # markup — see Claude/eclipse.md. `slim` keeps a ~1000px panel from
        # floating in an ultrawide.
        {
          name = "Eclipse";
          width = "slim";
          columns = [ { size = "full"; widgets = [ (iframe "Eclipse Control" 9554 700) ]; } ];
        }

        # ══════════════════════════════════════════════════════════════════
        # Monitoring — every plug's power, the light switches, cost
        # ══════════════════════════════════════════════════════════════════
        # Reads Home Assistant's REST API over localhost (both run natively on
        # Asgard): one Jinja query, plugQuery above. HA tokens can't be minted
        # declaratively (they need a logged-in session), so this one was made by
        # hand in the HA UI and stored in sops as `ha-token`.
        {
          name = "Monitoring";
          # Without this the page stretches the full 2560px of an ultrawide and
          # a single device card becomes a metre-wide band. `slim` caps the
          # content column (and allows at most two columns).
          width = "slim";
          columns = [
            { size = "full"; widgets = [ powerMonitoring powerSwitches ]; }
            { size = "small"; widgets = [ costOutlook plugHealth ]; }
          ];
        }
      ];
    };
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# DASHBOARD — Glance (port 8888)
# ══════════════════════════════════════════════════════════════════════════════

    # ── Glance — native systemd service for host-level server-stats ──
    #
    # Native, not a container, so the server-stats widget can read the host's
    # /proc and /sys directly.
    #
    # Both secrets reach the widgets through Glance's `readFileFromEnv` config
    # variable: LoadCredential copies each root-only (0400) sops secret into
    # this unit's private credentials dir (readable by the DynamicUser, nobody
    # else), an env var points at the copy, and Glance substitutes the file's
    # contents when it loads the config. That keeps them out of the Nix store
    # AND off every other local uid:
    #   • SABNZBD_API_KEY_FILE — full control of SABnzbd (Downloads widgets)
    #   • HA_TOKEN_FILE        — an ADMIN Home Assistant token (Monitoring page).
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
        SABNZBD_API_KEY_FILE = "/run/credentials/glance.service/sabnzbd-api-key";
        HA_TOKEN_FILE = "/run/credentials/glance.service/ha-token";
      };
      serviceConfig = {
        ExecStart = "${pkgs.glance}/bin/glance --config ${glanceConfig}";
        Restart = "on-failure";
        DynamicUser = true;
        LoadCredential = [
          "sabnzbd-api-key:${config.sops.secrets."sabnzbd-api-key".path}"
          "ha-token:${config.sops.secrets."ha-token".path}"
        ];
      };
    };

  };
}
