#!/usr/bin/env python3
"""
Eclipse control endpoint for Glance.

Serves a touch-friendly button panel (embedded in Glance as an iframe widget) plus
a JSON status endpoint. Actions are executed on the Eclipse LibreELEC box over SSH.

SSH rather than Kodi's JSON-RPC on purpose: the headline action is "restart Kodi
when it has wedged", and a wedged Kodi cannot answer its own API. Kodi's HTTP
server is disabled on Eclipse anyway (services.webserver = false, JSON-RPC bound
to 127.0.0.1:9090).
"""

import http.server
import json
import os
import socketserver
import subprocess
import threading
import time

ECLIPSE = os.environ.get("ECLIPSE_HOST", "100.80.62.3")
KEY = os.environ.get("ECLIPSE_KEY", "/run/secrets/eclipse-ssh-key")
PORT = int(os.environ.get("ECLIPSE_PORT", "9554"))

# Jellyfin library IDs (see Claude/eclipse.md)
MOVIES_ID = "f137a2dd21bbc1b99aa5c0f6bf02a805"
SHOWS_ID = "a656b907eb3a73532e40e44b968d0225"

CONNECTOR = "/sys/class/drm/card1-HDMI-A-1"
KODI_SEND = "/usr/bin/kodi-send"

# JetBrains Mono, served from our own origin so the panel matches Glance's
# typography. Glance embeds the font in its Go binary and sits on a different
# port, so it cannot be borrowed cross-origin.
FONT_DIR = os.environ.get("ECLIPSE_FONT_DIR", "")
FONTS = {
    "font/regular.woff2": "JetBrainsMono-Regular.woff2",
    "font/medium.woff2": "JetBrainsMono-Medium.woff2",
    "font/bold.woff2": "JetBrainsMono-Bold.woff2",
}

# Jellyfin syncs must run one at a time - concurrent calls raise
# "Exception: Sync is already running" (Claude/eclipse.md).
sync_lock = threading.Lock()


def ssh(remote_cmd, timeout=30):
    """Run a command on Eclipse. Returns (ok, output)."""
    argv = [
        "ssh", "-i", KEY,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-o", "ConnectTimeout=6",
        "root@" + ECLIPSE,
        remote_cmd,
    ]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        out = (p.stdout + p.stderr).strip()
        return p.returncode == 0, out
    except subprocess.TimeoutExpired:
        return False, "timed out after " + str(timeout) + "s"
    except Exception as exc:
        return False, str(exc)


STATUS_CMD = (
    'echo "kodi=$(systemctl is-active kodi 2>/dev/null)"; '
    'echo "hdmi=$(cat ' + CONNECTOR + '/status 2>/dev/null)"; '
    'echo "edid=$(wc -c < ' + CONNECTOR + '/edid 2>/dev/null)"; '
    'echo "uptime=$(cut -d. -f1 /proc/uptime)"; '
    "echo \"mode=$(grep -oE 'Display [0-9]+x[0-9]+ @ [0-9.]+' "
    '/storage/.kodi/temp/kodi.log 2>/dev/null | tail -1)"'
)


def get_status():
    ok, out = ssh(STATUS_CMD, timeout=15)
    st = {"reachable": ok, "kodi": "?", "hdmi": "?", "edid": 0,
          "uptime": 0, "mode": "", "error": ""}
    if not ok:
        st["error"] = out
        return st
    for line in out.splitlines():
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        if k == "edid":
            try:
                st["edid"] = int(v.strip() or 0)
            except ValueError:
                st["edid"] = 0
        elif k == "uptime":
            try:
                st["uptime"] = int(v.strip() or 0)
            except ValueError:
                st["uptime"] = 0
        elif k in st:
            st[k] = v.strip()
    # A connected link with no picture is the classic failure mode: Kodi started
    # before the TV came up and never re-probes. Flag it explicitly.
    st["needs_kodi_restart"] = (
        st["hdmi"] == "connected" and st["kodi"] == "active" and not st["mode"]
    )
    return st


def act_restart_kodi():
    return ssh("systemctl restart kodi && echo restarted", timeout=30)


def act_reboot():
    # Fire and forget - the box drops the connection as it goes down.
    ssh("(sleep 1; reboot) >/dev/null 2>&1 &", timeout=10)
    return True, "reboot issued"


KODI_LOG = "/storage/.kodi/temp/kodi.log"


def _sync_once(lib_id):
    """Fire a sync and watch the log for a real outcome.

    kodi-send's exit code only means the message was delivered, never that the
    action ran - so watch kodi.log for the addon's own verdict instead.
    """
    cmd = (
        "N=$(wc -l < " + KODI_LOG + "); "
        + KODI_SEND + ' --action="RunPlugin(plugin://plugin.video.jellyfin/'
        "?mode=synclib&id=" + lib_id + ')" >/dev/null 2>&1; '
        "for i in $(seq 1 20); do sleep 1; "
        "T=$(tail -n +$((N+1)) " + KODI_LOG + "); "
        'case "$T" in *"Full sync completed"*) echo SYNC_OK; exit 0;; esac; '
        'case "$T" in *PythonToCppException*) echo SYNC_ERR; exit 1;; esac; '
        "done; echo SYNC_TIMEOUT; exit 2"
    )
    return ssh(cmd, timeout=45)


def _sync(lib_id, label):
    if not sync_lock.acquire(blocking=False):
        return False, "another sync is already running"
    try:
        _, out = _sync_once(lib_id)
        if "SYNC_OK" in out:
            return True, label + " sync completed"
        if "SYNC_ERR" in out:
            # Known transient: the addon's library_thread is None after a
            # dropped server connection, so synclib raises
            # "'NoneType' object has no attribute 'add_library'". The exception
            # path itself reconnects, so one retry normally succeeds.
            time.sleep(10)
            _, out2 = _sync_once(lib_id)
            if "SYNC_OK" in out2:
                return True, label + " sync completed (needed a retry)"
            return False, label + " failed - addon threw twice, see kodi.log"
        return False, label + " did not confirm within 20s"
    finally:
        sync_lock.release()


ACTIONS = {
    "restart-kodi": ("Restart Kodi", act_restart_kodi),
    "reboot": ("Reboot Pi", act_reboot),
    "sync-movies": ("Movies", lambda: _sync(MOVIES_ID, "Movies")),
    "sync-shows": ("TV Shows", lambda: _sync(SHOWS_ID, "TV Shows")),
}


PAGE = r"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eclipse Control</title>
<style>
  @font-face { font-family:'JB'; src:url('font/regular.woff2') format('woff2');
               font-weight:400; font-display:swap; }
  @font-face { font-family:'JB'; src:url('font/medium.woff2') format('woff2');
               font-weight:500; font-display:swap; }
  @font-face { font-family:'JB'; src:url('font/bold.woff2') format('woff2');
               font-weight:700; font-display:swap; }

  :root {
    color-scheme: dark;
    --line:    hsla(160, 40%, 40%, .15);
    --line-hi: hsla(160, 50%, 50%, .34);
    --glow:    hsla(160, 50%, 40%, .10);
    --fg:      #d2d5d3;
    --dim:     hsl(160, 7%, 50%);
    --ok:      hsl(142, 62%, 56%);
    --bad:     hsl(0, 78%, 66%);
    --warn:    hsl(38, 88%, 62%);
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 0;
    font-family: 'JB', ui-monospace, 'JetBrains Mono', Menlo, monospace;
    font-size: 13px; line-height: 1.4;
    background: transparent; color: var(--fg);
    -webkit-font-smoothing: antialiased;
  }
  .wrap { max-width: 1020px; margin: 0 auto; }

  /* ── status bar ── */
  .bar {
    display: flex; flex-wrap: wrap; align-items: center;
    gap: 6px 20px; padding: 11px 14px; margin-bottom: 12px;
    border: 1px solid var(--line); border-radius: 10px;
    background: hsla(160, 30%, 50%, .035);
  }
  .cell { display: flex; align-items: center; gap: 7px; white-space: nowrap; }
  .dot {
    width: 7px; height: 7px; border-radius: 50%;
    background: var(--dim); flex: none;
  }
  .dot.ok   { background: var(--ok);   box-shadow: 0 0 7px hsla(142,62%,56%,.55); }
  .dot.bad  { background: var(--bad);  box-shadow: 0 0 7px hsla(0,78%,66%,.55); }
  .dot.warn { background: var(--warn); box-shadow: 0 0 7px hsla(38,88%,62%,.55); }
  .k {
    color: var(--dim); font-size: 10px; font-weight: 500;
    letter-spacing: .09em; text-transform: uppercase;
  }
  .v { font-weight: 500; font-size: 12.5px; }
  .v.ok { color: var(--ok); } .v.bad { color: var(--bad); } .v.warn { color: var(--warn); }

  /* ── alert ── */
  .alert {
    display: none; align-items: center; gap: 9px;
    padding: 9px 13px; margin-bottom: 12px; font-size: 12px;
    border: 1px solid hsla(38, 88%, 62%, .3); border-left-width: 3px;
    border-radius: 8px; background: hsla(38, 88%, 62%, .07); color: var(--warn);
  }
  .alert.show { display: flex; }

  /* ── buttons ── */
  .grid {
    display: grid; gap: 10px;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  }
  button {
    display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 9px;
    height: 78px; padding: 10px 8px;
    font-family: inherit; font-size: 12.5px; font-weight: 500;
    letter-spacing: .04em;
    color: var(--fg); cursor: pointer;
    border: 1px solid var(--line); border-radius: 10px;
    background: hsla(160, 30%, 50%, .035);
    transition: background .18s, border-color .18s, box-shadow .18s, transform .06s;
  }
  button svg { width: 19px; height: 19px; stroke-width: 1.6; opacity: .82; }
  button:hover:not(:disabled) {
    border-color: var(--line-hi);
    background: hsla(160, 40%, 45%, .085);
    box-shadow: 0 0 14px var(--glow);
  }
  button:hover:not(:disabled) svg { opacity: 1; }
  button:active:not(:disabled) { transform: translateY(1px); }
  button:disabled { opacity: .35; cursor: default; }
  button.primary { border-color: hsla(142, 55%, 45%, .28); }
  button.primary svg { color: var(--ok); opacity: .9; }
  button.danger:hover:not(:disabled) {
    border-color: hsla(0, 70%, 60%, .45);
    background: hsla(0, 70%, 55%, .09);
    box-shadow: 0 0 14px hsla(0, 70%, 50%, .1);
  }
  button.danger:hover:not(:disabled) svg { color: var(--bad); }
  button.armed {
    border-color: hsla(0, 75%, 62%, .6);
    background: hsla(0, 70%, 55%, .13); color: var(--bad);
  }
  button.armed svg { color: var(--bad); opacity: 1; }
  button.busy { opacity: 1; border-color: var(--line-hi); }
  button.busy svg { animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── log ── */
  .log {
    display: flex; align-items: center; gap: 8px;
    margin-top: 12px; padding: 8px 13px; min-height: 32px;
    font-size: 11.5px; color: var(--dim);
    border-radius: 8px; border: 1px solid transparent;
  }
  .log .glyph { color: hsla(160, 40%, 55%, .6); }
  .log.good { color: var(--ok); border-color: hsla(142,55%,45%,.22);
              background: hsla(142,55%,45%,.05); }
  .log.err  { color: var(--bad); border-color: hsla(0,70%,60%,.25);
              background: hsla(0,70%,55%,.05); }

  @media (max-width: 560px) {
    button { height: 64px; gap: 7px; font-size: 11.5px; }
    .bar { gap: 5px 14px; padding: 10px 12px; }
  }
</style></head><body>
<div class="wrap">
  <div class="bar" id="status"><span class="k">connecting</span></div>
  <div class="alert" id="hint">
    <span>&#9888;</span><span>Link is up but Kodi is not driving it &mdash; restart Kodi</span>
  </div>
  <div class="grid">
    <button class="primary" data-act="restart-kodi">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/>
        <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
      <span class="lbl">Restart Kodi</span>
    </button>
    <button data-act="sync-movies">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><rect x="2" y="3" width="20" height="18" rx="2"/>
        <line x1="7" y1="3" x2="7" y2="21"/><line x1="17" y1="3" x2="17" y2="21"/>
        <line x1="2" y1="12" x2="22" y2="12"/></svg>
      <span class="lbl">Sync Movies</span>
    </button>
    <button data-act="sync-shows">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><rect x="2" y="7" width="20" height="15" rx="2"/>
        <polyline points="17 2 12 7 7 2"/></svg>
      <span class="lbl">Sync TV Shows</span>
    </button>
    <button class="danger" data-act="reboot" data-confirm="1">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>
        <line x1="12" y1="2" x2="12" y2="12"/></svg>
      <span class="lbl">Reboot Pi</span>
    </button>
  </div>
  <div class="log" id="log"><span class="glyph">&rsaquo;</span><span id="logtext">ready</span></div>
</div>
<script>
var buttons = Array.prototype.slice.call(document.querySelectorAll('button[data-act]'));

function fmtUptime(s) {
  if (!s) return '-';
  var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  if (d) return d + 'd ' + h + 'h';
  if (h) return h + 'h ' + m + 'm';
  return m + 'm';
}
function fmtMode(s) {
  if (!s) return null;
  var m = s.match(/(\d+)x(\d+) @ ([\d.]+)/);
  return m ? m[1] + '×' + m[2] + ' @ ' + Math.round(parseFloat(m[3])) + 'Hz' : s;
}
function cell(k, v, cls) {
  return '<span class="cell"><span class="dot ' + (cls || '') + '"></span>' +
         '<span class="k">' + k + '</span>' +
         '<span class="v ' + (cls || '') + '">' + v + '</span></span>';
}
function refresh() {
  fetch('status').then(function (r) { return r.json(); }).then(function (s) {
    var h;
    if (!s.reachable) {
      h = cell('Eclipse', 'unreachable', 'bad');
    } else {
      var mode = fmtMode(s.mode);
      h = cell('Eclipse', 'online', 'ok') +
          cell('Kodi', s.kodi, s.kodi === 'active' ? 'ok' : 'bad') +
          cell('HDMI', s.hdmi, s.hdmi === 'connected' ? 'ok' : 'bad') +
          cell('Output', mode || 'not driving', mode ? 'ok' : 'warn') +
          cell('Uptime', fmtUptime(s.uptime), '');
    }
    document.getElementById('status').innerHTML = h;
    document.getElementById('hint').className = s.needs_kodi_restart ? 'alert show' : 'alert';
  }).catch(function () {
    document.getElementById('status').innerHTML = cell('Panel', 'offline', 'bad');
  });
}
function say(text, cls) {
  document.getElementById('logtext').textContent = text;
  document.getElementById('log').className = 'log' + (cls ? ' ' + cls : '');
}
function run(btn) {
  var name = btn.dataset.act;
  buttons.forEach(function (b) { if (b !== btn) b.disabled = true; });
  btn.classList.add('busy');
  say('running ' + name + '…', '');
  fetch('act/' + name, { method: 'POST' })
    .then(function (r) { return r.json(); })
    .then(function (j) { say(j.message, j.ok ? 'good' : 'err'); })
    .catch(function (e) { say(String(e), 'err'); })
    .then(function () {
      btn.classList.remove('busy');
      buttons.forEach(function (b) { b.disabled = false; });
      setTimeout(refresh, 2000);
    });
}
buttons.forEach(function (btn) {
  btn.addEventListener('click', function () {
    if (!btn.dataset.confirm) { run(btn); return; }
    var lbl = btn.querySelector('.lbl');
    if (btn.classList.contains('armed')) {
      btn.classList.remove('armed'); lbl.textContent = btn.dataset.label; run(btn); return;
    }
    btn.dataset.label = lbl.textContent;
    btn.classList.add('armed'); lbl.textContent = 'Tap to confirm';
    setTimeout(function () {
      if (btn.classList.contains('armed')) {
        btn.classList.remove('armed'); lbl.textContent = btn.dataset.label;
      }
    }, 4000);
  });
});
refresh();
setInterval(refresh, 10000);
</script></body></html>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body, ctype):
        raw = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(raw)

    def _send_bytes(self, code, raw, ctype, cache=False):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        if cache:
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = self.path.split("?")[0].strip("/")
        if path in ("", "index.html"):
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif path == "status":
            self._send(200, json.dumps(get_status()), "application/json")
        elif path in FONTS and FONT_DIR:
            try:
                with open(os.path.join(FONT_DIR, FONTS[path]), "rb") as fh:
                    self._send_bytes(200, fh.read(), "font/woff2", cache=True)
            except OSError:
                self._send(404, "font missing", "text/plain")
        else:
            self._send(404, "not found", "text/plain")

    def do_POST(self):
        path = self.path.split("?")[0].strip("/")
        if not path.startswith("act/"):
            self._send(404, json.dumps({"ok": False, "message": "not found"}),
                       "application/json")
            return
        name = path[4:]
        entry = ACTIONS.get(name)
        if not entry:
            self._send(400, json.dumps({"ok": False, "message": "unknown action"}),
                       "application/json")
            return
        label, fn = entry
        ok, msg = fn()
        self._send(200, json.dumps({"ok": ok, "action": label, "message": msg or label}),
                   "application/json")

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    Server(("0.0.0.0", PORT), Handler).serve_forever()
