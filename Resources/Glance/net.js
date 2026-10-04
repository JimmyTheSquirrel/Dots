// net.js — the home page's Network card, from network-panel's /events stream
// (Resources/Network-Panel/network-panel.py, :9555):
//
//   LAN       the server's NIC, down/up, each on its own scale (they differ by
//             an order of magnitude — a shared scale flattens upload to a line)
//   Tailnet   tailscale0: remote Jellyfin, Eclipse away from home, Moonlight
//   Latency   TCP handshake to the internet and to the router, every 5 s
//   Speed test  the last result, the last 7 days of them (hover for each), and
//             "Run now"
//   History   every run network-panel has kept (history.jsonl — it survives
//             reboots): per-day averages as a bar chart and a list, each day
//             opening into its runs; 7 d / 30 d / 90 d / all; download, upload
//             or ping; a CSV export; and "Clear" (two taps, admin only)
//
// One `init` with everything, then a `tick` a second. Replaced a 2 s fetch
// poll of /api. SHARED with MarsBar, like eclipse.js: there it is loaded with
// data-api="/net-api" (her serve proxy) and data-readonly (no "Run now" —
// a speed test pauses SABnzbd, which is an admin decision).
(function () {
  "use strict";
  var D = window.Dash;
  if (!D) return;
  var esc = D.esc;
  var me = document.currentScript, cfg = (me && me.dataset) || {};
  var API = cfg.api || D.api(cfg.apiPort || "9555");
  var READONLY = "readonly" in cfg;
  var N = 60;
  var st = null;          // everything from init, kept current by the deltas
  var queued = false;

  // History panel state. Which panel/range/metric you last used is remembered
  // per browser (a convenience — the page works the same without it).
  var H = { open: false, range: "30", metric: "down", days: {}, cache: {}, full: null, arm: 0, more: false, note: "" };
  try { var saved = JSON.parse(localStorage.getItem("nw-hist") || "{}"); H.open = !!saved.open; H.range = saved.range || H.range; H.metric = saved.metric || H.metric; } catch (_) {}
  function remember() { try { localStorage.setItem("nw-hist", JSON.stringify({ open: H.open, range: H.range, metric: H.metric })); } catch (_) {} }

  function arrow(dir) { return dir === "up" ? "↑" : "↓"; }

  function dirRow(dir, now, series, peakLabel) {
    var peak = Math.max.apply(null, series.concat([0]));
    var sp = D.line(series, D.nice(peak * 1.15 || 1), 300, 30, N);
    return '<div class="nw-dir ' + dir + '"><i>' + arrow(dir) + '</i>' +
      '<span class="nw-num">' + D.mbps(now) + '<u>Mb/s</u></span>' +
      '<svg class="nw-spark" viewBox="0 0 300 30" preserveAspectRatio="none" aria-hidden="true"><path d="' + sp.area + '"></path><path d="' + sp.line + '"></path></svg>' +
      (peakLabel ? '<span class="nw-peak">peak ' + D.mbps(peak) + ' Mb/s · last ' + N + 's</span>' : '') +
    '</div>';
  }

  function msClass(v, warn, bad) { return v == null ? "" : v >= bad ? "bad" : v >= warn ? "warn" : ""; }
  function ms(v) { return v == null ? "–" : (v >= 100 ? v.toFixed(0) : v.toFixed(1)); }

  function testTile(cls, label, unit, cur, series, icon) {
    var vals = series.map(function (r) { return r[cls === "ping" ? "ping" : cls]; });
    var max = D.nice(Math.max.apply(null, vals.concat([1])) * 1.1);
    var sp = D.line(vals, max, 300, 34, vals.length);
    var dot = sp.last ? '<circle cx="' + sp.last[0].toFixed(1) + '" cy="' + sp.last[1].toFixed(1) + '" r="3" vector-effect="non-scaling-stroke"></circle>' : "";
    return '<div class="nw-cell nw-test ' + cls + '" data-test="' + cls + '">' +
      '<div class="nw-k">' + label + '<span>' + (vals.length ? vals.length + " tests" : "") + '</span></div>' +
      '<span class="nw-num"><i>' + icon + '</i>' + (cur == null ? "–" : cls === "ping" ? ms(cur) : D.mbps(cur)) + '<u>' + unit + '</u></span>' +
      (sp.line ? '<svg class="nw-spark" viewBox="0 0 300 34" preserveAspectRatio="none" aria-hidden="true"><path d="' + sp.area + '"></path><path d="' + sp.line + '"></path></svg>' : '') +
    '</div>';
  }

  // ── History ────────────────────────────────────────────────────────────────
  var METRIC = {
    down: { label: "Download", unit: "Mb/s", icon: "↓", cls: "down", fmt: function (v) { return D.mbps(v); } },
    up:   { label: "Upload",   unit: "Mb/s", icon: "↑", cls: "up",   fmt: function (v) { return D.mbps(v); } },
    ping: { label: "Ping",     unit: "ms",   icon: "◷", cls: "ping", fmt: function (v) { return ms(v); } }
  };
  function dayKey(t) { var d = new Date(t); return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2); }
  function dayName(k, long) {
    var p = k.split("-"), d = new Date(+p[0], +p[1] - 1, +p[2]);
    var today = dayKey(Date.now()), yest = dayKey(Date.now() - 864e5);
    if (k === today) return "Today";
    if (k === yest) return "Yesterday";
    return d.toLocaleDateString(undefined, long ? { weekday: "long", day: "numeric", month: "long", year: "numeric" } : { weekday: "short", day: "numeric", month: "short" });
  }
  function histDays() {
    var src = (H.range === "all" && H.full) ? H.full.days : ((st.history || {}).days || []);
    if (H.range === "all") return src;
    var cut = dayKey(Date.now() - (+H.range - 1) * 864e5);
    return src.filter(function (d) { return d.d >= cut; });
  }

  // Bars, one per CALENDAR day (a day with no runs is a gap, not skipped), so
  // the chart's x axis is honest time. Min–max as a thin whisker behind each.
  function trend(days, m) {
    if (!days.length) return '<div class="nw-trend-empty">No speed tests in this range yet</div>';
    var byDay = {}; days.forEach(function (d) { byDay[d.d] = d; });
    var first = H.range === "all" ? days[days.length - 1].d : dayKey(Date.now() - (+H.range - 1) * 864e5);
    var cols = [], p = first.split("-"), cur = new Date(+p[0], +p[1] - 1, +p[2]), end = dayKey(Date.now());
    while (dayKey(cur) <= end && cols.length < 800) { cols.push(byDay[dayKey(cur)] || { d: dayKey(cur), empty: true }); cur.setDate(cur.getDate() + 1); }
    var max = D.nice(Math.max.apply(null, days.map(function (d) { return d[m][2]; }).concat([1])) * 1.05);
    H.cols = cols;
    return '<div class="nw-trend-wrap"><span class="nw-trend-max">' + METRIC[m].fmt(max) + " " + METRIC[m].unit + '</span>' +
      '<div class="nw-trend ' + METRIC[m].cls + '" data-trend style="--n:' + cols.length + '">' + cols.map(function (c) {
        if (c.empty) return '<i class="gap"></i>';
        var v = c[m];
        return '<i><b style="height:' + (100 * v[0] / max).toFixed(1) + '%"></b>' +
          '<s style="bottom:' + (100 * v[1] / max).toFixed(1) + '%;height:' + (100 * (v[2] - v[1]) / max).toFixed(1) + '%"></s></i>';
      }).join("") + '</div></div>' +
      '<div class="nw-trend-cap"><span>' + dayName(cols[0].d) + '</span><span>' + METRIC[m].label + ' · daily average, min–max</span><span>Today</span></div>';
  }

  function dayRow(d, max) {
    var m = H.metric, open = !!H.days[d.d], tests = H.cache[d.d];
    var row = '<li class="nw-day' + (open ? " open" : "") + '">' +
      '<button type="button" class="nw-day-h" data-nw-day="' + d.d + '" aria-expanded="' + open + '">' +
        '<span class="nw-day-d">' + dayName(d.d) + '<em>' + d.n + (d.n === 1 ? " test" : " tests") + (d.manual ? " · " + d.manual + " manual" : "") + '</em></span>' +
        '<span class="nw-day-bar ' + METRIC[m].cls + '"><i style="width:' + (100 * d[m][0] / max).toFixed(1) + '%"></i></span>' +
        '<span class="nw-day-v"><b>' + D.mbps(d.down[0]) + '</b><u>↓</u></span>' +
        '<span class="nw-day-v"><b>' + D.mbps(d.up[0]) + '</b><u>↑</u></span>' +
        '<span class="nw-day-v"><b>' + ms(d.ping[0]) + '</b><u>ms</u></span>' +
        '<i class="nw-chev" aria-hidden="true"></i>' +
      '</button>';
    if (open) {
      row += '<div class="nw-day-b">' + (!tests ? '<div class="nw-day-wait">Loading ' + dayName(d.d, true) + '…</div>'
        : !tests.length ? '<div class="nw-day-wait">No runs</div>'
        : '<div class="nw-day-sub">' + dayName(d.d, true) + ' · down ' + D.mbps(d.down[1]) + '–' + D.mbps(d.down[2]) +
            ' · up ' + D.mbps(d.up[1]) + '–' + D.mbps(d.up[2]) + ' · ping ' + ms(d.ping[1]) + '–' + ms(d.ping[2]) + ' ms</div>' +
          '<ol class="nw-runs">' + tests.slice().reverse().map(function (r) {
            var t = new Date(r.at * 1000);
            return '<li><span class="nw-run-t">' + t.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) + '</span>' +
              '<span class="nw-run-v"><b>' + D.mbps(r.down) + '</b> ↓</span><span class="nw-run-v"><b>' + D.mbps(r.up) + '</b> ↑</span>' +
              '<span class="nw-run-v"><b>' + ms(r.ping) + '</b> ms</span>' +
              '<span class="nw-run-x">' + [r.jitter != null ? r.jitter + " ms jitter" : "", r.loss ? r.loss + "% loss" : "",
                r.bg != null && r.bg >= 5 ? r.bg + " Mb/s background" : "", r.server ? esc(r.server) : ""].filter(Boolean).join(" · ") +
                (r.manual ? ' <em>manual</em>' : '') + '</span></li>';
          }).join("") + '</ol>') + '</div>';
    }
    return row + '</li>';
  }

  function historyPanel() {
    var h = st.history || {}, total = h.count || 0;
    var head = '<button type="button" class="nw-hist-t" id="nw-hist-t" aria-expanded="' + H.open + '">' +
      '<i class="nw-chev" aria-hidden="true"></i>History<span>' +
      (total ? total + " tests over " + ((h.days || []).length >= 120 ? "120+" : (h.days || []).length) + " days · kept across reboots" : "nothing recorded yet") +
      '</span></button>';
    if (!H.open) return '<div class="nw-hist">' + head + '</div>';
    var days = histDays(), m = H.metric;
    var max = D.nice(Math.max.apply(null, days.map(function (d) { return d[m][0]; }).concat([1])));
    var shown = H.more ? days : days.slice(0, 14);
    var chip = function (k, v, label) { return '<button type="button" class="nw-chip' + (H[k] === v ? " on" : "") + '" data-nw-' + k + '="' + v + '">' + label + '</button>'; };
    return '<div class="nw-hist open">' + head +
      '<div class="nw-hist-b">' +
        '<div class="nw-hist-bar">' +
          '<div class="nw-chips" role="group" aria-label="Range">' + chip("range", "7", "7 d") + chip("range", "30", "30 d") + chip("range", "90", "90 d") + chip("range", "all", "All") + '</div>' +
          '<div class="nw-chips" role="group" aria-label="Measure">' + chip("metric", "down", "↓ Down") + chip("metric", "up", "↑ Up") + chip("metric", "ping", "◷ Ping") + '</div>' +
          '<span class="nw-hist-act">' +
            '<a class="ag-pill" href="' + API + '/history.csv" download>Export CSV</a>' +
            (READONLY ? '' : '<button type="button" class="ag-pill nw-clear' + (H.arm > Date.now() ? " armed" : "") + '" id="nw-clear"' + (total ? "" : " disabled") + '>' +
              (H.arm > Date.now() ? "Tap again to delete " + total : "Clear") + '</button>') +
          '</span>' +
        '</div>' +
        (H.note ? '<div class="nw-hist-note">' + esc(H.note) + '</div>' : '') +
        trend(days, m) +
        (days.length ? '<ul class="nw-days">' + shown.map(function (d) { return dayRow(d, max); }).join("") + '</ul>' +
          (days.length > shown.length ? '<button type="button" class="nw-more" data-nw-more="1">Show all ' + days.length + ' days</button>' : '') : '') +
      '</div></div>';
  }

  function fetchDay(k) {
    fetch(API + "/history?day=" + encodeURIComponent(k)).then(function (r) { return r.json(); })
      .then(function (j) { H.cache[k] = j.tests || []; soon(); })
      .catch(function () { H.cache[k] = []; soon(); });
  }
  function fetchFull() {
    fetch(API + "/history").then(function (r) { return r.json(); })
      .then(function (j) { H.full = j; soon(); }).catch(function () {});
  }

  function render() {
    queued = false;
    var el = D.$("nw"); if (!el || !st) return;
    var l = st.live, lat = st.latency || {}, t = st.speedtest || {}, res = st.results || [];
    D.paint(el,
      '<div class="nw">' +
        '<div class="nw-row">' +
          '<div class="nw-cell"><div class="nw-k">LAN<span>' + D.esc(l.iface) + ' · internet + home</span></div>' +
            dirRow("down", l.down, l.hist_down, true) + dirRow("up", l.up, l.hist_up, true) + '</div>' +
          '<div class="nw-cell small"><div class="nw-k">Tailnet<span>' + D.esc(l.ts_iface || "tailscale0") + '</span></div>' +
            dirRow("down", l.ts_down, l.hist_ts_down || []) + dirRow("up", l.ts_up, l.hist_ts_up || []) + '</div>' +
          '<div class="nw-cell small"><div class="nw-k">Latency<span>tcp handshake</span></div>' +
            '<div class="nw-lat"><span>Internet</span><b class="' + msClass(lat.inet, 60, 150) + '">' + ms(lat.inet) + '<u>ms</u></b>' +
            '<span>Router</span><b class="' + msClass(lat.gw, 10, 50) + '">' + ms(lat.gw) + '<u>ms</u></b></div>' +
            (function () {
              var h = lat.hist || [], sp = D.line(h, D.nice(Math.max.apply(null, h.filter(function (v) { return v != null; }).concat([5])) * 1.2), 300, 26, 36);
              return sp.line ? '<svg class="nw-spark lat" viewBox="0 0 300 26" preserveAspectRatio="none" aria-hidden="true"><path d="' + sp.area + '"></path><path d="' + sp.line + '"></path></svg>' : '';
            })() +
          '</div>' +
        '</div>' +
        '<div class="ag-sec">Speed test<span class="ag-sec-end">Ookla · every 6 h · last 7 days</span></div>' +
        '<div class="nw-tests">' +
          testTile("down", "Download", "Mb/s", t.ok ? t.down : null, res, "↓") +
          testTile("up", "Upload", "Mb/s", t.ok ? t.up : null, res, "↑") +
          testTile("ping", "Ping", "ms", t.ok ? t.ping : null, res, "◷") +
        '</div>' +
        '<div class="nw-meta"><span>' +
          (t.ok ? "last run " + D.ago(Date.parse(t.timestamp) / 1000) + " · " + D.esc(t.server) + " · " + t.jitter + " ms jitter" : "never run") +
          " · upload is shaped to 30 Mb/s</span>" +
          (READONLY ? (st.running ? '<span>running now…</span>' : '') :
          '<button class="ag-pill" id="nw-run" type="button"' + (st.running || st.sent ? " disabled" : "") + '>' +
            (st.running ? "Running…" : st.sent ? "Starting…" : "Run now") + '</button>') + '</div>' +
        historyPanel() +
      '</div>');
    wireHover();
    wireTrend();
  }
  function soon() { if (!queued) { queued = true; requestAnimationFrame(render); } }

  // Hover a speed-test tile → that run's date and figure.
  var wired = {};
  function wireHover() {
    ["down", "up", "ping"].forEach(function (k) {
      var tile = document.querySelector('[data-test="' + k + '"]');
      if (!tile || wired[k] === tile) return;
      wired[k] = tile;
      D.hover(tile, function () { return (st.results || []).length; }, function (i) {
        var r = (st.results || [])[i]; if (!r) return "";
        var d = new Date(r.t);
        return '<div class="ag-tip-h">' + d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" }) +
          " " + d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) + '</div>' +
          '<div class="ag-tip-r"><span>Down</span><b>' + D.mbps(r.down) + ' Mb/s</b></div>' +
          '<div class="ag-tip-r"><span>Up</span><b>' + D.mbps(r.up) + ' Mb/s</b></div>' +
          '<div class="ag-tip-r"><span>Ping</span><b>' + ms(r.ping) + ' ms</b></div>';
      });
    });
  }

  // Hover a day's bar → that day's figures.
  var trendEl = null;
  function wireTrend() {
    var el = document.querySelector("[data-trend]");
    if (!el || el === trendEl) return;
    trendEl = el;
    D.hover(el.parentNode, function () { return (H.cols || []).length; }, function (i) {
      var c = (H.cols || [])[i]; if (!c) return "";
      if (c.empty) return '<div class="ag-tip-h">' + dayName(c.d, true) + '</div><div class="ag-tip-r"><span>no tests</span></div>';
      return '<div class="ag-tip-h">' + dayName(c.d, true) + ' · ' + c.n + (c.n === 1 ? " test" : " tests") + '</div>' +
        '<div class="ag-tip-r"><span>Down</span><b>' + D.mbps(c.down[0]) + ' Mb/s</b></div>' +
        '<div class="ag-tip-r"><span>  range</span><b>' + D.mbps(c.down[1]) + '–' + D.mbps(c.down[2]) + '</b></div>' +
        '<div class="ag-tip-r"><span>Up</span><b>' + D.mbps(c.up[0]) + ' Mb/s</b></div>' +
        '<div class="ag-tip-r"><span>Ping</span><b>' + ms(c.ping[0]) + ' ms</b></div>';
    });
  }

  function shift(arr, v) { arr.push(v); if (arr.length > N) arr.shift(); }

  D.ready("#nw", function () {
    D.stream(API + "/events", {
      init: function (d) { st = d; soon(); },
      tick: function (d) {
        if (!st) return;
        var l = st.live;
        l.down = d.d; l.up = d.u; l.ts_down = d.td; l.ts_up = d.tu;
        shift(l.hist_down, d.d); shift(l.hist_up, d.u);
        shift(l.hist_ts_down || (l.hist_ts_down = []), d.td); shift(l.hist_ts_up || (l.hist_ts_up = []), d.tu);
        soon();
      },
      latency: function (d) { if (st) { st.latency = d; soon(); } },
      speedtest: function (d) {
        if (!st) return;
        st.speedtest = d.speedtest; st.running = d.running; st.results = d.results; st.sent = false;
        if (d.history) {
          st.history = d.history;
          H.cache = {};                              // a new run (or a clear) changes the days
          Object.keys(H.days).forEach(function (k) { if (H.days[k]) fetchDay(k); });
          if (H.range === "all") fetchFull();
        }
        soon();
      }
    }, "nw-live");

    // History controls — one delegated handler, since every repaint replaces
    // nothing but what changed (dash.js morph) and the buttons come and go.
    document.addEventListener("click", function (e) {
      var t = e.target && e.target.closest ? e.target.closest("#nw-hist-t, [data-nw-range], [data-nw-metric], [data-nw-day], [data-nw-more], #nw-clear") : null;
      if (!t || !st) return;
      if (t.id === "nw-hist-t") { H.open = !H.open; remember(); }
      else if (t.dataset.nwRange) { H.range = t.dataset.nwRange; H.more = false; remember(); if (H.range === "all") fetchFull(); }
      else if (t.dataset.nwMetric) { H.metric = t.dataset.nwMetric; remember(); }
      else if (t.dataset.nwMore) { H.more = true; }
      else if (t.dataset.nwDay) {
        var k = t.dataset.nwDay;
        H.days[k] = !H.days[k];
        if (H.days[k] && !H.cache[k]) fetchDay(k);
      } else if (t.id === "nw-clear" && !t.disabled) {
        if (H.arm > Date.now()) {
          H.arm = 0;
          D.post(API + "/history/clear").then(function (j) {
            H.note = j && j.cleared != null ? "Cleared " + j.cleared + " tests." : "Couldn't clear the history.";
            H.full = null; H.cache = {}; H.days = {};
            setTimeout(function () { H.note = ""; soon(); }, 6000);
            soon();
          }).catch(function () { H.note = "Couldn't clear the history."; soon(); });
        } else {
          H.arm = Date.now() + 4000;                 // second tap within 4 s confirms
          setTimeout(soon, 4100);
        }
      }
      soon();
    });

    document.addEventListener("click", function (e) {
      var btn = e.target && e.target.closest ? e.target.closest("#nw-run") : null;
      if (!btn || btn.disabled || !st) return;
      st.sent = true; soon();
      D.post(API + "/run").catch(function () {}).then(function () {
        // The stream reports `running` within 2 s; this only covers a refusal.
        setTimeout(function () { if (st.sent) { st.sent = false; soon(); } }, 6000);
      });
    });
  });
})();
