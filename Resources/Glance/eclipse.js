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
//   ctl       paired Bluetooth devices + our names for them, subtitles,
//             network path                                         (#ec-ctl)
//   scan      a Bluetooth search and what it has found             (#ec-ctl)
//   ctlbusy   which device is pairing / connecting / … right now
//
// Everything Bluetooth lives in eclipse-control, not the page: a name given on
// one dashboard, a search started on her phone, a pad pairing — all of it is
// pushed to every open page, so the admin page and MarsBar always agree.
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
  var S = { status: null, tv: null, wolf: null, ctl: null, scan: null, ctlbusy: {}, activity: [], busy: {},
            armed: null, killing: {}, local: {}, btOpen: {}, btMsg: null, focusName: null, hint: null };
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
                "sync-shows": "Sync TV shows", "speedtest": "Link test", "reboot": "Reboot Pi", "jellyfin-toggle": "Switch Jellyfin path",
                "bt-on": "Turn Bluetooth on", "subs-on": "Subtitles on", "subs-off": "Subtitles off" };
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

  // ── Bluetooth: my devices, adding one, subtitles, network ────────────────
  // Shown on BOTH dashboards, same as every other card here — she is the one in
  // front of the TV, so she gets every control (Modules/Server/marsbar.nix).
  //
  // The important bit is `live` vs `connected`. BlueZ on this box will report a
  // DualSense as Connected while its kernel driver has failed to bind with -5,
  // leaving a bonded device with ZERO input nodes: it looks connected and does
  // nothing. The backend reports those separately and flags the combination as
  // `stale`; this card says so and offers Re-pair (the only fix) rather than
  // showing a green dot for a pad that cannot move a cursor.
  var BT = {
    gamepad: '<path d="M6 11h4M8 9v4M15 12h.01M18 10h.01"/><path d="M17.3 5H6.7a4 4 0 0 0-4 3.6l-.6 6a2.5 2.5 0 0 0 4.8 1.3L8 15h8l1.1 .9a2.5 2.5 0 0 0 4.8-1.3l-.6-6a4 4 0 0 0-4-3.6z"/>',
    audio: '<path d="M3 14v-2a9 9 0 0 1 18 0v2"/><path d="M21 14v4a2 2 0 0 1-2 2h-1v-6h3zM3 14v4a2 2 0 0 0 2 2h1v-6H3z"/>',
    keyboard: '<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/>',
    mouse: '<rect x="6" y="3" width="12" height="18" rx="6"/><path d="M12 7v4"/>',
    remote: '<rect x="8" y="2" width="8" height="20" rx="3"/><circle cx="12" cy="8" r="1.5"/><path d="M12 13h.01M12 16h.01"/>',
    phone: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
    other: '<path d="m7 7 10 10-5 5V2l5 5L7 17"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>'
  };
  var KIND = { gamepad: "controller", audio: "audio", keyboard: "keyboard", mouse: "mouse", remote: "remote", phone: "phone", other: "device" };
  var BUSYWORD = { pairing: "Pairing", connecting: "Connecting", disconnecting: "Disconnecting", forgetting: "Forgetting", saving: "Saving" };
  function ico(k) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (BT[k] || BT.other) + '</svg>';
  }
  function bars(rssi) {
    if (rssi == null) return '<span class="bt-bars" title="signal unknown"><i></i><i></i><i></i></span>';
    var n = rssi >= -60 ? 3 : rssi >= -75 ? 2 : 1;
    return '<span class="bt-bars s' + n + '" title="' + rssi + ' dBm"><i></i><i></i><i></i></span>';
  }
  function cap(w) { return w.charAt(0).toUpperCase() + w.slice(1); }
  function signalWord(rssi) { return rssi == null ? "" : rssi >= -60 ? "strong signal" : rssi >= -75 ? "good signal" : "weak signal"; }
  function battery(d) {
    if (d.battery == null) return "";
    var p = D.clamp(d.battery, 0, 100), low = p <= 20;
    return '<span class="bt-bat' + (low ? " low" : "") + (d.charging ? " chg" : "") + '" title="battery">' +
      '<i style="--p:' + p + '%"></i>' + p + '%' + (d.charging ? " ⚡" : "") + '</span>';
  }

  function devRow(d) {
    var busy = S.ctlbusy[d.mac];
    var st, cls;
    if (busy) { st = (BUSYWORD[busy] || busy) + "…"; cls = "busy"; }
    else if (d.stale) { st = "Connected, but no input — re-pair it"; cls = "bad"; }
    else if (d.live) { st = "Connected · working"; cls = "ok"; }
    else { st = "Not connected" + (d.trusted ? " · switch it on to connect" : ""); cls = "off"; }
    var key, label, attr, extra = "";
    if (d.stale) { key = "repair:" + d.mac; attr = "data-bt-repair"; label = "Re-pair"; extra = " warn"; }
    else if (d.live || d.connected) { key = "dis:" + d.mac; attr = "data-bt-disconn"; label = "Disconnect"; }
    else { key = "con:" + d.mac; attr = "data-bt-conn"; label = "Connect"; extra = " go"; }
    var armed = S.armed === key;
    var act = '<button type="button" class="bt-btn' + extra + (armed ? " armed" : "") + '" ' + attr + '="' + esc(d.mac) + '"' +
      (busy ? " disabled" : "") + '>' + (busy ? '<i class="bt-spin"></i>' : "") + (armed ? "Tap to confirm" : label) + '</button>';
    var trustBusy = busy === "saving";
    var forgetKey = "forget:" + d.mac, fArmed = S.armed === forgetKey;
    var repairKey = "repair:" + d.mac, rArmed = S.armed === repairKey;
    return '<details class="bt-dev ' + cls + '" data-bt="' + esc(d.mac) + '"' + (S.btOpen[d.mac] ? " open" : "") + '>' +
      '<summary class="bt-sum">' +
        '<span class="bt-ico">' + ico(d.kind) + '</span>' +
        '<span class="bt-main"><b class="bt-name">' + esc(d.name) + '</b>' +
          '<span class="bt-state"><i class="bt-dot"></i>' + esc(st) + battery(d) + '</span></span>' +
        act + '<i class="bt-chev" aria-hidden="true"></i>' +
      '</summary>' +
      '<div class="bt-more">' +
        '<label class="bt-field"><span>Name</span>' +
          '<span class="bt-inrow"><input class="bt-input" type="text" maxlength="24" autocomplete="off" enterkeyhint="done" spellcheck="false" ' +
            'data-bt-name="' + esc(d.mac) + '" value="' + esc(d.custom ? d.name : "") + '" placeholder="e.g. Rock’s pad">' +
          '<button type="button" class="bt-btn" data-bt-save="' + esc(d.mac) + '"' + (busy ? " disabled" : "") + '>Save</button></span>' +
          '<small>' + (d.custom ? "Its own name: " + esc(d.model) : "Give it a name so you know whose it is") + '</small></label>' +
        '<div class="bt-line"><span><b>Auto-connect</b><small>' +
          (d.trusted ? "Switch it on and it connects by itself" : "Off — it only connects when you tap Connect") + '</small></span>' +
          '<button type="button" role="switch" aria-checked="' + d.trusted + '" class="bt-switch' + (d.trusted ? " on" : "") + '" data-bt-trust="' + esc(d.mac) + '"' +
            (busy && !trustBusy ? " disabled" : "") + (trustBusy ? " disabled" : "") + ' aria-label="Auto-connect"><i></i></button></div>' +
        '<div class="bt-line"><span><b>' + esc(cap(KIND[d.kind] || "device")) + '</b><small>' + esc(d.model) + ' · ' + esc(d.mac) + '</small></span>' +
          '<span class="bt-pair">' +
            (d.stale ? "" : '<button type="button" class="bt-btn' + (rArmed ? " armed" : "") + '" data-bt-repair="' + esc(d.mac) + '"' + (busy ? " disabled" : "") + '>' + (rArmed ? "Tap to confirm" : "Re-pair") + '</button>') +
            '<button type="button" class="bt-btn danger' + (fArmed ? " armed" : "") + '" data-bt-forget="' + esc(d.mac) + '"' + (busy ? " disabled" : "") + '>' + (fArmed ? "Tap to forget" : "Forget") + '</button>' +
          '</span></div>' +
      '</div></details>';
  }

  function foundRow(f) {
    var busy = S.ctlbusy[f.mac];
    return '<div class="bt-found' + (busy ? " busy" : "") + '">' +
      '<span class="bt-ico">' + ico(f.kind) + '</span>' +
      '<span class="bt-main"><b class="bt-name">' + esc(f.name) + '</b>' +
        '<span class="bt-state">' + esc(KIND[f.kind] || "device") + (f.rssi != null ? " · " + signalWord(f.rssi) : "") + '</span></span>' +
      bars(f.rssi) +
      '<button type="button" class="bt-btn go" data-bt-pair="' + esc(f.mac) + '"' + (busy ? " disabled" : "") + '>' +
        (busy ? '<i class="bt-spin"></i>Pairing…' : "Pair") + '</button></div>';
  }

  function addSection(c) {
    var sc = S.scan || { active: false, found: [] };
    var now = Date.now() / 1000;
    var h = '<div class="ag-sec">Add a device</div>';
    if (sc.active) {
      var left = Math.max(0, Math.round((sc.ends || now) - now));
      var total = 45, pct = D.clamp(100 * left / Math.max(total, left), 0, 100);
      h += '<div class="bt-scan on"><span class="bt-radar"><i></i>' + ico("search") + '</span>' +
        '<span class="bt-main"><b>Searching… <span class="bt-left">' + left + 's</span></b>' +
          '<span class="bt-state">' + esc(S.hint || "Put it in pairing mode — it appears below") + '</span></span>' +
        '<button type="button" class="bt-btn" data-bt-stop>Stop</button>' +
        '<span class="bt-prog"><i style="width:' + pct.toFixed(1) + '%"></i></span></div>';
    } else {
      h += '<button type="button" class="bt-scan" data-bt-scan' + (c.bt_powered === false ? " disabled" : "") + '>' +
        '<span class="bt-radar">' + ico("search") + '</span>' +
        '<span class="bt-main"><b>' + (sc.ended ? "Search again" : "Search for devices") + '</b>' +
          '<span class="bt-state">' + (sc.ended ? "Last search found " + (sc.found || []).length + " — still pairable below" : "Controllers, headphones, keyboards near the TV") + '</span></span>' +
        '<i class="bt-chev go" aria-hidden="true"></i></button>';
    }
    var found = sc.found || [];
    if (found.length) {
      h += '<div class="bt-list">' + found.map(foundRow).join("") + '</div>';
    } else if (sc.active) {
      h += '<div class="bt-empty">Nothing yet — make sure it’s flashing (pairing mode) and close to the TV.</div>';
    }
    if (sc.unnamed) h += '<div class="bt-note">+ ' + sc.unnamed + ' nearby device' + (sc.unnamed > 1 ? "s" : "") + ' without a name, hidden</div>';
    // A DualSense only advertises while physically held in pairing mode, so
    // say how — a search that finds nothing otherwise reads as broken.
    h += '<details class="bt-howto"' + (S.btOpen.howto ? " open" : "") + ' data-bt="howto"><summary>How to put a controller in pairing mode</summary><ul>' +
      '<li><b>PlayStation (DualSense)</b> hold <b>Create</b> + <b>PS</b> until the light bar flashes quickly</li>' +
      '<li><b>Xbox</b> turn it on, then hold the <b>pair</b> button on top until the X flashes fast</li>' +
      '<li><b>Switch Pro</b> hold the small <b>sync</b> button on top</li>' +
      '<li><b>8BitDo</b> hold <b>pair</b> for 3 seconds</li>' +
      '<li>Headphones and others: usually hold the power button — see its manual</li></ul>' +
      '<small>Pairing a pad here takes it off Sisyphus: a controller only talks to the last thing it paired with.</small></details>';
    return h;
  }

  function renderCtl() {
    var el = $("ec-ctl"); if (!el) return;
    var c = S.ctl; if (!c) return;
    // Don't repaint under someone typing a name: their text, cursor and the
    // phone's keyboard would be thrown away. It paints on blur instead.
    var ae = document.activeElement;
    if (ae && ae.classList && ae.classList.contains("bt-input") && el.contains(ae)) return;

    if (!c.reachable) {
      D.paint(el, '<div class="ec"><div class="ec-hero"><span class="ec-orb bad"></span><div><div class="ec-title">Eclipse unreachable</div>' +
        '<div class="ec-sub">' + esc(c.error || "no answer over SSH") + '</div></div><div></div></div></div>');
      return;
    }
    var devs = c.devices || [];
    var on = devs.filter(function (d) { return d.live; }).length;
    var h = '<div class="ec bt">';
    if (S.btMsg) h += '<div class="bt-msg' + (S.btMsg.bad ? " bad" : "") + '">' + (S.btMsg.bad ? "✕ " : "✓ ") + esc(S.btMsg.text) + '</div>';
    if (c.bt_powered === false) {
      h += '<div class="ec-alert bt-off"><span>Bluetooth is <b>off</b> on Eclipse — nothing can connect.</span>' +
        '<button type="button" class="bt-btn go" data-act="bt-on"' + (S.busy["bt-on"] || S.local["bt-on"] ? " disabled" : "") + '>Turn on</button></div>';
    }

    h += '<div class="ag-sec">My devices<span class="ag-sec-end">' + (devs.length ? devs.length + " paired · " + on + " connected" : "none yet") + '</span></div>';
    if (!devs.length) h += '<div class="bt-empty">Nothing paired yet — search below to add a controller.</div>';
    else h += '<div class="bt-list">' + devs.map(devRow).join("") + '</div>';

    h += addSection(c);

    // Subtitles — a Jellyfin user setting, not a Kodi one (see eclipse.nix).
    var sb = c.subs;
    if (sb) {
      h += '<div class="ag-sec">Subtitles</div><div class="bt-line solo"><span><b>On by default</b><small>' +
        (sb.on ? "Subtitles show on everything" : "Only when the film itself asks for them") + (sb.lang_name ? " · " + esc(sb.lang_name) : "") + '</small></span>' +
        '<button type="button" role="switch" aria-checked="' + !!sb.on + '" class="bt-switch' + (sb.on ? " on" : "") + '" data-act="' + (sb.on ? "subs-off" : "subs-on") + '"' +
        (S.busy["subs-on"] || S.busy["subs-off"] || S.local["subs-on"] || S.local["subs-off"] ? " disabled" : "") + ' aria-label="Subtitles on by default"><i></i></button></div>';
    }

    // Network path — which link is actually carrying traffic.
    if ((c.net || []).length) {
      h += '<div class="ag-sec">Network</div><div class="bt-list">' + c.net.map(function (n) {
        return '<div class="bt-line solo"><span><b><i class="bt-dot ' + (n.online || n.ready ? "ok" : "") + '"></i>' + esc(n.name) + '</b><small>' +
          (n.kind === "ethernet" ? "wired" : n.kind) + (n.online ? " · carrying traffic" : n.ready ? " · standby, connected" : " · standby, idle") +
          '</small></span></div>';
      }).join("") + '</div>';
    }
    h += '</div>';
    D.paint(el, h);
    if (S.focusName) {
      var inp = el.querySelector('[data-bt-name="' + S.focusName + '"]');
      if (inp) { S.focusName = null; inp.focus(); inp.select(); }   // typing replaces any name it kept
    }
  }

  // A result line at the top of the card for a few seconds — the activity log
  // has it too, but on a phone that card is a long scroll away.
  var msgTimer = null;
  function btSay(j, okText) {
    var bad = !(j && j.ok);
    var text = bad ? (j && (j.error || j.message)) || "no answer from Eclipse" : (okText || (j && j.message) || "done");
    S.btMsg = { bad: bad, text: text };
    clearTimeout(msgTimer);
    msgTimer = setTimeout(function () { S.btMsg = null; soon(); }, bad ? 9000 : 5000);
    soon();
    return j;
  }
  function btPost(path) {
    return D.post(API + "/ctl/" + path).catch(function () { return { ok: false, error: "couldn’t reach eclipse-control" }; });
  }
  function saveName(mac) {
    var inp = document.querySelector('#ec-ctl [data-bt-name="' + mac + '"]');
    if (!inp) return;
    var v = inp.value.trim();
    inp.blur();
    btPost("rename/" + encodeURIComponent(mac) + "?name=" + encodeURIComponent(v)).then(function (j) { btSay(j); });
  }

  function render() { queued = false; renderMain(); renderTv(); renderWolf(); renderCtl(); renderLog(); }
  // The search countdown moves every second while one runs.
  setInterval(function () { if (S.scan && S.scan.active && !document.hidden) renderCtl(); }, 1000);
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
    if (b && b.closest("summary")) e.preventDefault();
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
    // Bluetooth. Connect is armed like reboot is, because it has a consequence
    // you cannot see from here: a DualSense only ever talks to ONE host and
    // returns to whichever it used last, so connecting it to Eclipse STEALS it
    // from whoever is gaming on Sisyphus (Claude/streaming.md). Forget and
    // Re-pair are armed too. Buttons inside a row's <summary> must not also
    // open/close the row.
    var bt = t.closest("#ec-ctl [data-bt-conn], #ec-ctl [data-bt-disconn], #ec-ctl [data-bt-pair], #ec-ctl [data-bt-forget]," +
      " #ec-ctl [data-bt-repair], #ec-ctl [data-bt-trust], #ec-ctl [data-bt-save], #ec-ctl [data-bt-scan], #ec-ctl [data-bt-stop]");
    if (bt) {
      e.preventDefault();
      if (bt.disabled) return;
      var mac;
      if (bt.hasAttribute("data-bt-scan")) { S.hint = null; btPost("scan").then(function (j) { if (!j.ok) btSay(j); }); return; }
      if (bt.hasAttribute("data-bt-stop")) { btPost("scan/stop"); return; }
      if ((mac = bt.getAttribute("data-bt-save"))) { saveName(mac); return; }
      if ((mac = bt.getAttribute("data-bt-trust"))) {
        btPost((bt.classList.contains("on") ? "untrust/" : "trust/") + encodeURIComponent(mac)).then(function (j) { btSay(j); });
        return;
      }
      if ((mac = bt.getAttribute("data-bt-pair"))) {
        btPost("pair/" + encodeURIComponent(mac)).then(function (j) {
          btSay(j);
          // Paired: open it and put the cursor in its name, so it gets one.
          if (j.ok) { S.btOpen[mac] = true; S.focusName = mac; soon(); }
        });
        return;
      }
      if ((mac = bt.getAttribute("data-bt-forget"))) {
        if (S.armed !== "forget:" + mac) { arm("forget:" + mac); return; }
        S.armed = null;
        btPost("forget/" + encodeURIComponent(mac)).then(function (j) { btSay(j); });
        return;
      }
      if ((mac = bt.getAttribute("data-bt-repair"))) {
        // The -5 fix: forget it, then search, with the pad in pairing mode.
        if (S.armed !== "repair:" + mac) { arm("repair:" + mac); return; }
        S.armed = null;
        var who = (S.ctl && (S.ctl.devices || []).filter(function (d) { return d.mac === mac; })[0] || {}).name || "it";
        btPost("forget/" + encodeURIComponent(mac)).then(function (j) {
          if (!j.ok) { btSay(j); return; }
          S.hint = "Now hold Create + PS on " + who + " until it flashes, then tap Pair";
          btPost("scan").then(function (j2) { if (!j2.ok) btSay(j2); });
        });
        return;
      }
      var off = bt.hasAttribute("data-bt-disconn");
      mac = bt.getAttribute(off ? "data-bt-disconn" : "data-bt-conn");
      var ck = (off ? "dis:" : "con:") + mac;
      if (!off && S.armed !== ck) { arm(ck); return; }
      S.armed = null;
      btPost((off ? "disconnect/" : "connect/") + encodeURIComponent(mac)).then(function (j) { btSay(j); });
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
      scan: function (d) { S.scan = d; if (!d.active && !(d.found || []).length) S.hint = null; soon(); },
      ctlbusy: function (d) { S.ctlbusy = d || {}; soon(); },
      activity: function (d) { S.activity = d; soon(); },
      busy: function (d) { S.busy = d; soon(); }
    }, "ec-live");
    document.addEventListener("click", onClick);
    // Which device rows are open survives the repaints (the morph mirrors the
    // rendered `open`, so the page has to remember it).
    document.addEventListener("toggle", function (e) {
      var d = e.target;
      if (d && d.matches && d.matches("#ec-ctl details[data-bt]")) S.btOpen[d.getAttribute("data-bt")] = d.open;
    }, true);
    // Names: Enter saves, Esc puts it back; leaving the field lets the card
    // repaint again (renderCtl holds off while it has focus).
    document.addEventListener("keydown", function (e) {
      var i = e.target;
      if (!i || !i.classList || !i.classList.contains("bt-input")) return;
      if (e.key === "Enter") { e.preventDefault(); saveName(i.getAttribute("data-bt-name")); }
      else if (e.key === "Escape") { i.value = i.defaultValue; i.blur(); }
    });
    document.addEventListener("focusout", function (e) {
      if (e.target && e.target.classList && e.target.classList.contains("bt-input")) setTimeout(soon, 0);
    });
    // relative times ("3m ago") keep moving between events
    setInterval(function () { if (!document.hidden) soon(); }, 30000);
  });
})();
