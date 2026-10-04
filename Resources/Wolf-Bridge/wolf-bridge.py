#!/usr/bin/env python3
"""wolf-bridge — Wolf's session list and "stop" over HTTP, for the Eclipse panel.

Wolf's control API is HTTP over a unix socket (/run/wolf/wolf.sock) that only
root can write to, on Sisyphus. The dashboard that wants it (eclipse-control,
on Asgard) is on another machine, so this exposes exactly two operations over
TCP and nothing else:

  GET  /sessions              -> {"wolf": "up"|"down", "sessions": [...]}
  POST /sessions/<id>/stop    -> {"ok": true[, "lingering": true]} — needs X-Dash: 1
  GET  /health                -> {"ok": true}

Wolf API facts this relies on (games-on-whales/wolf, `stable` branch,
src/moonlight-server/api/{unix_socket_server,endpoints}.cpp and
events/reflectors.hpp):

  * GET  /api/v1/sessions -> {"success":true,"sessions":[{client_ip, aes_key,
    aes_iv, rtsp_fake_ip, video_width, video_height, video_refresh_rate,
    audio_channel_count, app_id, client_id, client_settings}]}
    `client_id` is the SESSION id (std::to_string(v.session_id)), not a client.
    `aes_key` / `aes_iv` are the stream's encryption keys — never passed on.
  * POST /api/v1/sessions/stop {"session_id": "<that id>"} fires a
    StopStreamEvent; 500 {"error": "Invalid session_id"} if unknown.
  * GET  /api/v1/apps -> {"apps":[{"title","id",…}]} — for the app's name.
  * Replies are HTTP/1.0 with Content-Length; chunked requests are refused.
  * There is no start time anywhere in the API, so `started` is when this
    bridge FIRST SAW the session (kept in $RUNTIME_DIRECTORY so a bridge
    restart doesn't reset it; a reboot correctly does, Wolf's sessions die too).

Only peers in WOLF_BRIDGE_ALLOW (Asgard's tailnet IP + localhost) get an
answer — the port is reachable from the whole tailnet because Sisyphus trusts
tailscale0, and stopping someone's stream is not something any node should do.
"""

import http.client
import http.server
import ipaddress
import json
import os
import re
import socket
import threading
import time

SOCK = os.environ.get("WOLF_SOCKET", "/run/wolf/wolf.sock")
PORT = int(os.environ.get("WOLF_BRIDGE_PORT", "9560"))
ALLOW = {
    a.strip()
    for a in os.environ.get("WOLF_BRIDGE_ALLOW", "127.0.0.1,::1").split(",")
    if a.strip()
}
STATE = os.path.join(os.environ.get("RUNTIME_DIRECTORY", "/tmp"), "first-seen.json")
SESSION_ID = re.compile(r"^[0-9]{1,20}$")  # Wolf parses it with std::stoul


def log(msg):
    print(msg, flush=True)


# ── Wolf API client (HTTP over AF_UNIX) ───────────────────────────────────────


class _UnixConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout):
        super().__init__("localhost", timeout=timeout)
        self._path = path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(self.timeout)
        s.connect(self._path)
        self.sock = s


def wolf(method, path, body=None, timeout=3):
    """One request to Wolf. Returns (status, parsed JSON or {}). Raises OSError."""
    conn = _UnixConnection(SOCK, timeout)
    try:
        data = None if body is None else json.dumps(body).encode()
        headers = {"Content-Type": "application/json"} if data is not None else {}
        conn.request(method, path, body=data, headers=headers)
        resp = conn.getresponse()
        raw = resp.read()
        try:
            parsed = json.loads(raw) if raw else {}
        except ValueError:
            parsed = {"error": raw[:200].decode("utf-8", "replace")}
        return resp.status, parsed
    finally:
        conn.close()


# ── State: first-seen times and app titles ────────────────────────────────────

_lock = threading.Lock()
_first_seen = {}
_apps = {"at": 0.0, "titles": {}}


def _load_first_seen():
    try:
        with open(STATE) as f:
            data = json.load(f)
        if isinstance(data, dict):
            _first_seen.update({str(k): float(v) for k, v in data.items()})
    except (OSError, ValueError):
        pass


def _save_first_seen():
    tmp = STATE + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(_first_seen, f)
        os.replace(tmp, STATE)
    except OSError as e:
        log(f"could not persist first-seen state: {e}")


def _app_titles():
    # Apps change only when Wolf's config does — refresh once a minute at most.
    if time.time() - _apps["at"] > 60:
        try:
            status, body = wolf("GET", "/api/v1/apps")
            if status == 200:
                _apps["titles"] = {
                    str(a.get("id")): a.get("title") for a in body.get("apps", [])
                }
        except OSError:
            pass  # titles are cosmetic; keep whatever we had
        _apps["at"] = time.time()
    return _apps["titles"]


def list_sessions():
    status, body = wolf("GET", "/api/v1/sessions")
    if status != 200:
        raise OSError(f"Wolf answered {status}: {body.get('error', '')}".strip())
    titles = _app_titles()
    now = time.time()
    out = []
    with _lock:
        live, added = set(), False
        for s in body.get("sessions", []):
            sid = str(s.get("client_id") or "")
            if not sid:
                continue
            live.add(sid)
            if sid not in _first_seen:
                _first_seen[sid] = now
                added = True
            w, h, hz = s.get("video_width"), s.get("video_height"), s.get("video_refresh_rate")
            app_id = s.get("app_id")
            out.append({
                "id": sid,
                "app": titles.get(str(app_id)) or (f"app {app_id}" if app_id else "unknown app"),
                "client": s.get("client_ip") or "unknown",
                "client_ip": s.get("client_ip") or None,
                "started": int(_first_seen[sid]),
                "started_source": "first-seen",
                "video": f"{w}x{h}@{hz}" if w and h and hz else None,
                "audio_channels": s.get("audio_channel_count"),
            })
        stale = [k for k in _first_seen if k not in live]
        for k in stale:
            del _first_seen[k]
        if stale or added:
            _save_first_seen()
    return out


def stop_session(sid):
    status, body = wolf("POST", "/api/v1/sessions/stop", {"session_id": sid})
    if status != 200 or not body.get("success", False):
        return False, body.get("error") or f"Wolf answered {status}"
    # Wolf only *fires* a StopStreamEvent; wait for the session to actually go.
    deadline = time.time() + 3
    while time.time() < deadline:
        time.sleep(0.3)
        try:
            if not any(s["id"] == sid for s in list_sessions()):
                return True, None
        except OSError:
            break
    return True, "lingering"


# ── HTTP front ────────────────────────────────────────────────────────────────


def _peer_allowed(addr):
    try:
        ip = ipaddress.ip_address(addr)
        if ip.version == 6 and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        return str(ip) in ALLOW
    except ValueError:
        return False


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "wolf-bridge"

    def log_message(self, fmt, *args):  # quiet: only stops are worth a line
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _guard(self):
        if not _peer_allowed(self.client_address[0]):
            self._json(403, {"ok": False, "error": "not allowed from this address"})
            return False
        return True

    def do_GET(self):
        if not self._guard():
            return
        if self.path == "/health":
            return self._json(200, {"ok": True})
        if self.path == "/sessions":
            try:
                return self._json(200, {"wolf": "up", "sessions": list_sessions()})
            except OSError as e:
                return self._json(200, {"wolf": "down", "sessions": [], "error": str(e)[:200]})
        self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        if not self._guard():
            return
        m = re.fullmatch(r"/sessions/([^/]+)/stop", self.path)
        if not m:
            return self._json(404, {"ok": False, "error": "not found"})
        if self.headers.get("X-Dash") != "1":
            return self._json(403, {"ok": False, "error": "missing X-Dash header"})
        sid = m.group(1)
        if not SESSION_ID.match(sid):
            return self._json(400, {"ok": False, "error": "bad session id"})
        try:
            ok, note = stop_session(sid)
        except OSError as e:
            log(f"stop {sid} from {self.client_address[0]}: Wolf unreachable ({e})")
            return self._json(502, {"ok": False, "error": f"Wolf unreachable: {e}"[:200]})
        log(f"stop {sid} from {self.client_address[0]}: "
            + ("ok" if ok and not note else f"ok ({note})" if ok else f"failed ({note})"))
        if ok:
            return self._json(200, {"ok": True, **({"lingering": True} if note else {})})
        return self._json(404 if "Invalid session_id" in (note or "") else 502,
                          {"ok": False, "error": note})


def main():
    _load_first_seen()
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    log(f"wolf-bridge on :{PORT} -> {SOCK}; allowed peers: {', '.join(sorted(ALLOW))}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
