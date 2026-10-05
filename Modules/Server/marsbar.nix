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
    # Everything but marsbar.css is SHARED with the main Glance — the same
    # light client, the same Eclipse panel, the same network card — so she has
    # every control he has, both dashboards behave the same, and a fix lands on
    # both. Only the look differs: cards.css is written against colour tokens,
    # and marsbar.css defines them in her purple.
    assetFiles = {
      "marsbar.css" = ../../Resources/MarsBar/marsbar.css;
      # the vine rail down each card and the blossom that crowns it (marsbar.css)
      "vine.svg" = ../../Resources/MarsBar/vine.svg;
      "bloom.svg" = ../../Resources/MarsBar/bloom.svg;
      "cards.css" = ../../Resources/Glance/cards.css;
      "dash.js" = ../../Resources/Glance/dash.js;
      "lights.js" = ../../Resources/Glance/lights.js;
      "eclipse.js" = ../../Resources/Glance/eclipse.js;
      "net.js" = ../../Resources/Glance/net.js;
      # her colour picker (the "marsbar" profile of Asgard's own picker) and the
      # cats it can put all over the page
      "theme.js" = ../../Resources/Glance/theme.js;
      "cats.css" = ../../Resources/Glance/cats.css;
    };
    marsbarAssets = pkgs.linkFarm "glance-marsbar-assets" assetFiles;

    # Glance serves /assets/ with a 2h Cache-Control, so a script URL that never
    # changes would keep running the OLD code on her phone for up to two hours
    # after a deploy. The content hash in the query string makes every edit a new
    # URL. (custom-css-file needs no help: Glance stamps that one itself.)
    asset = name:
      "/assets/${name}?v=${builtins.substring 0 10 (builtins.hashFile "sha256" assetFiles.${name})}";

    # theme.js keeps her recoloured vine and blossom in localStorage, keyed to
    # this; a change to either drawing (or to how it is recoloured) redraws them.
    artVersion = builtins.substring 0 10 (builtins.hashString "sha256"
      (lib.concatMapStrings (f: builtins.hashFile "sha256" assetFiles.${f}) [ "vine.svg" "bloom.svg" "theme.js" ]));

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

    # ── Eclipse + network: the shared live cards ────────────────────────────
    # The SAME panel as the admin dashboard's Eclipse page (Resources/Glance/
    # eclipse.js, from eclipse-control's /events stream through her
    # /eclipse-api serve path): status, what the TV is playing, every action —
    # Restart Kodi, Sync library, Test link, the Jellyfin path, Reboot — the
    # Wolf streams Sisyphus is serving with an End button for a stuck one, and
    # the activity log both dashboards share. She is the one in front of the
    # TV when it locks up, so nothing is held back; the two that interrupt
    # playback (Reboot, switching the Jellyfin path) and ending a stream take a
    # second tap.
    #
    # It used to be a hand-built copy here: three actions, a 15 s poll, and
    # its own script (marsbar.js) — which is how the two drifted apart.
    #
    # The network card is net.js through /net-api, read-only: no "Run now",
    # since a speed test pauses SABnzbd and that is an admin call.
    liveCard = import ./_livecard.nix lib;

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

      # `defer`: run after the document is parsed, in order — dash.js first,
      # the helpers the others use. Each waits for Glance's widget markup
      # itself (it arrives later, via innerHTML). Every API is on THIS origin,
      # through the serve proxy below: data-api is a path, not a port.
      # Posters load from Jellyfin directly — asgard:8096 is in her ACL grant
      # (it is the Jellyfin she watches).
      #
      # theme.js is the one script NOT deferred: it sets her picked colour
      # before the page paints, so a pick never flashes purple first.
      document.head = ''
        <link rel="stylesheet" href="${asset "cards.css"}">
        <script src="${asset "theme.js"}" data-profile="marsbar" data-default="#ca99f5" data-art="${asset "vine.svg"},${asset "bloom.svg"}" data-art-v="${artVersion}" data-cats="${asset "cats.css"}"></script>
        <script src="${asset "dash.js"}" defer></script>
        <script src="${asset "lights.js"}" data-api="/ha" defer></script>
        <script src="${asset "eclipse.js"}" data-api="/eclipse-api" data-jellyfin="http://asgard:8096" defer></script>
        <script src="${asset "net.js"}" data-api="/net-api" data-readonly defer></script>
      '';

      # ONE page, three COLUMNS — Home · Eclipse · Network. On a phone Glance
      # shows one column at a time and puts a dot per column in its bottom bar,
      # so she swaps sections with a single tap on a dot. (Separate PAGES —
      # how this was before — live behind the ☰ menu instead: open it, find
      # the page, tap it. She only uses this on her phone.) Opens on the first
      # full column, Home. No `width = "slim"`: slim allows only two columns;
      # on a desktop the three simply sit side by side.
      pages = [
        {
          name = "MarsBar";
          slug = "home";
          hide-desktop-navigation = true;
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
            {
              size = "full";
              widgets = [
                (liveCard { id = "ec-main"; title = "Eclipse - ( Pi 5 )"; badge = "ec-live"; })
                (liveCard { id = "ec-tv"; title = "On the TV"; })
                (liveCard { id = "ec-wolf"; title = "Game streams"; })
                (liveCard { id = "ec-ctl"; title = "Controllers"; })
                (liveCard { id = "ec-log"; title = "Activity"; })
              ];
            }
            {
              size = "small";
              widgets = [
                (liveCard { id = "nw"; title = "Network"; badge = "nw-live"; })
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
