// cats.js — what the Cats theme's cats DO, on both dashboards.
//
// theme.js loads this (with cats.css) only when someone picks Cats in the
// colour picker, then calls Cats.on(); picking anything else calls Cats.off(),
// which takes every cat, timer and listener back out. Nobody else ever
// downloads it.
//
// The cats are inline SVG with their parts rigged — ears, eyes, head, legs,
// paws, tail — so cats.css can move the parts:
//   idle      blinking, a sitting cat's tail swishing, a loaf breathing: CSS,
//             always on. And now and then an "act", handed out by one slow
//             ticker to a cat that is on screen: an ear twitch, a head tilt,
//             a yawn, a groom, a tail flick, a look round, kneading, a duck
//             behind the card and a peek back over it, a sleeper's dream.
//   you       tap a cat: it mrrps, or purrs (hearts; a buzz on Android).
//             Tap it three times and it has had enough and hides for a bit.
//             A sleeping cat stirs and mumbles. With a mouse, every cat's
//             eyes follow the pointer and ears perk as it comes close; and a
//             double-click on an empty bit of page turns on a laser pointer —
//             the nearest cat jumps down and chases it (Esc, a double-click,
//             or 20 s of stillness sends it home).
//   the page  every light off: the Lights card's cat curls up asleep, and
//             wakes when a lamp comes on. Something playing: a kitten sits on
//             the progress bar batting at the playhead. Eclipse rebooting or
//             unreachable: the cats scatter, and come back one by one when it
//             is up. Running hot (the Pi's SoC from 70°, Asgard's CPU ring at
//             warn): a cat naps on the warm gauge. A download finishing: a cat
//             trots across the Downloads card with it, like a caught mouse.
//
// It reads the dashboards from the outside — the classes and attributes the
// cards already render (data-ha-state, .ec-orb, .ags-bar, .ags-ring.warn …)
// — so no card script knows the cats exist. Cats only ever go INTO a .widget
// (beside Glance's markup, never inside a Dash.paint target, which would
// morph them away) or the <body>.
//
// Every cat is aria-hidden. Only a cat's painted body takes a tap (a tail
// never does), and a cat sitting over a button or a link takes none at all,
// so it can never eat a tap meant for a light. Reduced motion: no acts, no
// chase, no scattering, no trotting — the cats sit still and still answer a
// tap with a word.
(function () {
  "use strict";
  if (window.Cats) return;

  var root = document.documentElement;
  function mq(q) { return !!(window.matchMedia && matchMedia(q).matches); }
  var REDUCE = mq("(prefers-reduced-motion: reduce)");
  var MOUSE = mq("(hover: hover) and (pointer: fine)");

  var live = false;
  var cats = [];     // perched on the cards: { el, kind, home, widget, vis, busy, away, gone, t }
  var extras = [];   // the kitten on a progress bar, the nappers on hot gauges
  var naps = {};     // "ring" / "soc" -> the cat napping there
  var seen = {};     // the dashboard as last seen, to act on a CHANGE, not on load
  var obs = null, io = null, ticker = 0, slow = 0, checkT = 0, laser = null;

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function pick(a) { return a[Math.floor(Math.random() * a.length)]; }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function shown(el) { var r = el && el.getBoundingClientRect(); return !!r && r.width > 0 && r.height > 0; }
  // A timer that belongs to a cat, so Cats.off() can cancel everything.
  function later(c, fn, ms) {
    var id = setTimeout(function () {
      c.t = c.t.filter(function (x) { return x !== id; });
      if (live) fn();
    }, ms);
    c.t.push(id);
    return id;
  }

  // ── the drawings ─────────────────────────────────────────────────────────────
  // Every moving part is drawn round 0,0 inside <g transform="translate(pivot)">:
  // an SVG element turns and scales about 0,0, so a CSS transform on the part
  // turns an ear about its base, a tail about the rump, a leg about the
  // shoulder. A right-hand part is the left one under scale(-1 1), so one
  // keyframe moves both, each the right way.
  function at(x, y, cls, inner, sx, sy) {
    return '<g transform="translate(' + x + ' ' + y + ')' + (sx ? ' scale(' + sx + ' ' + (sy || sx) + ')' : '') + '">' +
      '<g class="' + cls + '">' + inner + '</g></g>';
  }
  var EAR = '<path class="f" d="M-3.6 3.4L-1.6-12L6.4-2.8Z"/><path class="in" d="M-2 1.4L-1-8L4-2.4Z"/>';
  function ears(lx, rx, y, k) { return at(lx, y, "ear el", EAR, k, k) + at(rx, y, "ear er", EAR, -k, k); }
  // The iris stays put; .look slides the pupil across it (the eyes following
  // the pointer, a look round), .eye-i squashes for a blink, and the two lids
  // are the closed eyes: asleep (◡) and happy (^).
  function eye(x, y, r) {
    function p(v) { return (v * r).toFixed(2); }
    return at(x, y, "eye",
      '<g class="eye-i"><ellipse class="iris" rx="' + r + '" ry="' + p(1.12) + '"/>' +
        '<g class="look"><ellipse class="pupil" rx="' + p(0.4) + '" ry="' + p(0.9) + '"/>' +
        '<circle class="glint" cx="' + p(-0.34) + '" cy="' + p(-0.42) + '" r="' + p(0.28) + '"/></g></g>' +
      '<path class="lid lid-s" d="M' + p(-1) + ' ' + p(0.1) + 'Q0 ' + p(0.85) + ' ' + p(1) + ' ' + p(0.1) + '"/>' +
      '<path class="lid lid-h" d="M' + p(-1) + ' ' + p(0.45) + 'Q0 ' + p(-0.75) + ' ' + p(1) + ' ' + p(0.45) + '"/>');
  }
  // Nose, mouth (and the yawn behind it), whiskers and a blush, round the nose.
  function face(x, y, k) {
    return '<g transform="translate(' + x + ' ' + y + ') scale(' + k + ')">' +
      '<path class="wh" d="M-6.5.8L-16-1M-6.5 2.4L-15.5 4M6.5.8L16-1M6.5 2.4L15.5 4"/>' +
      '<ellipse class="blush" cx="-8.6" cy="1.4" rx="2.3" ry="1.3"/><ellipse class="blush" cx="8.6" cy="1.4" rx="2.3" ry="1.3"/>' +
      at(0, 3.6, "yawn", '<ellipse class="mo" rx="2.5" ry="2.8"/><ellipse class="tongue" cy="1.5" rx="1.5" ry="1"/>') +
      '<path class="mouth" d="M0 1Q-1.4 2.9-3 2.1M0 1Q1.4 2.9 3 2.1"/>' +
      '<path class="nose" d="M-1.7-.7H1.7L0 1.1Z"/></g>';
  }
  function stripes(x, y, k) {
    return '<path class="st" transform="translate(' + x + ' ' + y + ') scale(' + k + ')" d="M-3.2 0l.6 3.8M0-.6v4.2M3.2 0l-.6 3.8"/>';
  }
  var PAW = '<ellipse class="f" rx="6" ry="4.2"/><path class="toe" d="M-2.2 1.4v2.2M0 1.8v2.2M2.2 1.4v2.2"/>';
  var PAW_S = '<ellipse class="f" rx="4.6" ry="2.9"/><path class="toe" d="M-1.6 1v1.6M0 1.3v1.6M1.6 1v1.6"/>';
  var LEG = '<rect class="f" x="-2.7" y="0" width="5.4" height="14.6" rx="2.7"/><path class="toe" d="M-1.1 12.4v2M1.1 12.4v2"/>';

  var DRAW = {
    // Head and paws over the card's top edge (y 46), the rest of it behind
    // the card: the head is clipped at the edge, so it can duck out of sight.
    peek: function () {
      return '<svg viewBox="0 0 64 52" aria-hidden="true"><g clip-path="url(#cat-clip-peek)">' +
        at(32, 46, "head", '<g transform="translate(-32 -46)">' +
          ears(19.5, 44.5, 27.5, 1.3) +
          '<path class="f" d="M9 46C9 34 15 24.5 32 24C49 24.5 55 34 55 46Z"/>' +
          '<path class="lt" d="M23.5 46C24 42.6 27.6 41 32 41C36.4 41 40 42.6 40.5 46Z"/>' +
          stripes(32, 26.4, 1) + eye(24.5, 35, 3.2) + eye(39.5, 35, 3.2) + face(32, 40, 1) + '</g>') +
        '</g>' + at(20.5, 46.5, "paw pw-l", PAW) + at(43.5, 46.5, "paw pw-r", PAW, -1, 1) + '</svg>';
    },
    // Sitting on the edge (y 60), tail hanging down the front of the card.
    // The right foreleg comes after the head, so a groom draws it in front.
    sit: function () {
      return '<svg viewBox="0 0 48 92" aria-hidden="true">' +
        at(33, 56, "tail", '<path class="tl" d="M0 0C7 2 9.5 10 7 17.5C5.2 23 6.4 28.5 10.5 31"/>') +
        '<path class="f" d="M10.5 60C7.5 48.5 11 38.5 24 33.5C37 38.5 40.5 48.5 37.5 60Z"/>' +
        '<path class="lt" d="M19 39.5C21 44 27 44 29 39.5C28.6 47.5 19.4 47.5 19 39.5Z"/>' +
        at(19.5, 46, "leg lg-l", LEG) +
        at(24, 36, "head", '<g transform="translate(-24 -36)">' +
          ears(16.8, 31.2, 18, 1) +
          '<ellipse class="f" cx="24" cy="24.6" rx="12.4" ry="10.8"/>' +
          '<path class="lt" d="M18.6 31.8C19.4 28.8 21.6 27.6 24 27.6C26.4 27.6 28.6 28.8 29.4 31.8C27.8 34.6 20.2 34.6 18.6 31.8Z"/>' +
          stripes(24, 14.6, 0.8) + eye(19.3, 24.4, 2.6) + eye(28.7, 24.4, 2.6) + face(24, 28.4, 0.78) + '</g>') +
        at(28.5, 46, "leg lg-r", LEG) + '</svg>';
    },
    // A loaf on the edge (y 46), asleep unless .awake, tail curled round the
    // front paws.
    loaf: function () {
      return '<svg viewBox="0 0 76 46" aria-hidden="true">' +
        at(38, 46, "breathe", '<path class="f" transform="translate(-38 -46)" d="M5 46C5 33 14 24 38 24C62 24 71 33 71 46Z"/>') +
        at(38, 40, "head", '<g transform="translate(-38 -40)">' +
          ears(29.6, 46.4, 25.6, 0.95) +
          '<ellipse class="f" cx="38" cy="33" rx="13.5" ry="10.5"/>' +
          '<path class="lt" d="M32 40.6C32.6 37.8 35 36.6 38 36.6C41 36.6 43.4 37.8 44 40.6C42 43 34 43 32 40.6Z"/>' +
          stripes(38, 23.4, 0.85) + eye(32.6, 33.2, 2.7) + eye(43.4, 33.2, 2.7) + face(38, 37.2, 0.8) + '</g>') +
        at(30.5, 44.4, "paw pw-l", PAW_S) + at(45.5, 44.4, "paw pw-r", PAW_S, -1, 1) +
        at(66, 42, "tail", '<path class="tl dk" d="M0 0C-5 4-16 4.8-22 4"/>' +
          at(-22, 4, "tip", '<path class="tl dk" d="M0 0C-4-.3-8-1.4-9.6-4.2"/>')) + '</svg>';
    }
  };
  // The mouse a cat carries off when a download finishes.
  var MOUSE_SVG = '<svg class="cat-mouse" viewBox="-9 -3 32 15" aria-hidden="true">' +
    '<path d="M1 7C-2.6 6.4-4.6 9.6-8 9" fill="none" stroke="#6a574b" stroke-width="1.1" stroke-linecap="round"/>' +
    '<path d="M1 8C1 4 5 1.6 10 1.6C15 1.6 19 4.6 20.6 8Z" fill="#7d6a5c"/>' +
    '<circle cx="14.4" cy="2.4" r="2.8" fill="#9b8676"/><circle cx="14.4" cy="2.4" r="1.5" fill="#f4a7c0"/>' +
    '<circle cx="18" cy="5.4" r=".85" fill="#1d1410"/><circle cx="20.6" cy="7.4" r=".8" fill="#f4a7c0"/></svg>';
  var DEFS = '<svg class="cat-defs" width="0" height="0" aria-hidden="true" focusable="false"><defs>' +
    '<clipPath id="cat-clip-peek"><rect width="64" height="46"/></clipPath></defs></svg>';

  function make(kind, cls) {
    var c = { kind: kind, home: kind, away: {}, t: [], busy: "", vis: false };
    var el = c.el = document.createElement("span");
    el.className = "cat cat-" + kind + (cls ? " " + cls : "");
    el.setAttribute("aria-hidden", "true");
    el.style.setProperty("--bl", rnd(3.6, 7.4).toFixed(2) + "s");     // its own blink rhythm
    el.style.setProperty("--bd", (-rnd(0, 7)).toFixed(2) + "s");
    el.style.setProperty("--sw", rnd(3, 4.8).toFixed(2) + "s");       // and tail rhythm
    el._cat = c;
    draw(c);
    return c;
  }
  function draw(c) {
    c.el.innerHTML = DRAW[c.kind]() + (c.kind === "loaf" ? '<b class="cat-z"><i>z</i><i>z</i><i>Z</i></b>' : "");
  }
  function setKind(c, kind) {
    if (c.kind === kind) return;
    c.el.classList.remove("cat-" + c.kind);
    c.el.classList.add("cat-" + kind);
    c.kind = kind;
    draw(c);
    c.el.classList.remove("back");
    void c.el.offsetWidth;
    c.el.classList.add("back");
    later(c, function () { c.el.classList.remove("back"); }, 900);
  }
  function coat() { return pick(["", "coat1", "coat2", "coat3"]); }

  // ── on the cards ─────────────────────────────────────────────────────────────
  // One cat per card (a group's tabs are .widgets too — skipped), alternating
  // which cat, which side and which coat; a stroller and the paw prints once
  // per page. Glance adds the cards after load, so the observer calls this
  // again as they arrive.
  var KINDS = ["peek", "sit", "loaf"];
  function decorate() {
    if (!live || !document.body) return;
    if (!document.querySelector(".cat-defs")) document.body.insertAdjacentHTML("beforeend", DEFS);
    cats = cats.filter(function (c) { return c.el.isConnected; });
    var n = 0;
    document.querySelectorAll(".widget").forEach(function (w) {
      if (w.parentElement && w.parentElement.closest(".widget")) return;
      if (!w.querySelector(":scope > .cat-perch")) {
        var c = make(KINDS[n % 3], "cat-perch" + (n % 2 ? " right" : "") + (n % 4 ? " coat" + (n % 4) : ""));
        c.widget = w;
        c.perch = true;
        w.appendChild(c.el);
        cats.push(c);
        if (io) io.observe(c.el);
      }
      n++;
    });
    ["cat-walk", "cat-paws"].forEach(function (k) {
      if (document.querySelector("." + k)) return;
      var e = document.createElement("i");
      e.className = k;
      e.setAttribute("aria-hidden", "true");
      document.body.appendChild(e);
    });
    floor();
    soon();
  }
  // The stroller walks along the bottom of the SCREEN — on a phone, just above
  // Glance's bottom bar. The bar (its icons row) only: the rest of
  // .mobile-navigation is the ☰ panel, parked off-screen below it.
  function floor() {
    var nav = document.querySelector(".mobile-navigation"), bar = document.querySelector(".mobile-navigation-icons");
    var h = nav && bar && getComputedStyle(nav).display !== "none" ? bar.getBoundingClientRect().height : 0;
    root.style.setProperty("--cat-floor", Math.round(h + 4) + "px");
  }
  // A perched cat overlaps the card above it, and sometimes that card's
  // buttons: such a cat takes no taps (.tap is off), so the button still
  // gets them. Only the part above its own card's edge counts — that is
  // where every tappable bit of a cat is.
  var CTL = "button, a[href], input, select, textarea, summary, label, [data-ha-toggle], [role='button']";
  function layout() {
    var boxes = [];
    document.querySelectorAll(CTL).forEach(function (b) {
      if (b.closest(".cat")) return;
      var r = b.getBoundingClientRect();
      if (r.width && r.height) boxes.push(r);
    });
    cats.forEach(function (c) {
      if (!c.el.isConnected) return;
      var r = c.el.getBoundingClientRect(), edge = c.widget.getBoundingClientRect().top + 7;
      var b = { l: r.left + 2, r: r.right - 2, t: r.top + 2, b: Math.min(r.bottom, edge) - 2 };
      var clear = r.width > 0 && !boxes.some(function (x) { return x.left < b.r && x.right > b.l && x.top < b.b && x.bottom > b.t; });
      c.el.classList.toggle("tap", clear);
    });
  }

  // ── idle life ────────────────────────────────────────────────────────────────
  // An act is a class on the cat for as long as its animation runs
  // (cats.css). "twitch" is listed twice: the small things happen most.
  var ACTS = {
    peek: [["twitch", 600], ["twitch", 600], ["tilt", 2600], ["yawn", 2600], ["duck", 4600], ["knead", 2600], ["look", 3000]],
    sit: [["twitch", 600], ["twitch", 600], ["flick", 700], ["tilt", 2600], ["yawn", 2600], ["groom", 5600], ["look", 3000]],
    loaf: [["twitch", 600], ["twitch", 600], ["flick", 700], ["stir", 3200], ["dream", 1500]]
  };
  function act(c, name, ms) {
    if (c.busy || c.gone) return false;
    var cls = "a-" + (name === "twitch" ? (Math.random() < 0.5 ? "twitchL" : "twitchR") : name);
    c.busy = name;
    c.el.classList.add(cls);
    later(c, function () {
      c.el.classList.remove(cls);
      if (c.busy === name) c.busy = "";
    }, ms);
    return true;
  }
  // One ticker for the lot, and only for cats on screen in a shown tab.
  function idle() {
    if (document.hidden) return;
    var free = cats.concat(extras).filter(function (c) { return c.vis && !c.busy && !c.gone; });
    if (!free.length || Math.random() < 0.3) return;
    var c = pick(free), a = pick(c.acts || ACTS[c.kind]);
    act(c, a[0], a[1]);
  }

  // ── you ──────────────────────────────────────────────────────────────────────
  function say(c, text, ms) {
    var b = document.createElement("b");
    b.className = "cat-say";
    b.textContent = text;
    b.style.setProperty("--say", (ms || 1800) + "ms");
    // Too near the top of the screen for a bubble overhead: say it to the side.
    if (c.el.getBoundingClientRect().top < 30) b.classList.add("side");
    c.el.appendChild(b);
    later(c, function () { b.remove(); }, ms || 1800);
  }
  function flash(c, cls, ms) {
    c.el.classList.add(cls);
    later(c, function () { c.el.classList.remove(cls); }, ms);
  }
  function hearts(c, n) {
    for (var i = 0; i < n; i++) {
      var h = document.createElement("b");
      h.className = "cat-heart";
      h.textContent = "♥";
      h.style.left = rnd(25, 65).toFixed(0) + "%";
      h.style.setProperty("--hx", rnd(-14, 14).toFixed(0) + "px");
      h.style.animationDelay = (i * 0.28) + "s";
      c.el.appendChild(h);
      (function (h) { later(c, function () { h.remove(); }, 2400 + i * 280); })(h);
    }
  }
  function onTap(e) {
    var el = e.target && e.target.closest ? e.target.closest(".cat") : null;
    if (!el || !el._cat) return;
    e.preventDefault();
    e.stopPropagation();
    react(el._cat);
  }
  function react(c) {
    var now = Date.now();
    c.taps = (c.taps || []).filter(function (t) { return now - t < 5000; });
    c.taps.push(now);
    if (c.kind === "loaf" && !c.el.classList.contains("awake")) return stir(c);
    if (c.taps.length >= 3 && c.perch) { c.taps = []; return flee(c); }
    if (Math.random() < 0.5) {
      say(c, pick(["mrrp?", "mew!", "mrrrp", "meow", "prrt?", "mrow"]));
      flash(c, "happy", 1500);
      act(c, "tilt", 2600);
    } else {
      say(c, "prrrr…", 2400);
      flash(c, "happy", 2400);
      flash(c, "purr", 2400);
      if (!REDUCE) hearts(c, 3);
      try { if (navigator.vibrate) navigator.vibrate([10, 50, 10, 50, 10, 50, 10]); } catch (x) { /* not allowed here */ }
    }
  }
  // A sleeper opens its eyes, mumbles, and nods off again.
  function stir(c) {
    say(c, pick(c.hot ? ["so warm…", "warm spot. mine.", "prrr… cosy"]
                : c.lightsOff ? ["…lights off", "zz… five more minutes", "mrrf"]
                : ["mrrf?", "…mew?", "five more minutes"]), 2000);
    flash(c, "awake", 3600);
    act(c, "stir", 3200);
  }
  // Had enough: a peeking cat ducks behind its card, anyone else jumps off.
  function flee(c) {
    say(c, pick(["eep!", "hmph!", "nope"]), 1000);
    if (c.kind === "peek") {
      c.busy = "hide";
      later(c, function () { c.el.classList.add("ducked"); }, 350);
      later(c, function () {
        c.el.classList.add("rise");
        c.el.classList.remove("ducked");
        later(c, function () { c.el.classList.remove("rise"); if (c.busy === "hide") c.busy = ""; }, 1800);
      }, rnd(12000, 22000));
    } else {
      later(c, function () { jump(c); away(c, "tap", true); }, 350);
      later(c, function () { away(c, "tap", false); }, rnd(12000, 22000));
    }
  }
  function jump(c) {
    var s = Math.random() < 0.5 ? -1 : 1;
    c.el.style.setProperty("--jx", (s * rnd(60, 140)).toFixed(0) + "px");
    c.el.style.setProperty("--jr", (s * rnd(8, 24)).toFixed(0) + "deg");
  }
  // A cat can be away for several reasons at once (tapped too much, Eclipse
  // down, chasing the laser): it comes back when the last one clears.
  function away(c, why, gone) {
    if (gone) c.away[why] = 1; else delete c.away[why];
    var a = Object.keys(c.away).length > 0;
    if (a === !!c.gone) return;
    c.gone = a;
    c.el.classList.remove("back");
    c.el.classList.toggle("away", a);
    if (!a) {
      void c.el.offsetWidth;
      c.el.classList.add("back");
      later(c, function () { c.el.classList.remove("back"); }, 900);
    }
  }

  // Eyes on the pointer: every cat on screen looks at it, and ears perk when
  // it comes close. Read every rect first, then write, so it is one layout.
  var px = 0, py = 0, lookQ = false;
  function onMove(e) {
    px = e.clientX; py = e.clientY;
    if (laser) {
      laser.x = px; laser.y = py; laser.moved = performance.now();
      laser.dot.style.transform = "translate(" + px + "px," + py + "px)";
    }
    if (!lookQ) { lookQ = true; requestAnimationFrame(look); }
  }
  function look() {
    lookQ = false;
    var list = cats.filter(function (c) { return c.vis && !c.gone; });
    var rs = list.map(function (c) { return c.el.getBoundingClientRect(); });
    list.forEach(function (c, i) {
      var r = rs[i], dx = px - (r.left + r.width / 2), dy = py - (r.top + r.height * 0.45), d = Math.hypot(dx, dy) || 1;
      if (c.kind === "loaf" && !c.el.classList.contains("awake")) {
        if (d < 90 && Math.random() < 0.06) act(c, "twitch", 600);     // a sleeper's ear hears you
        return;
      }
      var k = d > 900 ? 0 : 1.2 / d;
      c.el.style.setProperty("--lx", (dx * k).toFixed(2));
      c.el.style.setProperty("--ly", (dy * k * 0.8).toFixed(2));
      c.el.classList.toggle("perk", d < 160);
    });
  }
  function onLeave() {
    cats.forEach(function (c) {
      c.el.style.removeProperty("--lx");
      c.el.style.removeProperty("--ly");
      c.el.classList.remove("perk");
    });
    if (laser) home();
  }

  // The laser pointer. A double-click on the page itself (not a card, not a
  // control) starts it; the nearest cat jumps off its perch and a runner —
  // the stroller's two-frame sprite, in that cat's coat — chases the dot
  // until it catches it (a pounce), and again whenever it moves off.
  function onDbl(e) {
    if (laser) { home(); return; }
    var t = e.target;
    if (t && t.closest && t.closest(".widget, a, button, input, select, textarea, label, .hud-pop, .hud-pick, .header, .mobile-navigation")) return;
    try { getSelection().removeAllRanges(); } catch (x) { /* nothing selected */ }
    chase(e.clientX, e.clientY);
  }
  function onKey(e) { if (e.key === "Escape" && laser) home(); }
  function chase(x, y) {
    var c = null, best = Infinity;
    cats.forEach(function (k) {
      if (!k.vis || k.gone || k.busy === "hide") return;
      var r = k.el.getBoundingClientRect(), d = Math.hypot(r.left + r.width / 2 - x, r.bottom - y);
      if (d < best) { best = d; c = k; }
    });
    var r = c ? c.el.getBoundingClientRect() : { left: -90, width: 0, bottom: innerHeight - 10 };
    var dot = document.createElement("i"), run = document.createElement("i");
    dot.className = "cat-laser";
    run.className = "cat-runner " + (c ? (c.el.className.match(/coat\d/) || [""])[0] : "");
    run.innerHTML = "<b></b>";
    dot.style.transform = "translate(" + x + "px," + y + "px)";
    document.body.appendChild(dot);
    document.body.appendChild(run);
    if (c) { jump(c); away(c, "laser", true); }
    root.classList.add("cat-lasering");
    var now = performance.now();
    laser = { dot: dot, run: run, cat: c, x: x, y: y, rx: r.left + r.width / 2, ry: r.bottom, v: 0, face: 1, last: now, moved: now, homing: false, caught: false };
    laser.raf = requestAnimationFrame(step);
  }
  function step(t) {
    var L = laser;
    if (!L) return;
    var dt = Math.min(0.05, (t - L.last) / 1000), tx, ty;
    L.last = t;
    if (L.homing) {                                   // back to its own card
      var r = L.cat && L.cat.el.isConnected ? L.cat.el.getBoundingClientRect() : null;
      tx = clamp(r ? r.left + r.width / 2 : -120, -120, innerWidth + 120);
      ty = clamp(r ? r.bottom : L.ry, -60, innerHeight + 60);
    } else {
      if (Math.abs(L.x - L.rx) > 22) L.face = L.x < L.rx ? -1 : 1;
      tx = L.x - 30 * L.face;                         // front paws on the dot
      ty = L.y + 8;
    }
    var dx = tx - L.rx, dy = ty - L.ry, d = Math.hypot(dx, dy);
    if (d > 4) {
      L.v = Math.min(L.homing ? 420 : 620, L.v + 1600 * dt);
      var s = Math.min(d, L.v * dt);
      L.rx += dx / d * s;
      L.ry += dy / d * s;
      if (L.homing && Math.abs(dx) > 6) L.face = dx < 0 ? -1 : 1;
      if (d > 40) L.caught = false;
    } else {
      L.v = 0;
      if (L.homing) { done(); return; }
      if (!L.caught) {
        L.caught = true;
        L.run.classList.remove("pounce");
        void L.run.offsetWidth;
        L.run.classList.add("pounce");
      }
    }
    L.run.classList.toggle("run", d > 10);
    L.run.style.transform = "translate(" + (L.rx - 40).toFixed(1) + "px," + (L.ry - 46).toFixed(1) + "px) scaleX(" + L.face + ")";
    if (!L.homing && t - L.moved > 20000) home();
    L.raf = requestAnimationFrame(step);
  }
  function home() {
    if (!laser || laser.homing) return;
    laser.homing = true;
    laser.dot.remove();
    root.classList.remove("cat-lasering");
  }
  function done() {
    var L = laser;
    laser = null;
    cancelAnimationFrame(L.raf);
    L.dot.remove();
    L.run.remove();
    root.classList.remove("cat-lasering");
    if (L.cat) away(L.cat, "laser", false);
  }

  // ── the dashboard ────────────────────────────────────────────────────────────
  function soon() { clearTimeout(checkT); checkT = setTimeout(check, 350); }
  function check() {
    if (!live) return;
    lights(); eclipse(); downloads(); tv(); hot();
  }
  function perchOf(w) {
    for (var i = 0; i < cats.length; i++) if (cats[i].widget === w) return cats[i];
    return null;
  }
  // Every light off (the all-lights switch reads "off"): the Lights card's cat
  // curls up asleep. A lamp on: it wakes, stretches, and is back to its old
  // self — never a loaf while the lights are on, since a loaf is a sleeper.
  function lights() {
    var hero = document.querySelector(".mb-hero[data-ha-state], .ag-hero[data-ha-state]");
    var c = hero && perchOf(hero.closest(".widget"));
    if (!c) return;
    var st = hero.getAttribute("data-ha-state");
    if (st !== "on" && st !== "off") return;            // unknown / offline: leave the cat be
    var off = st === "off";
    if (off === c.lightsOff) return;
    var first = c.lightsOff === undefined;
    c.lightsOff = off;
    var awakeKind = c.home === "loaf" ? "sit" : c.home;
    if (first) { setKind(c, off ? "loaf" : awakeKind); return; }
    if (off) {
      if (c.vis) say(c, pick(["night night", "…zz", "*yawn*"]), 1500);
      act(c, "yawn", 2600);
      later(c, function () { if (c.lightsOff) setKind(c, "loaf"); }, 1500);
    } else {
      if (c.kind === "loaf") {
        c.el.classList.add("awake");
        if (c.vis) say(c, pick(["!", "mrrp!", "oh! light!"]), 1500);
        c.busy = "";
        act(c, "stir", 2400);
      }
      later(c, function () {
        if (c.lightsOff) return;
        c.el.classList.remove("awake");
        setKind(c, awakeKind);
      }, 2400);
    }
  }
  // Eclipse rebooting or out of reach: every cat scatters; back up: they
  // come home one at a time. Only on a change seen here, not as first found.
  function eclipse() {
    var m = document.getElementById("ec-main");
    if (!m) return;
    var st = m.querySelector(".ec-orb.bad") || m.querySelector('[data-act="reboot"].busy') ? "down"
           : m.querySelector(".ec-orb.ok") ? "up" : "";
    if (!st || st === seen.ec) return;
    var was = seen.ec;
    seen.ec = st;
    if (was) scatter(st === "down");
  }
  function scatter(go) {
    cats.filter(function (c) { return c.el.isConnected; }).forEach(function (c, i) {
      if (go) {
        if (REDUCE) { away(c, "eclipse", true); return; }
        c.el.classList.add("startle");
        if (c.vis && i % 2 === 0) say(c, "!", 800);
        later(c, function () { c.el.classList.remove("startle"); jump(c); away(c, "eclipse", true); }, 420 + i * 70);
      } else {
        later(c, function () { away(c, "eclipse", false); }, 600 + i * 380);
      }
    });
  }
  // A name at the top of the Downloads card's "Recent" list that this page has
  // never shown = a download just finished: a cat trots across the card with
  // it. Everything listed when the card first fills is old news, and so is a
  // name coming back after a redraw — only a NEW one gets a cat.
  function downloads() {
    var lis = document.querySelectorAll("#ags-dl .dl-recent li");
    if (!lis.length) return;
    var names = [].map.call(lis, function (li) { var s = li.querySelector("span[title]"); return s ? s.getAttribute("title") : ""; });
    var first = !seen.dl;
    seen.dl = seen.dl || {};
    var top = names[0], fresh = !first && top && !seen.dl[top];
    names.forEach(function (n) { if (n) seen.dl[n] = 1; });
    if (fresh && !lis[0].classList.contains("bad")) carry(lis[0].closest(".widget"), lis[0]);
  }
  function carry(w, li) {
    if (!w || REDUCE || document.hidden || !shown(li)) return;
    var wr = w.getBoundingClientRect(), lr = li.getBoundingClientRect();
    var el = document.createElement("i");
    el.className = "cat-carry " + coat();
    el.setAttribute("aria-hidden", "true");
    el.innerHTML = "<span><b></b>" + MOUSE_SVG + "</span>";
    el.style.top = Math.round(lr.top - wr.top - 46) + "px";
    el.style.setProperty("--from", Math.round(wr.width - 90) + "px");   // starts inside: never widens the page
    w.appendChild(el);
    setTimeout(function () { el.remove(); }, 6600);
  }
  function extra(c, w) {
    c.widget = w;
    w.appendChild(c.el);
    extras.push(c);
    if (io) io.observe(c.el);
    return c;
  }
  function drop(c) {
    c.t.forEach(clearTimeout);
    c.t = [];
    c.el.remove();
    extras = extras.filter(function (x) { return x !== c; });
  }
  // Something playing (On the TV, Asgard's Now Playing): a kitten sits on the
  // first progress bar with a paw on the playhead, batting at it while it
  // plays, just watching while it's paused.
  function tv() {
    document.querySelectorAll("#ec-tv, #ags-playing").forEach(function (box) {
      var w = box.closest(".widget");
      if (!w) return;
      var play = box.querySelector(".ags-play"), bar = play && play.querySelector(".ags-bar"), fill = bar && bar.querySelector("i");
      var k = w._catBat;
      if (!fill || !shown(bar)) {
        if (k) { drop(k); w._catBat = null; }
        return;
      }
      if (!k) {
        k = w._catBat = extra(make("peek", "cat-batter tap coat2"), w);
        k.acts = [["twitch", 600], ["twitch", 600], ["yawn", 2600]];
      }
      var wr = w.getBoundingClientRect(), br = bar.getBoundingClientRect(), fr = fill.getBoundingClientRect();
      // Its left paw (11.5 px in) on the end of the fill, its edge on the bar.
      k.el.style.left = Math.round(clamp(fr.right, br.left + 6, br.right - 26) - wr.left - 11.5) + "px";
      k.el.style.top = Math.round(br.top - wr.top - 26) + "px";
      k.el.classList.toggle("batting", !play.classList.contains("paused"));
    });
  }
  // Running warm (the same thresholds the cards colour at): a cat naps on top
  // of the gauge, heat shimmering off it.
  function hot() {
    nap("ring", document.querySelector(".ags-ring.hue-temp.warn, .ags-ring.hue-temp.bad"), "svg", 26);
    nap("soc", document.querySelector("#ec-main .ec-temp b.warn, #ec-main .ec-temp b.bad"), null, 36);
  }
  // `lift`: how far above the gauge's box it lies — on the ring's rim, or
  // clear of the SoC number (the very number you'd want to read when it's hot).
  function nap(key, spot, sub, lift) {
    var k = naps[key], w = spot && shown(spot) ? spot.closest(".widget") : null;
    if (k && k.widget !== w) { drop(k); k = naps[key] = null; }
    if (!w) return;
    if (!k) {
      k = naps[key] = extra(make("loaf", "cat-nap tap " + coat()), w);
      k.hot = true;
      k.acts = [["twitch", 600], ["flick", 700], ["dream", 1500]];
      k.el.insertAdjacentHTML("beforeend", '<b class="cat-heat"><i></i><i></i><i></i></b>');
    }
    var a = (sub && spot.querySelector(sub)) || spot, wr = w.getBoundingClientRect(), r = a.getBoundingClientRect();
    k.el.style.left = Math.round(r.left - wr.left + r.width / 2 - 24) + "px";
    k.el.style.top = Math.round(r.top - wr.top - lift) + "px";
  }

  // Changes arrive as markup: Glance adding cards, the card scripts morphing
  // theirs. Anything inside a cat is the cats themselves — skipped.
  function watch() {
    if (obs || !window.MutationObserver) return;
    var queued = false;
    obs = new MutationObserver(function (list) {
      var grew = false, other = false;
      for (var i = 0; i < list.length; i++) {
        var t = list[i].target;
        if (t.nodeType === 1 && t.closest(".cat, .cat-carry")) continue;
        other = true;
        if (list[i].type === "childList") grew = true;
      }
      if (grew && !queued) {
        queued = true;
        requestAnimationFrame(function () { queued = false; decorate(); });
      }
      if (other) soon();
    });
    obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "title", "data-ha-state"] });
  }

  // ── on / off ─────────────────────────────────────────────────────────────────
  function onResize() { floor(); layout(); }
  function on() {
    if (live) return;
    live = true;
    function start() {
      if (!live) return;
      if (window.IntersectionObserver) {
        io = new IntersectionObserver(function (es) {
          es.forEach(function (e) { var c = e.target._cat; if (c) c.vis = e.isIntersecting; });
        }, { rootMargin: "40px" });
      }
      decorate();
      watch();
      layout();
      check();
      if (!REDUCE) ticker = setInterval(idle, 1100);
      slow = setInterval(function () {
        if (document.hidden) return;
        layout(); tv(); hot(); floor();
      }, 3000);
      document.addEventListener("click", onTap, true);
      document.addEventListener("ha:state", soon);
      window.addEventListener("resize", onResize);
      if (MOUSE) {
        document.addEventListener("pointermove", onMove, { passive: true });
        root.addEventListener("mouseleave", onLeave);
        if (!REDUCE) {
          document.addEventListener("dblclick", onDbl);
          document.addEventListener("keydown", onKey);
        }
      }
    }
    if (document.body) start(); else document.addEventListener("DOMContentLoaded", start, { once: true });
  }
  function off() {
    if (!live) return;
    live = false;
    clearInterval(ticker); clearInterval(slow); clearTimeout(checkT);
    if (obs) { obs.disconnect(); obs = null; }
    if (io) { io.disconnect(); io = null; }
    if (laser) { cancelAnimationFrame(laser.raf); laser = null; }
    root.classList.remove("cat-lasering");
    cats.concat(extras).forEach(function (c) { c.t.forEach(clearTimeout); });
    document.querySelectorAll(".cat, .cat-walk, .cat-paws, .cat-carry, .cat-defs, .cat-runner, .cat-laser").forEach(function (e) { e.remove(); });
    document.querySelectorAll(".widget").forEach(function (w) { w._catBat = null; });
    cats = []; extras = []; naps = {}; seen = {};
    document.removeEventListener("click", onTap, true);
    document.removeEventListener("ha:state", soon);
    window.removeEventListener("resize", onResize);
    document.removeEventListener("pointermove", onMove);
    root.removeEventListener("mouseleave", onLeave);
    document.removeEventListener("dblclick", onDbl);
    document.removeEventListener("keydown", onKey);
  }
  window.Cats = { on: on, off: off };
})();
