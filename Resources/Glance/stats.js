// stats.js — renders asgard-stats (Resources/Asgard-Stats/asgard-stats.py) into
// the Asgard, Storage and Now Playing cards on the main Glance page.
//
// Loaded from document.head with  data-api-port="9552"  → it connects to
// http://<this page's hostname>:9552/stream, so the dashboard works whether it
// was opened as asgard, its FQDN or its IP (each is in _origins.nix). Posters
// come straight from Jellyfin on data-jellyfin-port (its image endpoints are
// anonymous).
//
// One EventSource per page, opened only if one of the cards is on the page,
// parked after 60 s in a hidden tab and reopened (with an immediate repaint)
// when the tab comes back — the same lifecycle as lights.js.
//
// Every tick re-renders each card to an HTML string and MORPHS it into the
// live DOM: only changed attributes and text are touched. Swapping innerHTML
// instead would rebuild every node every 2 s, so no ring or bar would ever
// animate (a fresh element has nothing to transition from) and the posters
// would be re-requested each time.
(function () {
  "use strict";
  var me = document.currentScript;
  var PORT = (me && me.dataset.apiPort) || "9552";
  var JF_PORT = (me && me.dataset.jellyfinPort) || "8096";
  var API = location.protocol + "//" + location.hostname + ":" + PORT;
  var JF = location.protocol + "//" + location.hostname + ":" + JF_PORT;
  var HIST = 90;                 // chart samples: 90 × 2 s = 3 min (the server keeps the same)
  var hist = { cpu: [], mem: [], ts: null };
  var es = null, retry = null, park = null;

  // ── helpers ────────────────────────────────────────────────────────────────
  function $(id) { return document.getElementById(id); }
  function esc(t) {
    return t == null ? "" : String(t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function tb(bytes) {            // storage: decimal units, like the label on the drive
    if (bytes == null) return "–";
    var u = ["B", "KB", "MB", "GB", "TB"], i = 0;
    while (bytes >= 1000 && i < u.length - 1) { bytes /= 1000; i++; }
    return (bytes >= 100 || i < 3 ? Math.round(bytes) : bytes.toFixed(bytes >= 10 ? 1 : 2)) + " " + u[i];
  }
  function gib(bytes) { return (bytes / 1073741824).toFixed(bytes >= 10737418240 ? 0 : 1) + " GB"; }
  function dur(s) {
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return d ? d + "d " + h + "h" : h ? h + "h " + m + "m" : m + "m";
  }
  function ago(epoch) {
    var s = Date.now() / 1000 - epoch;
    return s < 90 ? "just now" : s < 5400 ? Math.round(s / 60) + "m ago" : Math.round(s / 3600) + "h ago";
  }
  function level(v, warn, bad) { return v >= bad ? "bad" : v >= warn ? "warn" : "ok"; }
  function push(arr, v) { arr.push(v); if (arr.length > HIST) arr.shift(); }

  // morph(live, next): make live's children match next's, reusing nodes.
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
  function morph(cur, next) {
    var a = cur.firstChild, b = next.firstChild, bn, an;
    while (b) {
      bn = b.nextSibling;
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
    while (a) { an = a.nextSibling; cur.removeChild(a); a = an; }
  }
  function paintInto(el, html) {
    var t = document.createElement("template");
    t.innerHTML = html;
    morph(el, t.content);
  }

  // ring gauge: value 0..1, centre text, label, colour class + state class.
  // The arc length is an inline STYLE, not the attribute: a style change is
  // what CSS transitions on, so the ring sweeps to its new value.
  function ring(frac, text, unit, label, hue, state) {
    var r = 30, c = 2 * Math.PI * r, f = clamp(frac || 0, 0, 1);
    return '<div class="ags-ring ' + hue + ' ' + state + '">' +
      '<svg viewBox="0 0 76 76" aria-hidden="true">' +
        '<circle class="ags-ring-track" cx="38" cy="38" r="' + r + '"></circle>' +
        '<circle class="ags-ring-fill" cx="38" cy="38" r="' + r + '" style="stroke-dasharray:' +
          (c * f).toFixed(1) + 'px ' + c.toFixed(1) + 'px"></circle>' +
      '</svg>' +
      '<div class="ags-ring-v"><b>' + text + '</b><i>' + unit + '</i></div>' +
      '<div class="ags-ring-l">' + label + '</div></div>';
  }

  // sparkline points for values scaled to max, right-aligned so a short
  // history still ends at "now"
  function pts(values, max, w, h) {
    var step = w / (HIST - 1), off = (HIST - values.length) * step, out = [];
    for (var i = 0; i < values.length; i++) {
      out.push((off + i * step).toFixed(1) + "," + (h - clamp(values[i] / max, 0, 1) * (h - 3) - 1.5).toFixed(1));
    }
    return out;
  }

  // ── renderers ──────────────────────────────────────────────────────────────
  function chart(cores) {
    // Scale to the next 25 % above the busiest point: a server idling at 15 %
    // otherwise draws a flat line along the floor. The top label says where.
    var peak = Math.max.apply(null, hist.cpu.concat(hist.mem, [1]));
    var max = Math.min(100, Math.ceil(peak * 1.1 / 25) * 25);
    var W = 300, H = 64, cpu = pts(hist.cpu, max, W, H), mem = pts(hist.mem, max, W, H);
    var area = cpu.length > 1
      ? '<path class="ags-spark-fill" d="M' + cpu.join(" L") + " L" + W + "," + H + " L" + cpu[0].split(",")[0] + "," + H + ' Z"></path>' +
        '<path class="ags-spark-line" d="M' + cpu.join(" L") + '"></path>'
      : "";
    var memLine = mem.length > 1 ? '<path class="ags-spark-mem" d="M' + mem.join(" L") + '"></path>' : "";
    return '<div class="ags-cpu">' +
      '<div class="ags-cores" style="--n:' + cores.length + '">' + cores.map(function (c, i) {
        return '<i class="' + level(c, 70, 90) + '" style="height:' + clamp(c, 3, 100) + '%" title="thread ' + i + ': ' + c + '%"></i>';
      }).join("") + '</div>' +
      '<div class="ags-spark-wrap"><span class="ags-spark-max">' + max + '%</span>' +
      '<svg class="ags-spark" viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" aria-hidden="true">' +
        '<defs>' +
          '<linearGradient id="ags-spark-g" x1="0" y1="0" x2="0" y2="1">' +
            '<stop offset="0" stop-color="#5fd4a8" stop-opacity=".34"></stop>' +
            '<stop offset="1" stop-color="#5fd4a8" stop-opacity="0"></stop></linearGradient>' +
          '<linearGradient id="ags-spark-s" x1="0" y1="0" x2="1" y2="0">' +
            '<stop offset="0" stop-color="#5fd4a8"></stop><stop offset="1" stop-color="#6cc6e8"></stop></linearGradient>' +
        '</defs>' +
        '<line class="ags-spark-grid" x1="0" x2="' + W + '" y1="' + H / 2 + '" y2="' + H / 2 + '"></line>' +
        area + memLine +
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
      ["uptime", dur(s.uptime)],
      ["load", s.load.map(function (x) { return x.toFixed(2); }).join("  ")],
      ["memory", gib(s.mem.used) + " / " + gib(s.mem.total)],
    ];
    if (s.mem.swap_total) facts.push(["swap", gib(s.mem.swap_used) + " / " + gib(s.mem.swap_total)]);
    if (t.nvme != null) facts.push(["nvme", Math.round(t.nvme) + " °C"]);
    (s.fans || []).forEach(function (f) {
      facts.push([/fan/i.test(f.label) ? f.label : f.label + " fan", f.rpm + " rpm"]);
    });

    paintInto(el,
      '<div class="ags-hero">' +
        '<div class="ags-rings">' +
          ring(s.cpu.total / 100, Math.round(s.cpu.total), "%", "CPU", "hue-cpu", level(s.cpu.total, 70, 90)) +
          ring(memFrac, Math.round(memFrac * 100), "%", "Memory", "hue-mem", level(memFrac * 100, 80, 92)) +
          (t.cpu != null
            ? ring((t.cpu - 25) / 75, Math.round(t.cpu), "°C", "CPU temp", "hue-temp", level(t.cpu, 75, 88))
            : ring(0, "–", "", "CPU temp", "hue-temp", "ok")) +
        '</div>' +
        '<dl class="ags-facts">' + facts.map(function (f) {
          return '<div><dt>' + esc(f[0]) + '</dt><dd>' + esc(f[1]) + '</dd></div>';
        }).join("") + '</dl>' +
      '</div>' +
      chart(s.cpu.cores || []));
  }

  function renderStorage(s) {
    var el = $("ags-storage"); if (!el) return;
    var disks = s.disks || [], pool = s.pool || {};
    var data = disks.filter(function (d) { return d.mount !== "/"; });
    var segs = "";
    data.forEach(function (d, i) {
      if (!d.mounted) return;
      segs += '<div class="ags-seg ags-seg-' + (i % 3) + '" style="flex:' + d.size + '">' +
                '<i style="width:' + (100 * d.used / d.size).toFixed(1) + '%"></i>' +
                '<span>' + esc(d.label.split(" · ")[0]) + '</span><em>' + tb(d.free) + ' free</em></div>';
    });
    var poolPct = pool.mounted && pool.size ? 100 * pool.used / pool.size : 0;
    var known = disks.filter(function (d) { return d.healthy != null; });
    var failing = disks.filter(function (d) { return d.healthy === false; });
    var smart = !s.smart_at ? "SMART not read yet"
      : failing.length ? "SMART: " + failing.map(function (d) { return d.label; }).join(", ") + " FAILING"
      : "SMART passed on " + known.length + " of " + disks.length + " · checked " + ago(s.smart_at);

    paintInto(el,
      '<div class="ags-pool">' +
        '<div class="ags-pool-head">' +
          '<div><div class="ags-big">' + (pool.mounted ? tb(pool.free) : "offline") + '</div>' +
            '<div class="ags-sub">' + (pool.mounted ? "free of " + tb(pool.size) + " · media pool" : "/data/media is not mounted") + '</div></div>' +
          '<div class="ags-pool-pct ' + level(poolPct, 85, 95) + '">' + (pool.mounted ? Math.round(poolPct) + "%" : "–") + '<i>used</i></div>' +
        '</div>' +
        '<div class="ags-segs">' + (segs || '<div class="ags-seg-empty">no data disks mounted</div>') + '</div>' +
      '</div>' +
      '<div class="ags-disks">' + disks.map(function (d) {
        if (!d.mounted) {
          return '<div class="ags-disk bad"><span class="ags-dot bad"></span><div class="ags-disk-main">' +
                 '<div class="ags-disk-name">' + esc(d.label) + '</div>' +
                 '<div class="ags-sub">' + esc(d.mount) + ' · NOT MOUNTED — services needing it are stopped</div></div></div>';
        }
        var pct = 100 * d.used / d.size;
        var health = d.healthy === false ? "bad" : (d.temp != null && d.temp >= 55 ? "warn" : "ok");
        var state = d.state === "standby" ? "asleep" : d.ssd ? "solid state" : d.state === "active" ? "spinning" : "";
        var on = d.hours ? " · " + (d.hours >= 8760 ? (d.hours / 8760).toFixed(1) + " yrs" : Math.round(d.hours / 24) + " days") + " on" : "";
        return '<div class="ags-disk">' +
          '<span class="ags-dot ' + health + (d.state === "standby" ? " asleep" : "") + '" title="' +
            (d.healthy === false ? "SMART: FAILING" : d.healthy ? "SMART: passed" : "SMART: unknown") + '"></span>' +
          '<div class="ags-disk-main">' +
            '<div class="ags-disk-name">' + esc(d.label) + '<span>' + esc(d.mount) + '</span></div>' +
            '<div class="ags-bar ' + level(pct, 85, 95) + '"><i style="width:' + pct.toFixed(1) + '%"></i></div>' +
            '<div class="ags-sub">' + tb(d.used) + ' of ' + tb(d.size) + ' · <b>' + tb(d.free) + ' free</b>' + on + '</div>' +
          '</div>' +
          '<div class="ags-disk-side">' +
            '<b>' + (d.temp != null ? Math.round(d.temp) + "°" : d.state === "standby" ? "zz" : "–") + '</b>' +
            '<span>' + state + '</span>' +
          '</div></div>';
      }).join("") + '</div>' +
      '<div class="ags-foot ' + (failing.length ? "bad" : "") + '">' + esc(smart) + '</div>');
  }

  function renderPlaying(s) {
    var el = $("ags-playing"); if (!el) return;
    var list = s.streams;
    if (list == null) { paintInto(el, '<div class="ags-idle">Jellyfin isn’t answering</div>'); return; }
    if (!list.length) { paintInto(el, '<div class="ags-idle"><i></i>Nothing playing</div>'); return; }
    paintInto(el, list.map(function (p) {
      var tc = p.transcode;
      var badge = p.method === "Transcode" ? '<span class="ags-badge warn">transcode</span>'
        : '<span class="ags-badge ok">' + (p.method === "DirectStream" ? "stream" : "direct") + '</span>';
      var detail = tc ? [tc.video, tc.mbps ? tc.mbps + " Mb/s" : "", tc.hw ? "HW" : "CPU"].filter(Boolean).join(" ") : "";
      var poster = p.poster ? ' style="background-image:url(' + JF + "/Items/" + encodeURIComponent(p.poster) +
        '/Images/Primary?fillHeight=144&amp;quality=85)"' : "";
      return '<div class="ags-play' + (p.paused ? " paused" : "") + '">' +
        '<div class="ags-poster"' + poster + '></div>' +
        '<div class="ags-play-body">' +
          '<div class="ags-play-top"><div class="ags-play-title">' + esc(p.title) + '</div>' + badge + '</div>' +
          '<div class="ags-sub ags-play-sub">' + esc(p.sub) + '</div>' +
          '<div class="ags-bar ok"><i style="width:' + (100 * (p.progress || 0)).toFixed(1) + '%"></i></div>' +
          '<div class="ags-sub ags-play-meta"><span>' + esc(p.user) + ' · ' + esc(p.device) +
            (p.paused ? " · paused" : "") + (detail ? " · " + esc(detail) : "") + '</span>' +
            '<span>' + (p.remaining_s != null ? dur(p.remaining_s) + " left" : "") + '</span></div>' +
        '</div></div>';
    }).join(""));
  }

  function paint(s) {
    if (s.ts !== hist.ts) {
      push(hist.cpu, s.cpu.total);
      push(hist.mem, s.mem.total ? 100 * s.mem.used / s.mem.total : 0);
      hist.ts = s.ts;
    }
    renderHost(s); renderStorage(s); renderPlaying(s);
    var live = $("ags-live"); if (live) { live.className = "ags-live on"; live.textContent = "live"; }
  }

  // ── stream lifecycle ───────────────────────────────────────────────────────
  function connect() {
    clearTimeout(retry);
    if (es) es.close();
    es = new EventSource(API + "/stream");
    // Sent once on connect: the server's last 3 min, so the chart starts full.
    es.addEventListener("history", function (e) {
      try { var h = JSON.parse(e.data); hist.cpu = h.cpu || []; hist.mem = h.mem || []; hist.ts = h.ts; } catch (_) {}
    });
    es.addEventListener("snapshot", function (e) { try { paint(JSON.parse(e.data)); } catch (_) {} });
    es.onerror = function () {
      var live = $("ags-live"); if (live) { live.className = "ags-live off"; live.textContent = "reconnecting"; }
      // EventSource retries a dropped stream itself, but gives up for good on an
      // HTTP error (e.g. the service restarting mid-deploy) — so retry ourselves.
      if (es && es.readyState === 2) { es = null; retry = setTimeout(connect, 3000); }
    };
  }
  function start() {
    if (!$("ags-host") && !$("ags-storage") && !$("ags-playing")) return false;
    connect();
    document.addEventListener("visibilitychange", function () {
      clearTimeout(park);
      if (document.hidden) {
        park = setTimeout(function () { if (es) { es.close(); es = null; } }, 60000);
      } else if (!es) {
        connect();
      }
    });
    return true;
  }
  // Glance injects widget markup after load; wait for it (at most ~10 s).
  var tries = 0;
  (function wait() { if (!start() && ++tries < 50) setTimeout(wait, 200); })();
})();
