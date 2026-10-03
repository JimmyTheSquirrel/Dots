// ════════════════════════════════════════════════════════════════════════════
// MarsBar — the Eclipse page's live bits: TV-box status + actions, and Asgard's
// network throughput graphs. (The lights are Resources/Glance/lights.js, shared
// with the main dashboard.)
//
// Lives in document.head, served from Glance's assets dir: widget markup is
// injected with innerHTML, which never executes <script>, and event delegation
// on `document` means it does not care when that markup arrives.
//
// Both backends are proxied onto this same origin by tailscale serve —
// /eclipse-api → eclipse-control (:9554), /net-api → network-panel (:9555) — so
// there is no CORS and nothing extra to grant in her ACL.
//
// Each poller runs ONLY on a page that has its widget, ONLY while the tab is
// visible, and catches up the instant it becomes visible again. They used to run
// on every page from DOMContentLoaded on, hidden or not: the 2s network poll
// alone was 1800 requests an hour from a phone face-down on the sofa.
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";

  function set(id, txt) {
    var el = document.getElementById(id);
    if (el) el.textContent = txt;
  }

  // Run fn every `ms` while the page is visible. The next run is scheduled
  // only after the previous one finishes, so a slow backend can never stack
  // requests up; hiding the tab stops it, showing it runs it immediately.
  function poll(fn, ms) {
    var timer = null, busy = false;
    function tick() {
      clearTimeout(timer);
      timer = null;
      if (document.hidden || busy) return;
      busy = true;
      Promise.resolve().then(fn).catch(function () {}).then(function () {
        busy = false;
        if (!document.hidden && !timer) timer = setTimeout(tick, ms);
      });
    }
    document.addEventListener("visibilitychange", function () {
      if (document.hidden) { clearTimeout(timer); timer = null; }
      else tick();
    });
    window.addEventListener("pageshow", function (e) { if (e.persisted) tick(); });
    tick();
    return tick; // call to refresh right now (e.g. after an action)
  }

  // Start `fn` once an element matching `selector` exists. Glance inserts the
  // page's widgets after DOMContentLoaded and then marks #page `content-ready`;
  // a page that finishes without the element never starts the poller at all.
  function whenPresent(selector, fn) {
    function boot() {
      if (document.querySelector(selector)) { fn(); return; }
      var page = document.getElementById("page");
      var obs = new MutationObserver(function () {
        if (document.querySelector(selector)) { obs.disconnect(); fn(); }
        else if (page && page.classList.contains("content-ready")) obs.disconnect();
      });
      obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }

  // ── TV box (Eclipse) ──────────────────────────────────────────────────────
  var TV_API = "/eclipse-api";
  var TV_POLL_MS = 15000;

  function fmtUptime(sec) {
    if (!sec && sec !== 0) return "—";
    var d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60);
    if (d > 0) return d + "d " + h + "h";
    return h > 0 ? h + "h " + m + "m" : m + "m";
  }

  // "Display 3840x2160 @ 60.000000" -> "4K · 60Hz". Named sizes, because the
  // raw "3840x2160 @ 60Hz" is too wide for a third of a phone screen.
  var SIZES = { "3840x2160": "4K", "2560x1440": "1440p", "1920x1080": "1080p", "1280x720": "720p" };
  function fmtMode(mode) {
    if (!mode) return "—";
    var m = /(\d+x\d+)\s*@\s*(\d+)/.exec(mode);
    if (!m) return mode.replace(/^Display\s*/, "");
    return (SIZES[m[1]] || m[1].replace("x", "×")) + " · " + m[2] + "Hz";
  }

  function paintTv(s) {
    var box = document.getElementById("tv-box");
    var up = s && s.reachable;
    if (box) box.setAttribute("data-tv", s ? (up ? "ok" : "bad") : "bad");
    set("tv-state", up ? "Eclipse online" : "Eclipse offline");
    set("tv-sub", up ? (s.needs_kodi_restart ? "picture lost — try Restart Kodi" : "ready")
                     : (s ? "cannot reach the TV box" : "cannot reach eclipse-control"));
    set("tv-kodi", up ? (s.kodi || "—") : "—");
    set("tv-mode", up ? fmtMode(s.mode) : "—");
    set("tv-uptime", up ? fmtUptime(s.uptime) : "—");
  }

  function refreshTv() {
    return fetch(TV_API + "/status", { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(paintTv)
      .catch(function () { paintTv(null); });
  }

  function log(msg, cls) {
    var el = document.getElementById("tv-log");
    if (!el) return;
    el.textContent = msg;
    el.className = "mb-log" + (cls ? " " + cls : "");
  }

  whenPresent("#tv-state", function () {
    var tvNow = poll(refreshTv, TV_POLL_MS);

    document.addEventListener("click", function (e) {
      if (!e.target.closest) return;
      var btn = e.target.closest(".mb-act[data-act]");
      if (!btn || btn.disabled) return;

      var act = btn.getAttribute("data-act");
      var label = btn.querySelector(".mb-name");
      var name = label ? label.textContent : act;
      btn.disabled = true;
      btn.classList.add("busy");
      log(name + "…", "busy");

      fetch(TV_API + "/act/" + encodeURIComponent(act), {
        method: "POST",
        // Required by eclipse-control: a POST without it is refused, which is
        // what stops any other web page in a tailnet browser firing these.
        headers: { "X-Dash": "1" }
      })
        .then(function (r) { return r.json().catch(function () { return {}; }); })
        .then(function (d) {
          btn.disabled = false;
          btn.classList.remove("busy");
          // Prefer the panel's own message — for the speed test that IS the
          // result ("43.3 down / 38.1 up Mbps over LAN"), so reporting a
          // generic "done" would throw away the answer.
          if (d && d.ok === false) { log(d.message || (name + " — failed"), "bad"); }
          else { log((d && d.message) || (name + " — done"), "ok"); }
          tvNow();
        })
        .catch(function () {
          btn.disabled = false;
          btn.classList.remove("busy");
          log(name + " — failed", "bad");
        });
    });
  });

  // ── Live network throughput ───────────────────────────────────────────────
  // Same source the admin dashboard uses (network-panel on :9555).
  //
  // Each trace is scaled to its OWN peak rather than a shared axis — upload and
  // download differ by orders of magnitude here, so a shared scale would flatten
  // one of them into a dead straight line.
  var NET_API = "/net-api";
  var NET_POLL_MS = 2000;
  var W = 300, H = 60;

  function draw(prefix, hist, peak) {
    var line = document.getElementById(prefix + "-line");
    var fill = document.getElementById(prefix + "-fill");
    if (!line || !hist || hist.length < 2) return;
    var max = Math.max(peak || 0, 0.01);
    var n = hist.length;
    var pts = [];
    for (var i = 0; i < n; i++) {
      var x = (i / (n - 1)) * W;
      var y = H - Math.min(1, hist[i] / max) * (H - 3) - 1.5;
      pts.push(x.toFixed(1) + "," + y.toFixed(1));
    }
    line.setAttribute("points", pts.join(" "));
    // Close the path along the baseline so the area under it fills.
    if (fill) fill.setAttribute("points", "0," + H + " " + pts.join(" ") + " " + W + "," + H);
  }

  function mbps(v) {
    return v != null ? (v >= 100 ? v.toFixed(0) : v.toFixed(1)) : "—";
  }

  function tickNet() {
    return fetch(NET_API + "/api", { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (j) {
        var l = j && j.live;
        if (!l) return;
        set("net-down-now", mbps(l.down));
        set("net-up-now", mbps(l.up));
        set("net-down-peak", l.peak_down != null ? mbps(l.peak_down) + " Mb/s" : "—");
        set("net-up-peak", l.peak_up != null ? mbps(l.peak_up) + " Mb/s" : "—");
        set("net-iface", (l.iface || "") + " · live · each trace scaled to its own peak");
        draw("net-down", l.hist_down, l.peak_down);
        draw("net-up", l.hist_up, l.peak_up);
      })
      .catch(function () { set("net-iface", "cannot reach the network panel"); });
  }

  whenPresent("#net-down-now", function () { poll(tickNet, NET_POLL_MS); });
})();
