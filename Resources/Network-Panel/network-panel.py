#!/usr/bin/env python3
"""
Network panel endpoint for Glance.

Three jobs in one process:

  * live throughput — a background thread samples /proc/net/dev once a second
    (the LAN interface AND tailscale0) and keeps a rolling 60s history, so the
    numbers and sparklines are ready on the very first request.
  * latency — while a dashboard is watching, a TCP handshake to the internet
    (1.1.1.1:443) and to the router every 5 s. A handshake rather than ICMP so
    it needs no raw socket; a refused port answers just as fast as an open one.
  * speed test — serves the last result written by speedtest.service and the
    history it appends, and can trigger a fresh run on demand.
  * speed-test history — every run is one line of RESULTS (history.jsonl in
    speedtest's StateDirectory, so it survives reboots and rebuilds). Served
    as per-day averages, one day's runs, or a CSV; POST /history/clear wipes it.

Two ways to read it:

  GET /api     one JSON snapshot (MarsBar polls this; its shape is a contract)
  GET /events  Server-Sent Events for the admin dashboard: everything once on
               connect, then a `tick` every second, `latency` every 5 s and
               `speedtest` when a run starts, finishes, lands a new result or
               the history is cleared
  GET /history             every day that has runs: count + avg/min/max of
                           down, up and ping, newest first
  GET /history?day=Y-M-D   that day's runs, each in full
  GET /history.csv         all of it, one row per run, as a download
  POST /run                start a speed test now          (needs X-Dash: 1)
  POST /history/clear      empty the history file           (needs X-Dash: 1)

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

import csv
import http.server
import io
import json
import os
import socket
import socketserver
import subprocess
import threading
import time
from collections import deque
from datetime import datetime
from urllib.parse import parse_qs, urlsplit

IFACE = os.environ.get("NETPANEL_IFACE", "enp3s0")
PORT = int(os.environ.get("NETPANEL_PORT", "9555"))
RESULT = os.environ.get("NETPANEL_RESULT", "/var/lib/speedtest/latest.json")
RESULTS = os.environ.get("NETPANEL_HISTORY", "/var/lib/speedtest/history.jsonl")
TS_IFACE = os.environ.get("NETPANEL_TS_IFACE", "tailscale0")
INTERNET = (os.environ.get("NETPANEL_PROBE", "1.1.1.1"), 443)
UNIT = os.environ.get("NETPANEL_UNIT", "speedtest.service")
# Touched before a "Run now" start; speedtest.service consumes it and records
# the run as manual, so the history can tell them from the 6-hourly timer.
MANUAL = os.environ.get("NETPANEL_MANUAL", os.path.join(os.path.dirname(RESULTS), ".manual"))

# Mirrors Modules/Server/_origins.nix, which Modules/Server/network.nix passes in
# as DASH_ORIGINS (comma-separated); this default only applies when run by hand. The admin Glance
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

LATENCY_SECONDS = 5.0
LATENCY_HISTORY = 36  # 3 minutes of probes

_lock = threading.Condition()   # guards the series; notified once per sample
_down = deque([0.0] * HISTORY, maxlen=HISTORY)
_up = deque([0.0] * HISTORY, maxlen=HISTORY)
_ts_down = deque([0.0] * HISTORY, maxlen=HISTORY)
_ts_up = deque([0.0] * HISTORY, maxlen=HISTORY)
_tick = {"n": 0}
_rtt = {"inet": None, "gw": None, "gw_ip": None, "hist": deque(maxlen=LATENCY_HISTORY)}
_watchers = {"n": 0}  # open /events streams — the latency probe only runs for them
_probe_now = threading.Event()  # a new watcher: probe at once, not up to 5 s later


def read_counters():
    """{iface: (rx_bytes, tx_bytes)} for the LAN interface and tailscale0."""
    out = {}
    with open("/proc/net/dev") as fh:
        for line in fh:
            name, _, rest = line.partition(":")
            name = name.strip()
            if name in (IFACE, TS_IFACE):
                f = rest.split()
                # Receive block is 8 columns wide, so transmit bytes is index 8.
                out[name] = (int(f[0]), int(f[8]))
    return out


def rate(now, prev, iface, elapsed):
    """Mb/s for one interface, or 0.0 across a gap. A counter that went
    backwards means the NIC counters wrapped or the interface was reset; treat
    it as a gap rather than a huge spike."""
    a, b = now.get(iface), prev.get(iface)
    if not a or not b or elapsed <= 0 or a[0] < b[0] or a[1] < b[1]:
        return 0.0, 0.0
    return (a[0] - b[0]) * 8 / elapsed / 1e6, (a[1] - b[1]) * 8 / elapsed / 1e6


def sampler():
    """Convert the kernel's monotonic byte counters into Mb/s series."""
    prev = read_counters()
    prev_at = time.monotonic()

    while True:
        time.sleep(SAMPLE_SECONDS)
        now = read_counters()
        at = time.monotonic()
        elapsed = at - prev_at
        down, up = rate(now, prev, IFACE, elapsed)
        tdown, tup = rate(now, prev, TS_IFACE, elapsed)
        with _lock:
            _down.append(down)
            _up.append(up)
            _ts_down.append(tdown)
            _ts_up.append(tup)
            _tick["n"] += 1
            _lock.notify_all()
        prev, prev_at = now, at


def gateway():
    """The default route's next hop on IFACE, from /proc/net/route (hex, LE)."""
    try:
        with open("/proc/net/route") as fh:
            for line in fh.readlines()[1:]:
                f = line.split()
                if f[0] == IFACE and f[1] == "00000000" and f[2] != "00000000":
                    return socket.inet_ntoa(int(f[2], 16).to_bytes(4, "little"))
    except (OSError, ValueError, IndexError):
        pass
    return None


def handshake_ms(host, port):
    """Round trip of one TCP handshake, in ms. A refused port is still an
    answer (the RST came back), so it counts; a timeout is None."""
    t0 = time.monotonic()
    try:
        socket.create_connection((host, port), timeout=2).close()
    except ConnectionRefusedError:
        pass
    except OSError:
        return None
    return round((time.monotonic() - t0) * 1000, 1)


def prober():
    """Latency to the internet and the router — only while someone watches."""
    while True:
        if _watchers["n"] > 0:
            gw = gateway()
            inet = handshake_ms(*INTERNET)
            gwms = handshake_ms(gw, 80) if gw else None
            with _lock:
                _rtt.update(inet=inet, gw=gwms, gw_ip=gw)
                _rtt["hist"].append(inet)
        _probe_now.wait(LATENCY_SECONDS)
        _probe_now.clear()


def live():
    with _lock:
        down = list(_down)
        up = list(_up)
        tdown = list(_ts_down)
        tup = list(_ts_up)

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
        # The tailnet's share (remote Jellyfin, Eclipse away from home, Moonlight).
        "ts_iface": TS_IFACE,
        "ts_down": round(tdown[-1], 2),
        "ts_up": round(tup[-1], 2),
        "hist_ts_down": [round(v, 2) for v in tdown],
        "hist_ts_up": [round(v, 2) for v in tup],
    }


def latency():
    with _lock:
        return {"inet": _rtt["inet"], "gw": _rtt["gw"], "gw_ip": _rtt["gw_ip"],
                "probe": INTERNET[0], "hist": list(_rtt["hist"])}


# ── Speed-test history ───────────────────────────────────────────────────────
# One JSON object per line, appended by speedtest.service. Older lines carry
# only t/down/up/ping; newer ones add jitter, loss, server, isp, bg (background
# Mb/s at test start) and manual. Parsed once per change of the file, not per
# request: every open tab asks for the summary on each new result.
_hist = {"key": None, "runs": []}
_hist_lock = threading.Lock()


def _num(v, nd=1):
    try:
        return round(float(v), nd)
    except (TypeError, ValueError):
        return None


def history():
    """Every recorded run, oldest first, each with its local day."""
    try:
        st = os.stat(RESULTS)
        key = (st.st_mtime_ns, st.st_size)
    except OSError:
        return []
    with _hist_lock:
        if _hist["key"] == key:
            return _hist["runs"]
        runs = []
        with open(RESULTS) as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                    at = datetime.fromisoformat(str(r["t"]).replace("Z", "+00:00")).astimezone()
                    run = {"t": r["t"], "at": int(at.timestamp()), "day": at.strftime("%Y-%m-%d"),
                           "down": _num(r["down"]), "up": _num(r["up"]), "ping": _num(r["ping"])}
                except (ValueError, KeyError, TypeError):
                    continue
                if run["down"] is None or run["up"] is None or run["ping"] is None:
                    continue
                for k in ("jitter", "loss", "bg"):
                    if r.get(k) is not None:
                        run[k] = _num(r[k])
                for k in ("server", "isp"):
                    if r.get(k):
                        run[k] = str(r[k])
                if r.get("manual"):
                    run["manual"] = True
                runs.append(run)
        runs.sort(key=lambda x: x["at"])
        _hist.update(key=key, runs=runs)
        return runs


def results(n=28):
    """The last n speed tests (7 days at one every 6 h), oldest first — what
    the three tiles' sparklines draw."""
    return [{"t": r["t"], "down": r["down"], "up": r["up"], "ping": r["ping"]} for r in history()[-n:]]


def _span(vals):
    return [round(sum(vals) / len(vals), 1), min(vals), max(vals)]


def days(limit=None):
    """Per-day summary, newest first: [{d, n, manual, down/up/ping: [avg, min, max]}]."""
    by = {}
    for r in history():
        by.setdefault(r["day"], []).append(r)
    out = []
    for d in sorted(by, reverse=True)[:limit]:
        rs = by[d]
        out.append({"d": d, "n": len(rs), "manual": sum(1 for r in rs if r.get("manual")),
                    "down": _span([r["down"] for r in rs]), "up": _span([r["up"] for r in rs]),
                    "ping": _span([r["ping"] for r in rs])})
    return out


def summary(limit=120):
    runs = history()
    try:
        size = os.path.getsize(RESULTS)
    except OSError:
        size = 0
    return {"count": len(runs), "bytes": size, "first": runs[0]["at"] if runs else None,
            "last": runs[-1]["at"] if runs else None, "days": days(limit)}


def day_runs(day):
    return [{k: v for k, v in r.items() if k != "day"} for r in history() if r["day"] == day]


CSV_FIELDS = ["time", "download_mbps", "upload_mbps", "ping_ms", "jitter_ms", "loss_pct",
              "background_mbps", "manual", "server", "isp"]


def history_csv():
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(CSV_FIELDS)
    for r in history():
        w.writerow([datetime.fromtimestamp(r["at"]).astimezone().isoformat(timespec="minutes"),
                    r["down"], r["up"], r["ping"], r.get("jitter", ""), r.get("loss", ""),
                    r.get("bg", ""), "yes" if r.get("manual") else "", r.get("server", ""), r.get("isp", "")])
    return buf.getvalue().encode()


def clear_history():
    """Empty the file (not delete: speedtest.service appends to it, and its
    directory is the unit's StateDirectory). latest.json stays — the tiles
    keep showing the last result."""
    n = len(history())
    with _hist_lock:
        with open(RESULTS, "w"):
            pass
        _hist.update(key=None, runs=[])
    return n


def _hist_stamp():
    try:
        st = os.stat(RESULTS)
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return None


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

    def events(self):
        """The admin dashboard's stream. Everything once, then deltas."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self._cors()
        self.end_headers()

        def send(event, payload):
            self.wfile.write(("event: %s\ndata: %s\n\n" % (event, json.dumps(payload, separators=(",", ":")))).encode())

        with _lock:
            _watchers["n"] += 1
        _probe_now.set()
        try:
            st = (speedtest(), running(), os.path.getmtime(RESULT) if os.path.exists(RESULT) else 0, _hist_stamp())
            send("init", {"live": live(), "latency": latency(), "speedtest": st[0],
                          "running": st[1], "results": results(), "history": summary()})
            self.wfile.flush()
            seen, n = _tick["n"], 0
            last_rtt = None
            while True:
                with _lock:
                    _lock.wait_for(lambda: _tick["n"] != seen, timeout=5)
                    seen = _tick["n"]
                    d, u, td, tu = _down[-1], _up[-1], _ts_down[-1], _ts_up[-1]
                    rtt = (_rtt["inet"], _rtt["gw"])
                send("tick", {"d": round(d, 2), "u": round(u, 2), "td": round(td, 2), "tu": round(tu, 2)})
                n += 1
                if rtt != last_rtt:
                    send("latency", latency())
                    last_rtt = rtt
                if n % 2 == 0:  # a finished or started run, or a cleared history, within 2 s
                    now = (None, running(), os.path.getmtime(RESULT) if os.path.exists(RESULT) else 0, _hist_stamp())
                    if now[1:] != st[1:]:
                        st = (speedtest(),) + now[1:]
                        send("speedtest", {"speedtest": st[0], "running": st[1], "results": results(),
                                           "history": summary()})
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with _lock:
                _watchers["n"] -= 1

    def do_GET(self):
        url = urlsplit(self.path)
        path = url.path.rstrip("/")
        if path == "/events":
            self.events()
            return
        if path == "/history":
            day = (parse_qs(url.query).get("day") or [None])[0]
            if day:
                self._send(200, {"day": day, "tests": day_runs(day)})
            else:
                self._send(200, summary(limit=None))
            return
        if path == "/history.csv":
            body = history_csv()
            self.send_response(200)
            self.send_header("Content-Type", "text/csv; charset=utf-8")
            self.send_header("Content-Disposition", 'attachment; filename="asgard-speedtests-%s.csv"'
                             % time.strftime("%Y-%m-%d"))
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self._cors()
            self.end_headers()
            self.wfile.write(body)
            return
        if path in ("", "/api"):
            self._send(200, {
                "live": live(),
                "speedtest": speedtest(),
                "running": running(),
            })
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        path = urlsplit(self.path).path.rstrip("/")
        if path not in ("/run", "/history/clear"):
            self._send(404, {"error": "not found"})
            return

        # See the module docstring: the header is what forces a preflight.
        if self.headers.get("X-Dash") != "1":
            self._send(403, {"error": "missing X-Dash header"})
            return

        if path == "/history/clear":
            try:
                self._send(200, {"cleared": clear_history()})
            except OSError as exc:
                self._send(500, {"error": str(exc)})
            return

        if running():
            self._send(200, {"running": True, "started": False})
            return

        try:
            with open(MANUAL, "w"):
                pass
        except OSError:
            pass  # only the "manual" tag in the history is lost
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
    threading.Thread(target=prober, daemon=True).start()
    Server(("0.0.0.0", PORT), Handler).serve_forever()
