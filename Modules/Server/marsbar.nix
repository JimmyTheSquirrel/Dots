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
  #                                      ├── /             → 127.0.0.1:8890  Glance
  #                                      ├── /ha/*         → 127.0.0.1:9556  ha-bridge
  #                                      ├── /eclipse-api/* → 127.0.0.1:9554  eclipse-control
  #                                      └── /net-api/*    → 127.0.0.1:9555  network-panel
  #
  # Only Glance itself binds loopback-only. The other three are shared with the
  # admin dashboard, which calls them directly over Asgard's own tailnet address,
  # so they listen on 0.0.0.0 — kept off the LAN by the firewall (none of their
  # ports is in allowedTCPPorts; only tailscale0 is trusted). Nothing here opens a
  # port either: the serve proxy terminates inside tailscaled, so the LAN and even
  # Asgard's own tailnet node cannot reach this dashboard.
  # ══════════════════════════════════════════════════════════════════════════
  flake.nixosModules.marsbar = { config, pkgs, lib, ... }:
  let
    glancePort = 8890; # loopback-only Glance for this dashboard
    servePort = 1111;  # the port she actually types: marsbar:1111
    bridgePort = 9556; # ha-bridge from Modules/Server/home-assistant.nix
    eclipsePort = 9554; # eclipse-control from Modules/Server/eclipse.nix (drives the Pi over SSH)
    netPort = 9555;     # network-panel from Modules/Server/network.nix (Asgard's live throughput)

    tsDir = "/run/tailscale-marsbar";
    tsSocket = "${tsDir}/tailscaled.sock";
    ts = "${pkgs.tailscale}/bin/tailscale --socket=${tsSocket}";

    inventory = import ./_plugs.nix;

    # ── Assets ──────────────────────────────────────────────────────────────
    # The CSS and JS live in real files and are served by Glance from its assets
    # dir (/assets/…), not pasted into the YAML. They used to be ~500 lines of
    # Nix-string inside a `document.head: |` block scalar, where one mis-indented
    # line silently ended the scalar and broke the whole config.
    #
    # lights.js is SHARED with the main Glance — one client, so both dashboards
    # behave the same and a fix lands on both.
    assetFiles = {
      "lights.js" = ../../Resources/Glance/lights.js;
      "marsbar.js" = ../../Resources/MarsBar/marsbar.js;
      "marsbar.css" = ../../Resources/MarsBar/marsbar.css;
    };
    marsbarAssets = pkgs.linkFarm "glance-marsbar-assets" assetFiles;

    # Glance serves /assets/ with a 2h Cache-Control, so a script URL that never
    # changes would keep running the OLD code on her phone for up to two hours
    # after a deploy. The content hash in the query string makes every edit a new
    # URL. (custom-css-file needs no help: Glance stamps that one itself.)
    asset = name:
      "/assets/${name}?v=${builtins.substring 0 10 (builtins.hashFile "sha256" assetFiles.${name})}";

    # ── Lights ──────────────────────────────────────────────────────────────
    # Generated from Modules/Server/_plugs.nix — the same inventory that builds
    # ha-bridge's ALLOWED set and the HA group, so a lamp drawn here can never be
    # one the bridge refuses, and Asgard's and Eclipse's relays (`light = false`)
    # can never be drawn here at all. The bridge is still the real boundary: a
    # button only draws something, the bridge decides whether it does anything
    # (403 otherwise).
    hero = {
      inherit (inventory.group) entity members;
      inherit (inventory.group.her) name sub icon;
      hero = true;
    };
    lamps = map (p: {
      inherit (p) entity icon;
      name = p.her.name or p.name;
      sub = p.her.sub or p.room;
      hero = false;
      members = [ ];
    }) inventory.lights;

    # The Lights widget's custom-api fetch returns the bridge's /states map, so
    # each tile renders with its REAL state already in data-ha-state — no grey
    # "unknown" flash and no reflow while the stream connects. The keys are
    # entity ids, and Glance resolves `.JSON.String` paths with gjson, where a
    # dot means "nested": `switch.x` would look for {"switch": {"x": …}}.
    # Escaping the dot (`switch\.x`) makes it a literal key. Written `\\.` here
    # because the Go template string literal unescapes it once.
    stateOf = entity:
      ''{{ .JSON.String "${builtins.replaceStrings [ "." ] [ "\\\\." ] entity}" }}'';

    # One tile. A <button>, so it is focusable and gets the right semantics for
    # free; data-ha-* is the contract with lights.js (see the top of that file).
    lightCard = l: let
      members = lib.optionalString (l.members != [ ])
        " data-ha-members=\"${lib.concatStringsSep " " l.members}\"";
    in ''
      <button type="button" class="mb-light${lib.optionalString l.hero " mb-hero"}" data-ha-entity="${l.entity}" data-ha-toggle${members} data-ha-state="${stateOf l.entity}">
        <span class="mb-ico" aria-hidden="true">${l.icon}</span>
        <span class="mb-txt"><span class="mb-name">${l.name}</span><span class="mb-sub">${l.sub}</span></span>
        <span class="mb-right"><span class="mb-state"></span><span class="mb-sw" aria-hidden="true"></span></span>
      </button>
    '';

    # Split the master switch away from the individual lamps under their own
    # headings — tapping "All Lights" by accident when you wanted one lamp is an
    # easy mistake when everything sits in one undifferentiated stack.
    lightsMarkup = ''
      <div class="mb-lights">
        <div class="mb-sec">Everything<span class="mb-live" aria-live="polite"><i></i><span data-ha-link-label>Connecting…</span></span></div>
        ${lightCard hero}
        <div class="mb-sec">Individual</div>
        ${lib.concatMapStrings lightCard lamps}
      </div>
    '';

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

    tvCard = a: ''
      <button type="button" class="mb-light mb-act" data-act="${a.act}">
        <span class="mb-ico" aria-hidden="true">${a.icon}</span>
        <span class="mb-txt"><span class="mb-name">${a.name}</span><span class="mb-sub">${a.sub}</span></span>
        <span class="mb-go" aria-hidden="true">›</span>
      </button>
    '';

    tvStat = id: label: ''
      <div class="mb-stat"><span class="mb-stat-k">${label}</span><span class="mb-stat-v" id="${id}">—</span></div>
    '';

    # Every value is painted by marsbar.js from /eclipse-api/status. Each slot
    # holds a placeholder of the right height from the start, so nothing jumps
    # when the first answer lands.
    tvMarkup = ''
      <div class="mb-tv" id="tv-box" data-tv="checking">
        <div class="mb-tv-head">
          <span class="mb-tv-dot"></span>
          <span class="mb-tv-h"><span class="mb-tv-state" id="tv-state">Checking…</span><span class="mb-tv-sub" id="tv-sub">contacting the TV box</span></span>
        </div>
        <div class="mb-stats">
          ${tvStat "tv-kodi" "Kodi"}
          ${tvStat "tv-mode" "Display"}
          ${tvStat "tv-uptime" "Uptime"}
        </div>
        <div class="mb-sec">Controls</div>
        <div class="mb-acts">
          ${lib.concatMapStrings tvCard tvActions}
        </div>
        <div class="mb-log" id="tv-log" role="status">Ready</div>
      </div>
    '';

    # Live network throughput graphs, mirroring the admin dashboard's network
    # panel. One <svg> per direction; the polyline points are filled in by
    # marsbar.js from /net-api, because Glance renders a widget server-side only
    # once and these need to move.
    netGraph = id: label: arrow: ''
      <div class="mb-net mb-net-${label}">
        <div class="mb-net-top">
          <span class="mb-net-now"><span class="mb-net-arrow">${arrow}</span><span id="${id}-now">—</span> <span class="mb-net-unit">Mb/s</span></span>
          <span class="mb-net-label">${label}</span>
        </div>
        <svg class="mb-net-svg" id="${id}-svg" viewBox="0 0 300 60" preserveAspectRatio="none"><polyline id="${id}-fill" class="mb-net-fill" points=""/><polyline id="${id}-line" class="mb-net-line" points=""/></svg>
        <div class="mb-net-foot">peak <span id="${id}-peak">—</span> over 60s</div>
      </div>
    '';

    netMarkup = ''
      <div class="mb-nets">
        ${netGraph "net-down" "download" "↓"}
        ${netGraph "net-up" "upload" "↑"}
      </div>
      <div class="mb-net-iface" id="net-iface">sampled every 2s</div>
    '';

    # ── The Glance config ───────────────────────────────────────────────────
    # Built as a Nix attrset and serialised by pkgs.formats.yaml, NOT written as
    # YAML text. The text version had to keep every card on ONE line: Nix '' strings
    # strip common indentation, so multi-line HTML interpolated into a YAML block
    # scalar arrived with its continuation lines at column 0 — under the scalar's
    # required indent — which silently ended the scalar ("could not find expected
    # ':'"). A real serialiser quotes and indents for us, so markup can be written
    # as markup.
    marsbarConfig = (pkgs.formats.yaml { }).generate "glance-marsbar.yml" {
      server = {
        host = "127.0.0.1";
        port = glancePort;
        assets-path = "${marsbarAssets}";
      };

      branding = {
        logo-text = "✦";
        app-name = "MarsBar";
        hide-footer = true;
      };

      # Purple, deliberately distinct from Asgard's green so there is never any
      # doubt about which dashboard is on screen.
      theme = {
        background-color = "hsl(268, 26%, 9%)";
        primary-color = "hsl(272, 82%, 78%)";
        positive-color = "hsl(272, 62%, 68%)";
        negative-color = "hsl(348, 76%, 64%)";
        custom-css-file = "/assets/marsbar.css";
      };

      # `defer`: run after the document is parsed, in order. Both wait for
      # Glance's widget markup themselves (it arrives later, via innerHTML).
      document.head = ''
        <script src="${asset "lights.js"}" data-api="/ha" defer></script>
        <script src="${asset "marsbar.js"}" defer></script>
      '';

      pages = [
        {
          name = "Home";
          # Phone-first: the desktop tab bar is hidden on both pages; on a
          # phone Glance lists the pages in its bottom navigation instead.
          hide-desktop-navigation = true;
          # Caps the column on a desktop screen. No effect on a phone.
          width = "slim";
          columns = [
            {
              size = "full";
              widgets = [
                # url points at the bridge so the widget fails VISIBLY when
                # ha-bridge is down — and its /states answer is what renders
                # each tile's initial state (see stateOf above). The bridge
                # answers from memory, so a 1s cache costs nothing and keeps
                # that first paint honest; lights.js takes over from there
                # with the live stream.
                {
                  type = "custom-api";
                  title = "Lights";
                  cache = "1s";
                  url = "http://127.0.0.1:${toString bridgePort}/states";
                  template = lightsMarkup;
                }
                {
                  type = "monitor";
                  title = "Media";
                  cache = "2m";
                  sites = [
                    { title = "Jellyfin"; url = "http://asgard:8096"; icon = "sh:jellyfin"; }
                    { title = "Jellyseerr"; url = "http://asgard:5055"; icon = "sh:jellyseerr"; }
                  ];
                }
              ];
            }
          ];
        }

        # Second PAGE, not a second column. On mobile Glance renders pages in
        # its bottom navigation (mobile-navigation-page-links), which is the
        # "tap and move across" she asked for; columns would just stack and
        # make her scroll. The desktop tab bar stays hidden on both pages.
        {
          name = "Eclipse - ( Pi 5 )";
          # Explicit slug: the auto-generated one from a name with brackets and
          # spaces is ugly and would change again on any future rename.
          slug = "eclipse";
          hide-desktop-navigation = true;
          width = "slim";
          columns = [
            {
              size = "full";
              widgets = [
                # url points at eclipse-control so the widget fails visibly if
                # the panel is down; the markup is static and painted by
                # marsbar.js.
                #
                # Long cache DELIBERATELY. This server-side fetch SSHes to the
                # Pi and cost ~0.7s on every single page load, which is most of
                # what made switching pages on a phone feel sluggish. Nothing
                # here is rendered from it — marsbar.js paints every value and
                # polls every 15s while the page is visible — so re-fetching
                # per navigation bought pure latency.
                {
                  type = "custom-api";
                  title = "Eclipse - ( Pi 5 )";
                  cache = "1h";
                  url = "http://127.0.0.1:${toString eclipsePort}/status";
                  template = tvMarkup;
                }

                # Live throughput. Replaced the Eclipse speed-test tiles, which
                # were a one-off measurement she had to trigger; this is the
                # always-on view from the admin dashboard that she actually
                # asked for. Painted entirely by marsbar.js (every 2s, visible
                # tab only), hence the long cache.
                {
                  type = "custom-api";
                  title = "Network";
                  cache = "1h";
                  url = "http://127.0.0.1:${toString netPort}/api";
                  template = netMarkup;
                }
              ];
            }
          ];
        }
      ];
    };
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

        # ha-bridge, for the light tiles. Plain HTTP reverse proxy, and that is
        # enough for its /events stream too: serve is a Go ReverseProxy, which
        # flushes text/event-stream responses immediately instead of buffering
        # them, and the bridge pings every 15s so the stream is never idle.
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
