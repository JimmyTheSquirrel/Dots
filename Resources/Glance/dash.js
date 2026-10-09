// dash.js — the helpers every live card on the main Glance shares, so
// stats.js, net.js and eclipse.js (and asgard.js's power chart) don't each carry
// their own copy. Loaded first from document.head; exposes window.Dash.
//
//   Dash.stream(url, handlers, badge)  one EventSource with the whole lifecycle:
//       reconnect with backoff (EventSource gives up for good on an HTTP error,
//       e.g. a service restarting mid-deploy), a watchdog for half-open links
//       (every backend here sends something at least every 15 s), and parking:
//       closed after 60 s in a hidden tab, reopened the moment it is shown.
//   Dash.paint(el, html)   morph html into el: only changed attributes and text
//       are touched, so CSS transitions run (a rebuilt node has nothing to
//       transition from) and images are not re-requested every tick.
//   Dash.ready(sel, fn)    run fn once Glance has injected an element matching
//       sel (widget markup arrives after load, via innerHTML), or never.
//   Dash.line(values, max, w, h, slots)  SVG path strings for a sparkline.
//   Dash.hover(el, n, html)  a crosshair-free hover read-out for a chart:
//       html(i) for the sample under the pointer.
(function () {
  "use strict";

  function $(id) { return document.getElementById(id); }
  function esc(t) {
    return t == null ? "" : String(t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  // ── formatting ─────────────────────────────────────────────────────────────
  function dur(s) {
    if (s == null || !isFinite(s)) return "–";
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return d ? d + "d " + h + "h" : h ? h + "h " + m + "m" : m ? m + "m" : Math.max(0, Math.round(s)) + "s";
  }
  function ago(epoch) {
    if (!epoch) return "";
    var s = Date.now() / 1000 - epoch;
    return s < 60 ? "just now" : s < 5400 ? Math.round(s / 60) + "m ago" : s < 172800 ? Math.round(s / 3600) + "h ago" : Math.round(s / 86400) + "d ago";
  }
  function tb(bytes) { // storage sizes: decimal, like the label on the drive
    if (bytes == null) return "–";
    var u = ["B", "KB", "MB", "GB", "TB"], i = 0;
    while (bytes >= 1000 && i < u.length - 1) { bytes /= 1000; i++; }
    return (bytes >= 100 || i < 3 ? Math.round(bytes) : bytes.toFixed(bytes >= 10 ? 1 : 2)) + " " + u[i];
  }
  function mbps(v) { return v == null || !isFinite(v) ? "–" : v >= 100 ? v.toFixed(0) : v.toFixed(1); }
  function level(v, warn, bad) { return v >= bad ? "bad" : v >= warn ? "warn" : "ok"; }

  // ── morph ──────────────────────────────────────────────────────────────────
  function attrs(a, b) {
    var i, n;
    for (i = 0; i < b.attributes.length; i++) {
      n = b.attributes[i];
      if (a.getAttribute(n.name) !== n.value) a.setAttribute(n.name, n.value);
    }
    for (i = a.attributes.length - 1; i >= 0; i--) {
      n = a.attributes[i].name;
      if (!b.hasAttribute(n)) a.removeAttribute(n);
    }
  }
  // Nodes marked data-keep (a hover read-out a script appended) are not part
  // of the rendered html and are left exactly where they are.
  function kept(n) { return n && n.nodeType === 1 && n.hasAttribute("data-keep"); }
  function morph(cur, next) {
    var a = cur.firstChild, b = next.firstChild, bn, an;
    while (b) {
      bn = b.nextSibling;
      while (kept(a)) a = a.nextSibling;
      if (!a) {
        cur.appendChild(b);
      } else if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) {
        cur.replaceChild(b, a); a = b.nextSibling;
      } else {
        if (a.nodeType === 1) { attrs(a, b); morph(a, b); }
        else if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue;
        a = a.nextSibling;
      }
      b = bn;
    }
    while (a) { an = a.nextSibling; if (!kept(a)) cur.removeChild(a); a = an; }
  }
  function paint(el, html) {
    if (!el) return;
    var t = document.createElement("template");
    t.innerHTML = html;
    morph(el, t.content);
  }

  // ── sparkline paths ───────────────────────────────────────────────────────
  // values right-aligned in `slots` positions (a short history still ends at
  // "now"); nulls break the line. Returns { line, area, last:[x,y] }.
  function line(values, max, w, h, slots) {
    slots = slots || values.length;
    var step = w / Math.max(1, slots - 1), off = (slots - values.length) * step;
    var segs = [], cur = [], last = null, i, x, y;
    for (i = 0; i < values.length; i++) {
      if (values[i] == null || !isFinite(values[i])) { if (cur.length) segs.push(cur); cur = []; continue; }
      x = off + i * step;
      y = h - clamp(values[i] / (max || 1), 0, 1) * (h - 3) - 1.5;
      cur.push(x.toFixed(1) + "," + y.toFixed(1));
      last = [x, y];
    }
    if (cur.length) segs.push(cur);
    var l = "", a = "";
    segs.forEach(function (s) {
      if (s.length < 2) return;
      l += "M" + s.join(" L");
      a += "M" + s[0].split(",")[0] + "," + h + " L" + s.join(" L") + " L" + s[s.length - 1].split(",")[0] + "," + h + " Z";
    });
    return { line: l, area: a, last: last };
  }
  // A "nice" ceiling for an axis, just above v: 1, 1.2, 1.5, 2, 2.5, 3, 4,
  // 5, 6, 8 × 10^n — fine enough that a 103 W peak gets a 120 W axis, not 200.
  var STEPS = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
  function nice(v) {
    if (!(v > 0)) return 1;
    var p = Math.pow(10, Math.floor(Math.log10(v))), m = v / p;
    for (var i = 0; i < STEPS.length; i++) if (m <= STEPS[i] + 1e-9) return +(STEPS[i] * p).toPrecision(3);
    return 10 * p;
  }

  // ── hover read-out ────────────────────────────────────────────────────────
  // el: the chart's positioned wrapper. n(): sample count. html(i): content.
  // onMove(i|null) lets the caller draw a crosshair.
  function hover(el, n, html, onMove) {
    var tip = document.createElement("div");
    tip.className = "ag-tip";
    tip.setAttribute("data-keep", "");
    el.appendChild(tip);
    function at(clientX) {
      var r = el.getBoundingClientRect(), k = n();
      if (!k) return null;
      var i = Math.round(clamp((clientX - r.left) / r.width, 0, 1) * (k - 1));
      return { i: i, x: (k > 1 ? i / (k - 1) : 1) * r.width, w: r.width };
    }
    function show(e) {
      var p = at(e.touches ? e.touches[0].clientX : e.clientX);
      if (!p) return hide();
      var body = html(p.i);
      if (!body) return hide();
      if (tip.innerHTML !== body) tip.innerHTML = body;
      tip.classList.add("show");             // shown first, so it can be measured
      var tw = tip.offsetWidth, left = p.x + 14;
      if (left + tw > p.w) left = p.x - tw - 14;
      tip.style.left = Math.max(0, Math.min(left, p.w - tw)) + "px";
      tip.style.top = "0px";
      if (onMove) onMove(p.i);
    }
    function hide() { tip.classList.remove("show"); if (onMove) onMove(null); }
    el.addEventListener("mousemove", show);
    el.addEventListener("mouseleave", hide);
    el.addEventListener("touchstart", show, { passive: true });
    el.addEventListener("touchmove", show, { passive: true });
    el.addEventListener("touchend", function () { setTimeout(hide, 1500); });
  }

  // ── wait for Glance's markup ──────────────────────────────────────────────
  function ready(sel, fn) {
    function boot() {
      if (document.querySelector(sel)) { fn(); return; }
      var page = $("page");
      var obs = new MutationObserver(function () {
        if (document.querySelector(sel)) { obs.disconnect(); fn(); }
        else if (page && page.classList.contains("content-ready")) obs.disconnect();
      });
      obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }

  // ── one EventSource, the whole lifecycle ──────────────────────────────────
  // handlers: { eventName: fn(data) }. badge: element id of an .ags-live badge.
  // Returns { reconnect, close } — close() ends it for good (the Overview's
  // living tree streams only while it is on screen).
  function stream(url, handlers, badge) {
    var es = null, retry = null, park = null, delay = 2000, lastSeen = 0, closed = false;

    function setBadge(on) {
      var b = badge && $(badge);
      if (!b) return;
      var cls = "ags-live " + (on ? "on" : "off"), txt = on ? "live" : "reconnecting";
      if (b.className !== cls) b.className = cls;
      if (b.textContent !== txt) b.textContent = txt;
    }
    function connect() {
      clearTimeout(retry); retry = null;
      if (closed) return;
      if (es) es.close();
      lastSeen = Date.now();
      var src = es = new EventSource(url);
      Object.keys(handlers).forEach(function (name) {
        src.addEventListener(name, function (e) {
          lastSeen = Date.now();
          delay = 2000;
          setBadge(true);
          var d;
          try { d = JSON.parse(e.data); } catch (_) { return; }
          try { handlers[name](d); } catch (err) { if (window.console) console.error(err); }
        });
      });
      src.addEventListener("ping", function () { lastSeen = Date.now(); setBadge(true); });
      src.onerror = function () {
        setBadge(false);
        if (src.readyState === 2 && es === src) {
          es = null;
          retry = setTimeout(connect, delay);
          delay = Math.min(delay * 2, 30000);
        }
      };
    }
    // A link that died half-open (a phone that changed networks) never errors;
    // silence is the only symptom.
    var watch = setInterval(function () {
      if (es && !document.hidden && Date.now() - lastSeen > 40000) { setBadge(false); connect(); }
    }, 10000);
    document.addEventListener("visibilitychange", function () {
      clearTimeout(park);
      if (document.hidden) park = setTimeout(function () { if (es) { es.close(); es = null; } }, 60000);
      else if (!es) connect();
    });
    window.addEventListener("pageshow", function (e) { if (e.persisted && !es) connect(); });
    connect();
    function close() {
      closed = true;
      clearTimeout(retry); clearTimeout(park); clearInterval(watch);
      if (es) { es.close(); es = null; }
    }
    return { reconnect: connect, close: close };
  }

  // POST with the X-Dash header every backend requires (it forces a CORS
  // preflight, which only the dashboards pass).
  function post(url) {
    return fetch(url, { method: "POST", headers: { "X-Dash": "1" } })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { j._status = r.status; return j; }); });
  }

  function api(port) { return location.protocol + "//" + location.hostname + ":" + port; }

  // The weave (asgard.css): one gradient any sparkline can paint with —
  // stroke: url(#ag-weave). In user space, 0 → 300 across, the width every
  // sparkline here is drawn in (viewBox="0 0 300 h"), so a flat line still
  // gets it: a bounding-box gradient on a zero-height path paints nothing.
  // Hidden by size, not display:none, which would switch the gradient off.
  // Its stops are data slots, so it follows whichever theme is loaded; only
  // asgard.css asks for it.
  (function weave() {
    if ($("ag-weave")) return;
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("style", "position:absolute;width:0;height:0;overflow:hidden");
    svg.innerHTML = '<linearGradient id="ag-weave" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="300" y2="0">' +
      '<stop offset="0" style="stop-color:var(--s1)"></stop><stop offset="1" style="stop-color:var(--s3)"></stop></linearGradient>';
    document.body.appendChild(svg);
  })();

  window.Dash = {
    $: $, esc: esc, clamp: clamp, dur: dur, ago: ago, tb: tb, mbps: mbps, level: level,
    paint: paint, line: line, nice: nice, hover: hover, ready: ready, stream: stream, post: post, api: api
  };
})();
