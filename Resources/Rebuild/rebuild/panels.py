"""The app-aware pieces: the machine cards on the home screen, and what the
preview panel beside each menu shows.

A preview answers "what happens if I press ⏎ here, and to what?": the steps,
the exact command it will run, the machine it's for (online? what's it
running?), and how it went last time (history.py). They're plain functions
of the app's state, drawn fresh each time the highlight moves, so they cost
nothing while you're not looking.
"""
from __future__ import annotations

import glob
import math
import os
import shutil
import time

from rich.console import Group
from rich.table import Table
from rich.text import Text
from textual import events
from textual.containers import Grid
from textual.message import Message
from textual.widget import Widget

from . import help as HELP
from . import history as HIST
from . import hosts as H
from . import probe as P
from .ui import (AQUA, BLUE, BG, DIM, FAINT, FG, GREEN, LINE, PURPLE, RED, YELLOW, bar, grad, mix, sparkline,
                 spinner)

VERB = {"switch": "switched", "boot": "set for next boot", "build": "built", "update": "inputs updated",
        "sync": "synced", "gc": "collected garbage", "check": "checked every host", "clone": "cloned"}


# ── bits ──────────────────────────────────────────────────────────────────────
def dot(state: str, t: float = 0.0) -> Text:
    if state == "online":
        return Text("●", mix(GREEN, "#d5d77a", 0.5 + 0.5 * math.sin(t * 2.4)))   # a slow heartbeat
    if state == "offline":
        return Text("○", RED)
    return Text("◌", DIM)


def run_line(r: HIST.Run | None, none: str = "nothing from here yet") -> Text:
    """✔ switched 2h ago · 3m 12s"""
    if r is None:
        return Text(none, FAINT)
    what = VERB.get(r.kind, r.kind) if r.ok else (r.result or f"{r.kind} failed")
    return Text.assemble(("✔ " if r.ok else "✘ ", f"bold {GREEN if r.ok else RED}"),
                         (what, FG if r.ok else RED), (f" · {P.ago(r.t + r.took)}", DIM),
                         (f" · {P.duration(r.took)}" if r.took >= 1 else "", DIM))


def grid(rows: list[tuple[str, Text | str]], key_width: int = 10) -> Table:
    t = Table.grid(padding=(0, 1))
    t.add_column(width=key_width, no_wrap=True)
    t.add_column(ratio=1)
    for k, v in rows:
        t.add_row(Text(k, DIM), v if isinstance(v, Text) else Text(v, FG))
    return t


def steps(*names: str, accent: str = AQUA) -> Text:
    """① build ─ ② diff ─ ③ activate"""
    t = Text()
    for i, n in enumerate(names):
        if i:
            t.append(" ─ ", FAINT)
        t.append(f"{'①②③④⑤'[i]} ", accent)
        t.append(n, FG)
    return t


def cmd(line: str, accent: str = AQUA) -> Text:
    return Text.assemble(("$ ", FAINT), (line, accent))


def store_line(width: int = 18) -> Text:
    try:
        du = shutil.disk_usage("/nix/store")
    except OSError:
        return Text("?", DIM)
    used = (du.total - du.free) / du.total if du.total else 0     # what's taken, however the fs counts it
    t = bar(used, width)
    if used > 0.85:
        t.stylize(RED if used > 0.93 else YELLOW, 0, round(used * width))
    t.append(f"  {P.human_bytes(du.free)} free", FG)
    t.append(f" of {P.human_bytes(du.total)}", DIM)
    return t


def repo_line(app) -> Text:
    if not app.repo.path:
        return Text.assemble((H.DOTS_FLAKE, YELLOW), ("  · no checkout here", DIM))
    st = app.repo_st
    if not st:
        return Text(f"{spinner()} reading the repo…", DIM)
    return Text.assemble((st.branch[:24], BLUE), "  ",
                         ("✔ clean", GREEN) if not st.dirty else (f"● {st.dirty} changed", YELLOW),
                         (f"  ↑{st.ahead} ↓{st.behind}", DIM))


def usually(host: str) -> Text:
    typ = HIST.typical(host)
    if typ is None:
        return Text("no runs yet", FAINT)
    return Text.assemble((f"~{P.duration(typ)}", FG), "  ", sparkline(HIST.durations(host), 16))


def generations(profile: str) -> int:
    pat = ("/nix/var/nix/profiles/system-*-link" if profile == "system"
           else f"/nix/var/nix/profiles/system-profiles/{profile}-*-link")
    return len(glob.glob(pat))


def peer_rows(app, h: H.Host) -> list[tuple[str, Text | str]]:
    p = app.tailnet.peer(h.name)
    rows: list[tuple[str, Text | str]] = []
    if p.state == "online":
        rows.append(("tailnet", Text.assemble(("● online", GREEN), (f" · {p.path} · {p.ip}", DIM))))
    elif p.state == "offline":
        rows.append(("tailnet", Text.assemble(("○ offline", RED), (f" · {p.seen_text()}", DIM))))
    elif p.state == "missing":
        rows.append(("tailnet", Text("◌ not on the tailnet", DIM)))
    else:
        rows.append(("tailnet", Text("◌ tailscale unavailable", DIM)))
    r = app.probes.get(h.name)
    if r and r.ok:
        rows.append(("running", Text.assemble(f"generation {r.generation}", (" · up ", DIM), P.uptime_text(r.uptime))))
    return rows


# ── the machine cards ─────────────────────────────────────────────────────────
class MachineCard(Widget):
    """One machine: how it is right now, what it runs, how its last deploy
    went. Its border breathes while it's online and flashes when its state
    changes; click it to go to it."""

    DEFAULT_CSS = """
    MachineCard { height: 6; border: round #504945; padding: 0 1; }
    MachineCard.compact { height: 3; }
    MachineCard:hover { background: #282828; }
    """

    class Picked(Message):
        def __init__(self, name: str) -> None:
            super().__init__()
            self.name = name

    def __init__(self, host: H.Host, **kw):
        super().__init__(**kw)
        self.host = host
        self.state: str | None = None
        self.flash_at = 0.0

    @property
    def here(self) -> bool:
        return H.THIS is not None and self.host.name == H.THIS.name

    def on_mount(self) -> None:
        self.border_title = f" {self.host.icon}  {self.host.name} "
        self.styles.border_title_style = "bold"
        self.ping_at = H.HOSTS.index(self.host) * 1.7         # the pings don't all go at once
        self.set_interval(1 / 10, self._tick)
        self._tick()

    def _now_state(self) -> str:
        return "here" if self.here else self.app.tailnet.peer(self.host.name).state

    def _tick(self) -> None:
        st = self._now_state()
        if st != self.state:
            if self.state is not None and self.state != "unknown":
                self.flash_at = time.monotonic()
            self.state = st
        # The border only changes on a state change (a flash that fades) —
        # restyling a border relayouts the screen, so it never breathes; the
        # heartbeat is the dot inside, which is a cheap redraw.
        base = {"here": mix(LINE, AQUA, 0.75), "online": mix(LINE, GREEN, 0.5)}.get(st, LINE)
        fl = max(0.0, 1 - (time.monotonic() - self.flash_at) / 0.9)
        colour = mix(base, "#ffffff", round(fl * 8) / 10) if fl else base
        if colour != getattr(self, "_border", None):
            self._border = colour
            self.styles.border = ("round", colour)
            self.styles.border_title_color = {"here": AQUA, "online": FG}.get(st, DIM)
        self.n = getattr(self, "n", -1) + 1
        if self.n % 50 == 0:                      # the history sparkline: every 5s is plenty
            hist = HIST.durations(self.host.name, 10)
            sub = sparkline(hist).plain if len(hist) >= 2 else ""
            if sub != self.border_subtitle:
                self.border_subtitle = sub
                self.styles.border_subtitle_color = DIM
        # An online machine pings: its dot swells and settles every few
        # seconds — a handful of frames, then nothing until the next one
        # (and none while you're in another window).
        pinging = st == "online" and self.app.app_focus and self.ping() is not None
        if fl or pinging or getattr(self, "_was_pinging", False):
            self.refresh()
        self._was_pinging = pinging

    PING_EVERY, PING_FOR = 6.0, 0.9

    def ping(self) -> float | None:
        """Where in a ping we are (0–1), or None between pings."""
        ph = (time.monotonic() + self.ping_at) % self.PING_EVERY
        return ph / self.PING_FOR if ph < self.PING_FOR else None

    def render(self) -> Text:
        app, h, t = self.app, self.host, time.monotonic()
        w = self.size.width
        lines: list[Text] = []
        if self.here:
            gen, when = H.generation(h.profile)
            lines.append(Text.assemble(("◆ ", AQUA), ("this machine", AQUA)))
            lines.append(Text(h.role, DIM))
            lines.append(Text.assemble(("gen ", DIM), (str(gen or "?"), FG), (f" · built {P.ago(when)}" if when else "", DIM)))
        else:
            p = app.tailnet.peer(h.name)
            stick = h.mode == "stick"
            if p.state == "online":
                k = self.ping()
                pip = Text("●", GREEN) if k is None else Text("◉●"[k > 0.55], mix("#ffffff", GREEN, k))
                lines.append(Text.assemble(pip, (" booted" if stick else " online", GREEN), (f" · {p.path.split()[0]}", DIM)))
            elif p.state == "offline":
                lines.append(Text.assemble(("○ ", RED), ("not booted" if stick else "offline", RED),
                                           (f" · {P.ago(p.seen)}" if p.seen else "", DIM)))
            elif p.state == "missing":
                lines.append(Text("◌ not on the tailnet", DIM))
            else:
                lines.append(Text("◌ tailscale unavailable", DIM))
            lines.append(Text(h.role, DIM))
            r = app.probes.get(h.name)
            if r and r.ok:
                lines.append(Text.assemble(("gen ", DIM), (str(r.generation), FG), (" · up ", DIM), (P.uptime_text(r.uptime), FG)))
            elif p.state == "online":
                lines.append(Text(p.ip, FAINT))
            else:
                lines.append(Text(""))
        last = HIST.last(h.name, ("switch", "boot", "build"))
        lines.append(run_line(last, "the USB stick" if h.mode == "stick" and not last else "nothing from here yet"))
        if self.has_class("compact"):           # a short terminal: just how it is right now
            lines = lines[:1]
        out = Text()
        for i, l in enumerate(lines):
            l.truncate(w, overflow="ellipsis")
            out.append_text(l)
            if i < len(lines) - 1:
                out.append("\n")
        return out

    def on_click(self, event: events.Click) -> None:
        self.post_message(self.Picked(self.host.name))


class MachineStrip(Grid):
    """The cards side by side — four across when there's room, else two; on a
    short terminal they shrink to one line each so the menu still fits."""

    DEFAULT_CSS = """
    MachineStrip { height: auto; grid-size: 4; grid-gutter: 0 1; margin: 1 2 0 2; grid-rows: 6; }
    """

    def compose(self):
        for h in H.HOSTS:
            yield MachineCard(h)

    def fit(self, width: int, height: int, other_rows: int) -> None:
        """WIDTH × HEIGHT is the screen; OTHER_ROWS what everything else on it needs."""
        inner = width - 4
        cols = 4 if inner >= 4 * 30 else 2 if inner >= 2 * 28 else 1
        rows = -(-len(H.HOSTS) // cols)
        compact = height < other_rows + 1 + rows * 6
        if self.styles.grid_size_columns != cols:
            self.styles.grid_size_columns = cols
        if compact != getattr(self, "compact", None):
            self.compact = compact
            self.styles.grid_rows = "3" if compact else "6"
            for card in self.query(MachineCard):
                card.set_class(compact, "compact")


# ── previews: the home screen ─────────────────────────────────────────────────
def pv_this(app) -> Group:
    h = H.THIS
    gen, when = H.generation(h.profile)
    parts: list = [
        Text.assemble(("◆ ", AQUA), (h.name, f"bold {FG}"), (f"  {h.role}", DIM)),
        Text(""),
        grid([("generation", Text.assemble(str(gen or "?"), (f" · built {P.ago(when)}" if when else "", DIM))),
              ("profile", Text.assemble(h.profile, (" · GRUB › System Select" if h.profile != "system" else "", DIM))),
              ("last", run_line(HIST.last(h.name, ("switch", "boot", "build")))),
              ("usually", usually(h.name)),
              ("repo", repo_line(app))]),
        Text(""),
        steps("build", "changes", "activate"),
    ]
    return Group(*parts)


def pv_any_host(app) -> Group:
    return Group(Text("Build any machine's config here and see what would change.", FG), Text(""),
                 Text.assemble(("! ", YELLOW), ("this machine isn't one of the four", DIM)))


def pv_remotes(app) -> Group:
    parts: list = [Text("Build here, copy over the tailnet, activate there.", DIM), Text("")]
    t = Table.grid(padding=(0, 1))
    t.add_column(no_wrap=True)
    t.add_column(no_wrap=True)
    t.add_column(ratio=1)
    for h in H.HOSTS:
        if (H.THIS and h.name == H.THIS.name) or h.mode == "stick":
            continue
        p = app.tailnet.peer(h.name)
        t.add_row(dot(p.state, time.monotonic()), Text(h.name, f"bold {FG}"),
                  run_line(HIST.last(h.name, ("switch", "boot", "build"))))
    parts.append(t)
    return Group(*parts)


def pv_utils(app) -> Group:
    rows: list[tuple[str, Text | str]] = [("repo", repo_line(app))]
    if app.repo.path:
        rows.append(("inputs", Text.assemble("locked ", (P.ago(H.lock_age(app.repo)), FG))))
    rows.append(("store", store_line()))
    rows.append(("last gc", run_line(HIST.last("", ("gc",)), "never from here")))
    rows.append(("last update", run_line(HIST.last("", ("update",)), "never from here")))
    return Group(grid(rows, 11))


def pv_apollo(app) -> Group:
    return Group(Text("The deployer USB: boot a machine from it, then install over the tailnet.", DIM), Text(""),
                 grid(apollo_rows(app)))


def apollo_rows(app) -> list[tuple[str, Text]]:
    p = app.tailnet.peer("Apollo")
    stick = {"online": Text.assemble(("● booted", GREEN), (f" · {p.path} · {p.ip}", DIM)),
             "offline": Text.assemble(("○ not booted", RED), (f" · {p.seen_text()}", DIM))}.get(
                 p.state, Text("◌ never seen on the tailnet", DIM))
    if app.mount_point:
        usb = Text.assemble(("✔ mounted", GREEN), (f" · {app.mount_point}", DIM))
    elif os.path.exists("/dev/disk/by-label/Apollo"):
        usb = Text.assemble(("! plugged in, not mounted", YELLOW))
    else:
        usb = Text("– not plugged in", DIM)
    return [("stick", stick), ("usb", usb)]


def pv_help_topics() -> Group:
    t = Table.grid(padding=(0, 2))
    t.add_column(no_wrap=True)
    t.add_column(ratio=1)
    for k, (title, accent, icon, _) in HELP.PAGES.items():
        t.add_row(Text(f"{icon}  {title}", accent), Text(""))
    return Group(Text("Every menu has its own page — ? opens it.", DIM), Text(""), t)


TIPS = [
    ("ctrl+p", "or / jumps to anything: type \"sw asg\" and ⏎ to switch Asgard"),
    ("click", "a machine card to go straight to it"),
    ("1 – 9", "pick a row without moving to it"),
    ("r", "refreshes the machines now instead of in 30s"),
    ("--classic", "system-rebuild --classic gives the old inline menus"),
]


def pv_tip() -> Group:
    k, what = TIPS[int(time.time() // 20) % len(TIPS)]
    return Group(Text.assemble(("tip  ", YELLOW), (k, f"bold {FG}"), ("  ", ""), (what, DIM)))


# ── previews: rebuilding ──────────────────────────────────────────────────────
def pv_action(app, h: H.Host, action: str, local: bool) -> Group:
    """Switch / Boot / Build: the steps, the command, the target."""
    accent = AQUA if local else BLUE
    flake = app.repo.flake
    pflag = f" -p {h.profile}" if h.profile not in ("system", "") else ""
    what = {"switch": "activate now — services restart, no reboot",
            "boot": "make it what the next boot starts" + (f" (GRUB › {h.name})" if pflag and local else ""),
            "build": "activate nothing" + (" — ./result points at it" if app.repo.path and local else "")}[action]
    reach = [] if local or action == "build" else ["reach"]
    names = reach + ["build", "changes"] + ([] if action == "build" else ["activate"])
    parts: list = [steps(*names, accent=accent), Text(""), Text(what, FG), Text("")]
    rows: list[tuple[str, Text | str]] = []
    if not local:
        rows += peer_rows(app, h)
    rows.append(("last", run_line(HIST.last(h.name, ("switch", "boot", "build")))))
    rows.append(("usually", usually(h.name)))
    parts += [grid(rows), Text("")]
    parts.append(cmd(f"nix build {flake}#…{h.key}…toplevel", accent))
    if action != "build":
        if local:
            parts.append(cmd(f"sudo nixos-rebuild {action}{pflag} --store-path …", accent))
        else:
            parts.append(cmd(f"nixos-rebuild {action}{pflag} --store-path … --target-host {h.target}", accent))
    return Group(*parts)


def pv_other_hosts(app) -> Group:
    t = Table.grid(padding=(0, 1))
    t.add_column(no_wrap=True)
    t.add_column(ratio=1)
    for h in H.HOSTS:
        if H.THIS and h.name == H.THIS.name:
            continue
        t.add_row(Text(f"{h.icon}  {h.name}", f"bold {FG}"), Text(h.role, DIM))
    return Group(Text("Build another machine's config here and diff it against what it runs. Nothing is "
                      "deployed.", FG), Text(""), t)


def pv_host(app, h: H.Host) -> Group:
    """A remote machine, for the Remote menu."""
    rows = peer_rows(app, h)
    rows.append(("ssh", Text(h.target, FG)))
    rows.append(("last", run_line(HIST.last(h.name, ("switch", "boot", "build")))))
    rows.append(("usually", usually(h.name)))
    return Group(Text.assemble((h.name, f"bold {FG}"), (f"  {h.role}", DIM)), Text(""), grid(rows))


def pv_ssh(app, h: H.Host) -> Group:
    return Group(Text(f"A shell on {h.name}. The app steps aside while it's open and comes back when you exit.", FG),
                 Text(""), cmd(f"ssh -t {h.target}", BLUE))


# ── previews: utilities ───────────────────────────────────────────────────────
def pv_sync(app) -> Group:
    st = app.repo_st
    parts: list = [steps("commit", "pull --rebase", "push", accent=YELLOW), Text("")]
    if not st:
        return Group(*parts, Text("reading the repo…", DIM))
    parts.append(grid([("branch", Text(st.branch, BLUE)), ("ahead", str(st.ahead)), ("behind", str(st.behind))]))
    if st.dirty:
        parts += [Text(""), Text(f"{st.dirty} changed — you'll be asked for a commit message", YELLOW)]
        for f in st.files[:10]:
            parts.append(Text(f"  {f}", DIM))
        if st.dirty > 10:
            parts.append(Text(f"  … and {st.dirty - 10} more", FAINT))
    else:
        parts += [Text(""), Text("nothing to commit — pull and push only", DIM)]
    return Group(*parts)


def pv_update(app) -> Group:
    lock = P.lock_table(app.repo.path / "flake.lock") if app.repo.path else {}
    parts: list = [steps("fetch", "what moved", "rebuild?", accent=YELLOW), Text("")]
    t = Table.grid(padding=(0, 2))
    t.add_column(no_wrap=True)
    t.add_column(no_wrap=True)
    t.add_column(no_wrap=True)
    now = time.time()
    for name, (rev, mod) in sorted(lock.items(), key=lambda kv: kv[1][1])[:12]:
        age = (now - mod) / 86400 if mod else 0
        t.add_row(Text(name, FG), Text(rev, FAINT),
                  Text(P.ago(mod), RED if age > 60 else YELLOW if age > 21 else DIM))
    parts.append(Text("oldest first", DIM))
    parts.append(t)
    parts += [Text(""), run_line(HIST.last("", ("update",)), "never updated from here")]
    return Group(*parts)


def pv_gc(app) -> Group:
    prof = H.THIS.profile if H.THIS else "system"
    n = generations(prof)
    rows: list[tuple[str, Text | str]] = [("store", store_line()),
                                         ("generations", Text.assemble(str(n), (" kept — all but the current go", DIM))),
                                         ("last", run_line(HIST.last("", ("gc",)), "never from here"))]
    return Group(Text.assemble(("! ", RED), ("you can't roll back past the current generation afterwards", FG)),
                 Text(""), grid(rows, 11), Text(""), cmd("nix-gc", YELLOW))


def pv_check(app) -> Group:
    t = Table.grid(padding=(0, 2))
    t.add_column(no_wrap=True)
    t.add_column(no_wrap=True)
    for h in H.HOSTS:
        t.add_row(Text(f"{h.icon}  {h.name}", FG), Text(h.key, DIM))
    return Group(Text("Evaluate every host at once — catches a typo or a bad option on a machine you're not "
                      "building. Builds nothing.", FG), Text(""), t, Text(""),
                 run_line(HIST.last("", ("check",)), "never from here"))


def pv_history(app) -> Group:
    runs = HIST.recent(6)
    parts: list = []
    for h in H.HOSTS:
        d = HIST.durations(h.name, 20)
        if len(d) >= 2:
            parts.append(Text.assemble((f"{h.name:<9}", FG), sparkline(d), (f"  ~{P.duration(HIST.typical(h.name) or 0)}", DIM)))
    if parts:
        parts.append(Text(""))
    for r in runs:
        parts.append(Text.assemble((f"{r.host or '—':<9}", f"bold {FG}"), run_line(r)))
    if not runs:
        parts.append(Text("nothing yet — every job the app runs lands here", FAINT))
    return Group(*parts)


def pv_clone(app) -> Group:
    return Group(Text("Clone the repo to ~/Dots so Git sync and Update inputs have something to work on. Rebuilds "
                      "use it from then on.", FG), Text(""), cmd(f"git clone {H.DOTS_URL} ~/Dots", YELLOW))


# ── previews: apollo + help ───────────────────────────────────────────────────
APOLLO_TEXT = {
    "deploy": ("Install a machine from scratch: it boots from the stick, joins the tailnet, and nixos-anywhere "
               "partitions and installs over SSH. Dry run and a VM test come first.", "apollo-deploy <host>"),
    "ssh": ("A shell on the booted stick, wherever it is on the tailnet.", "apollo-connect"),
    "iso": ("Build the Apollo image and copy it onto the stick (Ventoy).", "apollo-iso"),
    "key": ("Write a fresh tailnet auth key onto the stick so it joins by itself when it boots.", "apollo-key"),
}


def pv_apollo_item(app, key: str) -> Group:
    text, c = APOLLO_TEXT[key]
    return Group(Text(text, FG), Text(""), grid(apollo_rows(app)), Text(""), cmd(c, PURPLE))


def pv_help_page(key: str) -> Group:
    title, accent, icon, blocks = HELP.PAGES[key]
    parts: list = []
    for b in blocks:
        if b[0] == "head":
            parts.append(Text.assemble(("◆ ", accent), (b[1], f"bold {accent}")))
        elif b[0] in ("item", "key"):
            parts.append(Text.assemble((f"  {b[1]}", FG)))
        if len(parts) >= 14:
            break
    return Group(*parts)
