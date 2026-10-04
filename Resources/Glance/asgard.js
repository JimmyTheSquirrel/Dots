// ════════════════════════════════════════════════════════════════════════════
// Asgard (the main Glance, asgard:8888) — the Power page's live figures and its
// 24-hour chart. The light switches themselves are Resources/Glance/lights.js
// (shared with MarsBar); this listens to the same ha-bridge stream through the
// `ha:state` events lights.js fires for every entity it hears about — ha-bridge
// watches every plug's power, voltage, current, today's energy, wifi signal and
// online state (Modules/Server/_plugs.nix), so nothing on the page is a
// page-load snapshot any more.
//
// The network card that used to live here is Resources/Glance/net.js now.
//
// Markup contract (written by Modules/Server/glance.nix; lists are
// space-separated entity ids):
//   data-ag-w="sensor.x_power"            watts, 1 dp
//   data-ag-sum="sensor.a sensor.b"       summed watts, 1 dp
//   data-ag-kwh="…" data-ag-days="1" data-ag-dp="2"
//                                         sum × 0.024 × days  (kWh)
//   data-ag-cost="…" data-ag-days="365" data-ag-dp="0" data-ag-rate="0.3041"
//                                         "$" + sum × 0.024 × days × rate
//   data-ag-on="switch.a switch.b"        "N of M on"
//   data-ag-val="sensor.x" data-ag-dp="1" the sensor's value, N dp
//   data-ag-energy="sensor.a_total_daily_energy …" data-ag-rate="…" data-ag-dp="2"
//                                         "$" + Σ kWh today × rate (no rate: kWh)
//   data-ag-meter="sensor.x_wifi_signal_percent"   style.width = value %
//   data-ag-online="binary_sensor.x_status"        .is-up / .is-down
//   data-ag-seg="sensor.x_power"          a share-bar segment: flex-grow = watts
//
// ⚠ The projections are INSTANTANEOUS draw × 24 h — the same arithmetic as
// the Jinja in glance.nix (`p * 0.024`), which renders the first frame; keep
// the two in step. Never relabel them as an average (see glance.nix).
// ════════════════════════════════════════════════════════════════════════════
(function () {
  "use strict";
  var D = window.Dash;
  var me = document.currentScript;
  var BRIDGE = location.protocol + "//" + location.hostname + ":" + ((me && me.dataset.apiPort) || "9556");

  // ── 1. Live figures ───────────────────────────────────────────────────────
  // A sum is only repainted once every sensor it names has reported, so the
  // server-rendered figure stays until the stream can replace all of it.
  // Relay states are read back from the DOM instead: lights.js has already
  // painted them (optimistic flips included) before it fires the event.
  var vals = {}, queued = false;

  document.addEventListener("ha:state", function (e) {
    var d = e.detail || {};
    if (!d.entity || d.entity.indexOf("switch.") === 0) {
      if (!queued) { queued = true; requestAnimationFrame(paintPower); }
      return;
    }
    var v = parseFloat(d.state);
    if (d.entity.indexOf("binary_sensor.") === 0) vals[d.entity] = d.state;
    // HA's float(0): an unavailable sensor counts as 0, as in the Jinja.
    else vals[d.entity] = isFinite(v) ? v : 0;
    if (!queued) { queued = true; requestAnimationFrame(paintPower); }
  });

  function ids(el, attr) { return (el.getAttribute(attr) || "").split(/\s+/).filter(Boolean); }
  function sum(list) {
    var total = 0;
    for (var i = 0; i < list.length; i++) {
      if (!(list[i] in vals)) return null;
      total += vals[list[i]];
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
    each("data-ag-w", function (el) { var s = sum(ids(el, "data-ag-w")); if (s !== null) put(el, s.toFixed(1)); });
    each("data-ag-sum", function (el) { var s = sum(ids(el, "data-ag-sum")); if (s !== null) put(el, s.toFixed(1)); });
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
      put(el, "$" + (s * 0.024 * num(el, "data-ag-days", 1) * num(el, "data-ag-rate", 0)).toFixed(num(el, "data-ag-dp", 2)));
    });
    each("data-ag-val", function (el) {
      var s = sum(ids(el, "data-ag-val"));
      if (s !== null) put(el, s.toFixed(num(el, "data-ag-dp", 1)));
    });
    each("data-ag-energy", function (el) {
      var s = sum(ids(el, "data-ag-energy"));
      if (s === null) return;
      var rate = num(el, "data-ag-rate", 0);
      put(el, rate ? "$" + (s * rate).toFixed(num(el, "data-ag-dp", 2)) : s.toFixed(num(el, "data-ag-dp", 3)));
    });
    each("data-ag-meter", function (el) {
      var s = sum(ids(el, "data-ag-meter"));
      if (s !== null) el.style.width = Math.max(0, Math.min(100, s)).toFixed(0) + "%";
    });
    each("data-ag-seg", function (el) {
      var w = vals[el.getAttribute("data-ag-seg")];
      if (w === undefined) return;
      el.style.flexGrow = Math.max(0, w).toFixed(1);
      el.hidden = !(w > 0.05);          // an off lamp takes no space, not even a gap
    });
    each("data-ag-online", function (el) {
      var st = vals[el.getAttribute("data-ag-online")];
      if (st === undefined) return;
      var up = st === "on";
      el.classList.toggle("is-up", up);
      el.classList.toggle("is-down", !up);
      el.title = up ? "Plug online" : "Plug offline";
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

  // ── 2. The 24-hour chart ──────────────────────────────────────────────────
  // ha-bridge GET /history: 10-minute time-weighted averages per plug. Drawn as
  // ONE smooth line — the house's total — in canopy greens;
  // hovering any moment lists every plug's share of it (so nothing is lost by
  // not stacking them). Refreshed every 5 minutes while the page is visible;
  // the bridge caches it for 2.
  if (!D) return;
  var hist = null, totals = [];
  var W = 600, H = 120;

  // The series are the legend chips (glance.nix writes one per plug, in
  // inventory order): data-e entity, data-n name, data-c colour.
  function series(el) {
    var box = el.closest(".pw") || document;
    return Array.prototype.map.call(box.querySelectorAll(".pw-chip[data-e]"), function (c) {
      return { e: c.getAttribute("data-e"), n: c.getAttribute("data-n"), c: c.getAttribute("data-c") };
    });
  }

  // Catmull-Rom through the points, as cubic Béziers: a smooth line that still
  // passes through every bucket. Gaps (null) break it.
  function smooth(pts) {
    if (pts.length < 2) return "";
    var d = "M" + pts[0][0].toFixed(1) + "," + pts[0][1].toFixed(1);
    for (var i = 0; i < pts.length - 1; i++) {
      var p0 = pts[i - 1] || pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] || p2;
      d += " C" + (p1[0] + (p2[0] - p0[0]) / 6).toFixed(1) + "," + (p1[1] + (p2[1] - p0[1]) / 6).toFixed(1) +
           " " + (p2[0] - (p3[0] - p1[0]) / 6).toFixed(1) + "," + (p2[1] - (p3[1] - p1[1]) / 6).toFixed(1) +
           " " + p2[0].toFixed(1) + "," + p2[1].toFixed(1);
    }
    return d;
  }

  function drawChart() {
    var el = D.$("pw-chart"); if (!el || !hist) return;
    var ser = series(el), n = 0, i;
    ser.forEach(function (s) { n = Math.max(n, (hist.series[s.e] || []).length); });
    if (n < 2) { D.paint(el, '<div class="pw-empty">No history yet</div>'); return; }
    totals = [];
    for (i = 0; i < n; i++) {
      var t = 0, any = false;
      ser.forEach(function (s) { var v = (hist.series[s.e] || [])[i]; if (v != null) { t += v; any = true; } });
      totals.push(any ? t : null);
    }
    var known = totals.filter(function (v) { return v != null; });
    var peak = Math.max.apply(null, known.concat([1])), avg = known.reduce(function (a, b) { return a + b; }, 0) / (known.length || 1);
    var max = D.nice(peak * 1.12);
    var x = function (k) { return k / (n - 1) * W; }, y = function (v) { return H - v / max * (H - 6) - 2; };
    var runs = [], cur = [];
    totals.forEach(function (v, k) { if (v == null) { if (cur.length) runs.push(cur); cur = []; } else cur.push([x(k), y(v)]); });
    if (cur.length) runs.push(cur);
    var line = runs.map(smooth).join(" ");
    var area = runs.filter(function (r) { return r.length > 1; }).map(function (r) {
      return smooth(r) + " L" + r[r.length - 1][0].toFixed(1) + "," + H + " L" + r[0][0].toFixed(1) + "," + H + " Z";
    }).join(" ");
    var stats = D.$("pw-stats");
    if (stats) stats.textContent = "peak " + peak.toFixed(0) + " W · avg " + avg.toFixed(0) + " W · " + (avg * 24 / 1000).toFixed(2) + " kWh";
    D.paint(el,
      '<span class="pw-ymax">' + max + ' W</span>' +
      '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" aria-label="Total power draw, last 24 hours">' +
        '<defs>' +
          '<linearGradient id="pw-stroke" x1="0" y1="0" x2="1" y2="0"><stop offset="0" style="stop-color:var(--s1)"></stop><stop offset=".55" style="stop-color:var(--c-pine)"></stop><stop offset="1" style="stop-color:var(--c-lichen)"></stop></linearGradient>' +
          '<linearGradient id="pw-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(--c-pine);stop-opacity:.26"></stop><stop offset="1" style="stop-color:var(--c-pine);stop-opacity:0"></stop></linearGradient>' +
        '</defs>' +
        [0.5].map(function (f) { return '<line class="pw-grid" x1="0" x2="' + W + '" y1="' + y(max * f).toFixed(1) + '" y2="' + y(max * f).toFixed(1) + '"></line>'; }).join("") +
        '<path class="pw-area" d="' + area + '"></path>' +
        '<path class="pw-line" d="' + line + '"></path>' +
        '<line class="pw-cross" id="pw-cross" x1="0" x2="0" y1="0" y2="' + H + '"></line>' +
      '</svg>' +
      '<span class="pw-dot" id="pw-dot"></span>');
    el._n = n;
    el._y = function (k) { return totals[k] == null ? null : y(totals[k]) / H; };
  }

  function wireHover(el) {
    D.hover(el, function () { return el._n || 0; }, function (i) {
      if (!hist || totals[i] == null) return "";
      var t = new Date((hist.start + i * hist.step) * 1000);
      var rows = series(el).map(function (s) {
        var v = (hist.series[s.e] || [])[i];
        return '<div class="ag-tip-r" style="--dev:' + s.c + '"><span><i></i>' + D.esc(s.n) + '</span><b>' + (v == null ? "–" : v.toFixed(1) + " W") + '</b></div>';
      }).join("");
      return '<div class="ag-tip-h">' + t.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) +
        ' · ' + totals[i].toFixed(1) + ' W</div>' + rows;
    }, function (i) {
      var c = document.getElementById("pw-cross"), dot = document.getElementById("pw-dot");
      var on = i != null && el._y && el._y(i) != null;
      if (c) c.classList.toggle("on", on);
      if (dot) dot.classList.toggle("on", on);
      if (!on) return;
      var fx = i / ((el._n || 2) - 1);
      if (c) { c.setAttribute("x1", fx * W); c.setAttribute("x2", fx * W); }
      if (dot) { dot.style.left = (fx * 100) + "%"; dot.style.top = (el._y(i) * 100) + "%"; }
    });
  }

  function loadHistory() {
    return fetch(BRIDGE + "/history", { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (h) { hist = h; drawChart(); })
      .catch(function () {
        var el = D.$("pw-chart");
        if (el && !hist) D.paint(el, '<div class="pw-empty">History unavailable — Home Assistant didn’t answer</div>');
      });
  }

  D.ready("#pw-chart", function () {
    wireHover(D.$("pw-chart"));
    loadHistory();
    setInterval(function () { if (!document.hidden) loadHistory(); }, 300000);
    document.addEventListener("visibilitychange", function () { if (!document.hidden) loadHistory(); });
  });
})();
