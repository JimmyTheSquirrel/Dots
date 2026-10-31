#!/usr/bin/env python3
"""
Home Assistant bridge for the dashboards (asgard:8888 and marsbar:1111).

Why a bridge at all: Glance renders every widget server-side and injects the
markup with innerHTML, so a dashboard cannot talk to HA by itself — a <script>
in a widget template never executes, embedding the token would publish it in
page source, and HA refuses cross-origin calls anyway. This holds the token
server-side and exposes a handful of verbs:

  GET  /events           Server-Sent Events: a full snapshot on connect, then one
                         event per state change, plus a ping every 15s
  GET  /states           the same snapshot as one JSON object {entity: state}
  GET  /history          the last 24 h of every plug's power draw, as
                         10-minute time-weighted averages (the Power page chart)
  POST /toggle/<entity>  toggle one ALLOWED entity (needs `X-Dash: 1`)
  POST /light/<entity>   set one COLOURABLE bulb's preset and/or brightness
                         (likewise), and remember the choice in HA

PUSH, NOT POLL. Every open dashboard used to poll /states every 3s — hidden tabs
and pages without a single light included — and every one of those polls made
this bridge download HA's ENTIRE /api/states (hundreds of entities) to answer
with a handful. Now one websocket to HA (`subscribe_entities`, filtered to the
watched entities server-side, so HA only ever sends us what we care about) feeds
an in-memory snapshot, and every dashboard holds one EventSource. A lamp flipped
from her phone, the HA app, an automation or the physical button shows up on
every open dashboard within a few hundred milliseconds, and an idle dashboard
costs nothing but a ping every 15s.

If the websocket is down the bridge falls back to polling /api/states/<entity>
for the watched entities only, every POLL_S, and tells the dashboards so (link
"polling"), until the websocket comes back.

⚠ ALLOWED is the safety boundary, not the UI. The dashboards render Asgard's and
Eclipse's relays as locked, but a locked button is only a suggestion — anything
reachable on the tailnet could POST here. Keeping those two entity ids out of
ALLOWED (Modules/Server/_plugs.nix: `light = false`) is what actually stops a
stray request hard-cutting a running machine mid-write.

Config comes from HA_BRIDGE_CONFIG, a JSON file generated from the plug
inventory: {"allowed": [...], "watched": [...], "origins": [...]}. The token
comes in as a systemd credential ($CREDENTIALS_DIRECTORY/ha-token), never from a
world-readable path.
"""

import asyncio
import json
import logging
import math
import os
import time
from datetime import datetime, timezone
from urllib.parse import quote

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

HA = os.environ.get("HA_URL", "http://127.0.0.1:8123")
HOST = os.environ.get("HA_BRIDGE_HOST", "0.0.0.0")
PORT = int(os.environ.get("HA_BRIDGE_PORT", "9556"))

with open(os.environ["HA_BRIDGE_CONFIG"]) as _fh:
    _CONFIG = json.load(_fh)

ALLOWED = frozenset(_CONFIG["allowed"])
# Everything toggleable is necessarily watched, or a toggle could never confirm.
WATCHED = sorted(set(_CONFIG["watched"]) | ALLOWED)
WATCHED_SET = frozenset(WATCHED)
ORIGINS = frozenset(_CONFIG.get("origins", []))
# ── The bedside bulbs ───────────────────────────────────────────────────────
# POST /light may recolour these and nothing else, to one of PRESETS and nothing
# else — the same kind of boundary ALLOWED is for power, and for the same reason:
# anything on the tailnet can reach this port. Each entry names that bulb's two
# HA helper entities (input_select + input_number), which the bridge writes the
# choice into so the touch lamp's next power cut cannot lose it. Those two ids
# are also the ONLY input_select/input_number this process will ever write.
LIGHTS = {k: v for k, v in (_CONFIG.get("lights") or {}).items()}
# name -> {"rgbww": [r, g, b, cold_white, warm_white]}. Generated from the one
# preset table in Modules/Server/_plugs.nix, the same one the swatches are drawn
# from. One key for every preset because the reflashed firmware gives the bulb a
# single combined colour mode — see the note on `presets` in that file.
PRESETS = {k: v for k, v in (_CONFIG.get("presets") or {}).items()}
# The "mix your own" swatch. CUSTOM_NAME is the input_select option that means
# "use the sliders"; CUSTOM_CHANNELS are the five input_number entities behind
# it, in rgbww order (red, green, blue, cold white, warm white). Like the two
# per-bulb helpers, these are the ONLY input_numbers this process will write —
# a caller cannot name an entity, it can only supply five numbers.
CUSTOM_NAME = _CONFIG.get("customName") or "Custom"
CUSTOM_CHANNELS = list(_CONFIG.get("customChannels") or [])

# The power sensors the Power page charts. Read with HA's history API on
# demand — never streamed, never polled while nobody is looking.
HISTORY = list(_CONFIG.get("history", []))

KEEPALIVE_S = 15    # SSE ping — under any proxy idle timeout, and the client's watchdog
POLL_S = 10         # fallback poll interval while the websocket is down
TOGGLE_WAIT_S = 2.0 # how long POST /toggle waits for HA to report the new state
LIGHT_BODY_MAX = 512 # POST /light accepts a tiny JSON object; refuse anything else
CLIENT_QUEUE = 256  # frames buffered per SSE client before it is cut loose
RETRY_MS = 2000     # EventSource reconnect delay the browser is told to use
HIST_HOURS = 24     # /history window
HIST_STEP = 600     # /history bucket, seconds (144 points a day)
HIST_TTL = 120      # /history answers are reused for this long

log = logging.getLogger("ha-bridge")


def read_token():
    creds = os.environ.get("CREDENTIALS_DIRECTORY")
    path = (os.path.join(creds, "ha-token") if creds
            else os.environ.get("HA_TOKEN_FILE", "/run/secrets/ha-token"))
    with open(path) as fh:
        return fh.read().strip()


def sse(event, payload):
    return ("event: %s\ndata: %s\n\n" % (event, json.dumps(payload, separators=(",", ":")))).encode()


class Hub:
    """The snapshot, the SSE subscribers, and anyone waiting on a change."""

    def __init__(self):
        self.states = {}         # entity_id -> state string, watched entities only
        self.link = "connecting" # live | polling | down | connecting
        self.clients = set()     # one asyncio.Queue of encoded frames per SSE client
        self.waiters = {}        # entity_id -> set of futures for its next change

    def set_state(self, entity, state):
        if entity not in WATCHED_SET or state is None:
            return
        if self.states.get(entity) == state:
            return
        self.states[entity] = state
        self.broadcast(sse("state", {"entity": entity, "state": state}))
        for fut in self.waiters.pop(entity, ()):
            if not fut.done():
                fut.set_result(state)

    def set_link(self, link):
        if link == self.link:
            return
        log.info("home assistant link: %s -> %s", self.link, link)
        self.link = link
        self.broadcast(sse("link", {"ha": link}))

    def snapshot(self):
        return sse("snapshot", {"states": self.states, "ha": self.link})

    def broadcast(self, frame):
        for q in list(self.clients):
            try:
                q.put_nowait(frame)
            except asyncio.QueueFull:
                # A client that stopped reading (a suspended phone whose socket
                # has not died yet). Cut it loose rather than buffer forever;
                # its EventSource reconnects and gets a fresh snapshot.
                self.clients.discard(q)


# ── Home Assistant side ──────────────────────────────────────────────────────

def apply_entities_event(hub, event, first):
    """Apply one `subscribe_entities` event (HA's compressed state format).

    {"a": {id: {"s": state, "a": attrs, ...}}}   added / initial snapshot
    {"c": {id: {"+": {"s": state, ...}}}}         changed ("s" only if the state did)
    {"r": [id, ...]}                               removed
    """
    added = event.get("a") or {}
    for entity, st in added.items():
        hub.set_state(entity, st.get("s"))
    if first:
        # The first event after (re)subscribing is the complete current set.
        # Anything watched that HA did not include no longer exists there.
        for entity in WATCHED:
            if entity not in added:
                hub.set_state(entity, "unavailable")
    for entity, diff in (event.get("c") or {}).items():
        plus = diff.get("+") or {}
        if "s" in plus:
            hub.set_state(entity, plus["s"])
    for entity in event.get("r") or []:
        hub.set_state(entity, "unavailable")


async def ha_websocket(app):
    """Hold one subscription to HA for as long as the process lives."""
    hub, session = app["hub"], app["session"]
    backoff = 1
    last_error = None
    while True:
        try:
            async with session.ws_connect(HA + "/api/websocket", heartbeat=20) as ws:
                hello = await ws.receive_json(timeout=10)
                if hello.get("type") != "auth_required":
                    raise RuntimeError("unexpected greeting: %r" % hello.get("type"))
                await ws.send_json({"type": "auth", "access_token": app["token"]})
                auth = await ws.receive_json(timeout=10)
                if auth.get("type") != "auth_ok":
                    raise RuntimeError("auth refused: %s" % auth.get("message", auth.get("type")))
                await ws.send_json({"id": 1, "type": "subscribe_entities", "entity_ids": WATCHED})

                first = True
                async for msg in ws:
                    if msg.type != WSMsgType.TEXT:
                        break
                    data = json.loads(msg.data)
                    for m in data if isinstance(data, list) else [data]:
                        if m.get("type") == "result" and not m.get("success"):
                            raise RuntimeError("subscribe_entities failed: %s" % m.get("error"))
                        if m.get("type") == "event" and m.get("id") == 1:
                            apply_entities_event(hub, m.get("event") or {}, first)
                            if first:
                                first = False
                                backoff = 1
                                last_error = None
                                hub.set_link("live")
                raise ConnectionError("websocket closed")
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — any failure means reconnect
            # Log each distinct failure once, not once per backoff step — a
            # revoked token would otherwise fill the journal every 30s.
            err = "%s: %s" % (type(exc).__name__, exc)
            if err != last_error:
                log.warning("home assistant websocket: %s (retrying with backoff)", err)
                last_error = err
        if hub.link == "live":
            # Hand over to the poller until the websocket is back. Not "down":
            # the poller decides that, on its own evidence.
            hub.set_link("polling")
            app["poll_now"].set()
        await asyncio.sleep(backoff)
        backoff = min(backoff * 2, 30)


async def fetch_state(app, entity):
    async with app["session"].get(HA + "/api/states/" + entity,
                                  headers=app["auth"],
                                  timeout=ClientTimeout(total=5)) as r:
        if r.status == 404:
            return entity, "unavailable"
        r.raise_for_status()
        return entity, (await r.json()).get("state")


async def poll_once(app):
    results = await asyncio.gather(*(fetch_state(app, e) for e in WATCHED),
                                   return_exceptions=True)
    hub = app["hub"]
    ok = [r for r in results if not isinstance(r, BaseException)]
    # A poll that started before the websocket came back must not overwrite
    # what the websocket has reported since.
    if hub.link != "live":
        for entity, state in ok:
            hub.set_state(entity, state)
    return bool(ok)


async def ha_poller(app):
    """Fallback: per-entity REST reads while the websocket is not live."""
    hub, poll_now = app["hub"], app["poll_now"]
    while True:
        if hub.link != "live":
            try:
                ok = await poll_once(app)
            except Exception:  # noqa: BLE001
                ok = False
            if hub.link != "live":
                hub.set_link("polling" if ok else "down")
        poll_now.clear()
        try:
            await asyncio.wait_for(poll_now.wait(), POLL_S)
        except asyncio.TimeoutError:
            pass


# ── History (the Power page chart) ──────────────────────────────────────────

def _ts(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


def bucketize(changes, start, step, n):
    """Time-weighted mean per bucket from a list of (time, watts|None) changes.

    Each reading holds until the next one, so a lamp that sat at 7.9 W for an
    hour and blipped to 0 for a minute averages ~7.8, not the 3.9 a plain mean
    of the two samples would give. Buckets with no known reading are None
    (a gap in the line, not a fake zero).
    """
    end = start + n * step
    acc, cov = [0.0] * n, [0.0] * n
    for i, (t, v) in enumerate(changes):
        if v is None:
            continue
        a = max(t, start)
        b = min(changes[i + 1][0] if i + 1 < len(changes) else end, end)
        while a < b:
            k = int((a - start) // step)
            seg = min(b, start + (k + 1) * step)
            acc[k] += v * (seg - a)
            cov[k] += seg - a
            a = seg
    return [round(acc[k] / cov[k], 1) if cov[k] > 0 else None for k in range(n)]


async def fetch_history(app):
    now = time.time()
    start = (int(now - HIST_HOURS * 3600) // HIST_STEP) * HIST_STEP
    n = math.ceil((now - start) / HIST_STEP)
    iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
    params = {"filter_entity_id": ",".join(HISTORY), "end_time": iso(now),
              "minimal_response": "", "no_attributes": ""}
    async with app["session"].get(HA + "/api/history/period/" + quote(iso(start)),
                                  params=params, headers=app["auth"],
                                  timeout=ClientTimeout(total=20)) as r:
        r.raise_for_status()
        data = await r.json()
    series = {}
    for rows in data or []:
        if not rows:
            continue
        entity = rows[0].get("entity_id")
        changes = []
        for row in rows:
            try:
                v = float(row.get("state"))
            except (TypeError, ValueError):
                v = None  # unavailable / unknown: a gap
            changes.append((_ts(row.get("last_changed") or row.get("last_updated")), v))
        changes.sort(key=lambda c: c[0])
        if entity:
            series[entity] = bucketize(changes, start, HIST_STEP, n)
    return {"start": start, "step": HIST_STEP, "at": int(now),
            "series": {e: series.get(e, [None] * n) for e in HISTORY}}


async def get_history(request):
    app = request.app
    cache = app["history"]
    if cache["body"] is None or time.time() - cache["at"] > HIST_TTL:
        async with app["history_lock"]:  # one HA query however many tabs ask
            if cache["body"] is None or time.time() - cache["at"] > HIST_TTL:
                try:
                    cache["body"] = await fetch_history(app)
                    cache["at"] = time.time()
                except Exception as exc:  # noqa: BLE001
                    log.warning("history: %s: %s", type(exc).__name__, exc)
                    if cache["body"] is None:
                        return reply(request, 502, {"error": "home assistant history unavailable"})
    return reply(request, 200, cache["body"])


# ── HTTP side ────────────────────────────────────────────────────────────────

def cors_headers(request):
    """Allow the listed dashboards — and only those — to read cross-origin.

    The main Glance calls this port directly (asgard:8888 → asgard:9556), so it
    needs these. MarsBar goes through tailscale serve on its own origin and
    needs nothing. Never `*`: see POST /toggle below for why that matters.
    """
    origin = request.headers.get("Origin")
    if origin and origin in ORIGINS:
        return {"Access-Control-Allow-Origin": origin, "Vary": "Origin"}
    return {"Vary": "Origin"}


def reply(request, code, obj):
    return web.json_response(obj, status=code, dumps=lambda o: json.dumps(o, separators=(",", ":")),
                             headers={"Cache-Control": "no-store", **cors_headers(request)})


async def preflight(request):
    headers = cors_headers(request)
    if "Access-Control-Allow-Origin" not in headers:
        return web.Response(status=403, headers=headers)
    headers.update({
        "Access-Control-Allow-Methods": "GET, POST",
        "Access-Control-Allow-Headers": "X-Dash, Content-Type",
        "Access-Control-Max-Age": "600",
    })
    return web.Response(status=204, headers=headers)


async def get_states(request):
    hub = request.app["hub"]
    if not hub.states and hub.link in ("down", "connecting"):
        return reply(request, 503, {"error": "home assistant unreachable"})
    return reply(request, 200, hub.states)


async def get_events(request):
    hub = request.app["hub"]
    resp = web.StreamResponse(headers={
        "Content-Type": "text/event-stream",
        # No caching, and no buffering by anything in between. tailscale serve
        # (MarsBar's /ha mount) is a Go ReverseProxy, which already flushes
        # text/event-stream immediately; X-Accel-Buffering is for any nginx-style
        # proxy that might ever sit in front of this.
        "Cache-Control": "no-cache, no-transform",
        "X-Accel-Buffering": "no",
        **cors_headers(request),
    })
    await resp.prepare(request)

    q = asyncio.Queue(maxsize=CLIENT_QUEUE)
    # Subscribe BEFORE taking the snapshot: a change landing in between then
    # arrives twice (harmless) instead of never (a stale light).
    hub.clients.add(q)
    try:
        await resp.write(("retry: %d\n\n" % RETRY_MS).encode() + hub.snapshot())
        while q in hub.clients:
            try:
                frame = await asyncio.wait_for(q.get(), KEEPALIVE_S)
            except asyncio.TimeoutError:
                # A real event, not an SSE `:` comment. A comment would keep
                # proxies from idling the stream out just as well, but
                # EventSource never surfaces comments to JavaScript — and the
                # dashboards need to SEE the pings to notice a half-open
                # connection (a phone that changed networks) and reconnect,
                # instead of showing stale lights with full confidence.
                frame = sse("ping", {"t": int(time.time()), "ha": hub.link})
            if frame is None:
                break
            await resp.write(frame)
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        hub.clients.discard(q)
    return resp


async def post_toggle(request):
    entity = request.match_info["entity"]
    app, hub = request.app, request.app["hub"]

    # A custom header turns any cross-origin fetch into one that must pass a
    # CORS preflight first, and the preflight only succeeds for ORIGINS. Without
    # it, any web page open in a tailnet browser could flip a light with a
    # one-line fetch() — a body-less POST is a "simple" request that the browser
    # sends without asking.
    if request.headers.get("X-Dash") != "1":
        return reply(request, 403, {"error": "missing X-Dash header"})
    if entity not in ALLOWED:
        return reply(request, 403, {"error": "not toggleable", "entity": entity})

    fut = asyncio.get_running_loop().create_future()
    hub.waiters.setdefault(entity, set()).add(fut)
    try:
        async with app["session"].post(
                HA + "/api/services/" + entity.split(".")[0] + "/toggle",
                json={"entity_id": entity}, headers=app["auth"],
                timeout=ClientTimeout(total=10)) as r:
            if r.status >= 400:
                return reply(request, 502, {"error": "home assistant answered %d" % r.status})
            changed = await r.json(content_type=None)
        # HA lists whatever changed while the service ran — often nothing yet,
        # since a plug only reports back once its relay has actually moved.
        for st in changed or []:
            if isinstance(st, dict):
                hub.set_state(st.get("entity_id"), st.get("state"))
        # Rather than the old fixed 0.6s sleep, wait for the change itself (a
        # group switch settles last, after its members, so by the time it
        # reports, they have too). Bounded, so a plug that ignores the command
        # still gets an answer.
        if not fut.done():
            try:
                await asyncio.wait_for(asyncio.shield(fut), TOGGLE_WAIT_S)
            except asyncio.TimeoutError:
                if hub.link != "live":
                    # No websocket to tell us — read it back directly.
                    e, s = await fetch_state(app, entity)
                    hub.set_state(e, s)
    except Exception as exc:  # noqa: BLE001
        return reply(request, 502, {"error": str(exc) or type(exc).__name__})
    finally:
        waiting = hub.waiters.get(entity)
        if waiting is not None:
            waiting.discard(fut)
            if not waiting:
                hub.waiters.pop(entity, None)

    # `state` for callers that only care about the entity they clicked;
    # `states` so a group toggle can repaint its members in the same breath.
    return reply(request, 200, {"entity": entity, "state": hub.states.get(entity),
                                "states": hub.states})



async def call_service(app, domain, service, data):
    """Call one HA service and fold whatever it reports changed into the snapshot.

    HA answers a service call with the states that changed while it ran, so a
    light that was off and is now on — or an input_select that has just taken a
    new option — is already in the reply. Feeding those straight into the hub
    means every open dashboard repaints from this one call, without waiting for
    the websocket to come round, and it still works in the degraded polling mode.
    """
    async with app["session"].post(
            HA + "/api/services/%s/%s" % (domain, service),
            json=data, headers=app["auth"],
            timeout=ClientTimeout(total=10)) as r:
        if r.status >= 400:
            raise RuntimeError("home assistant answered %d for %s.%s" % (r.status, domain, service))
        changed = await r.json(content_type=None)
    hub = app["hub"]
    for st in changed or []:
        if isinstance(st, dict):
            hub.set_state(st.get("entity_id"), st.get("state"))


def current_mix(hub):
    """The five custom channels as they stand, from the live state snapshot.

    Returns None if any of them is missing or not a number — which happens on a
    fresh install before the input_numbers have ever been written, and means
    "there is no mix yet" rather than "the mix is black".
    """
    out = []
    for spec in CUSTOM_CHANNELS:
        raw = hub.states.get(spec["entity"])
        try:
            v = int(round(float(raw)))
        except (TypeError, ValueError):
            return None
        out.append(max(0, min(255, v)))
    return out or None


async def apply_mix(app, hub, channels):
    """Push a mix to every colourable bulb that is ON and already set to Custom.

    That is what makes dragging a slider feel live: tap Custom on the lamp you
    want, then dial it in and watch it move. A lamp that is off, or showing a
    different preset, is deliberately left alone — moving a slider must never
    switch a lamp on by itself.
    """
    for entity, conf in LIGHTS.items():
        if hub.states.get(entity) != "on":
            continue
        if hub.states.get(conf["preset"]) != CUSTOM_NAME:
            continue
        await call_service(app, "light", "turn_on",
                           {"entity_id": entity, "rgbww_color": list(channels)})


async def post_mix(request):
    """Store the shared custom colour, and preview it where it is already lit.

    Body: {"channels": [r, g, b, cold, warm]}, each 0-255.

    Separate from POST /light because this verb must NOT turn a lamp on. It
    writes the five sliders — the mix is shared by both bedside lamps and
    persists in HA — and only then pushes it to lamps already showing Custom.
    """
    app, hub = request.app, request.app["hub"]
    if request.headers.get("X-Dash") != "1":
        return reply(request, 403, {"error": "missing X-Dash header"})
    if not CUSTOM_CHANNELS:
        return reply(request, 500, {"error": "no custom channels configured"})
    if (request.content_length or 0) > LIGHT_BODY_MAX:
        return reply(request, 413, {"error": "body too large"})
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001
        return reply(request, 400, {"error": "expected a JSON object"})
    if not isinstance(body, dict):
        return reply(request, 400, {"error": "expected a JSON object"})

    channels = body.get("channels")
    if not isinstance(channels, list) or len(channels) != len(CUSTOM_CHANNELS):
        return reply(request, 400,
                     {"error": "channels must be %d numbers" % len(CUSTOM_CHANNELS)})
    clean = []
    for v in channels:
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return reply(request, 400, {"error": "channels must be numbers"})
        v = int(round(v))
        if not 0 <= v <= 255:
            return reply(request, 400, {"error": "channels out of range 0-255"})
        clean.append(v)

    try:
        for spec, value in zip(CUSTOM_CHANNELS, clean):
            await call_service(app, "input_number", "set_value",
                               {"entity_id": spec["entity"], "value": value})
        await apply_mix(app, hub, clean)
    except Exception as exc:  # noqa: BLE001
        return reply(request, 502, {"error": str(exc) or type(exc).__name__})

    return reply(request, 200, {"channels": clean, "states": hub.states})


async def post_light(request):
    """Set one COLOURABLE bulb's colour preset and/or brightness.

    Body: {"preset": "<a PRESETS name>"} and/or {"brightness_pct": 1..100},
    or {"channels": [r, g, b, cold, warm]} to mix a colour by hand.
    Any alone is fine; together is one call.

    `channels` is the one place a caller supplies a colour rather than naming
    one. That is safe for the same reason /toggle is: the ENTITY allowlist is
    the boundary, and it has already been checked above — these are bedroom
    lamps, and an odd colour on one is not a privileged action. Every value is
    still validated, the five are written to the custom sliders, and the
    bulb's preset is set to CUSTOM_NAME so the restore automation and both
    dashboards agree about what it is showing.

    Three things happen, and the order matters: the bulb is set, then the two
    HA helpers are updated to match. The helpers are the bulb's MEMORY — the
    bedroom lamps are touch lamps, so mains is cut at the base and HA loses the
    live colour attributes entirely. What is written here is what the restore
    automation puts back when the lamp is switched on again, and what both
    dashboards read to light the right swatch.

    turn_on, not a colour-only change: tapping a swatch on a lamp that is off
    should light it, which is also what makes the swatches work as the only
    control anyone needs.
    """
    entity = request.match_info["entity"]
    app, hub = request.app, request.app["hub"]

    # Same reasoning as POST /toggle: a custom header forces a CORS preflight,
    # and only ORIGINS pass it. Checked before the allowlist so an unauthorised
    # caller learns nothing about which entities exist.
    if request.headers.get("X-Dash") != "1":
        return reply(request, 403, {"error": "missing X-Dash header"})
    conf = LIGHTS.get(entity)
    if conf is None:
        return reply(request, 403, {"error": "not colourable", "entity": entity})

    if (request.content_length or 0) > LIGHT_BODY_MAX:
        return reply(request, 413, {"error": "body too large"})
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001 — any malformed body is the same answer
        return reply(request, 400, {"error": "expected a JSON object"})
    if not isinstance(body, dict):
        return reply(request, 400, {"error": "expected a JSON object"})

    # Build the service data from the PRESET TABLE, never from the body: the
    # caller picks a preset by name and the five channel values behind it come
    # from the config. So no caller can send an arbitrary colour, and a swatch
    # and the restore automation cannot disagree about what "Amber" means.
    data = {"entity_id": entity}

    # A hand-mixed colour. Mutually exclusive with `preset`: accepting both
    # would leave the swatch and the lamp disagreeing about what is lit.
    channels = body.get("channels")
    preset = body.get("preset")
    if channels is not None and preset is not None:
        return reply(request, 400, {"error": "send either preset or channels, not both"})
    if channels is not None:
        if not CUSTOM_CHANNELS:
            return reply(request, 500, {"error": "no custom channels configured"})
        if not isinstance(channels, list) or len(channels) != len(CUSTOM_CHANNELS):
            return reply(request, 400,
                         {"error": "channels must be %d numbers" % len(CUSTOM_CHANNELS)})
        clean = []
        for v in channels:
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                return reply(request, 400, {"error": "channels must be numbers"})
            v = int(round(v))
            if not 0 <= v <= 255:
                return reply(request, 400, {"error": "channels out of range 0-255"})
            clean.append(v)
        if not any(clean):
            # All five at zero is "on but emitting nothing", which reads as a
            # broken bulb. Turning it off is a different verb.
            return reply(request, 400, {"error": "at least one channel must be above zero"})
        channels = clean
        data["rgbww_color"] = channels
        preset = CUSTOM_NAME

    if channels is None and preset == CUSTOM_NAME:
        # The Custom swatch behaves like any other: one tap lights the lamp
        # with the stored mix. The values come from the live snapshot, so the
        # swatch and the sliders can never disagree.
        channels = current_mix(request.app["hub"])
        if channels is None:
            return reply(request, 400, {"error": "no custom colour set yet"})
        data["rgbww_color"] = list(channels)
    elif channels is None and preset is not None:
        spec = PRESETS.get(preset) if isinstance(preset, str) else None
        if not spec:
            return reply(request, 400, {"error": "unknown preset", "preset": preset})
        # rgbww_color: all five channels at once, which is the whole point of
        # the firmware change — amber can sit ON TOP of warm white instead of
        # replacing it. A preset without it is a config error, not a request
        # the caller got wrong, so it is a 500 rather than a 400.
        channels = spec.get("rgbww")
        if not isinstance(channels, list) or len(channels) != 5:
            log.error("preset %r has no usable rgbww channels: %r", preset, spec)
            return reply(request, 500, {"error": "preset misconfigured", "preset": preset})
        data["rgbww_color"] = list(channels)

    bright = body.get("brightness_pct")
    if bright is not None:
        if isinstance(bright, bool) or not isinstance(bright, (int, float)):
            return reply(request, 400, {"error": "brightness_pct must be a number"})
        bright = int(round(bright))
        if not 1 <= bright <= 100:
            return reply(request, 400, {"error": "brightness_pct out of range 1-100"})
        data["brightness_pct"] = bright

    if len(data) == 1:
        return reply(request, 400, {"error": "nothing to set"})

    try:
        await call_service(app, "light", "turn_on", data)
        # The sliders first, so that by the time the input_select flips to
        # Custom the mix behind it is already the one that is lit.
        if channels is not None:
            for spec, value in zip(CUSTOM_CHANNELS, channels):
                await call_service(app, "input_number", "set_value",
                                   {"entity_id": spec["entity"], "value": value})
        if preset is not None:
            await call_service(app, "input_select", "select_option",
                               {"entity_id": conf["preset"], "option": preset})
        if bright is not None:
            await call_service(app, "input_number", "set_value",
                               {"entity_id": conf["bright"], "value": bright})
    except Exception as exc:  # noqa: BLE001
        return reply(request, 502, {"error": str(exc) or type(exc).__name__})

    return reply(request, 200, {"entity": entity, "state": hub.states.get(entity),
                                "states": hub.states})

# ── lifecycle ────────────────────────────────────────────────────────────────

async def on_startup(app):
    app["token"] = read_token()
    app["auth"] = {"Authorization": "Bearer " + app["token"]}
    app["session"] = ClientSession()
    app["poll_now"] = asyncio.Event()
    app["history"] = {"at": 0.0, "body": None}
    app["history_lock"] = asyncio.Lock()
    app["tasks"] = [asyncio.create_task(ha_websocket(app)),
                    asyncio.create_task(ha_poller(app))]


async def on_shutdown(app):
    # Release the SSE handlers, which would otherwise hold shutdown open for
    # aiohttp's whole grace period waiting on streams that never end.
    hub = app["hub"]
    for q in list(hub.clients):
        hub.clients.discard(q)
        try:
            q.put_nowait(None)
        except asyncio.QueueFull:
            pass


async def on_cleanup(app):
    for t in app["tasks"]:
        t.cancel()
    await asyncio.gather(*app["tasks"], return_exceptions=True)
    await app["session"].close()


def make_app():
    app = web.Application()
    app["hub"] = Hub()
    app.router.add_get("/events", get_events)
    app.router.add_get("/states", get_states)
    app.router.add_get("/history", get_history)
    app.router.add_post("/toggle/{entity}", post_toggle)
    app.router.add_post("/light/{entity}", post_light)
    app.router.add_post("/mix", post_mix)
    app.router.add_route("OPTIONS", "/{tail:.*}", preflight)
    app.on_startup.append(on_startup)
    app.on_shutdown.append(on_shutdown)
    app.on_cleanup.append(on_cleanup)
    return app


if __name__ == "__main__":
    logging.basicConfig(level=os.environ.get("HA_BRIDGE_LOG", "INFO"),
                        format="%(levelname)s %(message)s")
    web.run_app(make_app(), host=HOST, port=PORT, access_log=None,
                shutdown_timeout=3, print=None)
