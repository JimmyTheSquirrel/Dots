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
//   the trunk     Asgard itself: its heartwood glows through a crack (and its
//                 hollow, and the runes carved low on it) with the CPU, warming
//                 toward amber with its temperature
//   the branches  the Map's zones — open to the internet, tailnet (two limbs
//                 off the leader, where Tailscale is), the VPN tunnel, around
//                 the house — each lit along its edge in its zone colour, with
//                 its doors (Cloudflare, Tailscale, Mullvad, the LAN) as glowing
//                 burls. Each limb forks toward its services until every one
//                 has a branch of its own (grow(): the services ahead split at
//                 their widest gap; widths by the pipe rule)
//   the leaves    ash leaves (stalks of paired leaflets), a cluster per service
//                 at its branch's tip, in front of a mass of the canopy's own.
//                 Up: in leaf, swaying; busier = brighter (its own CPU, from
//                 cgroupfs — asgard-stats `units`). Stopped: its leaves wither,
//                 droop and fall until it is back
//   sap           something streaming: light rises from the pool up the trunk
//                 to Jellyfin — and on to the TV when Eclipse is playing
//   seeds         downloads arriving: motes drift in from Usenet to SABnzbd;
//                 one that lands falls down the trunk into the pool, and takes
//                 root (a ripple in the well)
//   the sky       Sisyphus is the bright star over the crown (Elektra and
//                 Apollo beside it); a game stream is a beam from it to the TV
//   wind          the LAN's traffic: the more of it, the more the leaves sway
//
// Two SVGs on one viewBox: the still picture (sky, hill, wood, canopy —
// thousands of leaflets, drawn once, on its own layer so it never repaints)
// and the live layer over it (whatever moves or answers a tap).
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
  var W = 1000, H = 800;

  // Seeded, so the tree grows the same shape on every visit.
  var seed = 7;
  function rnd() { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }
  function between(a, b) { return a + rnd() * (b - a); }
  function f(n) { return Math.round(n * 10) / 10; }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  // ── vectors and curves ─────────────────────────────────────────────────────
  function add(a, d, k) { return [a[0] + d[0] * k, a[1] + d[1] * k]; }
  function unit(v) { var l = Math.hypot(v[0], v[1]) || 1; return [v[0] / l, v[1] / l]; }
  function toward(a, b) { return unit([b[0] - a[0], b[1] - a[1]]); }
  function blend(a, b, k) { return unit([a[0] * (1 - k) + b[0] * k, a[1] * (1 - k) + b[1] * k]); }
  function dist(a, b) { return Math.hypot(a[0] - b[0], a[1] - b[1]); }
  function turn(v, deg) { var r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r); return [v[0] * c - v[1] * s, v[0] * s + v[1] * c]; }
  function pt(a) { return f(a[0]) + " " + f(a[1]); }
  var LIGHT = unit([-0.35, -1]);          // where the light falls from: the sky, a little to the left
  // A Bézier (3 or 4 points) at t; its heading; its side (the normal); its length.
  function at(p, t) {
    var u = 1 - t;
    if (p.length === 3) return [u * u * p[0][0] + 2 * u * t * p[1][0] + t * t * p[2][0], u * u * p[0][1] + 2 * u * t * p[1][1] + t * t * p[2][1]];
    return [u * u * u * p[0][0] + 3 * u * u * t * p[1][0] + 3 * u * t * t * p[2][0] + t * t * t * p[3][0],
            u * u * u * p[0][1] + 3 * u * u * t * p[1][1] + 3 * u * t * t * p[2][1] + t * t * t * p[3][1]];
  }
  function dir(p, t) { return toward(at(p, Math.max(0, t - 0.01)), at(p, Math.min(1, t + 0.01))); }
  function side(p, t) { var d = dir(p, t); return [-d[1], d[0]]; }
  function len(p) { var L = 0, a = at(p, 0); for (var i = 1; i <= 16; i++) { var b = at(p, i / 16); L += dist(a, b); a = b; } return L; }
  function rev(p) { return p.slice().reverse(); }
  // Points along p from t0 to t1 (either way), each pushed off(t) to its side.
  function trace(p, t0, t1, n, off) {
    var out = [];
    for (var i = 0; i <= n; i++) {
      var t = t0 + (t1 - t0) * i / n, c = at(p, t), s = side(p, t), o = off ? off(t) : 0;
      out.push([c[0] + s[0] * o, c[1] + s[1] * o]);
    }
    return out;
  }
  function poly(a, close) { return "M" + a.map(pt).join("L") + (close ? "Z" : ""); }
  function taper(w0, w1, k) { return function (t) { return w0 + (w1 - w0) * Math.pow(t, k || 1); }; }
  // A band of a piece of wood between two of its sides (a < b, as shares of
  // its half-width), from t0 on. Always wound the same way, so any number of
  // bands in one path fill as one shape: no doubled shading where they meet.
  function band(p, wf, n, a, b, t0) {
    t0 = t0 || 0;
    var A = trace(p, t0, 1, n, function (t) { return a * wf(t) / 2; });
    var B = trace(p, t0, 1, n, function (t) { return b * wf(t) / 2; });
    return poly(A.concat(B.reverse()), true);
  }

  // ── wood ───────────────────────────────────────────────────────────────────
  // Every bit of wood (roots, trunk, limbs, twigs) goes into a few shared
  // paths: the body, its sunlit side, its shadow side, the grain, and a rim of
  // light along the lit edge in its zone's colour. One body path means every
  // fork joins without a seam. `bury` is how far (px) its base is sunk in the
  // wood it grows from: no shading there, so a fork never shows a stripe.
  var WOOD;
  function wood(p, wf, o) {
    o = o || {};
    var L = len(p), n = o.n || clamp(Math.round(L / 7), 5, 60);
    WOOD.body += band(p, wf, n, -1, 1);
    if (wf(0.5) < 2.4) return;
    var t0 = clamp((o.bury || 0) / L, 0, 0.85);
    var s = side(p, 0.5), lit = s[0] * LIGHT[0] + s[1] * LIGHT[1] >= 0 ? 1 : -1;
    // two steps a side, so the light rolls round the wood rather than striping it
    WOOD.lit += lit > 0 ? band(p, wf, n, 0.05, 0.85, t0) : band(p, wf, n, -0.85, -0.05, t0);
    WOOD.lit2 += lit > 0 ? band(p, wf, n, 0.3, 0.68, t0) : band(p, wf, n, -0.68, -0.3, t0);
    WOOD.dark += lit > 0 ? band(p, wf, n, -1, -0.15, t0) : band(p, wf, n, 0.15, 1, t0);
    WOOD.dark2 += lit > 0 ? band(p, wf, n, -1, -0.6, t0) : band(p, wf, n, 0.6, 1, t0);
    if (o.rim) WOOD.rim[o.rim] = (WOOD.rim[o.rim] || "") + poly(trace(p, t0, 1, n, function (t) { return lit * 0.92 * wf(t) / 2; }));
    var g = o.grain != null ? o.grain : wf(0) > 11 ? Math.round(wf(0) / 8) : 0;
    for (var i = 0; i < g; i++) {
      var k = between(-0.8, 0.8), a = t0 + between(0, 0.35), b = Math.min(1, a + between(0.2, 0.65)), ph = between(0, 6);
      var line = poly(trace(p, a, b, Math.max(4, Math.round(n * (b - a))), function (t) { return k * wf(t) / 2 + Math.sin(t * 15 + ph) * 1.3; }));
      if (rnd() < 0.3) WOOD.shine += line; else WOOD.grain += line;
    }
  }

  // ── leaves ─────────────────────────────────────────────────────────────────
  // Yggdrasil is an ash, so every leaf is an ash leaf: a stalk with pairs of
  // leaflets and one at its tip, bending a little under its own weight.
  function rel(a, o) { return f(a[0] - o[0]) + " " + f(a[1] - o[1]); }
  function leaflet(q, d, l) {
    var s = [-d[1], d[0]], w = l * 0.21, tip = add(q, d, l);
    return "M" + pt(q) + "c" + rel(add(add(q, d, l * 0.3), s, w), q) + " " + rel(add(add(q, d, l * 0.72), s, w * 0.8), q) + " " + rel(tip, q) +
      "c" + rel(add(add(q, d, l * 0.72), s, -w * 0.8), tip) + " " + rel(add(add(q, d, l * 0.3), s, -w), tip) + " " + rel(q, tip) + "Z";
  }
  function ash(B, d, L, pairs, out, veins) {
    var tip = add(B, d, L);
    tip[1] += L * 0.16;
    var p = [B, add(B, d, L * 0.55), tip];
    out.rib += poly(trace(p, 0, 1, 4));
    for (var k = 0; k < pairs; k++) {
      var t = 0.3 + 0.62 * k / Math.max(1, pairs - 1), q = at(p, t), tg = dir(p, t), s = [-tg[1], tg[0]], l = L * (0.44 - 0.12 * t);
      for (var j = -1; j <= 1; j += 2) {
        var dd = unit(add(tg, s, j * 1.2));
        dd = unit([dd[0], dd[1] + 0.22]);
        out.leaf += leaflet(q, dd, l);
        if (veins) out.vein += "M" + pt(add(q, dd, l * 0.1)) + "L" + pt(add(q, dd, l * 0.8));
      }
    }
    var td = dir(p, 1);
    out.leaf += leaflet(add(tip, td, -L * 0.04), td, L * 0.42);
    if (veins) out.vein += "M" + pt(tip) + "L" + pt(add(tip, td, L * 0.34));
  }
  // The canopy round the services: twigs all along the wood, each ending in a
  // spray of leaves — some deep in the crown (far), some in front (near).
  var FOL, MASS;
  function spray(B, d, k, layer) {
    var o = FOL[layer], n = 2 + Math.round(rnd() * 2);
    ash(B, d, 21 * k, 3, o);
    for (var i = 0; i < n; i++) {
      var dd = unit(add(turn(d, (i % 2 ? 1 : -1) * between(35, 80)), [0, 1], 0.15));
      ash(B, dd, between(15, 19) * k, rnd() < 0.5 ? 2 : 3, o);
    }
  }
  function sprigs(p, wf, every, from) {
    var n = Math.floor(len(p) / every);
    for (var i = 0; i < n; i++) {
      var t = clamp((i + 0.5 + between(-0.3, 0.3)) / n, from || 0.1, 0.97), b = at(p, t), s = side(p, t);
      var j = (i + (rnd() < 0.2 ? 1 : 0)) % 2 ? 1 : -1;
      var d = unit(add(dir(p, t), s, j * between(0.7, 1.4)));
      d = unit([d[0], d[1] - 0.45]);
      var l = between(14, 30), tip = add(b, d, l);
      wood([b, add(add(b, d, l * 0.5), [-d[1], d[0]], between(-4, 4)), tip], taper(clamp(wf(t) * 0.28, 1.4, 3.4), 0.7));
      spray(tip, d, between(0.8, 1.15), rnd() < 0.5 ? "far" : "near");
      MASS.push([tip, between(20, 30)]);
    }
  }
  // Round each service, a mass of the canopy's own leaves behind its cluster,
  // on twigs from the same branch — so a cluster is the lit face of a clump.
  function canopy(T) {
    MASS.push([T.c, T.r * 1.35]);
    for (var i = 0; i < 9; i++) {
      var a = (i / 9) * Math.PI * 2 + between(-0.3, 0.3), q = add(T.c, [Math.cos(a), Math.sin(a) * 0.85], T.r * between(0.55, 1.05));
      var d = unit(add(toward(T.c, q), [0, -1], 0.35));
      wood([T.b, add(add(T.b, toward(T.b, q), dist(T.b, q) * 0.5), [-d[1], d[0]], between(-5, 5)), q], taper(2.6, 0.8));
      spray(q, d, between(0.9, 1.2), i % 3 ? "far" : "near");
    }
  }

  // ── the tree ───────────────────────────────────────────────────────────────
  // The trunk, its leader and the crown's top are drawn by hand. Each zone's
  // limb grows from them toward its services and forks as it goes, the
  // services ahead splitting at their widest gap, until each one has a branch
  // of its own: every cluster hangs on wood. Widths follow the pipe rule (a
  // branch is as thick as what it carries).
  var TRUNK = [[500, 690], [476, 618], [526, 540], [500, 478]];
  function trunkW(t) { return 60 + 44 * (1 - t) + (t < 0.2 ? 64 * Math.pow(1 - t / 0.2, 2) : 0); }
  var LEADER = [[500, 484], [492, 446], [514, 408], [506, 372]];
  var TS = LEADER[3];                                   // where the tailnet's limbs part: Tailscale
  var APEX = [[506, 376], [498, 318], [514, 268], [502, 212]];
  var WELLS = [
    { id: "nvme", x: 214, y: 738, label: "NVMe" },
    { id: "pool", x: 500, y: 744, label: "Media pool" },
    { id: "photos", x: 786, y: 738, label: "Photos & state" }
  ];
  // Each limb: its zone (the Map's colour), where it grows from (a share of
  // the trunk, or "ts": the leader's fork), which way it sets off, how thick,
  // and its door (a knot, a share along its first stretch).
  var LIMBS = [
    { id: "public", t: "Open to the internet", c: "var(--s2)", from: 0.96, d: [-0.8, -0.6], w: 24, door: ["cf", 0.5] },
    { id: "house", t: "Around the house", c: "var(--s5)", from: 0.5, d: [0.96, -0.28], w: 19, door: ["lan", 0.55] },
    { id: "watch", t: "Tailnet · watch, read & fetch", c: "var(--hud)", from: "ts", d: [0.6, -0.8], w: 24 },
    { id: "control", t: "Tailnet · dashboards & control", c: "var(--hud)", from: "ts", d: [-0.6, -0.8], w: 21 },
    { id: "vpn", t: "Inside the VPN tunnel", c: "var(--hud2)", from: 0.42, d: [-0.96, -0.28], w: 16, door: ["mullvad", 0.5] },
    { id: "crown", t: "Tailnet · the way in", c: "var(--hud)" }
  ];
  var LIMB = {};
  LIMBS.forEach(function (L) { LIMB[L.id] = L; });
  // [id, limb, x, y, size] — the canopy, placed by hand so no name sits on another.
  var LEAVES = [
    ["glance", "control", 440, 136, 40], ["ha", "control", 306, 158, 40], ["feeds", "control", 182, 248, 40], ["tools", "control", 318, 262, 38],
    ["suwayomi", "watch", 574, 134, 40], ["shelfarr", "watch", 702, 160, 40], ["flare", "watch", 830, 240, 40],
    ["abs", "watch", 670, 266, 38], ["arrs", "watch", 728, 364, 40], ["prowlarr", "watch", 868, 354, 38],
    ["seerr", "public", 150, 360, 40], ["immich", "public", 270, 376, 40], ["jellyfin", "public", 408, 352, 42],
    ["sab", "vpn", 176, 472, 40],
    ["plugs", "house", 724, 470, 38], ["tv", "house", 864, 462, 40]
  ];
  var STARS = [
    { id: "sisyphus", x: 505, y: 40, r: 5.5, label: "Sisyphus" },
    { id: "kitkat", x: 398, y: 58, r: 3, label: "Elektra" },
    { id: "apollo", x: 612, y: 58, r: 3, label: "Apollo" },
    { id: "usenet", x: 56, y: 566, r: 3.4, label: "Usenet" },
    { id: "guests", x: 64, y: 100, r: 3.4, label: "The internet" }
  ];
  function hillY(x) { return 664 + 50 * Math.pow((x - 500) / 500, 2); }

  var TIP = {}, KNOT = {}, ROOT = {};
  function centroid(ts) { var x = 0, y = 0; ts.forEach(function (t) { x += t.c[0]; y += t.c[1]; }); return [x / ts.length, y / ts.length]; }
  // The services ahead of a fork, split in two at the widest gap between them.
  function halve(ts, Q, d) {
    var s = ts.map(function (t) {
      var v = toward(Q, t.c);
      return { t: t, a: Math.atan2(d[0] * v[1] - d[1] * v[0], d[0] * v[0] + d[1] * v[1]) };
    }).sort(function (a, b) { return a.a - b.a; });
    var best = 1, top = -1;
    for (var k = 1; k < s.length; k++) {
      var sc = (s[k].a - s[k - 1].a) * (1 + Math.min(k, s.length - k) / s.length);
      if (sc > top) { top = sc; best = k; }
    }
    return [s.slice(0, best), s.slice(best)].map(function (g) { return g.map(function (x) { return x.t; }); });
  }
  // A limb from P heading d, w wide, carrying the services ts.
  function reach(P, d, ts, w, L, route, bury) {
    if (ts.length === 1) return last(P, d, ts[0], w, L, route, bury);
    var C = centroid(ts), dd = blend(d, toward(P, C), 0.55), l = dist(P, C) * between(0.36, 0.46);
    var Q = add(P, dd, l), s = [-dd[1], dd[0]];
    var seg = [P, add(P, d, l * 0.4), add(add(Q, dd, -l * 0.35), s, between(-0.1, 0.1) * l), Q];
    var w1 = w * 0.86, wf = taper(w, w1);
    wood(seg, wf, { rim: L.c, bury: bury });
    sprigs(seg, wf, 22, 0.2);
    if (!L.first) L.first = seg;
    halve(ts, Q, dd).forEach(function (g) {
      reach(Q, blend(dd, toward(Q, centroid(g)), 0.6), g, Math.min(w1, w1 * Math.sqrt(g.length / ts.length) * 1.1), L, route.concat([seg]), 0);
    });
  }
  // The last stretch: to one service, ending just short of its cluster's heart.
  function last(P, d, T, w, L, route, bury) {
    var to = toward(P, T.c), l = dist(P, T.c), end = add(T.c, to, -T.r * 0.32);
    var seg = [P, add(P, d, l * 0.38), add(end, to, -l * 0.3), end], wf = taper(w, 2.4, 0.8);
    wood(seg, wf, { rim: L.c, bury: bury });
    sprigs(seg, wf, 24, 0.2);
    if (!L.first) L.first = seg;
    T.b = end; T.dir = dir(seg, 1); T.limb = L; T.route = route.concat([seg]);
    canopy(T);
  }
  function roots() {
    WELLS.forEach(function (wl, i) {
      var sx = 500 + (i - 1) * 40;
      var p = i === 1 ? [[500, 668], [494, 700], [506, 718], [500, wl.y - 6]]
        : [[sx, 672], [sx + (wl.x - sx) * 0.35, 698], [wl.x - (i - 1) * 40, wl.y - 44], [wl.x - (i - 1) * 6, wl.y - 9]];
      ROOT[wl.id] = p;
      wood(p, taper(i === 1 ? 46 : 34, 5, 0.8), { grain: 2, rim: "var(--s4)", bury: 18 });
      for (var k = 0; k < 3; k++) {
        var t = between(0.3, 0.8), b = at(p, t), d = unit(add(dir(p, t), side(p, t), (k % 2 ? 1 : -1) * 1.1));
        d = unit([d[0], Math.abs(d[1]) + 0.25]);
        var l = between(14, 28);
        wood([b, add(add(b, d, l * 0.5), [-d[1], d[0]], between(-3, 3)), add(b, d, l)], taper(4.5, 0.6));
      }
    });
    // buttresses: short, thick roots gripping the hill either side
    [[-1, 382, 30], [1, 618, 30], [-1, 438, 22], [1, 566, 22]].forEach(function (r) {
      var y = hillY(r[1]);
      wood([[500 + r[0] * 30, 650], [500 + r[0] * 66, 664], [r[1] - r[0] * 26, y - 2], [r[1], y + 6]], taper(r[2], 1.5, 0.7), { bury: 16, grain: 1 });
    });
  }
  function grow() {
    seed = 7;
    WOOD = { body: "", lit: "", lit2: "", dark: "", dark2: "", rim: {}, grain: "", shine: "" };
    FOL = { far: { leaf: "", rib: "" }, near: { leaf: "", rib: "" } };
    MASS = [];
    TIP = {}; KNOT = {}; ROOT = {};
    LIMBS.forEach(function (L) { L.leaves = []; L.knots = []; L.first = null; });
    LEAVES.forEach(function (v) { TIP[v[0]] = { id: v[0], c: [v[2], v[3]], r: v[4] }; LIMB[v[1]].leaves.push(v[0]); });
    roots();
    wood(TRUNK, trunkW, { rim: "var(--hud)", grain: 18, n: 56 });
    wood(LEADER, taper(40, 30), { rim: "var(--hud)", bury: 24, grain: 4 });
    wood(APEX, taper(17, 2.4, 0.9), { rim: "var(--hud)", bury: 12 });
    sprigs(APEX, taper(17, 2.4, 0.9), 16, 0.15);
    sprigs(LEADER, taper(40, 30), 30, 0.5);
    LIMBS.forEach(function (L) {
      if (!L.leaves.length) return;
      var ts = L.leaves.map(function (id) { return TIP[id]; });
      var P = L.from === "ts" ? TS : at(TRUNK, L.from);
      reach(P, unit(L.d), ts, L.w, L, L.from === "ts" ? [LEADER] : [], L.from === "ts" ? 14 : trunkW(L.from) / 2);
      if (L.door) { L.knots = [L.door[0]]; KNOT[L.door[0]] = { p: at(L.first, L.door[1]), limb: L }; }
    });
    LIMB.crown.knots = ["tailnet"];
    KNOT.tailnet = { p: TS, limb: LIMB.crown };
  }

  // ── a service's cluster: twiglets fanning from its branch's tip, in leaf ──
  function leaf(o, B, d, L) {
    var x = { leaf: "", rib: "", vein: "" };
    ash(B, d, L, 3, x, true);
    o[d[1] < -0.3 ? "b" : "a"] += x.leaf;
    o.rib += x.rib; o.vein += x.vein;
  }
  function cluster(id) {
    var T = TIP[id], o = { a: "", b: "", rib: "", vein: "", tw: "" }, n = 7;
    for (var i = 0; i < n; i++) {
      var d = turn(T.dir, -118 + 236 * (i + 0.5) / n + between(-16, 16));
      d = unit([d[0], d[1] - 0.3]);
      var l = T.r * between(0.3, 0.66), tip = add(T.b, d, l);
      var tw = [T.b, add(add(T.b, d, l * 0.5), [-d[1], d[0]], between(-4, 4)), tip];
      o.tw += band(tw, taper(3.6, 0.9), 6, -1, 1);
      leaf(o, tip, unit(add(d, [0, 1], between(0, 0.3))), T.r * between(0.42, 0.6));
      var t = between(0.35, 0.65);
      leaf(o, at(tw, t), unit(add(dir(tw, t), side(tw, t), (i % 2 ? 1 : -1) * between(1, 1.6))), T.r * between(0.32, 0.44));
    }
    // two hanging low, either side of where the branch comes in
    [-1, 1].forEach(function (j) { leaf(o, add(T.b, T.dir, 2), unit(add(turn(T.dir, j * 110), [0, 1], 0.5)), T.r * 0.45); });
    var fall = "";
    for (var k = 0; k < 3; k++) {
      fall += '<path class="yg-fall" style="--fx:' + f(between(-26, 26)) + "px;--fd:" + f(between(3.4, 5.6)) + "s;--fl:-" + f(between(0, 5)) + 's" d="' +
        leaflet([0, 0], [1, 0], 10) + '" transform="translate(' + pt([T.c[0] + between(-16, 16), T.c[1] + between(-8, 10)]) + ')"/>';
    }
    return '<g class="yg-c" data-id="' + id + '" style="--zc:' + T.limb.c + '">' +
      '<circle class="yg-glow" cx="' + T.c[0] + '" cy="' + T.c[1] + '" r="' + f(T.r * 1.2) + '"/>' +
      '<g class="yg-sway" style="transform-origin:' + f(T.b[0]) + "px " + f(T.b[1]) + "px;--sd:" + f(between(5.5, 8.5)) + "s;--sl:-" + f(between(0, 6)) + 's">' +
        '<path class="yg-leaf a" d="' + o.a + '"/><path class="yg-twigs" d="' + o.tw + '"/><path class="yg-leaf b" d="' + o.b + '"/>' +
        '<path class="yg-rib" d="' + o.rib + '"/><path class="yg-vein" d="' + o.vein + '"/>' +
      '</g>' + fall +
      '<circle class="yg-hit" cx="' + T.c[0] + '" cy="' + T.c[1] + '" r="' + (T.r + 10) + '"/>' +
      '<text class="yg-l" x="' + T.c[0] + '" y="' + (T.c[1] + T.r + 13) + '">' + D.esc(short(id)) + '</text>' +
    '</g>';
  }
  // A door: a burl on its limb with a light inside.
  function knot(id) {
    var s = KNOT[id], c = s.p;
    return '<g class="yg-k" data-id="' + id + '" style="--zc:' + s.limb.c + '">' +
      '<ellipse class="yg-burl" cx="' + f(c[0]) + '" cy="' + f(c[1]) + '" rx="12" ry="10"/>' +
      '<circle class="yg-ring" cx="' + f(c[0]) + '" cy="' + f(c[1]) + '" r="15"/>' +
      '<circle class="yg-knot" cx="' + f(c[0]) + '" cy="' + f(c[1]) + '" r="5"/>' +
      '<circle class="yg-hit" cx="' + f(c[0]) + '" cy="' + f(c[1]) + '" r="20"/>' +
      '<text class="yg-l k" x="' + f(c[0]) + '" y="' + f(c[1] + 30) + '">' + D.esc(short(id)) + '</text></g>';
  }

  var api = null;
  function name(id) { var n = api && api.nodes[id]; return n ? n.t : id; }
  // Short names on the tree itself (the chips and the detail use the full ones).
  var SHORT = { arrs: "The arrs", abs: "Audiobooks", tv: "Eclipse", feeds: "Live feeds", tools: "Terminal & files", cf: "Cloudflare", lan: "Home LAN", ha: "Home Assistant", mullvad: "Mullvad" };
  function short(id) { return SHORT[id] || name(id); }

  // "Asgard" in the elder futhark (ᚨᛋᚷᚨᚱᛞ), carved low on the trunk — as
  // strokes, since few fonts carry runes. Each in a 0.6 × 1 box.
  var RUNE = {
    a: [[0, 0, 0, 1], [0, 0.05, 0.5, 0.3], [0, 0.35, 0.5, 0.6]],
    s: [[0.5, 0, 0.05, 0.42], [0.05, 0.42, 0.5, 0.58], [0.5, 0.58, 0.05, 1]],
    g: [[0, 0, 0.6, 1], [0.6, 0, 0, 1]],
    r: [[0, 0, 0, 1], [0, 0, 0.45, 0.22], [0.45, 0.22, 0, 0.48], [0, 0.48, 0.5, 1]],
    d: [[0, 0, 0, 1], [0.7, 0, 0.7, 1], [0, 0, 0.7, 1], [0.7, 0, 0, 1]]
  };
  function runes(word, x, y, h, gap) {
    var out = "", cx = x - (word.length * gap) / 2;
    word.split("").forEach(function (ch) {
      RUNE[ch].forEach(function (s) { out += "M" + pt([cx + s[0] * h, y + s[1] * h]) + "L" + pt([cx + s[2] * h, y + s[3] * h]); });
      cx += gap;
    });
    return out;
  }
  // The heartwood, showing through a crack up the trunk's middle.
  function crack() {
    var A = [], B = [];
    for (var i = 0; i <= 30; i++) {
      var t = 0.3 + 0.64 * i / 30, c = at(TRUNK, t), s = side(TRUNK, t);
      var o = Math.sin(t * 31) * 3 + between(-1.6, 1.6), w = (1.4 + 3.4 * Math.sin(Math.PI * i / 30)) * between(0.6, 1.25);
      A.push(add(c, s, o - w / 2)); B.push(add(c, s, o + w / 2));
    }
    return poly(A.concat(B.reverse()), true);
  }

  function draw() {
    grow();
    var g = function (cls, d) { return d ? '<path class="' + cls + '" d="' + d.replace(/ -/g, "-") + '"/>' : ""; };
    var defs = '<defs>' +
      '<radialGradient id="yg-sky" cx="50%" cy="10%" r="85%"><stop offset="0" style="stop-color:rgb(var(--hud-rgb) / .14)"/><stop offset=".55" style="stop-color:rgb(var(--hud2-rgb) / .04)"/><stop offset="1" style="stop-color:transparent"/></radialGradient>' +
      '<radialGradient id="yg-aura"><stop offset="0" style="stop-color:rgb(var(--hud-rgb) / .09)"/><stop offset=".6" style="stop-color:rgb(var(--hud2-rgb) / .04)"/><stop offset="1" style="stop-color:transparent"/></radialGradient>' +
      // one field for the hill and the earth round the trunk's foot, so the two are one ground
      '<linearGradient id="yg-hill" gradientUnits="userSpaceOnUse" x1="0" y1="664" x2="0" y2="' + H + '"><stop offset="0" style="stop-color:color-mix(in srgb, var(--hud) 9%, #11161b)"/>' +
        '<stop offset=".38" style="stop-color:color-mix(in srgb, var(--hud) 6%, #0f1317)"/><stop offset="1" style="stop-color:#0b0e11;stop-opacity:0"/></linearGradient>' +
      '<filter id="yg-glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>' +
      '<filter id="yg-soft" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="12"/></filter>' +
    '</defs>';
    // ── the still picture (drawn once) ──
    var back = '<svg class="yg yg-back" viewBox="0 0 ' + W + " " + H + '" aria-hidden="true">' + defs +
      '<rect width="' + W + '" height="' + H + '" fill="url(#yg-sky)"/>' +
      '<ellipse class="yg-aura" cx="520" cy="300" rx="470" ry="250"/>';
    // the hill, its grass, a mist at the foot of the tree
    var hill = [];
    for (var x = 0; x <= W; x += 25) hill.push([x, hillY(x)]);
    var grass = "";
    for (var i = 0; i < 120; i++) {
      var gx = between(4, W - 4), gy = hillY(gx) + between(-1, 7), gh = between(5, 13), lean = between(-5, 5);
      grass += "M" + pt([gx, gy]) + "Q" + pt([gx + lean * 0.3, gy - gh * 0.6]) + " " + pt([gx + lean, gy - gh]);
    }
    back += '<path class="yg-hill" d="' + poly(hill) + "L" + W + " " + H + "L0 " + H + 'Z"/>' +
      '<path class="yg-hill-edge" d="' + poly(hill) + '"/>' + g("yg-grass", grass) +
      '<ellipse class="yg-ground" cx="500" cy="676" rx="300" ry="26"/>';
    // the crown's depths, the wood, the leaves in front
    back += g("yg-mass", MASS.map(function (m) { var r = f(m[1]); return "M" + f(m[0][0] - m[1]) + " " + f(m[0][1]) + "a" + r + " " + r + " 0 1 0 " + f(2 * m[1]) + " 0a" + r + " " + r + " 0 1 0 " + f(-2 * m[1]) + " 0Z"; }).join("")) +
      g("yg-fol far", FOL.far.leaf) + g("yg-stalk far", FOL.far.rib) +
      g("yg-wood", WOOD.body) + g("yg-wood-dark", WOOD.dark) + g("yg-wood-dark deep", WOOD.dark2) + g("yg-wood-lit", WOOD.lit) + g("yg-wood-lit hi", WOOD.lit2) + g("yg-grain", WOOD.grain) + g("yg-grain hi", WOOD.shine) +
      Object.keys(WOOD.rim).map(function (c) { return '<path class="yg-edge" style="--zc:' + c + '" d="' + WOOD.rim[c] + '"/>'; }).join("");
    // the earth heaped round the trunk's foot, so it grows out of the hill
    var mound = "";
    for (var mi = 0; mi < 44; mi++) {
      var mx = between(372, 628), my = 690 - 15 * Math.sqrt(Math.max(0, 1 - Math.pow((mx - 500) / 132, 2))) + between(0, 4), mh = between(4, 10), ml = between(-4, 4);
      mound += "M" + pt([mx, my]) + "Q" + pt([mx + ml * 0.3, my - mh * 0.6]) + " " + pt([mx + ml, my - mh]);
    }
    back += '<ellipse class="yg-mound" cx="500" cy="694" rx="134" ry="17"/>' + g("yg-grass", mound);
    // a hollow low on the trunk (lit from inside, in the live layer)
    var ho = add(at(TRUNK, 0.56), side(TRUNK, 0.56), -0.36 * trunkW(0.56) / 2);
    back += '<ellipse class="yg-hollow" cx="' + f(ho[0]) + '" cy="' + f(ho[1]) + '" rx="9" ry="15"/>';
    // the wells: a ring of stones, the water
    back += WELLS.map(function (wl) {
      var st = "";
      for (var k = 0; k < 18; k++) {
        var a = (k / 18) * Math.PI * 2 + between(-0.05, 0.05);
        st += '<ellipse cx="' + f(wl.x + Math.cos(a) * 64) + '" cy="' + f(wl.y + Math.sin(a) * 16) + '" rx="' + f(between(7, 10)) + '" ry="' + f(between(3.6, 5)) + '"/>';
      }
      return '<ellipse class="yg-rim" cx="' + wl.x + '" cy="' + wl.y + '" rx="66" ry="17"/>' +
        '<ellipse class="yg-water" cx="' + wl.x + '" cy="' + (wl.y + 1) + '" rx="56" ry="11"/>' + '<g class="yg-stones">' + st + '</g>';
    }).join("");
    back += g("yg-fol near", FOL.near.leaf) + g("yg-stalk near", FOL.near.rib) + '</svg>';

    // ── the live layer: everything that moves or answers a tap ──
    var h = '<svg class="yg yg-live" viewBox="0 0 ' + W + " " + H + '" role="img" aria-label="Asgard as a living tree">';
    var sky = "";
    for (var s = 0; s < 70; s++) {
      var sx = between(8, W - 8), sy = between(6, 560);
      if (sy > 70 + 270 * Math.pow((sx - 505) / 470, 2)) continue;              // not in front of the crown
      sky += '<circle cx="' + f(sx) + '" cy="' + f(sy) + '" r="' + f(between(0.5, 1.4)) + '" style="--tw:' + f(between(2.5, 6)) + "s;--tl:-" + f(between(0, 6)) + 's"/>';
    }
    h += '<g class="yg-sky">' + sky + '</g>';
    // roots that glow while their disk is busy; the wells' fill rings
    h += '<g class="yg-roots">' + WELLS.map(function (wl) { return '<path class="yg-rootglow" data-well="' + wl.id + '" d="' + poly(trace(ROOT[wl.id], 0.1, 1, 20)) + '"/>'; }).join("") + '</g>';
    h += WELLS.map(function (wl) {
      var C = 2 * Math.PI * 30;
      return '<g class="yg-w" data-id="' + wl.id + '">' +
        '<circle class="yg-fill" cx="' + wl.x + '" cy="' + (wl.y + 1) + '" r="30" transform="translate(' + wl.x + " " + (wl.y + 1) + ") scale(1.86 .37) translate(" + -wl.x + " " + -(wl.y + 1) + ')" style="stroke-dasharray:0 ' + f(C) + '"/>' +
        '<ellipse class="yg-ripple" cx="' + wl.x + '" cy="' + (wl.y + 1) + '" rx="10" ry="3"/>' +
        '<ellipse class="yg-hit" cx="' + wl.x + '" cy="' + wl.y + '" rx="76" ry="30"/>' +
        '<text class="yg-l w" x="' + wl.x + '" y="' + (wl.y + 38) + '">' + D.esc(wl.label) + '</text></g>';
    }).join("");
    // the trunk: its heartwood, the hollow's light, the runes — all with the CPU
    var cr = crack();
    h += '<g class="yg-trunk" data-id="asgard">' +
      '<path class="yg-heart glow" d="' + cr + '"/><path class="yg-heart" d="' + cr + '"/>' +
      '<ellipse class="yg-heart glow" cx="' + f(ho[0]) + '" cy="' + f(ho[1] + 2) + '" rx="5" ry="10"/>' +
      '<path class="yg-runes" d="' + runes("asgard", 500, 628, 13, 12) + '"/>' +
      '<path class="yg-hit" d="' + band(TRUNK, trunkW, 18, -1, 1) + '"/>' +
      '<text class="yg-l trunk" x="500" y="664">Asgard</text></g>';
    // effects: sap, the play beam, the game beam, the seeds' roads
    var J = TIP.jellyfin, tv = TIP.tv, sab = TIP.sab, sis = STARS[0], us = STARS[3], pool = [500, WELLS[1].y + 1];
    var sap = [pool].concat(trace(TRUNK, 0, LIMB.public.from, 24));
    J.route.forEach(function (p) { sap = sap.concat(trace(p, 0, 1, 14)); });
    sap.push(J.c);
    var fallr = [sab.c];
    sab.route.slice().reverse().forEach(function (p) { fallr = fallr.concat(trace(rev(p), 0, 1, 12)); });
    fallr = fallr.concat(trace(TRUNK, LIMB.vpn.from, 0, 16)).concat([pool]);
    h += '<g class="yg-fx">' +
      '<path class="yg-sap" d="' + poly(sap) + '"/>' +
      '<path class="yg-beam play" d="M' + pt(J.c) + "Q640 640 " + pt(tv.c) + '"/>' +
      '<path class="yg-beam game" d="M' + sis.x + " " + sis.y + "Q960 130 " + pt(tv.c) + '"/>' +
      '<path id="yg-seedroad" class="yg-road" d="M' + us.x + " " + us.y + "Q70 480 " + pt(sab.c) + '"/>' +
      '<path id="yg-fallroad" class="yg-road" d="' + poly(fallr) + '"/>' +
      '<g class="yg-seeds"></g>' +
    '</g>';
    h += '<g class="yg-leaves">' + LEAVES.map(function (v) { return cluster(v[0]); }).join("") + '</g>';
    h += '<g class="yg-knots">' + Object.keys(KNOT).map(knot).join("") + '</g>';
    h += '<g class="yg-stars">' + STARS.map(function (s) {
      return '<g class="yg-s" data-id="' + s.id + '"><circle class="yg-halo" cx="' + s.x + '" cy="' + s.y + '" r="' + s.r * 3.2 + '"/>' +
        '<circle class="yg-star" cx="' + s.x + '" cy="' + s.y + '" r="' + s.r + '"/>' +
        '<circle class="yg-hit" cx="' + s.x + '" cy="' + s.y + '" r="18"/>' +
        '<text class="yg-l s" x="' + s.x + '" y="' + (s.y + s.r + 15) + '">' + D.esc(s.label) + '</text></g>';
    }).join("") + '</g>';
    return back + h + '</svg>';
  }

  // ── the card around it ─────────────────────────────────────────────────────
  var el = null, svg = null, stage = null, streams = [], sel = null;
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
    svg = el.querySelector("svg.yg-live");
    stage = el.querySelector(".yg-stage");
    el.addEventListener("click", onClick);
    detail();
    open();
  }
  function unmount() {
    streams.forEach(function (s) { s.close(); });
    streams = [];
    if (el) { el.removeEventListener("click", onClick); el.innerHTML = ""; }
    el = svg = stage = null;
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
    stage.style.setProperty("--wind", clamp(Math.log10((live.mbps || 0) + 1) / 2.6, 0, 1).toFixed(2));
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
    stage.style.setProperty("--cpu", clamp((live.cpu || 0) / 70, 0.08, 1).toFixed(2));
    stage.style.setProperty("--yg-heat", "color-mix(in oklch, var(--hud), #ffb347 " + Math.round(heat * 100) + "%)");
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
