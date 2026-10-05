// eclipse.js — the Eclipse panel, drawn natively from eclipse-control's
// /events stream (Resources/Eclipse-Control/eclipse-control.py, :9554).
// SHARED by both dashboards — the admin Glance and MarsBar run this same file,
// so she has every control he has and a fix lands on both:
//
//   admin    <script … data-api-port="9554">   → http://<this host>:9554
//   MarsBar  <script … data-api="/eclipse-api"> → her own origin, through the
//            marsbar node's serve proxy (her ACL never reaches an Asgard port)
//   data-jellyfin  where posters load from (default http://<this host>:8096)
//
// It used to be an iframe of a page that service served (admin) and a 15 s
// poller with three actions (MarsBar); now one stream pushes:
//
//   status    the Pi: Kodi, display, Jellyfin path, link test, SoC temperature,
//             throttle/under-voltage flags, load, memory          (#ec-main)
//   tv        what Jellyfin says the TV is playing                (#ec-tv)
//   wolf      Moonlight streams Wolf is serving on Sisyphus         (#ec-wolf)
//   activity  the last actions from EITHER dashboard              (#ec-log)
//   busy      what is running now — every open page greys it out
//
// The Pi is only polled while a page is watching.
//
// Actions are POST /act/<name> with X-Dash. Reboot, switching the Jellyfin
// path (it restarts Kodi) and ending a stream need a second tap within 3 s.
(function () {
  "use strict";
  var D = window.Dash;
  if (!D) return;
  var me = document.currentScript, cfg = (me && me.dataset) || {};
  var API = cfg.api || D.api(cfg.apiPort || "9554");
  var JF = cfg.jellyfin || D.api("8096");
  var esc = D.esc, $ = D.$;
  var S = { status: null, tv: null, wolf: null, ctl: null, activity: [], busy: {}, armed: null, killing: {}, local: {} };
  var STALE_SECS = 3 * 3600;
  var queued = false;

  var ICON = {
    kodi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 4v5h-5"/></svg>',
    sync: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 8v6"/><path d="m9 11 3 3 3-3"/></svg>',
    link: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20a8 8 0 1 0-8-8"/><path d="m12 12 4-4"/><path d="M4 12H2"/><path d="M12 4V2"/></svg>',
    power: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><path d="M12 2v10"/></svg>',
    stream: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/><path d="m10 8.5 4 2-4 2z"/></svg>',
    stop: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>'
  };
  var SIZES = { "3840x2160": "4K", "2560x1440": "1440p", "1920x1080": "1080p", "1280x720": "720p" };
  function fmtMode(s) {
    var m = /(\d+x\d+)\s*@\s*([\d.]+)/.exec(s || "");
    return m ? (SIZES[m[1]] || m[1].replace("x", "×")) + " · " + Math.round(parseFloat(m[2])) + " Hz" : null;
  }

  // ── main card ─────────────────────────────────────────────────────────────
  function stat(k, v, sub, cls, extra) {
    return '<div class="ec-stat"><span class="ag-k">' + k + '</span><span class="ec-v ' + (cls || "") + '">' + v + '</span>' +
      (extra || "") + '<span class="ags-sub">' + (sub || "&nbsp;") + '</span></div>';
  }
  function anyBusy() { return Object.keys(S.busy).length > 0 || Object.keys(S.local).length > 0; }
  function btn(act, label, icon, sub, cls) {
    var busy = S.busy[act] || S.local[act];
    var armed = S.armed === act;
    return '<button type="button" class="ag-btn ' + (cls || "") + (busy ? " busy" : "") + (armed ? " armed" : "") + '" data-act="' + act + '"' +
      (anyBusy() && !busy ? " disabled" : "") + (busy ? " disabled" : "") + '>' + icon +
      '<span>' + (armed ? "Tap again" : busy ? label + "…" : label) + '</span><small>' + sub + '</small></button>';
  }

  function renderMain() {
    var el = $("ec-main"); if (!el) return;
    var s = S.status;
    if (!s) return;
    if (!s.reachable) {
      D.paint(el, '<div class="ec"><div class="ec-hero"><span class="ec-orb bad"></span><div>' +
        '<div class="ec-title">Eclipse unreachable</div><div class="ec-sub">' + esc(s.error || "no answer over SSH") + '</div></div><div></div></div>' +
        '<div class="ec-actions">' + btn("reboot", "Reboot", ICON.power, "if it answers", "danger") + '</div></div>');
      return;
    }
    var mode = fmtMode(s.mode);
    var jf = s.jellyfin_mode || "unknown";
    var thr = s.throttled || { now: [], since_boot: [] };
    var alerts = "";
    if (s.needs_kodi_restart) alerts += '<div class="ec-alert">⚠ <span>The TV link is up but Kodi isn’t driving it — <b>Restart Kodi</b>.</span></div>';
    if (thr.now.length) alerts += '<div class="ec-alert bad">⚡ <span><b>' + esc(thr.now.join(", ")) + '</b> right now — the Pi is being held back.</span></div>';
    else if (thr.since_boot.indexOf("under-voltage") >= 0) alerts += '<div class="ec-alert">⚡ <span><b>Under-voltage</b> has happened since boot — check the Pi’s power supply.</span></div>';

    var temp = s.temp != null ? Math.round(s.temp) : null;
    var tcls = temp == null ? "" : temp >= 80 ? "bad" : temp >= 70 ? "warn" : "";
    var speed = s.speed_mbps;
    var gauge = speed != null ? '<div class="ec-gauge"><i style="left:' + D.clamp(speed / 200 * 100, 0, 100).toFixed(1) + '%"></i></div>' : "";
    var memPct = s.mem_used != null ? Math.round(s.mem_used * 100) : null;

    D.paint(el,
      '<div class="ec">' +
        '<div class="ec-hero"><span class="ec-orb ok"></span><div>' +
          '<div class="ec-title">Eclipse online</div>' +
          '<div class="ec-sub">up ' + D.dur(s.uptime) + ' · LibreELEC · Pi 5' + (s.load ? ' · load ' + s.load[0].toFixed(2) : '') +
            (memPct != null ? ' · memory ' + memPct + '%' : '') + '</div></div>' +
          '<div class="ec-temp"><b class="' + tcls + '">' + (temp != null ? temp + "°" : "–") + '</b><span>SoC</span></div>' +
        '</div>' +
        alerts +
        '<div class="ec-stats">' +
          stat("Kodi", esc(s.kodi), s.kodi === "active" ? "running" : "not running", s.kodi === "active" ? "ok" : "bad") +
          stat("Display", mode || "no picture", s.hdmi === "connected" ? "HDMI connected" : "HDMI disconnected", mode ? "" : "warn") +
          stat("Jellyfin", jf === "lan" ? "LAN" : jf === "remote" ? "Tailscale" : "unknown",
               jf === "remote" ? "capped ~8 Mb/s" : jf === "lan" ? "uncapped direct play" : "address unrecognised", jf === "unknown" ? "warn" : "") +
          stat("Link", speed != null ? D.mbps(speed) + ' <small class="ag-u">Mb/s</small>' : "untested",
               speed != null ? (s.speed_up_mbps != null ? "↑ " + D.mbps(s.speed_up_mbps) + " · " : "") + (s.speed_path || "") + " · " + D.ago(s.speed_when) : "tap Test link",
               speed == null ? "" : speed >= 50 ? "ok" : speed >= 20 ? "warn" : "bad", gauge) +
        '</div>' +
        '<div class="ec-actions">' +
          btn("restart-kodi", "Restart Kodi", ICON.kodi, "frozen or no picture", "primary" + (s.needs_kodi_restart ? " nudge" : "")) +
          btn("sync-library", "Sync library", ICON.sync, "new films + episodes") +
          btn("speedtest", "Test link", ICON.link, "Pi → Asgard") +
          btn("reboot", "Reboot", ICON.power, "last resort", "danger") +
        '</div>' +
        '<div class="ec-path"><span class="ag-k">Jellyfin path</span>' +
          '<span class="ec-seg">' +
            ["lan", "remote"].map(function (m) {
              var on = jf === m, armed = S.armed === "path:" + m, busy = S.busy["jellyfin-toggle"] || S.local["jellyfin-toggle"];
              return '<button type="button" data-path="' + m + '" class="' + (on ? "on" : "") + (armed ? " armed" : "") + '"' + (busy ? " disabled" : "") + '>' +
                (armed ? "Tap again" : m === "lan" ? "LAN" : "Tailscale") + '</button>';
            }).join("") +
          '</span>' +
          '<span class="ags-sub">' + (jf === "lan" ? "Home network — full quality." : jf === "remote" ? "Over the tailnet — capped so it never stalls." : "") +
            ' Switching restarts Kodi.</span>' +
        '</div>' +
      '</div>');
  }

  // ── Wolf streams ──────────────────────────────────────────────────────────
  function renderWolf() {
    var el = $("ec-wolf"); if (!el) return;
    var w = S.wolf;
    if (!w) return;
    if (w.wolf !== "up") {
      D.paint(el, '<div class="wf-empty down"><i></i>' + (w.wolf === "down" ? "Wolf isn’t running on Sisyphus" : "Sisyphus unreachable") + '</div>');
      return;
    }
    var now = Date.now() / 1000;
    var list = (w.sessions || []).filter(function (x) { return !S.killing[x.id]; });
    if (!list.length) { D.paint(el, '<div class="wf-empty"><i></i>No active streams</div>'); return; }
    D.paint(el, '<div class="wf">' + list.map(function (x) {
      var age = x.started ? now - x.started : 0, stale = age > STALE_SECS, armed = S.armed === "kill:" + x.id;
      return '<div class="wf-row' + (stale ? " stale" : "") + '">' +
        '<div class="wf-ico">' + ICON.stream + '</div>' +
        '<div><div class="wf-app">' + esc(x.app) + (stale ? '<span class="wf-badge">stuck?</span>' : '') + '</div>' +
        '<div class="wf-meta"><b>' + esc(x.client_label || x.client) + '</b>' +
          (x.video ? " · " + esc(x.video.replace("x", "×").replace("@", " @ ") + " Hz") : "") +
          (x.started ? " · streaming " + (age < 60 ? "<1m" : D.dur(age)) : "") + '</div></div>' +
        '<button type="button" class="wf-kill' + (armed ? " armed" : "") + '" data-kill="' + esc(x.id) + '">' + ICON.stop +
          '<span>' + (armed ? "Tap to end" : "End") + '</span></button></div>';
    }).join("") + '</div>');
  }

  // ── on the TV ─────────────────────────────────────────────────────────────
  function renderTv() {
    var el = $("ec-tv"); if (!el || !S.tv) return;
    if (!S.tv.ok) { D.paint(el, '<div class="ags-idle">Jellyfin isn’t answering</div>'); return; }
    var list = S.tv.playing || [];
    if (!list.length) { D.paint(el, '<div class="ags-idle"><i></i>Nothing playing on the TV</div>'); return; }
    D.paint(el, list.map(function (p) {
      var poster = p.poster ? ' style="background-image:url(' + JF + "/Items/" + encodeURIComponent(p.poster) +
        '/Images/Primary?fillHeight=216&amp;quality=85)"' : "";
      return '<div class="ags-play' + (p.paused ? " paused" : "") + '">' +
        '<div class="ags-poster"' + poster + '></div>' +
        '<div class="ags-play-body">' +
          '<div class="ags-play-top"><div class="ags-play-title">' + esc(p.title) + '</div>' +
            (p.method === "Transcode" ? '<span class="ags-badge warn">transcode</span>' : '<span class="ags-badge">direct</span>') + '</div>' +
          '<div class="ags-sub ags-play-sub">' + esc(p.sub) + '</div>' +
          '<div class="ags-bar"><i style="width:' + (100 * (p.progress || 0)).toFixed(1) + '%"></i></div>' +
          '<div class="ags-sub ags-play-meta"><span>' + esc(p.user) + (p.paused ? " · paused" : "") + '</span>' +
            '<span>' + (p.remaining_s != null ? D.dur(p.remaining_s) + " left" : "") + '</span></div>' +
        '</div></div>';
    }).join(""));
  }

  // ── activity ──────────────────────────────────────────────────────────────
  var LABEL = { "restart-kodi": "Restart Kodi", "sync-library": "Sync library", "sync-movies": "Sync movies",
                "sync-shows": "Sync TV shows", "speedtest": "Link test", "reboot": "Reboot Pi", "jellyfin-toggle": "Switch Jellyfin path" };
  function renderLog() {
    var el = $("ec-log"); if (!el) return;
    var running = Object.keys(S.busy).map(function (a) {
      return '<li class="run"><i>●</i><b>' + esc(LABEL[a] || a) + '</b><span>running…</span></li>';
    }).join("");
    var done = (S.activity || []).map(function (e) {
      return '<li class="' + (e.ok ? "" : "bad") + '"><i>' + (e.ok ? "✓" : "✕") + '</i><b>' + esc(e.action) +
        '<em>' + D.ago(e.t) + '</em></b><span>' + esc(e.message) + '</span></li>';
    }).join("");
    D.paint(el, running || done ? '<ul class="lg">' + running + done + '</ul>' : '<div class="lg-empty">Nothing yet — actions from either dashboard show up here.</div>');
  }

  // ── controllers + subtitles ───────────────────────────────────────────────
  // Shown on BOTH dashboards, same as every other card here — she is the one in
  // front of the TV, so she gets every control (Modules/Server/marsbar.nix).
  //
  // The important bit is `live` vs `connected`. BlueZ on this box will report a
  // DualSense as Connected while its kernel driver has failed to bind with -5,
  // leaving a bonded device with ZERO input nodes: it looks connected and does
  // nothing. The backend reports those separately and flags the combination as
  // `stale`; this card calls that out explicitly rather than showing a green
  // dot for a pad that cannot move a cursor.
  function ctlBtn(d) {
    var off = d.live || d.connected;
    var key = (off ? "dis:" : "con:") + d.mac;
    var busy = S.local[key], armed = S.armed === key;
    var label = armed ? "Tap again" : busy ? "…" : off ? "Disconnect" : "Connect";
    return '<button type="button" class="ag-btn tiny' + (armed ? " armed" : "") +
      (busy ? " busy" : "") + '" data-' + (off ? "disconn" : "conn") + '="' + esc(d.mac) + '"' +
      (anyBusy() && !busy ? " disabled" : "") + (busy ? " disabled" : "") +
      '><span>' + label + '</span></button>';
  }

  function renderCtl() {
    var el = $("ec-ctl"); if (!el) return;
    var c = S.ctl; if (!c) return;
    var h = '<div class="ec">';

    if (!c.reachable) {
      h += '<div class="ec-hero"><span class="ec-orb bad"></span><div><b>Eclipse unreachable</b>' +
        '<small>' + esc(c.error || "no answer over SSH") + '</small></div></div></div>';
      D.paint(el, h); return;
    }

    // Controllers
    var devs = c.devices || [];
    h += '<div class="ec-rows">';
    if (!devs.length) {
      h += '<div class="ec-row"><span class="ags-sub">No controllers paired yet</span></div>';
    }
    devs.forEach(function (d) {
      var cls = d.stale ? "warn" : d.live ? "ok" : "";
      var what = d.stale ? "connected but no input — needs re-pairing"
        : d.live ? "connected and working"
          : d.connected ? "connecting…" : "off or out of range";
      h += '<div class="ec-row">' +
        '<span class="ec-orb ' + (d.stale ? "bad" : d.live ? "good" : "") + '"></span>' +
        '<div class="ec-row-main"><b>' + esc(d.name) + '</b><small>' + what + '</small></div>' +
        ctlBtn(d) + '</div>';
    });
    h += '</div>';

    // A DualSense only advertises while physically held in pairing mode, so say
    // so — a Scan button that silently finds nothing reads as broken.
    h += '<div class="ec-btns">' +
      btn("ctl-scan", "Scan", ICON.link, "hold PS + Create first") +
      '</div>';

    // Subtitles — a Jellyfin user setting, not a Kodi one (see eclipse.nix).
    var sb = c.subs;
    if (sb) {
      h += '<div class="ec-rows"><div class="ec-row">' +
        '<div class="ec-row-main"><b>Subtitles</b><small>default ' +
        (sb.on ? "on" : "off") + (sb.lang_name ? " · " + esc(sb.lang_name) : "") + '</small></div>' +
        '<button type="button" class="ag-btn tiny" data-act="' + (sb.on ? "subs-off" : "subs-on") + '"' +
        (anyBusy() ? " disabled" : "") + '><span>' + (sb.on ? "Turn off" : "Turn on") + '</span></button>' +
        '</div></div>';
    }

    // Network path — which link is actually carrying traffic.
    (c.net || []).forEach(function (n) {
      h += '<div class="ec-rows"><div class="ec-row">' +
        '<span class="ec-orb ' + (n.online ? "good" : n.ready ? "good" : "") + '"></span>' +
        '<div class="ec-row-main"><b>' + esc(n.name) + '</b><small>' + n.kind +
        (n.online ? " · online" : n.ready ? " · standby, connected" : " · standby, idle") +
        '</small></div></div></div>';
    });

    h += '</div>';
    D.paint(el, h);
  }

  function render() { queued = false; renderMain(); renderTv(); renderWolf(); renderCtl(); renderLog(); }
  function soon() { if (!queued) { queued = true; requestAnimationFrame(render); } }

  // ── input ─────────────────────────────────────────────────────────────────
  var armTimer = null;
  function arm(key) {
    S.armed = key; soon();
    clearTimeout(armTimer);
    armTimer = setTimeout(function () { if (S.armed === key) { S.armed = null; soon(); } }, 3000);
  }
  function act(name) {
    S.local[name] = true; soon();
    D.post(API + "/act/" + encodeURIComponent(name))
      .catch(function () {})
      .then(function () { delete S.local[name]; soon(); });   // the stream carries the outcome
  }

  function onClick(e) {
    var t = e.target && e.target.closest ? e.target : null;
    if (!t) return;
    var b = t.closest("#ec-main [data-act], #ec-ctl [data-act]");
    if (b && !b.disabled) {
      var name = b.getAttribute("data-act");
      if (name === "reboot" && S.armed !== name) { arm(name); return; }
      S.armed = null;
      act(name);
      return;
    }
    var p = t.closest("#ec-main [data-path]");
    if (p && !p.disabled && !p.classList.contains("on")) {
      var key = "path:" + p.getAttribute("data-path");
      if (S.armed !== key) { arm(key); return; }
      S.armed = null;
      act("jellyfin-toggle");
      return;
    }
    // Controller connect/disconnect. Connect is armed like reboot is, because
    // it has a consequence you cannot see from here: a DualSense only ever
    // talks to ONE host and returns to whichever it used last, so connecting it
    // to Eclipse STEALS it from whoever is gaming on Sisyphus (Claude/streaming.md).
    var cd = t.closest("#ec-ctl [data-conn], #ec-ctl [data-disconn]");
    if (cd && !cd.disabled) {
      var off = cd.hasAttribute("data-disconn");
      var mac = cd.getAttribute(off ? "data-disconn" : "data-conn");
      var ck = (off ? "dis:" : "con:") + mac;
      if (!off && S.armed !== ck) { arm(ck); return; }
      S.armed = null;
      S.local[ck] = true; soon();
      D.post(API + "/ctl/" + (off ? "disconnect" : "connect") + "/" + encodeURIComponent(mac))
        .catch(function () {})
        .then(function () { delete S.local[ck]; soon(); });
      return;
    }
    var k = t.closest("#ec-wolf [data-kill]");
    if (k) {
      var id = k.getAttribute("data-kill"), kk = "kill:" + id;
      if (S.armed !== kk) { arm(kk); return; }
      S.armed = null;
      S.killing[id] = true; soon();                       // optimistic: gone now
      D.post(API + "/wolf/stop/" + encodeURIComponent(id))
        .then(function (j) { if (!(j.ok || j._status === 404)) delete S.killing[id]; })
        .catch(function () { delete S.killing[id]; })
        .then(function () { setTimeout(function () { S.killing = {}; soon(); }, 4000); });
    }
  }

  D.ready("#ec-main, #ec-tv, #ec-wolf, #ec-ctl, #ec-log", function () {
    D.stream(API + "/events", {
      status: function (d) { S.status = d; soon(); },
      tv: function (d) { S.tv = d; soon(); },
      wolf: function (d) { S.wolf = d; soon(); },
      ctl: function (d) { S.ctl = d; soon(); },
      activity: function (d) { S.activity = d; soon(); },
      busy: function (d) { S.busy = d; soon(); }
    }, "ec-live");
    document.addEventListener("click", onClick);
    // relative times ("3m ago") keep moving between events
    setInterval(function () { if (!document.hidden) soon(); }, 30000);
  });
})();
