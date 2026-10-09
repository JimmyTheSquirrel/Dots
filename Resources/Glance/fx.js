// fx.js — the "Just for fun" themes besides Cats, on BOTH dashboards.
//
// theme.js loads this (with fx.css) only when someone picks one of them, sets
// <html data-fx="snow|sakura|stars|spooky|ocean"> and calls Fx.on(kind);
// picking anything else calls Fx.off(), which takes every layer, timer and
// listener back out. Nobody else ever downloads it.
//
//   snow     a quiet snowfall: soft flakes at three depths, the nearest few
//            real six-armed ones, turning as they fall
//   sakura   cherry-blossom petals tumbling across the page on the wind
//   stars    a night sky behind the cards — a crescent moon, stars (twinkling,
//            on Asgard) — stars glinting for a moment all over the page, and
//            now and then a shooting star. Tap an empty bit of sky and one
//            shoots from there.
//   spooky   a low moon and mist behind the cards; bats flit across now and
//            then (tap one: eek!), and every so often a spider lets itself
//            down from the top of a card on a thread (tap it: back up it goes)
//   ocean    light coming down through the water behind the cards, bubbles
//            rising, a fish now and then (tap it and it darts off)
//
// Two layers, both fixed and aria-hidden, neither ever takes a tap:
//   .fx-back   behind everything (z-index -1, like the cats' paw prints).
//              Still on MarsBar (fx.css): her cards are frosted glass, and
//              anything moving under the glass is re-blurred every frame.
//   .fx-front  over the cards (under the picker and the ☰ menu): what falls,
//              rises and flies.
// A creature is tapped by POSITION — a pointerdown that lands on it — and the
// tap still goes on to whatever is underneath, so a bat crossing a light can
// never eat the tap meant for the light. The spider goes INTO a .widget
// (beside Glance's markup, never inside a Dash.paint target), like a cat.
//
// Everything that moves is a CSS animation of transform or opacity — the
// compositor's work, not the page's — and the falling things are made once and
// loop, with no timers at all. Hidden tab: the spawners skip their turn and
// the layers pause. Reduced motion: nothing falls, flies or twinkles — the
// sky, the moon, the mist and the light stay, still.
(function () {
  "use strict";
  if (window.Fx) return;

  var root = document.documentElement;
  var REDUCE = !!(window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches);

  var kind = null, back = null, front = null, timers = [], live = [];

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function r2(v) { return Math.round(v * 100) / 100; }
  function few(desk, phone) { return window.innerWidth < 700 ? phone : desk; }
  function css(o) { return Object.keys(o).map(function (k) { return k + ":" + o[k]; }).join(";"); }
  // A timer that belongs to the theme, so Fx.off() can cancel everything.
  function later(fn, ms) {
    var id = setTimeout(function () {
      timers = timers.filter(function (x) { return x !== id; });
      if (kind) fn();
    }, ms);
    timers.push(id);
  }
  // fn now and then (every a..b ms; the first after `first`), skipped while
  // the tab is hidden.
  function every(fn, a, b, first) {
    (function next(ms) {
      later(function () { if (!document.hidden) fn(); next(rnd(a, b)); }, ms);
    })(first);
  }
  function layer(cls) {
    var e = document.createElement("div");
    e.className = cls;
    e.setAttribute("aria-hidden", "true");
    document.body.appendChild(e);
    return e;
  }
  // n particles, each with its own numbers: vars(i) -> { c: extra class, v: style }.
  function many(n, cls, vars) {
    for (var i = 0, h = ""; i < n; i++) {
      var p = vars(i);
      h += '<i class="' + cls + (p.c ? " " + p.c : "") + '" style="' + css(p.v) + '"><b></b></i>';
    }
    return h;
  }
  // A one-shot: gone when its animation ends.
  function once(e) {
    e.addEventListener("animationend", function (ev) { if (ev.target === e) e.remove(); });
    return e;
  }

  // ── the drawings ─────────────────────────────────────────────────────────────
  // Moving parts are drawn round their pivot (0,0), as the cats are: a CSS
  // transform on the part turns a wing about the shoulder, a tail about its root.
  function wing() {
    return '<g transform="translate(-3 -1)"><g class="wing"><path class="bd" d="M0-2C-6-7-15-8.5-26-5.5C-23-2.5-22 1-21.6 4.6' +
      'C-18.6 2.6-15.6 2.6-13.6 5.6C-11.6 2.8-8.2 2.6-5.8 5.4C-4.2 3-2.2 2 0 2.4Z"/></g></g>';
  }
  var BAT = '<svg viewBox="-30 -16 60 32">' + wing() + '<g transform="scale(-1 1)">' + wing() + '</g>' +
    '<ellipse class="bd" cx="0" cy="3" rx="4.4" ry="6.2"/><circle class="bd" cx="0" cy="-3.6" r="3.9"/>' +
    '<path class="bd" d="M-3.4-5.4L-3.8-10.6L-0.8-6.8ZM3.4-5.4L3.8-10.6L0.8-6.8Z"/>' +
    '<circle class="ey" cx="-1.5" cy="-3.8" r=".9"/><circle class="ey" cx="1.5" cy="-3.8" r=".9"/></svg>';
  // Faces left; .r turns it round.
  var FISH = '<svg viewBox="0 0 64 32"><g transform="translate(46 16)"><g class="tail"><path class="fb" d="M0 0L15-10C12.4-4 12.4 4 15 10Z"/></g></g>' +
    '<path class="fn" d="M22 7.6C25 2 31 1.6 35 6.6Z"/><path class="fn" d="M24 24.6C27 29 31 29.4 33.4 25.4Z"/>' +
    '<path class="fb" d="M3 16C9 6 25 3 37 7C42 9 46 12 47.5 16C46 20 42 23 37 25C25 29 9 26 3 16Z"/>' +
    '<path class="fs" d="M17 8C20.2 12 20.2 20 17 24M27 6.6C30.4 11 30.4 21 27 25.4"/>' +
    '<circle class="fe" cx="11.5" cy="14.2" r="2.3"/><circle class="fg" cx="10.9" cy="13.5" r=".75"/></svg>';
  var SPIDER = '<svg viewBox="-12 -12 24 26"><path class="lg" d="M-3-1C-7-5-9-4-11-8M-3 1C-7-1-10 0-12-2M-3 3C-7 3-9 6-11 8' +
    'M-2.5 5C-5 7-6 10-7 12M3-1C7-5 9-4 11-8M3 1C7-1 10 0 12-2M3 3C7 3 9 6 11 8M2.5 5C5 7 6 10 7 12"/>' +
    '<ellipse class="sb" cx="0" cy="4" rx="4.6" ry="5.4"/><circle class="sb" cx="0" cy="-2.6" r="3"/>' +
    '<circle class="se" cx="-1.1" cy="-2.9" r=".8"/><circle class="se" cx="1.1" cy="-2.9" r=".8"/></svg>';

  // ── what flies by ────────────────────────────────────────────────────────────
  // Crosses the front layer once (fx-fly, --x0,--y0 → --x1,--y1) and is gone.
  function critter(cls, art, vars) {
    var e = document.createElement("i");
    e.className = "fx-c " + cls;
    e.style.cssText = css(vars);
    e.innerHTML = "<b>" + art + "</b>";
    e.addEventListener("animationend", function (ev) { if (ev.target === e) drop(e); });
    front.appendChild(e);
    live.push(e);
    return e;
  }
  function drop(e) {
    e.remove();
    live = live.filter(function (x) { return x !== e; });
  }
  // Tapped: freeze where it is, then off it goes — d(r) says how far.
  function flee(c, d, ms, ease) {
    c._fled = true;
    var r = c.getBoundingClientRect(), s = parseFloat(c.style.getPropertyValue("--s")) || 1, v = d(r);
    c.style.animation = "none";
    c.style.transform = "translate(" + r2(r.left) + "px," + r2(r.top) + "px) scale(" + s + ")";
    c.classList.add("fled");
    void c.offsetWidth;
    c.style.transition = "transform " + ms + "ms " + ease + ", opacity " + ms + "ms ease-in";
    c.style.transform = "translate(" + r2(r.left + v[0]) + "px," + r2(r.top + v[1]) + "px) scale(" + r2(s * (v[2] || 1)) + ")";
    c.style.opacity = "0";
    later(function () { drop(c); }, ms + 60);
    return r;
  }
  function say(x, y, text) {
    var e = once(document.createElement("i"));
    e.className = "fx-say";
    e.textContent = text;
    e.style.cssText = css({ left: r2(x) + "px", top: r2(y) + "px" });
    front.appendChild(e);
  }

  function bats() {
    var W = window.innerWidth, H = window.innerHeight, ltr = Math.random() < 0.5;
    var k = 1 + Math.floor(Math.random() * few(3, 2)), y = rnd(H * 0.08, H * 0.55);
    for (var i = 0; i < k; i++) {
      var c = critter("bat", BAT, {
        "--x0": (ltr ? -80 : W + 20) + "px", "--x1": (ltr ? W + 20 : -80) + "px",
        "--y0": r2(y + rnd(-40, 40)) + "px", "--y1": r2(y + rnd(-110, 50)) + "px",
        "--s": r2(rnd(0.75, 1.15)), "--d": r2(rnd(6.5, 10)) + "s", "--dl": r2(i * rnd(0.3, 0.8)) + "s",
        "--fl": r2(rnd(0.18, 0.28)) + "s", "--bb": r2(rnd(0.9, 1.5)) + "s",
      });
      c._tap = function (b, x) {
        var r = flee(b, function (r) {
          return [(r.left + r.width / 2 > x ? 1 : -1) * rnd(220, 340), -rnd(280, 420), 0.6];
        }, 900, "cubic-bezier(.45,0,.85,.5)");
        say(r.left + r.width / 2, r.top, "eek!");
      };
    }
  }
  function fish() {
    var W = window.innerWidth, H = window.innerHeight, ltr = Math.random() < 0.5, y = rnd(H * 0.35, H * 0.86);
    var c = critter("fish" + (ltr ? " r" : "") + (Math.random() < 0.4 ? " c2" : ""), FISH, {
      "--x0": (ltr ? -90 : W + 20) + "px", "--x1": (ltr ? W + 20 : -90) + "px",
      "--y0": r2(y) + "px", "--y1": r2(y + rnd(-60, 60)) + "px",
      "--s": r2(rnd(0.7, 1.2)), "--d": r2(rnd(14, 22)) + "s", "--bb": r2(rnd(1.6, 2.6)) + "s", "--fl": r2(rnd(0.35, 0.55)) + "s",
    });
    c._tap = function (f) {
      var r = flee(f, function () { return [(ltr ? 1 : -1) * rnd(340, 520), rnd(-70, 30)]; }, 800, "cubic-bezier(.2,.7,.3,1)");
      for (var i = 0; i < 4; i++) {
        var b = once(document.createElement("i"));
        b.className = "fx-pop";
        b.style.cssText = css({ left: r2(r.left + r.width * (ltr ? 0.15 : 0.85) + rnd(-6, 6)) + "px", top: r2(r.top + r.height / 2 + rnd(-6, 6)) + "px",
          "--s": r2(rnd(4, 9)) + "px", "--dl": r2(i * 0.08) + "s" });
        front.appendChild(b);
      }
    };
  }
  function shoot(x, y) {
    var W = window.innerWidth, H = window.innerHeight, left;
    if (x == null) { x = rnd(W * 0.15, W * 0.95); y = rnd(H * 0.03, H * 0.35); left = Math.random() < (x > W / 2 ? 0.75 : 0.25); }
    else left = x > W / 2;
    var e = once(document.createElement("i"));
    e.className = "shoot";
    e.style.cssText = css({ left: r2(x) + "px", top: r2(y) + "px", "--a": r2(left ? rnd(142, 160) : rnd(20, 38)) + "deg",
      "--l": r2(rnd(90, 150)) + "px", "--go": r2(rnd(240, 420)) + "px", "--d": r2(rnd(0.75, 1.15)) + "s" });
    front.appendChild(e);
  }
  // A star glinting for a moment, anywhere — over the cards too, so the night
  // is there even where the sky behind them is hidden.
  function glint() {
    var e = once(document.createElement("i"));
    e.className = "glint";
    e.style.cssText = css({ left: r2(rnd(2, 98)) + "%", top: r2(rnd(2, 96)) + "%", "--s": r2(rnd(7, 15)) + "px", "--d": r2(rnd(1.2, 2.2)) + "s" });
    front.appendChild(e);
  }
  // The spider: down from the top edge of a card that's on screen, a while
  // hanging there, swaying, and back up — the whole visit one animation.
  function spider() {
    if (document.querySelector(".fx-web")) return;
    var H = window.innerHeight, cards = [];
    document.querySelectorAll(".widget").forEach(function (w) {
      if (w.parentElement && w.parentElement.closest(".widget")) return;   // a group's tabs
      var r = w.getBoundingClientRect();
      if (r.width > 220 && r.height > 140 && r.top > 40 && r.top < H * 0.6) cards.push(w);
    });
    if (!cards.length) return;
    var w = cards[Math.floor(Math.random() * cards.length)];
    var e = document.createElement("i");
    e.className = "fx-web";
    e.setAttribute("aria-hidden", "true");
    e.style.cssText = css({ left: r2(rnd(58, 88)) + "%", "--drop": r2(rnd(40, 90)) + "px", "--d": r2(rnd(18, 26)) + "s" });
    e.innerHTML = '<b class="fx-spider">' + SPIDER + "</b>";
    var sp = e.firstChild;
    sp.addEventListener("animationend", function (ev) { if (ev.target === sp) drop(e); });
    e._tap = function () {
      e._fled = true;
      var m = getComputedStyle(sp).transform;
      sp.style.transform = m === "none" ? "" : m;
      sp.style.animation = "none";
      void sp.offsetWidth;
      sp.style.transition = "transform .6s cubic-bezier(.5,0,.8,.4)";
      sp.style.transform = "translateY(-36px)";
      later(function () { drop(e); }, 700);
    };
    w.appendChild(e);
    live.push(e);
  }

  // ── the scenes ───────────────────────────────────────────────────────────────
  var SCENE = {
    snow: function () {
      if (REDUCE) return;
      front.innerHTML = many(few(48, 26), "sn", function () {
        var z = Math.random(), big = z > 0.88, fall = rnd(15, 24) - z * 7;   // nearer: bigger, brighter, faster
        return { c: big ? "flake" : "", v: {
          left: r2(rnd(-2, 100)) + "%", "--s": r2(big ? rnd(9, 14) : 2 + z * 4) + "px", "--o": r2(0.3 + z * 0.6),
          "--d": r2(fall) + "s", "--dl": -r2(rnd(0, fall)) + "s",
          "--sw": r2(rnd(10, 44)) + "px", "--sd": r2(rnd(2.8, 6)) + "s", "--sdl": -r2(rnd(0, 6)) + "s" } };
      });
    },
    sakura: function () {
      if (REDUCE) return;
      front.innerHTML = many(few(22, 12), "pt", function () {
        var d = rnd(10, 18);
        return { c: Math.random() < 0.3 ? "pale" : "", v: {
          left: r2(rnd(0, 130)) + "%", "--s": r2(rnd(11, 18)) + "px", "--o": r2(rnd(0.6, 0.95)),
          "--dx": -r2(rnd(20, 45)) + "vw", "--d": r2(d) + "s", "--dl": -r2(rnd(0, d)) + "s",
          "--td": r2(rnd(2.4, 4.8)) + "s", "--tdl": -r2(rnd(0, 4)) + "s", "--rx": r2(rnd(0.2, 0.9)), "--ry": r2(rnd(0.1, 0.7)) } };
      });
    },
    stars: function () {
      back.innerHTML = '<i class="moon"></i>' + many(few(90, 50), "st", function () {
        var z = Math.random();
        return { c: !REDUCE && Math.random() < 0.4 ? "tw" : "", v: {
          left: r2(rnd(0, 100)) + "%", top: r2(rnd(0, 92)) + "%", "--s": r2(1 + z * z * 2.2) + "px", "--o": r2(0.25 + z * 0.65),
          "--tw": r2(rnd(2.5, 6)) + "s", "--twl": -r2(rnd(0, 6)) + "s" } };
      });
      if (REDUCE) return;
      every(shoot, 6000, 16000, 2500);
      every(glint, 500, 1400, 300);
    },
    spooky: function () {
      back.innerHTML = '<i class="moon"></i><i class="mist m1"></i><i class="mist m2"></i>';
      if (REDUCE) return;
      every(bats, 7000, 16000, 1500);
      every(spider, 26000, 42000, 5000);
    },
    ocean: function () {
      back.innerHTML = '<i class="ray r1"></i><i class="ray r2"></i><i class="ray r3"></i><i class="ray r4"></i><i class="deep"></i>';
      if (REDUCE) return;
      front.innerHTML = many(few(20, 10), "bb", function () {
        var d = rnd(9, 18);
        return { v: { left: r2(rnd(0, 100)) + "%", "--s": r2(rnd(4, 14)) + "px", "--d": r2(d) + "s", "--dl": -r2(rnd(0, d)) + "s",
          "--sw": r2(rnd(6, 16)) + "px", "--sd": r2(rnd(1.8, 3.6)) + "s", "--sdl": -r2(rnd(0, 3)) + "s" } };
      });
      every(fish, 8000, 17000, 2500);
    },
  };

  // ── taps ─────────────────────────────────────────────────────────────────────
  function onDown(e) {
    if (e.button > 0) return;
    for (var i = live.length - 1; i >= 0; i--) {
      var c = live[i], art = c.querySelector("svg");
      if (c._fled || !c._tap || !art) continue;
      var r = art.getBoundingClientRect(), pad = 10;
      if (e.clientX > r.left - pad && e.clientX < r.right + pad && e.clientY > r.top - pad && e.clientY < r.bottom + pad) {
        c._tap(c, e.clientX);
        return;
      }
    }
  }
  // Starry night: a tap on the sky itself (not a card, not a control) — a
  // shooting star from there.
  function onClick(e) {
    var t = e.target;
    if (t && t.closest && t.closest(".widget, a, button, input, select, textarea, label, summary, .hud-pop, .hud-pick, .header, .mobile-navigation")) return;
    shoot(e.clientX, e.clientY);
  }
  function onVis() { root.classList.toggle("fx-paused", document.hidden); }

  // ── on / off ─────────────────────────────────────────────────────────────────
  function on(k) {
    if (kind === k || !SCENE[k]) return;
    if (kind) off();
    kind = k;
    function start() {
      if (kind !== k) return;
      back = layer("fx-back fx-" + k);
      front = layer("fx-front fx-" + k);
      SCENE[k]();
      document.addEventListener("pointerdown", onDown, { capture: true, passive: true });
      if (k === "stars" && !REDUCE) document.addEventListener("click", onClick);
      document.addEventListener("visibilitychange", onVis);
    }
    if (document.body) start(); else document.addEventListener("DOMContentLoaded", start, { once: true });
  }
  function off() {
    if (!kind) return;
    kind = null;
    timers.forEach(clearTimeout);
    timers = []; live = [];
    document.querySelectorAll(".fx-back, .fx-front, .fx-web").forEach(function (e) { e.remove(); });
    back = front = null;
    document.removeEventListener("pointerdown", onDown, { capture: true });
    document.removeEventListener("click", onClick);
    document.removeEventListener("visibilitychange", onVis);
    root.classList.remove("fx-paused");
  }
  window.Fx = { on: on, off: off };
})();
