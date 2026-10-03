#!/usr/bin/env python3
"""
Eclipse control endpoint for Glance.

Serves a touch-friendly button panel (embedded in Glance as an iframe widget) plus
a JSON status endpoint. Actions are executed on the Eclipse LibreELEC box over SSH.

SSH rather than Kodi's JSON-RPC on purpose: the headline action is "restart Kodi
when it has wedged", and a wedged Kodi cannot answer its own API. Kodi's HTTP
server is disabled on Eclipse anyway (services.webserver = false, JSON-RPC bound
to 127.0.0.1:9090).

Status is polled by both dashboards (the admin iframe every 10s, MarsBar every
15s, plus Glance's own server-side fetches), and every poll used to open a
brand-new SSH session — key exchange and all, ~0.7s each. Two things keep that
cheap now:

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
LAST_SPEEDTEST = {"mbps": None, "up_mbps": None, "when": 0.0}

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
    "echo \"mode=$(grep -oE 'Display [0-9]+x[0-9]+ @ [0-9.]+' "
    '/storage/.kodi/temp/kodi.log 2>/dev/null | tail -1)"; '
    'echo "jellyfin=$(grep -oE \'"address": *"[^"]+"\' '
    + JELLYFIN_ADDON_DIR + '/data.json 2>/dev/null | cut -d\'"\' -f4)"'
)


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
    return st


def _fetch_status():
    ok, out = ssh(STATUS_CMD, timeout=15)
    st = {"reachable": ok, "kodi": "?", "hdmi": "?", "edid": 0,
          "uptime": 0, "mode": "", "jellyfin": "", "error": ""}
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
    "sync-movies": ("Movies", lambda: _sync(MOVIES_ID, "Movies")),
    "sync-shows": ("TV Shows", lambda: _sync(SHOWS_ID, "TV Shows")),
    "jellyfin-toggle": ("Jellyfin server", act_jellyfin_toggle),
    "speedtest": ("Speed test", act_speedtest),
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
    --card:    hsla(160, 30%, 50%, .035);
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

  /* ── header ── */
  .head {
    display: flex; align-items: center; justify-content: space-between;
    padding: 2px 2px 16px;
  }
  .head-left { display: flex; align-items: center; gap: 13px; }
  .dot-lg {
    width: 12px; height: 12px; border-radius: 50%; flex: none;
    background: var(--dim); transition: background .2s, box-shadow .2s;
  }
  .dot-lg.ok  { background: var(--ok);  box-shadow: 0 0 13px hsla(142,62%,56%,.65); }
  .dot-lg.bad { background: var(--bad); box-shadow: 0 0 13px hsla(0,78%,66%,.65); }
  .head-title { font-size: 17px; font-weight: 700; letter-spacing: .01em; }
  .head-sub   { font-size: 11.5px; color: var(--dim); margin-top: 3px; }
  .head-right { font-size: 10.5px; color: var(--dim); text-align: right; white-space: nowrap; }

  /* ── alert ── */
  .alert {
    display: none; align-items: center; gap: 9px;
    padding: 9px 13px; margin-bottom: 14px; font-size: 12px;
    border: 1px solid hsla(38, 88%, 62%, .3); border-left-width: 3px;
    border-radius: 8px; background: hsla(38, 88%, 62%, .07); color: var(--warn);
  }
  .alert.show { display: flex; }

  /* ── stat cards ── */
  .stats {
    display: grid; gap: 10px; margin-bottom: 22px;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  }
  .stat {
    display: flex; flex-direction: column; gap: 7px;
    min-height: 88px; padding: 12px 14px;
    border: 1px solid var(--line); border-radius: 10px;
    background: var(--card);
  }
  .stat-k {
    display: flex; align-items: center; gap: 6px;
    color: var(--dim); font-size: 10px; font-weight: 500;
    letter-spacing: .09em; text-transform: uppercase;
  }
  .stat-k svg { width: 12px; height: 12px; stroke-width: 2; opacity: .8; }
  .stat-v { font-size: 19px; font-weight: 700; letter-spacing: .005em; }
  .stat-v.ok   { color: var(--ok); }
  .stat-v.bad  { color: var(--bad); }
  .stat-v.warn { color: var(--warn); }
  .stat-sub { font-size: 11px; color: var(--dim); margin-top: auto; }
  .gauge {
    height: 5px; border-radius: 3px; margin-top: 3px; position: relative;
    background: linear-gradient(90deg,
      var(--bad) 0%, var(--bad) 16.6%,
      var(--warn) 16.6%, var(--warn) 66.6%,
      var(--ok) 66.6%, var(--ok) 100%);
    opacity: .32;
  }
  .gauge i {
    position: absolute; top: -3px; width: 2px; height: 11px;
    background: var(--fg); border-radius: 1px; transform: translateX(-1px);
    box-shadow: 0 0 6px rgba(0,0,0,.5);
  }

  /* ── button sections ── */
  .section-label {
    font-size: 10px; font-weight: 600; letter-spacing: .12em;
    text-transform: uppercase; color: var(--dim); margin: 0 2px 8px;
  }
  .grid {
    display: grid; gap: 10px; margin-bottom: 20px;
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
    background: var(--card);
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

  /* ── wolf sessions ── */
  .wolf { display: grid; gap: 8px; margin-bottom: 20px; }
  .wolf-empty {
    display: flex; align-items: center; gap: 10px;
    color: var(--dim); font-size: 12px; padding: 13px 14px;
    border: 1px dashed var(--line); border-radius: 10px;
  }
  .wolf-empty i {
    width: 8px; height: 8px; border-radius: 50%; background: var(--dim); flex: none;
  }
  .wolf-empty.down i { background: var(--bad); }
  .wolf-row {
    display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 14px;
    padding: 11px 12px 11px 14px; border: 1px solid var(--line); border-radius: 10px;
    background: var(--card);
    transition: opacity .3s, transform .3s, border-color .2s;
  }
  .wolf-row.stale { border-color: hsla(38, 88%, 62%, .42); }
  .wolf-row.gone { opacity: 0; transform: translateX(14px); }
  .wolf-ico {
    position: relative; width: 36px; height: 36px; border-radius: 10px;
    display: grid; place-items: center;
    background: hsla(142, 62%, 56%, .1); color: var(--ok);
  }
  .wolf-ico svg { width: 18px; height: 18px; stroke-width: 1.7; }
  .wolf-ico::after {   /* live pulse */
    content: ""; position: absolute; inset: -1px; border-radius: 11px;
    border: 1px solid hsla(142, 62%, 56%, .55); animation: wolfpulse 2.4s ease-out infinite;
  }
  .wolf-row.stale .wolf-ico { background: hsla(38, 88%, 62%, .12); color: var(--warn); }
  .wolf-row.stale .wolf-ico::after { border-color: hsla(38, 88%, 62%, .55); }
  @keyframes wolfpulse { from { opacity: .9; transform: scale(1); } to { opacity: 0; transform: scale(1.35); } }
  .wolf-app { font-weight: 700; font-size: 13.5px; display: flex; align-items: center; flex-wrap: wrap; gap: 8px; }
  .wolf-badge {
    font-size: 9.5px; font-weight: 600; letter-spacing: .1em; text-transform: uppercase;
    color: var(--warn); border: 1px solid hsla(38, 88%, 62%, .4); border-radius: 999px; padding: 1px 7px;
  }
  .wolf-meta { color: var(--dim); font-size: 11.5px; margin-top: 3px; }
  .wolf-meta b { color: var(--fg); font-weight: 500; }
  button.wolf-kill {
    flex-direction: row; height: 36px; min-width: 96px; padding: 0 14px; gap: 7px;
    font-size: 11.5px;
  }
  button.wolf-kill svg { width: 15px; height: 15px; }
  button.wolf-kill:hover:not(:disabled) {
    border-color: hsla(0, 70%, 60%, .45); background: hsla(0, 70%, 55%, .09); color: var(--bad);
  }
  @media (prefers-reduced-motion: reduce) {
    .wolf-ico::after { animation: none; }
    .wolf-row { transition: none; }
  }

  /* ── activity log ── */
  .log-wrap {
    margin-top: 4px; border: 1px solid var(--line); border-radius: 10px;
    background: hsla(160, 30%, 50%, .02); overflow: hidden;
  }
  .log-head {
    padding: 8px 13px; font-size: 10px; font-weight: 500;
    letter-spacing: .09em; text-transform: uppercase; color: var(--dim);
    border-bottom: 1px solid var(--line);
  }
  .log-list { max-height: 148px; overflow-y: auto; }
  .log-item {
    display: flex; align-items: baseline; gap: 10px;
    padding: 7px 13px; font-size: 11.5px; color: var(--dim);
    border-bottom: 1px solid hsla(160, 30%, 50%, .06);
  }
  .log-item:last-child { border-bottom: none; }
  .log-item .t { flex: none; min-width: 58px; margin-right: 10px; opacity: .7; font-variant-numeric: tabular-nums; }
  .log-item .m { color: var(--fg); }
  .log-item.good .m { color: var(--ok); }
  .log-item.err  .m { color: var(--bad); }
  .log-empty { padding: 14px 13px; font-size: 11.5px; color: var(--dim); }

  @media (max-width: 560px) {
    button { height: 64px; gap: 7px; font-size: 11.5px; }
    .stat { min-height: 76px; padding: 10px 12px; }
    .stat-v { font-size: 17px; }
    .head-title { font-size: 15.5px; }
  }
</style></head><body>
<div class="wrap">
  <div class="head">
    <div class="head-left">
      <span class="dot-lg" id="head-dot"></span>
      <div>
        <div class="head-title" id="head-title">Connecting&hellip;</div>
        <div class="head-sub" id="head-sub">&nbsp;</div>
      </div>
    </div>
    <div class="head-right" id="head-time"></div>
  </div>

  <div class="alert" id="hint">
    <span>&#9888;</span><span>Link is up but Kodi is not driving it &mdash; restart Kodi</span>
  </div>

  <div class="stats" id="stats"></div>

  <div class="section-label">Streams &middot; Wolf on Sisyphus</div>
  <div class="wolf" id="wolf"><div class="wolf-empty"><i></i>checking&hellip;</div></div>

  <div class="section-label">Playback</div>
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
  </div>

  <div class="section-label">Network &amp; System</div>
  <div class="grid">
    <button data-act="jellyfin-toggle" id="jellyfin-btn">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><circle cx="12" cy="12" r="10"/>
        <line x1="2" y1="12" x2="22" y2="12"/>
        <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
      <span class="lbl" id="jellyfin-lbl">Jellyfin: &hellip;</span>
    </button>
    <button data-act="speedtest" id="speedtest-btn">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><path d="M12 20a8 8 0 1 0 0-16 8 8 0 0 0 0 16z"/>
        <path d="M12 12 16 8"/><path d="M12 2v2"/><path d="M12 20v2"/>
        <path d="M4.9 4.9l1.4 1.4"/><path d="M17.7 17.7l1.4 1.4"/></svg>
      <span class="lbl">Speed Test</span>
    </button>
    <button class="danger" data-act="reboot" data-confirm="1">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round"
           stroke-linejoin="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>
        <line x1="12" y1="2" x2="12" y2="12"/></svg>
      <span class="lbl">Reboot Pi</span>
    </button>
  </div>

  <div class="log-wrap">
    <div class="log-head">Activity</div>
    <div class="log-list" id="log"><div class="log-empty">ready</div></div>
  </div>
</div>
<script>
var buttons = Array.prototype.slice.call(document.querySelectorAll('button[data-act]'));
var logHistory = [];

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
function fmtClock(d) {
  var p = function (n) { return (n < 10 ? '0' : '') + n; };
  return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}
function fmtAgo(ts) {
  if (!ts) return '';
  var s = Math.max(0, Math.round(Date.now() / 1000 - ts));
  if (s < 90) return s + 's ago';
  var m = Math.round(s / 60);
  if (m < 90) return m + 'm ago';
  return Math.round(m / 60) + 'h ago';
}
function stat(k, v, sub, cls, extra) {
  return '<div class="stat"><span class="stat-k">' + k + '</span>' +
         '<span class="stat-v ' + (cls || '') + '">' + v + '</span>' +
         (extra || '') +
         '<span class="stat-sub">' + (sub || '&nbsp;') + '</span></div>';
}
function gauge(mbps) {
  var max = 30, pct = Math.max(0, Math.min(100, (mbps || 0) / max * 100));
  return '<div class="gauge"><i style="left:' + pct + '%"></i></div>';
}
var JELLYFIN_NAMES = { lan: 'LAN', remote: 'Tailscale', unknown: '?' };
function refresh() {
  fetch('status').then(function (r) { return r.json(); }).then(function (s) {
    var dot = document.getElementById('head-dot');
    var title = document.getElementById('head-title');
    var sub = document.getElementById('head-sub');
    var stats = document.getElementById('stats');
    if (!s.reachable) {
      dot.className = 'dot-lg bad';
      title.textContent = 'Eclipse unreachable';
      sub.textContent = s.error || 'no response over SSH';
      stats.innerHTML = '';
    } else {
      dot.className = 'dot-lg ok';
      title.textContent = 'Eclipse online';
      sub.textContent = 'up ' + fmtUptime(s.uptime);

      var mode = fmtMode(s.mode);
      var jf = s.jellyfin_mode || 'unknown';
      var jfQuality = jf === 'remote' ? 'capped ~8 Mbps' : (jf === 'lan' ? 'uncapped direct play' : 'address unrecognised');
      var speedCls = '', speedTxt = 'never tested', speedSub = 'tap Speed Test to measure', gaugeHtml = '';
      if (s.speed_mbps != null) {
        speedCls = s.speed_mbps >= 20 ? 'ok' : (s.speed_mbps >= 5 ? 'warn' : 'bad');
        speedTxt = s.speed_mbps.toFixed(1) + ' Mbps';
        speedSub = 'tested ' + fmtAgo(s.speed_when);
        gaugeHtml = gauge(s.speed_mbps);
      }

      stats.innerHTML =
        stat('Kodi', s.kodi, 'process state', s.kodi === 'active' ? 'ok' : 'bad') +
        stat('Display', mode || 'not driving', s.hdmi === 'connected' ? 'HDMI connected' : 'HDMI disconnected', mode ? 'ok' : 'warn') +
        stat('Jellyfin', JELLYFIN_NAMES[jf], jfQuality, jf === 'unknown' ? 'warn' : 'ok') +
        stat('Speed', speedTxt, speedSub, speedCls, gaugeHtml) +
        stat('Uptime', fmtUptime(s.uptime), 'since last restart', '');

      var lbl = document.getElementById('jellyfin-lbl');
      if (lbl && !lbl.closest('button').classList.contains('busy')) {
        var next = jf === 'remote' ? 'lan' : 'remote';
        lbl.textContent = 'Jellyfin: switch to ' + JELLYFIN_NAMES[next];
      }
    }
    document.getElementById('hint').className = s.needs_kodi_restart ? 'alert show' : 'alert';
    document.getElementById('head-time').textContent = 'updated ' + fmtClock(new Date());
  }).catch(function () {
    document.getElementById('head-dot').className = 'dot-lg bad';
    document.getElementById('head-title').textContent = 'Panel offline';
    document.getElementById('head-sub').textContent = 'cannot reach eclipse-control';
    document.getElementById('stats').innerHTML = '';
  });
}
function logAdd(text, cls) {
  logHistory.unshift({ t: fmtClock(new Date()), text: text, cls: cls || '' });
  logHistory = logHistory.slice(0, 6);
  document.getElementById('log').innerHTML = logHistory.map(function (e) {
    return '<div class="log-item ' + e.cls + '"><span class="t">' + e.t + '</span>' +
           '<span class="m">' + e.text + '</span></div>';
  }).join('');
}
function run(btn) {
  var name = btn.dataset.act;
  buttons.forEach(function (b) { if (b !== btn) b.disabled = true; });
  btn.classList.add('busy');
  logAdd('running ' + name + '…', '');
  // X-Dash is required by do_POST (see there); same-origin, so no preflight.
  fetch('act/' + name, { method: 'POST', headers: { 'X-Dash': '1' } })
    .then(function (r) { return r.json(); })
    .then(function (j) { logAdd(j.message, j.ok ? 'good' : 'err'); })
    .catch(function (e) { logAdd(String(e), 'err'); })
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
// ── Wolf sessions ─────────────────────────────────────────────────────────────
// A Moonlight stream that outlives its client keeps Wolf's virtual pads alive
// (Claude/wolf.md). This lists what Wolf is serving and stops one on a double
// tap. Rows are keyed by session id so a refresh never resets an armed button.
var STALE_SECS = 3 * 3600;
var wolfState = { armed: null, killing: {} };
var ICON_STREAM = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/><path d="m10 8.5 4 2-4 2z"/></svg>';
var ICON_STOP = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>';
function fmtFor(secs) {
  var h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60);
  return h ? h + 'h ' + m + 'm' : (m ? m + 'm' : '<1m');
}
function esc(t) { var d = document.createElement('div'); d.textContent = t == null ? '' : String(t); return d.innerHTML; }
function wolfRender(data) {
  var box = document.getElementById('wolf');
  if (data.wolf !== 'up') {
    box.innerHTML = '<div class="wolf-empty down"><i></i>' +
      (data.wolf === 'down' ? 'Wolf isn\'t running on Sisyphus' : 'Sisyphus unreachable') + '</div>';
    return;
  }
  var list = (data.sessions || []).filter(function (x) { return !wolfState.killing[x.id]; });
  if (!list.length) { box.innerHTML = '<div class="wolf-empty"><i></i>No active streams</div>'; return; }
  var now = Date.now() / 1000;
  box.innerHTML = list.map(function (x) {
    var age = x.started ? now - x.started : 0;
    var stale = age > STALE_SECS;
    var armed = wolfState.armed === x.id;
    return '<div class="wolf-row' + (stale ? ' stale' : '') + '" data-id="' + esc(x.id) + '">' +
      '<div class="wolf-ico">' + ICON_STREAM + '</div>' +
      '<div><div class="wolf-app">' + esc(x.app) +
        (stale ? '<span class="wolf-badge">stuck?</span>' : '') + '</div>' +
      '<div class="wolf-meta"><b>' + esc(x.client_label || x.client) + '</b>' +
        (x.video ? ' &middot; ' + esc(x.video.replace('x', '×').replace('@', ' @ ') + 'Hz') : '') +
        (x.started ? ' &middot; <span title="since the bridge first saw it">streaming ' + fmtFor(age) + '</span>' : '') +
      '</div></div>' +
      '<button class="wolf-kill' + (armed ? ' armed' : '') + '" data-kill="' + esc(x.id) + '">' + ICON_STOP +
        '<span>' + (armed ? 'Tap to kill' : 'End') + '</span></button>' +
    '</div>';
  }).join('');
}
var wolfLast = null;
function wolfRefresh() {
  fetch('wolf/sessions').then(function (r) { return r.json(); })
    .then(function (d) { wolfLast = d; wolfRender(d); })
    .catch(function () { wolfRender({ wolf: 'unreachable' }); });
}
document.getElementById('wolf').addEventListener('click', function (ev) {
  var btn = ev.target.closest('button[data-kill]');
  if (!btn) return;
  var id = btn.dataset.kill;
  if (wolfState.armed !== id) {           // first tap arms it for 3 s
    wolfState.armed = id;
    if (wolfLast) wolfRender(wolfLast);
    setTimeout(function () {
      if (wolfState.armed === id) { wolfState.armed = null; if (wolfLast) wolfRender(wolfLast); }
    }, 3000);
    return;
  }
  wolfState.armed = null;
  var row = btn.closest('.wolf-row');
  row.classList.add('gone');                // optimistic: slide it away now
  wolfState.killing[id] = true;
  logAdd('ending stream ' + id + '…', '');
  fetch('wolf/stop/' + encodeURIComponent(id), { method: 'POST', headers: { 'X-Dash': '1' } })
    .then(function (r) { return r.json().then(function (j) { return { code: r.status, j: j }; }); })
    .then(function (res) {
      // 404 = Wolf no longer has it: already gone is what we wanted.
      if (res.j.ok || res.code === 404) {
        logAdd(res.j.lingering ? 'stream told to stop — Wolf is still tearing it down' : 'stream ended', 'good');
      } else {
        delete wolfState.killing[id];
        logAdd('could not end stream: ' + (res.j.error || res.code), 'err');
      }
    })
    .catch(function (e) { delete wolfState.killing[id]; logAdd('could not end stream: ' + e, 'err'); })
    .then(function () { setTimeout(function () { wolfState.killing = {}; wolfRefresh(); }, 900); });
});

refresh();
wolfRefresh();
setInterval(function () { if (!document.hidden) wolfRefresh(); }, 5000);
// Only while someone can see it. An iframe reports its parent tab's visibility,
// so a backgrounded dashboard stops costing the Pi an SSH call every 10s; it
// catches up the moment the tab is shown again.
setInterval(function () { if (!document.hidden) refresh(); }, 10000);
document.addEventListener('visibilitychange', function () {
  if (!document.hidden) { refresh(); wolfRefresh(); }
});
</script></body></html>
"""


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
        elif path == "wolf/sessions":
            self._send(200, json.dumps(wolf_sessions()), "application/json")
        elif path in FONTS and FONT_DIR:
            try:
                with open(os.path.join(FONT_DIR, FONTS[path]), "rb") as fh:
                    self._send_bytes(200, fh.read(), "font/woff2", cache=True)
            except OSError:
                self._send(404, "font missing", "text/plain")
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
            code, body = wolf_stop(path[len("wolf/stop/"):])
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
        name = path[4:]
        entry = ACTIONS.get(name)
        if not entry:
            self._send(400, json.dumps({"ok": False, "message": "unknown action"}),
                       "application/json")
            return
        label, fn = entry
        ok, msg = fn()
        invalidate_status()
        self._send(200, json.dumps({"ok": ok, "action": label, "message": msg or label}),
                   "application/json")

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
    Server(("0.0.0.0", PORT), Handler).serve_forever()
