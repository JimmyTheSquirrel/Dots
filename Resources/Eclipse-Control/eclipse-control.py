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
  POST /ctl/…            Bluetooth: search, pair, connect, rename … (needs `X-Dash: 1`)
  POST /net/scan         search for Wi-Fi                          (needs `X-Dash: 1`)
  POST /net/wired        back to the cable, wired only (home)
  POST /net/wifi[/<id>]  Wi-Fi (away): a saved network, or a new one with
                         {"pass": "…"} in the body — sent on to the Pi via stdin
  POST /net/forget/<id>  forget a saved Wi-Fi network

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
import re
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
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
# Controllers + subtitles. Slower than the rest on purpose: this one shells
# out to bluetoothctl, which talks DBus to a bluetoothd that has already shown
# it can burn CPU (21 min over 6 days with one paired, powered-OFF pad).
EVENTS_CTL_S = 8.0

# A bounded discovery window. bluetoothctl's --timeout makes `scan on` return on
# its own; without it the scan runs forever and holds an SSH channel open. It
# runs in the BACKGROUND (start_scan) and is not an /act/ action, so it never
# greys the rest of the panel; while it runs, what it finds is pushed every
# EVENTS_SCAN_S as a `scan` event, to every open dashboard.
CTL_SCAN_S = int(os.environ.get("CTL_SCAN_SECONDS", "45"))
EVENTS_SCAN_S = 3.0
# How long the last search's results stay up after it ends, so a device found
# in the last seconds can still be tapped.
CTL_SCAN_KEEP_S = 180
# The most unpaired devices a search lists (and asks `info` about): a block of
# flats can show dozens of phones and TVs.
CTL_SCAN_MAX = 24
# Names WE give devices ("Rock's pad"), kept on Asgard — they never touch the
# Pi, so no caller string goes near its root shell. Both dashboards read them
# from here, so a rename on one shows on the other.
CTL_NAME_MAX = 24

# Anchored and upper-case. Any MAC from a dashboard is interpolated into a
# string that ssh() hands to a shell AS ROOT on the Pi, so it is validated here
# AND checked against the Pi's own device list before it goes near a command.
# Same precedent as wolf_stop()'s session_id.isdigit().
MAC_RE = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$")

# ── Network: the cable, Wi-Fi, and switching between them ───────────────────
# Wired-only is the house rule (Resources/Eclipse-Box/network/, 2026-10-09): the
# Pi once dual-homed and sent a 4K game stream over its own weak radio while the
# cable sat idle. The dashboards can switch it to Wi-Fi on purpose (away from
# home) and back, and join a network with its password; eclipse-net.sh does the
# switch ON the Pi, detached, and undoes it if the Pi can't get online.
#
# Every switch is safe to make remotely only because ECLIPSE is the Pi's tailnet
# address: whichever link it is on, the control channel finds it again.
EVENTS_NET_S = 8.0
EVENTS_NETSW_S = 3.0           # while a switch runs: watch for its result
# Longest a switch can take before we stop waiting: connman restart + ~25 s to
# find the network + ~30 s to get online, and the same again to put it back.
NET_SWITCH_MAX_S = 180
NET_SCAN_KEEP_S = 180
NET_LIST_MAX = 24
NET_DIR = "/storage/.cache/eclipse-net"
NET_SCRIPT = os.environ.get("ECLIPSE_NET_SCRIPT") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "eclipse-net.sh")
# connman service ids, as connmanctl prints them. A dashboard-supplied id is
# matched against this AND the Pi's own list before it reaches a root shell.
# Hidden networks (wifi_<mac>_hidden_…) have no SSID to join by, so they never
# match; enterprise (ieee8021x) ones match but are not joinable from here.
WIFI_RE = re.compile(r"^wifi_[0-9a-f]{12}_([0-9a-f]{2,64})_managed_(psk|sae|wep|none|ieee8021x)$")
WIRED_RE = re.compile(r"^ethernet_[0-9a-f]{12}_cable$")
JOINABLE = ("psk", "sae", "wep", "none")

# Subtitle defaults are a JELLYFIN USER setting, not a Kodi one. The addon runs
# set_audio_subs() about 2s into every playback and calls showSubtitles(False)
# when no track index resolves, so anything set Kodi-side is overwritten on
# every single play. The only durable lever is the server-side preference of
# the user Eclipse logs in as. See Claude/eclipse.md.
JELLYFIN_TV_USER = os.environ.get("JELLYFIN_TV_USER", "")
# Jellyfin's SubtitlePlaybackMode enum. "Always" = subtitles on by default;
# "Default" = only what the media itself flags as default/forced.
SUBS_ON, SUBS_OFF = "Always", "Default"
SUB_LANGS = {"eng": "English", "jpn": "Japanese", "fre": "French",
             "spa": "Spanish", "ger": "German", "": "No preference"}

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


def ssh(remote_cmd, timeout=30, stdin=None):
    """Run a command on Eclipse. Returns (ok, output). `stdin` is fed to the
    remote command — the way anything secret (a Wi-Fi password) gets there:
    never in remote_cmd, which is on a command line on both machines."""
    global _inflight
    with _inflight_lock:
        _inflight += 1
    try:
        p = subprocess.run(SSH_BASE + [remote_cmd], capture_output=True, text=True,
                           timeout=timeout, input=stdin if stdin is not None else "")
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


# ── Controllers and subtitles ────────────────────────────────────────────────
# WHY THIS IS NOT JUST "is BlueZ connected". The DualSense on this box fails to
# bind its kernel driver with -5 (EIO) often enough to matter: 17 reconnect
# cycles and 3 probe failures in the logs, and /storage/dualsense-repair.log
# records the signature -- BlueZ reporting `Connected: yes` alongside
# "input nodes: 0 match(es)". In that state the pad is a bonded Bluetooth
# device producing NO input at all. A card that trusted BlueZ would show a
# working controller in precisely the broken case, which is worse than useless.
#
# So `paired` and `connected` come from BlueZ, but `live` -- the only one the
# card shows as working -- means an actual node exists in /proc/bus/input.
# One look at everything, every EVENTS_CTL_S while a page is watching:
#   adapter=  bluetoothctl show (Powered, Discovering, Pairable)
#   dev=      every device BlueZ knows (paired, and anything a search found)
#   flag=     Paired / Trusted / Connected membership (bluetoothctl's filters)
#   btbat=    BlueZ's Battery1 percentage, for connected devices that have one
#   input=    /proc/bus/input/devices names AND Uniq — for a Bluetooth HID
#             device Uniq is its MAC, so `live` matches the exact pad, not
#             just one with the same name (two DualSenses share a name)
#   bat=      kernel power_supply: hid-playstation's ps-controller-battery-<mac>
# (The network has its own card and poll now: NET_CMD.)
# Generic "Key: value" seds + filtering in Python: LibreELEC's sed is busybox.
CTL_CMD = (
    "bluetoothctl show 2>/dev/null | sed -n 's/^[[:space:]]*\\([A-Za-z]*\\): /adapter=\\1=/p'; "
    "bluetoothctl devices 2>/dev/null | sed -n 's/^Device /dev=/p'; "
    "for f in Paired Trusted Connected; do bluetoothctl devices $f 2>/dev/null"
    " | sed -n \"s/^Device \\([0-9A-Fa-f:]*\\).*/flag=$f \\1/p\"; done; "
    "for m in $(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}'); do"
    " bluetoothctl info \"$m\" 2>/dev/null"
    " | sed -n \"s/^[[:space:]]*Battery Percentage: .*(\\([0-9]*\\)).*/btbat=$m \\1/p\"; done; "
    "grep -E '^(N: Name|U: Uniq)=' /proc/bus/input/devices 2>/dev/null | sed 's/^/input=/'; "
    "for b in /sys/class/power_supply/*; do [ -r \"$b/capacity\" ] &&"
    " echo \"bat=${b##*/} $(cat \"$b/capacity\" 2>/dev/null) $(cat \"$b/status\" 2>/dev/null)\"; done"
)

# What a running search has found: every device BlueZ knows that is NOT paired
# (a pad in pairing mode, a phone…), each with its signal and icon. Devices
# with no name yet (BlueZ shows those as their MAC) skip the `info` call.
SCAN_CMD = (
    "p=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'); "
    "bluetoothctl devices 2>/dev/null | head -" + str(CTL_SCAN_MAX * 2) + " | while read -r _ m name; do"
    " case \" $p \" in *\"$m\"*) continue;; esac;"
    " echo \"found=$m $name\";"
    " case \"$name\" in ??-??-??-??-??-??) continue;; esac;"
    " bluetoothctl info \"$m\" 2>/dev/null | sed -n"
    " -e \"s/^[[:space:]]*RSSI: \\(.*\\)/fi=$m rssi \\1/p\""
    " -e \"s/^[[:space:]]*Icon: \\(.*\\)/fi=$m icon \\1/p\"; done"
)

_UNNAMED = re.compile(r"^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$", re.I)


def _kind(name, icon=""):
    """gamepad / audio / keyboard / mouse / remote / phone / other — from
    BlueZ's Icon when it has one, else the name."""
    n, i = (name or "").lower(), (icon or "").lower()
    if i.startswith("input-gaming") or any(w in n for w in (
            "controller", "dualsense", "dualshock", "gamepad", "xbox", "joy-con",
            "8bitdo", "stadia", "joystick")):
        return "gamepad"
    if i.startswith("audio") or any(w in n for w in (
            "buds", "airpods", "headphone", "headset", "speaker", "soundbar", "wh-", "wf-")):
        return "audio"
    if i == "input-keyboard" or "keyboard" in n:
        return "keyboard"
    if i in ("input-mouse", "input-tablet") or "mouse" in n or "trackpad" in n:
        return "mouse"
    if "remote" in n:
        return "remote"
    if i == "phone" or any(w in n for w in ("iphone", "galaxy", "pixel", "phone")):
        return "phone"
    return "other"


def _rssi(v):
    """'0xffffffc4 (-60)' on newer BlueZ, '-60' on older: the signed dBm."""
    m = re.search(r"\((-?\d+)\)", v or "") or re.match(r"^\s*(-?\d+)\s*$", v or "")
    return int(m.group(1)) if m else None


# ── Our names for devices ────────────────────────────────────────────────────
_STATE_DIR = os.environ.get("STATE_DIRECTORY", "").split(":")[0]
NAMES_FILE = os.environ.get("CTL_NAMES_FILE") or (
    os.path.join(_STATE_DIR, "ctl-names.json") if _STATE_DIR else "")
_names_lock = threading.Lock()


def _load_names():
    try:
        with open(NAMES_FILE) as fh:
            raw = json.load(fh)
        return {k.upper(): str(v)[:CTL_NAME_MAX] for k, v in raw.items()
                if MAC_RE.match(k.upper()) and str(v).strip()}
    except (OSError, ValueError, AttributeError, TypeError):
        return {}


NAMES = _load_names()


def _save_names():
    if not NAMES_FILE:
        return
    tmp = NAMES_FILE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(NAMES, fh, indent=1, sort_keys=True)
    os.replace(tmp, NAMES_FILE)


def clean_name(raw):
    """A name a person typed: whitespace collapsed, no control or format
    characters, at most CTL_NAME_MAX characters. It is only ever shown (escaped
    by the page) and stored here — never sent to the Pi."""
    s = unicodedata.normalize("NFC", raw or "")
    s = "".join(ch for ch in s if unicodedata.category(ch)[0] not in "CZ" or ch == " ")
    return " ".join(s.split())[:CTL_NAME_MAX].strip()


def _subs_state():
    """Caitlin's server-side subtitle preference, or None if unreadable.

    This is a Jellyfin USER setting; see JELLYFIN_TV_USER above for why it
    cannot live on the Kodi side.
    """
    if not JELLYFIN_TV_USER:
        return None
    cred = os.environ.get("CREDENTIALS_DIRECTORY")
    try:
        with open(os.path.join(cred, "jellyfin-api-key")) as fh:
            key = fh.read().strip()
    except (OSError, TypeError):
        return None
    req = urllib.request.Request(JELLYFIN_URL + "/Users/" + JELLYFIN_TV_USER,
                                 headers={"X-Emby-Token": key})
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            cfg = json.load(r).get("Configuration", {})
    except (OSError, ValueError):
        return None
    lang = cfg.get("SubtitleLanguagePreference") or ""
    return {"on": cfg.get("SubtitleMode") == SUBS_ON,
            "mode": cfg.get("SubtitleMode", ""),
            "lang": lang, "lang_name": SUB_LANGS.get(lang, lang)}


def _set_subs(mode=None, lang=None):
    """PATCH the TV user's subtitle preference. Jellyfin wants the WHOLE
    Configuration object back, so read-modify-write -- POSTing only the changed
    key silently resets everything else to defaults."""
    if not JELLYFIN_TV_USER:
        return False, "no Jellyfin user configured"
    cred = os.environ.get("CREDENTIALS_DIRECTORY")
    try:
        with open(os.path.join(cred, "jellyfin-api-key")) as fh:
            key = fh.read().strip()
    except (OSError, TypeError):
        return False, "no Jellyfin API key"
    hdr = {"X-Emby-Token": key, "Content-Type": "application/json"}
    try:
        req = urllib.request.Request(JELLYFIN_URL + "/Users/" + JELLYFIN_TV_USER, headers=hdr)
        with urllib.request.urlopen(req, timeout=5) as r:
            cfg = json.load(r).get("Configuration", {})
        if mode is not None:
            cfg["SubtitleMode"] = mode
        if lang is not None:
            cfg["SubtitleLanguagePreference"] = lang
        put = urllib.request.Request(
            JELLYFIN_URL + "/Users/" + JELLYFIN_TV_USER + "/Configuration",
            data=json.dumps(cfg).encode(), headers=hdr, method="POST")
        urllib.request.urlopen(put, timeout=5).read()
    except (OSError, ValueError) as exc:
        return False, str(exc)[:160]
    return True, "subtitles " + ("on" if cfg.get("SubtitleMode") == SUBS_ON else "off") + \
                 (", " + SUB_LANGS.get(cfg.get("SubtitleLanguagePreference", ""), "?")
                  if lang is not None else "")


def _fetch_ctl():
    ok, out = ssh(CTL_CMD, timeout=15)
    st = {"reachable": ok, "bt_powered": False, "devices": [], "subs": _subs_state()}
    if not ok:
        st["error"] = out
        return st
    adapter, known, flags, btbat, inputs, bats = {}, {}, {}, {}, [], {}
    cur = None
    for line in out.splitlines():
        k, _, v = line.partition("=")
        v = v.strip()
        if k == "adapter":
            key, _, val = v.partition("=")
            adapter[key] = val.strip()
        elif k == "dev":
            mac, _, name = v.partition(" ")
            if MAC_RE.match(mac.upper()):
                known[mac.upper()] = name.strip() or mac.upper()
        elif k == "flag":
            f, _, mac = v.partition(" ")
            flags.setdefault(mac.strip().upper(), set()).add(f)
        elif k == "btbat":
            mac, _, pct = v.partition(" ")
            if pct.strip().isdigit():
                btbat[mac.upper()] = int(pct)
        elif k == "input":
            # N: then U: per input device, in that order.
            if v.startswith("N: Name="):
                cur = {"name": v[8:].strip().strip('"'), "uniq": ""}
                inputs.append(cur)
            elif v.startswith("U: Uniq=") and cur is not None:
                cur["uniq"] = v[8:].strip().upper()
        elif k == "bat":
            parts = v.split()
            if len(parts) >= 2 and parts[1].isdigit():
                bats[parts[0].lower()] = (int(parts[1]), " ".join(parts[2:]).lower())
    st["bt_powered"] = adapter.get("Powered") == "yes"
    uniqs = {i["uniq"] for i in inputs if i["uniq"]}
    for mac, model in known.items():
        f = flags.get(mac, set())
        if "Paired" not in f:
            continue                       # found by a search, not ours: that's the scan list
        connected = "Connected" in f
        # The liveness test: an input node carrying THIS MAC. Only for a node
        # with no Uniq at all, fall back to the name (a DualSense registers the
        # pad and its motion sensors, so a prefix is enough).
        live = mac in uniqs or any(
            not i["uniq"] and (model.lower() in i["name"].lower()
                               or i["name"].lower().startswith(model.lower()[:14]))
            for i in inputs)
        live = live and connected
        battery, charging = btbat.get(mac), False
        for sup, (pct, status) in bats.items():
            if mac.lower() in sup:
                battery, charging = pct, status in ("charging", "full")
        custom = NAMES.get(mac, "")
        st["devices"].append({
            "mac": mac, "name": custom or model, "model": model, "custom": bool(custom),
            "kind": _kind(model), "trusted": "Trusted" in f, "connected": connected,
            "live": live,
            # The case the whole card exists to expose.
            "stale": connected and not live,
            "battery": battery if connected else None, "charging": charging,
        })
    st["devices"].sort(key=lambda d: (not d["live"], not d["connected"], d["name"].lower()))
    return st


def _last_meaningful(out):
    """bluetoothctl prefixes its output with D-Bus chatter (SupportedUUIDs and
    friends). Show the last line that actually says something."""
    for line in reversed((out or "").splitlines()):
        line = line.strip()
        if line and not line.startswith("SupportedUUIDs") and not line.startswith("["):
            return line[:160]
    return ""


def _known_macs(paired_only=False):
    """MACs the Pi itself reports — every known device, or only the paired
    ones. A dashboard-supplied MAC is checked against this before it is ever
    interpolated into a root shell command."""
    ok, out = ssh("bluetoothctl devices" + (" Paired" if paired_only else "") +
                  " 2>/dev/null | sed -n 's/^Device /dev=/p'", timeout=8)
    if not ok:
        return set()
    return {l.partition("=")[2].split()[0].upper()
            for l in out.splitlines() if l.startswith("dev=") and l.partition("=")[2].strip()}


def _display(mac):
    """What to call a device in the activity log: our name, else BlueZ's."""
    if NAMES.get(mac):
        return NAMES[mac]
    for d in (HUB.state.get("ctl") or {}).get("devices", []):
        if d["mac"] == mac:
            return d["name"]
    for d in (HUB.state.get("scan") or {}).get("found", []):
        if d["mac"] == mac:
            return d["name"]
    return mac


def _ctl_guard(mac, paired_only=True):
    """Validate a dashboard-supplied MAC: shape, then the Pi's own list."""
    mac = (mac or "").upper()
    if not MAC_RE.match(mac):
        return mac, (400, {"ok": False, "error": "bad MAC"})
    if mac not in _known_macs(paired_only):
        return mac, (404, {"ok": False, "error": "not a known device" if paired_only
                                  else "not found — search again"})
    return mac, None


def _with_ctl_busy(mac, what, fn):
    """Run fn() with `mac` marked busy (`what`: pairing, connecting…) on every
    open dashboard; one operation per device at a time."""
    if not HUB.set_ctlbusy(mac, what):
        return 409, {"ok": False, "error": _display(mac) + " is busy"}
    try:
        return fn()
    finally:
        HUB.set_ctlbusy(mac, None)
        HUB.wake.set()


def ctl_connect(mac, disconnect=False):
    mac, bad = _ctl_guard(mac)
    if bad:
        return bad
    verb = "disconnect" if disconnect else "connect"

    def go():
        ok, out = ssh("bluetoothctl " + verb + " " + mac + " 2>&1 | tail -4", timeout=25)
        if not ok:
            return 502, {"ok": False, "error": (out or "ssh failed")[:200]}
        # bluetoothctl's exit status is NOT usable here, for two reasons: it is
        # piped through tail (so the pipeline reports tail's status, always 0),
        # and in non-interactive mode it exits 0 even when the attempt plainly
        # failed. Taking it at face value reports a successful connect for a pad
        # that is switched off -- exactly the false "it's working" this whole
        # card exists to stop. The output text is the only honest signal.
        low = (out or "").lower()
        if "successful" in low:
            return 200, {"ok": True, "message": _display(mac) + " " + verb + "ed"}
        if "failed" in low or "not available" in low:
            # status 0x04 / br-connection-create-sock is what a powered-off or
            # out-of-range pad looks like; say that rather than echoing D-Bus.
            friendly = ("it's off or out of range — switch it on (PS button) and try again"
                        if ("0x04" in low or "create-sock" in low or "page timeout" in low
                            or "page-timeout" in low or "host is down" in low)
                        else _last_meaningful(out))
            return 502, {"ok": False, "error": _display(mac) + ": " + friendly}
        return 200, {"ok": True, "message": _last_meaningful(out) or (_display(mac) + " " + verb + "ed")}

    return _with_ctl_busy(mac, verb + "ing", go)


def ctl_trust(mac, on=True):
    """Auto-connect. BlueZ only lets a device connect BY ITSELF (switch the pad
    on, it reconnects) when it is Trusted — there is no agent on the Pi to
    authorise it otherwise."""
    mac, bad = _ctl_guard(mac)
    if bad:
        return bad

    def go():
        ok, out = ssh("bluetoothctl " + ("trust " if on else "untrust ") + mac + " 2>&1 | tail -2", timeout=12)
        if ok and "succeeded" in (out or "").lower():
            return 200, {"ok": True, "message": _display(mac) + (
                ": auto-connect on — it connects when switched on" if on else ": auto-connect off")}
        return 502, {"ok": False, "error": _last_meaningful(out) or "no answer"}

    return _with_ctl_busy(mac, "saving", go)


def ctl_forget(mac):
    """Remove the pairing. Our name for it is kept, so re-pairing the same pad
    (the -5 recovery) gets its name back."""
    mac, bad = _ctl_guard(mac)
    if bad:
        return bad

    def go():
        name = _display(mac)
        ok, out = ssh("bluetoothctl remove " + mac + " 2>&1 | tail -2", timeout=15)
        if ok and "removed" in (out or "").lower():
            return 200, {"ok": True, "message": name + " forgotten — pair it again to use it"}
        return 502, {"ok": False, "error": _last_meaningful(out) or "no answer"}

    return _with_ctl_busy(mac, "forgetting", go)


def ctl_pair(mac):
    """Pair, trust (auto-connect) and connect a device a search found. Pairing
    stops the search first: BlueZ pairs badly while it is still discovering.
    No agent is needed — a gamepad pairs "just works" (no PIN), which is what
    BlueZ does by itself when there is none."""
    mac, bad = _ctl_guard(mac, paired_only=False)
    if bad:
        return bad

    def go():
        name = _display(mac)
        stop_scan(quiet=True)
        ok, out = ssh(
            "bluetoothctl pairable on >/dev/null 2>&1; "
            "bluetoothctl --timeout 30 pair " + mac + " 2>&1 | tail -6; "
            "bluetoothctl trust " + mac + " >/dev/null 2>&1; "
            "sleep 2; "
            "bluetoothctl info " + mac + " 2>/dev/null | grep -E 'Paired:|Connected:'; "
            "bluetoothctl pairable off >/dev/null 2>&1",
            timeout=55)
        low = (out or "").lower()
        if ok and "paired: yes" in low:
            with SCAN_LOCK:
                SCAN["found"] = [d for d in SCAN["found"] if d["mac"] != mac]
            _publish_scan()
            return 200, {"ok": True, "mac": mac, "message": name + " paired" + (
                " and connected" if "connected: yes" in low else " — switch it on to connect")}
        why = _last_meaningful(out.replace("Paired: no", "").replace("Connected: no", "")) if out else ""
        if "authenticationfailed" in low.replace(" ", "") or "authentication" in low:
            why = "it stopped pairing — hold the buttons again until the light flashes, then Pair"
        elif "not available" in low or "does not exist" in low:
            why = "it's gone from range — search again"
        return 502, {"ok": False, "error": name + ": " + (why or "pairing failed")}

    return _with_ctl_busy(mac, "pairing", go)


def ctl_rename(mac, name):
    """Our name for a paired device; empty puts its own name back. Stored on
    Asgard (NAMES_FILE); nothing is sent to the Pi."""
    mac = (mac or "").upper()
    if not MAC_RE.match(mac):
        return 400, {"ok": False, "error": "bad MAC"}
    paired = {d["mac"] for d in (HUB.state.get("ctl") or {}).get("devices", [])}
    if mac not in paired:
        return 404, {"ok": False, "error": "not a paired device"}
    name = clean_name(name)
    with _names_lock:
        old = NAMES.get(mac, "")
        if name:
            NAMES[mac] = name
        else:
            NAMES.pop(mac, None)
        try:
            _save_names()
        except OSError as exc:
            return 500, {"ok": False, "error": "could not save: " + str(exc)[:80]}
    # Show it now, on every dashboard, without waiting for the next poll.
    ctl = HUB.state.get("ctl")
    if ctl:
        devs = []
        for d in ctl.get("devices", []):
            d = dict(d)
            if d["mac"] == mac:
                d["name"], d["custom"] = (name or d["model"]), bool(name)
            devs.append(d)
        HUB.publish("ctl", dict(ctl, devices=devs))
    model = next((d["model"] for d in (ctl or {}).get("devices", []) if d["mac"] == mac), mac)
    return 200, {"ok": True, "message": (old or model) + (" is now " + name if name else " shows its own name again")}


# ── Searching: a background discovery window, pushed live ────────────────────
SCAN_LOCK = threading.Lock()
SCAN = {"proc": None, "active": False, "started": 0, "ends": 0, "ended": 0,
        "found": [], "unnamed": 0}


def _scan_state():
    with SCAN_LOCK:
        if not SCAN["active"] and not SCAN["found"] and not SCAN["ended"]:
            return {"active": False, "found": [], "unnamed": 0}
        if not SCAN["active"] and time.time() - SCAN["ended"] > CTL_SCAN_KEEP_S:
            SCAN["found"], SCAN["unnamed"], SCAN["ended"] = [], 0, 0
            return {"active": False, "found": [], "unnamed": 0}
        return {"active": SCAN["active"], "ends": SCAN["ends"], "ended": SCAN["ended"],
                "found": list(SCAN["found"]), "unnamed": SCAN["unnamed"]}


def _publish_scan():
    HUB.publish("scan", _scan_state())


def _fetch_scan():
    """One look at what the running search has found."""
    ok, out = ssh(SCAN_CMD, timeout=20)
    if not ok:
        return
    found, info = {}, {}
    for line in out.splitlines():
        k, _, v = line.partition("=")
        if k == "found":
            mac, _, name = v.strip().partition(" ")
            if MAC_RE.match(mac.upper()):
                found[mac.upper()] = name.strip()
        elif k == "fi":
            mac, _, rest = v.strip().partition(" ")
            key, _, val = rest.partition(" ")
            info.setdefault(mac.upper(), {})[key] = val.strip()
    named, unnamed = [], 0
    for mac, name in found.items():
        if not name or _UNNAMED.match(name):
            unnamed += 1
            continue
        i = info.get(mac, {})
        named.append({"mac": mac, "name": name, "kind": _kind(name, i.get("icon")),
                      "rssi": _rssi(i.get("rssi"))})
    # Controllers first, then the strongest signal: the pad in your hand.
    named.sort(key=lambda d: (d["kind"] != "gamepad",
                              -(d["rssi"] if d["rssi"] is not None else -999), d["name"].lower()))
    with SCAN_LOCK:
        SCAN["found"], SCAN["unnamed"] = named[:CTL_SCAN_MAX], unnamed


def start_scan():
    global _inflight
    with SCAN_LOCK:
        if SCAN["active"]:
            return 200, {"ok": True, "message": "already searching"}
        # `power on` first: searching is the moment someone clearly wants
        # Bluetooth on. The ssh channel lives as long as the search, on the
        # shared master; _inflight counts it so _drop_master() never cuts it.
        cmd = ("bluetoothctl power on >/dev/null 2>&1; "
               "bluetoothctl --timeout " + str(CTL_SCAN_S) + " scan on >/dev/null 2>&1")
        try:
            proc = subprocess.Popen(SSH_BASE + [cmd], stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
        except OSError as exc:
            return 502, {"ok": False, "error": str(exc)[:120]}
        now = time.time()
        SCAN.update(proc=proc, active=True, started=now, ends=now + CTL_SCAN_S, ended=0,
                    found=[], unnamed=0)
    with _inflight_lock:
        _inflight += 1
    threading.Thread(target=_scan_wait, args=(proc,), daemon=True).start()
    _publish_scan()
    HUB.wake.set()
    return 200, {"ok": True, "message": "searching for %ds" % CTL_SCAN_S}


def _scan_wait(proc):
    global _inflight
    try:
        proc.wait(timeout=CTL_SCAN_S + 20)
    except subprocess.TimeoutExpired:
        proc.kill()
    finally:
        with _inflight_lock:
            _inflight -= 1
    _fetch_scan()
    with SCAN_LOCK:
        if SCAN["proc"] is proc:
            SCAN.update(proc=None, active=False, ended=time.time())
    _publish_scan()
    HUB.wake.set()


def stop_scan(quiet=False):
    """End the search now. Discovery belongs to the bluetoothctl that started
    it (BlueZ tracks it per D-Bus client), so a second `scan off` would not
    stop it: closing that process's ssh channel does — sshd hangs it up, and
    BlueZ ends a departed client's discovery."""
    with SCAN_LOCK:
        proc = SCAN["proc"]
    if proc is None:
        return 200, {"ok": True, "message": "not searching"}
    proc.terminate()
    return 200, {"ok": True, "message": "search stopped"}


# ── Network: what Eclipse is on, Wi-Fi in range, switching ───────────────────
# One look at everything the Network card shows:
#   tech=     connman technologies and whether each radio is powered
#   svc=      `connmanctl services`: every network in range plus the saved
#             ones, flags first (* saved, A auto-connect, O online / R ready)
#   str=      signal strength for the Wi-Fi ones (0-100, connman's scale)
#   saved=    every saved Wi-Fi ON DISK, in range or not, with its AutoConnect —
#             the wired-only rule is "all of these false", and a network out of
#             range is invisible to connmanctl
#   prov=     the provisioning files a join from here leaves behind
#   sct=      the one-link override (SingleConnectedTechnology) — a re-flash loses it
#   carrier=  is a cable plugged in
#   unit=     is a switch (eclipse-net.sh) running right now
#   result=   how the last switch ended
#   home=     can it reach Asgard on the house LAN — away from home, the LAN
#             Jellyfin path can't work
NET_CMD = (
    "connmanctl technologies 2>/dev/null | awk '/^\\/net\\/connman\\/technology\\// "
    "{ t = $1; sub(/.*\\//, \"\", t) } /^ *Powered = / { print \"tech=\" t \" \" $3 }'; "
    "connmanctl services 2>/dev/null | sed 's/^/svc=/'; "
    "n=0; for id in $(connmanctl services 2>/dev/null | awk '$NF ~ /^wifi_/ { print $NF }'); do"
    " n=$((n + 1)); [ $n -gt " + str(NET_LIST_MAX) + " ] && break;"
    " connmanctl services \"$id\" 2>/dev/null | sed -n \"s/^ *Strength = /str=$id /p\"; done; "
    "for d in /storage/.cache/connman/wifi_*/; do [ -f \"$d/settings\" ] || continue; s=${d%/};"
    " echo \"saved=${s##*/} $(sed -n 's/^AutoConnect=//p' \"$d/settings\" | head -1)"
    " $(sed -n 's/^Name=//p' \"$d/settings\" | head -1)\"; done; "
    "for f in /storage/.cache/connman/eclipse-*.config; do [ -f \"$f\" ] && echo \"prov=${f##*/}\"; done; "
    "echo \"sct=$(sed -n 's/^SingleConnectedTechnology *= *//p' /storage/.config/connman_main.conf 2>/dev/null)\"; "
    "echo \"carrier=$(cat /sys/class/net/eth0/carrier 2>/dev/null)\"; "
    "echo \"unit=$(systemctl is-active eclipse-net 2>/dev/null)\"; "
    "echo \"result=$(cat " + NET_DIR + "/result 2>/dev/null)\"; "
    "case \"$(ip route get " + ASGARD_LAN_IP + " 2>/dev/null)\" in *tailscale*|'') echo home=0;;"
    " *) ping -c 1 -W 1 " + ASGARD_LAN_IP + " >/dev/null 2>&1 && echo home=1 || echo home=0;; esac"
)


def _ssid(hexpart):
    try:
        return bytes.fromhex(hexpart).decode("utf-8", "replace")
    except ValueError:
        return ""


def _net_row(sid, name="", flags="", strength=None):
    m = WIFI_RE.match(sid)
    sec = m.group(2) if m else ""
    return {"id": sid, "name": name or (_ssid(m.group(1)) if m else sid),
            "security": sec, "secure": sec not in ("none", ""),
            "joinable": sec in JOINABLE, "strength": strength,
            "saved": "*" in flags, "auto": "A" in flags,
            "online": "O" in flags, "ready": "R" in flags, "in_range": bool(flags) or strength is not None}


def _fetch_net():
    ok, out = ssh(NET_CMD, timeout=20)
    if not ok:
        return {"reachable": False, "error": out[:200]}
    techs, strength, saved, prov, misc, rows, wired = {}, {}, {}, set(), {}, {}, None
    for line in out.splitlines():
        k, _, v = line.partition("=")
        if k == "tech":
            t, _, p = v.partition(" ")
            techs[t] = p.strip() == "True"
        elif k == "svc":
            flags, rest = v[:3], v[3:].strip()
            if not rest:
                continue
            sid = rest.split()[-1]
            name = rest[:-len(sid)].strip()
            if WIRED_RE.match(sid):
                wired = {"id": sid, "online": "O" in flags, "ready": "R" in flags, "auto": "A" in flags}
            elif WIFI_RE.match(sid):
                rows[sid] = (flags, name)
        elif k == "str":
            sid, _, s = v.partition(" ")
            strength[sid] = int(s) if s.strip().isdigit() else None
        elif k == "saved":
            sid, _, rest = v.partition(" ")
            auto, _, name = rest.partition(" ")
            if WIFI_RE.match(sid):
                saved[sid] = (auto.strip() == "true", name.strip())
        elif k == "prov":
            prov.add(v.strip())
        elif k in ("sct", "carrier", "unit", "result", "home"):
            misc[k] = v.strip()
    nets = {}
    for sid, (flags, name) in rows.items():
        nets[sid] = _net_row(sid, name, flags if flags.strip() else " ", strength.get(sid))
        nets[sid]["in_range"] = True
    for sid, (auto, name) in saved.items():
        n = nets.setdefault(sid, _net_row(sid, name))
        n["saved"], n["auto"] = True, auto
        if not n["name"] or n["name"] == sid:
            n["name"] = name or n["name"]
    for n in nets.values():
        n["ours"] = ("eclipse-" + WIFI_RE.match(n["id"]).group(1) + ".config") in prov
    using = None
    if wired and (wired["online"] or wired["ready"]):
        using = {"kind": "wired", "id": wired["id"], "name": "Cable", "online": wired["online"]}
    for n in nets.values():
        if (n["online"] or n["ready"]) and (using is None or (n["online"] and not using["online"])):
            using = {"kind": "wifi", "id": n["id"], "name": n["name"], "online": n["online"],
                     "strength": n["strength"]}
    saved_list = sorted((n for n in nets.values() if n["saved"]),
                        key=lambda n: (not (n["online"] or n["ready"]), not n["in_range"],
                                       -(n["strength"] or 0), n["name"].lower()))
    found = sorted((n for n in nets.values() if not n["saved"] and n["name"]),
                   key=lambda n: (-(n["strength"] or 0), n["name"].lower()))[:NET_LIST_MAX]
    result = None
    parts = misc.get("result", "").split(" ", 3)
    if len(parts) == 4 and parts[0].isdigit():
        result = {"t": int(parts[0]), "token": parts[1], "outcome": parts[2], "message": parts[3]}
    sct = misc.get("sct", "").lower() == "true"
    wifi_auto = any(n["auto"] for n in saved_list)
    return {
        "reachable": True,
        "using": using,
        "cable": misc.get("carrier") == "1",
        "wired": wired,
        "wifi_on": techs.get("wifi", False),
        "sct": sct,
        # The 2026-10-09 rule, as the Pi has it right now.
        "wired_only": sct and not wifi_auto,
        "wifi_auto": wifi_auto,
        "home": misc.get("home") == "1",
        "saved": saved_list,
        "found": found,
        "switch_running": misc.get("unit") in ("active", "activating"),
        "result": result,
    }


# A switch in flight. The Pi can't report while its link is changing, so this
# side remembers what was asked and when, and keeps the card saying "Switching…"
# until the Pi's result file carries this switch's token (or it times out).
NETSW_LOCK = threading.Lock()
NETSW = {"active": False}


def _netsw_state():
    with NETSW_LOCK:
        return dict(NETSW)


def _net_switch_check(st):
    """Called with each fresh network state while a switch runs."""
    with NETSW_LOCK:
        sw = dict(NETSW)
    if not sw.get("active"):
        return
    res = (st or {}).get("result") or {}
    done = res.get("token") == sw["token"] and not st.get("switch_running")
    late = time.time() > sw["until"]
    if not (done or late):
        return
    if done:
        ok, msg = res["outcome"] == "ok", res["message"][:160]
    else:
        ok, msg = False, ("no word from Eclipse since switching to " + sw["label"] +
                          " — it should have gone back by itself; if it's still missing, plug in a "
                          "cable or use LibreELEC → Connections on the TV")
    with NETSW_LOCK:
        if NETSW.get("token") != sw["token"]:
            return
        # `last` lets every open card say how it ended, not just the log.
        NETSW.clear()
        NETSW.update(active=False, last={"ok": ok, "message": msg, "token": sw["token"]})
    HUB.log("Network", ok, msg)
    HUB.publish("netsw", _netsw_state())


def net_refresh():
    st = _fetch_net()
    HUB.publish("net", st)
    if st.get("reachable"):
        _net_switch_check(st)
    elif _netsw_state().get("active"):
        _net_switch_check({})                 # only the timeout can end it now
    return st


# Searching: connman scans in the background anyway (BackgroundScanning), so a
# search only asks for a fresh one now and holds the results list open.
NETSCAN = {"active": False, "ended": 0}
NETSCAN_LOCK = threading.Lock()


def _netscan_state():
    with NETSCAN_LOCK:
        if NETSCAN["ended"] and time.time() - NETSCAN["ended"] > NET_SCAN_KEEP_S:
            NETSCAN["ended"] = 0
        return dict(NETSCAN)


def net_scan():
    with NETSCAN_LOCK:
        if NETSCAN["active"]:
            return 200, {"ok": True, "message": "already searching"}
        NETSCAN.update(active=True, ended=0)
    HUB.publish("netscan", _netscan_state())

    def go():
        try:
            # `enable wifi`: searching is the moment someone clearly wants the
            # radio on (it was once found off, persisted — Claude/eclipse.md). It
            # does not JOIN anything: wired-only keeps every saved network's
            # AutoConnect off.
            ssh("connmanctl enable wifi >/dev/null 2>&1; connmanctl scan wifi 2>&1 | tail -1", timeout=30)
            net_refresh()
        finally:
            with NETSCAN_LOCK:
                NETSCAN.update(active=False, ended=time.time())
            HUB.publish("netscan", _netscan_state())

    threading.Thread(target=go, daemon=True).start()
    return 200, {"ok": True, "message": "searching for Wi-Fi"}


def _keyfile_value(s):
    """A value for connman's GKeyFile provisioning file: backslash and spaces
    escaped (\\\\, \\s) so leading/trailing spaces survive and nothing can break
    out of the line. Newlines are refused before this is ever called."""
    return s.replace("\\", "\\\\").replace(" ", "\\s")


def _check_pass(sec, pw):
    if sec == "none":
        return None
    if any(ord(c) < 0x20 or ord(c) > 0x7e for c in pw):
        return "the password can only use plain keyboard characters"
    if sec in ("psk", "sae"):
        if len(pw) == 64 and all(c in "0123456789abcdefABCDEF" for c in pw):
            return None
        if not 8 <= len(pw) <= 63:
            return "a Wi-Fi password is 8 to 63 characters"
    elif sec == "wep":
        if len(pw) not in (5, 13) and not (len(pw) in (10, 26) and
                                           all(c in "0123456789abcdefABCDEF" for c in pw)):
            return "a WEP key is 5 or 13 characters (10 or 26 hex)"
    return None


def _net_start(mode, sid, label, config=None):
    """Hand eclipse-net.sh to the Pi and start it detached. `config`, when
    joining a new network, is the provisioning file — sent through stdin."""
    try:
        with open(NET_SCRIPT) as f:
            script = f.read()
    except OSError as exc:
        return 500, {"ok": False, "error": "eclipse-net.sh missing on Asgard: " + str(exc)[:80]}
    token = os.urandom(6).hex()
    with NETSW_LOCK:
        if NETSW.get("active"):
            return 409, {"ok": False, "error": "already switching to " + NETSW["label"]}
        now = time.time()
        NETSW.clear()
        NETSW.update(active=True, mode=mode, id=sid or "", label=label, token=token,
                     since=now, until=now + NET_SWITCH_MAX_S)
    ok, out = ssh("umask 077; mkdir -p " + NET_DIR + " && cat > " + NET_DIR + "/eclipse-net.sh", stdin=script)
    if ok:
        ok, out = (ssh("umask 077; cat > " + NET_DIR + "/pending.config", stdin=config) if config
                   else ssh("rm -f " + NET_DIR + "/pending.config"))
    if ok:
        # --collect: a failed run doesn't linger and block the next one.
        ok, out = ssh("systemctl reset-failed eclipse-net >/dev/null 2>&1; "
                      "systemd-run --quiet --collect --unit=eclipse-net /bin/sh " + NET_DIR + "/eclipse-net.sh " +
                      mode + " " + (sid or "-") + " " + ("new" if config else "old") + " " + token + " 2>&1",
                      timeout=20)
    if not ok:
        with NETSW_LOCK:
            NETSW.clear()
            NETSW["active"] = False
        HUB.publish("netsw", _netsw_state())
        if config:
            ssh("rm -f " + NET_DIR + "/pending.config", timeout=10)
        return 502, {"ok": False, "error": "couldn't start the switch: " + (out or "no answer")[:160]}
    HUB.publish("netsw", _netsw_state())
    HUB.wake.set()
    return 200, {"ok": True, "message": "switching to " + label + " — Eclipse may drop off for up to a minute"}


def net_wired():
    st = net_refresh()
    if not st.get("reachable"):
        return 502, {"ok": False, "error": "Eclipse isn't answering"}
    if not st.get("cable"):
        return 409, {"ok": False, "error": "there's no cable in Eclipse — plug one in first"}
    u = st.get("using") or {}
    if u.get("kind") == "wired" and st.get("wired_only"):
        return 200, {"ok": True, "message": "already on the cable, wired only"}
    return _net_start("wired", "", "the cable")


def net_wifi(sid="", body=None):
    """Wi-Fi mode on network `sid` (a saved one, or a new one with a password
    in the body), or with no sid the strongest saved network in range."""
    st = net_refresh()
    if not st.get("reachable"):
        return 502, {"ok": False, "error": "Eclipse isn't answering"}
    nets = {n["id"]: n for n in st.get("saved", []) + st.get("found", [])}
    if not sid:
        best = [n for n in st.get("saved", []) if n["in_range"] and n["joinable"]]
        if not best:
            return 404, {"ok": False, "error": "no saved Wi-Fi in range — search and pick one"}
        sid = best[0]["id"]
    m = WIFI_RE.match(sid or "")
    if not m:
        return 400, {"ok": False, "error": "bad network id"}
    n = nets.get(sid)
    if not n:
        return 404, {"ok": False, "error": "that network isn't in range any more — search again"}
    if not n["joinable"]:
        return 400, {"ok": False, "error": n["name"] + " needs a username (work/uni Wi-Fi) — use LibreELEC → Connections on the TV"}
    pw = (body or {}).get("pass")
    config = None
    if n["saved"]:
        # A saved network joins with what the Pi already has. A new password is
        # NOT taken here: a join that fails throws its provisioning file away,
        # and connman would take the saved network down with it — a typo would
        # forget the house Wi-Fi. Forget it, then join it fresh.
        if pw is not None:
            return 409, {"ok": False, "error": n["name"] + " is already saved — Forget it first to enter a new password"}
        if (st.get("using") or {}).get("id") == sid:
            return 200, {"ok": True, "message": "already on " + n["name"]}
    else:
        pw = pw if isinstance(pw, str) else ""
        if n["security"] != "none":
            bad = _check_pass(n["security"], pw)
            if bad:
                return 400, {"ok": False, "error": bad}
        config = ("[service_eclipse]\nType = wifi\nSSID = " + m.group(1) + "\n" +
                  ("Passphrase = " + _keyfile_value(pw) + "\n" if n["security"] != "none" else ""))
    return _net_start("wifi", sid, n["name"], config)


def net_forget(sid):
    st = net_refresh()
    if not st.get("reachable"):
        return 502, {"ok": False, "error": "Eclipse isn't answering"}
    m = WIFI_RE.match(sid or "")
    n = next((x for x in st.get("saved", []) if x["id"] == sid), None)
    if not m or not n:
        return 404, {"ok": False, "error": "not a saved network"}
    if (st.get("using") or {}).get("id") == sid:
        return 409, {"ok": False, "error": "Eclipse is on " + n["name"] + " right now — switch to the cable or another network first"}
    if _netsw_state().get("active"):
        return 409, {"ok": False, "error": "a switch is running — try again in a minute"}
    # Our provisioning file first: removing it is what makes connman drop a
    # network it provisioned (an immutable one refuses `config --remove`).
    ok, out = ssh("rm -f /storage/.cache/connman/eclipse-" + m.group(1) + ".config; "
                  "connmanctl config " + sid + " --remove >/dev/null 2>&1; "
                  "rm -rf /storage/.cache/connman/" + sid + "; echo forgotten", timeout=15)
    net_refresh()
    if ok and "forgotten" in out:
        return 200, {"ok": True, "message": n["name"] + " forgotten"}
    return 502, {"ok": False, "error": (out or "no answer")[:160]}


def _route_sublang(code):
    """POST /ctl/sublang/<iso639-2>. Whitelisted, so no caller string reaches
    Jellyfin's config untouched."""
    if code not in SUB_LANGS:
        return 400, {"ok": False, "error": "unknown language"}
    ok, msg = _set_subs(lang=code)
    return (200 if ok else 502), {"ok": ok, "message": msg} if ok else {"ok": False, "error": msg}


def act_subs_on():
    return _set_subs(mode=SUBS_ON)


def act_subs_off():
    return _set_subs(mode=SUBS_OFF)


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
    # `systemctl --no-block reboot` returns immediately and leaves the job with
    # systemd, so the box goes down after ssh has hung up.
    #
    # It used to be `(sleep 1; reboot) >/dev/null 2>&1 &` and THAT DID NOT WORK:
    # when the remote command finishes, sshd SIGHUPs the whole process group and
    # takes the backgrounded subshell with it before the sleep elapses. The
    # action still reported "reboot issued" because ssh exited 0, so the button
    # looked like it worked and the Pi simply never rebooted. Verified by hand
    # 2026-10-05 -- `uptime -s` was unchanged after a "successful" press.
    ssh("systemctl --no-block reboot", timeout=10)
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
    # Controllers + subtitles — both dashboards get all of these. Per-device
    # connect/disconnect/pair/forget/trust are NOT here: those take a MAC, and
    # every entry in this table is a zero-argument closure so that no
    # caller-supplied value can ever reach ssh()'s shell string. They go through
    # the /ctl/ routes instead, which validate against MAC_RE and the Pi's own
    # device list (_ctl_guard). Searching is /ctl/scan, in the background.
    "bt-on": ("Turn Bluetooth on", lambda: ssh("bluetoothctl power on 2>&1 | tail -1", timeout=12)),
    "subs-on": ("Subtitles on", act_subs_on),
    "subs-off": ("Subtitles off", act_subs_off),
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
#   ctl       paired Bluetooth devices, our names for them, subtitles
#   scan      a running (or just-finished) search: what it has found
#   ctlbusy   {MAC: "pairing" | "connecting" | …} — so a Pair tapped on one
#             dashboard shows "Pairing…" on that device on the other too
#   net       the cable, Wi-Fi in range and saved, wired-only or not (_fetch_net)
#   netscan   a Wi-Fi search running / just ended
#   netsw     a cable ⇄ Wi-Fi switch in flight, until the Pi reports back
# The poller sleeps while nobody is connected.

class Hub:
    def __init__(self):
        self.cond = threading.Condition()
        self.version = 0
        self.state = {"status": None, "tv": None, "wolf": None, "ctl": None,
                      "scan": {"active": False, "found": [], "unnamed": 0},
                      "net": None, "netscan": {"active": False, "ended": 0},
                      "netsw": {"active": False},
                      "activity": [], "busy": {}, "ctlbusy": {}}
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

    def set_ctlbusy(self, mac, what):
        """Mark one device busy (`what`) or free (None); False if it already is."""
        with self.cond:
            busy = dict(self.state["ctlbusy"])
            if what:
                if mac in busy:
                    return False
                busy[mac] = what
            else:
                busy.pop(mac, None)
            self.state["ctlbusy"] = busy
            self.version += 1
            self.cond.notify_all()
        return True

    def poller(self):
        status_at = wolf_at = tv_at = ctl_at = scan_at = net_at = 0.0
        while True:
            if self.watchers > 0:
                now = time.monotonic()
                if now - net_at >= (EVENTS_NETSW_S if NETSW.get("active") else EVENTS_NET_S):
                    net_at = now
                    net_refresh()
                    self.publish("netscan", _netscan_state())     # ages the last search out
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
                if now - ctl_at >= EVENTS_CTL_S:
                    ctl_at = now
                    self.publish("ctl", _fetch_ctl())
                if SCAN["active"] and now - scan_at >= EVENTS_SCAN_S:
                    scan_at = now
                    _fetch_scan()
                    _publish_scan()
                elif not SCAN["active"] and SCAN["ended"]:
                    _publish_scan()        # ages the last results out
            else:
                status_at = wolf_at = tv_at = ctl_at = net_at = 0.0
            if self.wake.wait(1.0):
                self.wake.clear()
                # An action finished or a client joined: look again NOW. ctl_at
                # must be reset alongside status_at or the card lags a Connect
                # tap by up to EVENTS_CTL_S even though the action has finished,
                # which reads as "the button did nothing".
                status_at = ctl_at = net_at = 0.0


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

    def _no_dash(self):
        if self.headers.get("X-Dash") == "1":
            return False
        self._send(403, json.dumps({"ok": False, "error": "missing X-Dash header"}), "application/json")
        return True

    def do_POST(self):
        path = self.path.split("?")[0].strip("/")
        # Always drain the body: this is a keep-alive HTTP/1.1 server, and an
        # unread body would be parsed as the next request on the connection.
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        raw = self.rfile.read(min(max(length, 0), 4096)) if length > 0 else b""
        # Network: the cable, Wi-Fi, joining and forgetting. Ids are validated
        # (WIFI_RE) and checked against the Pi's own list before any shell sees
        # them; a password arrives in the body (JSON) and goes to the Pi only
        # through ssh's stdin.
        if path == "net/scan" or path == "net/wired" or path == "net/wifi" or \
                path.startswith("net/wifi/") or path.startswith("net/forget/"):
            if self._no_dash():
                return
            body = None
            if raw:
                try:
                    body = json.loads(raw.decode("utf-8"))
                except (ValueError, UnicodeDecodeError):
                    self._send(400, json.dumps({"ok": False, "error": "bad request body"}), "application/json")
                    return
                if not isinstance(body, dict):
                    body = None
            if path == "net/scan":
                code, out = net_scan()
            elif path == "net/wired":
                code, out = net_wired()
            elif path.startswith("net/forget/"):
                code, out = net_forget(urllib.parse.unquote(path[len("net/forget/"):]))
                HUB.log("Forget network", code == 200, str(out.get("message") or out.get("error"))[:160])
            else:
                code, out = net_wifi(urllib.parse.unquote(path[len("net/wifi/"):]) if path != "net/wifi" else "", body)
            if code != 200 and path != "net/scan" and not path.startswith("net/forget/"):
                HUB.log("Network", False, str(out.get("error") or code)[:160])
            HUB.wake.set()
            self._send(code, json.dumps(out), "application/json")
            return
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
        # Bluetooth. Searching takes no argument; every other verb takes a
        # MAC (validated against MAC_RE and the Pi's own list before it goes
        # near a shell) — rename also a ?name=, which never leaves Asgard.
        if path in ("ctl/scan", "ctl/scan/stop"):
            if self.headers.get("X-Dash") != "1":
                self._send(403, json.dumps({"ok": False, "error": "missing X-Dash header"}),
                           "application/json")
                return
            code, body = start_scan() if path == "ctl/scan" else stop_scan()
            if path == "ctl/scan" and code == 200 and body.get("message", "").startswith("searching"):
                HUB.log("Search", True, "searching for Bluetooth devices")
            self._send(code, json.dumps(body), "application/json")
            return
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        # Per-device controller verbs and the subtitle language. Same shape as
        # wolf/stop/ above: a caller-supplied value, validated before use.
        for prefix, label, handler in (
            ("ctl/connect/", "Connect", lambda v: ctl_connect(v)),
            ("ctl/disconnect/", "Disconnect", lambda v: ctl_connect(v, disconnect=True)),
            ("ctl/pair/", "Pair", ctl_pair),
            ("ctl/forget/", "Forget", ctl_forget),
            ("ctl/trust/", "Auto-connect", lambda v: ctl_trust(v, True)),
            ("ctl/untrust/", "Auto-connect", lambda v: ctl_trust(v, False)),
            ("ctl/rename/", "Rename", lambda v: ctl_rename(v, (query.get("name") or [""])[0])),
            ("ctl/sublang/", "Subtitle language", _route_sublang),
        ):
            if not path.startswith(prefix):
                continue
            if self.headers.get("X-Dash") != "1":
                self._send(403, json.dumps({"ok": False, "error": "missing X-Dash header"}),
                           "application/json")
                return
            arg = urllib.parse.unquote(path[len(prefix):])
            code, body = handler(arg)
            HUB.log(label, code == 200,
                    str(body.get("message") or body.get("error") or code)[:160])
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
