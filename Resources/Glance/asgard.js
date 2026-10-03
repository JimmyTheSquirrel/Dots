// ════════════════════════════════════════════════════════════════════════════
// Asgard (the main Glance, asgard:8888) — the live bits that are not the light
// switches themselves. Those are Resources/Glance/lights.js, shared with
// MarsBar; this file listens to the same stream.
//
//   1. Network panel — throughput, sparklines and the last speed test from
//      network-panel.py (:9555), plus its "Run now" button.
//   2. Live power — watts, sums, the draw bar, "at current draw" projections and
//      "N of M on", repainted from lights.js's `ha:state` events. No polling:
//      ha-bridge already streams every plug's power sensor.
//
// Lives in document.head, served from Glance's assets dir: Glance injects
// widget markup with innerHTML, which never runs <script>, and inline JS in the
// YAML has broken the config before. Event delegation and a MutationObserver
// mean it does not care when that markup arrives.
//
// Glance 0.8.5 renders each widget server-side ONCE per page load (page.js
// calls fetchPageContent() a single time) — there is no client-side widget
// refresh to hook. Everything that moves on screen is driven from here.
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";

  function $(id) { return document.getElementById(id); }

  function text(id, value) {
    var el = $(id);
    if (el && el.textContent !== value) el.textContent = value;
  }

  // Run fn every `ms` while the page is visible. The next run is scheduled
  // only after the previous one settles, so a slow backend can never stack
  // requests; hiding the tab stops it, showing it runs it immediately. (Same
  // helper as Resources/MarsBar/marsbar.js.)
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

  // Start fn once an element matching `selector` exists. Glance inserts the
  // page's widgets after DOMContentLoaded and then marks #page `content-ready`;
  // a page that finishes without the element never starts it at all — so the
  // network poller only ever runs on the page that has the network panel.
  function whenPresent(selector, fn) {
    function boot() {
      if (document.querySelector(selector)) { fn(); return; }
      var page = $("page");
      var obs = new MutationObserver(function () {
        if (document.querySelector(selector)) { obs.disconnect(); fn(); }
        else if (page && page.classList.contains("content-ready")) obs.disconnect();
      });
      obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }

  // ── 1. Network panel ──────────────────────────────────────────────────────
  // Built from location.hostname so it keeps working when the dashboard is
  // opened by IP or FQDN instead of `asgard` (each is in _origins.nix).
  var NET_API = location.protocol + "//" + location.hostname + ":9555";
  var NET_POLL_MS = 2000;

  function fmt(v) {
    if (typeof v !== "number" || !isFinite(v)) return "--";
    return v >= 100 ? v.toFixed(0) : v.toFixed(1);
  }

  function spark(id, values) {
    var svg = $(id);
    if (!svg || !values || values.length < 2) return;
    var w = 240, h = 44, pad = 2, n = values.length, max = 0;
    for (var i = 0; i < n; i++) if (values[i] > max) max = values[i];
    // Each direction auto-scales to its own peak. A shared scale is more
    // honest but pins the upload trace flat to the floor on an asymmetric
    // line, which reads as "nothing is happening".
    if (max <= 0) max = 1;
    var pts = [];
    for (var j = 0; j < n; j++) {
      var x = (j / (n - 1)) * w;
      var y = h - pad - (values[j] / max) * (h - pad * 2);
      pts.push(x.toFixed(1) + "," + y.toFixed(1));
    }
    var line = "M" + pts.join(" L");
    svg.querySelector(".np-line").setAttribute("d", line);
    svg.querySelector(".np-fill").setAttribute("d", line + " L" + w + "," + h + " L0," + h + " Z");
  }

  function renderNet(data) {
    var live = data.live || {};
    text("np-down", fmt(live.down));
    text("np-up", fmt(live.up));
    text("np-peak-down", fmt(live.peak_down));
    text("np-peak-up", fmt(live.peak_up));
    spark("np-spark-down", live.hist_down);
    spark("np-spark-up", live.hist_up);

    var st = data.speedtest || {};
    if (st.ok) {
      text("np-st-down", fmt(st.down));
      text("np-st-up", fmt(st.up));
      text("np-st-ping", fmt(st.ping));
      text("np-st-jitter", fmt(st.jitter));
      text("np-st-server", st.server || "");
      // Glance's page.js keeps [data-dynamic-relative-time] ticking ("5h");
      // a new result only has to move the timestamp it counts from.
      var when = $("np-st-when"), t = Date.parse(st.timestamp);
      if (when && !isNaN(t)) {
        var unix = String(Math.floor(t / 1000));
        if (when.getAttribute("data-dynamic-relative-time") !== unix) {
          when.setAttribute("data-dynamic-relative-time", unix);
          when.textContent = relative(t);
        }
      }
    }

    var btn = $("np-run");
    if (btn && !btn.classList.contains("np-sent")) {
      btn.disabled = !!data.running;
      btn.textContent = data.running ? "Running…" : "Run now";
    }
  }

  // Glance's own format (page.js timestampToRelativeTime), so a freshly
  // painted stamp matches the ones it ticks.
  function relative(ms) {
    var s = Math.max(0, Math.round((Date.now() - ms) / 1000));
    if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m";
    if (s < 86400) return Math.floor(s / 3600) + "h";
    if (s < 2592000) return Math.floor(s / 86400) + "d";
    return Math.floor(s / 2592000) + "mo";
  }

  function tickNet() {
    return fetch(NET_API + "/api", { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(renderNet);
  }

  whenPresent("#np-down", function () {
    var now = poll(tickNet, NET_POLL_MS);
    document.addEventListener("click", function (e) {
      var btn = e.target && e.target.closest ? e.target.closest("#np-run") : null;
      if (!btn || btn.disabled) return;
      btn.disabled = true;
      btn.classList.add("np-sent");
      btn.textContent = "Starting…";
      fetch(NET_API + "/run", {
        method: "POST",
        // Required by network-panel: a POST without it is refused, which is
        // what stops any other web page in a tailnet browser starting tests.
        headers: { "X-Dash": "1" }
      })
        .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); })
        .then(function () { btn.classList.remove("np-sent"); now(); })
        .catch(function () {
          btn.textContent = "Failed";
          setTimeout(function () { btn.classList.remove("np-sent"); now(); }, 2500);
        });
    });
  });

  // ── 2. Live power ─────────────────────────────────────────────────────────
  // Markup contract (written by Modules/Server/glance.nix; lists are
  // space-separated entity ids):
  //   data-ag-w="sensor.x_power"            watts, 1 dp
  //   data-ag-sum="sensor.a sensor.b"       summed watts, 1 dp
  //   data-ag-bar="…" data-ag-ref="150"     style.width = sum / ref, capped 100%
  //   data-ag-kwh="…" data-ag-days="1" data-ag-dp="2"
  //                                         sum × 0.024 × days  (kWh)
  //   data-ag-cost="…" data-ag-days="365" data-ag-dp="0" data-ag-rate="0.3041"
  //                                         "$" + sum × 0.024 × days × rate
  //   data-ag-on="switch.a switch.b"        "N of M on"
  //
  // ⚠ The projections are INSTANTANEOUS draw × 24 h — the same arithmetic as
  // the Jinja in glance.nix (`p * 0.024`), which renders the first frame; keep
  // the two in step. Never relabel them as an average (see glance.nix).
  //
  // A sum is only repainted once every sensor it names has reported, so the
  // server-rendered figure stays until the stream can replace all of it.
  // Relay states are read back from the DOM instead: lights.js has already
  // painted them (optimistic flips included) before it fires the event, and
  // it only fires for entities that CHANGED — one whose server-rendered state
  // was already right never produces an event at all.
  var watts = {}, queued = false;

  document.addEventListener("ha:state", function (e) {
    var d = e.detail || {};
    if (!d.entity) return;
    if (/^sensor\..+_power$/.test(d.entity)) {
      var w = parseFloat(d.state);
      // HA's float(0): an unavailable sensor counts as 0 W, as in the Jinja.
      watts[d.entity] = isFinite(w) ? w : 0;
    }
    if (!queued) { queued = true; requestAnimationFrame(paintPower); }
  });

  function ids(el, attr) { return (el.getAttribute(attr) || "").split(/\s+/).filter(Boolean); }

  function sum(list) {
    var total = 0;
    for (var i = 0; i < list.length; i++) {
      if (!(list[i] in watts)) return null;
      total += watts[list[i]];
    }
    return total;
  }

  function put(el, value) {
    if (el.textContent === value) return;
    el.textContent = value;
    // A brief brighten so a moving number is noticed; CSS drops it under
    // prefers-reduced-motion.
    el.classList.remove("ag-tick");
    void el.offsetWidth;
    el.classList.add("ag-tick");
  }

  function each(attr, fn) {
    var els = document.querySelectorAll("[" + attr + "]");
    for (var i = 0; i < els.length; i++) fn(els[i]);
  }

  function num(el, attr, dflt) {
    var v = parseFloat(el.getAttribute(attr));
    return isFinite(v) ? v : dflt;
  }

  function paintPower() {
    queued = false;
    each("data-ag-w", function (el) {
      var s = sum(ids(el, "data-ag-w"));
      if (s !== null) put(el, s.toFixed(1));
    });
    each("data-ag-sum", function (el) {
      var s = sum(ids(el, "data-ag-sum"));
      if (s !== null) put(el, s.toFixed(1));
    });
    each("data-ag-bar", function (el) {
      var s = sum(ids(el, "data-ag-bar"));
      if (s !== null) el.style.width = Math.min(100, (s / num(el, "data-ag-ref", 150)) * 100).toFixed(1) + "%";
    });
    each("data-ag-kwh", function (el) {
      var s = sum(ids(el, "data-ag-kwh"));
      if (s !== null) put(el, (s * 0.024 * num(el, "data-ag-days", 1)).toFixed(num(el, "data-ag-dp", 2)));
    });
    each("data-ag-cost", function (el) {
      var s = sum(ids(el, "data-ag-cost"));
      if (s === null) return;
      var v = s * 0.024 * num(el, "data-ag-days", 1) * num(el, "data-ag-rate", 0);
      put(el, "$" + v.toFixed(num(el, "data-ag-dp", 2)));
    });
    each("data-ag-on", function (el) {
      var list = ids(el, "data-ag-on"), on = 0;
      for (var i = 0; i < list.length; i++) {
        var painted = document.querySelector('[data-ha-entity="' + list[i] + '"]');
        if (!painted) return;
        if (painted.getAttribute("data-ha-state") === "on") on++;
      }
      put(el, on + " of " + list.length + " on");
    });
  }
})();
