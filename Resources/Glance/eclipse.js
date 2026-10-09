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
//   net       the cable, Wi-Fi saved and in range, wired-only or not  (#ec-net)
//   netscan   a Wi-Fi search running
//   netsw     a cable ⇄ Wi-Fi switch in flight, until the Pi reports back
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
            armed: null, killing: {}, local: {}, btOpen: {}, btMsg: null, focusName: null, hint: null,
            net: null, netscan: null, netsw: null, netOpen: {}, netMsg: null, netJoin: null, netPass: "",
            netShow: false, netFocus: false, logOpen: false };
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
  // Folds away (remembered in this browser, folded to start with): folded, its
  // header is the latest entry — or what is running now — so a glance still
  // says what last happened.
  var LOGK = "eclipse-log";
  try { S.logOpen = localStorage.getItem(LOGK) === "open"; } catch (e) { /* private window */ }
  function renderLog() {
    var el = $("ec-log"); if (!el) return;
    var busy = Object.keys(S.busy), acts = S.activity || [];
    var running = busy.map(function (a) {
      return '<li class="run"><i>●</i><b>' + esc(LABEL[a] || a) + '</b><span>running…</span></li>';
    }).join("");
    var done = acts.map(function (e) {
      return '<li class="' + (e.ok ? "" : "bad") + '"><i>' + (e.ok ? "✓" : "✕") + '</i><b>' + esc(e.action) +
        '<em>' + D.ago(e.t) + '</em></b><span>' + esc(e.message) + '</span></li>';
    }).join("");
    if (!running && !done) { D.paint(el, '<div class="lg-empty">Nothing yet — actions from either dashboard show up here.</div>'); return; }
    var top = busy.length ? '<i class="lg-i run">●</i><span class="bt-main"><b>' + esc(LABEL[busy[0]] || busy[0]) + '</b><span class="bt-state">running…</span></span>'
      : '<i class="lg-i' + (acts[0].ok ? "" : " bad") + '">' + (acts[0].ok ? "✓" : "✕") + '</i><span class="bt-main"><b>' + esc(acts[0].action) +
        '<em>' + D.ago(acts[0].t) + '</em></b><span class="bt-state">' + esc(acts[0].message) + '</span></span>';
    var n = busy.length + acts.length;
    D.paint(el, '<details class="lg-fold" data-lg' + (S.logOpen ? " open" : "") + '>' +
      '<summary class="bt-rsum lg-sum">' + (S.logOpen ? '<span class="bt-main"><b>Last ' + n + '</b><span class="bt-state">from either dashboard, newest first</span></span>' : top) +
        '<span class="lg-n">' + n + '</span><span class="bt-rhint" aria-hidden="true"></span><i class="bt-chev" aria-hidden="true"></i></summary>' +
      '<ul class="lg">' + running + done + '</ul></details>');
  }

  // ── Bluetooth: my devices, adding one, subtitles ─────────────────────────
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

  // Search results open or folded: S.btOpen.results, kept in this browser so a
  // fold survives a reload.
  var RES = "eclipse-bt-results";
  try { if (localStorage.getItem(RES) === "folded") S.btOpen.results = false; } catch (e) { /* private window */ }
  function results(open) {
    S.btOpen.results = open;
    try { if (open) localStorage.removeItem(RES); else localStorage.setItem(RES, "folded"); } catch (e) { /* private window */ }
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
    // What the search found folds away: a new search opens it, a pair closes
    // it (the device is up in My devices now), and a tap on its header hides
    // or shows it any time — remembered in this browser. My devices above
    // never folds.
    var found = sc.found || [];
    if (found.length || sc.active || sc.unnamed) {
      var n = found.length;
      var what = sc.active ? (n ? n + " found so far" : "Looking…") : "Found " + n + " device" + (n === 1 ? "" : "s");
      h += '<details class="bt-results" data-bt="results"' + (S.btOpen.results !== false ? " open" : "") + '>' +
        '<summary class="bt-rsum"><span class="bt-main"><b>' + what + '</b>' +
          (sc.unnamed ? '<span class="bt-state">+ ' + sc.unnamed + ' without a name, hidden</span>' : "") + '</span>' +
          '<span class="bt-rhint" aria-hidden="true"></span><i class="bt-chev" aria-hidden="true"></i></summary>';
      if (n) h += '<div class="bt-list">' + found.map(foundRow).join("") + '</div>';
      else if (sc.active) h += '<div class="bt-empty">Nothing yet — make sure it’s flashing (pairing mode) and close to the TV.</div>';
      h += '</details>';
    }
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

  // ── Network: the cable, Wi-Fi, switching (#ec-net) ────────────────────────
  // Wired only is the house rule (Resources/Eclipse-Box/network/): the Pi once
  // sent a 4K game stream over its own weak radio while the cable sat idle. So
  // Wired means wired ONLY — no saved Wi-Fi joins by itself, even if the cable
  // comes out — and Wi-Fi is a deliberate switch, for taking the box somewhere
  // else: saved networks then rejoin by themselves (a cable still wins).
  //
  // Every switch runs on the Pi, detached (eclipse-net.sh), because the link
  // this page reaches it over is the one changing: the card says "Switching…"
  // until the Pi reports back, and the Pi puts things back by itself if it
  // can't get online. Joining a new network sends its password in the POST
  // body; it never goes in a URL, and the field is cleared once it's sent.
  var NI = {
    wifi: '<path d="M2 8.8a15 15 0 0 1 20 0"/><path d="M5 12.3a10 10 0 0 1 14 0"/><path d="M8.5 15.8a5 5 0 0 1 7 0"/><circle cx="12" cy="19.3" r="1.1"/>',
    cable: '<path d="M8 2v4M16 2v4"/><rect x="5" y="6" width="14" height="7" rx="2"/><path d="M9 13v3a3 3 0 0 0 6 0v-3M12 19v3"/>',
    off: '<path d="M2 8.8a15 15 0 0 1 4.5-2.9M10.5 4.6A15 15 0 0 1 22 8.8"/><path d="M8.5 15.8a5 5 0 0 1 7 0"/><path d="m3 3 18 18"/>',
    lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'
  };
  function nico(k) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (NI[k] || NI.wifi) + '</svg>';
  }
  // connman's Strength is 0-100.
  function nlevel(s) { return s == null ? 0 : s >= 65 ? 3 : s >= 40 ? 2 : 1; }
  function nbars(s) {
    var n = nlevel(s);
    return '<span class="bt-bars' + (n ? " s" + n : "") + '" title="' + (s == null ? "signal unknown" : "signal " + s + "%") + '"><i></i><i></i><i></i></span>';
  }
  function nword(s) { var n = nlevel(s); return n === 3 ? "strong signal" : n === 2 ? "good signal" : n === 1 ? "weak signal" : ""; }
  var SECWORD = { psk: "Secured", sae: "Secured", wep: "Secured (old WEP)", none: "Open", ieee8021x: "Work/uni login" };

  var NRES = "eclipse-net-results";
  try { if (localStorage.getItem(NRES) === "folded") S.netOpen.results = false; } catch (e) { /* private window */ }
  function nresults(open) {
    S.netOpen.results = open;
    try { if (open) localStorage.removeItem(NRES); else localStorage.setItem(NRES, "folded"); } catch (e) { /* private window */ }
  }

  function savedRow(n, u, locked) {
    var on = u && u.id === n.id;
    var st = on ? "Connected" + (n.strength != null ? " · " + nword(n.strength) : "")
      : n.in_range ? "In range · " + (nword(n.strength) || "signal unknown") : "Not in range";
    if (!on && n.auto) st += " · joins by itself";
    var cls = on ? "ok" : n.in_range ? "" : "off";
    var jk = "join:" + n.id, armed = S.armed === jk;
    var act = on ? '<span class="nt-chip">On</span>'
      : n.in_range && n.joinable ? '<button type="button" class="bt-btn go' + (armed ? " armed" : "") + '" data-net-join="' + esc(n.id) + '"' + (locked ? " disabled" : "") + '>' + (armed ? "Tap to switch" : "Join") + '</button>'
      : "";
    var fk = "nforget:" + n.id, fArmed = S.armed === fk;
    return '<details class="bt-dev nt-net ' + cls + '" data-net="' + esc(n.id) + '"' + (S.netOpen[n.id] ? " open" : "") + '>' +
      '<summary class="bt-sum">' +
        '<span class="bt-ico">' + nico("wifi") + '</span>' +
        '<span class="bt-main"><b class="bt-name">' + esc(n.name) + '</b>' +
          '<span class="bt-state"><i class="bt-dot"></i>' + esc(st) + '</span></span>' +
        (n.in_range ? nbars(n.strength) : "") + act + '<i class="bt-chev" aria-hidden="true"></i>' +
      '</summary>' +
      '<div class="bt-more">' +
        '<div class="bt-line"><span><b>Joins by itself</b><small>' +
          (n.auto ? "Yes — Eclipse is in Wi-Fi mode, so every saved network does" : "No — wired only: no saved Wi-Fi joins on its own") +
          '</small></span></div>' +
        '<div class="bt-line"><span><b>' + esc(SECWORD[n.security] || "Wi-Fi") + '</b><small>' +
          (n.secure ? "Password saved on Eclipse · " : "") + esc(n.id) + '</small></span>' +
          '<span class="bt-pair"><button type="button" class="bt-btn danger' + (fArmed ? " armed" : "") + '" data-net-forget="' + esc(n.id) + '"' +
            (on || locked ? " disabled" : "") + '>' + (fArmed ? "Tap to forget" : "Forget") + '</button></span></div>' +
        (on ? '<small class="bt-note">It’s the network Eclipse is on — switch to the cable or another network to forget it.</small>' : "") +
      '</div></details>';
  }

  function foundNet(n, u, locked) {
    var sec = SECWORD[n.security] || "Wi-Fi";
    var line = sec + (n.strength != null ? " · " + nword(n.strength) : "");
    if (!n.joinable) {
      return '<div class="bt-found nt-found off"><span class="bt-ico">' + nico("wifi") + '</span>' +
        '<span class="bt-main"><b class="bt-name">' + esc(n.name) + '</b><span class="bt-state">' + esc(sec) + ' — use LibreELEC’s settings on the TV</span></span>' +
        nbars(n.strength) + '<span></span></div>';
    }
    if (S.netJoin === n.id) {
      var back = u ? (u.kind === "wired" ? "the cable" : u.name) : "how it was";
      return '<div class="bt-found nt-found nt-join"><span class="bt-ico">' + nico("wifi") + '</span>' +
        '<span class="bt-main"><b class="bt-name">' + esc(n.name) + '</b><span class="bt-state">' + esc(line) + '</span></span>' +
        nbars(n.strength) + '<span></span>' +
        '<div class="nt-form">' +
          '<span class="nt-pw"><input class="bt-input nt-pass" type="' + (S.netShow ? "text" : "password") + '" data-net-pass="' + esc(n.id) + '" ' +
            'placeholder="Wi-Fi password" maxlength="64" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" enterkeyhint="go">' +
          '<button type="button" class="nt-eye" data-net-eye aria-label="' + (S.netShow ? "Hide" : "Show") + ' password">' + (S.netShow ? "Hide" : "Show") + '</button></span>' +
          '<button type="button" class="bt-btn go" data-net-go="' + esc(n.id) + '"' + (locked ? " disabled" : "") + '>Join</button>' +
          '<button type="button" class="bt-btn" data-net-cancel>Cancel</button>' +
          '<small>Eclipse moves to ' + esc(n.name) + ' to try it — it drops off here for up to a minute. If it can’t get online it goes back to ' +
            esc(back) + ' by itself, and the password isn’t kept.</small>' +
        '</div></div>';
    }
    var k = "open:" + n.id, armed = S.armed === k;
    return '<div class="bt-found nt-found"><span class="bt-ico">' + nico("wifi") + '</span>' +
      '<span class="bt-main"><b class="bt-name">' + esc(n.name) + '</b><span class="bt-state">' +
        (n.secure ? '<i class="nt-lock">' + nico("lock") + '</i>' : "") + esc(line) + '</span></span>' +
      nbars(n.strength) +
      '<button type="button" class="bt-btn go' + (armed ? " armed" : "") + '" data-net-new="' + esc(n.id) + '"' + (locked ? " disabled" : "") + '>' +
        (armed ? "Tap to join" : "Join") + '</button></div>';
  }

  // What it's on now, the Wired | Wi-Fi switch, and anything worth knowing.
  function netTop(c, u, kind, locked) {
    var h = "";
    // ── what it's on now
    var title = !u ? "Not connected" : kind === "wired" ? "On the cable" : "On Wi-Fi · " + esc(u.name);
    var sub = !u ? "No cable and no Wi-Fi" :
      kind === "wired" ? (c.wired_only ? "Wired only — Wi-Fi never joins by itself" : "Wired · a saved Wi-Fi can join if the cable comes out") :
      (nword(u.strength) ? cap(nword(u.strength)) + " · " : "") + "saved networks rejoin by themselves";
    h += '<div class="nt-now ' + kind + '"><span class="bt-ico">' + nico(kind === "wired" ? "cable" : kind === "wifi" ? "wifi" : "off") + '</span>' +
      '<span class="bt-main"><b class="bt-name">' + title + '</b><span class="bt-state">' + esc(sub) + '</span></span>' +
      (kind === "wifi" ? nbars(u.strength) : "") +
      '<span class="nt-where ' + (c.home ? "home" : "away") + '" title="' + (c.home ? "Asgard answers on the house LAN" : "Asgard isn’t on this network") + '">' +
        (c.home ? "Home" : "Away") + '</span></div>';

    // ── the switch
    var bestSaved = (c.saved || []).filter(function (n) { return n.in_range && n.joinable; })[0];
    h += '<div class="ec-path nt-mode"><span class="ag-k">Connection</span><span class="ec-seg">' +
      ["wired", "wifi"].map(function (m) {
        var on = kind === m && (m !== "wired" || c.wired_only);
        var armed = S.armed === "mode:" + m;
        var dis = locked || (m === "wired" && !c.cable);
        return '<button type="button" data-net-mode="' + m + '" class="' + (kind === m ? "on" : "") + (armed ? " armed" : "") + '"' +
          (dis || on ? " disabled" : "") + '>' + (armed ? "Tap again" : m === "wired" ? "Wired" : "Wi-Fi") + '</button>';
      }).join("") + '</span><span class="ags-sub">' +
      (kind === "wired" && c.wired_only ? "The house setting: full speed, and nothing swaps to Wi-Fi behind your back. Taking Eclipse out? Switch to Wi-Fi first." :
       kind === "wired" ? "Tap <b>Wired</b> to lock it to the cable again (no saved Wi-Fi joins by itself)." :
       kind === "wifi" ? (c.cable ? "A cable is plugged in — tap <b>Wired</b> to use it (it’s much faster)." : "No cable in. Back home? Plug it in, then tap <b>Wired</b>.") :
       c.cable ? "Tap <b>Wired</b> to use the cable." : "Plug in a cable, or join a Wi-Fi network below.") +
      (!bestSaved && kind !== "wifi" ? " No saved Wi-Fi in range — search below." : "") + '</span></div>';

    // ── things worth knowing
    if (!c.sct) {
      h += '<div class="ec-alert">⚠ <span>The one-link rule is missing on the Pi (a re-flash?), so cable and Wi-Fi can both be up at once — ' +
        'the 9 Oct lag. ' + (c.cable ? "Tap <b>Wired</b> to put it back." : "Plug in a cable and tap <b>Wired</b> to put it back.") + '</span></div>';
    }
    var jf = S.status && S.status.jellyfin_mode;
    if (!c.home && u && jf === "lan") {
      var ja = S.armed === "net-jf";
      h += '<div class="ec-alert nt-jf"><span>Away from the house, Jellyfin’s <b>LAN</b> path can’t load anything — use <b>Tailscale</b>. Switching restarts Kodi.</span>' +
        '<button type="button" class="bt-btn go' + (ja ? " armed" : "") + '" data-net-jf' + (S.busy["jellyfin-toggle"] ? " disabled" : "") + '>' + (ja ? "Tap again" : "Use Tailscale") + '</button></div>';
    } else if (c.home && kind === "wired" && jf === "remote") {
      var jb = S.armed === "net-jf";
      h += '<div class="ec-alert nt-jf ok"><span>Home on the cable, but Jellyfin is still on the capped <b>Tailscale</b> path. Switching restarts Kodi.</span>' +
        '<button type="button" class="bt-btn go' + (jb ? " armed" : "") + '" data-net-jf' + (S.busy["jellyfin-toggle"] ? " disabled" : "") + '>' + (jb ? "Tap again" : "Use LAN") + '</button></div>';
    }
    return h;
  }

  function renderNet() {
    var el = $("ec-net"); if (!el) return;
    var c = S.net, sw = S.netsw && S.netsw.active ? S.netsw : null;
    if (!c && !sw) return;
    // Don't repaint under someone typing a password (their text and the
    // phone's keyboard would go); it paints when they leave the field.
    var ae = document.activeElement;
    if (ae && ae.classList && ae.classList.contains("nt-pass") && el.contains(ae)) return;

    var h = '<div class="ec bt nt">';
    if (S.netMsg) h += '<div class="bt-msg' + (S.netMsg.bad ? " bad" : "") + '">' + (S.netMsg.bad ? "✕ " : "✓ ") + esc(S.netMsg.text) + '</div>';
    if (sw) {
      var gone = Math.max(0, Math.round(Date.now() / 1000 - (sw.since || 0)));
      var pct = D.clamp(100 * gone / 60, 4, 100);
      h += '<div class="bt-scan on nt-sw"><span class="bt-radar"><i></i>' + nico(sw.mode === "wired" ? "cable" : "wifi") + '</span>' +
        '<span class="bt-main"><b>Switching to ' + esc(sw.label) + '… <span class="bt-left">' + gone + 's</span></b>' +
          '<span class="bt-state">Eclipse drops off the dashboard for up to a minute while it changes over. ' +
          'If it can’t get online it goes back by itself.</span></span>' +
        '<span class="bt-prog"><i style="width:' + pct.toFixed(1) + '%"></i></span></div>';
    }
    if (c && !c.reachable && !sw) {
      h += '<div class="ec-hero"><span class="ec-orb bad"></span><div><div class="ec-title">Eclipse unreachable</div>' +
        '<div class="ec-sub">' + esc(c.error || "no answer over SSH") + '</div></div><div></div></div>' +
        '<div class="bt-empty">Just switched it? Give it a minute. Still gone: plug in a cable, or on the TV open ' +
        '<b>LibreELEC → Connections</b> with the remote.</div></div>';
      D.paint(el, h + '</div>');
      return;
    }
    if (!c || !c.reachable) { D.paint(el, h + '</div>'); return; }

    var u = c.using, locked = !!sw || !!c.switch_running;
    var kind = u ? u.kind : "none";
    // Mid-switch the Pi's own view is in flux (connman restarting, no link
    // for a moment): don't show that as the answer — the switch panel above
    // is the state; the lists stay, greyed, for reference.
    if (sw) h += '<div class="nt-dim">';
    else h += netTop(c, u, kind, locked);

    // ── saved networks
    var saved = c.saved || [];
    h += '<div class="ag-sec">Saved Wi-Fi<span class="ag-sec-end">' + (saved.length ? saved.length + " saved · " +
      saved.filter(function (n) { return n.in_range; }).length + " in range" : "none") + '</span></div>';
    h += saved.length ? '<div class="bt-list">' + saved.map(function (n) { return savedRow(n, u, locked); }).join("") + '</div>'
      : '<div class="bt-empty">Nothing saved — search below to join one.</div>';

    // ── joining one
    var sc = S.netscan || {}, found = c.found || [];
    h += '<div class="ag-sec">Join a network</div>';
    if (sc.active) {
      h += '<div class="bt-scan on"><span class="bt-radar"><i></i>' + nico("wifi") + '</span>' +
        '<span class="bt-main"><b>Searching…</b><span class="bt-state">Listening for Wi-Fi near the TV</span></span><span></span></div>';
    } else {
      h += '<button type="button" class="bt-scan" data-net-scan' + (locked ? " disabled" : "") + '>' +
        '<span class="bt-radar">' + ico("search") + '</span>' +
        '<span class="bt-main"><b>' + (sc.ended ? "Search again" : "Search for Wi-Fi") + '</b>' +
          '<span class="bt-state">' + (c.wifi_on ? "Networks near the TV — a friend’s, a hotspot, a hotel’s" : "Wi-Fi is off on Eclipse — searching turns it on (nothing joins by itself)") + '</span></span>' +
        '<i class="bt-chev go" aria-hidden="true"></i></button>';
    }
    if (found.length || sc.active) {
      var nf = found.length;
      h += '<details class="bt-results" data-net="results"' + (S.netOpen.results !== false || S.netJoin ? " open" : "") + '>' +
        '<summary class="bt-rsum"><span class="bt-main"><b>' + (nf ? nf + " network" + (nf === 1 ? "" : "s") + " nearby" : "Looking…") + '</b>' +
          '<span class="bt-state">Strongest first</span></span>' +
        '<span class="bt-rhint" aria-hidden="true"></span><i class="bt-chev" aria-hidden="true"></i></summary>';
      if (nf) h += '<div class="bt-list">' + found.map(function (n) { return foundNet(n, u, locked); }).join("") + '</div>';
      h += '</details>';
    }

    // ── away from home
    h += '<details class="bt-howto"' + (S.netOpen.howto ? " open" : "") + ' data-net="howto"><summary>Taking Eclipse somewhere else</summary><ul>' +
      '<li><b>Before you go</b> switch to <b>Wi-Fi</b> — wired only means no network at all once the cable’s out</li>' +
      '<li><b>Your phone is the key</b> — join its hotspot once, here, at home. In Wi-Fi mode Eclipse joins any saved network by itself, so turn the hotspot on wherever you are and it comes back to this dashboard</li>' +
      '<li><b>There</b> search here and join their Wi-Fi — then you can turn the hotspot off</li>' +
      '<li><b>Jellyfin</b> switch its path to <b>Tailscale</b> while you’re out (this card says when)</li>' +
      '<li><b>Back home</b> plug the cable in and tap <b>Wired</b></li>' +
      '<li><b>No dashboard at all?</b> On the TV with the remote: <b>LibreELEC → Connections</b></li></ul>' +
      '<small>Wi-Fi mode still prefers a cable: plug one in and it takes over after a restart.</small></details>';
    if (sw) h += '</div>';
    h += '</div>';
    D.paint(el, h);
    // The typed password lives here, not in the HTML — restored after a repaint.
    if (S.netJoin) {
      var inp = el.querySelector('[data-net-pass="' + S.netJoin + '"]');
      if (inp) {
        if (inp.value !== S.netPass) inp.value = S.netPass;
        if (S.netFocus) { S.netFocus = false; inp.focus(); }
      }
    }
  }

  var netTimer = null;
  function netSay(j, okText) {
    var bad = !(j && j.ok);
    S.netMsg = { bad: bad, text: bad ? (j && (j.error || j.message)) || "no answer from Eclipse" : (okText || (j && j.message) || "done") };
    clearTimeout(netTimer);
    netTimer = setTimeout(function () { S.netMsg = null; soon(); }, bad ? 15000 : 8000);
    soon();
    return j;
  }
  function netPost(path, body) {
    var o = { method: "POST", headers: { "X-Dash": "1" } };
    if (body) { o.body = JSON.stringify(body); o.headers["Content-Type"] = "text/plain"; }
    return fetch(API + "/net/" + path, o)
      .then(function (r) { return r.json().catch(function () { return {}; }); })
      .catch(function () { return { ok: false, error: "couldn’t reach eclipse-control" }; });
  }
  function netJoinGo(id) {
    var inp = document.querySelector('#ec-net [data-net-pass="' + id + '"]');
    var pw = inp ? inp.value : S.netPass;
    if (inp) inp.blur();
    S.netPass = ""; S.netJoin = null; S.netShow = false;
    if (inp) inp.value = "";
    netPost("wifi/" + encodeURIComponent(id), { pass: pw }).then(function (j) { netSay(j); });
  }

  function render() { queued = false; renderMain(); renderTv(); renderWolf(); renderCtl(); renderNet(); renderLog(); }
  // The search countdown moves every second while one runs.
  setInterval(function () {
    if (document.hidden) return;
    if (S.scan && S.scan.active) renderCtl();
    if (S.netsw && S.netsw.active) renderNet();          // the switch's seconds
  }, 1000);
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
    var b = t.closest("#ec-main [data-act], #ec-ctl [data-act], #ec-net [data-act]");
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
          // Paired: open it and put the cursor in its name, so it gets one —
          // and fold the search results away; it's in My devices now.
          if (j.ok) { S.btOpen[mac] = true; S.focusName = mac; results(false); soon(); }
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
    // Network. Every switch is armed (a second tap within 3 s): it takes the
    // box off this dashboard for up to a minute.
    var nb = t.closest("#ec-net [data-net-mode], #ec-net [data-net-join], #ec-net [data-net-new], #ec-net [data-net-go]," +
      " #ec-net [data-net-cancel], #ec-net [data-net-eye], #ec-net [data-net-forget], #ec-net [data-net-scan], #ec-net [data-net-jf]");
    if (nb) {
      e.preventDefault();
      if (nb.disabled) return;
      var id;
      if (nb.hasAttribute("data-net-scan")) { netPost("scan").then(function (j) { if (!j.ok) netSay(j); }); return; }
      if (nb.hasAttribute("data-net-cancel")) { S.netJoin = null; S.netPass = ""; S.netShow = false; soon(); return; }
      if (nb.hasAttribute("data-net-eye")) {
        var pi = document.querySelector("#ec-net .nt-pass");
        if (pi) S.netPass = pi.value;
        S.netShow = !S.netShow; S.netFocus = true; soon(); return;
      }
      if (nb.hasAttribute("data-net-jf")) {
        if (S.armed !== "net-jf") { arm("net-jf"); return; }
        S.armed = null; act("jellyfin-toggle"); return;
      }
      if ((id = nb.getAttribute("data-net-mode"))) {
        if (id === "wifi" && !(S.net && (S.net.saved || []).some(function (n) { return n.in_range && n.joinable; }))) {
          // Nothing saved in range: show what is, to pick from.
          nresults(true);
          netSay({ ok: true }, "No saved Wi-Fi in range — pick a network below to join it");
          netPost("scan");
          return;
        }
        if (S.armed !== "mode:" + id) { arm("mode:" + id); return; }
        S.armed = null;
        netPost(id).then(function (j) { netSay(j); });
        return;
      }
      if ((id = nb.getAttribute("data-net-join"))) {
        if (S.armed !== "join:" + id) { arm("join:" + id); return; }
        S.armed = null;
        netPost("wifi/" + encodeURIComponent(id)).then(function (j) { netSay(j); });
        return;
      }
      if ((id = nb.getAttribute("data-net-new"))) {
        var nn = S.net && (S.net.found || []).filter(function (n) { return n.id === id; })[0];
        if (nn && !nn.secure) {                       // open: no password, just confirm
          if (S.armed !== "open:" + id) { arm("open:" + id); return; }
          S.armed = null;
          netPost("wifi/" + encodeURIComponent(id), { pass: "" }).then(function (j) { netSay(j); });
          return;
        }
        S.netJoin = id; S.netPass = ""; S.netShow = false; S.netFocus = true; soon();
        return;
      }
      if ((id = nb.getAttribute("data-net-go"))) { netJoinGo(id); return; }
      if ((id = nb.getAttribute("data-net-forget"))) {
        if (S.armed !== "nforget:" + id) { arm("nforget:" + id); return; }
        S.armed = null;
        netPost("forget/" + encodeURIComponent(id)).then(function (j) { netSay(j); });
        return;
      }
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

  D.ready("#ec-main, #ec-tv, #ec-wolf, #ec-ctl, #ec-net, #ec-log", function () {
    D.stream(API + "/events", {
      status: function (d) { S.status = d; soon(); },
      tv: function (d) { S.tv = d; soon(); },
      wolf: function (d) { S.wolf = d; soon(); },
      ctl: function (d) { S.ctl = d; soon(); },
      scan: function (d) {
        // A search starting while we watch: show what it finds. (Not the
        // first state after a page load — a search already under way then,
        // and a fold made before the reload should stay folded.)
        if (d.active && S.scan && !S.scan.active) results(true);
        S.scan = d;
        if (!d.active && !(d.found || []).length) S.hint = null;
        soon();
      },
      ctlbusy: function (d) { S.ctlbusy = d || {}; soon(); },
      net: function (d) { S.net = d; soon(); },
      netscan: function (d) {
        if (d.active && S.netscan && !S.netscan.active) nresults(true);   // a new search: show it
        S.netscan = d; soon();
      },
      netsw: function (d) {
        // A switch this page watched has ended: say how, in the card itself.
        if (S.netsw && S.netsw.active && !d.active && d.last) {
          netSay(d.last.ok ? { ok: true, message: d.last.message } : { ok: false, error: d.last.message });
        }
        S.netsw = d; soon();
      },
      activity: function (d) { S.activity = d; soon(); },
      busy: function (d) { S.busy = d; soon(); }
    }, "ec-live");
    document.addEventListener("click", onClick);
    // Which device rows are open survives the repaints (the morph mirrors the
    // rendered `open`, so the page has to remember it).
    document.addEventListener("toggle", function (e) {
      var d = e.target;
      if (d && d.matches && d.matches("#ec-log details[data-lg]")) {
        if (S.logOpen !== d.open) {
          S.logOpen = d.open; soon();
          try { localStorage.setItem(LOGK, d.open ? "open" : "folded"); } catch (x) { /* private window */ }
        }
        return;
      }
      if (d && d.matches && d.matches("#ec-net details[data-net]")) {
        var nk = d.getAttribute("data-net");
        if (nk === "results") nresults(d.open); else S.netOpen[nk] = d.open;
        return;
      }
      if (!d || !d.matches || !d.matches("#ec-ctl details[data-bt]")) return;
      var k = d.getAttribute("data-bt");
      if (k === "results") results(d.open);
      else S.btOpen[k] = d.open;
    }, true);
    // Names: Enter saves, Esc puts it back; leaving the field lets the card
    // repaint again (renderCtl holds off while it has focus).
    document.addEventListener("keydown", function (e) {
      var i = e.target;
      if (i && i.classList && i.classList.contains("nt-pass")) {
        if (e.key === "Enter") { e.preventDefault(); netJoinGo(i.getAttribute("data-net-pass")); }
        else if (e.key === "Escape") { S.netJoin = null; S.netPass = ""; i.blur(); soon(); }
        return;
      }
      if (!i || !i.classList || !i.classList.contains("bt-input")) return;
      if (e.key === "Enter") { e.preventDefault(); saveName(i.getAttribute("data-bt-name")); }
      else if (e.key === "Escape") { i.value = i.defaultValue; i.blur(); }
    });
    document.addEventListener("focusout", function (e) {
      if (e.target && e.target.classList && e.target.classList.contains("bt-input")) setTimeout(soon, 0);
    });
    // The password is kept as it's typed (a repaint must not lose it).
    document.addEventListener("input", function (e) {
      if (e.target && e.target.classList && e.target.classList.contains("nt-pass")) S.netPass = e.target.value;
    });
    // relative times ("3m ago") keep moving between events
    setInterval(function () { if (!document.hidden) soon(); }, 30000);
  });
})();
