{ ... }: {
  # ══════════════════════════════════════════════════════════════════════════
  # MarsBar — a second, deliberately tiny Glance dashboard
  #
  # Lives on its OWN tailnet node (`marsbar`), not on Asgard's. That is the whole
  # point: MagicDNS names come from machines, not services, so `marsbar:1111`
  # requires a machine called marsbar — and running one buys real isolation as a
  # side effect. A Tailscale ACL granting only `marsbar:*` cannot reach a single
  # Asgard port, because they are different nodes with different IPs. Compare the
  # alternative (a second page on asgard:8888), where every admin page stays one
  # URL edit away.
  #
  # Traffic path:
  #   her browser ──► marsbar:1111 ──► tailscaled (userspace netstack)
  #                                      ├── /      → 127.0.0.1:8890  Glance
  #                                      └── /ha/*  → 127.0.0.1:9556  ha-bridge
  #
  # Both backends bind LOOPBACK ONLY. Nothing here opens a firewall port: the
  # serve proxy terminates inside tailscaled, so the LAN and even Asgard's own
  # tailnet node cannot reach this dashboard.
  # ══════════════════════════════════════════════════════════════════════════
  flake.nixosModules.marsbar = { config, pkgs, lib, ... }:
  let
    glancePort = 8890; # loopback-only Glance for this dashboard
    servePort = 1111;  # the port she actually types: marsbar:1111
    bridgePort = 9556; # ha-bridge from Modules/Server/home-assistant.nix
    eclipsePort = 9554; # eclipse-control from Modules/Server/server.nix (drives the Pi over SSH)
    netPort = 9555;     # network-panel from Modules/Server/server.nix (Asgard's live throughput)

    tsDir = "/run/tailscale-marsbar";
    tsSocket = "${tsDir}/tailscaled.sock";
    ts = "${pkgs.tailscale}/bin/tailscale --socket=${tsSocket}";

    # ── Lights ──────────────────────────────────────────────────────────────
    # These MUST be a subset of ALLOWED in Modules/Server/home-assistant.nix. That set
    # is the real safety boundary — it is why `switch.server_power_switch` and
    # `switch.eclipse_switch` cannot be toggled from here even if someone hand-
    # crafts a POST. Listing an entity here only draws a button; the bridge
    # decides whether it does anything (403 otherwise).
    lights = [
      { entity = "switch.living_room_lights";      name = "All Lights";       sub = "Everything at once"; icon = "✦"; hero = true; }
      { entity = "switch.colour_lamp_switch";      name = "Colour Lamp";      sub = "Living room";        icon = "◐"; hero = false; }
      { entity = "switch.lounge_room_lamp_switch"; name = "Lounge Lamp";      sub = "Lounge room";        icon = "◑"; hero = false; }
      # Display name only — the HA entity id stays christmas_lights_switch, and
      # renaming it here does NOT need a matching change in ALLOWED.
      { entity = "switch.christmas_lights_switch"; name = "Fairy Lights";     sub = "Living room";       icon = "❅"; hero = false; }
    ];

    # Each card is emitted as ONE line with no internal newlines, and the template
    # below keeps it on a single line too. This is deliberate, not sloppy: the cards
    # are interpolated into a YAML block scalar, and Nix's '' strings strip the
    # common leading indentation from their content. Multi-line HTML therefore
    # arrives with its continuation lines at column 0 — under the block scalar's
    # required indent — which silently ends the scalar and yields
    # "could not find expected ':'". One line per card sidesteps the whole problem.
    lightCard = l:
      ''<button class="mb-light''
      + lib.optionalString l.hero " mb-hero"
      + ''" data-entity="${l.entity}" data-mb-state="unknown">''
      + ''<span class="mb-ico">${l.icon}</span>''
      + ''<span class="mb-txt">''
      + ''<span class="mb-name">${l.name}</span>''
      + ''<span class="mb-sub">${l.sub}</span>''
      + ''</span>''
      + ''<span class="mb-right">''
      + ''<span class="mb-state">—</span>''
      + ''<span class="mb-sw"></span>''
      + ''</span>''
      + ''</button>'';

    # ── Eclipse (TV box) controls ───────────────────────────────────────────
    # Rebuilt NATIVELY rather than iframing asgard:9554 like the admin dashboard
    # does. The iframe exists there because Glance's `html` widget sanitises
    # markup, but a custom-api widget plus a handler in document.head has no such
    # limit — same trick as the light toggles. That buys the purple theme for
    # free, a layout that works on a phone, and no iframe height guessing.
    #
    # Deliberately NOT exposed here: `reboot` (bounces the TV box) and
    # `jellyfin-toggle` (changes how streams route). `speedtest` is omitted as
    # noise. Add an entry below to surface one — the panel already accepts them.
    tvActions = [
      { act = "restart-kodi"; name = "Restart Kodi";  sub = "Fixes a frozen or missing UI"; icon = "↻"; }
      { act = "sync-movies";  name = "Sync Movies";   sub = "Pull in new films";            icon = "▦"; }
      { act = "sync-shows";   name = "Sync TV Shows"; sub = "Pull in new episodes";         icon = "▶"; }
    ];

    tvCard = a:
      ''<button class="mb-light mb-act" data-act="${a.act}">''
      + ''<span class="mb-ico">${a.icon}</span>''
      + ''<span class="mb-txt">''
      + ''<span class="mb-name">${a.name}</span>''
      + ''<span class="mb-sub">${a.sub}</span>''
      + ''</span>''
      + ''<span class="mb-go">›</span>''
      + ''</button>'';

    tvStat = id: label:
      ''<div class="mb-stat"><span class="mb-stat-k">${label}</span>''
      + ''<span class="mb-stat-v" id="${id}">—</span></div>'';

    tvMarkup =
      ''<div class="mb-tv">''
      + ''<div class="mb-tv-head">''
      + ''<span class="mb-tv-dot" id="tv-dot"></span>''
      + ''<span class="mb-tv-h"><span class="mb-tv-state" id="tv-state">checking…</span>''
      + ''<span class="mb-tv-sub" id="tv-sub">contacting the TV box</span></span>''
      + ''</div>''
      + ''<div class="mb-stats">''
      + tvStat "tv-kodi" "Kodi"
      + tvStat "tv-mode" "Display"
      + tvStat "tv-uptime" "Uptime"
      + ''</div>''
      + ''<div class="mb-sec">Controls</div>''
      + lib.concatMapStrings tvCard tvActions
      + ''<div class="mb-log" id="tv-log">ready</div>''
      + ''</div>'';

    # Live network throughput graphs, mirroring the admin dashboard's network
    # panel. One <svg> per direction; the polyline points are filled in by the
    # head script from /net-api, because Glance renders a widget server-side only
    # once and these need to move.
    netGraph = id: label: arrow:
      ''<div class="mb-net">''
      + ''<div class="mb-net-top">''
      + ''<span class="mb-net-now"><span class="mb-net-arrow">${arrow}</span>''
      + ''<span id="${id}-now">—</span> <span class="mb-net-unit">Mb/s</span></span>''
      + ''</div>''
      + ''<svg class="mb-net-svg" id="${id}-svg" viewBox="0 0 300 60" preserveAspectRatio="none">''
      + ''<polyline id="${id}-fill" class="mb-net-fill" points=""/>''
      + ''<polyline id="${id}-line" class="mb-net-line" points=""/>''
      + ''</svg>''
      + ''<div class="mb-net-foot">${label} · peak <span id="${id}-peak">—</span> over 60s</div>''
      + ''</div>'';

    netMarkup =
      ''<div class="mb-nets">''
      + netGraph "net-down" "download" "↓"
      + netGraph "net-up" "upload" "↑"
      + ''</div>''
      + ''<div class="mb-net-iface" id="net-iface">sampled every 2s</div>'';

    # Split the master switch away from the individual lamps under their own
    # headings — tapping "All Lights" by accident when you wanted one lamp is an
    # easy mistake when everything sits in one undifferentiated stack.
    lightCards =
      ''<div class="mb-sec">Everything</div>''
      + lib.concatMapStrings lightCard (lib.filter (l: l.hero) lights)
      + ''<div class="mb-sec">Individual</div>''
      + lib.concatMapStrings lightCard (lib.filter (l: !l.hero) lights);

    marsbarConfig = pkgs.writeText "glance-marsbar.yml" ''
      server:
        host: 127.0.0.1
        port: ${toString glancePort}

      branding:
        logo-text: "✦"
        app-name: MarsBar
        hide-footer: true

      # Purple, deliberately distinct from Asgard's green so there is never any
      # doubt about which dashboard is on screen.
      theme:
        background-color: hsl(268, 26%, 9%)
        primary-color: hsl(272, 82%, 78%)
        positive-color: hsl(272, 62%, 68%)
        negative-color: hsl(348, 76%, 64%)

      document:
        head: |
          <style>
            /* Defined card edges — the widgets previously floated with almost no
               boundary, which made the page read as one undifferentiated list. */
            .widget {
              position: relative;
              border: 1px solid hsla(272, 50%, 66%, 0.26);
              border-radius: 18px;
              padding: 16px 15px 18px 38px;
              margin-bottom: 4px;
              background: hsla(270, 25%, 13%, 0.45);
              backdrop-filter: blur(6px);
            }

            /* ── Decorative vine rail ──────────────────────────────────────────
               A climbing stem with alternating green and orchid leaves, running
               down the inside of each widget's left edge. Inline SVG data URI, so
               it stays self-contained — the artifact CSP and this box's offline-
               first setup both rule out fetching an image from anywhere.
               pointer-events:none so it can never eat a tap meant for a switch. */
            .widget::before {
              content: "";
              position: absolute;
              left: 5px; top: 12px; bottom: 12px;
              width: 26px;
              pointer-events: none;
              opacity: 0.8;
              background-repeat: repeat-y;
              background-position: top center;
              background-image: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='26' height='140' viewBox='0 0 26 140'><path d='M13 0 C4 24 22 46 13 70 C4 94 22 116 13 140' fill='none' stroke='%236fc79a' stroke-width='1.5' opacity='.5'/><ellipse cx='6' cy='26' rx='6' ry='3.2' fill='%236fc79a' opacity='.5' transform='rotate(-32 6 26)'/><ellipse cx='20' cy='58' rx='6' ry='3.2' fill='%23c77fe0' opacity='.45' transform='rotate(32 20 58)'/><ellipse cx='6' cy='96' rx='6' ry='3.2' fill='%236fc79a' opacity='.5' transform='rotate(-32 6 96)'/><ellipse cx='20' cy='128' rx='6' ry='3.2' fill='%23c77fe0' opacity='.45' transform='rotate(32 20 128)'/></svg>");
            }

            /* Gradient hairline across the top — purple into green, tying the
               vine colour into the rest of the palette. */
            .widget::after {
              content: "";
              position: absolute;
              left: 14px; right: 14px; top: 0;
              height: 2px;
              border-radius: 2px;
              background: linear-gradient(to right, hsl(288, 72%, 68%), hsl(272, 70%, 70%), hsl(150, 50%, 60%), transparent);
            }
            .widget-header {
              margin-bottom: 14px;
              padding-bottom: 10px;
              border-bottom: 1px solid hsla(272, 40%, 66%, 0.16);
            }
            .widget-header .widget-title {
              letter-spacing: 0.14em;
              font-size: 0.82rem;
              font-weight: 700;
              color: hsl(272, 60%, 82%);
            }

            /* ── Media links — bigger, readable tap targets ── */
            .widget-type-monitor .monitor-site {
              border-radius: 12px;
              padding: 6px 4px;
              transition: background-color 0.2s ease;
            }
            .widget-type-monitor .monitor-site:active { background: hsla(272, 50%, 55%, 0.16); }
            .widget-type-monitor .monitor-site .title,
            .widget-type-monitor .monitor-site a {
              font-size: 1.02rem;
              font-weight: 600;
              color: hsl(270, 30%, 95%);
            }

            /* ── Light toggles ──────────────────────────────────────────────
               Single column at every width. This is a phone-only dashboard, so
               a two-up grid only bought cramped labels and smaller tap targets. */
            .mb-lights { display: flex; flex-direction: column; gap: 12px; }

            /* Section headings inside the Lights widget. The first sits flush;
               later ones get top space so the groups read as distinct blocks. */
            /* Phone-first: these were 0.78rem and read as fine print. Now a real
               heading, with a small leaf glyph and a rule running off to the right. */
            .mb-sec {
              display: flex;
              align-items: center;
              gap: 10px;
              font-size: 1.02rem;
              font-weight: 700;
              text-transform: uppercase;
              letter-spacing: 0.15em;
              color: hsl(272, 70%, 86%);
              padding: 0 2px 4px;
            }
            .mb-sec::before {
              content: "❧";
              font-size: 1.05rem;
              color: hsl(150, 45%, 62%);
              text-shadow: 0 0 10px hsla(150, 60%, 55%, 0.45);
            }
            .mb-sec::after {
              content: "";
              flex: 1;
              height: 1px;
              background: linear-gradient(to right, hsla(272, 60%, 72%, 0.45), hsla(150, 45%, 60%, 0.18), transparent);
            }
            .mb-sec + * { margin-top: -2px; }
            .mb-light + .mb-sec { margin-top: 18px; }

            .mb-light {
              display: flex;
              align-items: center;
              gap: 15px;
              width: 100%;
              padding: 18px 18px;
              border-radius: 16px;
              cursor: pointer;
              text-align: left;
              font: inherit;
              color: inherit;
              border: 2px solid hsla(272, 35%, 62%, 0.20);
              background: hsla(270, 28%, 20%, 0.35);
              transition: background 0.22s ease, border-color 0.22s ease, box-shadow 0.22s ease;
            }
            .mb-light:disabled { cursor: wait; opacity: 0.5; }

            /* ON — lit and glowing. OFF — flat and clearly dimmed. Four signals
               change together (border, fill, icon, switch) because one subtle
               tint was not readable at a glance, which was the original complaint. */
            .mb-light[data-mb-state="on"] {
              background: hsla(272, 60%, 44%, 0.30);
              border-color: hsl(272, 75%, 68%);
              box-shadow: 0 0 26px hsla(272, 80%, 60%, 0.22);
            }
            .mb-light[data-mb-state="off"] {
              background: hsla(270, 18%, 16%, 0.55);
              border-color: hsla(272, 20%, 55%, 0.16);
            }
            .mb-light[data-mb-state="unknown"] { opacity: 0.55; }

            /* The hero card (All Lights) reads as the primary control — a warmer,
               deeper shade than the individual lamps plus a gradient and an accent
               stripe down its leading edge, so "master switch" is obvious without
               reading a word of it. */
            .mb-hero {
              padding: 22px 18px;
              border-radius: 18px;
              position: relative;
              overflow: hidden;
              background: linear-gradient(135deg, hsla(288, 46%, 30%, 0.55), hsla(262, 44%, 24%, 0.45));
              border-color: hsla(288, 50%, 70%, 0.34);
            }
            .mb-hero::before {
              content: "";
              position: absolute;
              left: 0; top: 0; bottom: 0;
              width: 4px;
              background: linear-gradient(to bottom, hsl(288, 80%, 72%), hsl(150, 55%, 62%));
            }
            .mb-hero .mb-name { font-size: 1.34rem; }
            .mb-hero .mb-sub { font-size: 0.95rem; }
            .mb-hero .mb-ico { font-size: 2.1rem; }
            .mb-hero[data-mb-state="on"] {
              background: linear-gradient(135deg, hsla(288, 62%, 44%, 0.46), hsla(266, 58%, 38%, 0.38));
              border-color: hsl(288, 72%, 72%);
              box-shadow: 0 0 30px hsla(285, 80%, 62%, 0.26);
            }

            .mb-ico {
              font-size: 1.75rem;
              line-height: 1;
              width: 1.9rem;
              text-align: center;
              flex: none;
              color: hsla(272, 25%, 70%, 0.55);
              transition: color 0.22s ease, text-shadow 0.22s ease;
            }
            .mb-light[data-mb-state="on"] .mb-ico {
              color: hsl(272, 95%, 84%);
              text-shadow: 0 0 16px hsla(272, 92%, 74%, 0.9);
            }

            .mb-txt { display: flex; flex-direction: column; gap: 3px; flex: 1; min-width: 0; }
            /* Bigger and full-contrast — these were 0.95rem at partial opacity
               and were genuinely hard to read on a phone. */
            .mb-name {
              font-size: 1.1rem;
              font-weight: 600;
              letter-spacing: 0.01em;
              color: hsl(270, 30%, 96%);
              white-space: nowrap;
              overflow: hidden;
              text-overflow: ellipsis;
            }
            .mb-sub { font-size: 0.92rem; color: hsla(270, 20%, 90%, 0.60); }

            .mb-right { display: flex; flex-direction: column; align-items: center; gap: 7px; flex: none; }
            .mb-state {
              font-size: 0.76rem;
              font-weight: 700;
              text-transform: uppercase;
              letter-spacing: 0.14em;
              color: hsla(270, 20%, 88%, 0.45);
            }
            .mb-light[data-mb-state="on"] .mb-state { color: hsl(272, 95%, 84%); }

            /* A real sliding switch. The knob physically moves, which reads as
               on/off instantly without having to parse any text. */
            .mb-sw {
              position: relative;
              width: 54px; height: 31px;
              border-radius: 999px;
              flex: none;
              background: hsla(270, 12%, 48%, 0.28);
              border: 1px solid hsla(270, 20%, 62%, 0.22);
              transition: background 0.25s ease, border-color 0.25s ease;
            }
            .mb-sw::after {
              content: "";
              position: absolute; top: 3px; left: 3px;
              width: 23px; height: 23px;
              border-radius: 50%;
              background: hsl(270, 12%, 68%);
              transition: transform 0.25s ease, background 0.25s ease;
            }
            .mb-light[data-mb-state="on"] .mb-sw {
              background: hsl(272, 68%, 56%);
              border-color: hsl(272, 82%, 74%);
            }
            .mb-light[data-mb-state="on"] .mb-sw::after {
              transform: translateX(23px);
              background: hsl(0, 0%, 100%);
            }

            /* ── TV box (Eclipse) ── */
            .mb-tv { display: flex; flex-direction: column; gap: 12px; }
            .mb-tv-head { display: flex; align-items: center; gap: 12px; padding: 2px 2px 0; }
            .mb-tv-dot {
              width: 13px; height: 13px; border-radius: 50%; flex: none;
              background: hsla(270, 10%, 55%, 0.5);
              transition: background 0.25s ease, box-shadow 0.25s ease;
            }
            .mb-tv-dot.ok  { background: hsl(150, 62%, 56%); box-shadow: 0 0 14px hsla(150, 62%, 56%, 0.7); }
            .mb-tv-dot.bad { background: hsl(348, 76%, 64%); box-shadow: 0 0 14px hsla(348, 76%, 64%, 0.7); }
            .mb-tv-h { display: flex; flex-direction: column; gap: 2px; }
            .mb-tv-state { font-size: 1.12rem; font-weight: 600; color: hsl(270, 30%, 96%); }
            .mb-tv-sub { font-size: 0.88rem; color: hsla(270, 20%, 90%, 0.55); }

            .mb-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; }
            .mb-stat {
              display: flex; flex-direction: column; gap: 4px;
              padding: 11px 10px;
              border-radius: 12px;
              border: 1px solid hsla(272, 35%, 62%, 0.18);
              background: hsla(270, 25%, 18%, 0.35);
              min-width: 0;
            }
            .mb-stat-k {
              font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.12em;
              color: hsla(270, 20%, 90%, 0.45);
            }
            .mb-stat-v {
              font-size: 0.92rem; font-weight: 600; color: hsl(272, 70%, 86%);
              overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
            }

            /* Action cards reuse .mb-light's shape but never light up — they fire
               and return, so a toggle switch would be a lie. */
            .mb-act { background: hsla(270, 25%, 19%, 0.42); }
            .mb-act:disabled { cursor: wait; opacity: 0.5; }
            .mb-go { font-size: 1.5rem; color: hsla(272, 55%, 80%, 0.5); flex: none; }
            .mb-act.busy .mb-go { color: hsl(272, 80%, 82%); }

            .mb-log {
              font-size: 0.85rem;
              color: hsla(270, 20%, 90%, 0.55);
              padding: 11px 13px;
              border-radius: 11px;
              border: 1px solid hsla(272, 30%, 60%, 0.14);
              background: hsla(270, 22%, 12%, 0.5);
              min-height: 1.2em;
            }
            .mb-log.ok  { color: hsl(150, 55%, 72%); }
            .mb-log.bad { color: hsl(348, 76%, 74%); }

            /* ── Live network graphs ── */
            .mb-nets { display: flex; flex-direction: column; gap: 14px; }
            .mb-net {
              padding: 13px 14px 10px;
              border-radius: 13px;
              background: linear-gradient(170deg, hsla(270, 26%, 20%, 0.38), hsla(268, 22%, 14%, 0.16));
            }
            .mb-net-top { display: flex; align-items: baseline; justify-content: space-between; }
            .mb-net-now { font-size: 1.32rem; font-weight: 700; color: hsl(272, 75%, 86%); }
            .mb-net-arrow { margin-right: 6px; color: hsl(272, 70%, 74%); }
            .mb-net-unit { font-size: 0.78rem; font-weight: 500; color: hsla(270, 20%, 90%, 0.5); }
            .mb-net-svg { width: 100%; height: 58px; display: block; margin: 6px 0 4px; }
            .mb-net-line { fill: none; stroke: hsl(272, 72%, 74%); stroke-width: 1.6; vector-effect: non-scaling-stroke; }
            .mb-net-fill { fill: hsla(272, 70%, 62%, 0.16); stroke: none; }
            #net-up-line { stroke: hsl(198, 70%, 68%); }
            #net-up-fill { fill: hsla(198, 70%, 60%, 0.14); }
            #net-up-now .mb-net-arrow, .mb-net .mb-net-arrow { }
            .mb-net-foot { font-size: 0.76rem; color: hsla(270, 20%, 90%, 0.42); }
            .mb-net-iface { font-size: 0.74rem; color: hsla(270, 20%, 90%, 0.32); padding: 2px 2px 0; }
          </style>

          <script>
            // Light toggles.
            //
            // Glance injects widget markup with innerHTML, which never executes
            // <script>, so this must live in document.head — and event delegation
            // on `document` means it does not care when that markup arrives.
            //
            // Same-origin: tailscale serve mounts ha-bridge at /ha on this very
            // port, so there is no CORS preflight and no second host to authorise
            // in the ACL. The bridge holds the HA token server-side; nothing
            // secret reaches the page.
            (function () {
              var API = "/ha";

              function paint(entity, state) {
                var els = document.querySelectorAll('.mb-light[data-entity="' + entity + '"]');
                for (var i = 0; i < els.length; i++) {
                  els[i].setAttribute("data-mb-state", state === "on" ? "on" : "off");
                  var s = els[i].querySelector(".mb-state");
                  if (s) s.textContent = state === "on" ? "on" : "off";
                }
              }

              function refreshAll() {
                return fetch(API + "/states", { cache: "no-store" })
                  .then(function (r) { return r.json(); })
                  .then(function (m) {
                    Object.keys(m).forEach(function (k) { paint(k, m[k]); });
                  })
                  .catch(function () { /* keep whatever is on screen */ });
              }

              document.addEventListener("click", function (e) {
                if (!e.target.closest) return;
                var btn = e.target.closest(".mb-light[data-entity]");
                if (!btn || btn.disabled) return;

                var entity = btn.getAttribute("data-entity");
                var cell = btn.querySelector(".mb-state");
                btn.disabled = true;
                if (cell) cell.textContent = "···";

                fetch(API + "/toggle/" + encodeURIComponent(entity), { method: "POST" })
                  .then(function (r) { return r.json(); })
                  .then(function (d) {
                    btn.disabled = false;
                    // Toggling the group moves its members too, so repaint
                    // everything from the bridge rather than trusting one entity.
                    if (d && d.state) { paint(entity, d.state); refreshAll(); }
                    else if (cell) { cell.textContent = "error"; }
                  })
                  .catch(function () {
                    btn.disabled = false;
                    if (cell) cell.textContent = "error";
                  });
              });

              // Glance renders each widget server-side exactly once per page load
              // and has no client-side widget refresh, so without this poll the
              // states would silently go stale the moment someone used the HA app
              // or a wall switch.
              document.addEventListener("DOMContentLoaded", function () {
                refreshAll();
                // 3s, not 10s. HA state changes from her dashboard, the HA app,
                // an automation or a physical switch, and none of those notify
                // this page — 10s made a light flipped elsewhere feel broken.
                setInterval(refreshAll, 3000);
              });
            })();
          </script>

          <script>
            // TV box (Eclipse) controls — same shape as the light handler above:
            // delegated clicks so widget-injection timing never matters, and a
            // poll because Glance renders each widget server-side only once.
            //
            // Talks to eclipse-control via /eclipse on this same origin (tailscale
            // serve proxies it), so no CORS and nothing extra in her ACL.
            (function () {
              var API = "/eclipse-api";

              function set(id, txt) {
                var el = document.getElementById(id);
                if (el) el.textContent = txt;
              }

              function fmtUptime(sec) {
                if (!sec && sec !== 0) return "—";
                var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
                return h > 0 ? h + "h " + m + "m" : m + "m";
              }

              // "Display 3840x2160 @ 60.000000" -> "3840x2160 @ 60Hz"
              function fmtMode(mode) {
                if (!mode) return "—";
                var m = mode.replace(/^Display\s*/, "");
                return m.replace(/@\s*([0-9]+)(\.[0-9]+)?/, "@ $1Hz");
              }

              function paintTv(s) {
                var dot = document.getElementById("tv-dot");
                var up = s && s.reachable;
                if (dot) dot.className = "mb-tv-dot " + (up ? "ok" : "bad");
                set("tv-state", up ? "Eclipse online" : "Eclipse offline");
                set("tv-sub", up ? (s.error ? s.error : "ready") : "cannot reach the TV box");
                set("tv-kodi", up ? (s.kodi || "—") : "—");
                set("tv-mode", up ? fmtMode(s.mode) : "—");
                set("tv-uptime", up ? fmtUptime(s.uptime) : "—");

              }

              function refreshTv() {
                return fetch(API + "/status", { cache: "no-store" })
                  .then(function (r) { return r.json(); })
                  .then(paintTv)
                  .catch(function () { paintTv(null); });
              }

              function log(msg, cls) {
                var el = document.getElementById("tv-log");
                if (!el) return;
                el.textContent = msg;
                el.className = "mb-log" + (cls ? " " + cls : "");
              }

              document.addEventListener("click", function (e) {
                if (!e.target.closest) return;
                var btn = e.target.closest(".mb-act[data-act]");
                if (!btn || btn.disabled) return;

                var act = btn.getAttribute("data-act");
                var label = btn.querySelector(".mb-name");
                var name = label ? label.textContent : act;
                btn.disabled = true;
                btn.classList.add("busy");
                log(name + "…");

                fetch(API + "/act/" + encodeURIComponent(act), { method: "POST" })
                  .then(function (r) { return r.json().catch(function () { return {}; }); })
                  .then(function (d) {
                    btn.disabled = false;
                    btn.classList.remove("busy");
                    // Prefer the panel's own message — for the speed test that
                    // IS the result ("43.3 down / 38.1 up Mbps over LAN"), so
                    // reporting a generic "done" would throw away the answer.
                    if (d && d.ok === false) { log(d.message || (name + " — failed"), "bad"); }
                    else { log((d && d.message) || (name + " — done"), "ok"); }
                    refreshTv();
                  })
                  .catch(function () {
                    btn.disabled = false;
                    btn.classList.remove("busy");
                    log(name + " — failed", "bad");
                  });
              });

              document.addEventListener("DOMContentLoaded", function () {
                refreshTv();
                setInterval(refreshTv, 15000);
              });
            })();
          </script>

          <script>
            // Live network throughput, same source the admin dashboard uses
            // (network-panel on :9555), proxied onto this origin at /net-api.
            //
            // Each trace is scaled to its OWN peak rather than a shared axis —
            // upload and download differ by orders of magnitude here, so a shared
            // scale would flatten one of them into a dead straight line.
            (function () {
              var API = "/net-api";
              var W = 300, H = 60;

              function draw(prefix, hist, peak) {
                var line = document.getElementById(prefix + "-line");
                var fill = document.getElementById(prefix + "-fill");
                if (!line || !hist || !hist.length) return;
                var max = Math.max(peak || 0, 0.01);
                var n = hist.length;
                var pts = [];
                for (var i = 0; i < n; i++) {
                  var x = (i / (n - 1)) * W;
                  var y = H - Math.min(1, hist[i] / max) * (H - 3) - 1.5;
                  pts.push(x.toFixed(1) + "," + y.toFixed(1));
                }
                line.setAttribute("points", pts.join(" "));
                // Close the path along the baseline so the area under it fills.
                if (fill) fill.setAttribute("points", "0," + H + " " + pts.join(" ") + " " + W + "," + H);
              }

              function set(id, txt) {
                var el = document.getElementById(id);
                if (el) el.textContent = txt;
              }

              function tickNet() {
                fetch(API + "/api", { cache: "no-store" })
                  .then(function (r) { return r.json(); })
                  .then(function (j) {
                    var l = j && j.live;
                    if (!l) return;
                    set("net-down-now", (l.down != null ? l.down.toFixed(1) : "—"));
                    set("net-up-now", (l.up != null ? l.up.toFixed(1) : "—"));
                    set("net-down-peak", (l.peak_down != null ? l.peak_down.toFixed(1) + " Mb/s" : "—"));
                    set("net-up-peak", (l.peak_up != null ? l.peak_up.toFixed(1) + " Mb/s" : "—"));
                    set("net-iface", (l.iface || "") + " · sampled every 2s · each trace scaled to its own peak");
                    draw("net-down", l.hist_down, l.peak_down);
                    draw("net-up", l.hist_up, l.peak_up);
                  })
                  .catch(function () { set("net-iface", "cannot reach the network panel"); });
              }

              document.addEventListener("DOMContentLoaded", function () {
                tickNet();
                setInterval(tickNet, 2000);
              });
            })();
          </script>

      pages:
        - name: Home
          # Single page, phone-only — the nav bar just showed one tab of itself.
          hide-desktop-navigation: true
          columns:
            - size: full
              widgets:
                # url points at the bridge purely so the widget fails VISIBLY when
                # ha-bridge is down. The cards are rendered statically and painted
                # by the script above — deliberately: the bridge keys are entity
                # ids like "switch.colour_lamp_switch", and Glance treats dots in
                # a key as a nested path, so .JSON.String on them cannot resolve.
                - type: custom-api
                  title: Lights
                  # Same reasoning as the Eclipse widget: the script paints every
                  # state and polls every 10s, so this fetch only needs to prove
                  # the bridge is alive — not run on every navigation.
                  cache: 1h
                  url: http://127.0.0.1:${toString bridgePort}/states
                  template: |
                    <div class="mb-lights">${lightCards}</div>

                - type: monitor
                  title: Media
                  cache: 2m
                  sites:
                    - title: Jellyfin
                      url: http://asgard:8096
                      icon: sh:jellyfin
                    - title: Jellyseerr
                      url: http://asgard:5055
                      icon: sh:jellyseerr

        # Second PAGE, not a second column. On mobile Glance renders pages as
        # pills along the bottom (mobile-navigation-page-links), which is the
        # "tap the dots and move across" she asked for; columns would just stack
        # and make her scroll. The desktop tab bar stays hidden on both pages.
        - name: Eclipse - ( Pi 5 )
          # Explicit slug: the auto-generated one from a name with brackets and
          # spaces is ugly and would change again on any future rename.
          slug: eclipse
          hide-desktop-navigation: true
          columns:
            - size: full
              widgets:
                # url points at eclipse-control so the widget fails visibly if the
                # panel is down; the markup is static and painted by the script.
                #
                # Long cache DELIBERATELY. This server-side fetch SSHes to the Pi
                # and cost ~0.7s on every single page load, which is most of what
                # made switching pages on a phone feel sluggish. Nothing here is
                # rendered from it — the head script paints every value and polls
                # every 15s — so re-fetching per navigation bought pure latency.
                - type: custom-api
                  title: Eclipse - ( Pi 5 )
                  cache: 1h
                  url: http://127.0.0.1:${toString eclipsePort}/status
                  template: |
                    ${tvMarkup}

                # Live throughput. Replaced the Eclipse speed-test tiles, which
                # were a one-off measurement she had to trigger; this is the
                # always-on view from the admin dashboard that she actually asked
                # for. Painted entirely by the head script, hence the long cache.
                - type: custom-api
                  title: Network
                  cache: 1h
                  url: http://127.0.0.1:${toString netPort}/api
                  template: |
                    ${netMarkup}
    '';
  in {
    # ── Glance instance ─────────────────────────────────────────────────────
    # Separate unit from the main `glance.service` so restarting one never takes
    # the other down, and so her dashboard cannot be broken by an edit to the
    # admin config.
    systemd.services.glance-marsbar = {
      description = "Glance dashboard for the marsbar tailnet node";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.glance}/bin/glance --config ${marsbarConfig}";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
      };
    };

    # ── Second tailscaled: the `marsbar` node ───────────────────────────────
    # userspace-networking means no second TUN device and no routing tangle with
    # the host's own tailscale0 — connections terminate inside this daemon and are
    # proxied to loopback by `tailscale serve`.
    #
    # --port=0 picks a random WireGuard port so it cannot collide with the main
    # tailscaled on 41641.
    #
    # --statedir (a DIRECTORY), not --state (a file): tailscaled needs a var root to
    # store provisioned TLS certs in, and with only --state it has none — `tailscale
    # cert` fails "500 Internal Server Error: no TailscaleVarRoot" and every HTTPS
    # handshake dies with a TLS internal error. The node identity is unaffected, since
    # tailscaled looks for tailscaled.state inside the statedir, which is where the
    # existing file already lives.
    #
    # That failure is nastier than it sounds: Brave upgrades http:// to https:// by
    # default (Chrome does not), so a broken HTTPS endpoint makes the dashboard
    # unreachable in Brave while still working fine in Chrome.
    systemd.services.tailscaled-marsbar = {
      description = "tailscaled for the marsbar node";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = ''
          ${pkgs.tailscale}/bin/tailscaled \
            --statedir=/var/lib/tailscale-marsbar \
            --socket=${tsSocket} \
            --tun=userspace-networking \
            --port=0
        '';
        RuntimeDirectory = "tailscale-marsbar";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "tailscale-marsbar";
        StateDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # ── Join the tailnet + publish the serve proxy ──────────────────────────
    systemd.services.marsbar-tailscale-up = {
      description = "Authenticate the marsbar node and publish its serve config";
      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled-marsbar.service" "glance-marsbar.service" ];
      requires = [ "tailscaled-marsbar.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        # tailscaled creates its socket a beat after the unit starts.
        for _ in $(seq 1 60); do
          [ -S ${tsSocket} ] && break
          sleep 1
        done

        state=$(${ts} status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState' 2>/dev/null || echo Unknown)
        if [ "$state" != "Running" ]; then
          # --accept-dns=false is LOAD-BEARING: without it this second daemon
          # fights the host's primary tailscaled over /etc/resolv.conf and can
          # break DNS for every service on Asgard.
          ${ts} up \
            --hostname=marsbar \
            --authkey="file:/run/secrets/tailscale-auth-key" \
            --accept-dns=false \
            --accept-routes=false
        fi

        # Idempotent — serve config is persisted in this node's state.
        ${ts} serve --bg --http=${toString servePort} http://127.0.0.1:${toString glancePort}
        ${ts} serve --bg --http=${toString servePort} --set-path=/ha http://127.0.0.1:${toString bridgePort}

        # Eclipse TV-box API, same trick as /ha — proxied onto this origin so she
        # never needs a grant on asgard:9554.
        #
        # ⚠ The mount path MUST NOT collide with a Glance page slug. This was
        # `/eclipse`, and once the page was renamed to slug `eclipse` the serve
        # proxy shadowed Glance's own route: hitting /eclipse returned the raw
        # (green, unthemed) control panel instead of her dashboard page, and that
        # panel — loaded without its trailing slash — resolved its relative
        # fetch('status') to /status, so it showed "cannot reach eclipse-control".
        # Two bugs from one name clash. Keep API mounts on an `-api` suffix that
        # no page slug will ever take.
        ${ts} serve --bg --http=${toString servePort} --set-path=/eclipse-api http://127.0.0.1:${toString eclipsePort}

        # Live network throughput (Asgard's enp3s0), for the graphs on her Eclipse
        # page. Same `-api` suffix rule as above so it can never shadow a page slug.
        ${ts} serve --bg --http=${toString servePort} --set-path=/net-api http://127.0.0.1:${toString netPort}

        # HTTP ONLY — deliberately no HTTPS/443 here.
        #
        # An HTTPS endpoint was tried (for a secure context, so Chrome would drop the
        # address strip it pins on installed PWAs served over HTTP) and then removed,
        # because it broke Brave outright: Brave upgrades http:// to https:// by default
        # but KEEPS THE PORT, so http://marsbar:1111 became https://marsbar:1111 — a port
        # with no TLS listener — while Chrome, which does not upgrade, kept working.
        # Serving TLS on 1111 would not fix that either: the cert is issued for
        # marsbar.<tailnet>.ts.net, so an https://marsbar:1111 URL fails name validation.
        #
        # If HTTPS is ever revisited, the working URL is the FQDN on 443 with no port
        # (https://marsbar.<tailnet>.ts.net), the ACL grant needs tcp:443, and teardown
        # must be explicit — `tailscale serve --https=443 off` — because serve config is
        # persisted in node state and deleting these lines does NOT remove it.
      '';
    };
  };
}
