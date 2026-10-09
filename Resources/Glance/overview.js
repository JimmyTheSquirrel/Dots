// ════════════════════════════════════════════════════════════════════════════
// overview.js — the Overview page (#ov-map): how it all works, top-down.
//
// Read it like a family tree, top to bottom:
//
//   CONTROL CENTRE   Sisyphus — the repo lives here; it builds and deploys
//         │          every other machine over the tailnet
//   ┌─────┼─────┐
//   Elektra  ASGARD  Apollo        the machines it deploys
//            │
//   ┌─ ASGARD, opened up ──────────────────────────────────────────────┐
//   │ OPEN TO THE INTERNET   anyone → Cloudflare Tunnel → 3 services    │
//   │ TAILNET ONLY           you, her → Tailscale → everything else     │
//   │ INSIDE THE VPN TUNNEL  SABnzbd → Mullvad → Usenet                 │
//   │ AROUND THE HOUSE       the TV, the plugs, the home network        │
//   │ THE DISKS              NVMe · the pool · photos                   │
//   └───────────────────────────────────────────────────────────────────┘
//
// Every row reads left to right — who or what comes in, the door it comes
// through, what it reaches — so the only arrows are between neighbours in a
// row and nothing ever crosses anything. It is plain HTML (flex rows), not a
// drawing: a phone stacks the rows and turns the arrows downward.
//
//   tap a box     it lights up, with what it talks to (EDGES) lit softer, and
//                 the panel under the tree says what it is, its port, why
//   a story chip  walks one path ("A film, start to finish", …) a step at a
//                 time: each step's boxes light up and get the step's number,
//                 so the path reads 1 → 2 → 3 across the tree; a caption says
//                 what's happening. Plays itself; ‹ › step, ❚❚ pauses
//
// A picture of the CONFIG, not a live view — nothing polls. A new service,
// port or connection is a line in NODES (+ its place in TREE below) and
// EDGES, maybe a STORIES step. Colours are HUD tokens only (var(--hud…),
// --s1…--s6, --ag-*), so the viewer's picked colour recolours it.
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";
  if (!window.Dash) return;
  var D = window.Dash;
  var still = window.matchMedia ? matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };

  // ── what's on it ───────────────────────────────────────────────────────────
  // k: box kind — host / svc (a service on Asgard) / door (a way in or out) /
  // out (outside Asgard) / who (people). p: port(s). w: a warning.
  var NODES = [
    { id: "sisyphus", k: "host", t: "Sisyphus", s: "the control centre · your desktop",
      d: "Where the repo lives — ~/Dots, the only copy anywhere. system-rebuild builds every machine here and pushes it to them over the tailnet. It also runs Wolf, which streams games to the TV." },
    { id: "kitkat", k: "host", t: "Elektra", s: "her desktop",
      d: "Her NVIDIA machine running Hyprland. Built on Sisyphus and pushed to her over the tailnet, like everything else." },
    { id: "asgard", k: "host", t: "Asgard", s: "the server · opened up below",
      d: "The server: an Intel i5-14400, a 1 TB NVMe, 8 TB + 12 TB drives. Everything on it is declared in the repo (Modules/Server/) — a fresh install is a clone and one rebuild from Sisyphus." },
    { id: "apollo", k: "host", t: "Apollo", s: "the installer USB",
      d: "A USB stick that boots any computer into a live system, joins the tailnet by itself, and lets Sisyphus install one of the machines onto it from scratch." },

    { id: "guests", k: "who", t: "Anyone with the link", s: "family & friends · no app",
      d: "No app, no VPN, no account on the tailnet — just a web address. Only the three services in this row can be reached this way." },
    { id: "cf", k: "door", t: "Cloudflare Tunnel", s: "*.bifrost-vault.com",
      d: "The only way in from the internet. cloudflared on Asgard dials OUT to Cloudflare, so no port is open on the router. Three names: jellyfin., requests. and photos.bifrost-vault.com. Uploads are capped at 30 Mbit so a remote stream never lags a game at home." },
    { id: "jellyfin", k: "svc", t: "Jellyfin", s: "films · TV · music", p: "8096",
      d: "The media server. Reads the pool and streams to the TV, phones and browsers — transcoding on the Intel GPU (QuickSync) when a device can't play the original." },
    { id: "seerr", k: "svc", t: "Jellyseerr", s: "ask for a film or show", p: "5055",
      d: "The request page. Pick something and it goes to Radarr or Sonarr with the right quality profile — no logging into the arrs." },
    { id: "immich", k: "svc", t: "Immich", s: "photos", p: "2283", w: "No backup yet — the one thing here that can't be downloaded again.",
      d: "The photo library, with its own database. It lives on plain ext4 on the 8 TB drive, not in the pool." },

    { id: "you", k: "who", t: "You", s: "phone · laptop · anywhere",
      d: "Your own devices, all on the tailnet — so everything in this row answers wherever you are: home, work, 4G." },
    { id: "her", k: "who", t: "Her", s: "on the tailnet · limited access",
      d: "Her devices are on the tailnet too, but its rules (a Tailscale ACL) only let her reach the few things she uses — Jellyfin and Jellyseerr among them. Nothing else on Asgard answers her." },
    { id: "tailnet", k: "door", t: "Tailscale", s: "private mesh · WireGuard",
      d: "A private, encrypted network between your own devices (tailb54b82.ts.net). Almost everything on Asgard listens only here: its firewall trusts tailscale0 and nothing else." },
    { id: "abs", k: "svc", t: "Audiobookshelf", s: "audiobooks · ebooks", p: "13378",
      d: "Audiobooks and ebooks, with listening progress synced across devices. Shelfarr delivers into it." },
    { id: "suwayomi", k: "svc", t: "Suwayomi", s: "manga", p: "4567",
      d: "Manga reader and downloader. Some sources hide behind Cloudflare checks — FlareSolverr gets it past those." },
    { id: "arrs", k: "svc", t: "Sonarr · Radarr · Lidarr", s: "watch for TV · films · music", p: "8989 · 7878 · 8686",
      d: "They know what you want, watch for new releases, pick the best one their quality profile allows, hand it to SABnzbd, then rename it into the library." },
    { id: "prowlarr", k: "svc", t: "Prowlarr", s: "searches the indexers", p: "9696",
      d: "One place for the indexers. Every arr — and Shelfarr — searches through it." },
    { id: "indexers", k: "out", t: "Indexers", s: "on the internet",
      d: "Search engines for Usenet — NZBgeek, Miatrix and NzbPlanet. They say which posts make up a release; the files themselves come through the VPN row below." },
    { id: "shelfarr", k: "svc", t: "Shelfarr", s: "ask for a book", p: "5056",
      d: "Book and audiobook requests. Searches through Prowlarr, downloads through SABnzbd, delivers into Audiobookshelf. Wired up by books-setup.service." },
    { id: "house", k: "svc", t: "Housekeeping", s: "Recyclarr · Decluttarr · arr-policy",
      d: "Recyclarr keeps the quality profiles in step with the TRaSH guides (daily). Decluttarr clears stuck or failed downloads. arr-policy applies the rules the other two can't." },
    { id: "flare", k: "svc", t: "FlareSolverr", s: "gets past Cloudflare checks", p: "8191",
      d: "A headless browser that solves Cloudflare challenges for Suwayomi and Shelfarr." },
    { id: "ha", k: "svc", t: "Home Assistant", s: "the smart plugs", p: "8123",
      d: "Talks to the smart plugs. Its token never reaches a browser: ha-bridge (one of the live feeds) holds it, and only lets the dashboards switch the plugs on its list." },
    { id: "feeds", k: "svc", t: "Live feeds", s: "stats · network · Eclipse · lights", p: "9552 · 9555 · 9554 · 9556",
      d: "Small services that push live data to the dashboard: asgard-stats (the machine), network-panel (throughput, speed tests), eclipse-control (drives the TV box over SSH) and ha-bridge (the only thing allowed to flip a plug)." },
    { id: "glance", k: "svc", t: "Glance", s: "this dashboard", p: "8888",
      d: "What you're looking at. Every card is pushed live by the feeds — nothing on these pages polls." },
    { id: "tools", k: "svc", t: "Terminal & files", s: "ttyd · FileBrowser", p: "7681 · 8081",
      d: "A web terminal (the Terminal page) and a file manager for /data." },

    { id: "sab", k: "svc", t: "SABnzbd", s: "downloads", p: "8080",
      d: "Downloads from Usenet and unpacks onto the NVMe. It lives inside its own network namespace whose ONLY connection is the Mullvad tunnel — if the VPN drops, it has no network at all (a kill switch by design)." },
    { id: "mullvad", k: "door", t: "Mullvad VPN", s: "encrypted tunnel · Sydney",
      d: "WireGuard, in a network namespace of its own. SABnzbd's only way out; nothing else on Asgard uses it, so the rest of the server's traffic is never slowed or exposed by it." },
    { id: "usenet", k: "out", t: "Usenet providers", s: "FrugalUsenet + Newshosting",
      d: "Where the files actually come from: two providers on separate backbones, the second as a backup." },

    { id: "tv", k: "out", t: "Eclipse · the TV", s: "Pi 5 · Kodi · wired",
      d: "A Raspberry Pi 5 running LibreELEC and Kodi. Plays from Jellyfin over the home network, runs Moonlight for game streams from Sisyphus, and the dashboards drive it through eclipse-control over SSH. Not a Nix machine — its recipe is Claude/eclipse.md." },
    { id: "plugs", k: "out", t: "Smart plugs", s: "Athom · ESPHome · Wi-Fi",
      d: "The lights and the power figures on the Power page. Each plug reports its watts, volts and daily kWh to Home Assistant." },
    { id: "lan", k: "door", t: "Home network", s: "router · ethernet",
      d: "The house LAN. The TV is wired to it, Wi-Fi standing by. Asgard opens exactly one port on it on purpose: 9557, a speed-test sink with no controls — everything else is tailnet-only." },

    { id: "nvme", k: "svc", t: "NVMe · 1 TB", s: "NixOS · /downloads",
      d: "The system, every service's settings, and the download scratch space — fast, so unpacking never fights playback." },
    { id: "pool", k: "svc", t: "Media pool · ~19 TB", s: "8 TB + 12 TB · mergerfs",
      d: "Two drives merged into one /data/media. Each file lives whole on one drive, so losing a drive loses only its own files — all of which can be downloaded again. No RAID, on purpose." },
    { id: "photos", k: "svc", t: "Photos & state", s: "8 TB drive · plain ext4", w: "The photos have no backup yet.",
      d: "Immich's photos and the arrs' databases, mounted straight from the 8 TB drive rather than through the pool (databases and FUSE don't mix)." }
  ];
  var BY = {};
  NODES.forEach(function (n) { BY[n.id] = n; });

  // Who talks to whom — not drawn (that's what made the old map a tangle);
  // used to light a tapped box's neighbours and list them in the panel.
  var EDGES = [
    ["sisyphus", "kitkat", "deploys"], ["sisyphus", "asgard", "deploys"], ["sisyphus", "apollo", "builds the image"],
    ["sisyphus", "tv", "Wolf game streams"],
    ["guests", "cf", "a web address"], ["cf", "jellyfin", "streams"], ["cf", "seerr", "requests"], ["cf", "immich", "photos"],
    ["you", "tailnet", "connects"], ["her", "tailnet", "connects"], ["kitkat", "tailnet", "connects"],
    ["tailnet", "glance", "this page"], ["tailnet", "jellyfin", "streams"], ["tailnet", "seerr", "requests"],
    ["seerr", "arrs", "the request"], ["arrs", "prowlarr", "search"], ["prowlarr", "indexers", "query"],
    ["arrs", "sab", "grab"], ["arrs", "pool", "rename & import"],
    ["shelfarr", "prowlarr", "search"], ["shelfarr", "sab", "download"], ["shelfarr", "abs", "delivers"],
    ["shelfarr", "flare", "challenges"], ["suwayomi", "flare", "challenges"],
    ["house", "arrs", "profiles"], ["house", "sab", "clears stuck"],
    ["sab", "mullvad", "the only way out"], ["mullvad", "usenet", "download"], ["sab", "nvme", "unpack"],
    ["jellyfin", "pool", "reads"], ["abs", "pool", "reads"], ["suwayomi", "pool", "saves"], ["immich", "photos", "stores"],
    ["plugs", "ha", "Wi-Fi"], ["ha", "feeds", "plug states"], ["feeds", "glance", "live"],
    ["feeds", "tv", "drives over SSH"], ["tv", "lan", "wired"], ["lan", "jellyfin", "plays films"]
  ];

  // Each step: the boxes it lights, and what to say.
  var STORIES = [
    { id: "film", t: "A film, start to finish", steps: [
      [["you", "tailnet", "seerr"], "You ask for a film in Jellyseerr — from the sofa, or anywhere on the tailnet."],
      [["arrs"], "Jellyseerr hands the request to Radarr, with the “Asgard - Movies” quality profile."],
      [["prowlarr", "indexers"], "Radarr asks Prowlarr, and Prowlarr searches the indexers for releases."],
      [["sab"], "Radarr picks the best release its profile allows and sends it to SABnzbd."],
      [["mullvad", "usenet"], "SABnzbd downloads it from Usenet — only ever through the Mullvad tunnel."],
      [["nvme"], "It's unpacked on the fast NVMe…"],
      [["pool"], "…then Radarr renames it and moves it into the 19 TB pool."],
      [["jellyfin"], "Jellyfin notices it and adds it to the library."],
      [["lan", "tv"], "Press play on the TV: Eclipse streams it from Jellyfin over the home network."]
    ] },
    { id: "away", t: "Watching from anywhere", steps: [
      [["guests"], "A friend opens jellyfin.bifrost-vault.com — no app, no VPN."],
      [["cf"], "The Cloudflare Tunnel carries it in. No port is open on the router: Asgard dialled out to Cloudflare."],
      [["jellyfin", "pool"], "Jellyfin streams the file, transcoding on the Intel GPU if their device needs it."],
      [["you", "tailnet"], "You don't need the tunnel: on the tailnet, Jellyfin (and everything else) is direct."]
    ] },
    { id: "dash", t: "This dashboard", steps: [
      [["feeds"], "Small services on Asgard watch the machine, the network, the TV and the lights…"],
      [["glance"], "…and push every change to Glance the moment it happens. Nothing polls."],
      [["you", "tailnet"], "Your browser opens it over the tailnet and keeps a live stream per card."],
      [["plugs", "ha"], "Lights: the plugs report to Home Assistant; ha-bridge holds its token and only flips the plugs on its list."],
      [["tv"], "The TV panel's buttons go to eclipse-control, which drives the Pi over SSH."]
    ] },
    { id: "book", t: "A book", steps: [
      [["shelfarr"], "Ask for a book or an audiobook in Shelfarr."],
      [["prowlarr", "indexers"], "It searches through Prowlarr, like the arrs do."],
      [["sab", "mullvad", "usenet"], "SABnzbd downloads it, through the VPN tunnel."],
      [["abs", "pool"], "Shelfarr delivers it to Audiobookshelf, which keeps it in the pool."]
    ] },
    { id: "change", t: "Changing anything", steps: [
      [["sisyphus"], "Every machine is described in one repo — ~/Dots on Sisyphus, the only copy."],
      [["asgard"], "system-rebuild builds Asgard's new system on Sisyphus and pushes it over the tailnet; Asgard switches to it (any older version is one pick away in its boot menu)."],
      [["kitkat"], "Elektra, her desktop, is deployed the same way, from the same repo."],
      [["apollo"], "And a brand-new machine starts from the Apollo stick: boot it, and Sisyphus installs it over the tailnet."]
    ] },
    { id: "game", t: "Game night", steps: [
      [["sisyphus"], "Wolf on Sisyphus streams a game, in true 4K…"],
      [["lan", "tv"], "…to Moonlight on Eclipse. The pads pair straight to the TV box over Bluetooth."],
      [["feeds", "glance"], "A stuck stream can be ended from the dashboard."]
    ] }
  ];

  // ── the tree ───────────────────────────────────────────────────────────────
  // Asgard's rows, top to bottom. A row: its colour, heading, one line on who
  // gets in, then `flow` — boxes (ids) and → between them; a nested array is
  // a set of boxes side by side at that point. `groups`: sub-rows under a
  // heading. `note`: a sentence under the row.
  var ZONES = [
    { id: "public", c: "var(--s2)", icon: "globe", t: "Open to the internet", s: "anyone with the link — these three, and nothing else",
      flow: ["guests", "→", "cf", "→", ["jellyfin", "seerr", "immich"]],
      note: "Asgard dials out to Cloudflare, so no port is open on the router." },
    { id: "private", c: "var(--hud)", icon: "lock", t: "Tailnet only", s: "your devices, and hers — private and encrypted",
      flow: [["you", "her"], "→", "tailnet"],
      reach: "reaches everything in this row — and the three above",
      groups: [
        { t: "Watch & read", flow: [["abs", "suwayomi"]] },
        { t: "Getting new things", flow: ["arrs", "→", "prowlarr", "→", "indexers"], more: ["shelfarr", "house", "flare"] },
        { t: "Dashboards & control", flow: ["ha", "→", "feeds", "→", "glance"], more: ["tools"] }
      ] },
    { id: "vpn", c: "var(--hud2)", icon: "shield", t: "Inside the VPN tunnel", s: "SABnzbd only — its one way out is Mullvad",
      flow: ["sab", "⇒", "mullvad", "→", "usenet"],
      note: "Kill switch: if the tunnel drops, SABnzbd has no network at all. Nothing else on Asgard goes through it." },
    { id: "house", c: "var(--s5)", icon: "home", t: "Around the house", s: "on the home network, driven from the dashboard",
      flow: [["tv", "plugs"], "→", "lan"],
      note: "The TV plays from Jellyfin over the LAN; the plugs report to Home Assistant over Wi-Fi." },
    { id: "disks", c: "var(--s4)", icon: "disk", t: "The disks", s: "where everything above keeps its things",
      flow: [["nvme", "pool", "photos"]] }
  ];

  var ICON = {
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
    shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
    home: '<path d="M4 11l8-7 8 7v9H4z"/><path d="M10 20v-5h4v5"/>',
    disk: '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
    cog: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>'
  };
  function icon(k) { return '<svg class="ov-ico" viewBox="0 0 24 24" aria-hidden="true">' + ICON[k] + '</svg>'; }

  function esc(s) { return D.esc(String(s)); }
  function box(id, extra) {
    var n = BY[id];
    return '<button type="button" class="ov-box k-' + n.k + (extra ? " " + extra : "") + '" data-id="' + id + '">' +
      '<span class="ov-bt">' + esc(n.t) + (n.w ? '<i class="ov-warn" title="' + esc(n.w) + '"></i>' : "") + '</span>' +
      '<span class="ov-bs">' + esc(n.s) + '</span>' +
      (n.p ? '<code>:' + esc(n.p) + '</code>' : "") +
      '</button>';
  }
  function flow(parts, z) {
    return '<div class="ov-flow">' + parts.map(function (p) {
      if (p === "→" || p === "⇒") return '<i class="ov-arr' + (p === "⇒" ? " tunnel" : "") + '" aria-hidden="true"></i>';
      if (Array.isArray(p)) return '<div class="ov-set">' + p.map(function (id) { return box(id); }).join("") + '</div>';
      return box(p);
    }).join("") + '</div>';
  }
  function groups(gs) {
    return '<div class="ov-groups">' + gs.map(function (g) {
      return '<div class="ov-group"><div class="ov-gh">' + esc(g.t) + '</div>' + flow(g.flow) +
        (g.more ? '<div class="ov-set more">' + g.more.map(function (id) { return box(id); }).join("") + '</div>' : "") +
        (g.also ? '<div class="ov-also">' + esc(g.also) + '</div>' : "") + '</div>';
    }).join("") + '</div>';
  }

  function tree() {
    var h = '<div class="ov-tree">';
    h += '<div class="ov-tier"><span class="ov-tier-l">' + icon("cog") + 'Control centre</span>' + box("sisyphus", "root") + '</div>';
    h += '<div class="ov-fan" data-why="builds &amp; deploys every machine over the tailnet">' +
      '<div class="ov-kid">' + box("kitkat") + '</div>' +
      '<div class="ov-kid main">' + box("asgard", "server") + '</div>' +
      '<div class="ov-kid">' + box("apollo") + '</div></div>';
    h += '<div class="ov-server"><div class="ov-server-h"><b>Inside Asgard</b><span>sorted by who can reach it</span></div>';
    ZONES.forEach(function (z) {
      h += '<section class="ov-zone z-' + z.id + '" style="--c:' + z.c + '">' +
        '<div class="ov-zh">' + icon(z.icon) + '<b>' + esc(z.t) + '</b><span>' + esc(z.s) + '</span></div>' +
        flow(z.flow, z) +
        (z.groups ? '<div class="ov-reach">' + esc(z.reach) + '</div>' + groups(z.groups) : "") +
        (z.note ? '<div class="ov-note">' + esc(z.note) + '</div>' : "") +
        '</section>';
    });
    h += '</div></div>';
    return h;
  }

  // ── the card ───────────────────────────────────────────────────────────────
  var el = null, sel = null, story = null, timer = null, playing = true;

  function render() {
    el.innerHTML =
      '<div class="ov">' +
        '<div class="ov-stories" role="toolbar" aria-label="Walk through how things work">' +
          '<span class="ov-lead">Show me</span>' +
          STORIES.map(function (st) { return '<button type="button" class="ov-chip" data-story="' + st.id + '">' + esc(st.t) + '</button>'; }).join("") +
        '</div>' +
        '<div class="ov-cap" hidden></div>' +
        tree() +
        '<div class="ov-detail" aria-live="polite"></div>' +
        '<div class="ov-legend"><span><i class="l-box"></i>runs on the machine</span><span><i class="l-door"></i>a way in or out</span>' +
          '<span><i class="l-out"></i>outside Asgard</span><span><i class="l-warn"></i>needs attention</span>' +
          '<span><i class="l-tun"></i>the encrypted tunnel</span></div>' +
      '</div>';
    paint();
  }

  // Light what's picked (and its neighbours), or the story so far: this
  // step's boxes lit, earlier steps' boxes softer, each with its number.
  function paint() {
    var lit = {}, near = {}, num = {}, focus = !!(sel || story);
    if (story) {
      story.st.steps.forEach(function (step, i) {
        if (i > story.i) return;
        step[0].forEach(function (id) {
          if (num[id] == null) num[id] = i + 1;
          if (i === story.i) lit[id] = true; else near[id] = true;
        });
      });
    } else if (sel) {
      lit[sel] = true;
      EDGES.forEach(function (e) {
        if (e[0] === sel) near[e[1]] = true;
        if (e[1] === sel) near[e[0]] = true;
      });
    }
    el.querySelector(".ov-tree").classList.toggle("focus", focus);
    el.querySelectorAll(".ov-box").forEach(function (b) {
      var id = b.getAttribute("data-id");
      b.classList.toggle("on", !!lit[id]);
      b.classList.toggle("near", !lit[id] && !!near[id]);
      if (num[id] != null) b.setAttribute("data-n", num[id]); else b.removeAttribute("data-n");
      b.setAttribute("aria-pressed", lit[id] ? "true" : "false");
    });
    detail();
    caption();
    follow();
  }

  // A story's lit box off screen (a phone, mostly): bring it into view,
  // clear of the pinned caption.
  function follow() {
    if (!story) return;
    var first = el.querySelector('.ov-box[data-id="' + story.st.steps[story.i][0][0] + '"]');
    var cap = el.querySelector(".ov-cap");
    if (!first || cap.hidden) return;
    var r = first.getBoundingClientRect(), c = cap.getBoundingClientRect();
    if (r.top < c.bottom + 8 || r.bottom > window.innerHeight - 90) {
      window.scrollBy({ top: r.top - (c.bottom + 24), behavior: still.matches ? "auto" : "smooth" });
    }
  }

  function detail() {
    var out = el.querySelector(".ov-detail");
    var id = sel || (story ? story.st.steps[story.i][0][story.st.steps[story.i][0].length - 1] : null);
    if (!id) {
      out.innerHTML = '<div class="ov-d-empty">Tap any box to see what it is, where it listens and what it talks to — or pick a story above.</div>';
      return;
    }
    var n = BY[id], links = [];
    EDGES.forEach(function (e) {
      if (e[0] === id) links.push([e[1], e[2], "→"]);
      else if (e[1] === id) links.push([e[0], e[2], "←"]);
    });
    out.innerHTML =
      '<div class="ov-d-h"><b>' + esc(n.t) + '</b><span>' + esc(n.s) + '</span>' +
        (n.p ? '<code>:' + esc(n.p) + '</code>' : "") + '</div>' +
      '<p>' + esc(n.d) + '</p>' +
      (n.w ? '<p class="ov-d-warn">' + esc(n.w) + '</p>' : "") +
      (links.length ? '<div class="ov-d-links">' + links.map(function (l) {
        return '<button type="button" class="ov-link" data-go="' + l[0] + '">' + l[2] + " " + esc(BY[l[0]].t) + '<small>' + esc(l[1]) + '</small></button>';
      }).join("") + '</div>' : "");
  }

  function caption() {
    var cap = el.querySelector(".ov-cap");
    el.querySelectorAll(".ov-chip").forEach(function (c) {
      c.setAttribute("aria-pressed", story && story.st.id === c.getAttribute("data-story") ? "true" : "false");
    });
    if (!story) { cap.hidden = true; return; }
    var st = story.st, n = st.steps.length;
    cap.hidden = false;
    cap.innerHTML =
      '<div class="ov-cap-t"><b>' + (story.i + 1) + ' / ' + n + '</b> ' + esc(st.steps[story.i][1]) +
        '<span class="ov-pips">' + st.steps.map(function (_, i) { return '<i' + (i === story.i ? ' class="on"' : i < story.i ? ' class="done"' : "") + '></i>'; }).join("") + '</span></div>' +
      '<button type="button" class="ov-step" data-step="-1" aria-label="Previous step"' + (story.i ? "" : " disabled") + '>‹</button>' +
      '<button type="button" class="ov-step" data-step="1" aria-label="Next step"' + (story.i < n - 1 ? "" : " disabled") + '>›</button>' +
      (still.matches ? "" : '<button type="button" class="ov-play" aria-label="' + (playing ? "Pause" : "Play") + '">' + (playing ? "❚❚" : "▶") + '</button>') +
      '<button type="button" class="ov-close" aria-label="End the story">✕</button>';
  }

  function schedule() {
    clearTimeout(timer);
    if (!story || !playing || still.matches) return;
    timer = setTimeout(function () {
      if (!story) return;
      if (story.i < story.st.steps.length - 1) { story.i++; paint(); schedule(); }
      else { playing = false; caption(); }
    }, 5200);
  }
  function startStory(id) {
    var st = STORIES.filter(function (s) { return s.id === id; })[0];
    if (!st) return;
    if (story && story.st.id === id) { story = null; clearTimeout(timer); paint(); return; }
    sel = null;
    story = { st: st, i: 0 };
    playing = !still.matches;
    paint();
    schedule();
  }
  function pick(id) {
    story = null;
    clearTimeout(timer);
    sel = sel === id ? null : id;
    paint();
  }

  function onClick(e) {
    var t = e.target;
    var chip = t.closest(".ov-chip");
    if (chip) { startStory(chip.getAttribute("data-story")); return; }
    var stp = t.closest(".ov-step");
    if (stp && story) {
      story.i = D.clamp(story.i + parseInt(stp.getAttribute("data-step"), 10), 0, story.st.steps.length - 1);
      playing = false; clearTimeout(timer); paint(); return;
    }
    if (t.closest(".ov-play") && story) { playing = !playing; if (playing && story.i === story.st.steps.length - 1) story.i = 0; paint(); schedule(); return; }
    if (t.closest(".ov-close")) { story = null; clearTimeout(timer); paint(); return; }
    var go = t.closest(".ov-link");
    if (go) {
      sel = null; pick(go.getAttribute("data-go"));
      var b = el.querySelector('.ov-box[data-id="' + go.getAttribute("data-go") + '"]');
      if (b) b.scrollIntoView({ block: "center", behavior: still.matches ? "auto" : "smooth" });
      return;
    }
    var bx = t.closest(".ov-box");
    if (bx) { pick(bx.getAttribute("data-id")); return; }
    if (t.closest(".ov-tree") && (sel || story)) { sel = null; story = null; clearTimeout(timer); paint(); }
  }

  function init() {
    el = D.$("ov-map");
    if (!el || el.getAttribute("data-ov")) return;
    el.setAttribute("data-ov", "");
    render();
    el.addEventListener("click", onClick);
    // A hidden tab stops the story's clock.
    document.addEventListener("visibilitychange", function () { if (document.hidden) clearTimeout(timer); else schedule(); });
  }

  D.ready("#ov-map", init);
})();
