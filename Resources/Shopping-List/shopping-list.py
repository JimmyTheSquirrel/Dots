#!/usr/bin/env python3
"""
shopping-list — the shared shopping list and recipe book behind both dashboards.

One small process holds the list (and the recipes, and what has been bought
before) in memory, writes it to one JSON file on every change, and pushes the
whole thing to every open dashboard the moment it changes. Both dashboards run
the same client (Resources/Glance/shopping.js): the admin Glance on asgard:8888
calls this directly over the tailnet; MarsBar reaches it through its own
`tailscale serve` mount at /shop-api, so her browser never needs a grant on
this port.

  GET  /events          Server-Sent Events: `state` (everything) on connect and
                        after every change, `ping` every 15 s so a half-open
                        stream can be noticed and reopened
  GET  /state           the same snapshot, once

  POST /items/add       {items: [{id?, name, qty?, cat?, from?}], by?, recipe?}
                        A name already on the list is MERGED, not duplicated:
                        quantities with the same unit add up ("2" + "3" → "5",
                        "500g" + "250g" → "750g"); one already ticked is put
                        back on the list. `recipe` (an id) counts a cook.
  POST /items/toggle    {id, done}
  POST /items/edit      {id, name?, qty?, cat?}
  POST /items/remove    {ids: [...]}
  POST /items/clear     {which: "done" | "all"}
  POST /items/restore   {items: [...]}   put removed items back (Undo)
  POST /recipes/save    {id?, name, icon?, ingredients: [{name, qty?, cat?}], note?}
  POST /recipes/delete  {id}

Every POST answers {ok, state} (or {ok: false, error}) and needs `X-Dash: 1`.

Every write is IDEMPOTENT, on purpose: the client queues changes it could not
deliver (a phone in a supermarket with one bar of signal) and retries them, so
the same request can arrive twice. An add carries the client's own id and is a
no-op if that id exists; a toggle says which way; remove and edit name their
ids. Replaying a request never doubles anything.

Security is the same as the other dashboard backends (see
Modules/Server/_origins.nix): CORS only for the dashboard origins, never `*`;
a POST without `X-Dash: 1` is refused (the custom header forces a CORS
preflight, which only those origins pass); bodies are capped at 64 KB; every
string is cleaned (control characters out, length capped) and every id and
category checked against a pattern. The client escapes everything it draws.
Tailnet-only: :9558 is not in allowedTCPPorts and only tailscale0 is trusted.

State lives in $STATE_DIRECTORY/state.json (the unit's StateDirectory, so it
survives reboots and rebuilds), written to a temp file and renamed, so a crash
mid-write can never leave a half file. It is user data, not configuration: the
one declarative piece is the starter recipes (SHOP_SEED), used ONLY when there
is no state file at all — a fresh install — so deleting a starter recipe sticks.
"""

import http.server
import json
import os
import re
import secrets
import socketserver
import threading
import time
import unicodedata
from urllib.parse import urlsplit

PORT = int(os.environ.get("SHOP_PORT", "9558"))
STATE = os.environ.get("SHOP_STATE") or os.path.join(
    os.environ.get("STATE_DIRECTORY", "/var/lib/shopping-list").split(":")[0], "state.json")
SEED = os.environ.get("SHOP_SEED", "")

# Mirrors Modules/Server/_origins.nix, which Modules/Server/shopping.nix passes
# in as DASH_ORIGINS; this default only applies when run by hand.
DASH_ORIGINS = frozenset(o.strip() for o in os.environ.get(
    "DASH_ORIGINS",
    "http://asgard:8888,http://asgard.tailb54b82.ts.net:8888,"
    "http://100.126.205.100:8888,http://marsbar:1111,"
    "http://marsbar.tailb54b82.ts.net:1111",
).split(",") if o.strip())

MAX_ITEMS = 300
MAX_RECIPES = 200
MAX_INGREDIENTS = 60
MAX_HISTORY = 400      # remembered names, for the "usuals" and suggestions
SENT_HISTORY = 160     # how many of them each snapshot carries
MAX_BATCH = 80         # items in one add / restore
NAME_LEN = 80
QTY_LEN = 24
FROM_LEN = 60
NOTE_LEN = 600
ICON_LEN = 16
WHO_LEN = 20
BODY_MAX = 64 * 1024
PING_SECONDS = 15

ID_RE = re.compile(r"^[a-z0-9]{6,16}$")
CAT_RE = re.compile(r"^[a-z]{1,12}$")
# "2", "1.5", "500g", "2 L", "3 tins" — a number and an optional unit word.
QTY_RE = re.compile(r"^\s*(\d+(?:[.,]\d+)?)\s*([^\d\s].{0,15})?\s*$")

_lock = threading.Condition()
_state = {}


# ── cleaning ────────────────────────────────────────────────────────────────
# Bidi overrides and isolates: invisible, and only good for making text lie
# about its own order.
_BIDI = set("\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069")


def clean(value, limit):
    """A display string: no control characters, whitespace collapsed, capped.
    Format characters (Cf) other than bidi controls stay: the zero-width joiner
    is what holds a composite emoji like 👩‍🍳 together."""
    if not isinstance(value, str):
        return ""
    value = "".join(ch for ch in value
                    if ch in " \t" or (unicodedata.category(ch) not in ("Cc", "Cs", "Co", "Cn") and ch not in _BIDI))
    value = " ".join(value.split())
    return value[:limit].strip()


def clean_cat(value):
    return value if isinstance(value, str) and CAT_RE.match(value) else "other"


def clean_id(value):
    return value if isinstance(value, str) and ID_RE.match(value) else None


def new_id():
    return secrets.token_hex(5)  # 10 chars of [0-9a-f] — matches ID_RE


def key(name):
    """How two names are recognised as the same thing: case, spacing and a
    plural ending don't matter ("Onions" == "onion", "berries" == "berry").
    shopping.js has the same function — keep them in step."""
    k = " ".join(name.lower().split()).strip(" .,;:!-")
    if len(k) > 4 and k.endswith("ies"):
        return k[:-3] + "y"
    if len(k) > 4 and k.endswith("oes"):
        return k[:-2]
    if len(k) > 3 and k.endswith("s") and not k.endswith(("ss", "us", "is")):
        return k[:-1]
    return k


def _num(text):
    return float(text.replace(",", "."))


def _fmt(n):
    return str(int(n)) if n == int(n) else ("%.2f" % n).rstrip("0").rstrip(".")


def merge_qty(a, b):
    """The quantity after adding b to an item that already says a."""
    if not a:
        return b
    if not b:
        return a
    ma, mb = QTY_RE.match(a), QTY_RE.match(b)
    if ma and mb and (ma.group(2) or "").strip().lower() == (mb.group(2) or "").strip().lower():
        unit = (ma.group(2) or "").strip()
        total = _fmt(_num(ma.group(1)) + _num(mb.group(1)))
        # "500g" stays tight, "3 tins" keeps its space — as it was written.
        sep = " " if re.match(r"^\s*[\d.,]+\s", a) else ""
        return (total + (sep + unit if unit else ""))[:QTY_LEN]
    joined = a + " + " + b
    return joined if len(joined) <= QTY_LEN else a


def merge_from(a, b):
    if not b or b in [p.strip() for p in (a or "").split(",")]:
        return a
    joined = (a + ", " + b) if a else b
    return joined if len(joined) <= FROM_LEN else a


# ── state ───────────────────────────────────────────────────────────────────
def empty():
    # sid: changes only when the file is created afresh, so a client holding a
    # snapshot from before can tell a reset from an old message.
    return {"sid": new_id(), "v": 0, "items": [], "recipes": [], "history": {}}


def seed_recipes():
    """The starter recipes (a JSON list), cleaned like any other save."""
    if not SEED:
        return []
    try:
        with open(SEED) as fh:
            raw = json.load(fh)
    except (OSError, ValueError):
        return []
    out = []
    for r in raw if isinstance(raw, list) else []:
        rec = recipe_from(r, None)
        if rec:
            out.append(rec)
    return out[:MAX_RECIPES]


def load():
    global _state
    try:
        with open(STATE) as fh:
            st = json.load(fh)
        if not isinstance(st, dict) or not isinstance(st.get("items"), list):
            raise ValueError("not a state file")
        st.setdefault("sid", new_id())
        st.setdefault("v", 0)
        st.setdefault("recipes", [])
        st.setdefault("history", {})
        _state = st
        return
    except FileNotFoundError:
        _state = empty()
        _state["recipes"] = seed_recipes()
    except (OSError, ValueError) as exc:
        # Keep the unreadable file for a human to look at, and start empty
        # rather than refuse to run. No re-seeding: the recipes they had
        # deleted would come back.
        aside = "%s.broken-%d" % (STATE, int(time.time()))
        try:
            os.replace(STATE, aside)
        except OSError:
            pass
        print("state file unreadable (%s); kept as %s, starting empty" % (exc, aside), flush=True)
        _state = empty()
    save()


def save():
    os.makedirs(os.path.dirname(STATE) or ".", exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(_state, fh, ensure_ascii=False, separators=(",", ":"))
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, STATE)


def snapshot():
    """What a dashboard gets. History is trimmed to the names worth suggesting."""
    hist = sorted(_state["history"].values(), key=lambda h: (h.get("n", 0), h.get("at", 0)), reverse=True)
    return {
        "sid": _state["sid"],
        "v": _state["v"],
        "items": _state["items"],
        "recipes": sorted(_state["recipes"], key=lambda r: r["name"].lower()),
        "history": [[h["name"], h.get("cat", "other"), h.get("n", 1), h.get("at", 0)] for h in hist[:SENT_HISTORY]],
    }


def changed():
    """Call with _lock held, after a mutation: persist, bump, wake the streams."""
    _state["v"] += 1
    save()
    _lock.notify_all()


def remember(name, cat, bump=True):
    k = key(name)
    if not k:
        return
    h = _state["history"].get(k) or {"n": 0}
    h.update(name=name, cat=cat, at=int(time.time()))
    if bump:
        h["n"] = h.get("n", 0) + 1
    _state["history"][k] = h
    if len(_state["history"]) > MAX_HISTORY:
        oldest = sorted(_state["history"].items(), key=lambda kv: kv[1].get("at", 0))
        for k2, _ in oldest[:len(_state["history"]) - MAX_HISTORY]:
            del _state["history"][k2]


def find(item_id):
    for it in _state["items"]:
        if it["id"] == item_id:
            return it
    return None


class Refused(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code = code


def who(body):
    return clean(body.get("by"), WHO_LEN)


# ── items ───────────────────────────────────────────────────────────────────
def op_add(body):
    entries = body.get("items")
    if not isinstance(entries, list) or not entries:
        raise Refused(400, "nothing to add")
    by, now, added, merged = who(body), int(time.time()), [], []
    for e in entries[:MAX_BATCH]:
        if not isinstance(e, dict):
            continue
        name = clean(e.get("name"), NAME_LEN)
        if not name:
            continue
        cid = clean_id(e.get("id"))
        if cid and find(cid):
            continue  # a retried request: this one is already here
        qty, cat, frm = clean(e.get("qty"), QTY_LEN), clean_cat(e.get("cat")), clean(e.get("from"), FROM_LEN)
        k = key(name)
        same = [it for it in _state["items"] if key(it["name"]) == k]
        live = next((it for it in same if not it.get("done")), None)
        if live or same:
            it = live or same[0]
            if live:
                it["qty"] = merge_qty(it.get("qty", ""), qty)
                frm = merge_from(it.get("from", ""), frm)
            else:
                # Already in the trolley from earlier: needed again, so it goes
                # back on the list with the new quantity rather than as a twin.
                it.update(done=False, qty=qty, at=now)
                it.pop("doneAt", None)
                if by:
                    it["by"] = by
            if frm:
                it["from"] = frm
            else:
                it.pop("from", None)
            merged.append(it["id"])
            # The item keeps its own name and aisle (which may be a correction
            # someone made); the new entry's guess doesn't overwrite them.
            remember(it["name"], it["cat"])
            continue
        if len(_state["items"]) >= MAX_ITEMS:
            raise Refused(409, "the list is full (%d items)" % MAX_ITEMS)
        it = {"id": cid or new_id(), "name": name, "qty": qty, "cat": cat, "done": False, "at": now}
        if frm:
            it["from"] = frm
        if by:
            it["by"] = by
        _state["items"].append(it)
        added.append(it["id"])
        remember(name, cat)
    rid = clean_id(body.get("recipe"))
    for r in _state["recipes"]:
        if r["id"] == rid:
            r["used"] = r.get("used", 0) + 1
            r["last"] = now
    return {"added": added, "merged": merged}


def op_toggle(body):
    it = find(clean_id(body.get("id")))
    if not it:
        raise Refused(404, "that item is no longer on the list")
    done = bool(body.get("done"))
    if it.get("done") != done:
        it["done"] = done
        if done:
            it["doneAt"] = int(time.time())
        else:
            it.pop("doneAt", None)
    return {}


def op_edit(body):
    it = find(clean_id(body.get("id")))
    if not it:
        raise Refused(404, "that item is no longer on the list")
    if "name" in body:
        name = clean(body.get("name"), NAME_LEN)
        if name:
            it["name"] = name
    if "qty" in body:
        it["qty"] = clean(body.get("qty"), QTY_LEN)
    if "cat" in body:
        it["cat"] = clean_cat(body.get("cat"))
    # The aisle a thing was moved to is the aisle it lives in from now on.
    remember(it["name"], it["cat"], bump=False)
    return {}


def op_remove(body):
    ids = body.get("ids")
    if not isinstance(ids, list):
        raise Refused(400, "no ids")
    want = {i for i in (clean_id(x) for x in ids[:MAX_ITEMS]) if i}
    gone = [it for it in _state["items"] if it["id"] in want]
    _state["items"] = [it for it in _state["items"] if it["id"] not in want]
    now = time.time()
    for it in gone:
        # Taken straight back off: most likely a typo, so it shouldn't linger
        # in the suggestions either.
        h = _state["history"].get(key(it["name"]))
        if h and h.get("n", 0) <= 1 and now - it.get("at", 0) < 120:
            del _state["history"][key(it["name"])]
    return {"removed": gone}


def op_clear(body):
    which = body.get("which")
    if which not in ("done", "all"):
        raise Refused(400, "clear what?")
    gone = [it for it in _state["items"] if which == "all" or it.get("done")]
    _state["items"] = [it for it in _state["items"] if not (which == "all" or it.get("done"))]
    return {"removed": gone}


def op_restore(body):
    entries = body.get("items")
    if not isinstance(entries, list):
        raise Refused(400, "nothing to restore")
    back = []
    for e in entries[:MAX_ITEMS]:
        if not isinstance(e, dict):
            continue
        iid, name = clean_id(e.get("id")), clean(e.get("name"), NAME_LEN)
        if not iid or not name or find(iid) or len(_state["items"]) >= MAX_ITEMS:
            continue
        it = {"id": iid, "name": name, "qty": clean(e.get("qty"), QTY_LEN), "cat": clean_cat(e.get("cat")),
              "done": bool(e.get("done")), "at": int(e["at"]) if isinstance(e.get("at"), int) else int(time.time())}
        for f, n in (("from", FROM_LEN), ("by", WHO_LEN)):
            v = clean(e.get(f), n)
            if v:
                it[f] = v
        if it["done"]:
            it["doneAt"] = int(e["doneAt"]) if isinstance(e.get("doneAt"), int) else int(time.time())
        _state["items"].append(it)
        back.append(iid)
    return {"restored": back}


# ── recipes ─────────────────────────────────────────────────────────────────
def recipe_from(body, rid):
    name = clean(body.get("name"), NAME_LEN)
    ings = []
    for g in body.get("ingredients") or []:
        if isinstance(g, str):
            g = {"name": g}
        if not isinstance(g, dict):
            continue
        n = clean(g.get("name"), NAME_LEN)
        if n:
            ings.append({"name": n, "qty": clean(g.get("qty"), QTY_LEN), "cat": clean_cat(g.get("cat"))})
    if not name or not ings:
        return None
    return {"id": rid or clean_id(body.get("id")) or new_id(), "name": name,
            "icon": clean(body.get("icon"), ICON_LEN) or "🍽️", "ingredients": ings[:MAX_INGREDIENTS],
            "note": clean(body.get("note"), NOTE_LEN)}


def op_recipe_save(body):
    rid = clean_id(body.get("id"))
    rec = recipe_from(body, rid)
    if not rec:
        raise Refused(400, "a recipe needs a name and at least one ingredient")
    for i, r in enumerate(_state["recipes"]):
        if r["id"] == rec["id"]:
            rec["used"], rec["last"] = r.get("used", 0), r.get("last", 0)
            _state["recipes"][i] = rec
            return {"id": rec["id"]}
    if len(_state["recipes"]) >= MAX_RECIPES:
        raise Refused(409, "that's a lot of recipes (%d) — delete one first" % MAX_RECIPES)
    rec["used"], rec["last"], rec["at"] = 0, 0, int(time.time())
    _state["recipes"].append(rec)
    return {"id": rec["id"]}


def op_recipe_delete(body):
    rid = clean_id(body.get("id"))
    gone = [r for r in _state["recipes"] if r["id"] == rid]
    _state["recipes"] = [r for r in _state["recipes"] if r["id"] != rid]
    return {"removed": gone}


OPS = {
    "items/add": op_add,
    "items/toggle": op_toggle,
    "items/edit": op_edit,
    "items/remove": op_remove,
    "items/clear": op_clear,
    "items/restore": op_restore,
    "recipes/save": op_recipe_save,
    "recipes/delete": op_recipe_delete,
}


# ── HTTP ────────────────────────────────────────────────────────────────────
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _cors(self):
        origin = self.headers.get("Origin")
        if origin and origin in DASH_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self._cors()
        self.end_headers()

        def send(event, payload):
            data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            self.wfile.write(("event: %s\ndata: %s\n\n" % (event, data)).encode())
            self.wfile.flush()

        try:
            with _lock:
                snap, seen = snapshot(), _state["v"]
            send("state", snap)
            while True:
                with _lock:
                    moved = _lock.wait_for(lambda: _state["v"] != seen, timeout=PING_SECONDS)
                    if moved:
                        snap, seen = snapshot(), _state["v"]
                if moved:
                    send("state", snap)
                else:
                    send("ping", {})
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def do_GET(self):
        path = urlsplit(self.path).path.rstrip("/")
        if path == "/events":
            self.events()
        elif path in ("", "/state"):
            with _lock:
                snap = snapshot()
            self._send(200, snap)
        else:
            self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        path = urlsplit(self.path).path.strip("/")
        # Always drain the body: this is a keep-alive server, and an unread body
        # would be parsed as the next request on the connection.
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length > BODY_MAX:
            self.close_connection = True
            self._send(413, {"ok": False, "error": "too big"})
            return
        raw = self.rfile.read(length) if length > 0 else b""
        op = OPS.get(path)
        if not op:
            self._send(404, {"ok": False, "error": "not found"})
            return
        if self.headers.get("X-Dash") != "1":
            self._send(403, {"ok": False, "error": "missing X-Dash header"})
            return
        try:
            body = json.loads(raw.decode("utf-8")) if raw else {}
            if not isinstance(body, dict):
                raise ValueError
        except (ValueError, UnicodeDecodeError):
            self._send(400, {"ok": False, "error": "bad request body"})
            return
        # Decide under the lock, answer outside it: a slow client must never
        # hold up everyone else's changes. All or nothing: a request refused
        # halfway through (a batch that fills the list) or one that cannot be
        # written to disk leaves memory exactly as it was, so memory and the
        # file never disagree.
        global _state
        with _lock:
            before = json.dumps(_state)
            try:
                extra = op(body)
                changed()
                code, out = 200, {"ok": True, "state": snapshot()}
                out.update(extra)
            except Refused as exc:
                _state = json.loads(before)
                code, out = exc.code, {"ok": False, "error": str(exc), "state": snapshot()}
            except OSError as exc:
                print("could not save: %s" % exc, flush=True)
                _state = json.loads(before)
                code, out = 500, {"ok": False, "error": "couldn't save on the server", "state": snapshot()}
        self._send(code, out)

    def do_OPTIONS(self):
        origin = self.headers.get("Origin")
        allowed = bool(origin) and origin in DASH_ORIGINS
        self.send_response(204 if allowed else 403)
        self._cors()
        if allowed:
            self.send_header("Access-Control-Allow-Methods", "GET, POST")
            self.send_header("Access-Control-Allow-Headers", "X-Dash, Content-Type")
            self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    with _lock:
        load()
    print("shopping-list on :%d, state %s" % (PORT, STATE), flush=True)
    Server(("0.0.0.0", PORT), Handler).serve_forever()
