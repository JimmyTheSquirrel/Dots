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
                        quantities add up ("2" + "3" → "5", 600mL + 1L → 1.6L,
                        "" counts as one); one already ticked is put back on
                        the list. Each add that says something is kept in the
                        item's `parts` ({id, from, qty, by}), and two or more
                        make it "doubled up" (`settled` false) — flagged on the
                        dashboards for the shopper to decide. `recipe` (an id)
                        counts a cook.
  POST /items/toggle    {id, done}
  POST /items/edit      {id, name?, qty?, cat?, settled?}   setting qty settles a flag
  POST /items/remove    {ids: [...]}
  POST /items/clear     {which: "done" | "all"}
  POST /items/restore   {items: [...]}   put removed items back (Undo)
  POST /recipes/save    {id?, name, icon?, ingredients: [{name, qty?, cat?, skip?}], note?}
  POST /recipes/delete  {id}
  POST /staples/save    {id?, name, qty?, cat?, icon?}   one per name: saving a
                        name that's already a staple updates that one (and keeps
                        its picture unless the save names one)
  POST /staples/delete  {id}
  POST /groups/save     {id?, name}   a group of usuals; one per name
  POST /groups/delete   {id}          its usuals are left with no group

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
The starter staples likewise, plus once onto a list that predates staples.
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
MAX_STAPLES = 150      # the usuals (stored as "staples"): things you always keep in
MAX_GROUPS = 30        # the groups the usuals are sorted into
MAX_PARTS = 12         # contributions remembered per list item (who asked, how much)
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


# Metric units, as (base unit, how many of it). Written the Australian-label
# way and tight: 300mL, 2L, 500g, 1.5kg. shopping.js's METRIC knows the same
# spellings — keep the two in step.
METRIC = {"g": ("g", 1), "gm": ("g", 1), "gms": ("g", 1), "gram": ("g", 1), "grams": ("g", 1),
          "kg": ("g", 1000), "kgs": ("g", 1000), "kilo": ("g", 1000), "kilos": ("g", 1000),
          "ml": ("mL", 1), "millilitre": ("mL", 1), "millilitres": ("mL", 1),
          "milliliter": ("mL", 1), "milliliters": ("mL", 1),
          "l": ("mL", 1000), "lt": ("mL", 1000), "ltr": ("mL", 1000), "litre": ("mL", 1000),
          "litres": ("mL", 1000), "liter": ("mL", 1000), "liters": ("mL", 1000)}


def _metric(base, amount):
    """An amount in g / mL, written the way a label would: 1000 and up in kg / L."""
    if amount >= 1000:
        return _fmt(amount / 1000) + ("kg" if base == "g" else "L")
    return _fmt(amount) + base


def _word(unit):
    """A unit word folded for comparing: "tins" == "tin", "bunches" == "bunch"."""
    u = unit.strip().lower()
    if u.endswith("ches") or u.endswith("shes") or u.endswith("xes"):
        return u[:-2]
    return u[:-1] if len(u) > 3 and u.endswith("s") and not u.endswith("ss") else u


def merge_qty(a, b):
    """The quantity after adding b to an item that already says a.

    Metric adds up across sizes (600mL + 1L = 1.6L, 750g + 500g = 1.25kg);
    the same word unit adds up ("1 tin" + "2 tins" = "3 tins"); anything else
    is kept side by side ("2 + 1 bunch"), or a is kept if that won't fit."""
    if not a:
        return b
    if not b:
        return a
    ma, mb = QTY_RE.match(a), QTY_RE.match(b)
    if ma and mb:
        ua, ub = (ma.group(2) or "").strip(), (mb.group(2) or "").strip()
        na, nb = _num(ma.group(1)), _num(mb.group(1))
        pa, pb = METRIC.get(ua.lower()), METRIC.get(ub.lower())
        if pa and pb and pa[0] == pb[0]:
            return _metric(pa[0], na * pa[1] + nb * pb[1])[:QTY_LEN]
        if _word(ua) == _word(ub):
            total = na + nb
            if not ua:
                return _fmt(total)
            one = _word(ua)
            many = ua if _word(ua) != ua.lower() else (ub if _word(ub) != ub.lower() else
                                                       one + ("es" if one.endswith(("ch", "sh", "x", "s")) else "s"))
            # "500g"-style tight units stay tight, "3 tins" keeps its space.
            sep = " " if re.match(r"^\s*[\d.,]+\s", a) else ""
            return (_fmt(total) + sep + (one if total == 1 else many))[:QTY_LEN]
    joined = a + " + " + b
    return joined if len(joined) <= QTY_LEN else a


def _unit(q):
    """The unit of a numeric quantity ("" for a plain count), or None when it
    isn't one ("dozen", "2-3")."""
    m = QTY_RE.match(q or "")
    return (m.group(2) or "").strip() if m else None


def add_up(a, b):
    """Two contributions to one item, added. An empty quantity is one of the
    thing, so "" + "" = "2" and "" + "2" = "3"; against a measured amount
    ("" + "300mL") the measure stands — the item is flagged as asked for
    twice either way, and the shopper decides (see op_add)."""
    if not a and _unit(b):
        return b
    if not b and _unit(a):
        return a
    return merge_qty(a or "1", b or "1")


def merge_from(a, b):
    if not b or b in [p.strip() for p in (a or "").split(",")]:
        return a
    joined = (a + ", " + b) if a else b
    return joined if len(joined) <= FROM_LEN else a


# ── state ───────────────────────────────────────────────────────────────────
def empty():
    # sid: changes only when the file is created afresh, so a client holding a
    # snapshot from before can tell a reset from an old message.
    return {"sid": new_id(), "v": 0, "items": [], "recipes": [], "staples": [], "groups": [], "history": {}}


def _seed():
    """SHOP_SEED: {"recipes": [...], "staples": [...]} (or, from before staples
    existed, just the list of recipes)."""
    if not SEED:
        return {}
    try:
        with open(SEED) as fh:
            raw = json.load(fh)
    except (OSError, ValueError):
        return {}
    return {"recipes": raw} if isinstance(raw, list) else raw if isinstance(raw, dict) else {}


def seed_recipes():
    """The starter recipes, cleaned like any other save."""
    out = []
    for r in _seed().get("recipes") or []:
        rec = recipe_from(r, None) if isinstance(r, dict) else None
        if rec:
            out.append(rec)
    return out[:MAX_RECIPES]


def seed_usuals():
    """The starter groups and usuals, cleaned like any other save. A seed
    usual names its group ("Fridge"); here that becomes the group's id."""
    seed = _seed()
    groups, ids = [], {}
    for g in seed.get("groups") or []:
        name = clean(g if isinstance(g, str) else (g or {}).get("name"), GROUP_LEN)
        if name and name.lower() not in ids and len(groups) < MAX_GROUPS:
            ids[name.lower()] = new_id()
            groups.append({"id": ids[name.lower()], "name": name})
    out, seen = [], set()
    for r in seed.get("staples") or []:
        r = r if isinstance(r, dict) else {"name": r}
        st = staple_from(dict(r, group=ids.get(str(r.get("group") or "").lower(), "")), None, groups)
        if st and key(st["name"]) not in seen:
            seen.add(key(st["name"]))
            out.append(st)
    return groups, out[:MAX_STAPLES]


# How the usuals saved before groups existed are sorted into some, once, by
# the aisle each one lives in.
GROUP_BY_AISLE = [
    ("Cupboard", ("pantry", "snacks", "drinks", "other")),
    ("Fridge", ("dairy", "meat", "produce", "bakery", "frozen")),
    ("Cleaning & paper", ("household", "personal", "pets")),
]


def group_by_aisle(staples):
    def which(cat):
        for name, cats in GROUP_BY_AISLE:
            if cat in cats:
                return name
        return "Cupboard"
    by = {}
    for x in staples:
        by.setdefault(which(x.get("cat") or "other"), []).append(x)
    groups = []
    for name, _ in GROUP_BY_AISLE:
        if by.get(name):
            gid = new_id()
            groups.append({"id": gid, "name": name})
            for x in by[name]:
                x["group"] = gid
    return groups


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
        if "staples" not in st:
            # A list from before staples existed gets the starters, once: the
            # key is there from now on, so deleting every one sticks.
            st["groups"], st["staples"] = seed_usuals()
        elif "groups" not in st:
            # …and one from before groups, its usuals sorted into some, once.
            st["groups"] = group_by_aisle(st["staples"])
        else:
            return
    except FileNotFoundError:
        _state = empty()
        _state["recipes"] = seed_recipes()
        _state["groups"], _state["staples"] = seed_usuals()
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
        "staples": sorted(_state["staples"], key=lambda r: r["name"].lower()),
        "groups": _state.get("groups", []),
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


def _parts(it):
    """Who asked for an item and how much: one entry per add that said
    something. An item from before parts existed gets one made from itself."""
    ps = it.get("parts")
    if isinstance(ps, list) and ps:
        return ps
    return [{"id": it["id"], "from": it.get("from", ""), "qty": it.get("qty", ""), "by": it.get("by", "")}]


def _seen(cid):
    """Has an add with this client id already landed — as an item, or merged
    into one as a part? A retried request must not count twice."""
    for it in _state["items"]:
        if it["id"] == cid or any(p.get("id") == cid for p in it.get("parts") or []):
            return True
    return False


def part_from(e):
    if not isinstance(e, dict):
        return None
    return {"id": clean_id(e.get("id")) or new_id(), "from": clean(e.get("from"), FROM_LEN),
            "qty": clean(e.get("qty"), QTY_LEN), "by": clean(e.get("by"), WHO_LEN)}


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
    """Add things — or, for a name already on the list, add TO it.

    Every add that says something (an amount, or the recipe it's for) is kept
    as a part of the item — {from, qty, by} — and the quantity is their sum.
    Two or more parts make the item "doubled up" (`settled` false) and the
    dashboards flag it, so whoever is shopping can decide: 300mL of cream for
    each of two recipes probably means 600mL; sour cream for each of two
    probably means one tub. An add that says nothing more ("milk" again) just
    finds it's already there."""
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
        if cid and _seen(cid):
            continue  # a retried request: this one has already landed
        qty, cat, frm = clean(e.get("qty"), QTY_LEN), clean_cat(e.get("cat")), clean(e.get("from"), FROM_LEN)
        pid = cid or new_id()
        part = {"id": pid, "from": frm, "qty": qty, "by": by}
        k = key(name)
        same = [it for it in _state["items"] if key(it["name"]) == k]
        live = next((it for it in same if not it.get("done")), None)
        if live:
            if qty or frm:
                live["parts"] = (_parts(live) + [part])[-MAX_PARTS:]
                live["qty"] = add_up(live.get("qty", ""), qty)[:QTY_LEN]
                live["settled"] = False
                frm2 = merge_from(live.get("from", ""), frm)
                if frm2:
                    live["from"] = frm2
            merged.append(live["id"])
            # The item keeps its own name and aisle (which may be a correction
            # someone made); the new entry's guess doesn't overwrite them.
            remember(live["name"], live["cat"])
            continue
        if same:
            # Already in the trolley from earlier: needed again, so it goes
            # back on the list with the new quantity rather than as a twin.
            it = same[0]
            it.update(done=False, qty=qty, at=now, parts=[part], settled=False)
            it.pop("doneAt", None)
            if by:
                it["by"] = by
            if frm:
                it["from"] = frm
            else:
                it.pop("from", None)
            merged.append(it["id"])
            remember(it["name"], it["cat"])
            continue
        if len(_state["items"]) >= MAX_ITEMS:
            raise Refused(409, "the list is full (%d items)" % MAX_ITEMS)
        it = {"id": pid, "name": name, "qty": qty, "cat": cat, "done": False, "at": now, "parts": [part]}
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
        # Setting the amount by hand IS the decision a doubled-up flag asks for.
        it["settled"] = True
    if "settled" in body:
        it["settled"] = bool(body.get("settled"))
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
        parts = [p for p in (part_from(x) for x in (e.get("parts") or [])[:MAX_PARTS]) if p] \
            if isinstance(e.get("parts"), list) else []
        if parts:
            it["parts"] = parts
            it["settled"] = bool(e.get("settled"))
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
            ing = {"name": n, "qty": clean(g.get("qty"), QTY_LEN), "cat": clean_cat(g.get("cat"))}
            # "Usually have" (spices, sauces, oil): part of the recipe, left off
            # the list when shopping for it unless ticked that time. Stored only
            # when set, so recipes from before it read exactly as they did.
            if g.get("skip") is True:
                ing["skip"] = True
            ings.append(ing)
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


# ── cupboard staples ────────────────────────────────────────────────────────
# Things you always keep in — toilet paper, cereal, cordial — saved so they're
# one tap onto the list. One per name (key()): saving a name that's already a
# staple updates that one, whatever id it came with.
def staple_from(body, sid, groups=None):
    name = clean(body.get("name"), NAME_LEN)
    if not name:
        return None
    # icon: a picture someone picked; "" means the dashboard guesses one from
    # the name (shopping.js → iconFor). group: a group's id, or "" (none) —
    # including when the group it names has just been deleted.
    gid = clean_id(body.get("group")) or ""
    if gid and not any(g["id"] == gid for g in (groups if groups is not None else _state.get("groups", []))):
        gid = ""
    return {"id": sid or clean_id(body.get("id")) or new_id(), "name": name,
            "qty": clean(body.get("qty"), QTY_LEN), "cat": clean_cat(body.get("cat")),
            "icon": clean(body.get("icon"), ICON_LEN), "group": gid}


def op_staple_save(body):
    st = staple_from(body, None)
    if not st:
        raise Refused(400, "a usual needs a name")
    k = key(st["name"])
    for i, s in enumerate(_state["staples"]):
        if s["id"] == st["id"] or key(s["name"]) == k:
            st["id"] = s["id"]
            # A save that doesn't mention the picture (re-adding "24 pack
            # toilet paper", ★ from a row) keeps the one that was picked.
            if "icon" not in body:
                st["icon"] = s.get("icon", "")
            if "group" not in body:
                st["group"] = s.get("group", "")
            _state["staples"][i] = st
            return {"id": st["id"]}
    if len(_state["staples"]) >= MAX_STAPLES:
        raise Refused(409, "that's a lot of usuals (%d) — remove one first" % MAX_STAPLES)
    _state["staples"].append(st)
    return {"id": st["id"]}


def op_staple_delete(body):
    sid = clean_id(body.get("id"))
    gone = [s for s in _state["staples"] if s["id"] == sid]
    _state["staples"] = [s for s in _state["staples"] if s["id"] != sid]
    return {"removed": gone}


# ── groups (of usuals) ──────────────────────────────────────────────────────
# Made by hand — Cupboard, Fridge, Cleaning, whatever suits — and kept in the
# order they were made. Deleting one leaves its usuals with no group.
GROUP_LEN = 40


def op_group_save(body):
    gid, name = clean_id(body.get("id")), clean(body.get("name"), GROUP_LEN)
    if not name:
        raise Refused(400, "a group needs a name")
    groups = _state.setdefault("groups", [])
    for g in groups:
        if g["id"] == gid:
            g["name"] = name
            return {"id": gid}
    for g in groups:
        if g["name"].lower() == name.lower():
            return {"id": g["id"]}  # one per name, so a retry or a twin lands on it
    if len(groups) >= MAX_GROUPS:
        raise Refused(409, "that's a lot of groups (%d) — remove one first" % MAX_GROUPS)
    g = {"id": gid or new_id(), "name": name}
    groups.append(g)
    return {"id": g["id"]}


def op_group_delete(body):
    gid = clean_id(body.get("id"))
    gone = [g for g in _state.get("groups", []) if g["id"] == gid]
    _state["groups"] = [g for g in _state.get("groups", []) if g["id"] != gid]
    moved = []
    for x in _state["staples"]:
        if gid and x.get("group") == gid:
            x["group"] = ""
            moved.append(x["id"])
    return {"removed": gone, "moved": moved}


OPS = {
    "items/add": op_add,
    "items/toggle": op_toggle,
    "items/edit": op_edit,
    "items/remove": op_remove,
    "items/clear": op_clear,
    "items/restore": op_restore,
    "recipes/save": op_recipe_save,
    "recipes/delete": op_recipe_delete,
    "staples/save": op_staple_save,
    "staples/delete": op_staple_delete,
    "groups/save": op_group_save,
    "groups/delete": op_group_delete,
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
