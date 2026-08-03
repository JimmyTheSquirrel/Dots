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


PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eclipse Control</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 14px;
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    background: transparent; color: #d8d8d8;
  }
  .status {
    display: flex; flex-wrap: wrap; gap: 8px 18px;
    padding: 10px 12px; margin-bottom: 14px;
    border: 1px solid #ffffff1a; border-radius: 8px; background: #ffffff08;
  }
  .item { font-size: 13px; letter-spacing: .3px; }
  .item .k { color: #8a8a8a; text-transform: uppercase; font-size: 11px; }
  .item .v { font-weight: 600; }
  .ok { color: hsl(142, 72%, 52%); }
  .bad { color: hsl(0, 84%, 66%); }
  .warn { color: hsl(38, 92%, 60%); }
  .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
  button {
    appearance: none; border: 1px solid #ffffff1f; border-radius: 8px;
    background: #ffffff0d; color: #e6e6e6;
    padding: 16px 12px; font-size: 15px; font-weight: 600;
    letter-spacing: .3px; cursor: pointer; min-height: 58px;
    transition: background .15s, border-color .15s, transform .05s;
  }
  button:hover:not(:disabled) {
    background: hsl(142, 72%, 39%, .18); border-color: hsl(142, 72%, 45%, .55);
  }
  button:active:not(:disabled) { transform: translateY(1px); }
  button:disabled { opacity: .45; cursor: not-allowed; }
  button.danger:hover:not(:disabled) {
    background: hsl(0, 84%, 60%, .16); border-color: hsl(0, 84%, 60%, .5);
  }
  .full { grid-column: 1 / -1; }
  #log {
    margin-top: 12px; padding: 9px 11px; min-height: 20px;
    font-size: 12.5px; border-radius: 6px; background: #ffffff08;
    border: 1px solid #ffffff14; color: #a8a8a8; white-space: pre-wrap;
  }
  .hint { color: hsl(38, 92%, 60%); font-size: 12px; margin-bottom: 10px; display: none; }
</style></head><body>
  <div class="status" id="status"><span class="item">loading...</span></div>
  <div class="hint" id="hint">Link is up but Kodi is not driving it - restart Kodi.</div>
  <div class="grid">
    <button class="full" onclick="act('restart-kodi', this)">Restart Kodi</button>
    <button onclick="act('sync-movies', this)">Sync Movies</button>
    <button onclick="act('sync-shows', this)">Sync TV Shows</button>
    <button class="full danger" onclick="confirmAct('reboot', this)">Reboot Pi</button>
  </div>
  <div id="log">ready</div>
<script>
function fmtUptime(s) {
  if (!s) return "-";
  var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  if (d) return d + "d " + h + "h";
  if (h) return h + "h " + m + "m";
  return m + "m";
}
function cell(k, v, cls) {
  return '<span class="item"><span class="k">' + k + '</span> ' +
         '<span class="v ' + (cls || '') + '">' + v + '</span></span>';
}
function refresh() {
  fetch('status').then(function (r) { return r.json(); }).then(function (s) {
    var h = '';
    if (!s.reachable) {
      h = cell('Eclipse', 'unreachable', 'bad');
    } else {
      h += cell('Eclipse', 'online', 'ok');
      h += cell('Kodi', s.kodi, s.kodi === 'active' ? 'ok' : 'bad');
      h += cell('HDMI', s.hdmi, s.hdmi === 'connected' ? 'ok' : 'bad');
      h += cell('EDID', s.edid ? s.edid + 'B' : 'none', s.edid ? 'ok' : 'bad');
      h += cell('Output', s.mode || 'not driving', s.mode ? 'ok' : 'warn');
      h += cell('Uptime', fmtUptime(s.uptime), '');
    }
    document.getElementById('status').innerHTML = h;
    document.getElementById('hint').style.display = s.needs_kodi_restart ? 'block' : 'none';
  }).catch(function () {
    document.getElementById('status').innerHTML = cell('Panel', 'offline', 'bad');
  });
}
function setBusy(b) {
  var bs = document.querySelectorAll('button');
  for (var i = 0; i < bs.length; i++) bs[i].disabled = b;
}
function act(name, btn) {
  var log = document.getElementById('log');
  log.textContent = 'running ' + name + '...';
  setBusy(true);
  fetch('act/' + name, { method: 'POST' })
    .then(function (r) { return r.json(); })
    .then(function (j) { log.textContent = (j.ok ? 'OK  ' : 'FAILED  ') + j.message; })
    .catch(function (e) { log.textContent = 'FAILED  ' + e; })
    .then(function () { setBusy(false); setTimeout(refresh, 2500); });
}
function confirmAct(name, btn) {
  if (btn.dataset.armed) { delete btn.dataset.armed; btn.textContent = 'Reboot Pi'; act(name, btn); return; }
  btn.dataset.armed = '1'; btn.textContent = 'Tap again to confirm';
  setTimeout(function () {
    if (btn.dataset.armed) { delete btn.dataset.armed; btn.textContent = 'Reboot Pi'; }
  }, 4000);
}
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

    def do_GET(self):
        path = self.path.split("?")[0].strip("/")
        if path in ("", "index.html"):
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif path == "status":
            self._send(200, json.dumps(get_status()), "application/json")
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
