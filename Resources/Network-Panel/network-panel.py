#!/usr/bin/env python3
"""
Network panel endpoint for Glance.

Two jobs in one process:

  * live throughput — a background thread samples /proc/net/dev once a second and
    keeps a rolling 60s history, so both the numbers and the sparklines are ready
    on the very first request rather than filling in over the next minute.
  * speed test — serves the last result written by speedtest.service, and can
    trigger a fresh run on demand.

This replaced `flow` wrapped in a second read-only ttyd on :7682. That worked,
but ttyd kills the child whenever the websocket drops — a backgrounded tab, a
suspend, a brief network blip — and xterm.js then paints its "reconnecting"
banner over the panel, which is what it spent most of its life showing.

Glance 0.8.5 renders each widget server-side exactly ONCE per page load: page.js
calls fetchPageContent() a single time from setupPage(), and there is no
client-side widget refresh to hook into. So /api gets consumed twice:

  * by Glance itself over localhost, to server-render the initial state
  * by a poller in Glance's `document.head`, over the tailnet, to keep it live

which is why this sends CORS and binds 0.0.0.0 rather than 127.0.0.1. It is
still tailnet-only: tailscale0 is a trusted firewall interface and 9555 is
deliberately not in allowedTCPPorts.

CORS goes to the dashboards only (DASH_ORIGINS), never `*`, and POST /run needs
an `X-Dash: 1` header. Together those stop any other web page open in a tailnet
browser from kicking off speed tests: without the header a body-less POST is a
"simple" request the browser sends cross-origin without asking, and with it the
browser has to pass a preflight that only the dashboards pass.

Units are fixed at Mb/s throughout, deliberately. flow's auto-scaling used to
drop the panel to Kb/s whenever the link went quiet, which made a glance at the
dashboard misread by three orders of magnitude.
"""

import http.server
import json
import os
import socketserver
import subprocess
import threading
import time
from collections import deque

IFACE = os.environ.get("NETPANEL_IFACE", "enp3s0")
PORT = int(os.environ.get("NETPANEL_PORT", "9555"))
RESULT = os.environ.get("NETPANEL_RESULT", "/var/lib/speedtest/latest.json")
UNIT = os.environ.get("NETPANEL_UNIT", "speedtest.service")

# Mirrors Modules/Server/_origins.nix; the unit can pass it in as DASH_ORIGINS
# (comma-separated), and this default applies until it does. The admin Glance
# builds this panel's URL from location.hostname, so each name it is opened by
# is listed.
DASH_ORIGINS = frozenset(o.strip() for o in os.environ.get(
    "DASH_ORIGINS",
    "http://asgard:8888,http://asgard.tailb54b82.ts.net:8888,"
    "http://100.126.205.100:8888,http://marsbar:1111,"
    "http://marsbar.tailb54b82.ts.net:1111",
).split(",") if o.strip())

SAMPLE_SECONDS = 1.0
HISTORY = 60  # seconds of sparkline history, at one sample per second

_lock = threading.Lock()
_down = deque([0.0] * HISTORY, maxlen=HISTORY)
_up = deque([0.0] * HISTORY, maxlen=HISTORY)


def read_counters():
    """Return (rx_bytes, tx_bytes) for IFACE, or None if it is not present."""
    with open("/proc/net/dev") as fh:
        for line in fh:
            name, _, rest = line.partition(":")
            if name.strip() != IFACE:
                continue
            f = rest.split()
            # Receive block is 8 columns wide, so transmit bytes is index 8.
            return int(f[0]), int(f[8])
    return None


def sampler():
    """Convert the kernel's monotonic byte counters into a Mb/s series."""
    prev = read_counters()
    prev_at = time.monotonic()

    while True:
        time.sleep(SAMPLE_SECONDS)
        now = read_counters()
        at = time.monotonic()

        if now is None or prev is None:
            prev, prev_at = now, at
            continue

        elapsed = at - prev_at
        # A counter that went backwards means the NIC counters wrapped or the
        # interface was reset; treat it as a gap rather than a huge spike.
        if elapsed <= 0 or now[0] < prev[0] or now[1] < prev[1]:
            prev, prev_at = now, at
            continue

        down = (now[0] - prev[0]) * 8 / elapsed / 1e6
        up = (now[1] - prev[1]) * 8 / elapsed / 1e6

        with _lock:
            _down.append(down)
            _up.append(up)

        prev, prev_at = now, at


def live():
    with _lock:
        down = list(_down)
        up = list(_up)

    return {
        "iface": IFACE,
        "down": round(down[-1], 2),
        "up": round(up[-1], 2),
        # Peak over the retained window, not since boot. A session peak drifts
        # up once and then sits there telling you nothing.
        "peak_down": round(max(down), 2),
        "peak_up": round(max(up), 2),
        "hist_down": [round(v, 2) for v in down],
        "hist_up": [round(v, 2) for v in up],
        "window": HISTORY,
    }


def speedtest():
    """Normalise the Ookla CLI's JSON into the shape the widget templates want."""
    try:
        with open(RESULT) as fh:
            raw = json.load(fh)
    except (OSError, ValueError):
        return {"ok": False}

    try:
        server = raw["server"]
        return {
            "ok": True,
            # Ookla reports bandwidth in BYTES per second, not bits.
            "down": round(raw["download"]["bandwidth"] * 8 / 1e6, 1),
            "up": round(raw["upload"]["bandwidth"] * 8 / 1e6, 1),
            "ping": round(raw["ping"]["latency"], 1),
            "jitter": round(raw["ping"]["jitter"], 1),
            "loss": round(raw.get("packetLoss", 0.0), 1),
            "server": "%s, %s" % (server.get("name", "?"), server.get("location", "?")),
            "isp": raw.get("isp", ""),
            "timestamp": raw.get("timestamp", ""),
            "url": raw.get("result", {}).get("url", ""),
        }
    except (KeyError, TypeError, ValueError):
        return {"ok": False}


_state_cache = {"at": 0.0, "running": False}


def running():
    """Is a test in flight? Cached for a second — every open tab polls this."""
    now = time.monotonic()
    if now - _state_cache["at"] < 1.0:
        return _state_cache["running"]

    try:
        out = subprocess.run(
            ["systemctl", "show", "-p", "ActiveState", "--value", UNIT],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        state = out in ("activating", "active")
    except (OSError, subprocess.SubprocessError):
        state = False

    _state_cache["at"] = now
    _state_cache["running"] = state
    return state


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _cors(self):
        origin = self.headers.get("Origin")
        if origin and origin in DASH_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") in ("", "/api"):
            self._send(200, {
                "live": live(),
                "speedtest": speedtest(),
                "running": running(),
            })
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/run":
            self._send(404, {"error": "not found"})
            return

        # See the module docstring: the header is what forces a preflight.
        if self.headers.get("X-Dash") != "1":
            self._send(403, {"error": "missing X-Dash header"})
            return

        if running():
            self._send(200, {"running": True, "started": False})
            return

        try:
            subprocess.run(
                ["systemctl", "start", "--no-block", UNIT],
                capture_output=True, text=True, timeout=10, check=True,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            self._send(500, {"error": str(exc)})
            return

        _state_cache["at"] = 0.0  # force the next poll to re-read the unit
        self._send(200, {"running": True, "started": True})

    def do_OPTIONS(self):
        origin = self.headers.get("Origin")
        allowed = bool(origin) and origin in DASH_ORIGINS
        self.send_response(204 if allowed else 403)
        self._cors()
        if allowed:
            self.send_header("Access-Control-Allow-Methods", "GET, POST")
            self.send_header("Access-Control-Allow-Headers", "X-Dash")
            self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    threading.Thread(target=sampler, daemon=True).start()
    Server(("0.0.0.0", PORT), Handler).serve_forever()
