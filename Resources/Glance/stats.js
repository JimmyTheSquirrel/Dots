// stats.js — renders asgard-stats (Resources/Asgard-Stats/asgard-stats.py) into
// the home page's live cards: Asgard, Storage, Now Playing and Downloads.
// (The Eclipse page's "On the TV" is eclipse.js — from eclipse-control, so
// MarsBar can show it too without any access to this service.)
//
// Loaded from document.head with data-api-port="9552" → it connects to
// http://<this page's hostname>:9552/stream, so the dashboard works whether it
// was opened as asgard, its FQDN or its IP (each is in _origins.nix). Posters
// come straight from Jellyfin on data-jellyfin-port (its image endpoints are
// anonymous). Stream lifecycle and DOM morphing: dash.js.
(function () {
  "use strict";
  var D = window.Dash;
  if (!D) return;
  var me = document.currentScript;
  var API = D.api((me && me.dataset.apiPort) || "9552");
  var JF = D.api((me && me.dataset.jellyfinPort) || "8096");
  var CARDS = "#ags-host, #ags-storage, #ags-playing, #ags-dl";
  var HIST = 90;                     // chart samples: 90 × 2 s = 3 min (the server keeps the same)
  var hist = { cpu: [], mem: [], ts: null, dl: [] };
  var esc = D.esc, $ = D.$, level = D.level;

  function push(arr, v, n) { arr.push(v); if (arr.length > (n || HIST)) arr.shift(); }
  function gib(bytes) { return (bytes / 1073741824).toFixed(bytes >= 10737418240 ? 0 : 1) + " GB"; }

  // A release name → something a person would say.
  //   Severance.S02E07.1080p.WEB.H264      → Severance S02E07
  //   Dune.Part.Two.2024.1080p.BluRay.x264 → Dune Part Two (2024)
  function pretty(name) {
    var n = String(name || "").replace(/\.(mkv|mp4|avi|nzb)$/i, "").replace(/[._]+/g, " ").trim();
    var m = n.match(/^(.*?)\s(S\d{1,2}(?:E\d{1,3}(?:-?E\d{1,3})?)?)\b/i);
    if (m && m[1]) return m[1].replace(/\s(19|20)\d{2}$/, "").trim() + " " + m[2].toUpperCase();
    m = n.match(/^(.*?)\s\(?((?:19|20)\d{2})\)?(?:\s|$)/);
    if (m && m[1]) return m[1].trim() + " (" + m[2] + ")";
    return n.split(/\s(?:2160p|1080p|720p|480p|WEB|BluRay|HDTV|x26[45]|H ?26[45]|HEVC)\b/i)[0].trim();
  }

  // ring gauge: value 0..1. The arc length is an inline STYLE, not the
  // attribute: a style change is what CSS transitions on, so it sweeps.
  // warn/bad add a word under the label — never colour alone.
  function ring(frac, text, unit, label, hue, state, word) {
    var r = 30, c = 2 * Math.PI * r, f = D.clamp(frac || 0, 0, 1);
    return '<div class="ags-ring ' + hue + ' ' + state + '">' +
      '<svg viewBox="0 0 76 76" aria-hidden="true">' +
        '<circle class="ags-ring-track" cx="38" cy="38" r="' + r + '"></circle>' +
        '<circle class="ags-ring-fill" cx="38" cy="38" r="' + r + '" style="stroke-dasharray:' +
          (c * f).toFixed(1) + 'px ' + c.toFixed(1) + 'px"></circle>' +
      '</svg>' +
      '<div class="ags-ring-v"><b>' + text + '</b><i>' + unit + '</i></div>' +
      '<div class="ags-ring-l">' + label + (state !== "ok" && word ? '<em>' + word + '</em>' : '') + '</div></div>';
  }

  // ── Asgard ─────────────────────────────────────────────────────────────────
  function chart(cores) {
    // Scale to the next 25 % above the busiest point: a server idling at 15 %
    // otherwise draws a flat line along the floor. The top label says where.
    var peak = Math.max.apply(null, hist.cpu.concat(hist.mem, [1]));
    var max = Math.min(100, Math.ceil(peak * 1.1 / 25) * 25);
    var W = 300, H = 64, cpu = D.line(hist.cpu, max, W, H, HIST), mem = D.line(hist.mem, max, W, H, HIST);
    return '<div class="ags-cpu">' +
      '<div class="ags-cores" style="--n:' + cores.length + '">' + cores.map(function (c, i) {
        return '<i class="' + level(c, 70, 90) + '" style="height:' + D.clamp(c, 3, 100) + '%" title="thread ' + i + ': ' + c + '%"></i>';
      }).join("") + '</div>' +
      '<div class="ags-spark-wrap"><span class="ags-spark-max">' + max + '%</span>' +
      '<svg class="ags-spark" viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" aria-hidden="true">' +
        '<defs><linearGradient id="ags-spark-g" x1="0" y1="0" x2="0" y2="1">' +
          '<stop offset="0" stop-color="#359658" stop-opacity=".34"></stop>' +
          '<stop offset="1" stop-color="#359658" stop-opacity="0"></stop></linearGradient></defs>' +
        '<line class="ags-spark-grid" x1="0" x2="' + W + '" y1="' + H / 2 + '" y2="' + H / 2 + '"></line>' +
        (cpu.line ? '<path class="ags-spark-fill" d="' + cpu.area + '"></path><path class="ags-spark-line" d="' + cpu.line + '"></path>' : '') +
        (mem.line ? '<path class="ags-spark-mem" d="' + mem.line + '"></path>' : '') +
      '</svg></div>' +
      '<div class="ags-cpu-cap"><span>' + cores.length + ' threads</span>' +
        '<span><b class="k-cpu">cpu</b> <b class="k-mem">memory</b> · last 3 min</span></div>' +
    '</div>';
  }

  function renderHost(s) {
    var el = $("ags-host"); if (!el) return;
    var memFrac = s.mem.total ? s.mem.used / s.mem.total : 0;
    var t = s.temps || {};
    var facts = [
      ["uptime", D.dur(s.uptime)],
      ["load", s.load.map(function (x) { return x.toFixed(2); }).join("  ")],
      ["memory", gib(s.mem.used) + " / " + gib(s.mem.total)],
    ];
    if (s.mem.swap_total) facts.push(["swap", gib(s.mem.swap_used) + " / " + gib(s.mem.swap_total)]);
    if (t.nvme != null) facts.push(["nvme", Math.round(t.nvme) + " °C"]);
    (s.fans || []).forEach(function (f) {
      facts.push([/fan/i.test(f.label) ? f.label : f.label + " fan", f.rpm + " rpm"]);
    });
    D.paint(el,
      '<div class="ags-hero">' +
        '<div class="ags-rings">' +
          ring(s.cpu.total / 100, Math.round(s.cpu.total), "%", "CPU", "hue-cpu", level(s.cpu.total, 70, 90), "busy") +
          ring(memFrac, Math.round(memFrac * 100), "%", "Memory", "hue-mem", level(memFrac * 100, 80, 92), "high") +
          (t.cpu != null
            ? ring((t.cpu - 25) / 75, Math.round(t.cpu), "°C", "CPU temp", "hue-temp", level(t.cpu, 75, 88), "hot")
            : ring(0, "–", "", "CPU temp", "hue-temp", "ok")) +
        '</div>' +
        '<dl class="ags-facts">' + facts.map(function (f) {
          return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
        }).join("") + '</dl>' +
      '</div>' +
      chart(s.cpu.cores || []));
  }

  // ── Storage ────────────────────────────────────────────────────────────────
  function renderStorage(s) {
    var el = $("ags-storage"); if (!el) return;
    var disks = s.disks || [], pool = s.pool || {};
    // Each disk keeps its palette slot by its position in the list (the disko
    // order), so its segment up top and its row below are the same colour.
    var segs = "";
    disks.forEach(function (d, i) {
      if (d.mount === "/" || !d.mounted) return;
      segs += '<div class="ags-seg ags-seg-' + (i % 3) + '" style="flex:' + d.size + '">' +
                '<i style="width:' + (100 * d.used / d.size).toFixed(1) + '%"></i>' +
                '<span>' + esc(d.label.split(" · ")[0]) + '</span><em>' + D.tb(d.free) + ' free</em></div>';
    });
    var poolPct = pool.mounted && pool.size ? 100 * pool.used / pool.size : 0;
    var known = disks.filter(function (d) { return d.healthy != null; });
    var failing = disks.filter(function (d) { return d.healthy === false; });
    var smart = !s.smart_at ? "SMART not read yet"
      : failing.length ? "SMART: " + failing.map(function (d) { return d.label; }).join(", ") + " FAILING"
      : "SMART passed on " + known.length + " of " + disks.length + " · checked " + D.ago(s.smart_at);

    D.paint(el,
      '<div class="ags-pool">' +
        '<div class="ags-pool-head">' +
          '<div><div class="ags-big">' + (pool.mounted ? D.tb(pool.free) : "offline") + '</div>' +
            '<div class="ags-sub">' + (pool.mounted ? "free of " + D.tb(pool.size) + " · media pool" : "/data/media is not mounted") + '</div></div>' +
          '<div class="ags-pool-pct ' + level(poolPct, 85, 95) + '">' + (pool.mounted ? Math.round(poolPct) + "%" : "–") + '<i>used</i></div>' +
        '</div>' +
        '<div class="ags-segs">' + (segs || '<div class="ags-seg-empty">no data disks mounted</div>') + '</div>' +
      '</div>' +
      '<div class="ags-disks">' + disks.map(function (d, i) {
        if (!d.mounted) {
          return '<div class="ags-disk bad"><span class="ags-dot bad"></span><div class="ags-disk-main">' +
                 '<div class="ags-disk-name">' + esc(d.label) + '</div>' +
                 '<div class="ags-sub">' + esc(d.mount) + ' · NOT MOUNTED — services needing it are stopped</div></div></div>';
        }
        var pct = 100 * d.used / d.size;
        var health = d.healthy === false ? "bad" : (d.temp != null && d.temp >= 55 ? "warn" : "ok");
        var state = d.state === "standby" ? "asleep" : d.ssd ? "solid state" : d.state === "active" ? "spinning" : "";
        var on = d.hours ? " · " + (d.hours >= 8760 ? (d.hours / 8760).toFixed(1) + " yrs" : Math.round(d.hours / 24) + " days") + " on" : "";
        return '<div class="ags-disk d' + (i % 3) + '">' +
          '<span class="ags-dot ' + health + (d.state === "standby" ? " asleep" : "") + '" title="' +
            (d.healthy === false ? "SMART: FAILING" : d.healthy ? "SMART: passed" : "SMART: unknown") + '"></span>' +
          '<div class="ags-disk-main">' +
            '<div class="ags-disk-name">' + esc(d.label) + '<span>' + esc(d.mount) + '</span></div>' +
            '<div class="ags-bar ' + (pct >= 85 ? level(pct, 85, 95) : "") + '"><i style="width:' + pct.toFixed(1) + '%"></i></div>' +
            '<div class="ags-sub">' + D.tb(d.used) + ' of ' + D.tb(d.size) + ' · <b>' + D.tb(d.free) + ' free</b>' + on + '</div>' +
          '</div>' +
          '<div class="ags-disk-side">' +
            '<b>' + (d.temp != null ? Math.round(d.temp) + "°" : d.state === "standby" ? "zz" : "–") + '</b>' +
            '<span>' + state + '</span>' +
          '</div></div>';
      }).join("") + '</div>' +
      '<div class="ags-foot ' + (failing.length ? "bad" : "") + '">' + esc(smart) + '</div>');
  }

  // ── Now Playing ────────────────────────────────────────────────────────────
  function playRow(p) {
    var tc = p.transcode;
    var badge = p.method === "Transcode" ? '<span class="ags-badge warn">transcode</span>'
      : '<span class="ags-badge">' + (p.method === "DirectStream" ? "stream" : "direct") + '</span>';
    var detail = tc ? [tc.video, tc.mbps ? tc.mbps + " Mb/s" : "", tc.hw ? "HW" : "CPU"].filter(Boolean).join(" ") : "";
    var poster = p.poster ? ' style="background-image:url(' + JF + "/Items/" + encodeURIComponent(p.poster) +
      '/Images/Primary?fillHeight=216&amp;quality=85)"' : "";
    return '<div class="ags-play' + (p.paused ? " paused" : "") + '">' +
      '<div class="ags-poster"' + poster + '></div>' +
      '<div class="ags-play-body">' +
        '<div class="ags-play-top"><div class="ags-play-title">' + esc(p.title) + '</div>' + badge + '</div>' +
        '<div class="ags-sub ags-play-sub">' + esc(p.sub) + '</div>' +
        '<div class="ags-bar"><i style="width:' + (100 * (p.progress || 0)).toFixed(1) + '%"></i></div>' +
        '<div class="ags-sub ags-play-meta"><span>' + esc(p.user) + ' · ' + esc(p.device) +
          (p.paused ? " · paused" : "") + (detail ? " · " + esc(detail) : "") + '</span>' +
          '<span>' + (p.remaining_s != null ? D.dur(p.remaining_s) + " left" : "") + '</span></div>' +
      '</div></div>';
  }
  function renderPlaying(s) {
    var el = $("ags-playing"); if (!el) return;
    if (!s.media) return;                           // first frame after idle: keep the skeleton
    if (s.streams == null) { D.paint(el, '<div class="ags-idle">Jellyfin isn’t answering</div>'); return; }
    D.paint(el, s.streams.length ? s.streams.map(playRow).join("") : '<div class="ags-idle"><i></i>Nothing playing</div>');
  }

  // ── Downloads ──────────────────────────────────────────────────────────────
  function renderDownloads(s) {
    var el = $("ags-dl"); if (!el || !s.media) return;
    var d = s.downloads;
    if (!d) { D.paint(el, '<div class="ags-idle">SABnzbd isn’t answering</div>'); return; }
    if (hist.dlTs !== s.ts) { push(hist.dl, d.paused ? 0 : d.mbps, 60); hist.dlTs = s.ts; }
    var state = d.paused ? "paused" : d.count ? "downloading" : "idle";
    var sp = D.line(hist.dl, D.nice(Math.max.apply(null, hist.dl.concat([1])) * 1.1), 300, 34, 60);
    var cur = (d.slots || [])[0], next = (d.slots || []).slice(1);
    var h = d.history || {};
    var html =
      '<div class="dl">' +
        '<div class="dl-head">' +
          '<div class="dl-speed"><b>' + (state === "downloading" ? D.mbps(d.mbps) : "0") + '</b><u>Mb/s</u></div>' +
          '<span class="dl-state ' + (state === "downloading" ? "" : state) + '">' + state + '</span>' +
        '</div>' +
        '<div class="dl-meta">' + (d.count ? d.count + " in queue · " + D.tb(d.left_mb * 1e6) + " left" + (d.eta_s ? " · " + D.dur(d.eta_s) : "") : "queue empty") + '</div>' +
        (hist.dl.length >= 6 && sp.line ? '<svg class="dl-spark" viewBox="0 0 300 34" preserveAspectRatio="none" aria-hidden="true"><path d="' + sp.area + '"></path><path d="' + sp.line + '"></path></svg>' : '') +
        (cur ? '<div class="dl-item"><div class="dl-name"><span title="' + esc(cur.name) + '">' + esc(pretty(cur.name)) + '</span><b>' + Math.round(cur.pct) + '%</b></div>' +
                 '<div class="ags-bar"><i style="width:' + D.clamp(cur.pct, 0, 100).toFixed(1) + '%"></i></div></div>' : '') +
        (next.length ? '<div class="dl-next">Up next: ' + next.map(function (x) { return esc(pretty(x.name)); }).join(" · ") + '</div>' : '') +
        ((h.items || []).length ? '<div class="ag-sec">Recent</div><ul class="dl-recent">' + h.items.map(function (it) {
          var bad = /fail/i.test(it.status);
          return '<li class="' + (bad ? "bad" : "") + '"><i>' + (bad ? "✕" : "✓") + '</i><span title="' + esc(it.name) + '">' + esc(pretty(it.name)) + '</span>' +
            '<em>' + (bad ? esc(it.error.split(",")[0] || "failed") : D.tb(it.bytes)) + (it.done ? " · " + D.ago(it.done).replace(" ago", "") : "") + '</em></li>';
        }).join("") + '</ul>' : '') +
        (h.day ? '<div class="dl-foot"><b>' + esc(h.day) + '</b> today · <b>' + esc(h.week) + '</b> this week</div>' : '') +
      '</div>';
    D.paint(el, html);
  }

  function snapshot(s) {
    if (s.ts !== hist.ts) {
      push(hist.cpu, s.cpu.total);
      push(hist.mem, s.mem.total ? 100 * s.mem.used / s.mem.total : 0);
      hist.ts = s.ts;
    }
    renderHost(s); renderStorage(s); renderPlaying(s); renderDownloads(s);
  }

  D.ready(CARDS, function () {
    D.stream(API + "/stream", {
      // Sent once on connect: the server's last 3 min, so the chart starts full.
      history: function (h) { hist.cpu = h.cpu || []; hist.mem = h.mem || []; hist.ts = h.ts; },
      snapshot: snapshot
    }, "ags-live");
  });
})();
