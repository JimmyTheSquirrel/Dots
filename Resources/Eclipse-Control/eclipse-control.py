#!/usr/bin/env python3
"""
Eclipse control endpoint for the dashboards.

A JSON API, not a page: both dashboards draw the same Eclipse panel from
GET /events with the same script (Resources/Glance/eclipse.js) — the admin Glance
directly, MarsBar through her /eclipse-api serve mount. Actions are executed on
the Eclipse LibreELEC box over SSH.

  GET  /status           the Pi's state (JSON), one-shot
  GET  /events           Server-Sent Events: status, what the TV is playing,
                         Wolf sessions, the shared activity log and which
                         actions are running, pushed as they change. Nothing is
                         polled while no page has one open.
  GET  /wolf/sessions    Moonlight streams Wolf is serving on Sisyphus
  POST /act/<name>       run an action (needs `X-Dash: 1`)
  POST /wolf/stop/<id>   end a stream (needs `X-Dash: 1`)

SSH rather than Kodi's JSON-RPC on purpose: the headline action is "restart Kodi
when it has wedged", and a wedged Kodi cannot answer its own API. Kodi's HTTP
server is disabled on Eclipse anyway (services.webserver = false, JSON-RPC bound
to 127.0.0.1:9090).

Status used to be polled by both dashboards (the admin iframe every 10s, MarsBar
every 15s, plus Glance's own server-side fetches), and every poll used to open a
brand-new SSH session — key exchange and all, ~0.7s each. Three things keep that
cheap now:

  * one poller (see Hub) feeds every /events client, and runs only while at
    least one is connected — a closed dashboard costs the Pi nothing;
  * SSH connection reuse (ControlMaster): one authenticated connection to the Pi
    is kept open and every command rides it as a new channel, so a status
    check costs one round trip instead of a handshake.
  * a short status cache with in-flight de-duplication (get_status): requests
    arriving within STATUS_TTL share one answer, and requests arriving while an
    SSH call is already running wait for that call instead of starting another.
"""

import atexit
import http.server
import json
import os
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ECLIPSE = os.environ.get("ECLIPSE_HOST", "100.80.62.3")
KEY = os.environ.get("ECLIPSE_KEY", "/run/secrets/eclipse-ssh-key")
PORT = int(os.environ.get("ECLIPSE_PORT", "9554"))

# The dashboards allowed to call this cross-origin. Mirrors
# Modules/Server/_origins.nix, which Modules/Server/eclipse.nix passes in as
# DASH_ORIGINS (comma-separated); this default only applies when run by hand. Neither
# dashboard actually needs it today — the admin one iframes this panel (same
# origin) and MarsBar proxies it onto her own origin — but it replaces a CORS
# `*` that let ANY web page read status, and see do_POST for the part that
# matters.
DASH_ORIGINS = frozenset(o.strip() for o in os.environ.get(
    "DASH_ORIGINS",
    "http://asgard:8888,http://asgard.tailb54b82.ts.net:8888,"
    "http://100.126.205.100:8888,http://marsbar:1111,"
    "http://marsbar.tailb54b82.ts.net:1111",
).split(",") if o.strip())

# How long one status answer is reused. Short enough that a dashboard never
# shows anything meaningfully old; long enough that several open dashboards,
# Glance's server-side fetches and the panel's own poll collapse into one SSH
# call between them.
STATUS_TTL = 5.0

# Jellyfin library IDs (see Claude/eclipse.md)
MOVIES_ID = "f137a2dd21bbc1b99aa5c0f6bf02a805"
SHOWS_ID = "a656b907eb3a73532e40e44b968d0225"

# Jellyfin server address the Kodi addon is pointed at. LAN is only reachable
# when Eclipse is on Asgard's home network; ASGARD's Tailscale IP works from
# anywhere, including Eclipse's current house (see Claude/eclipse.md).
JELLYFIN_LAN = "http://192.168.0.226:8096"
JELLYFIN_REMOTE = "http://100.126.205.100:8096"
JELLYFIN_ADDON_DIR = "/storage/.kodi/userdata/addon_data/plugin.video.jellyfin"

# maxBitrate is an index into the addon's own Mbps list (see Claude/eclipse.md).
# 23 = 1000 Mbps i.e. uncapped, 17 = 20 Mbps, 10 = 8 Mbps.
#
# LAN is uncapped because the path genuinely carries it - but NOT because it is
# wired. Eclipse's "wired" run goes through an ASUS RP-BE58 repeater
# (192.168.0.68), so one hop is wireless, and the throughput depends entirely
# on which band that repeater's backhaul is using:
#
#   5 GHz backhaul (correct): 196 Mbps down / 115 up, 6.6ms avg ping, 0% loss
#   2.4 GHz fallback (bad):    47.6 down / 43.4 up,  30ms avg, 146ms spikes, 2% loss
#
# Both measured 2026-09-26 against the memory-served sink on SPEEDTEST_LAN_PORT.
# On 5 GHz there is ~2.8x headroom over the heaviest file in the library
# ("The Drama", 51GB, 68.9 Mbps), so uncapped is correct and a cap would only
# force pointless 4K transcodes.
#
# ⚠️ The repeater can silently fall back to 2.4 GHz after any power interruption
# and stay there - it sat that way for ~10 days before being noticed, because
# the Pi's own diagnostics stay green (1000Mb/s, zero errors) throughout. If
# playback starts stuttering, measure the link FIRST and power-cycle the
# repeater if it reads ~45 Mbps. Only set this to "17" as a stopgap if the
# repeater cannot be fixed; a value between 45 and 196 buys nothing either way.
JELLYFIN_BITRATE_LAN = "23"
JELLYFIN_BITRATE_REMOTE = "10"

# Asgard's own tailnet address - Eclipse can't resolve the "asgard" hostname
# (tailscaled runs with --accept-dns=false here, no MagicDNS, see
# Claude/eclipse.md), so the speed test target below must be a bare IP.
ASGARD_TAILSCALE_IP = "100.126.205.100"
ASGARD_LAN_IP = "192.168.0.226"
SPEEDTEST_SIZE_MB = 25
# Separate listener for the LAN speed test. Serves the zero payload and NOTHING
# else - no status, no actions - so it is safe to open on the LAN interface,
# unlike PORT which carries the whole control surface. See act_speedtest().
SPEEDTEST_LAN_PORT = int(os.environ.get("ECLIPSE_SPEEDTEST_LAN_PORT", "9557"))

# Cache of the last speed test result, so the panel keeps showing a number
# across page reloads instead of resetting to "never tested" every time.
LAST_SPEEDTEST = {"mbps": None, "up_mbps": None, "when": 0.0, "path": ""}

CONNECTOR = "/sys/class/drm/card1-HDMI-A-1"
KODI_SEND = "/usr/bin/kodi-send"

# How often the /events poller asks, while anyone is watching. Status is SSH
# (one channel on the shared master — see SSH_BASE); Wolf is one local HTTP call.
EVENTS_STATUS_S = 5.0
EVENTS_WOLF_S = 3.0
EVENTS_TV_S = 5.0

# What the TV is playing, from Jellyfin's own session list (its API key comes in
# as a systemd credential). Asking Kodi itself would need its JSON-RPC, which is
# bound to the Pi's loopback — and a wedged Kodi is exactly when this matters.
JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096").rstrip("/")

# Jellyfin syncs must run one at a time - concurrent calls raise
# "Exception: Sync is already running" (Claude/eclipse.md).
sync_lock = threading.Lock()


def _control_dir():
    """A private directory for the SSH control socket.

    $RUNTIME_DIRECTORY when the unit sets RuntimeDirectory= (systemd creates
    it, owns it and removes it). Otherwise a fresh mkdtemp() — 0700 and
    unpredictably named, so nothing else on the box can pre-create or hijack
    the socket path even in a shared /tmp — removed again on exit.
    """
    runtime = os.environ.get("RUNTIME_DIRECTORY", "").split(":")[0]
    if runtime:
        return runtime
    path = tempfile.mkdtemp(prefix="eclipse-ssh-")
    atexit.register(shutil.rmtree, path, True)
    return path


CONTROL_DIR = _control_dir()

SSH_BASE = [
    "ssh", "-i", KEY,
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "LogLevel=ERROR",
    "-o", "ConnectTimeout=6",
    # Connection reuse. The first command opens a master connection that stays
    # up for ControlPersist seconds after its last use; every command in the
    # meantime is just a new channel on it. %C is a hash of host/port/user, so
    # the socket path stays far under the 108-byte unix socket limit.
    "-o", "ControlMaster=auto",
    "-o", "ControlPath=" + os.path.join(CONTROL_DIR, "%C"),
    "-o", "ControlPersist=120",
    # A master whose peer vanished (the Pi rebooted, its wifi dropped) would
    # otherwise hand out channels that hang until each command's timeout.
    # Keepalives notice a dead peer within ~30s and let the master exit.
    "-o", "ServerAliveInterval=10",
    "-o", "ServerAliveCountMax=2",
    "root@" + ECLIPSE,
]


_inflight_lock = threading.Lock()
_inflight = 0


def _drop_master():
    """Close the shared connection so the next command dials afresh — but only
    if nothing else is using it: `-O exit` ends every session on the master,
    and a library sync legitimately runs for tens of seconds. When something
    else IS in flight, the keepalives above retire a dead master on their own.
    """
    with _inflight_lock:
        if _inflight != 1:
            return
    try:
        subprocess.run(SSH_BASE[:-1] + ["-O", "exit", SSH_BASE[-1]],
                       capture_output=True, timeout=5)
    except Exception:
        pass


def ssh(remote_cmd, timeout=30):
    """Run a command on Eclipse. Returns (ok, output)."""
    global _inflight
    with _inflight_lock:
        _inflight += 1
    try:
        p = subprocess.run(SSH_BASE + [remote_cmd], capture_output=True, text=True,
                           timeout=timeout)
        out = (p.stdout + p.stderr).strip()
        if p.returncode == 255:
            # 255 is ssh's own failure (connect/auth/mux), not the remote
            # command's. Do not let a wedged master poison the next call.
            _drop_master()
        return p.returncode == 0, out
    except subprocess.TimeoutExpired:
        # Usually a master whose connection died half-open.
        _drop_master()
        return False, "timed out after " + str(timeout) + "s"
    except Exception as exc:
        return False, str(exc)
    finally:
        with _inflight_lock:
            _inflight -= 1


STATUS_CMD = (
    'echo "kodi=$(systemctl is-active kodi 2>/dev/null)"; '
    'echo "hdmi=$(cat ' + CONNECTOR + '/status 2>/dev/null)"; '
    'echo "edid=$(wc -c < ' + CONNECTOR + '/edid 2>/dev/null)"; '
    'echo "uptime=$(cut -d. -f1 /proc/uptime)"; '
    # SoC temperature (m°C), the firmware's throttle flags (under-voltage is
    # the classic Pi 5 problem, and it is invisible from Kodi), load, memory.
    'echo "temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"; '
    'echo "throttled=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)"; '
    'echo "load=$(cut -d" " -f1-3 /proc/loadavg)"; '
    "echo \"mem=$(awk '/^MemTotal|^MemAvailable/ {printf \"%s \", $2}' /proc/meminfo)\"; "
    "echo \"mode=$(grep -oE 'Display [0-9]+x[0-9]+ @ [0-9.]+' "
    '/storage/.kodi/temp/kodi.log 2>/dev/null | tail -1)"; '
    'echo "jellyfin=$(grep -oE \'"address": *"[^"]+"\' '
    + JELLYFIN_ADDON_DIR + '/data.json 2>/dev/null | cut -d\'"\' -f4)"'
)


def _throttle(bits):
    """`vcgencmd get_throttled` → what is wrong now, and what has been since boot.

    Low bits are the present state, bits 16-19 latch "has happened": an
    under-voltage that came and went during a 4K remux still shows up here.
    """
    names = ("under-voltage", "frequency capped", "throttled", "soft temp limit")
    return {
        "now": [n for i, n in enumerate(names) if bits & (1 << i)],
        "since_boot": [n for i, n in enumerate(names) if bits & (1 << (16 + i))],
    }


def _jellyfin_mode(address):
    if address == JELLYFIN_REMOTE:
        return "remote"
    if address == JELLYFIN_LAN:
        return "lan"
    return "unknown"


_status_lock = threading.Lock()
_status = {"at": 0.0, "value": None, "inflight": None}


def get_status():
    """The Pi's status, at most STATUS_TTL old, from at most one SSH call.

    The first caller after the cache expires does the SSH; anyone arriving
    while it runs waits on its Event and shares the answer, rather than
    opening a second session for the same few lines.
    """
    with _status_lock:
        fresh = _status["value"] is not None and time.monotonic() - _status["at"] < STATUS_TTL
        if fresh:
            return _with_speedtest(_status["value"])
        done = _status["inflight"]
        leader = done is None
        if leader:
            done = _status["inflight"] = threading.Event()
    if not leader:
        done.wait(20)
        with _status_lock:
            value = _status["value"]
        if value is not None:
            return _with_speedtest(value)
        # The leader failed outright; fall through and try ourselves.
    try:
        value = _fetch_status()
    finally:
        if leader:
            with _status_lock:
                _status["inflight"] = None
            done.set()
    with _status_lock:
        _status.update(at=time.monotonic(), value=value)
    return _with_speedtest(value)


def invalidate_status():
    """After an action, so the next poll shows its effect rather than the cache."""
    with _status_lock:
        _status["at"] = 0.0


def _with_speedtest(st):
    # Not cached with the rest: act_speedtest updates it independently.
    st = dict(st)
    st["speed_mbps"] = LAST_SPEEDTEST["mbps"]
    st["speed_up_mbps"] = LAST_SPEEDTEST["up_mbps"]
    st["speed_when"] = LAST_SPEEDTEST["when"]
    st["speed_path"] = LAST_SPEEDTEST["path"]
    return st


def _fetch_status():
    ok, out = ssh(STATUS_CMD, timeout=15)
    st = {"reachable": ok, "kodi": "?", "hdmi": "?", "edid": 0,
          "uptime": 0, "mode": "", "jellyfin": "", "error": "",
          "temp": None, "throttled": None, "load": None, "mem_used": None,
          "at": int(time.time())}
    if not ok:
        st["error"] = out
        return st
    for line in out.splitlines():
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip()
        try:
            if k in ("edid", "uptime"):
                st[k] = int(v or 0)
            elif k == "temp":
                st["temp"] = round(int(v) / 1000, 1) if v else None
            elif k == "throttled":
                st["throttled"] = _throttle(int(v, 16)) if v else None
            elif k == "load":
                st["load"] = [float(x) for x in v.split()[:3]] or None
            elif k == "mem":
                total, avail = (int(x) for x in v.split()[:2])
                st["mem_used"] = round(1 - avail / total, 3) if total else None
            elif k in st:
                st[k] = v
        except ValueError:
            pass
    # A connected link with no picture is the classic failure mode: Kodi started
    # before the TV came up and never re-probes. Flag it explicitly.
    st["needs_kodi_restart"] = (
        st["hdmi"] == "connected" and st["kodi"] == "active" and not st["mode"]
    )
    st["jellyfin_mode"] = _jellyfin_mode(st["jellyfin"])
    return st


def act_speedtest():
    """Measure real download throughput from Eclipse's own vantage point.

    Deliberately not a ping or a tiny request - this addon has no ABR (see
    Claude/eclipse.md), so what matters is sustained throughput at the sizes
    a real remux actually pulls. Downloads a fixed-size blob of zeros, which
    sidesteps needing a Jellyfin API key on Eclipse.

    Measures whichever path playback is ACTUALLY using right now, picked from
    the Jellyfin address the addon is currently pointed at:

      lan     -> ASGARD_LAN_IP:SPEEDTEST_LAN_PORT   (direct, the fast path)
      remote  -> ASGARD_TAILSCALE_IP:PORT           (WireGuard, much slower)

    This used to always test the Tailscale path. With the addon on LAN that
    reported ~19 Mbps of WireGuard overhead on a gigabit link - a real number
    for the remote path, but not the one anyone wants when the box is local.

    The LAN test needs its own port because PORT (9554) is deliberately absent
    from allowedTCPPorts and reachable only over trusted tailscale0. Opening it
    to the LAN would expose every action on this panel - including `reboot` -
    to anything on the wifi. SPEEDTEST_LAN_PORT serves the payload and nothing
    else, so it is safe to open.
    """
    st = get_status()
    if _jellyfin_mode(st.get("jellyfin", "")) == "remote":
        url = "http://" + ASGARD_TAILSCALE_IP + ":" + str(PORT) + "/speedtest-data"
        path = "Tailscale"
    else:
        url = "http://" + ASGARD_LAN_IP + ":" + str(SPEEDTEST_LAN_PORT) + "/"
        path = "LAN"
    ok, out = ssh("curl -s -o /dev/null -w '%{speed_download}' '" + url + "'", timeout=60)
    if not ok:
        return False, "speed test failed: " + out
    try:
        mbps = float(out.strip()) * 8 / 1_000_000
    except ValueError:
        return False, "speed test failed: bad reading (" + out + ")"
    LAST_SPEEDTEST["mbps"] = round(mbps, 1)

    # Upload, same payload in the other direction. Streamed from dd via `curl
    # -T -` so the Pi never writes a 25MB temp file to its SD card, and drained
    # by SpeedtestHandler.do_PUT. Only meaningful on the LAN path - the remote
    # path PUTs to /speedtest-data on the control port, which has no PUT route,
    # so upload is skipped (and left as None) when testing over Tailscale.
    up_mbps = None
    if path == "LAN":
        up_cmd = ("dd if=/dev/zero bs=1M count=" + str(SPEEDTEST_SIZE_MB)
                  + " 2>/dev/null | curl -s -o /dev/null -w '%{speed_upload}'"
                  + " -X PUT -T - '" + url + "'")
        up_ok, up_out = ssh(up_cmd, timeout=60)
        if up_ok:
            try:
                up_mbps = round(float(up_out.strip()) * 8 / 1_000_000, 1)
            except ValueError:
                up_mbps = None
    LAST_SPEEDTEST["up_mbps"] = up_mbps
    LAST_SPEEDTEST["when"] = time.time()
    LAST_SPEEDTEST["path"] = path

    if up_mbps is not None:
        return True, "{:.1f} down / {:.1f} up Mbps over {}".format(mbps, up_mbps, path)
    return True, "{:.1f} Mbps down over {}".format(mbps, path)


def act_restart_kodi():
    return ssh("systemctl restart kodi && echo restarted", timeout=30)


def act_reboot():
    # Fire and forget - the box drops the connection as it goes down.
    ssh("(sleep 1; reboot) >/dev/null 2>&1 &", timeout=10)
    return True, "reboot issued"


def act_jellyfin_toggle():
    """Swap the Jellyfin addon between Asgard's LAN and Tailscale addresses.

    Both data.json (session/server record) and settings.xml (addon settings
    screen) carry the address independently - the addon reads data.json at
    runtime, but settings.xml drifting out of sync would show the stale
    address in its own settings UI. Restarting Kodi is what makes the addon
    re-read data.json and reconnect.

    Bundles the maxBitrate cap with the address on purpose: it's the same
    decision either way. LAN = uncapped direct play, which the RP-BE58's
    5 GHz backhaul carries at ~196 Mbps (see the JELLYFIN_BITRATE_LAN
    comment - and note that number collapses to ~45 if the repeater falls
    back to 2.4 GHz). Remote = capped to ~8 Mbps, the ceiling the WiFi
    regulatory-domain bug actually allows (see Claude/eclipse.md) - direct
    play at full bitrate over that link just stalls, and capping it is what
    makes it watchable.
    """
    ok, current = ssh(
        'grep -oE \'"address": *"[^"]+"\' ' + JELLYFIN_ADDON_DIR
        + "/data.json 2>/dev/null | cut -d'\"' -f4",
        timeout=10,
    )
    if not ok or not current.strip():
        return False, "could not read current Jellyfin address"
    current = current.strip()
    target = JELLYFIN_REMOTE if current != JELLYFIN_REMOTE else JELLYFIN_LAN
    bitrate = JELLYFIN_BITRATE_REMOTE if target == JELLYFIN_REMOTE else JELLYFIN_BITRATE_LAN
    cmd = (
        "sed -i 's#" + current + "#" + target + "#' "
        + JELLYFIN_ADDON_DIR + "/data.json " + JELLYFIN_ADDON_DIR + "/settings.xml"
        + " && sed -i -E 's#<setting id=\"maxBitrate\"[^>]*>[0-9]+</setting>#"
        + '<setting id="maxBitrate">' + bitrate + "</setting>#' "
        + JELLYFIN_ADDON_DIR + "/settings.xml"
        + " && systemctl restart kodi && echo SWAPPED"
    )
    ok, out = ssh(cmd, timeout=30)
    if not ok or "SWAPPED" not in out:
        return False, "swap failed: " + out
    label = "Tailscale (remote)" if target == JELLYFIN_REMOTE else "LAN"
    quality = "capped ~8 Mbps" if target == JELLYFIN_REMOTE else "uncapped direct play"
    return True, "Jellyfin server switched to " + label + " (" + quality + ")"


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


def tv_playing():
    """Jellyfin sessions playing on the TV box: the Kodi addon reports itself as
    client "Kodi" (device name as set on the Pi). None = Jellyfin not answering."""
    cred = os.environ.get("CREDENTIALS_DIRECTORY")
    try:
        with open(os.path.join(cred, "jellyfin-api-key")) as fh:
            key = fh.read().strip()
    except (OSError, TypeError):
        return None
    req = urllib.request.Request(JELLYFIN_URL + "/Sessions?activeWithinSeconds=90",
                                 headers={"X-Emby-Token": key})
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            sessions = json.load(r)
    except (OSError, ValueError):
        return None
    out = []
    for s in sessions:
        item = s.get("NowPlayingItem")
        client, device = s.get("Client", ""), s.get("DeviceName", "")
        if not item or not ("kodi" in client.lower() or any(w in device.lower() for w in ("eclipse", "libreelec", "kodi"))):
            continue
        ps = s.get("PlayState", {})
        run, pos = item.get("RunTimeTicks") or 0, ps.get("PositionTicks") or 0
        sub_ = item.get("SeriesName") or (str(item["ProductionYear"]) if item.get("ProductionYear") else "")
        if item.get("SeriesName") and item.get("IndexNumber") is not None:
            sub_ = "%s · S%02dE%02d" % (item["SeriesName"], item.get("ParentIndexNumber", 0), item["IndexNumber"])
        out.append({
            "title": item.get("Name", ""), "sub": sub_, "user": s.get("UserName", ""),
            "poster": item.get("SeriesId") or item.get("AlbumId") or item.get("Id"),
            "method": ps.get("PlayMethod", ""), "paused": bool(ps.get("IsPaused")),
            "progress": round(pos / run, 4) if run else None,
            "remaining_s": int((run - pos) / 1e7) if run else None,
        })
    return out


def act_sync_library():
    """Both libraries, one after the other (syncs must not overlap anyway).
    The dashboard's one Sync button: new films and new episodes are almost
    always wanted together, and an up-to-date library syncs in seconds."""
    ok1, m1 = _sync(MOVIES_ID, "Movies")
    ok2, m2 = _sync(SHOWS_ID, "TV Shows")
    return ok1 and ok2, m1 + " · " + m2


# ── Wolf sessions (Moonlight streams served by Sisyphus) ─────────────────────
# Wolf never reaps a session whose client vanished (Claude/wolf.md), and a stuck
# one keeps its virtual pads alive. wolf-bridge on Sisyphus (Modules/Gaming/
# wolf.nix) lists and stops sessions, and only answers Asgard — so the browser
# never calls it; this panel proxies it server-side.
WOLF_BRIDGE = os.environ.get("WOLF_BRIDGE_URL", "http://sisyphus:9560").rstrip("/")
_ECLIPSE_IPS = {"at": 0.0, "ips": {ECLIPSE}}


def _eclipse_ips():
    """The Pi's own addresses (tailnet + LAN), learned over the SSH link we
    already hold, so a session from it can be labelled "Eclipse (TV)" whichever
    network Moonlight used. Refreshed every 10 minutes in the background — an
    offline Pi makes that ssh take seconds, and the session list mustn't wait
    on a cosmetic label."""
    if time.time() - _ECLIPSE_IPS["at"] > 600:
        _ECLIPSE_IPS["at"] = time.time()

        def refresh_ips():
            ok, out = ssh("ip -o -4 addr show | awk '{print $4}'", timeout=8)
            if ok:
                _ECLIPSE_IPS["ips"] = {ECLIPSE} | {
                    ln.split("/")[0] for ln in out.split() if ln and not ln.startswith("127.")
                }
        threading.Thread(target=refresh_ips, daemon=True).start()
    return _ECLIPSE_IPS["ips"]


def _bridge(method, path, timeout=4):
    req = urllib.request.Request(WOLF_BRIDGE + path, method=method,
                                 headers={"X-Dash": "1"} if method == "POST" else {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {"ok": False, "error": f"bridge answered {e.code}"}


def wolf_sessions():
    try:
        status, body = _bridge("GET", "/sessions")
    except (OSError, ValueError) as e:
        return {"wolf": "unreachable", "sessions": [], "error": str(e)[:160]}
    if status != 200:
        return {"wolf": "unreachable", "sessions": [], "error": f"bridge answered {status}"}
    ips = _eclipse_ips()
    for sess in body.get("sessions", []):
        sess["client_label"] = "Eclipse (TV)" if sess.get("client_ip") in ips else (sess.get("client_ip") or "unknown")
    return body


def wolf_stop(session_id):
    if not session_id.isdigit():
        return 400, {"ok": False, "error": "bad session id"}
    try:
        return _bridge("POST", f"/sessions/{session_id}/stop", timeout=8)
    except (OSError, ValueError) as e:
        return 502, {"ok": False, "error": f"Sisyphus unreachable: {e}"[:160]}


ACTIONS = {
    "restart-kodi": ("Restart Kodi", act_restart_kodi),
    "reboot": ("Reboot Pi", act_reboot),
    "sync-library": ("Sync library", act_sync_library),
    # MarsBar's buttons — one library each (Modules/Server/marsbar.nix).
    "sync-movies": ("Sync movies", lambda: _sync(MOVIES_ID, "Movies")),
    "sync-shows": ("Sync TV shows", lambda: _sync(SHOWS_ID, "TV Shows")),
    "jellyfin-toggle": ("Switch Jellyfin path", act_jellyfin_toggle),
    "speedtest": ("Link test", act_speedtest),
}


# ── Live hub: one poller, any number of /events clients ─────────────────────
# Everything the admin page shows, kept here and pushed on change:
#   status    get_status() (SSH, cached)      every EVENTS_STATUS_S
#   tv        tv_playing() (Jellyfin)          every EVENTS_TV_S
#   wolf      wolf_sessions()                 every EVENTS_WOLF_S
#   activity  the last 12 actions, from ANY dashboard — so a Restart Kodi
#             tapped on MarsBar shows up on the admin page too, and the log
#             survives a reload
#   busy      actions running right now — every open page greys that button
# The poller sleeps while nobody is connected.

class Hub:
    def __init__(self):
        self.cond = threading.Condition()
        self.version = 0
        self.state = {"status": None, "tv": None, "wolf": None, "activity": [], "busy": {}}
        self.watchers = 0
        self.wake = threading.Event()

    def publish(self, key, value):
        with self.cond:
            if self.state.get(key) == value:
                return
            self.state[key] = value
            self.version += 1
            self.cond.notify_all()

    def log(self, action, ok, message):
        entry = {"t": int(time.time()), "action": action, "ok": ok, "message": message}
        with self.cond:
            self.state["activity"] = ([entry] + self.state["activity"])[:12]
            self.version += 1
            self.cond.notify_all()

    def set_busy(self, name, on):
        with self.cond:
            busy = dict(self.state["busy"])
            if on:
                if name in busy:
                    return False  # already running — one at a time per action
                busy[name] = int(time.time())
            else:
                busy.pop(name, None)
            self.state["busy"] = busy
            self.version += 1
            self.cond.notify_all()
        return True

    def poller(self):
        status_at = wolf_at = tv_at = 0.0
        while True:
            if self.watchers > 0:
                now = time.monotonic()
                if now - wolf_at >= EVENTS_WOLF_S:
                    wolf_at = now
                    self.publish("wolf", wolf_sessions())
                if now - tv_at >= EVENTS_TV_S:
                    tv_at = now
                    tv = tv_playing()
                    self.publish("tv", {"ok": tv is not None, "playing": tv or []})
                if now - status_at >= EVENTS_STATUS_S:
                    status_at = now
                    self.publish("status", get_status())
            else:
                status_at = wolf_at = tv_at = 0.0
            if self.wake.wait(1.0):
                self.wake.clear()
                status_at = 0.0  # an action finished or a client joined: look now


HUB = Hub()


def run_action(name):
    entry = ACTIONS.get(name)
    if not entry:
        return 400, {"ok": False, "message": "unknown action"}
    label, fn = entry
    if not HUB.set_busy(name, True):
        return 409, {"ok": False, "action": label, "message": label + " is already running"}
    try:
        ok, msg = fn()
    except Exception as exc:  # noqa: BLE001 — report, never kill the handler
        ok, msg = False, "%s: %s" % (type(exc).__name__, exc)
    finally:
        HUB.set_busy(name, False)
    invalidate_status()
    HUB.log(label, ok, msg or label)
    HUB.wake.set()
    return 200, {"ok": ok, "action": label, "message": msg or label}


_ZEROS = b"\0" * (256 * 1024)


def send_zeros(handler):
    """Stream the SPEEDTEST_SIZE_MB zero-filled speed-test payload.

    Plain zeros generated on the fly - the point is raw throughput over the
    path under test, not disk I/O or Jellyfin auth - in fixed chunks, so this
    never buffers 25MB in RAM. Shared by the Tailscale route on the control port
    (/speedtest-data) and the LAN-only SpeedtestHandler.
    """
    size = SPEEDTEST_SIZE_MB * 1024 * 1024
    handler.send_response(200)
    handler.send_header("Content-Type", "application/octet-stream")
    handler.send_header("Content-Length", str(size))
    handler.end_headers()
    sent = 0
    try:
        while sent < size:
            n = min(len(_ZEROS), size - sent)
            handler.wfile.write(_ZEROS[:n])
            sent += n
    except (BrokenPipeError, ConnectionResetError):
        pass


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _cors(self):
        origin = self.headers.get("Origin")
        if origin and origin in DASH_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")

    def _send(self, code, body, ctype):
        raw = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        if ctype == "application/json":
            self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(raw)

    def events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self._cors()
        self.end_headers()
        sent = {}
        with HUB.cond:
            HUB.watchers += 1
        HUB.wake.set()
        try:
            self.wfile.write(b"retry: 3000\n\n")
            seen, last_write = -1, time.monotonic()
            while True:
                with HUB.cond:
                    if HUB.version == seen:
                        HUB.cond.wait(timeout=15)
                    seen = HUB.version
                    state = dict(HUB.state)
                for key, value in state.items():
                    if value is None or sent.get(key) == value:
                        continue
                    sent[key] = value
                    self.wfile.write(("event: %s\ndata: %s\n\n" % (key, json.dumps(value))).encode())
                    last_write = time.monotonic()
                if time.monotonic() - last_write >= 15:
                    # A real event, so the page can notice a half-open link.
                    self.wfile.write(b"event: ping\ndata: {}\n\n")
                    last_write = time.monotonic()
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with HUB.cond:
                HUB.watchers -= 1

    def do_GET(self):
        path = self.path.split("?")[0].strip("/")
        if path == "status":
            self._send(200, json.dumps(get_status()), "application/json")
        elif path == "events":
            self.events()
        elif path == "wolf/sessions":
            self._send(200, json.dumps(wolf_sessions()), "application/json")
        elif path == "speedtest-data":
            # Raw throughput over this exact Tailscale path (the remote case
            # in act_speedtest).
            send_zeros(self)
        else:
            self._send(404, "not found", "text/plain")

    def do_OPTIONS(self):
        # CORS preflight. Only the dashboards get a yes — which, with the
        # X-Dash requirement below, is what keeps every other origin out.
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

    def do_POST(self):
        path = self.path.split("?")[0].strip("/")
        if path.startswith("wolf/stop/"):
            if self.headers.get("X-Dash") != "1":
                self._send(403, json.dumps({"ok": False, "error": "missing X-Dash header"}),
                           "application/json")
                return
            sid = path[len("wolf/stop/"):]
            code, body = wolf_stop(sid)
            if code == 200 or code == 404:
                HUB.log("End stream", True, "Wolf stream " + sid + (" ended" if code == 200 else " was already gone"))
            else:
                HUB.log("End stream", False, "could not end stream " + sid + ": " + str(body.get("error", code)))
            HUB.wake.set()
            self._send(code, json.dumps(body), "application/json")
            return
        if not path.startswith("act/"):
            self._send(404, json.dumps({"ok": False, "message": "not found"}),
                       "application/json")
            return
        # Every action is a body-less POST — a "simple" request that a browser
        # sends cross-origin WITHOUT asking first. With the old CORS `*`, any web
        # page open on a tailnet browser could reboot the Pi with one fetch().
        # Requiring a custom header forces a preflight (do_OPTIONS), which only
        # the dashboards pass; same-origin callers (this panel's own page,
        # MarsBar through its serve proxy) just send it.
        if self.headers.get("X-Dash") != "1":
            self._send(403, json.dumps({"ok": False, "message": "missing X-Dash header"}),
                       "application/json")
            return
        code, body = run_action(path[4:])
        self._send(code, json.dumps(body), "application/json")

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class SpeedtestHandler(http.server.BaseHTTPRequestHandler):
    """LAN-facing data sink. Answers GET with the zero payload and nothing else.

    Kept as a separate handler on a separate port ON PURPOSE. The main Handler
    carries /status and every /act/ verb including `reboot`, and PORT is
    tailnet-only for that reason. This one has no control surface at all, so
    opening it on the LAN interface risks nothing beyond wasted bandwidth.
    """

    def do_GET(self):
        send_zeros(self)

    def do_PUT(self):
        """Drain an upload and discard it - the counterpart to do_GET.

        Read in chunks rather than one .read(n): the client streams this with
        `curl -T -`, so it arrives chunked and buffering the whole 25MB just to
        throw it away would be pointless memory churn.
        """
        remaining = self.headers.get("Content-Length")
        try:
            if remaining is not None:
                remaining = int(remaining)
                while remaining > 0:
                    got = self.rfile.read(min(256 * 1024, remaining))
                    if not got:
                        break
                    remaining -= len(got)
            else:
                # Chunked transfer - no Content-Length to count down from.
                while True:
                    line = self.rfile.readline(65)
                    if not line:
                        break
                    size = int(line.strip().split(b";")[0] or b"0", 16)
                    if size == 0:
                        self.rfile.readline()
                        break
                    left = size
                    while left > 0:
                        got = self.rfile.read(min(256 * 1024, left))
                        if not got:
                            break
                        left -= len(got)
                    self.rfile.readline()
        except (BrokenPipeError, ConnectionResetError, ValueError):
            return
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        self.send_response(405)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    # systemd stops us with SIGTERM; turning it into a normal exit is what lets
    # atexit remove a mkdtemp() control directory (see _control_dir).
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    threading.Thread(
        target=Server(("0.0.0.0", SPEEDTEST_LAN_PORT), SpeedtestHandler).serve_forever,
        daemon=True,
    ).start()
    threading.Thread(target=HUB.poller, daemon=True).start()
    Server(("0.0.0.0", PORT), Handler).serve_forever()
