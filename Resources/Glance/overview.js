// ════════════════════════════════════════════════════════════════════════════
// overview.js — the Overview page (#ov-map): how Asgard works, top-down.
//
// One SVG, drawn here from the tables below: who uses it (top), how they get
// in, Asgard itself in four groups (ask for it · watch · find & fetch · keep
// an eye on it), where it all lives (the disks), and what's out on the
// internet. Lines are the real connections between them.
//
//   tap/click a box    it lights up with everything it talks to, and the panel
//                      under the map says what it is, its port and why
//   a story chip       walks one path step by step ("A film, start to
//                      finish", "Watching from anywhere", …): the boxes and
//                      lines of each step light up, with dots running along
//                      the lines in the direction things move. ‹ › step,
//                      ⏸ pauses; it plays itself otherwise
//
// Two layouts from the same tables: WIDE (a fixed 1600-unit drawing, scaled to
// the card) and TALL (two columns, for a phone) — picked by the card's width,
// redrawn only when that changes.
//
// It is a picture of the CONFIG, not a live view: nothing here polls. When a
// service moves or a new one arrives, change NODES / EDGES / STORIES — they
// are the whole truth this page tells (and Claude/server-info.md is where the
// facts come from).
//
// Colours are the HUD's — var(--hud…), --s1…--s6, --ag-* — never literals, so
// the viewer's picked colour (theme.js) recolours the map too.
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";
  if (!window.Dash) return;
  var D = window.Dash;
  var NS = "http://www.w3.org/2000/svg";
  var still = window.matchMedia ? matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };

  // ── what's on the map ──────────────────────────────────────────────────────
  // zone → its colour. z is a node's zone; p its port(s); w a warning.
  var ZONE = {
    people: { label: "People & screens", c: "var(--s5)" },
    in:     { label: "Ways in",          c: "var(--s3)" },
    ask:    { label: "Ask for it",       c: "var(--s2)" },
    watch:  { label: "Watch · read · listen", c: "var(--s1)" },
    fetch:  { label: "Find & fetch",     c: "var(--hud2)" },
    over:   { label: "Keep an eye on it", c: "var(--s5)" },
    disk:   { label: "Where it lives",   c: "var(--s4)" },
    out:    { label: "Out on the internet", c: "var(--s3)" },
    home:   { label: "Around the house", c: "var(--s2)" },
    box:    { label: "Asgard",           c: "var(--hud)" }
  };

  var NODES = [
    { id: "you", z: "people", t: "You", s: "phone · laptop · anywhere",
      d: "Your own devices. Every one is on the tailnet, so this page and every service answer wherever you are — home, work, 4G." },
    { id: "sisyphus", z: "people", t: "Sisyphus", s: "your desktop",
      d: "Where the repo lives — ~/Dots, the only copy. system-rebuild builds every machine here and pushes it over the tailnet, Asgard included. It also runs Wolf: game streams to the TV." },
    { id: "kitkat", z: "people", t: "Kit-Kat", s: "her desktop",
      d: "Her NVIDIA machine running Hyprland. Deployed from Sisyphus like everything else." },
    { id: "her", z: "people", t: "Her", s: "MarsBar dashboard",
      d: "Her own small dashboard — the lights, Jellyfin, the TV panel — at marsbar:1111. The tailnet's rules let her reach that, Jellyfin and Jellyseerr; nothing else on Asgard." },
    { id: "tv", z: "people", t: "Living-room TV", s: "Eclipse · Pi 5 · Kodi",
      d: "A Raspberry Pi 5 running LibreELEC and Kodi. Plays from Jellyfin over the home network, runs Moonlight for game streams from Sisyphus, and is driven from the dashboards over SSH. Not a Nix machine — its recipe is Claude/eclipse.md." },
    { id: "guests", z: "people", t: "Family & friends", s: "on the internet",
      d: "No app, no VPN: Jellyfin, Jellyseerr and Immich are published through a Cloudflare Tunnel at *.bifrost-vault.com. Nothing else is reachable from outside." },

    { id: "tailnet", z: "in", t: "Tailscale", s: "private mesh · WireGuard",
      d: "A private, encrypted network between your own devices (tailb54b82.ts.net). Almost everything on Asgard listens only here: the firewall trusts tailscale0 and nothing else." },
    { id: "mbnode", z: "in", t: "marsbar node", s: "her own tailnet name", p: "1111",
      d: "A second Tailscale node running on Asgard that serves only MarsBar. Tailnet rules work per machine and port, not per web address — so her own node is what keeps the admin pages out of her reach." },
    { id: "lan", z: "in", t: "Home network", s: "router · ethernet",
      d: "The house LAN. Eclipse is wired to it, Wi-Fi standing by. Asgard opens exactly one port on it on purpose: 9557, a speed-test sink with no controls." },
    { id: "cf", z: "in", t: "Cloudflare Tunnel", s: "public · no open ports",
      d: "cloudflared on Asgard dials OUT to Cloudflare, so no port is open on the router. Three names: jellyfin., requests. and photos.bifrost-vault.com. Uploads to the internet are capped at 30 Mbit so a remote stream never lags a game at home." },

    { id: "seerr", z: "ask", t: "Jellyseerr", s: "ask for a film or show", p: "5055",
      d: "The request page. Pick something and it goes to Radarr or Sonarr with the right quality profile — no logging into the arrs." },
    { id: "shelfarr", z: "ask", t: "Shelfarr", s: "ask for a book", p: "5056",
      d: "Book and audiobook requests. Searches through Prowlarr, downloads through SABnzbd, delivers into Audiobookshelf. Wired up by books-setup.service." },

    { id: "jellyfin", z: "watch", t: "Jellyfin", s: "films · TV · music", p: "8096",
      d: "The media server. Reads the pool and streams to the TV, phones and browsers — transcoding on the Intel GPU (QuickSync) when a device can't play the original." },
    { id: "abs", z: "watch", t: "Audiobookshelf", s: "audiobooks · ebooks", p: "13378",
      d: "Audiobooks and ebooks, with listening progress synced across devices. Shelfarr delivers into it." },
    { id: "suwayomi", z: "watch", t: "Suwayomi", s: "manga", p: "4567",
      d: "Manga reader and downloader. Some sources hide behind Cloudflare checks — FlareSolverr gets it past those." },
    { id: "immich", z: "watch", t: "Immich", s: "photos", p: "2283", w: "No backup yet — the one thing here that can't be downloaded again.",
      d: "The photo library, with its own database. It lives on real ext4 on the 8 TB drive, not in the pool." },

    { id: "arrs", z: "fetch", t: "Sonarr · Radarr · Lidarr", s: "TV · films · music", p: "8989 · 7878 · 8686",
      d: "They know what you want, watch for new releases, pick the best one their quality profile allows, send it to SABnzbd, then rename it into the library." },
    { id: "prowlarr", z: "fetch", t: "Prowlarr", s: "searches the indexers", p: "9696",
      d: "One place for the indexers. Every arr — and Shelfarr — searches through it." },
    { id: "sab", z: "fetch", t: "SABnzbd", s: "downloads", p: "8080",
      d: "Downloads from Usenet and unpacks onto the NVMe. It lives inside a Mullvad WireGuard namespace: if the VPN drops, it has no network at all — a kill switch by design." },
    { id: "house", z: "fetch", t: "Housekeeping", s: "Recyclarr · Decluttarr · arr-policy",
      d: "Recyclarr keeps the quality profiles in step with the TRaSH guides (daily). Decluttarr clears stuck or failed downloads. arr-policy applies the rules the other two can't." },
    { id: "flare", z: "fetch", t: "FlareSolverr", s: "gets past Cloudflare checks", p: "8191",
      d: "A headless browser that solves Cloudflare challenges for Suwayomi and Shelfarr." },

    { id: "glance", z: "over", t: "Glance", s: "this dashboard", p: "8888",
      d: "What you're looking at. Every card is pushed live by the feeds — nothing on these pages polls." },
    { id: "marsbar", z: "over", t: "MarsBar", s: "her dashboard", p: "8890",
      d: "A second Glance, in purple, listening only on Asgard itself — reachable solely through the marsbar node." },
    { id: "feeds", z: "over", t: "Live feeds", s: "stats · network · Eclipse · lights", p: "9552 · 9555 · 9554 · 9556",
      d: "Small services that push live data to both dashboards: asgard-stats (the machine), network-panel (throughput, speed tests), eclipse-control (drives the Pi over SSH) and ha-bridge (the only thing allowed to flip a plug)." },
    { id: "tools", z: "over", t: "Terminal & files", s: "ttyd · FileBrowser", p: "7681 · 8081",
      d: "A web terminal (the Terminal page) and a file manager for /data." },
    { id: "ha", z: "over", t: "Home Assistant", s: "lights · power", p: "8123",
      d: "Talks to the smart plugs. Its token never reaches a browser: ha-bridge holds it, and only lets the dashboards switch the plugs on its list." },

    { id: "nvme", z: "disk", t: "NVMe · 1 TB", s: "NixOS · /downloads",
      d: "The system, every service's settings, and the download scratch space — fast, so unpacking never fights playback." },
    { id: "pool", z: "disk", t: "Media pool · ~19 TB", s: "8 TB + 12 TB · mergerfs",
      d: "Two drives merged into one /data/media. Each file lives whole on one drive, so losing a drive loses only its own files — all of which can be downloaded again. No RAID, on purpose." },
    { id: "photos", z: "disk", t: "Photos & state", s: "8 TB drive · plain ext4", w: "The photos have no backup yet.",
      d: "Immich's photos and the arrs' databases, mounted straight from the 8 TB drive rather than through the pool (databases and FUSE don't mix)." },

    { id: "indexers", z: "out", t: "Indexers", s: "three Usenet indexers",
      d: "Search engines for Usenet — NZBgeek, Miatrix and NzbPlanet. They say which posts make up a release." },
    { id: "mullvad", z: "out", t: "Mullvad VPN", s: "Sydney exit",
      d: "SABnzbd's only way out — WireGuard, in its own network namespace. Nothing else on Asgard uses it." },
    { id: "usenet", z: "out", t: "Usenet", s: "FrugalUsenet + Newshosting",
      d: "Where the files actually come from: two providers on separate backbones, the second as a backup." },
    { id: "plugs", z: "home", t: "Smart plugs", s: "Athom · ESPHome",
      d: "The lights and the power figures on the Power page. Each plug reports its watts, volts and daily kWh to Home Assistant over Wi-Fi." }
  ];
  var ASGARD = { id: "asgard", z: "box", t: "Asgard", s: "i5-14400 · NixOS",
    d: "The server: an Intel i5-14400 with a 1 TB NVMe and 8 TB + 12 TB drives. Everything on it is declared in the repo (Modules/Server/) — a fresh install is a clone and one rebuild." };

  // from, to, what moves along it; ctl = control rather than data (dashed).
  var EDGES = [
    ["you", "tailnet", "connects"], ["sisyphus", "tailnet", "connects"], ["kitkat", "tailnet", "connects"],
    ["her", "mbnode", "opens marsbar:1111"], ["tv", "lan", "wired"], ["guests", "cf", "a web address"],
    ["tailnet", "glance", "this page"], ["tailnet", "seerr", "requests"], ["tailnet", "jellyfin", "streams"],
    ["mbnode", "marsbar", "her page"], ["lan", "jellyfin", "plays films"],
    ["cf", "jellyfin", "streams"], ["cf", "seerr", "requests"], ["cf", "immich", "photos"],
    ["sisyphus", "asgard", "deploys every config", 1], ["sisyphus", "tv", "Wolf game streams"],
    ["seerr", "arrs", "the request"], ["shelfarr", "prowlarr", "search"], ["shelfarr", "sab", "download"],
    ["shelfarr", "abs", "delivers"], ["shelfarr", "flare", "challenges", 1],
    ["arrs", "prowlarr", "search"], ["prowlarr", "indexers", "query"], ["arrs", "sab", "grab"],
    ["sab", "mullvad", "VPN only"], ["mullvad", "usenet", "download"], ["sab", "nvme", "unpack"],
    ["arrs", "pool", "rename & import"], ["jellyfin", "pool", "reads"], ["abs", "pool", "reads"],
    ["suwayomi", "pool", "saves"], ["suwayomi", "flare", "challenges", 1], ["immich", "photos", "stores"],
    ["house", "arrs", "profiles", 1], ["house", "sab", "clears stuck", 1],
    ["feeds", "glance", "live"], ["feeds", "marsbar", "live"], ["feeds", "tv", "controls over SSH", 1],
    ["ha", "feeds", "plug states"], ["plugs", "ha", "Wi-Fi"]
  ];

  // Each step: the boxes it lights, the lines (from>to) it runs dots along,
  // and what to say.
  var STORIES = [
    { id: "film", t: "A film, start to finish", steps: [
      [["you", "tailnet", "seerr"], ["you>tailnet", "tailnet>seerr"], "You ask for a film in Jellyseerr — from the sofa, or anywhere on the tailnet."],
      [["seerr", "arrs"], ["seerr>arrs"], "Jellyseerr hands the request to Radarr, with the “Asgard - Movies” quality profile."],
      [["arrs", "prowlarr", "indexers"], ["arrs>prowlarr", "prowlarr>indexers"], "Radarr asks Prowlarr, and Prowlarr searches the indexers for releases."],
      [["arrs", "sab"], ["arrs>sab"], "Radarr picks the best release its profile allows and sends it to SABnzbd."],
      [["sab", "mullvad", "usenet"], ["sab>mullvad", "mullvad>usenet"], "SABnzbd downloads it from Usenet — only ever through the Mullvad VPN."],
      [["sab", "nvme"], ["sab>nvme"], "It's unpacked on the fast NVMe…"],
      [["arrs", "pool"], ["arrs>pool"], "…then Radarr renames it and moves it into the 19 TB pool."],
      [["jellyfin", "pool"], ["jellyfin>pool"], "Jellyfin notices it and adds it to the library."],
      [["jellyfin", "lan", "tv"], ["lan>jellyfin", "tv>lan"], "Press play on the TV: Eclipse streams it from Jellyfin over the home network."]
    ] },
    { id: "away", t: "Watching from anywhere", steps: [
      [["guests", "cf"], ["guests>cf"], "A friend opens jellyfin.bifrost-vault.com — no app, no VPN."],
      [["cf", "jellyfin"], ["cf>jellyfin"], "The Cloudflare Tunnel carries it to Jellyfin. No port is open on the router: Asgard dialled out."],
      [["jellyfin", "pool"], ["jellyfin>pool"], "Jellyfin streams the file, transcoding on the Intel GPU if their device needs it."],
      [["cf"], [], "Uploads are capped at 30 Mbit, so a remote stream never makes a game at home lag."],
      [["you", "tailnet", "jellyfin"], ["you>tailnet", "tailnet>jellyfin"], "You don't need the tunnel: on the tailnet, asgard:8096 is direct."]
    ] },
    { id: "dash", t: "This dashboard", steps: [
      [["feeds"], [], "Small services on Asgard watch the machine, the network, Eclipse and the lights…"],
      [["feeds", "glance"], ["feeds>glance"], "…and push every change to Glance the moment it happens. Nothing polls."],
      [["you", "tailnet", "glance"], ["you>tailnet", "tailnet>glance"], "Your browser opens asgard:8888 over the tailnet and keeps a live stream per card."],
      [["plugs", "ha", "feeds"], ["plugs>ha", "ha>feeds"], "Lights: the plugs report to Home Assistant; ha-bridge holds its token and only flips the plugs on its list."],
      [["feeds", "tv"], ["feeds>tv"], "The Eclipse panel's buttons go to eclipse-control, which drives the Pi over SSH."],
      [["her", "mbnode", "marsbar", "feeds"], ["her>mbnode", "mbnode>marsbar", "feeds>marsbar"], "Her MarsBar gets the same live cards, through her own tailnet node."]
    ] },
    { id: "book", t: "A book", steps: [
      [["shelfarr"], [], "Ask for a book or an audiobook in Shelfarr."],
      [["shelfarr", "prowlarr", "indexers"], ["shelfarr>prowlarr", "prowlarr>indexers"], "It searches through Prowlarr, like the arrs do."],
      [["shelfarr", "sab", "mullvad", "usenet"], ["shelfarr>sab", "sab>mullvad", "mullvad>usenet"], "SABnzbd downloads it, through the VPN."],
      [["shelfarr", "abs", "pool"], ["shelfarr>abs", "abs>pool"], "Shelfarr delivers it to Audiobookshelf, which keeps it in the pool."]
    ] },
    { id: "game", t: "Game night", steps: [
      [["sisyphus", "tv"], ["sisyphus>tv"], "Wolf on Sisyphus streams a game, in true 4K, to Moonlight on Eclipse."],
      [["tv"], [], "The pads pair straight to Eclipse over Bluetooth — managed on the Eclipse page."],
      [["feeds", "glance", "marsbar"], ["feeds>glance", "feeds>marsbar"], "A stuck stream can be ended from either dashboard."]
    ] },
    { id: "change", t: "Changing anything", steps: [
      [["sisyphus"], [], "Every machine is described in one repo — ~/Dots on Sisyphus, the only copy."],
      [["sisyphus", "asgard"], ["sisyphus>asgard"], "system-rebuild builds Asgard's new system on Sisyphus and pushes it over the tailnet."],
      [["asgard"], [], "Asgard switches to it — and any earlier version is one pick away in its boot menu."],
      [["kitkat", "tailnet"], ["kitkat>tailnet"], "Kit-Kat is deployed the same way, from the same repo."]
    ] }
  ];

  var BY = {};
  NODES.concat([ASGARD]).forEach(function (n) { BY[n.id] = n; });

  // ── layouts ────────────────────────────────────────────────────────────────
  // WIDE: hand-placed on a 1600-unit-wide drawing. Each node: x, y, w (h is
  // the layout's). Bands get a label; the Asgard box and the VPN box are frames.
  var WIDE = (function () {
    var L = { W: 1600, H: 1000, h: 60, font: 1, nodes: {}, bands: [], frames: [] };
    function at(id, x, y, w) { L.nodes[id] = { x: x, y: y, w: w || 220 }; }
    ["you", "sisyphus", "kitkat", "her", "tv", "guests"].forEach(function (id, i) { at(id, 110 + i * 250, 58); });
    at("tailnet", 110, 196, 720); at("mbnode", 860, 196); at("lan", 1110, 196); at("cf", 1360, 196);
    var col = [135, 420, 705, 1030], cw = [260, 260, 300, 275], row = function (r) { return 368 + r * 88; };
    ["seerr", "shelfarr"].forEach(function (id, r) { at(id, col[0], row(r), cw[0]); });
    ["jellyfin", "abs", "suwayomi", "immich"].forEach(function (id, r) { at(id, col[1], row(r), cw[1]); });
    ["arrs", "prowlarr", "sab", "house", "flare"].forEach(function (id, r) { at(id, col[2], row(r), cw[2]); });
    ["glance", "marsbar", "feeds", "tools", "ha"].forEach(function (id, r) { at(id, col[3], row(r), cw[3]); });
    at("nvme", 135, 878, 320); at("pool", 480, 878, 500); at("photos", 1005, 878, 300);
    at("indexers", 1355, row(1), 232); at("mullvad", 1355, row(2), 232); at("usenet", 1355, row(3), 232); at("plugs", 1355, row(4) + 22, 232);
    L.bands = [
      { y: 42, label: ZONE.people.label }, { y: 180, label: ZONE.in.label },
      { y: 862, label: ZONE.disk.label }, { y: row(1) - 16, x: 1355, label: ZONE.out.label, short: true },
      { y: row(4) + 6, x: 1355, label: ZONE.home.label, short: true }
    ];
    L.zones = [
      { x: col[0], y: 348, label: ZONE.ask.label, c: ZONE.ask.c }, { x: col[1], y: 348, label: ZONE.watch.label, c: ZONE.watch.c },
      { x: col[2], y: 348, label: ZONE.fetch.label, c: ZONE.fetch.c }, { x: col[3], y: 348, label: ZONE.over.label, c: ZONE.over.c }
    ];
    L.frames = [
      { id: "asgard", x: 110, y: 290, w: 1220, h: 538, label: "ASGARD", sub: ASGARD.s, main: true },
      { id: "vpn", x: col[2] - 12, y: row(2) - 26, w: cw[2] + 24, h: 60 + 38, label: "inside the Mullvad VPN namespace", dashed: true }
    ];
    return L;
  })();

  // TALL: for a phone. Two columns, every group a band of its own, in the
  // same top-down order; Asgard's four groups inside its frame.
  function tall() {
    var W = 420, cw = 194, gap = 12, h = 56, L = { W: W, h: h, font: 0.82, nodes: {}, bands: [], frames: [], zones: [] };
    var y = 26;
    function band(label, ids, inBox) {
      if (inBox) L.zones.push({ x: 24, y: y + 4, label: label.label, c: label.c });
      else L.bands.push({ y: y + 4, label: label });
      y += 18;
      ids.forEach(function (id, i) {
        L.nodes[id] = { x: (inBox ? 24 : 12) + (i % 2) * (cw + gap - (inBox ? 12 : 0)), y: y + Math.floor(i / 2) * (h + 12), w: cw - (inBox ? 12 : 0) };
      });
      y += Math.ceil(ids.length / 2) * (h + 12) + 18;
    }
    band(ZONE.people.label, ["you", "sisyphus", "kitkat", "her", "tv", "guests"]);
    band(ZONE.in.label, ["tailnet", "mbnode", "lan", "cf"]);
    var top = y;
    y += 42;
    band(ZONE.ask, ["seerr", "shelfarr"], true);
    band(ZONE.watch, ["jellyfin", "abs", "suwayomi", "immich"], true);
    band(ZONE.fetch, ["arrs", "prowlarr", "sab", "house", "flare"], true);
    band(ZONE.over, ["glance", "marsbar", "feeds", "tools", "ha"], true);
    L.frames.push({ id: "asgard", x: 6, y: top, w: W - 12, h: y - top - 6, label: "ASGARD", sub: ASGARD.s, main: true });
    y += 8;
    band(ZONE.disk.label, ["nvme", "pool", "photos"]);
    band(ZONE.out.label, ["indexers", "mullvad", "usenet"]);
    band(ZONE.home.label, ["plugs"]);
    L.H = y;
    return L;
  }

  // ── drawing ────────────────────────────────────────────────────────────────
  function esc(s) { return D.esc(String(s)); }
  function chamfer(x, y, w, h, k) {
    return "M" + (x + k) + " " + y + "H" + (x + w) + "V" + (y + h - k) + "L" + (x + w - k) + " " + (y + h) + "H" + x + "V" + (y + k) + "Z";
  }
  function box(L, id) {
    var n = L.nodes[id];
    if (n) return { x: n.x, y: n.y, w: n.w, h: L.h };
    var f = L.frames.filter(function (f) { return f.id === id; })[0];
    return f ? { x: f.x, y: f.y, w: f.w, h: f.h, frame: true } : null;
  }
  // A line from A to B: out of A's side that faces B, into B's facing side,
  // as one smooth curve. Mostly-vertical pairs use top/bottom edges; level
  // pairs use the sides; a pair on the same row of boxes arcs over the top.
  function route(L, a, b) {
    var A = box(L, a), B = box(L, b);
    if (!A || !B) return "";
    var ax = A.x + A.w / 2, ay = A.y + A.h / 2, bx = B.x + B.w / 2, by = B.y + B.h / 2;
    if (B.frame) { bx = Math.min(Math.max(ax, B.x + 60), B.x + B.w - 60); by = B.y; return curveV(ax, A.y + A.h, bx, by); }
    var dx = bx - ax, dy = by - ay;
    if (Math.abs(dy) < L.h * 0.6 && Math.abs(dx) > (A.w + B.w) / 2 + 40 && L.W > 1000) {   // same row, far apart: arc over
      var lift = Math.min(60, 20 + Math.abs(dx) * 0.05);
      return "M" + ax + " " + A.y + "C" + ax + " " + (A.y - lift) + " " + bx + " " + (B.y - lift) + " " + bx + " " + B.y;
    }
    if (Math.abs(dy) >= L.h * 0.9) {
      return dy > 0 ? curveV(ax, A.y + A.h, bx, B.y) : curveV(ax, A.y, bx, B.y + B.h);
    }
    var sx = dx > 0 ? A.x + A.w : A.x, ex = dx > 0 ? B.x : B.x + B.w;
    var mx = (sx + ex) / 2;
    return "M" + sx + " " + ay + "C" + mx + " " + ay + " " + mx + " " + by + " " + ex + " " + by;
  }
  function curveV(x1, y1, x2, y2) {
    var my = (y1 + y2) / 2;
    return "M" + x1 + " " + y1 + "C" + x1 + " " + my + " " + x2 + " " + my + " " + x2 + " " + y2;
  }
  function eid(a, b) { return "ov-e-" + a + "-" + b; }

  function svg(L) {
    var s = '<svg class="ov-svg" viewBox="0 0 ' + L.W + " " + L.H + '" role="img" aria-label="How Asgard works: a map of every service and how they connect">';
    s += '<defs><marker id="ov-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">' +
      '<path d="M0 1 L9 5 L0 9z" class="ov-arrowhead"/></marker></defs>';
    // the frames, under everything
    L.frames.forEach(function (f) {
      s += '<g class="ov-frame' + (f.main ? " main" : " vpn") + '" data-id="' + f.id + '"' + (f.main ? ' tabindex="0" role="button" aria-label="Asgard: about the server"' : "") + '>' +
        '<path d="' + chamfer(f.x, f.y, f.w, f.h, f.main ? 22 : 10) + '"/>' +
        (f.main ? '<text class="ov-frame-t" x="' + (f.x + 26) + '" y="' + (f.y + 30 * L.font) + '">' + esc(f.label) + '</text>' +
                  '<text class="ov-frame-s" x="' + (f.x + 26 + 160 * L.font) + '" y="' + (f.y + 30 * L.font) + '">' + esc(f.sub) + '</text>'
                : '<text class="ov-frame-s" x="' + (f.x + 12) + '" y="' + (f.y + 16) + '">' + esc(f.label) + '</text>') +
        '</g>';
    });
    L.bands.forEach(function (b) {
      s += '<text class="ov-band" x="' + (b.x != null ? b.x : (L.W > 1000 ? 110 : 12)) + '" y="' + b.y + '">' + esc(b.label.toUpperCase()) + '</text>';
    });
    (L.zones || []).forEach(function (z) {
      s += '<text class="ov-zone" style="--c:' + z.c + '" x="' + z.x + '" y="' + z.y + '">' + esc(z.label.toUpperCase()) + '</text>';
    });
    // the lines
    s += '<g class="ov-edges">';
    EDGES.forEach(function (e) {
      var d = route(L, e[0], e[1]);
      if (!d) return;
      var from = BY[e[0]];
      s += '<g class="ov-e' + (e[3] ? " ctl" : "") + '" data-a="' + e[0] + '" data-b="' + e[1] + '" style="--c:' + ZONE[from.z].c + '">' +
        '<path id="' + eid(e[0], e[1]) + '" d="' + d + '" marker-end="url(#ov-arrow)"/></g>';
    });
    s += '</g>';
    // the boxes
    // Text is in the page's monospace face, so its width is chars × a
    // constant: cut anything that would spill out of its box, and show a
    // port only where it fits beside the title (the panel always has it).
    function fit(t, px, room) {
      var n = Math.floor(room / px);
      return t.length <= n ? t : t.slice(0, Math.max(1, n - 1)) + "…";
    }
    NODES.forEach(function (n) {
      var b = L.nodes[n.id];
      if (!b) return;
      var x = b.x, y = b.y, w = b.w, h = L.h, f = L.font;
      var tw = 10.4 * f, sw = 7.7 * f, pw = 7.1 * f;
      var port = n.p && n.p.indexOf("·") < 0 && L.W > 1000 && 14 + n.t.length * tw + 16 + (n.p.length + 1) * pw <= w - 10 ? n.p : "";
      s += '<g class="ov-n" data-id="' + n.id + '" style="--c:' + ZONE[n.z].c + '" tabindex="0" role="button" aria-label="' + esc(n.t + ": " + n.s) + '">' +
        '<path class="ov-box" d="' + chamfer(x, y, w, h, 10) + '"/>' +
        '<path class="ov-tick" d="M' + x + " " + (y + 10) + "V" + (y + h) + '"/>' +
        '<text class="ov-t" x="' + (x + 14) + '" y="' + (y + 25 * f) + '" style="font-size:' + (17 * f) + 'px">' + esc(fit(n.t, tw, w - 24)) + '</text>' +
        '<text class="ov-s" x="' + (x + 14) + '" y="' + (y + 46 * f) + '" style="font-size:' + (12.5 * f) + 'px">' + esc(fit(n.s, sw, w - 24 - (n.w ? 14 : 0))) + '</text>' +
        (port ? '<text class="ov-p" x="' + (x + w - 10) + '" y="' + (y + 25 * f) + '" text-anchor="end" style="font-size:' + (11.5 * f) + 'px">:' + esc(port) + '</text>' : "") +
        (n.w ? '<circle class="ov-warn" cx="' + (x + w - 12) + '" cy="' + (y + h - 12) + '" r="4.5"/>' : "") +
        '</g>';
    });
    s += '<g class="ov-dots"></g></svg>';
    return s;
  }

  // ── the card ───────────────────────────────────────────────────────────────
  var el = null, layout = null, sel = null, story = null, timer = null, playing = true;

  function render() {
    var wide = el.clientWidth >= 760;
    var L = wide ? WIDE : tall();
    layout = L;
    el.innerHTML =
      '<div class="ov">' +
        '<div class="ov-stories" role="toolbar" aria-label="Walk through how things work">' +
          '<span class="ov-lead">Show me</span>' +
          STORIES.map(function (st) { return '<button type="button" class="ov-chip" data-story="' + st.id + '">' + esc(st.t) + '</button>'; }).join("") +
        '</div>' +
        '<div class="ov-cap" hidden></div>' +
        '<div class="ov-map ' + (wide ? "wide" : "tall") + '">' + svg(L) + '</div>' +
        '<div class="ov-detail" aria-live="polite"></div>' +
        '<div class="ov-legend"><span><i class="l-data"></i>data moves this way</span><span><i class="l-ctl"></i>control · config</span>' +
          '<span><i class="l-warn"></i>needs attention</span><span class="ov-tip">Tap any box — or pick a story above.</span></div>' +
      '</div>';
    paint();
  }

  // Light what's selected (and its neighbours), or the story's current step.
  function paint() {
    var svgEl = el.querySelector(".ov-svg");
    if (!svgEl) return;
    var nodes = {}, edges = {}, focus = false;
    if (story) {
      var step = story.st.steps[story.i];
      step[0].forEach(function (id) { nodes[id] = 2; });
      step[1].forEach(function (k) { edges[k] = 2; });
      focus = true;
    } else if (sel) {
      nodes[sel] = 2;
      EDGES.forEach(function (e) {
        if (e[0] === sel || e[1] === sel) { edges[e[0] + ">" + e[1]] = 1; nodes[e[0]] = nodes[e[0]] || 1; nodes[e[1]] = nodes[e[1]] || 1; }
      });
      focus = true;
    }
    svgEl.classList.toggle("focus", focus);
    svgEl.querySelectorAll(".ov-n, .ov-frame.main").forEach(function (g) {
      var k = nodes[g.getAttribute("data-id")];
      g.classList.toggle("on", k === 2);
      g.classList.toggle("near", k === 1);
    });
    var dots = svgEl.querySelector(".ov-dots"), html = "";
    svgEl.querySelectorAll(".ov-e").forEach(function (g) {
      var k = g.getAttribute("data-a") + ">" + g.getAttribute("data-b"), on = edges[k];
      g.classList.toggle("on", !!on);
      // Dots run along a lit line, source → target — a few, staggered.
      if (on && !still.matches) {
        var id = eid(g.getAttribute("data-a"), g.getAttribute("data-b")), dur = 2.2;
        for (var i = 0; i < 3; i++) {
          html += '<circle class="ov-dot" r="' + (layout.W > 1000 ? 4.5 : 3.5) + '" style="--c:' + g.style.getPropertyValue("--c") + '">' +
            '<animateMotion dur="' + dur + 's" begin="' + (-i * dur / 3).toFixed(2) + 's" repeatCount="indefinite"><mpath href="#' + id + '"/></animateMotion></circle>';
        }
      }
    });
    dots.innerHTML = html;
    detail();
    caption();
    // On a phone the map is taller than the screen: bring the step's first
    // box into view if it's off it (the caption stays pinned above).
    if (story && layout.W < 1000) {
      var first = svgEl.querySelector('.ov-n[data-id="' + story.st.steps[story.i][0][0] + '"], .ov-frame[data-id="' + story.st.steps[story.i][0][0] + '"]');
      if (first) {
        var r = first.getBoundingClientRect(), cap = el.querySelector(".ov-cap").getBoundingClientRect();
        if (r.top < cap.bottom + 8 || r.bottom > window.innerHeight - 90) {
          window.scrollBy({ top: r.top - (cap.bottom + 24), behavior: still.matches ? "auto" : "smooth" });
        }
      }
    }
  }

  function detail() {
    var box = el.querySelector(".ov-detail");
    var id = sel || (story ? story.st.steps[story.i][0][story.st.steps[story.i][0].length - 1] : null);
    if (!id) {
      box.innerHTML = '<div class="ov-d-empty">Tap any box on the map to see what it is, where it listens and what it talks to.</div>';
      return;
    }
    var n = BY[id], links = [];
    EDGES.forEach(function (e) {
      if (e[0] === id) links.push([e[1], e[2], "→"]);
      else if (e[1] === id) links.push([e[0], e[2], "←"]);
    });
    box.innerHTML =
      '<div class="ov-d-h" style="--c:' + ZONE[n.z].c + '"><b>' + esc(n.t) + '</b><span>' + esc(n.s) + '</span>' +
        (n.p ? '<code>:' + esc(n.p) + '</code>' : "") + '<em>' + esc(ZONE[n.z].label) + '</em></div>' +
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
      '<button type="button" class="ov-step" data-step="-1" aria-label="Previous step"' + (story.i ? "" : " disabled") + '>‹</button>' +
      '<div class="ov-cap-t"><b>' + (story.i + 1) + ' / ' + n + '</b> ' + esc(st.steps[story.i][2]) +
        '<span class="ov-pips">' + st.steps.map(function (_, i) { return '<i' + (i === story.i ? ' class="on"' : i < story.i ? ' class="done"' : "") + '></i>'; }).join("") + '</span></div>' +
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
    if (t.closest(".ov-play")) { playing = !playing; if (playing && story.i === story.st.steps.length - 1) story.i = 0; paint(); schedule(); return; }
    if (t.closest(".ov-close")) { story = null; clearTimeout(timer); paint(); return; }
    var go = t.closest(".ov-link");
    if (go) { sel = null; pick(go.getAttribute("data-go")); return; }
    var n = t.closest(".ov-n, .ov-frame.main");
    if (n) { pick(n.getAttribute("data-id")); return; }
    if (t.closest(".ov-svg") && (sel || story)) { sel = null; story = null; clearTimeout(timer); paint(); }
  }
  function onKey(e) {
    if (e.key !== "Enter" && e.key !== " ") return;
    var n = e.target.closest && e.target.closest(".ov-n, .ov-frame.main");
    if (n) { e.preventDefault(); pick(n.getAttribute("data-id")); }
  }

  function init() {
    el = D.$("ov-map");
    if (!el || el.getAttribute("data-ov")) return;
    el.setAttribute("data-ov", "");
    render();
    el.addEventListener("click", onClick);
    el.addEventListener("keydown", onKey);
    var wasWide = el.clientWidth >= 760;
    window.addEventListener("resize", function () {
      var wide = el.clientWidth >= 760;
      if (wide !== wasWide) { wasWide = wide; render(); }
    });
    // A hidden tab stops the story's clock (and the dots are SMIL: the
    // browser parks those itself).
    document.addEventListener("visibilitychange", function () { if (document.hidden) clearTimeout(timer); else schedule(); });
  }

  D.ready("#ov-map", init);
})();
