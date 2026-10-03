#!/usr/bin/env python3
"""
Tailnet status for the main Glance's "Yggdrasil Network" widget (asgard:8888).

Reads tailscaled's LocalAPI over its unix socket and serves one small JSON
document on 127.0.0.1:9553, which Glance fetches server-side and renders. Loopback
only and no CORS: nothing but Glance itself ever reads it.

    GET /status  →  {"online": 6, "total": 9, "nodes": [ … ]}

Shaped for scanning, not completeness — the widget is a list of every device on
the tailnet, and the questions it answers are "what is up", "what is it called"
and "when did I last see the one that isn't":

  * nodes come SORTED: this machine, then everything online (A→Z), then the
    offline ones, most recently seen first — so the interesting rows are at the
    top and the long-dead ones collapse out of view below them.
  * `name` is the MagicDNS name's first label (sisyphus, rhys-s25), i.e. the name
    you actually type. The OS hostname used before is often useless: Android
    reports "localhost", so two phones showed up as two identical "localhost"
    rows; LibreELEC reports "LibreELEC" for a box everyone calls eclipse.
  * `seen` is tailscaled's LastSeen as RFC 3339, only for offline nodes (it is
    the zero time while a node is online) — Glance turns it into a live "9h".
  * `link` says how an online peer is reached right now: "direct", "relay syd"
    (via a DERP server), or "idle" (no traffic with it recently).

Replaces an inline `python3 -c` that shelled out to curl for every request and
returned peers in tailscaled's hash order.
"""

import http.client
import http.server
import json
import os
import socket

SOCKET = os.environ.get("TS_STATUS_SOCKET", "/var/run/tailscale/tailscaled.sock")
HOST = os.environ.get("TS_STATUS_HOST", "127.0.0.1")
PORT = int(os.environ.get("TS_STATUS_PORT", "9553"))


class LocalAPI(http.client.HTTPConnection):
    """HTTP over tailscaled's unix socket. The Host header is ignored by it."""

    def __init__(self, sock_path, timeout=5):
        super().__init__("local-tailscaled.sock", timeout=timeout)
        self._sock_path = sock_path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(self.timeout)
        s.connect(self._sock_path)
        self.sock = s


def tailscale_status():
    conn = LocalAPI(SOCKET)
    try:
        conn.request("GET", "/localapi/v0/status")
        resp = conn.getresponse()
        body = resp.read()
        if resp.status != 200:
            raise RuntimeError("tailscaled answered %d" % resp.status)
        return json.loads(body)
    finally:
        conn.close()


def node(n, is_self=False):
    dns = (n.get("DNSName") or "").rstrip(".")
    host = n.get("HostName") or ""
    name = dns.split(".")[0] if dns else (host or "?")
    online = bool(n.get("Online")) or is_self
    seen = n.get("LastSeen") or ""
    if seen.startswith("0001-") or online:
        seen = ""
    if is_self:
        link = "this machine"
    elif not online:
        link = ""
    elif not n.get("Active"):
        link = "idle"
    elif n.get("CurAddr"):
        link = "direct"
    elif n.get("Relay"):
        link = "relay " + n["Relay"]
    else:
        link = "connecting"
    ips = n.get("TailscaleIPs") or []
    return {
        "name": name,
        # Only worth showing when it says something the name does not.
        "host": host if host and host.lower() not in (name.lower(), "localhost") else "",
        "os": n.get("OS") or "",
        "ip": next((ip for ip in ips if "." in ip), ips[0] if ips else ""),
        "online": online,
        "self": is_self,
        "link": link,
        "seen": seen,
    }


def summary(data):
    me = node(data.get("Self") or {}, is_self=True)
    peers = [node(p) for p in (data.get("Peer") or {}).values()]
    up = sorted((p for p in peers if p["online"]), key=lambda p: p["name"].lower())
    # tailscaled reports LastSeen in UTC ("…Z"), so RFC 3339 sorts as text;
    # newest first, and never-seen ("") lands last.
    down = sorted((p for p in peers if not p["online"]), key=lambda p: p["seen"], reverse=True)
    nodes = [me] + up + down
    return {
        "online": 1 + len(up),
        "offline": len(down),
        "total": len(nodes),
        "nodes": nodes,
    }


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] != "/status":
            self.send_error(404)
            return
        try:
            body = json.dumps(summary(tailscale_status())).encode()
            code = 200
        except Exception as exc:  # noqa: BLE001 — a failed read must fail the widget visibly
            body = json.dumps({"error": "%s: %s" % (type(exc).__name__, exc)}).encode()
            code = 502
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    http.server.HTTPServer((HOST, PORT), Handler).serve_forever()
