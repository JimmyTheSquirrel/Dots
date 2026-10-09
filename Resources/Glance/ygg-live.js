// ════════════════════════════════════════════════════════════════════════════
// ygg-live.js — the Overview's LIVING TREE: Yggdrasil, as Asgard is right now.
//
// The Overview card has two views (overview.js: Map | Living tree, a slider at
// the top). The map is the config, drawn flat; this is the same system grown
// as the world-ash, and alive:
//
//   the wells     the three roots drink from three wells — the NVMe, the media
//                 pool and the 8 TB drive (photos & state); a ring round each
//                 is how full it is, and a root glows while its disk is busy
//   the trunk     Asgard itself: its heartwood glows with the CPU and warms
//                 toward amber with its temperature
//   the branches  the Map's zones — open to the internet, tailnet (two limbs),
//                 the VPN tunnel, around the house — each in its zone colour,
//                 with its doors (Cloudflare, Tailscale, Mullvad, the LAN) as
//                 glowing knots
//   the leaves    a cluster per service. Up: in leaf, swaying; busier = brighter
//                 (its own CPU, from cgroupfs — asgard-stats `units`). Stopped:
//                 its leaves wither, droop and fall until it is back
//   sap           something streaming: light rises from the pool up the trunk
//                 to Jellyfin — and on to the TV when Eclipse is playing
//   seeds         downloads arriving: motes drift in from Usenet to SABnzbd;
//                 one that lands falls down the trunk into the pool, and takes
//                 root (a ripple in the well)
//   the sky       Sisyphus is the bright star over the crown (Elektra and
//                 Apollo beside it); a game stream is a beam from it to the TV
//   wind          the LAN's traffic: the more of it, the more the leaves sway
//
// Tap anything for what it is (overview.js's words) and how it is doing now.
// Under the tree, every service as a chip by branch — the same taps, and a
// list a phone can read.
//
// Streams (asgard-stats, eclipse-control, network-panel, ha-bridge) are open
// ONLY while this view is on screen: LivingTree.mount() opens them, unmount()
// closes them. overview.js loads this file the first time the tree is shown.
// Colours are HUD tokens (var(--hud…), --s*) — the picker recolours it.
// Reduced motion: nothing sways, flows or falls; the states still show.
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";
  if (!window.Dash || window.LivingTree) return;
  var D = window.Dash;
  var REDUCE = !!(window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches);
  var W = 1000, H = 720;

  // Seeded, so the tree grows the same shape on every visit.
  var seed = 7;
  function rnd() { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }
  function between(a, b) { return a + rnd() * (b - a); }
  function f(n) { return Math.round(n * 10) / 10; }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  // ── geometry ───────────────────────────────────────────────────────────────
  function quad(p, t) {
    var u = 1 - t;
    if (p.length === 3) return [u * u * p[0][0] + 2 * u * t * p[1][0] + t * t * p[2][0], u * u * p[0][1] + 2 * u * t * p[1][1] + t * t * p[2][1]];
    return [u * u * u * p[0][0] + 3 * u * u * t * p[1][0] + 3 * u * t * t * p[2][0] + t * t * t * p[3][0],
            u * u * u * p[0][1] + 3 * u * u * t * p[1][1] + 3 * u * t * t * p[2][1] + t * t * t * p[3][1]];
  }
  function normal(p, t) {
    var a = quad(p, Math.max(0, t - 0.01)), b = quad(p, Math.min(1, t + 0.01));
    var dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy) || 1;
    return [-dy / l, dx / l];
  }
  // A tapered limb along curve p: width w(t), as one filled outline.
  function limb(p, w, n) {
    n = n || 28;
    var L = [], R = [];
    for (var i = 0; i <= n; i++) {
      var t = i / n, c = quad(p, t), nn = normal(p, t), h = w(t) / 2;
      L.push(f(c[0] + nn[0] * h) + " " + f(c[1] + nn[1] * h));
      R.push(f(c[0] - nn[0] * h) + " " + f(c[1] - nn[1] * h));
    }
    return "M" + L.join("L") + "L" + R.reverse().join("L") + "Z";
  }
  function line(p, n, off) {
    n = n || 20;
    var out = [];
    for (var i = 0; i <= n; i++) {
      var t = i / n, c = quad(p, t), nn = normal(p, t), o = off ? off(t) : 0;
      out.push(f(c[0] + nn[0] * o) + " " + f(c[1] + nn[1] * o));
    }
    return "M" + out.join("L");
  }

  // The trunk, the roots and the limbs (hand-placed, so it reads as a tree;
  // the twigs and leaves on them are grown).
  var TRUNK = [[500, 582], [466, 486], [534, 404], [500, 318]];
  function trunkW(t) { return 58 + 52 * (1 - t) + (t < 0.16 ? 96 * Math.pow(1 - t / 0.16, 2) : 0); }
  var WELLS = [
    { id: "nvme", x: 232, y: 664, label: "NVMe" },
    { id: "pool", x: 500, y: 680, label: "Media pool" },
    { id: "photos", x: 768, y: 664, label: "Photos & state" }
  ];
  var ROOTS = WELLS.map(function (wl, i) {
    var sx = 500 + (i - 1) * 34;
    return [[sx, 572], [sx + (wl.x - sx) * 0.3, 628 - (i === 1 ? 8 : 0)], [wl.x + (i - 1) * -40, wl.y - 34], [wl.x, wl.y - 8]];
  });
  // Each limb: its zone (the Map's colour), its curve and base width, and its
  // doors (knots, at a point along it). The leaf clusters are placed by hand
  // in a canopy dome (LEAVES), so no name ever sits on another; each hangs
  // off the nearest point of its limb by a twig.
  var LIMBS = [
    { id: "public", t: "Open to the internet", c: "var(--s2)", p: [[486, 344], [430, 300], [330, 210], [176, 150]], w: 26, knots: [["cf", 0.22]] },
    { id: "house", t: "Around the house", c: "var(--s5)", p: [[480, 452], [400, 434], [300, 404], [150, 396]], w: 22, knots: [["lan", 0.28]] },
    { id: "watch", t: "Tailnet · watch, read & fetch", c: "var(--hud)", p: [[512, 330], [560, 250], [660, 160], [912, 112]], w: 26, knots: [] },
    { id: "control", t: "Tailnet · dashboards & control", c: "var(--hud)", p: [[518, 382], [600, 350], [720, 300], [918, 278]], w: 22, knots: [] },
    { id: "vpn", t: "Inside the VPN tunnel", c: "var(--hud2)", p: [[516, 470], [620, 482], [750, 466], [892, 446]], w: 20, knots: [["mullvad", 0.48]] },
    { id: "crown", t: "Tailnet · the way in", c: "var(--hud)", p: [[500, 326], [508, 284], [492, 240], [500, 198]], w: 22, knots: [["tailnet", 1]] }
  ];
  var LIMB = {};
  LIMBS.forEach(function (L) { LIMB[L.id] = L; L.leaves = []; });
  // [id, limb, x, y, radius, label above?]
  var LEAVES = [
    ["seerr", "public", 296, 126, 30, true], ["immich", "public", 166, 206, 30], ["jellyfin", "public", 352, 238, 32],
    ["tv", "house", 196, 330, 30], ["plugs", "house", 314, 344, 28],
    ["suwayomi", "watch", 640, 118, 26], ["shelfarr", "watch", 766, 108, 26], ["flare", "watch", 892, 148, 26],
    ["abs", "watch", 580, 198, 26], ["arrs", "watch", 706, 200, 28], ["prowlarr", "watch", 836, 222, 26],
    ["ha", "control", 628, 286, 26], ["glance", "control", 752, 288, 26], ["feeds", "control", 878, 312, 26],
    ["tools", "control", 690, 368, 24],
    ["sab", "vpn", 858, 404, 30]
  ];
  var STARS = [
    { id: "sisyphus", x: 500, y: 40, r: 5.5, label: "Sisyphus" },
    { id: "kitkat", x: 424, y: 60, r: 3, label: "Elektra" },
    { id: "apollo", x: 576, y: 60, r: 3, label: "Apollo" },
    { id: "usenet", x: 966, y: 420, r: 3.4, label: "Usenet" },
    { id: "guests", x: 56, y: 112, r: 3.4, label: "The internet" }
  ];

  // The point of a limb nearest (x, y): where a cluster's twig leaves it.
  function nearest(p, x, y) {
    var best = null, bd = 1e9;
    for (var i = 0; i <= 40; i++) {
      var q = quad(p, i / 40), d = (q[0] - x) * (q[0] - x) + (q[1] - y) * (q[1] - y);
      if (d < bd) { bd = d; best = q; }
    }
    return best;
  }
  var SPOT = {};
  function grow() {
    SPOT = {};
    LIMBS.forEach(function (L) { L.leaves = []; });
    LEAVES.forEach(function (v) {
      var L = LIMB[v[1]], b = nearest(L.p, v[2], v[3]);
      L.leaves.push(v[0]);
      SPOT[v[0]] = { b: b, c: [v[2], v[3]], limb: L, r: v[4], above: !!v[5] };
    });
    LIMBS.forEach(function (L) { L.knots.forEach(function (k) { SPOT[k[0]] = { b: quad(L.p, k[1]), knot: true, limb: L }; }); });
  }

  var LEAF = "M0 0C3.2-4.4 9.6-5.4 15 0C9.6 5.4 3.2 4.4 0 0Z";
  function cluster(id) {
    var s = SPOT[id], n = Math.round(s.r * 0.66), h = "";
    var ang0 = Math.atan2(s.c[1] - s.b[1], s.c[0] - s.b[0]);
    for (var i = 0; i < n; i++) {
      var a = ang0 + between(-2.3, 2.3), d = Math.sqrt(rnd()) * s.r;
      var x = s.c[0] + Math.cos(a) * d * 0.9, y = s.c[1] + Math.sin(a) * d * 0.75;
      var rot = (a * 180 / Math.PI) + between(-40, 40), sc = between(0.85, 1.45);
      h += '<path class="yg-leaf ' + (i % 3 ? "a" : "b") + '" d="' + LEAF + '" transform="translate(' + f(x) + " " + f(y) + ") rotate(" + f(rot) + ") scale(" + f(sc) + ')"/>';
    }
    // A few to fall when it withers.
    var fall = "";
    for (var k = 0; k < 3; k++) {
      fall += '<path class="yg-fall" style="--fx:' + f(between(-26, 26)) + "px;--fd:" + f(between(3.4, 5.6)) + "s;--fl:-" + f(between(0, 5)) + 's" d="' + LEAF +
        '" transform="translate(' + f(s.c[0] + between(-14, 14)) + " " + f(s.c[1] + between(-6, 8)) + ')"/>';
    }
    var tw = "M" + f(s.b[0]) + " " + f(s.b[1]) + "Q" + f((s.b[0] + s.c[0]) / 2 + between(-8, 8)) + " " + f((s.b[1] + s.c[1]) / 2 + between(-8, 8)) + " " + f(s.c[0]) + " " + f(s.c[1]);
    var below = !s.above;
    return '<g class="yg-c" data-id="' + id + '" style="--zc:' + s.limb.c + '">' +
      '<g class="yg-sway" style="transform-origin:' + f(s.b[0]) + "px " + f(s.b[1]) + "px;--sd:" + f(between(5.5, 8.5)) + "s;--sl:-" + f(between(0, 6)) + 's">' +
        '<path class="yg-twig" d="' + tw + '"/>' + h + '</g>' + fall +
      '<circle class="yg-hit" cx="' + f(s.c[0]) + '" cy="' + f(s.c[1]) + '" r="' + (s.r + 8) + '"/>' +
      '<text class="yg-l" x="' + f(s.c[0]) + '" y="' + f(below ? s.c[1] + s.r + 15 : s.c[1] - s.r - 7) + '">' + D.esc(short(id)) + '</text>' +
    '</g>';
  }
  function knot(id) {
    var s = SPOT[id];
    return '<g class="yg-k" data-id="' + id + '" style="--zc:' + s.limb.c + '">' +
      '<circle class="yg-ring" cx="' + f(s.b[0]) + '" cy="' + f(s.b[1]) + '" r="11"/>' +
      '<circle class="yg-knot" cx="' + f(s.b[0]) + '" cy="' + f(s.b[1]) + '" r="6"/>' +
      '<circle class="yg-hit" cx="' + f(s.b[0]) + '" cy="' + f(s.b[1]) + '" r="20"/>' +
      '<text class="yg-l k" x="' + f(s.b[0]) + '" y="' + f(id === "tailnet" ? s.b[1] - 18 : s.b[1] + 26) + '">' + D.esc(short(id)) + '</text></g>';
  }

  var api = null;
  function name(id) { var n = api && api.nodes[id]; return n ? n.t : id; }
  // Short names on the tree itself (the chips and the detail use the full ones).
  var SHORT = { arrs: "The arrs", abs: "Audiobooks", tv: "Eclipse", feeds: "Live feeds", tools: "Terminal & files", cf: "Cloudflare", lan: "Home LAN", ha: "Home Assistant", mullvad: "Mullvad" };
  function short(id) { return SHORT[id] || name(id); }

  function draw() {
    seed = 7;
    grow();
    var h = '<svg class="yg" viewBox="0 0 ' + W + " " + H + '" role="img" aria-label="Asgard as a living tree">' +
      '<defs>' +
        '<radialGradient id="yg-sky" cx="50%" cy="8%" r="90%"><stop offset="0" stop-color="rgb(var(--hud-rgb) / .16)"/><stop offset=".55" stop-color="rgb(var(--hud2-rgb) / .05)"/><stop offset="1" stop-color="transparent"/></radialGradient>' +
        '<linearGradient id="yg-bark" x1="0" x2="1"><stop offset="0" stop-color="#2c241e"/><stop offset=".45" stop-color="#4a3b30"/><stop offset=".7" stop-color="#3a2f27"/><stop offset="1" stop-color="#1c1713"/></linearGradient>' +
        '<linearGradient id="yg-heart" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="var(--yg-heat, var(--hud))" stop-opacity=".0"/><stop offset=".35" stop-color="var(--yg-heat, var(--hud))" stop-opacity=".85"/><stop offset="1" stop-color="var(--yg-heat, var(--hud))" stop-opacity=".25"/></linearGradient>' +
        '<filter id="yg-glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>' +
        '<radialGradient id="yg-aura"><stop offset="0" stop-color="rgb(var(--hud-rgb) / .10)"/><stop offset=".6" stop-color="rgb(var(--hud2-rgb) / .05)"/><stop offset="1" stop-color="transparent"/></radialGradient>' +
      '</defs>' +
      '<rect class="yg-bg" width="' + W + '" height="' + H + '" fill="url(#yg-sky)"/>';
    // the sky: faint stars, then the named ones
    var sky = "";
    for (var i = 0; i < 70; i++) sky += '<circle cx="' + f(between(10, W - 10)) + '" cy="' + f(between(6, 300)) + '" r="' + f(between(0.5, 1.4)) + '" style="--tw:' + f(between(2.5, 6)) + 's;--tl:-' + f(between(0, 6)) + 's"/>';
    h += '<g class="yg-sky">' + sky + '</g>';
    // the ground, a faint mist
    h += '<ellipse class="yg-ground" cx="500" cy="590" rx="470" ry="34"/>';
    // roots and wells
    h += '<g class="yg-roots">' + ROOTS.map(function (p, i) {
      return '<path class="yg-root" data-well="' + WELLS[i].id + '" d="' + limb(p, function (t) { return 30 * (1 - t) + 5; }, 24) + '"/>' +
        '<path class="yg-rootglow" data-well="' + WELLS[i].id + '" d="' + line(p, 24) + '"/>';
    }).join("") + '</g>';
    h += WELLS.map(function (wl) {
      var C = 2 * Math.PI * 30;
      return '<g class="yg-w" data-id="' + wl.id + '">' +
        '<ellipse class="yg-rim" cx="' + wl.x + '" cy="' + wl.y + '" rx="66" ry="17"/>' +
        '<ellipse class="yg-water" cx="' + wl.x + '" cy="' + (wl.y + 2) + '" rx="56" ry="11"/>' +
        '<circle class="yg-fill" cx="' + wl.x + '" cy="' + (wl.y + 2) + '" r="30" transform="translate(' + wl.x + " " + (wl.y + 2) + ") scale(1.9 .42) translate(" + -wl.x + " " + -(wl.y + 2) + ')" style="stroke-dasharray:0 ' + f(C) + '"/>' +
        '<ellipse class="yg-ripple" cx="' + wl.x + '" cy="' + (wl.y + 2) + '" rx="10" ry="3"/>' +
        '<ellipse class="yg-hit" cx="' + wl.x + '" cy="' + wl.y + '" rx="76" ry="30"/>' +
        '<text class="yg-l w" x="' + wl.x + '" y="' + (wl.y + 36) + '">' + D.esc(wl.label) + '</text></g>';
    }).join("");
    // the trunk: bark, its grain, and the heartwood that glows with the CPU
    h += '<g class="yg-trunk" data-id="asgard">' +
      '<path class="yg-bark" d="' + limb(TRUNK, trunkW, 36) + '"/>' +
      [-0.32, -0.16, 0.02, 0.18, 0.33].map(function (k, i) {
        return '<path class="yg-grain" d="' + line(TRUNK, 30, function (t) { return k * trunkW(t) + Math.sin(t * 9 + i) * 3; }) + '"/>';
      }).join("") +
      '<path class="yg-heart" d="' + limb(TRUNK, function (t) { return trunkW(t) * 0.22; }, 36) + '"/>' +
      '<path class="yg-hit" d="' + limb(TRUNK, trunkW, 18) + '"/>' +
      '<text class="yg-l trunk" x="500" y="530">Asgard</text></g>';
    // limbs, under their leaves
    h += '<ellipse class="yg-aura" cx="540" cy="250" rx="440" ry="215"/>';
    h += '<g class="yg-limbs">' + LIMBS.map(function (L) {
      // a few twiglets off each limb, so it reads as wood, not a plank
      var tw = "";
      for (var k = 0; k < 3; k++) {
        var t0 = between(0.25, 0.8), b0 = quad(L.p, t0), nn = normal(L.p, t0), sgn = rnd() < 0.5 ? 1 : -1;
        if (nn[1] * sgn > 0) sgn = -sgn;                                  // twiglets reach upward
        var len = between(26, 46), tip = [b0[0] + nn[0] * sgn * len + between(-14, 14), b0[1] + nn[1] * sgn * len];
        tw += '<path class="yg-limb tw" d="' + limb([b0, [(b0[0] + tip[0]) / 2 + between(-8, 8), (b0[1] + tip[1]) / 2], tip], function (t) { return 5 * (1 - t) + 1; }, 10) + '"/>';
      }
      return tw + '<path class="yg-limb" style="--zc:' + L.c + '" d="' + limb(L.p, function (t) { return L.w * Math.pow(1 - t, 1.3) + 2.5; }) + '"/>' +
        '<path class="yg-vein" style="--zc:' + L.c + '" d="' + line(L.p, 24, function (t) { return -(L.w * Math.pow(1 - t, 1.3) + 2.5) * 0.28; }) + '"/>';
    }).join("") + '</g>';
    // effects: sap, the play beam, the game beam, the seeds' road
    var j = SPOT.jellyfin, tv = SPOT.tv, sab = SPOT.sab, sis = STARS[0], us = STARS[3];
    var sap = "M500 676L500 566" + line(TRUNK, 20).replace("M", "L").split("L").filter(function (pt, i, a) {
      if (!pt) return false;
      var y = +pt.split(" ")[1];
      return y >= 344;
    }).map(function (pt) { return "L" + pt; }).join("") + line(LIMBS[0].p, 16).replace("M", "L") + "L" + f(j.c[0]) + " " + f(j.c[1]);
    h += '<g class="yg-fx">' +
      '<path class="yg-sap" d="' + sap + '"/>' +
      '<path class="yg-beam play" d="M' + f(j.c[0]) + " " + f(j.c[1]) + "Q" + f(Math.min(j.c[0], tv.c[0]) - 120) + " " + f((j.c[1] + tv.c[1]) / 2) + " " + f(tv.c[0]) + " " + f(tv.c[1]) + '"/>' +
      '<path class="yg-beam game" d="M' + sis.x + " " + sis.y + "Q" + 120 + " " + 140 + " " + f(tv.c[0]) + " " + f(tv.c[1]) + '"/>' +
      '<path id="yg-seedroad" class="yg-road" d="M' + us.x + " " + us.y + "Q" + 900 + " " + 470 + " " + f(sab.c[0]) + " " + f(sab.c[1]) + '"/>' +
      '<path id="yg-fallroad" class="yg-road" d="M' + f(sab.c[0]) + " " + f(sab.c[1]) + line(LIMBS[4].p.slice().reverse(), 12).replace("M", "L") + "L505 520L500 600L500 " + (WELLS[1].y + 2) + '"/>' +
      '<g class="yg-seeds"></g>' +
    '</g>';
    // leaves and knots
    h += '<g class="yg-leaves">' + Object.keys(SPOT).filter(function (id) { return !SPOT[id].knot; }).map(cluster).join("") + '</g>';
    h += '<g class="yg-knots">' + Object.keys(SPOT).filter(function (id) { return SPOT[id].knot; }).map(knot).join("") + '</g>';
    h += '<g class="yg-stars">' + STARS.map(function (s) {
      return '<g class="yg-s" data-id="' + s.id + '"><circle class="yg-halo" cx="' + s.x + '" cy="' + s.y + '" r="' + s.r * 3.2 + '"/>' +
        '<circle class="yg-star" cx="' + s.x + '" cy="' + s.y + '" r="' + s.r + '"/>' +
        '<circle class="yg-hit" cx="' + s.x + '" cy="' + s.y + '" r="18"/>' +
        '<text class="yg-l s" x="' + s.x + '" y="' + (s.y + s.r + 15) + '">' + D.esc(s.label) + '</text></g>';
    }).join("") + '</g>';
    return h + '</svg>';
  }

  // ── the card around it ─────────────────────────────────────────────────────
  var el = null, svg = null, streams = [], sel = null;
  var live = { units: null, cpu: null, temp: null, disks: {}, pool: null, streams: [], dl: null, landed: null,
               ecUp: null, tvPlaying: [], wolf: 0, mbps: 0, lamps: null };

  function chips() {
    return LIMBS.filter(function (L) { return L.leaves.length || L.knots.length; }).map(function (L) {
      var ids = L.knots.map(function (k) { return k[0]; }).concat(L.leaves);
      return '<div class="yg-row" style="--zc:' + L.c + '"><b>' + D.esc(L.t) + '</b>' + ids.map(function (id) {
        return '<button type="button" class="yg-chip" data-id="' + id + '"><i></i>' + D.esc(name(id)) + '</button>';
      }).join("") + '</div>';
    }).join("") + '<div class="yg-row" style="--zc:var(--s4)"><b>The wells</b>' + WELLS.map(function (w) {
      return '<button type="button" class="yg-chip" data-id="' + w.id + '"><i></i>' + D.esc(w.label) + '</button>';
    }).join("") + '</div>';
  }

  function mount(host, overview) {
    api = overview;
    el = host;
    el.innerHTML = '<div class="yg-wrap">' +
      '<div class="yg-status" aria-live="polite">Listening to the tree…</div>' +
      '<div class="yg-stage">' + draw() + '</div>' +
      '<div class="yg-detail" aria-live="polite"></div>' +
      '<div class="yg-chips">' + chips() + '</div>' +
      '<div class="yg-legend"><span><i class="l-leaf"></i>a service — brighter is busier</span><span><i class="l-dead"></i>withered: stopped</span>' +
        '<span><i class="l-sap"></i>sap: something streaming</span><span><i class="l-seed"></i>seeds: downloads arriving</span>' +
        '<span><i class="l-well"></i>wells: the disks, ringed by how full</span><span><i class="l-wind"></i>wind: network traffic</span></div>' +
      '</div>';
    svg = el.querySelector("svg.yg");
    el.addEventListener("click", onClick);
    detail();
    open();
  }
  function unmount() {
    streams.forEach(function (s) { s.close(); });
    streams = [];
    if (el) { el.removeEventListener("click", onClick); el.innerHTML = ""; }
    el = svg = null;
  }

  function open() {
    var p = api.ports || {};
    var host = function (port) { return D.api(port); };
    if (p.stats) streams.push(D.stream(host(p.stats) + "/stream", {
      snapshot: function (d) {
        live.units = d.units || null;
        live.cpu = d.cpu ? d.cpu.total : null;
        live.temp = d.temps ? d.temps.cpu : null;
        live.pool = d.pool || null;
        (d.disks || []).forEach(function (k) { live.disks[k.id] = k; });
        live.streams = d.streams || [];
        live.dl = d.downloads || null;
        var first = d.downloads && d.downloads.history && (d.downloads.history.items || [])[0];
        var landed = first && !/fail/i.test(first.status) ? first.name : null;
        if (landed && live.landed && landed !== live.landed) seedFall();
        if (landed) live.landed = landed;
        paint();
      }
    }));
    if (p.eclipse) streams.push(D.stream(host(p.eclipse) + "/events", {
      status: function (d) { live.ecUp = !!(d && d.reachable); paint(); },
      tv: function (d) { live.tvPlaying = (d && d.playing) || []; paint(); },
      wolf: function (d) { live.wolf = d && d.wolf === "up" ? (d.sessions || []).length : 0; paint(); }
    }));
    if (p.net) streams.push(D.stream(host(p.net) + "/events", {
      init: function (d) { live.mbps = (d && d.live && d.live.down) || 0; paint(); },
      tick: function (d) { live.mbps = (d && d.d) || 0; wind(); }
    }));
    if (p.bridge) streams.push(D.stream(host(p.bridge) + "/events", {
      snapshot: function (d) { lamps(d); paint(); },
      state: function (d) { if (d && d.entity) { lampState[d.entity] = d.state; countLamps(); paint(); } }
    }));
  }
  var lampState = {};
  function lamps(d) {
    lampState = {};
    var src = (d && (d.states || d)) || {};
    Object.keys(src).forEach(function (k) {
      if (/^(light|switch)\./.test(k)) lampState[k] = typeof src[k] === "object" ? src[k].state : src[k];
    });
    countLamps();
  }
  function countLamps() {
    var ks = Object.keys(lampState);
    live.lamps = ks.length ? ks.filter(function (k) { return lampState[k] === "on"; }).length : null;
  }

  // ── painting the live state onto the drawing ────────────────────────────────
  function state(id) {
    var u = live.units && live.units[id];
    if (u) return { up: u.up === u.of, part: u.up > 0 && u.up < u.of, cpu: u.cpu, down: u.down, known: true };
    if (id === "tv" || id === "lan") return { up: live.ecUp !== false, known: live.ecUp != null, cpu: live.tvPlaying.length ? 30 : 0 };
    if (id === "plugs") return { up: true, known: live.lamps != null, cpu: (live.lamps || 0) * 8 };
    if (id === "mullvad") {
      var dl = live.dl;
      return { up: true, known: !!dl, cpu: dl && !dl.paused && dl.mbps > 0 ? 40 : 0 };
    }
    return { up: true, known: false, cpu: 0 };
  }
  function wind() {
    if (!svg) return;
    svg.style.setProperty("--wind", clamp(Math.log10((live.mbps || 0) + 1) / 2.6, 0, 1).toFixed(2));
  }
  function paint() {
    if (!svg) return;
    var down = [], total = 0;
    svg.querySelectorAll(".yg-c, .yg-k").forEach(function (g) {
      var id = g.getAttribute("data-id"), s = state(id);
      if (s.known) total++;
      if (s.known && !s.up && !s.part) down.push(name(id));
      g.classList.toggle("down", s.known && !s.up && !s.part);
      g.classList.toggle("part", !!s.part);
      g.classList.toggle("unknown", !s.known);
      g.style.setProperty("--act", clamp((s.cpu || 0) / 35, 0, 1).toFixed(2));
    });
    var plugs = svg.querySelector('.yg-c[data-id="plugs"]');
    if (plugs) plugs.classList.toggle("lit", (live.lamps || 0) > 0);
    // the trunk: heartwood with the CPU, warmer with the heat
    var t = live.temp, heat = t == null ? 0 : clamp((t - 50) / 30, 0, 1);
    svg.style.setProperty("--cpu", clamp((live.cpu || 0) / 70, 0.08, 1).toFixed(2));
    svg.style.setProperty("--yg-heat", "color-mix(in oklch, var(--hud), #ffb347 " + Math.round(heat * 100) + "%)");
    // the wells and their roots
    WELLS.forEach(function (wl) {
      var g = svg.querySelector('.yg-w[data-id="' + wl.id + '"]'), k = wl.id === "pool" ? live.pool : live.disks[wl.id === "photos" ? "hdd" : wl.id];
      if (!g || !k || !k.size) return;
      var pct = clamp(k.used / k.size, 0, 1), C = 2 * Math.PI * 30;
      g.querySelector(".yg-fill").style.strokeDasharray = f(pct * C) + " " + f(C);
      g.classList.toggle("warn", pct >= 0.85);
      var io = k.io ? k.io.r + k.io.w : 0;
      if (wl.id === "pool") io = (live.disks.hdd && live.disks.hdd.io ? live.disks.hdd.io.r + live.disks.hdd.io.w : 0) + (live.disks.hdd2 && live.disks.hdd2.io ? live.disks.hdd2.io.r + live.disks.hdd2.io.w : 0);
      svg.querySelectorAll('[data-well="' + wl.id + '"]').forEach(function (r) { r.classList.toggle("busy", io > 5); });
    });
    // sap and beams
    svg.querySelector(".yg-sap").classList.toggle("on", live.streams.length > 0);
    svg.querySelector(".yg-beam.play").classList.toggle("on", live.tvPlaying.length > 0);
    svg.querySelector(".yg-beam.game").classList.toggle("on", live.wolf > 0);
    seeds(live.dl && !live.dl.paused && live.dl.mbps > 0 ? live.dl.mbps : 0);
    wind();
    // the chips mirror the leaves
    el.querySelectorAll(".yg-chip").forEach(function (c) {
      var g = svg.querySelector('[data-id="' + c.getAttribute("data-id") + '"]');
      c.className = "yg-chip" + (g && g.classList.contains("down") ? " down" : g && g.classList.contains("part") ? " part" : "") +
        (c.getAttribute("data-id") === sel ? " sel" : "");
    });
    status(down, total);
    if (sel) detail();
  }
  function status(down, total) {
    var s = el.querySelector(".yg-status"), bits = [];
    if (!total) { s.textContent = "Listening to the tree…"; return; }
    if (live.cpu != null) bits.push("CPU " + Math.round(live.cpu) + "%");
    if (live.streams.length) bits.push(live.streams.length + " streaming");
    if (live.dl && live.dl.count) bits.push(live.dl.count + " downloading");
    s.innerHTML = (down.length
      ? '<b class="bad">' + down.length + (down.length === 1 ? " branch has" : " branches have") + " withered</b> — " + D.esc(down.join(", "))
      : '<b>In full leaf</b> — every service is up') + (bits.length ? '<span>' + D.esc(bits.join(" · ")) + '</span>' : "");
  }

  // Seeds: motes along the road from Usenet to SABnzbd, quicker the faster it pulls.
  var seedRate = -1;
  function seeds(mbps) {
    var g = svg.querySelector(".yg-seeds"), rate = mbps > 0 ? clamp(4.2 - mbps / 120, 1.3, 4.2) : 0;
    if (REDUCE) rate = 0;
    if (Math.abs(rate - seedRate) < 0.3 && (rate > 0) === (seedRate > 0)) return;
    seedRate = rate;
    g.innerHTML = rate ? [0, 1, 2, 3, 4].map(function (i) {
      return '<circle class="yg-seed" r="3.2"><animateMotion dur="' + f(rate) + 's" begin="' + f(i * rate / 5) + 's" repeatCount="indefinite" rotate="auto">' +
        '<mpath href="#yg-seedroad"/></animateMotion></circle>';
    }).join("") : "";
  }
  // A download landed: one seed falls down the trunk into the pool.
  function seedFall() {
    if (!svg || REDUCE) return;
    var g = svg.querySelector(".yg-seeds");
    var c = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    c.setAttribute("class", "yg-seed big");
    c.setAttribute("r", "4.5");
    c.innerHTML = '<animateMotion dur="3.2s" begin="indefinite" fill="freeze" keyPoints="0;1" keyTimes="0;1" calcMode="spline" keySplines=".5 0 .7 1"><mpath href="#yg-fallroad"/></animateMotion>';
    g.appendChild(c);
    var a = c.querySelector("animateMotion");
    if (a.beginElement) a.beginElement();
    setTimeout(function () {
      c.remove();
      var w = svg && svg.querySelector('.yg-w[data-id="pool"]');
      if (w) { w.classList.remove("ripple"); void w.getBoundingClientRect(); w.classList.add("ripple"); }
    }, 3200);
  }

  // ── what you tapped ────────────────────────────────────────────────────────
  function liveLine(id) {
    var s = state(id);
    if (id === "asgard") return live.cpu == null ? "" : "CPU " + Math.round(live.cpu) + "%" + (live.temp != null ? " · " + Math.round(live.temp) + " °C" : "");
    if (id === "nvme" || id === "pool" || id === "photos") {
      var k = id === "pool" ? live.pool : live.disks[id === "photos" ? "hdd" : id];
      return k && k.size ? D.tb(k.used) + " of " + D.tb(k.size) + " used (" + Math.round(100 * k.used / k.size) + "%) · " + D.tb(k.free) + " free" : "";
    }
    if (id === "sisyphus") return live.wolf ? "Streaming a game to the TV right now" : "No game streaming right now";
    if (id === "jellyfin" && live.streams.length) return live.streams.length + " streaming: " + live.streams.map(function (x) { return x.title + " (" + x.user + ")"; }).join(", ");
    if (id === "sab" && live.dl) return live.dl.count ? live.dl.count + " in the queue · " + D.mbps(live.dl.mbps) + " Mb/s" : "Queue empty";
    if (id === "tv") return live.ecUp === false ? "Eclipse isn't answering" : live.tvPlaying.length ? "Playing: " + live.tvPlaying.map(function (p) { return p.title; }).join(", ") : "Online · nothing playing";
    if (id === "plugs") return live.lamps == null ? "" : live.lamps + " lamp" + (live.lamps === 1 ? "" : "s") + " on";
    if (!s.known) return "";
    if (!s.up && !s.part) return "Stopped — " + (s.down || []).join(", ") + (s.down && s.down.length === 1 ? " isn't" : " aren't") + " running";
    if (s.part) return "Partly up — " + s.down.join(", ") + " stopped";
    return "Up" + (s.cpu != null ? " · " + s.cpu.toFixed(1) + "% CPU" : "");
  }
  function detail() {
    var out = el && el.querySelector(".yg-detail");
    if (!out) return;
    svg.querySelectorAll(".sel").forEach(function (x) { x.classList.remove("sel"); });
    if (!sel) { out.innerHTML = '<div class="ov-d-empty">Tap a leaf, a knot, a well or a star — or a name below.</div>'; return; }
    var n = api.nodes[sel] || { t: sel, s: "", d: "" };
    var g = svg.querySelector('[data-id="' + sel + '"]');
    if (g) g.classList.add("sel");
    var ln = liveLine(sel);
    out.innerHTML = '<div class="ov-d-h"><b>' + D.esc(n.t) + '</b><span>' + D.esc(n.s || "") + '</span>' + (n.p ? '<code>:' + D.esc(n.p) + '</code>' : "") + '</div>' +
      (ln ? '<p class="yg-live-line">' + D.esc(ln) + '</p>' : "") + '<p>' + D.esc(n.d || "") + '</p>';
  }
  function onClick(e) {
    var t = e.target.closest("[data-id]");
    if (!t || !el.contains(t)) return;
    var id = t.getAttribute("data-id");
    sel = sel === id ? null : id;
    detail();
    el.querySelectorAll(".yg-chip").forEach(function (c) { c.classList.toggle("sel", c.getAttribute("data-id") === sel); });
  }

  window.LivingTree = { mount: mount, unmount: unmount };
})();
