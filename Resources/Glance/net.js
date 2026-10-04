// net.js — the home page's Network card, from network-panel's /events stream
// (Resources/Network-Panel/network-panel.py, :9555):
//
//   LAN       the server's NIC, down/up, each on its own scale (they differ by
//             an order of magnitude — a shared scale flattens upload to a line)
//   Tailnet   tailscale0: remote Jellyfin, Eclipse away from home, Moonlight
//   Latency   TCP handshake to the internet and to the router, every 5 s
//   Speed test  the last result, the last 7 days of them (hover for each), and
//             "Run now"
//
// One `init` with everything, then a `tick` a second. Replaced a 2 s fetch
// poll of /api. SHARED with MarsBar, like eclipse.js: there it is loaded with
// data-api="/net-api" (her serve proxy) and data-readonly (no "Run now" —
// a speed test pauses SABnzbd, which is an admin decision).
(function () {
  "use strict";
  var D = window.Dash;
  if (!D) return;
  var me = document.currentScript, cfg = (me && me.dataset) || {};
  var API = cfg.api || D.api(cfg.apiPort || "9555");
  var READONLY = "readonly" in cfg;
  var N = 60;
  var st = null;          // everything from init, kept current by the deltas
  var queued = false;

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
      '</div>');
    wireHover();
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
      speedtest: function (d) { if (st) { st.speedtest = d.speedtest; st.running = d.running; st.results = d.results; st.sent = false; soon(); } }
    }, "nw-live");

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
