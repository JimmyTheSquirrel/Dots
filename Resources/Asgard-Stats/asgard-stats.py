#!/usr/bin/env python3
"""asgard-stats — live host stats for the Asgard dashboard, pushed over SSE.

Replaces Glance's small server-stats widget with one stream the page renders
itself (Resources/Glance/stats.js):

  GET /stream    text/event-stream: the last 3 min of CPU/memory history and
                 a snapshot on connect, then a snapshot every 2 s, plus a ping
                 every 15 s so a dead link shows up client-side
  GET /snapshot  the same JSON once

Everything fast comes from /proc and /sys, which any user can read, so the
service runs as a DynamicUser (Modules/Server/stats.nix):

  every 2 s   CPU (total + per core), load, memory/swap, uptime, CPU package
              and NVMe temperatures (hwmon), fan RPMs (it87 hwmon), LAN rx/tx
  every 60 s  filesystem usage of every disk's mount and the mergerfs pool —
              os.path.ismount first: a missing `nofail` disk must read as
              "not mounted", not as the NVMe's numbers through an empty dir

and, ONLY while at least one dashboard is connected (they are HTTP calls into
other services, so nobody watching means nobody asked):

  every 10 s  Jellyfin "now playing"            (API key: systemd credential)
  every 3 s   SABnzbd queue, every 60 s its history (API key: systemd credential)

The /proc samples keep running regardless — they cost microseconds, and the
CPU/memory history a newly opened page draws has to have no holes.

Drive temperature / SMART health / spin state need root, so a separate timer
(asgard-smart, every 5 min) runs `smartctl -n standby` — which never wakes a
sleeping drive — and writes SMART_FILE; this only reads it.
"""

import http.server
import json
import os
import socketserver
import threading
import time
import urllib.request
from collections import deque

PORT = int(os.environ.get("ASGARD_STATS_PORT", "9552"))
IFACE = os.environ.get("LAN_IFACE", "enp3s0")
POOL = os.environ.get("POOL_MOUNT", "/data/media")
SMART_FILE = os.environ.get("SMART_FILE", "/var/lib/asgard-smart/smart.json")
DISKS = json.loads(os.environ.get("ASGARD_DISKS", "[]"))  # [{id,label,dev,mount}]
JF_URL = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096").rstrip("/")
SAB_URL = os.environ.get("SABNZBD_URL", "http://127.0.0.1:8080").rstrip("/")
ORIGINS = frozenset(
    o.strip() for o in os.environ.get("DASH_ORIGINS", "").split(",") if o.strip()
)
FAST, SLOW, JF_EVERY = 2.0, 60.0, 10.0
SAB_EVERY, SAB_HIST_EVERY = 3.0, 60.0
HIST = 90  # samples of history handed to a new client: 90 × 2 s = the chart's 3 min


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def credential(name):
    cred = os.environ.get("CREDENTIALS_DIRECTORY")
    return read(os.path.join(cred, name)) if cred else ""


# ── Fast samples ──────────────────────────────────────────────────────────────

_prev = {"cpu": None, "net": None, "t": None}


def cpu_sample():
    rows = {}
    for line in read("/proc/stat").splitlines():
        if not line.startswith("cpu"):
            break
        parts = line.split()
        vals = list(map(int, parts[1:9]))
        idle = vals[3] + vals[4]  # idle + iowait
        rows[parts[0]] = (sum(vals), idle)
    prev, _prev["cpu"] = _prev["cpu"], rows
    if not prev:
        return {"total": 0.0, "cores": [0.0] * (len(rows) - 1)}

    def busy(k):
        t0, i0 = prev.get(k, (0, 0))
        t1, i1 = rows[k]
        dt = t1 - t0
        return round(100.0 * (1 - (i1 - i0) / dt), 1) if dt > 0 else 0.0

    cores = [busy(k) for k in sorted((k for k in rows if k != "cpu"), key=lambda k: int(k[3:]))]
    return {"total": busy("cpu"), "cores": cores}


def mem_sample():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) * 1024 if v.split() else 0
    total, avail = m.get("MemTotal", 0), m.get("MemAvailable", 0)
    return {
        "total": total, "used": total - avail, "cached": m.get("Cached", 0),
        "swap_total": m.get("SwapTotal", 0), "swap_used": m.get("SwapTotal", 0) - m.get("SwapFree", 0),
    }


def hwmon_sample():
    temps, fans = {}, []
    for d in sorted(os.listdir("/sys/class/hwmon")) if os.path.isdir("/sys/class/hwmon") else []:
        base = os.path.join("/sys/class/hwmon", d)
        name = read(os.path.join(base, "name"))
        if name == "coretemp":
            for f in os.listdir(base):
                if f.endswith("_label") and read(os.path.join(base, f)).startswith("Package"):
                    v = read(os.path.join(base, f.replace("_label", "_input")))
                    if v:
                        temps["cpu"] = round(int(v) / 1000, 1)
        elif name == "nvme":
            v = read(os.path.join(base, "temp1_input"))
            if v:
                temps["nvme"] = round(int(v) / 1000, 1)
        elif name.startswith("it87") or name.startswith("it86"):
            for f in sorted(os.listdir(base)):
                if f.startswith("fan") and f.endswith("_input"):
                    rpm = int(read(os.path.join(base, f), "0") or 0)
                    if rpm > 0:  # unpopulated headers read 0
                        label = read(os.path.join(base, f.replace("_input", "_label"))) or f[:-6].upper()
                        fans.append({"label": label, "rpm": rpm})
    return temps, fans


def net_sample(now):
    rx = tx = None
    for line in read("/proc/net/dev").splitlines():
        if line.strip().startswith(IFACE + ":"):
            f = line.split(":", 1)[1].split()
            rx, tx = int(f[0]), int(f[8])
    prev, _prev["net"] = _prev["net"], (rx, tx, now)
    if rx is None or not prev or prev[0] is None:
        return {"iface": IFACE, "rx_mbps": 0.0, "tx_mbps": 0.0}
    dt = now - prev[2]
    return {
        "iface": IFACE,
        "rx_mbps": round((rx - prev[0]) * 8 / dt / 1e6, 2) if dt > 0 else 0.0,
        "tx_mbps": round((tx - prev[1]) * 8 / dt / 1e6, 2) if dt > 0 else 0.0,
    }


# ── Slow samples ──────────────────────────────────────────────────────────────

def fs(mount):
    if not os.path.ismount(mount):
        return {"mounted": False}
    st = os.statvfs(mount)
    size = st.f_blocks * st.f_frsize
    return {"mounted": True, "size": size, "used": (st.f_blocks - st.f_bfree) * st.f_frsize,
            "free": st.f_bavail * st.f_frsize}


def disks_sample():
    try:
        with open(SMART_FILE) as f:
            smart = json.load(f)
    except (OSError, ValueError):
        smart = {}
    out = []
    for d in DISKS:
        s = smart.get(d["dev"], {})
        out.append({**{k: d[k] for k in ("id", "label", "mount")}, **fs(d["mount"]),
                    "temp": s.get("temp"), "healthy": s.get("healthy"), "state": s.get("state"),
                    "hours": s.get("hours"), "ssd": s.get("ssd")})
    return out, {**fs(POOL), "mount": POOL}, smart.get("_at")


def jellyfin_sample():
    key = credential("jellyfin-api-key")
    if not key:
        return None
    req = urllib.request.Request(JF_URL + "/Sessions?activeWithinSeconds=90",
                                 headers={"X-Emby-Token": key})
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            sessions = json.load(r)
    except (OSError, ValueError):
        return None
    out = []
    for s in sessions:
        item = s.get("NowPlayingItem")
        if not item:
            continue
        ps = s.get("PlayState", {})
        ti = s.get("TranscodingInfo") or {}
        title = item.get("Name", "")
        sub = item.get("SeriesName") or (str(item.get("ProductionYear")) if item.get("ProductionYear") else "")
        if item.get("SeriesName") and item.get("IndexNumber") is not None:
            sub = f'{item["SeriesName"]} · S{item.get("ParentIndexNumber", 0):02d}E{item["IndexNumber"]:02d}'
        run = item.get("RunTimeTicks") or 0
        pos = ps.get("PositionTicks") or 0
        out.append({
            "user": s.get("UserName", ""), "device": s.get("DeviceName", ""),
            "client": s.get("Client", ""),
            # Whose Primary image to show: the series' poster for an episode, the
            # album's cover for a track, else the item's own. The page loads it
            # from Jellyfin directly — image endpoints need no token.
            "poster": item.get("SeriesId") or item.get("AlbumId") or item.get("Id"),
            "title": title, "sub": sub, "type": item.get("Type", ""),
            "method": ps.get("PlayMethod", ""), "paused": bool(ps.get("IsPaused")),
            "progress": round(pos / run, 4) if run else None,
            "remaining_s": int((run - pos) / 1e7) if run else None,
            "transcode": {"video": ti.get("VideoCodec"), "audio": ti.get("AudioCodec"),
                          "mbps": round(ti["Bitrate"] / 1e6, 1) if ti.get("Bitrate") else None,
                          "hw": bool(ti.get("HardwareAccelerationType"))} if ti else None,
        })
    return out


def _sab(mode, **params):
    key = credential("sabnzbd-api-key")
    if not key:
        return None
    q = "&".join(f"{k}={v}" for k, v in params.items())
    url = f"{SAB_URL}/api?mode={mode}&output=json&apikey={key}" + (f"&{q}" if q else "")
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            return json.load(r)
    except (OSError, ValueError):
        return None


def _hms(t):
    """SAB's "1:02:03" / "0:06:35" time-left string → seconds."""
    try:
        parts = [int(x) for x in str(t).split(":")]
    except ValueError:
        return None
    sec = 0
    for x in parts:
        sec = sec * 60 + x
    return sec


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def sab_queue():
    """The live queue: what is downloading, how fast, how long. None = SAB down."""
    j = _sab("queue", limit=4)
    if not j or "queue" not in j:
        return None
    q = j["queue"]
    return {
        "status": q.get("status", ""),          # Downloading / Paused / Idle
        "paused": bool(q.get("paused")),
        "mbps": round(_f(q.get("kbpersec")) * 8 / 1000, 1),
        "left_mb": round(_f(q.get("mbleft")), 1),
        "eta_s": _hms(q.get("timeleft")),
        "count": int(_f(q.get("noofslots_total"))),
        "slots": [{
            "name": sl.get("filename", ""),
            "cat": sl.get("cat", ""),
            "pct": _f(sl.get("percentage")),
            "mb": round(_f(sl.get("mb")), 1),
            "left_mb": round(_f(sl.get("mbleft")), 1),
            "eta_s": _hms(sl.get("timeleft")),
            "status": sl.get("status", ""),
        } for sl in q.get("slots", [])[:4]],
    }


def sab_history():
    """The last few finished jobs, plus SAB's own day/week/month totals."""
    j = _sab("history", limit=5)
    if not j or "history" not in j:
        return None
    h = j["history"]
    return {
        "day": h.get("day_size", ""), "week": h.get("week_size", ""), "month": h.get("month_size", ""),
        "items": [{
            "name": it.get("name", ""),
            "cat": it.get("category", ""),
            "status": it.get("status", ""),     # Completed / Failed / (post-processing stages)
            "bytes": int(_f(it.get("bytes"))),
            "done": int(_f(it.get("completed"))) or None,
            "error": it.get("fail_message", "") or "",
        } for it in h.get("slots", [])[:5]],
    }


# ── State + fan-out ───────────────────────────────────────────────────────────

_cond = threading.Condition()
_snap = {"version": 0, "body": b""}
# Kept here, not just in the browser, so a freshly opened page draws a full
# chart at once instead of growing one from the right for three minutes.
_hist = {"cpu": deque(maxlen=HIST), "mem": deque(maxlen=HIST), "ts": None}
_watchers = {"n": 0}  # open /stream connections; 0 → skip the HTTP-backed samples
_wake = threading.Event()  # a viewer just connected: sample now, don't wait out FAST


def publish(data):
    body = json.dumps(data).encode()  # serialised once, however many tabs listen
    with _cond:
        _hist["cpu"].append(data["cpu"]["total"])
        _hist["mem"].append(round(100 * data["mem"]["used"] / data["mem"]["total"], 1) if data["mem"]["total"] else 0)
        _hist["ts"] = data["ts"]  # lets the page skip the snapshot already in the history
        _snap["body"] = body
        _snap["version"] += 1
        _cond.notify_all()


def sampler():
    slow_at = jf_at = sab_at = sabh_at = 0.0
    disks, pool, smart_at, streams, sab, sabh = [], {}, None, None, None, None
    while True:
        now = time.time()
        watched = _watchers["n"] > 0
        if now - slow_at >= SLOW:
            disks, pool, smart_at = disks_sample()
            slow_at = now
        if not watched:
            # Nobody to show it to: forget both the timers and the values, so a
            # new viewer is never shown what was playing an hour ago. `media`
            # tells the page whether these fields are real yet.
            jf_at = sab_at = sabh_at = 0.0
            streams = sab = sabh = None
        else:
            if now - jf_at >= JF_EVERY:
                streams = jellyfin_sample()
                jf_at = now
            if now - sab_at >= SAB_EVERY:
                sab = sab_queue()
                sab_at = now
            if now - sabh_at >= SAB_HIST_EVERY:
                sabh = sab_history()
                sabh_at = now
        temps, fans = hwmon_sample()
        load = read("/proc/loadavg").split()[:3]
        publish({
            "ts": now,
            "uptime": float(read("/proc/uptime", "0 0").split()[0]),
            "load": [float(x) for x in load] if len(load) == 3 else [0, 0, 0],
            "cpu": cpu_sample(), "mem": mem_sample(), "temps": temps, "fans": fans,
            "net": net_sample(now), "disks": disks, "pool": pool, "smart_at": smart_at,
            "streams": streams,
            "downloads": dict(sab, history=sabh) if sab else None,
            "media": watched,
        })
        _wake.wait(max(0.2, FAST - (time.time() - now)))
        _wake.clear()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _cors(self):
        origin = self.headers.get("Origin")
        if origin and origin in ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/snapshot":
            body = _snap["body"] or b"{}"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self._cors()
            self.end_headers()
            self.wfile.write(body)
            return
        if path != "/stream":
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self._cors()
        self.end_headers()
        seen, last_ping = -1, time.time()
        with _cond:
            _watchers["n"] += 1
        _wake.set()
        try:
            with _cond:
                hist = {k: list(v) if isinstance(v, deque) else v for k, v in _hist.items()}
            self.wfile.write(b"event: history\ndata: " + json.dumps(hist).encode() + b"\n\n")
            while True:
                with _cond:
                    if _snap["version"] == seen:
                        _cond.wait(timeout=15)
                    version, body = _snap["version"], _snap["body"]
                if version != seen and body:
                    self.wfile.write(b"event: snapshot\ndata: " + body + b"\n\n")
                    seen = version
                if time.time() - last_ping >= 15:
                    self.wfile.write(b"event: ping\ndata: {}\n\n")
                    last_ping = time.time()
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            return
        finally:
            with _cond:
                _watchers["n"] -= 1


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    threading.Thread(target=sampler, daemon=True).start()
    print(f"asgard-stats on :{PORT} ({len(DISKS)} disks, iface {IFACE})", flush=True)
    Server(("0.0.0.0", PORT), Handler).serve_forever()
