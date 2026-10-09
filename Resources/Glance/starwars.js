// starwars.js — Asgard's Star Wars skin: what moves. starwars.css is how it
// looks; theme.js loads both when rock picks the skin, calls StarWars.on(),
// and StarWars.off() when he picks another (everything it made, every timer
// and listener, goes).
//
//   space        a starfield in three depths behind everything (made once:
//                each depth is ONE element whose box-shadows are its stars),
//                a few bright stars with a glint, and a ringed planet
//   holograms    the cards materialise (CSS), and every so often a scan line
//                sweeps one that is on screen
//   hyperspace   (switch "jump") a page change is a jump: the stars stretch
//                into streaks and flash, the next page loads, and it drops
//                out of hyperspace there — a canvas, for under a second
//   the crawl    (switch "crawl") on the home page, once a day: "A long time
//                ago, on a server far, far away…", the title, and the crawl —
//                its episode numbered by the day of the year, its title and
//                its three paragraphs written from what the cards say right
//                now (uptime, downloads, what's playing, the hoard). Tap,
//                Esc or Skip ends it.
//   sabers       (switch "sabers") every progress bar is a lightsaber —
//                starwars.css, under html[data-sw-sabers]
//
// Reads the cards from the outside (their text), like the ravens. Switches
// live in this browser as asgard-sw-<part> = "off" (theme.js's picker).
// Reduced motion: no jump, no crawl, no scan.
(function () {
  "use strict";
  if (window.StarWars) return;
  var root = document.documentElement;
  var REDUCE = !!(window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches);
  var animate = Element.prototype.animate;     // Glance replaces HTMLElement's (Claude/marsbar.md)
  var live = false, space = null, scanT = 0, timers = [];
  var opts = { crawl: true, jump: true, sabers: true };

  function get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function put(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private window */ } }
  function sget(k) { try { return sessionStorage.getItem(k); } catch (e) { return null; } }
  function sput(k, v) { try { if (v == null) sessionStorage.removeItem(k); else sessionStorage.setItem(k, v); } catch (e) { /* private window */ } }
  ["crawl", "jump", "sabers"].forEach(function (k) { opts[k] = get("asgard-sw-" + k) !== "off"; });
  function rnd(a, b) { return a + Math.random() * (b - a); }
  function q(s) { return document.querySelector(s); }
  function txt(el) { return el ? (el.textContent || "").replace(/\s+/g, " ").trim() : ""; }
  function later(fn, ms) { var id = setTimeout(fn, ms); timers.push(id); return id; }

  // ── space ──────────────────────────────────────────────────────────────────
  function stars(n, size, alpha) {
    var w = Math.max(screen.width, innerWidth, 1600), h = Math.max(screen.height, innerHeight, 1000), out = [];
    for (var i = 0; i < n; i++) {
      var tint = Math.random() < 0.15 ? "210 225 255" : Math.random() < 0.08 ? "255 236 210" : "255 255 255";
      out.push(Math.round(rnd(0, w)) + "px " + Math.round(rnd(0, h)) + "px 0 " + size + "px rgb(" + tint + " / " + alpha.toFixed(2) + ")");
    }
    return out.join(",");
  }
  function makeSpace() {
    if (space) return;
    space = document.createElement("div");
    space.className = "sw-space";
    space.setAttribute("aria-hidden", "true");
    var h = '<i class="sw-stars s1" style="box-shadow:' + stars(260, 0, 0.55) + '"></i>' +
      '<i class="sw-stars s2" style="box-shadow:' + stars(110, 0.5, 0.8) + '"></i>' +
      '<i class="sw-stars s3" style="box-shadow:' + stars(40, 1, 0.95) + '"></i>';
    for (var i = 0; i < 6; i++) {
      h += '<i class="sw-bright" style="left:' + rnd(3, 97).toFixed(1) + '%;top:' + rnd(3, 80).toFixed(1) + '%;animation-delay:-' + rnd(0, 5).toFixed(1) + 's"></i>';
    }
    space.innerHTML = h + '<i class="sw-planet"></i>';
    document.body.appendChild(space);
  }

  // ── holograms: a scan now and then over a card on screen ───────────────────
  function scan() {
    if (document.hidden || REDUCE) return;
    var ws = [].filter.call(document.querySelectorAll(".widget"), function (w) {
      if (w.classList.contains("header") || (w.parentElement && w.parentElement.closest(".widget"))) return false;
      var r = w.getBoundingClientRect();
      return r.width > 160 && r.top < innerHeight && r.bottom > 0;
    });
    if (!ws.length) return;
    var w = ws[Math.floor(Math.random() * ws.length)];
    var s = w.querySelector(":scope > .sw-scan");
    if (!s) { s = document.createElement("i"); s.className = "sw-scan"; s.setAttribute("aria-hidden", "true"); w.appendChild(s); }
    s.style.setProperty("--sw-h", Math.max(60, w.getBoundingClientRect().height - 60) + "px");
    s.classList.remove("go"); void s.offsetWidth; s.classList.add("go");
  }

  // ── hyperspace ─────────────────────────────────────────────────────────────
  // Streaks from the centre on a canvas: `out` stretches them into the jump
  // (then a flash, and the next page), `in` collapses them back to stars.
  function jump(dir, done) {
    var c = document.createElement("canvas"), dpr = Math.min(devicePixelRatio || 1, 2);
    c.className = "sw-jump"; c.width = innerWidth * dpr; c.height = innerHeight * dpr;
    c.style.width = innerWidth + "px"; c.style.height = innerHeight + "px";
    document.body.appendChild(c);
    var g = c.getContext("2d"), cx = c.width / 2, cy = c.height / 2, n = 260, st = [];
    var hue = getComputedStyle(root).getPropertyValue("--hud").trim() || "#9fd7ff";
    for (var i = 0; i < n; i++) {
      var a = rnd(0, Math.PI * 2), d = Math.pow(Math.random(), 0.6) * Math.hypot(cx, cy);
      st.push({ a: a, d: d, w: rnd(0.6, 2) * dpr });
    }
    var ms = dir === "out" ? 720 : 620, t0 = performance.now();
    function frame(now) {
      var t = Math.min(1, (now - t0) / ms), k = dir === "out" ? t * t * t : 1 - Math.pow(1 - t, 3);
      g.fillStyle = "rgba(2, 3, 8, " + (dir === "out" ? 0.35 + 0.65 * k : 1 - k) + ")";
      g.fillRect(0, 0, c.width, c.height);
      var stretch = dir === "out" ? k : 1 - k;
      for (var j = 0; j < n; j++) {
        var s = st[j], x = Math.cos(s.a), y = Math.sin(s.a);
        var r0 = s.d * (1 - 0.2 * stretch), r1 = s.d + (40 + s.d * 1.6) * stretch * dpr;
        g.strokeStyle = j % 5 ? "rgba(225, 240, 255, " + (0.35 + 0.6 * stretch) + ")" : hue;
        g.lineWidth = s.w;
        g.beginPath(); g.moveTo(cx + x * r0, cy + y * r0); g.lineTo(cx + x * r1, cy + y * r1); g.stroke();
      }
      if (t < 1) return requestAnimationFrame(frame);
      if (dir === "out") {
        var f = document.createElement("div"); f.className = "sw-flash"; document.body.appendChild(f);
        animate.call(f, [{ opacity: 0 }, { opacity: 1 }], { duration: 140, fill: "forwards" }).onfinish = done;
      } else { c.remove(); if (done) done(); }
    }
    requestAnimationFrame(frame);
  }
  function onNav(e) {
    if (!opts.jump || REDUCE || e.defaultPrevented || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    var a = e.target.closest && e.target.closest("a.nav-item[href], .mobile-navigation a[href]");
    if (!a || a.target === "_blank") return;
    var href = a.getAttribute("href");
    if (!href || href.charAt(0) === "#" || a.classList.contains("nav-item-current")) return;
    e.preventDefault();
    sput("sw-jumped", "1");
    jump("out", function () { location.href = a.href; });
  }

  // ── the crawl ──────────────────────────────────────────────────────────────
  function roman(n) {
    var m = [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]], s = "";
    m.forEach(function (p) { while (n >= p[0]) { s += p[1]; n -= p[0]; } });
    return s;
  }
  // "3d 7h" → "3 days and 7 hours"
  function words(d) {
    var u = { d: "day", h: "hour", m: "minute", s: "second" }, parts = [];
    d.replace(/(\d+)\s*([dhms])/g, function (_, n, k) { parts.push(n + " " + u[k] + (n === "1" ? "" : "s")); });
    return parts.length > 1 ? parts.slice(0, -1).join(", ") + " and " + parts[parts.length - 1] : parts[0] || d;
  }
  function today() { var d = new Date(); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate(); }
  function dayOfYear() { var d = new Date(), s = new Date(d.getFullYear(), 0, 0); return Math.floor((d - s) / 864e5); }
  // What the cards say, as a story. Each piece is optional: a card that is
  // not on the page (or not painted yet) just isn't in it.
  function story() {
    var up = /uptime\s*([0-9][0-9dhms ]*[dhms])/i.exec(txt(q("#ags-host")));
    var cpu = null, rings = document.querySelectorAll("#ags-host .ags-ring");
    [].forEach.call(rings, function (r) { if (/^cpu$/i.test(txt(r.querySelector(".ags-ring-l")))) cpu = txt(r.querySelector(".ags-ring-v b")); });
    var free = /([\d.,]+\s*[TG]B)\s*free/i.exec(txt(q("#ags-storage")));
    var dl = txt(q("#ags-dl .dl-state")), speed = txt(q("#ags-dl .dl-speed b")), cur = txt(q("#ags-dl .dl-name span[title]"));
    var queue = /(\d+) in queue/.exec(txt(q("#ags-dl .dl-meta")));
    var landed = txt(q("#ags-dl .dl-recent li:not(.bad) span[title]"));
    var playing = [].map.call(document.querySelectorAll("#ags-playing .ags-play-title"), txt).filter(Boolean);
    var title = playing.length ? "THE BINGE STRIKES BACK" : dl === "downloading" ? "A NEW DOWNLOAD" :
      cpu && +cpu >= 60 ? "REVENGE OF THE CPU" : "RETURN OF THE UPTIME";
    var p1 = (cpu && +cpu >= 60 ? "These are troubled times on the server. " : "It is a period of calm on the server. ") +
      (up ? "Asgard has stood for " + words(up[1].trim()) + " without falling" : "Asgard stands") +
      (cpu ? ", its processors humming at " + cpu + "%" : "") + ".";
    var p2 = dl === "downloading"
      ? "Across the Outer Rim, " + (queue ? queue[1] + " transmissions race" : "a transmission races") + " toward the hall at " + speed +
        " megabits a second" + (cur ? ", the swiftest of them " + cur : "") + "."
      : landed ? "The last transmission to reach the hall was " + landed + ". The relays fall silent, awaiting new orders."
      : "No transmissions cross the void tonight. The relays wait.";
    var p3 = playing.length
      ? "On the great screen, " + playing[0] + (playing.length > 1 ? " — and " + (playing.length - 1) + " more beside it" : "") +
        ". The galaxy watches" + (free ? ", while " + free[1] + " lie free in the hoard" : "") + "…"
      : (free ? free[1] + " lie free in the hoard, " : "The hoard waits, ") + "and the great screen is dark, its watchers gone to rest…";
    return { ep: roman(dayOfYear()), title: title, ps: [p1, p2, p3] };
  }
  function crawl() {
    if (!opts.crawl || REDUCE || location.pathname.replace(/\/+$/, "") !== "") return;
    if (get("asgard-sw-crawled") === today()) return;
    // The cards paint a moment after load; tell it once they have.
    var tries = 0;
    (function wait() {
      if (!live) return;
      if (!q("#ags-host .ags-ring") && tries++ < 12) { later(wait, 400); return; }
      put("asgard-sw-crawled", today());
      show(story());
    })();
  }
  function show(s) {
    var el = document.createElement("div");
    el.className = "sw-crawl";
    el.setAttribute("role", "dialog");
    el.setAttribute("aria-label", "Opening crawl — tap to skip");
    el.innerHTML = '<i class="sw-c-stars sw-stars s2" style="box-shadow:' + stars(160, 0.5, 0.8) + '"></i>' +
      '<div class="sw-intro">A long time ago, on a server far,<br>far away…</div>' +
      '<div class="sw-title">ASGARD</div>' +
      '<div class="sw-field"><div class="sw-text"><p class="sw-ep">Episode ' + s.ep + '</p><p class="sw-ep-t">' + s.title + '</p>' +
      s.ps.map(function (p) { return "<p>" + p.replace(/[<>&]/g, "") + "</p>"; }).join("") + '</div></div>' +
      '<button type="button" class="sw-skip">Skip ›</button>';
    document.body.appendChild(el);
    var gone = false;
    function end() {
      if (gone) return;
      gone = true;
      document.removeEventListener("keydown", key);
      el.classList.add("out");
      setTimeout(function () { el.remove(); }, 850);
    }
    function key(e) { if (e.key === "Escape" || e.key === " " || e.key === "Enter") end(); }
    el.addEventListener("click", end);
    document.addEventListener("keydown", key);
    later(end, 46000);
  }

  // ── on / off ───────────────────────────────────────────────────────────────
  function sabers() { if (live && opts.sabers) root.setAttribute("data-sw-sabers", ""); else root.removeAttribute("data-sw-sabers"); }
  function on() {
    if (live) return;
    live = true;
    function start() {
      if (!live) return;
      makeSpace();
      sabers();
      if (!REDUCE) scanT = setInterval(scan, 9000);
      document.addEventListener("click", onNav, true);
      if (sget("sw-jumped") && !REDUCE) { sput("sw-jumped", null); jump("in"); }
      crawl();
    }
    if (document.body) start(); else document.addEventListener("DOMContentLoaded", start, { once: true });
  }
  function off() {
    if (!live) return;
    live = false;
    clearInterval(scanT);
    timers.forEach(clearTimeout); timers = [];
    document.removeEventListener("click", onNav, true);
    root.removeAttribute("data-sw-sabers");
    document.querySelectorAll(".sw-space, .sw-scan, .sw-jump, .sw-flash, .sw-crawl").forEach(function (e) { e.remove(); });
    space = null;
  }
  function set(part, want) {
    if (!(part in opts)) return;
    opts[part] = want;
    if (part === "sabers") sabers();
  }
  window.StarWars = { on: on, off: off, set: set };
})();
