// ravens.js — Huginn and Muninn, Odin's ravens, on Asgard's dashboard.
//
// "Huginn and Muninn fly each day over the wide world" (Grímnismál 20) and
// come back to tell Odin what they saw — which is what a dashboard is for. So
// the Ravens theme puts the two of them on the cards:
//
//   idle      perched on a card's top edge: they breathe, blink, cock their
//             heads, preen, ruffle and hop. Every minute or so one flies to
//             another card on screen, wings beating, along a rising arc.
//   you       tap one and it croaks and tells you something it has seen.
//             Huginn ("thought") says what is happening NOW: downloads, what
//             is playing, the lamps, Asgard's load, Eclipse and its network.
//             Muninn ("memory") says what HAS happened: the last download to
//             land, the last thing done to Eclipse, how long Asgard has been
//             up, how much of the hoard is left. Tap again for more; pester
//             one and it flies off.
//   the page  when something changes — a download lands, something starts
//             playing, Eclipse drops off or comes back or changes network,
//             the lamps go on or off — a raven flies to that card and waits
//             with a glowing mark over its head. Tap it for the news.
//
// Like the cats (cats.js), it reads the cards from the OUTSIDE — the text and
// classes they already render — so no card script knows the ravens exist, and
// a raven only ever goes INTO a .widget (beside Glance's markup, never inside
// a Dash.paint target, which would morph it away) or the <body> mid-flight.
//
// theme.js loads this (with ravens.css) only when someone picks Ravens; picking
// anything else calls Ravens.off(), which takes every raven, timer and
// listener back out. Asgard only: MarsBar has her garden. Reduced motion: no
// idle acts and no flights — a raven with news just shows its mark where it
// sits — and a tap still answers.
(function () {
  "use strict";
  if (window.Ravens) return;

  function mq(q) { return !!(window.matchMedia && matchMedia(q).matches); }
  var REDUCE = mq("(prefers-reduced-motion: reduce)");
  var animate = Element.prototype.animate;   // Glance replaces HTMLElement's — see Claude/marsbar.md

  var live = false, ravens = [], seen = null, timers = [], tick = 0, slow = 0, lastNews = 0;

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function pick(a) { return a[Math.floor(Math.random() * a.length)]; }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function q(s) { return document.querySelector(s); }
  function qa(s) { return [].slice.call(document.querySelectorAll(s)); }
  function txt(el) { return el ? (el.textContent || "").replace(/\s+/g, " ").trim() : ""; }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
  function later(fn, ms) {
    var id = setTimeout(function () { timers = timers.filter(function (x) { return x !== id; }); if (live) fn(); }, ms);
    timers.push(id);
    return id;
  }

  // ── the drawing ──────────────────────────────────────────────────────────────
  // Side view, facing right, feet on y=54 — the card's edge. Every moving part
  // is drawn round 0,0 inside <g transform="translate(pivot)">, so ravens.css
  // turns the head about the neck, the wing about the shoulder, the tail about
  // the rump, the lower beak about its hinge.
  function at(x, y, cls, inner) {
    return '<g transform="translate(' + x + ' ' + y + ')"><g class="' + cls + '">' + inner + '</g></g>';
  }
  var TAIL = '<path class="ink" d="M0 0L-15 9.5L-19 15.5L-14.5 15L-12 17L-8 13.2L3 4.5Z"/>' +
    '<path class="sheen" d="M-2 2.4L-13 10.6M-1 4.2L-10 13" />';
  var BODY = '<path class="ink" d="M16 37C15.5 28.5 23 21 33.5 20.5C41.5 20.2 46.5 25 46.5 31.5C46.5 39.5 40.5 45.6 31 46.6C23.5 47.4 16.4 44 16 37Z"/>' +
    '<path class="sheen soft" d="M22 40.5C27 44 35 43.6 40 39"/>';
  var WING = '<path class="wing" d="M0 0C-7.5-1.2-17.5 3.2-24 11C-27 14.8-28.6 19.6-28 22.4C-21.5 21.8-11.5 17.6-5 11.6C-1.5 8.2 0.8 4 0 0Z"/>' +
    '<path class="sheen" d="M-6 4.2C-12 6.6-18.5 11.6-22.5 17.4M-3.6 8.4C-9.6 11.6-15 15.6-18.6 20"/>';
  var HACKLES = '<path class="ink" d="M-1 -1.6C1.6 1.2 3.6 4 3.2 7.6L1.2 6.4L1 9.2L-1.2 7.4L-2.6 9.6L-4 6.4L-6.2 7.8L-6 3.4Z"/>';
  var HEAD = HACKLES +
    '<circle class="ink" cx="5.2" cy="-8.6" r="7.6"/>' +
    '<path class="beak" d="M10.6-12.4C15.4-12.8 20.8-11.4 24.4-7.4C20.8-7.8 15.6-7.6 11.4-6.2Z"/>' +
    at(11.6, -6.6, "rv-jaw", '<path class="beak dk" d="M0 0L11.2-0.6C8.2 1.6 4 2.6 0.2 2.2Z"/>') +
    '<path class="sheen" d="M-0.6-14C2.4-16.2 7-16.4 10-14.4"/>' +
    at(7.8, -10.2, "rv-eye", '<circle class="iris" r="1.7"/><circle class="glint" cx="0.55" cy="-0.6" r="0.55"/><path class="lid" d="M-2.2 0H2.2"/>');
  var LEGS = '<g class="rv-legs"><path class="leg" d="M27.5 46L26.4 53.6M33 45.8L33.6 53.6"/>' +
    '<path class="toe" d="M22.8 54H30.2M30.4 54H37.4"/></g>';
  // Spread wings for flight: the far one darker, both beating about the shoulder.
  var FWING = '<path d="M0 0C-4-9-12.5-19.5-25-25.5L-23.2-22.6L-29.5-22.2L-26.4-19L-31.6-17.6L-27-14.8L-31.2-12.2L-26-10.4' +
    'C-18.5-8-9-4.2 0 0Z"/>';
  var SVG = '<svg viewBox="0 0 64 56" aria-hidden="true">' +
    at(36, 27, "rv-fw far", '<g class="wing dk">' + FWING + '</g>') +
    at(21, 38, "rv-tail", TAIL) +
    '<g class="rv-body">' + BODY + LEGS + '</g>' +
    at(40, 25, "rv-head", HEAD) +
    at(40.5, 26.5, "rv-wing", WING) +
    at(37, 28, "rv-fw near", '<g class="wing">' + FWING + '</g>') +
    '</svg>';

  // Their runes, drawn (no font on these screens has the Runic block): ansuz,
  // Odin's own, for Huginn; mannaz, the mind of man, for Muninn.
  var WHO = {
    huginn: { name: "Huginn", word: "thought", rune: "M4 1.5V14.5M4 2.5L10 6.5M4 6.5L10 10.5" },
    muninn: { name: "Muninn", word: "memory", rune: "M3 14.5V1.5L11 7.5M11 14.5V1.5L3 7.5" }
  };

  function make(id) {
    var el = document.createElement("div");
    el.className = "rv rv-" + id;
    el.setAttribute("aria-hidden", "true");
    el.innerHTML = SVG + '<i class="rv-pip"></i>';
    var r = { id: id, el: el, widget: null, busy: "", news: null, said: -1, taps: [] };
    el._raven = r;
    return r;
  }

  // ── where they sit ───────────────────────────────────────────────────────────
  function cards() {
    return qa(".widget").filter(function (w) {
      if (w.parentElement && w.parentElement.closest(".widget")) return false;
      var b = w.getBoundingClientRect();
      return b.width >= 180 && b.height >= 60;
    });
  }
  function onScreen(w) {
    var b = w.getBoundingClientRect();
    return b.bottom > 60 && b.top < innerHeight - 40 && b.top > 50;     // its top edge is in view
  }
  function perch(r, w, x) {
    var b = w.getBoundingClientRect();
    var max = Math.max(12, b.width - 70);
    r.widget = w;
    if (x == null) x = spot(r, w);
    r.el.style.left = Math.round(clamp(x == null ? rnd(0.12, 0.8) * b.width : x, 12, max)) + "px";
    r.el.style.top = "";
    w.appendChild(r.el);
  }
  // A raven over a button would eat its taps — and a perch stands proud of
  // its card, over the bottom of the card above (or the nav bar). So a spot on
  // the edge is chosen clear of every control and of the other raven; if none
  // is, the raven sits there but takes no taps (.tap off), as the cats do.
  var CTL = "button, a[href], input, select, textarea, summary, label, [data-ha-toggle], [role='button']";
  function controls() {
    return qa(CTL).filter(function (b) { return !b.closest(".rv"); }).map(function (b) { return b.getBoundingClientRect(); })
      .filter(function (b) { return b.width && b.height; });
  }
  function hits(boxes, l, t, w, h) {
    return boxes.some(function (x) { return x.left < l + w - 4 && x.right > l + 4 && x.top < t + h - 4 && x.bottom > t + 4; });
  }
  // The nav bar, the phone's menu bar and the picker sit over the cards: a
  // raven under one of them could be seen but never tapped.
  var OVER = ".header, .mobile-navigation, .hud-pop, .popover-container";
  function covered(l, t, w, h) {
    if (t < 0 || t + h > innerHeight) return true;
    var pts = [[l + w * 0.5, t + h * 0.62], [l + w * 0.3, t + h * 0.4], [l + w * 0.7, t + h * 0.4]];
    return pts.some(function (pt) {
      var e = document.elementFromPoint(pt[0], pt[1]);
      return !!(e && e.closest && e.closest(OVER));
    });
  }
  function spot(r, w) {
    // Its size: as drawn, or (not on the page yet) ravens.css's for this screen.
    var b = w.getBoundingClientRect(), size = r.el.getBoundingClientRect(), small = mq("(max-width: 550px)");
    var rw = size.width || (small ? 52 : 64), rh = size.height || (small ? 46 : 56), lift = rh - (small ? 5 : 6);
    var boxes = controls().concat(ravens.filter(function (o) { return o !== r && o.el.isConnected; })
      .map(function (o) { return o.el.getBoundingClientRect(); }));
    var xs = [];
    for (var i = 0; i < 9; i++) xs.push(12 + (b.width - rw - 24) * (i / 8));
    xs.sort(function () { return Math.random() - 0.5; });
    var vis = b.bottom > 0 && b.top < innerHeight;
    for (var k = 0; k < xs.length; k++) {
      var l = b.left + xs[k], t = b.top - lift;
      if (!hits(boxes, l, t, rw, rh) && !(vis && covered(l, t, rw, rh))) return xs[k];
    }
    return null;                                           // nowhere on this edge is clear
  }
  function clearCards(r, list) {
    return list.filter(function (w) { return spot(r, w) != null; });
  }
  function layout() {
    var boxes = controls();
    ravens.forEach(function (r) {
      var b = r.el.getBoundingClientRect();
      var clear = b.width > 0 && !boxes.some(function (x) { return x.left < b.right - 4 && x.right > b.left + 4 && x.top < b.bottom - 4 && x.bottom > b.top + 4; });
      r.el.classList.toggle("tap", clear && r.busy !== "fly");
    });
  }
  function place() {
    var list = cards(), vis = list.filter(onScreen);
    ravens.forEach(function (r, i) {
      if (r.el.isConnected || r.busy === "fly") return;
      var other = ravens[1 - i] && ravens[1 - i].widget;
      var pool = (vis.length ? vis : list).filter(function (w) { return w !== other; });
      var good = clearCards(r, pool);
      if (!good.length) good = clearCards(r, list.filter(function (w) { return w !== other; }));   // one further down, then
      // Nowhere clear yet (the cards may still be painting): wait for the next
      // look — but not for ever.
      r.tries = (r.tries || 0) + 1;
      if (!good.length && r.tries < 4) return;
      var w = good[i % Math.max(1, good.length)] || pool[0] || list[0];
      if (w) perch(r, w);
    });
    layout();
  }

  // ── idle life ────────────────────────────────────────────────────────────────
  var ACTS = [["tilt", 1400], ["tilt", 1400], ["look", 2600], ["preen", 2400], ["ruffle", 1100], ["hop", 700], ["bob", 900], ["caw", 800]];
  function act(r, name, ms) {
    if (r.busy) return false;
    r.busy = name;
    r.el.classList.add("a-" + name);
    later(function () { r.el.classList.remove("a-" + name); if (r.busy === name) r.busy = ""; }, ms);
    return true;
  }
  function idle() {
    if (document.hidden) return;
    var free = ravens.filter(function (r) { return !r.busy && r.el.isConnected; });
    if (!free.length || Math.random() < 0.35) return;
    var r = pick(free), a = pick(ACTS);
    if (a[0] === "look") r.el.classList.toggle("west");
    if (!act(r, a[0], a[1]) || a[0] !== "hop") return;
    // The hop's class carries the slide (ravens.css); move it once that's on.
    var x = parseFloat(r.el.style.left) || 0, wb = r.widget ? r.widget.getBoundingClientRect() : null;
    if (!wb) return;
    // Only hop to somewhere still clear of buttons.
    var nx = clamp(x + rnd(-40, 40), 12, wb.width - 70), eb = r.el.getBoundingClientRect();
    if (hits(controls(), wb.left + nx, eb.top, eb.width, eb.height)) return;
    requestAnimationFrame(function () { r.el.style.left = Math.round(nx) + "px"; });
  }
  // Now and then one crosses to another card on screen.
  function wander() {
    if (document.hidden || REDUCE) return;
    var free = ravens.filter(function (r) { return !r.busy && r.el.isConnected && !r.news; });
    if (!free.length) return;
    var r = pick(free);
    var other = ravens.filter(function (x) { return x !== r; }).map(function (x) { return x.widget; });
    var to = clearCards(r, cards().filter(function (w) { return onScreen(w) && other.indexOf(w) < 0 && w !== r.widget; }));
    if (to.length) fly(r, pick(to));
  }

  // ── flight ───────────────────────────────────────────────────────────────────
  // Lifted out of its card into the page, flown along a rising arc (sampled
  // keyframes — WAAPI has no curved paths), and set down in the new card.
  function fly(r, w, then) {
    if (!r.el.isConnected || r.busy === "fly" || !w) return;
    var b = r.el.getBoundingClientRect(), sx = scrollX, sy = scrollY;
    var wb = w.getBoundingClientRect();
    var x = spot(r, w);
    x = clamp(x == null ? rnd(0.12, 0.78) * wb.width : x, 12, Math.max(12, wb.width - 70));
    var fx = b.left + sx, fy = b.top + sy;
    var tx = wb.left + sx + x, ty = wb.top + sy + (b.top - (r.widget ? r.widget.getBoundingClientRect().top : b.top + 44));
    r.busy = "fly";
    r.el.classList.remove("tap");
    clearSay(r);
    document.body.appendChild(r.el);
    r.el.classList.add("air", "flying");
    r.el.style.left = fx + "px"; r.el.style.top = fy + "px";
    var dx = tx - fx, dy = ty - fy, dist = Math.sqrt(dx * dx + dy * dy);
    r.el.classList.toggle("west", dx < 0);
    var peak = -Math.min(170, 60 + dist * 0.2), n = 16, kf = [];
    for (var i = 0; i <= n; i++) {
      var t = i / n, tilt = (dy * t + peak * 4 * t * (1 - t));
      kf.push({ transform: "translate(" + (dx * t).toFixed(1) + "px," + tilt.toFixed(1) + "px) rotate(" +
        ((1 - 2 * t) * (dx < 0 ? 8 : -8)).toFixed(1) + "deg)" });
    }
    var dur = clamp(dist / 480 * 1000, 1200, 3800);
    var a = animate.call(r.el, kf, { duration: dur, easing: "cubic-bezier(.45,.05,.4,1)", fill: "forwards" });
    a.onfinish = function () {
      if (!live) return;
      if (!w.isConnected) w = cards().filter(onScreen)[0] || cards()[0];
      r.el.classList.remove("air", "flying");
      if (w) perch(r, w, x);
      a.cancel();
      r.busy = "";
      act(r, "land", 520);
      layout();
      if (then) then();
    };
  }

  // ── what they've seen ────────────────────────────────────────────────────────
  // Each reads a card that may not be on this page (or not painted yet) and
  // returns nothing then. Huginn: now. Muninn: before.
  function lampCount() {
    var all = qa("[data-ha-entity^='light.'], [data-ha-entity^='switch.']").filter(function (e) { return !e.closest(".rv"); });
    var seenIds = {}, on = 0, n = 0;
    all.forEach(function (e) {
      var id = e.getAttribute("data-ha-entity"), st = e.getAttribute("data-ha-state");
      if (seenIds[id] || !st || st === "unknown" || st === "unavailable") return;
      seenIds[id] = 1; n++;
      if (st === "on") on++;
    });
    return n ? { on: on, n: n } : null;
  }
  function playing() {
    return qa("#ags-playing .ags-play-title, #ec-tv .ags-play-title").map(txt).filter(Boolean);
  }
  var THOUGHT = [
    function () {
      var st = txt(q("#ags-dl .dl-state"));
      if (!st) return null;
      if (st === "downloading") {
        var cur = q("#ags-dl .dl-name span[title]"), meta = txt(q("#ags-dl .dl-meta"));
        return "Downloads are pouring in at " + txt(q("#ags-dl .dl-speed b")) + " Mb/s" +
          (cur ? " — " + txt(cur) + " is on its way" : "") + (meta ? ". " + cap(meta) : "") + ".";
      }
      return st === "paused" ? "The downloads are paused. Someone's holding the reins." : "No downloads running — the queue is empty.";
    },
    function () {
      var p = playing();
      if (!p.length) return q("#ags-playing .ags-idle, #ec-tv .ags-idle") ? "Nothing's playing. The hall is quiet." : null;
      return p.length > 1 ? p.length + " things are playing — " + p[0] + " among them." : "On the screen right now: " + p[0] + ".";
    },
    function () {
      var l = lampCount();
      if (!l) return null;
      return !l.on ? "Every lamp in the house is dark." : l.on === l.n ? "Every lamp is lit — all " + l.n + "." : l.on + " of the " + l.n + " lamps are lit.";
    },
    function () {
      var rings = qa("#ags-host .ags-ring");
      if (!rings.length) return null;
      var v = rings.map(function (r) { return [txt(r.querySelector(".ags-ring-l")).toLowerCase(), txt(r.querySelector(".ags-ring-v b")), txt(r.querySelector(".ags-ring-v i"))]; });
      var cpu = v.filter(function (x) { return /^cpu$/.test(x[0]); })[0], temp = v.filter(function (x) { return /temp/.test(x[0]); })[0];
      var hot = temp && +temp[1] >= 70;
      return "Asgard is " + (cpu && +cpu[1] >= 60 ? "working hard" : "at ease") + (cpu ? " — CPU at " + cpu[1] + "%" : "") +
        (temp ? ", " + temp[1] + "°C" + (hot ? ". Warm, for a hall of ice" : "") : "") + ".";
    },
    function () {
      var t = txt(q("#ec-main .ec-title"));
      if (!t) return null;
      var n = txt(q("#ec-net .nt-now .bt-name"));
      return t + (n ? " — " + n.charAt(0).toLowerCase() + n.slice(1) : "") + ".";
    },
    function () {
      var h = new Date().getHours();
      return h < 5 ? "It's the dead of night. Even Odin sleeps — I don't." :
        h < 9 ? "Dawn. We fly out at first light and are back before breakfast." :
        h < 18 ? "Midday over the nine worlds. Nothing stirs that I can't see." : "Dusk. The wolves will be out soon.";
    }
  ];
  var MEMORY = [
    function () {
      var li = q("#ags-dl .dl-recent li");
      if (!li) return null;
      var name = li.querySelector("span[title]"), em = txt(li.querySelector("em"));
      return li.classList.contains("bad") ? "The last download failed: " + txt(name) + "." :
        "The last to land was " + txt(name) + (em ? " (" + em + ")" : "") + ".";
    },
    function () {
      var li = q("#ec-log .lg li:not(.run)");
      if (!li) return null;
      var b = li.querySelector("b"), what = b ? txt(b.firstChild) : "", when = txt(li.querySelector("em")), msg = txt(li.querySelector("span"));
      return "The last thing done to Eclipse: " + (what || "something") + (when ? ", " + when : "") + (msg ? " — " + msg : "") + ".";
    },
    function () {
      var m = /uptime\s*([0-9][0-9dhms ]*[dhms])/i.exec(txt(q("#ags-host")));
      return m ? "Asgard has stood for " + m[1].trim() + " without falling." : null;
    },
    function () {
      var m = /([\d.,]+\s*[TG]B)\s*free/i.exec(txt(q("#ags-storage")));
      return m ? "There's " + m[1] + " left in the hoard." : null;
    },
    function () {
      var d = q("#ags-dl .dl-foot");
      return d ? cap(txt(d)) + " — I counted." : null;
    },
    function () { return "Huginn and Muninn fly every day over the wide world. Odin fears Huginn may not come back — but he fears more for me."; },
    function () { return "Ravens remember faces. I remember yours."; }
  ];
  function next(r) {
    var pool = r.id === "huginn" ? THOUGHT : MEMORY;
    for (var k = 1; k <= pool.length; k++) {
      var i = (r.said + k) % pool.length, s = null;
      try { s = pool[i](); } catch (e) { s = null; }
      if (s) { r.said = i; return s; }
    }
    return "Kraa.";
  }

  // ── talking ──────────────────────────────────────────────────────────────────
  // The read-out lives in the <body>, not the raven: a card is its own
  // stacking context, so anything inside it would slide under the next card.
  function clearSay(r) {
    if (r.bubble) r.bubble.remove();
    r.bubble = null;
    clearTimeout(r.sayT);
  }
  function say(r, text, ms) {
    clearSay(r);
    var who = WHO[r.id];
    var b = document.createElement("div");
    b.className = "rv-say";
    b.setAttribute("aria-hidden", "true");
    b.innerHTML = '<b><svg viewBox="0 0 14 16" aria-hidden="true"><path d="' + who.rune + '"/></svg>' + who.name + ' · ' + who.word + '</b><span></span>';
    b.querySelector("span").textContent = text;
    document.body.appendChild(b);
    var rb = r.el.getBoundingClientRect(), bw = b.offsetWidth, bh = b.offsetHeight;
    var below = rb.top - bh - 12 < 64;                      // no room under the nav bar: say it below
    var x = clamp(rb.left + rb.width / 2 - bw / 2, 8, innerWidth - bw - 8);
    var y = below ? rb.bottom + 8 : rb.top - bh - 10;
    b.style.left = Math.round(x + scrollX) + "px";
    b.style.top = Math.round(y + scrollY) + "px";
    b.style.setProperty("--rv-ax", Math.round(clamp(rb.left + rb.width / 2 - x, 14, bw - 14)) + "px");
    b.classList.add(below ? "below" : "above");
    r.bubble = b;
    r.sayT = later(function () {
      b.classList.add("out");
      later(function () { b.remove(); if (r.bubble === b) r.bubble = null; }, 400);
    }, ms || 7000);
  }
  function onTap(e) {
    var el = e.target && e.target.closest ? e.target.closest(".rv") : null;
    if (!el || !el._raven || !el.classList.contains("tap")) return;
    var r = el._raven, now = Date.now();
    r.taps = r.taps.filter(function (t) { return now - t < 6000; });
    r.taps.push(now);
    if (r.taps.length >= 5 && !REDUCE) {
      r.taps = [];
      say(r, pick(["Kraa! Enough.", "Kraa — I have other worlds to watch.", "Pester Odin instead."]), 1800);
      act(r, "caw", 800);
      later(function () {
        var to = clearCards(r, cards().filter(function (w) { return onScreen(w) && w !== r.widget; }));
        r.busy = "";
        if (to.length) fly(r, pick(to));
      }, 900);
      return;
    }
    var news = r.news;
    r.news = null;
    r.el.classList.remove("has-news");
    r.busy = "";
    act(r, "caw", 800);
    say(r, news || next(r), news ? 9000 : 7000);
  }

  // ── the page ─────────────────────────────────────────────────────────────────
  // What the cards say now, as one snapshot: a CHANGE to it is news (nothing
  // is news on the first look, or every load would be a flurry of ravens).
  function snapshot() {
    var li = q("#ags-dl .dl-recent li span[title]"), orb = q("#ec-main .ec-orb"), l = lampCount();
    var n = txt(q("#ec-net .nt-now .bt-name"));
    return {
      landed: li ? li.getAttribute("title") : null,
      landedPretty: txt(li),
      playing: playing(),
      eclipse: orb ? (orb.classList.contains("bad") ? "down" : orb.classList.contains("ok") ? "up" : "") : "",
      eclipseNet: /^On the cable/.test(n) ? "the cable" : /^On Wi-Fi/.test(n) ? n.replace(/^On Wi-Fi · /, "Wi-Fi (") + ")" : "",
      lamps: l ? l.on : null
    };
  }
  function news(id, sel, text) {
    var r = ravens.filter(function (x) { return x.id === id; })[0];
    if (!r) return;
    var about = sel && q(sel), w = about && about.closest(".widget");
    r.news = text;
    r.el.classList.add("has-news");
    lastNews = Date.now();
    // Fly to the card it's about — if there's a clear spot to land on there;
    // otherwise the mark alone, where it sits.
    if (!REDUCE && w && w !== r.widget && onScreen(w) && r.busy !== "fly" && spot(r, w) != null) { r.busy = ""; fly(r, w); }
  }
  function check() {
    var s = snapshot();
    if (!seen) { seen = s; return; }
    var o = seen;
    seen = s;
    if (Date.now() - lastNews < 20000) return;      // one piece of news at a time
    if (s.landed && o.landed && s.landed !== o.landed) return news("muninn", "#ags-dl", "Fresh from the downloads: " + s.landedPretty + ". It just landed.");
    if (s.eclipse && o.eclipse && s.eclipse !== o.eclipse) {
      return news("huginn", "#ec-main", s.eclipse === "down" ? "Eclipse has gone quiet. I can't hear it any more." : "Eclipse is back on its feet.");
    }
    if (s.eclipseNet && o.eclipseNet && s.eclipseNet !== o.eclipseNet) return news("huginn", "#ec-net", "Eclipse has moved to " + s.eclipseNet + ".");
    var fresh = s.playing.filter(function (t) { return o.playing.indexOf(t) < 0; });
    if (fresh.length) return news("huginn", "#ags-playing, #ec-tv", "Something's started: " + fresh[0] + ".");
    if (s.lamps != null && o.lamps != null && s.lamps !== o.lamps) {
      return news("huginn", "[data-ha-entity]", s.lamps > o.lamps ? "Someone lit a lamp." + (s.lamps > 1 ? " " + s.lamps + " are on now." : "") :
        s.lamps ? "A lamp went out. " + s.lamps + " still lit." : "The last lamp went out. Dark, as I like it.");
    }
  }

  // ── on / off ─────────────────────────────────────────────────────────────────
  function onResize() { layout(); }
  function onScroll() {
    // A raven perched on a card scrolled far away is no use: after a while
    // out of sight, one comes back to a card you can see.
    clearTimeout(onScroll.t);
    onScroll.t = later(function () {
      var gone = ravens.filter(function (r) { return !r.busy && r.widget && !onScreen(r.widget); });
      var to = clearCards(gone[0] || ravens[0], cards().filter(onScreen));
      if (!gone.length || !to.length) return;
      var r = gone[0];
      var other = ravens.filter(function (x) { return x !== r; }).map(function (x) { return x.widget; });
      var free = to.filter(function (w) { return other.indexOf(w) < 0; });
      if (REDUCE) perch(r, (free.length ? free : to)[0]);
      else fly(r, pick(free.length ? free : to));
    }, 2500);
  }
  function on() {
    if (live) return;
    live = true;
    function start() {
      if (!live) return;
      ravens = [make("huginn"), make("muninn")];
      // The cards paint a moment after load; perch once they have.
      later(function () { place(); check(); }, 900);
      if (!REDUCE) tick = setInterval(idle, 1400);
      slow = setInterval(function () {
        if (document.hidden) return;
        if (ravens.some(function (r) { return !r.el.isConnected && r.busy !== "fly"; })) place();
        layout();
        check();
        if (!REDUCE && Math.random() < 0.08) wander();
      }, 4000);
      document.addEventListener("click", onTap, true);
      window.addEventListener("resize", onResize);
      window.addEventListener("scroll", onScroll, { passive: true });
    }
    if (document.body) start(); else document.addEventListener("DOMContentLoaded", start, { once: true });
  }
  function off() {
    if (!live) return;
    live = false;
    clearInterval(tick); clearInterval(slow);
    timers.forEach(clearTimeout); timers = [];
    ravens.forEach(function (r) { r.el.getAnimations && r.el.getAnimations().forEach(function (a) { a.cancel(); }); r.el.remove(); clearSay(r); });
    ravens = []; seen = null; lastNews = 0;
    document.removeEventListener("click", onTap, true);
    window.removeEventListener("resize", onResize);
    window.removeEventListener("scroll", onScroll);
  }
  window.Ravens = { on: on, off: off };
})();
