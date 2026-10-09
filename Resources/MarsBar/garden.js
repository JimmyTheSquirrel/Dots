// ════════════════════════════════════════════════════════════════════════════
// garden.js — MarsBar's vine, alive (marsbar:1111 only; whatever colour she
// has picked). On unless she turns it off: the colour picker's "Just for fun"
// section has a Garden switch (theme.js), kept in THIS browser's localStorage
// as marsbar-garden = "off". Off, everything below goes — crowns, butterflies,
// fireflies, the night/dark attributes — and the static bloom.svg blossom is
// back on every card; on again, it all comes back without a reload.
//
//   blossoms     every card's crown blossom is redrawn as a rigged inline SVG
//                (.mb-crown) whose five petals slowly fold shut and open again
//                — each card on its own slow cycle, so they never move as one —
//                while the flower sways a little on its stem. From 20:00 to
//                06:00 they stay shut (<html data-mb-night>) and open again in
//                the morning.
//   butterflies  now and then ONE butterfly flutters in from the left or the
//                top, lands on a card's vine, slowly fans its wings, then
//                visits another card or leaves. Tap it and it bolts.
//   fireflies    at night, or when every light is off (<html data-mb-dark>),
//                a dozen fireflies drift and blink over the page.
//
// Why the crown is redrawn rather than left to bloom.svg: a CSS background is
// one flat picture, and nothing inside it can move. So once the crowns are in,
// <html class="mb-garden"> hides the old ::before blossom (marsbar.css) and
// the inline copy, drawn to the same coordinates, takes its place. Its colours
// are written against --mb-h / --mb-h2 like the rest of marsbar.css — the
// gradients live in ONE hidden <svg> in <body> that every crown references —
// so her colour picker recolours the blossoms live. The Cats theme keeps its
// kitten face: cats.css draws that on the ::before, and .mb-crown hides.
//
// The page must never grow or scroll sideways because of a butterfly. They
// live in .mb-sky, a zero-size box at the document's origin, placed by
// transform in PAGE coordinates — and they only ever enter or leave across
// the left or top edge, because overflow past those edges can't be scrolled
// to. Every point of a flight is also clamped inside the page's right and
// bottom edges.
//
// Phone battery: whatever moves, moves by transform or opacity — CSS
// animations or the Web Animations API, nothing per-frame in JS. The only
// layout reads are at a butterfly's take-off and landing, and one rect every
// 1.5 s while it rests (has its card gone? On a phone Glance shows one column
// at a time, and a butterfly sitting on a hidden card's vine flies off).
// Nothing spawns in a hidden tab. Reduced motion: crowns stand still
// (marsbar.css stops every animation) and no butterfly or firefly is ever
// made.
//
// Hooks for CSS and other scripts — all aria-hidden, none takes a tap except
// a resting butterfly:
//   html.mb-garden          crowns are in; the ::before blossom is hidden
//   html[data-mb-night]     20:00–06:00 local (re-checked every minute)
//   html[data-mb-dark]      the All Lights switch (.mb-hero) reads "off"
//   .mb-crown               a card's blossom, in its .widget-header
//   .mb-sky > .mb-fly       the butterfly (.rest while it sits; .bolt fleeing)
//   .mb-fireflies           the firefly layer (.on while shown)
//   window.Garden           { on(), off(), enabled } — for theme.js's switch
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";

  if (!window.Dash) return;   // dash.js loads first; no Dash, no page to garden

  var root = document.documentElement;
  var still = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  var enabled = true;
  try { enabled = localStorage.getItem("marsbar-garden") !== "off"; } catch (e) { /* private window: on */ }

  // ⚠ Glance's templating.js replaces HTMLElement.prototype.animate with its
  // own animate({keyframes, options}, callback), which returns the ELEMENT, not
  // an Animation — called the standard way it throws and nothing ever
  // finishes. Element.prototype.animate is still the browser's own: use that.
  var nativeAnimate = Element.prototype.animate;
  function animate(el, keyframes, options) { return nativeAnimate.call(el, keyframes, options); }

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function pick(list) { return list[Math.floor(Math.random() * list.length)]; }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function px(n) { return n.toFixed(1); }

  // A colour on one of her two hues, e.g. tint("--mb-h", 51, 100, 94) →
  // hsl(calc(var(--mb-h) + 51), 100%, 94%). A literal would ignore her pick.
  function tint(v, n, s, l) {
    return "hsl(calc(var(" + v + ") " + (n < 0 ? "- " + -n : "+ " + n) + "), " + s + "%, " + l + "%)";
  }
  function stop(at, colour) { return '<stop offset="' + at + '" style="stop-color: ' + colour + '"/>'; }

  // ── the blossoms ───────────────────────────────────────────────────────────
  // bloom.svg, redrawn: same leaves, stem and flower, same coordinates (so the
  // crown sits exactly where the picture did), its colours turned into hue
  // offsets. Each petal is its own <ellipse class="pet"> inside a rotated <g>
  // — the rotation stays an attribute, because a CSS transform on an SVG
  // element replaces its transform attribute — so marsbar.css can fold each
  // petal toward the flower's heart.
  var DEFS =
    '<svg class="mbg-defs" aria-hidden="true" focusable="false"><defs>' +
      '<radialGradient id="mbg-pt" cx="0" cy="0" r="6" gradientUnits="userSpaceOnUse">' +
        stop(0, tint("--mb-h", 51, 100, 94)) + stop(0.45, tint("--mb-h", 27, 61, 75)) + stop(1, tint("--mb-h", 0, 55, 59)) +
      '</radialGradient>' +
      '<linearGradient id="mbg-lf" x1="0" y1="-6" x2="16" y2="4" gradientUnits="userSpaceOnUse">' +
        stop(0, tint("--mb-h2", -3, 57, 72)) + stop(0.55, tint("--mb-h2", 1, 42, 53)) + stop(1, tint("--mb-h2", 5, 46, 34)) +
      '</linearGradient>' +
      '<linearGradient id="mbg-ly" x1="0" y1="-6" x2="16" y2="4" gradientUnits="userSpaceOnUse">' +
        stop(0, tint("--mb-h", 3, 74, 83)) + stop(0.6, tint("--mb-h", -3, 55, 66)) + stop(1, tint("--mb-h", -9, 38, 47)) +
      '</linearGradient>' +
    '</defs></svg>';

  var LEAF = "M0 0 C3 -5.6 10 -7.6 17 -1.6 C10.6 4.6 3.6 4.1 0 0Z";
  var MIDRIB = "M0.8 0 Q8 -1.4 16.2 -1.6";

  function crownSvg() {
    // A little lag between the petals, different on every crown, so a flower
    // folds like a flower and not like a shutter.
    var petals = "";
    [0, 72, 144, 216, 288].forEach(function (a) {
      petals += '<g transform="rotate(' + a + ')"><ellipse class="pet" cy="-3.6" rx="2.5" ry="3.9" style="--pd: ' +
        px(rnd(0, 0.7)) + 's"/></g>';
    });
    return '<svg viewBox="-20 -20 40 40" width="40" height="40" focusable="false">' +
      '<g transform="translate(-2 6) rotate(160) scale(.85)">' +
        '<path d="' + LEAF + '" fill="url(#mbg-lf)"/>' +
        '<path class="mbc-vn" d="' + MIDRIB + '" fill="none" stroke-opacity=".55" stroke-width=".55"/>' +
        '<path class="mbc-vn" d="M4.6 -0.5 L7.4 -4.1 M8.6 -1 L11.6 -4.4 M12.2 -1.3 L14.2 -3.4 M4.6 -0.5 L7.6 2.3 M8.6 -1 L11.4 1.6" fill="none" stroke-opacity=".35" stroke-width=".4"/>' +
      '</g>' +
      '<g transform="translate(2 6) rotate(20) scale(.7)">' +
        '<path d="' + LEAF + '" fill="url(#mbg-ly)"/>' +
        '<path class="mbc-vy" d="' + MIDRIB + '" fill="none" stroke-opacity=".5" stroke-width=".55"/>' +
      '</g>' +
      '<path class="mbc-st" d="M0 20 L0 7" stroke-width="1.6" stroke-linecap="round"/>' +
      '<g transform="translate(0 -1) scale(1.9)">' +
        '<g fill="url(#mbg-pt)">' + petals + '</g>' +
        '<g class="mbc-hrt"><circle r="1.7" fill="#f3c55f"/>' +
          '<g fill="#fff4d0"><circle cx=".9" cy="-.6" r=".35"/><circle cx="-.8" cy="-.4" r=".3"/><circle cy=".9" r=".3"/></g>' +
        '</g>' +
      '</g>' +
    '</svg>';
  }

  // Top-level cards only: a widget nested in another (a Glance group) would
  // put a second flower in the middle of a card.
  function cards() {
    var out = [], ws = document.querySelectorAll(".widget");
    for (var i = 0; i < ws.length; i++) {
      var up = ws[i].parentElement;
      if (!up || !up.closest(".widget")) out.push(ws[i]);
    }
    return out;
  }

  // Idempotent: runs once Glance's markup is in, then every minute, so a card
  // that arrives late (or is re-rendered) still gets its blossom.
  function crowns() {
    if (!enabled) return;
    var ws = cards(), made = 0;
    for (var i = 0; i < ws.length; i++) {
      var head = ws[i].firstElementChild;
      if (!head || !head.classList.contains("widget-header") || head.querySelector(".mb-crown")) continue;
      // Every crown on its own cycle (--gd, 20–28 s), started at a random
      // point in it (--gl), swaying out of step with the rest (--gs).
      var c = document.createElement("span"), d = rnd(20, 28);
      c.className = "mb-crown";
      c.setAttribute("aria-hidden", "true");
      c.style.setProperty("--gd", px(d) + "s");
      c.style.setProperty("--gl", px(-rnd(0, d)) + "s");
      c.style.setProperty("--gw", px(rnd(6, 8)) + "s");
      c.style.setProperty("--gs", px(-rnd(0, 8)) + "s");
      c.innerHTML = crownSvg();
      head.appendChild(c);
      made++;
    }
    if (made && !document.querySelector(".mbg-defs")) document.body.insertAdjacentHTML("beforeend", DEFS);
    if (made) root.classList.add("mb-garden");
  }

  // Evening: marsbar.css swaps each petal's cycle for the shut pose — but a
  // browser starts no CSS transition when an animation and the value under it
  // change in the same breath (Chrome snaps), so each petal and heart is
  // walked there from wherever its cycle had it by a one-off animation.
  var PARTS = ".mb-crown .pet, .mb-crown .mbc-hrt";
  function pose(el) {
    var cs = getComputedStyle(el);
    return { transform: cs.transform, strokeOpacity: cs.strokeOpacity, opacity: cs.opacity };
  }
  function nightfall() {
    var parts = document.querySelectorAll(PARTS), from = [], i;
    for (i = 0; i < parts.length; i++) from.push(pose(parts[i]));
    root.setAttribute("data-mb-night", "");
    if (still.matches || !parts.length || !nativeAnimate) return;
    for (i = 0; i < parts.length; i++) {
      animate(parts[i], [from[i], pose(parts[i])], { duration: 6000, easing: "ease-in-out" });
    }
  }

  // Morning: start every crown's cycle in its "held shut" stretch, so the
  // flowers open slowly instead of snapping to wherever their cycle would be.
  function wake() {
    var cs = document.querySelectorAll(".mb-crown");
    for (var i = 0; i < cs.length; i++) {
      var d = parseFloat(cs[i].style.getPropertyValue("--gd")) || 24;
      cs[i].style.setProperty("--gl", px(-d * rnd(0.68, 0.75)) + "s");
    }
  }

  // ── night and lights-out ───────────────────────────────────────────────────
  // The attribute is the truth (so a hand-set one is honoured until the next
  // minute's check, and anything else can read it).
  function clock() {
    if (!enabled) return;
    var h = new Date().getHours(), night = h >= 20 || h < 6;
    if (night === root.hasAttribute("data-mb-night")) return;
    if (night) nightfall();
    else { wake(); root.removeAttribute("data-mb-night"); }
    dusk();
  }

  // Every light off: the All Lights switch is the group, so its state says it.
  // lights.js paints data-ha-state before it fires ha:state; no switch on the
  // page (or no answer yet) is not "dark".
  function dusk() {
    if (!enabled) return;
    var hero = document.querySelector(".mb-hero[data-ha-state]");
    var dark = !!hero && hero.getAttribute("data-ha-state") === "off";
    if (dark !== root.hasAttribute("data-mb-dark")) {
      if (dark) root.setAttribute("data-mb-dark", "");
      else root.removeAttribute("data-mb-dark");
    }
    fireflies(!still.matches && (dark || root.hasAttribute("data-mb-night")));
  }

  // ── the fireflies ──────────────────────────────────────────────────────────
  // Made the first time they are wanted. Each drifts on its own slow path
  // (CSS keyframes through --x1/--y1 … --x3/--y3) and blinks on its own
  // rhythm, dark as long as lit, so only a few glow at once. Faded out, the
  // layer is display:none — a hidden layer still running two dozen
  // animations would cost battery for nothing.
  var ff = null, ffOff = null;
  function fireflies(on) {
    if (on && !ff) {
      ff = document.createElement("div");
      ff.className = "mb-fireflies";
      ff.setAttribute("aria-hidden", "true");
      ff.hidden = true;
      var html = "";
      for (var i = 0; i < 12; i++) {
        var p = ["left: " + px(rnd(4, 96)) + "%", "top: " + px(rnd(6, 90)) + "%"];
        for (var k = 1; k <= 3; k++) {
          p.push("--x" + k + ": " + px(rnd(-60, 60)) + "px", "--y" + k + ": " + px(rnd(-50, 50)) + "px");
        }
        var drift = rnd(14, 24), blink = rnd(2.5, 5);
        p.push("--fd: " + px(drift) + "s", "--fdl: " + px(-rnd(0, drift)) + "s",
          "--fg: " + px(blink) + "s", "--fgl: " + px(-rnd(0, blink)) + "s");
        if (Math.random() < 0.3) p.push("--fs: .75");
        html += '<i style="' + p.join("; ") + '"></i>';
      }
      ff.innerHTML = html;
      document.body.appendChild(ff);
    }
    if (!ff) return;
    clearTimeout(ffOff);
    if (on) {
      if (ff.hidden) {
        ff.hidden = false;
        void ff.offsetWidth;   // commit display before the fade, or it won't transition
      }
      ff.classList.add("on");
    } else if (!ff.hidden) {
      ff.classList.remove("on");
      ffOff = setTimeout(function () { ff.hidden = true; }, 2600);
    }
  }

  // ── the butterflies ────────────────────────────────────────────────────────
  // Drawn from above, 26×22: two wings (forewing over hindwing, a few white
  // spots) — the right one the left one mirrored — and a dark body with a
  // head and clubbed antennae. Each wing is its own little <svg>, so a flap
  // is an HTML scaleX about the body: composited, no repaint.
  //   .mb-fly   position (WAAPI translate) and its shadow
  //   .mbf-o    heading (WAAPI rotate) — split from the position so the
  //             shadow stays below the butterfly whichever way it faces
  //   .mbf-b    the flight's bob
  var HUES = [40, -40, 70, 0, 110, 160];   // from her purple: pink, blue, coral, hers, apricot, lime
  var W = 26, H = 22;                 // the butterfly's box; its centre is the body
  var WING =
    '<path class="hw" d="M-0.8 0.4 C-4.5 0 -9.6 0.4 -10.4 3.2 C-10.8 6.4 -8.2 9.6 -5 10 C-3 10.2 -1.4 7.4 -0.6 4.2Z"/>' +
    '<path class="fw" d="M-0.8 -3.8 C-4 -8.5 -9.5 -10.5 -12.4 -9 C-13.4 -6.5 -12.6 -2.6 -10.6 -0.6 C-7.5 0.6 -3.5 0.6 -0.8 0.2Z"/>' +
    '<g class="sp"><circle cx="-10.3" cy="-7.3" r=".75"/><circle cx="-8.4" cy="-8.4" r=".5"/><circle cx="-6.6" cy="6.3" r=".7"/></g>';

  function hue(n, s, l) {   // a wing colour: her purple + this butterfly's --fh + n
    return "hsl(calc(var(--mb-h) + var(--fh) + " + n + "), " + s + "%, " + l + "%)";
  }

  var sky = null, fly = null, nextT = null, serial = 0, lastW = window.innerWidth;

  function butterfly() {
    var n = ++serial, fh = pick(HUES);
    var el = document.createElement("div");
    el.className = "mb-fly";
    el.setAttribute("aria-hidden", "true");
    el.style.setProperty("--fh", fh);
    el.style.setProperty("--fa", px(rnd(2.8, 4.2)) + "s");
    var fw = "mbf-f" + n, hw = "mbf-h" + n;
    // The wing gradients live in this butterfly's own body <svg>, so they
    // inherit its --fh (a stop takes custom properties from where it sits,
    // not from the shape that uses it). Darker at the root, bright across the
    // middle, a dusky edge at the tip.
    var defs = '<defs>' +
      '<radialGradient id="' + fw + '" cx="0" cy="-1" r="13" gradientUnits="userSpaceOnUse">' +
        stop(0, hue(-6, 45, 36)) + stop(0.32, hue(0, 78, 68)) + stop(0.66, hue(0, 92, 80)) +
        stop(0.88, hue(14, 95, 86)) + stop(1, hue(4, 60, 55)) +
      '</radialGradient>' +
      '<radialGradient id="' + hw + '" cx="0" cy="1" r="11" gradientUnits="userSpaceOnUse">' +
        stop(0, hue(-6, 45, 34)) + stop(0.38, hue(10, 80, 70)) + stop(0.8, hue(18, 90, 78)) + stop(1, hue(10, 60, 54)) +
      '</radialGradient>' +
    '</defs>';
    var wing = WING.replace('class="hw"', 'class="hw" fill="url(#' + hw + ')"')
                   .replace('class="fw"', 'class="fw" fill="url(#' + fw + ')"');
    el.innerHTML =
      '<div class="mbf-o"><div class="mbf-b">' +
        '<svg class="mbf-w mbf-l" viewBox="-13 -11 13 22" focusable="false">' + wing + '</svg>' +
        '<svg class="mbf-w mbf-r" viewBox="0 -11 13 22" focusable="false"><g transform="scale(-1 1)">' + wing + '</g></svg>' +
        '<svg class="mbf-t" viewBox="-13 -11 26 22" focusable="false">' + defs +
          '<path class="an" d="M-0.35 -7.3 Q-1.2 -9.6 -3.1 -10.4 M0.35 -7.3 Q1.2 -9.6 3.1 -10.4"/>' +
          '<g class="bd"><circle cx="-3.1" cy="-10.4" r=".5"/><circle cx="3.1" cy="-10.4" r=".5"/>' +
            '<ellipse cy="2.6" rx=".95" ry="5.6"/><ellipse cy="-3.4" rx="1.35" ry="2.3"/><circle cy="-6.3" r="1.05"/></g>' +
        '</svg>' +
      '</div></div>';
    if (!sky) {
      sky = document.createElement("div");
      sky.className = "mb-sky";
      sky.setAttribute("aria-hidden", "true");
      document.body.appendChild(sky);
    }
    sky.appendChild(el);
    var b = { el: el, rot: el.firstChild, x: 0, y: 0, a: 0, card: null, hops: 0, timer: null, anims: null, gone: false };
    el.addEventListener("pointerdown", function () { if (b.card && fly === b) bolt(); });
    return b;
  }

  // Somewhere on a visible card's vine, in its visible part: at least 70px
  // below its top (clear of the crown), clear of its faded-out foot, and clear
  // of the screen's edges (and Glance's phone nav bar at the bottom).
  function perches(not) {
    var out = [], ws = cards(), vh = window.innerHeight;
    for (var i = 0; i < ws.length; i++) {
      if (ws[i] === not) continue;
      var r = ws[i].getBoundingClientRect();
      if (!r.width) continue;
      var lo = Math.max(r.top + 70, 60), hi = Math.min(r.bottom - 54, vh - 90);
      if (hi - lo >= 20) out.push({ el: ws[i], r: r, lo: lo, hi: hi });
    }
    return out;
  }
  function spot(p) {
    var sx = window.scrollX, sy = window.scrollY;
    // The vine rail's middle: 4 + 36/2 px into the card (1 + 36/2 on a phone).
    return {
      card: p.el,
      x: p.r.left + sx + (window.innerWidth <= 420 ? 19 : 22),
      y: rnd(p.lo, p.hi) + sy,
      top: p.r.top + sy, left: p.r.left + sx
    };
  }

  // A wandering path from where it is to (to.x, to.y): a curve through a
  // random point in view near the middle of the way (within `roam` px, more
  // on a long way), with a butterfly's waver laid along it — two sine waves
  // across the line of flight, faded out at both ends so it leaves and lands
  // exactly. Sampled every ~24px into keyframes (straight runs between sparse
  // keyframes read as a drone, not a butterfly), each facing the way it is
  // going. The page's right and bottom edges are walls — a transform past
  // them would make the page wider or taller — and a landing turns it to face
  // up the vine.
  function route(b, to, roam, landing, flutter) {
    var de = document.documentElement;
    var maxX = de.clientWidth - 40, maxY = de.scrollHeight - 40;
    var sx = window.scrollX, sy = window.scrollY, vw = window.innerWidth, vh = window.innerHeight;
    var rx = Math.max(roam, 0.6 * Math.abs(to.x - b.x)), ry = Math.max(roam * 0.8, 0.6 * Math.abs(to.y - b.y));
    var w = {
      x: clamp((b.x + to.x) / 2 + rnd(-rx, rx), sx + 30, sx + vw - 50),
      y: clamp((b.y + to.y) / 2 + rnd(-ry, ry), sy + 40, sy + vh - 100)
    };
    // The control point that makes the curve pass through w at its middle.
    var cx = 2 * w.x - (b.x + to.x) / 2, cy = 2 * w.y - (b.y + to.y) / 2;
    var len = Math.sqrt((w.x - b.x) * (w.x - b.x) + (w.y - b.y) * (w.y - b.y)) +
              Math.sqrt((to.x - w.x) * (to.x - w.x) + (to.y - w.y) * (to.y - w.y));
    var f = flutter || 1;
    var k1 = rnd(80, 130), k2 = rnd(26, 40), a1 = rnd(7, 13) * f, a2 = rnd(2, 4) * f;
    var p1 = rnd(0, 6.28), p2 = rnd(0, 6.28);
    var steps = clamp(Math.round(len / 24), 12, 40), pts = [];
    for (var i = 0; i <= steps; i++) {
      var t = i / steps, u = 1 - t;
      // Where the curve is, and which way it is heading there.
      var x = u * u * b.x + 2 * u * t * cx + t * t * to.x;
      var y = u * u * b.y + 2 * u * t * cy + t * t * to.y;
      var dx = 2 * u * (cx - b.x) + 2 * t * (to.x - cx), dy = 2 * u * (cy - b.y) + 2 * t * (to.y - cy);
      var dl = Math.sqrt(dx * dx + dy * dy) || 1, s = t * len;
      var off = (a1 * Math.sin(6.28 * s / k1 + p1) + a2 * Math.sin(6.28 * s / k2 + p2)) * Math.sin(Math.PI * t);
      pts.push({ x: Math.min(maxX, x - dy / dl * off), y: Math.min(maxY, y + dx / dl * off) });
    }
    // Headings: along the path (its head is "up" in the drawing, hence +90),
    // with a little yaw, unwrapped so it never spins the long way round.
    // Coming in to land it swings round to its resting heading over the last
    // few keyframes, rather than snapping round at the very end.
    var a = b.a, rest = rnd(-22, 22);
    function turn(from, toward) { return ((toward - from) % 360 + 540) % 360 - 180; }
    pts.forEach(function (p, i) {
      if (i === 0) { p.a = a; return; }
      var q = pts[Math.max(0, i - 2)], r = pts[Math.min(steps, i + 2)];
      var want = Math.atan2(r.y - q.y, r.x - q.x) * 180 / Math.PI + 90 + rnd(-7, 7);
      if (landing && i > steps - 4) want += turn(want, rest) * (i - steps + 4) / 4;
      a += turn(a, want);
      p.a = a;
    });
    return { pts: pts, len: len };
  }

  function flight(b, path, ms, easing, done) {
    var kt = [], kr = [];
    path.pts.forEach(function (p) {
      kt.push({ transform: "translate(" + px(p.x - W / 2) + "px, " + px(p.y - H / 2) + "px)" });
      kr.push({ transform: "rotate(" + px(p.a) + "deg)" });
    });
    var opt = { duration: ms, easing: easing, fill: "forwards" };
    var end = path.pts[path.pts.length - 1];
    b.anims = [animate(b.el, kt, opt), animate(b.rot, kr, opt)];
    b.anims[0].onfinish = function () {
      if (b.gone) return;
      // Keep the final pose as plain style and drop the animations, rather
      // than piling up filled ones flight after flight.
      b.el.style.transform = kt[kt.length - 1].transform;
      b.rot.style.transform = kr[kr.length - 1].transform;
      b.anims.forEach(function (a) { a.cancel(); });
      b.anims = null;
      b.x = end.x; b.y = end.y; b.a = end.a;
      done();
    };
  }

  // ~95 px/s along the way, never quicker than 2.4 s or slower than 9.
  function pace(len) { return clamp(len / 95 * 1000, 2400, 9000); }

  function visit(b, p) {
    var to = spot(p), path = route(b, to, 240, true);
    b.card = null;
    b.el.classList.remove("rest");
    flight(b, path, pace(path.len), "cubic-bezier(.35, .1, .45, 1)", function () { land(b, to); });
  }

  // Is the vine it is making for (or sitting on) still where it was? Not if
  // the card is hidden (a column swap on a phone) or has moved (content above
  // it changed size) — then it would be sitting on thin air.
  function onVine(to) {
    var r = to.card.getBoundingClientRect();
    return r.width > 0 && Math.abs(r.top + window.scrollY - to.top) <= 6 &&
      Math.abs(r.left + window.scrollX - to.left) <= 6;
  }

  function land(b, to) {
    if (!onVine(to)) return leave(b);   // gone from under it on the way in
    b.card = to.card;
    b.el.classList.add("rest");
    var until = Date.now() + rnd(9000, 22000);
    b.timer = setInterval(function () {
      if (!onVine(to)) return leave(b);   // startled: off it goes
      if (Date.now() < until || document.hidden) return;
      var next = b.hops < 2 && Math.random() < 0.5 ? perches(b.card) : [];
      clearInterval(b.timer);
      if (next.length) { b.hops++; visit(b, pick(next)); }
      else leave(b);
    }, 1500);
  }

  // Off up and to the left — the edges it may cross (see the header).
  function leave(b, fast) {
    clearInterval(b.timer);
    b.card = null;
    b.el.classList.remove("rest");
    if (fast) b.el.classList.add("bolt");
    var sy = window.scrollY;
    var to = { x: b.x - rnd(60, 220), y: sy - rnd(50, 110) };
    var path = route(b, to, fast ? 60 : 160, false, fast ? 1.7 : 1);
    var ms = fast ? clamp(path.len / 420 * 1000, 900, 1800) : pace(path.len);
    flight(b, path, ms, fast ? "cubic-bezier(.2, .55, .45, 1)" : "cubic-bezier(.5, 0, .75, 1)", function () {
      gone(b);
      later(rnd(25000, 70000));
    });
  }
  function bolt() { if (fly) leave(fly, true); }

  // Take it out at once (and any flight it is on).
  function gone(b) {
    if (!b || b.gone) return;
    b.gone = true;
    clearInterval(b.timer);
    if (b.anims) b.anims.forEach(function (a) { a.cancel(); });
    if (b.el.parentNode) b.el.parentNode.removeChild(b.el);
    if (fly === b) fly = null;
  }

  function later(ms) {
    clearTimeout(nextT);
    nextT = setTimeout(spawn, ms);
  }

  function spawn() {
    nextT = null;
    if (fly || still.matches || !enabled) return;
    if (document.hidden) return later(rnd(8000, 20000));
    var ps = perches(null);
    if (!ps.length) return later(rnd(15000, 30000));
    var b = fly = butterfly(), sx = window.scrollX, sy = window.scrollY;
    // In from just past the left edge, or from above the top one.
    if (Math.random() < 0.55) { b.x = sx - 30; b.y = sy + rnd(0.15, 0.6) * window.innerHeight; b.a = rnd(60, 120); }
    else { b.x = sx + rnd(0.1, 0.75) * window.innerWidth; b.y = sy - 30; b.a = rnd(150, 210); }
    b.el.style.transform = "translate(" + px(b.x - W / 2) + "px, " + px(b.y - H / 2) + "px)";
    b.rot.style.transform = "rotate(" + px(b.a) + "deg)";
    visit(b, pick(ps));
  }

  // ── on / off ───────────────────────────────────────────────────────────────
  // Off takes every living thing off the page at once; the intervals and
  // listeners below stay, but each of them checks `enabled` first.
  function off() {
    if (!enabled) return;
    enabled = false;
    clearTimeout(nextT);
    nextT = null;
    gone(fly);
    clearTimeout(ffOff);
    [".mb-crown", ".mbg-defs", ".mb-sky", ".mb-fireflies"].forEach(function (q) {
      document.querySelectorAll(q).forEach(function (e) { e.remove(); });
    });
    ff = sky = null;
    root.classList.remove("mb-garden");          // the static bloom.svg blossom is back
    root.removeAttribute("data-mb-night");
    root.removeAttribute("data-mb-dark");
  }
  function on() {
    if (enabled) return;
    enabled = true;
    start();
  }
  window.Garden = { on: on, off: off, get enabled() { return enabled; } };

  // ── wiring ─────────────────────────────────────────────────────────────────
  function start() {
    clock();   // before the crowns exist, so a night-time page draws them shut
    Dash.ready(".widget", function () {
      if (!enabled) return;
      crowns();
      dusk();
      if (!still.matches && !fly && !nextT) later(rnd(6000, 15000));
    });
  }
  if (enabled) start();

  document.addEventListener("ha:state", dusk);
  setInterval(function () { clock(); crowns(); }, 60000);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) clock(); });

  // A turned phone or a resized window moves every card: a resting butterfly
  // would be left hanging in the air. (Height alone changes all the time on a
  // phone — the address bar sliding away — and moves nothing sideways.)
  window.addEventListener("resize", function () {
    if (window.innerWidth === lastW) return;
    lastW = window.innerWidth;
    if (fly && fly.card) leave(fly);
  });

  // Reduced motion switched on mid-visit: the butterfly and fireflies go now.
  function onStill() {
    if (!enabled) return;
    if (still.matches) { clearTimeout(nextT); nextT = null; gone(fly); }
    else if (!fly && !nextT && root.classList.contains("mb-garden")) later(rnd(6000, 15000));
    dusk();
  }
  if (still.addEventListener) still.addEventListener("change", onStill);
  else if (still.addListener) still.addListener(onStill);
})();
