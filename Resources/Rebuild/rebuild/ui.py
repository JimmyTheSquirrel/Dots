"""The look: palette, gradient, and the widgets every screen is made of.

Gruvbox brights, the same family kitty uses, and the signature gradient —
aqua → blue → purple, the logo's colours — exactly as lib/ui.sh draws it, so
the app and the command-line half look like one thing.

Everything that moves moves on a timer that only runs while there's something
to animate (the logo's intro and its shine every few seconds, a spinner while
a job runs, confetti for a second or two), so an idle menu costs next to
nothing. The app-aware pieces — machine cards, the previews — are panels.py.
"""
from __future__ import annotations

import math
import random
import time
from dataclasses import dataclass
from typing import Callable

from rich.console import RenderableType
from rich.text import Text
from textual import events
from textual.containers import Horizontal, Vertical
from textual.message import Message
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widget import Widget
from textual.widgets import Input, Static

AQUA, BLUE, PURPLE, YELLOW = "#8ec07c", "#83a598", "#d3869b", "#fabd2f"
RED, GREEN, FG, DIM, LINE, BG = "#fb4934", "#b8bb26", "#ebdbb2", "#928374", "#504945", "#1d2021"
ORANGE = "#fe8019"
HL = "#3c3836"          # the highlighted row
SURFACE = "#282828"     # pop-ups
FAINT = "#665c54"
SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

I_NIX, I_BACK, I_QUIT = "", "", ""
I_KEY, I_WARN, I_CLOCK, I_SEARCH = "", "", "", ""
CAP_L, CAP_R = "", ""


# ── colour ────────────────────────────────────────────────────────────────────
def _rgb(c: str) -> tuple[int, int, int]:
    return int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)


def _hex(v) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(x))) for x in v)


def mix(a: str, b: str, t: float) -> str:
    A, B = _rgb(a), _rgb(b)
    t = max(0.0, min(1.0, t))
    return _hex([A[i] + (B[i] - A[i]) * t for i in range(3)])


def grad(t: float) -> str:
    """The logo gradient at t ∈ [0, 1]: aqua → blue → purple (lib/ui.sh ui_grad)."""
    t = max(0.0, min(1.0, t)) * 1000
    if t < 500:
        return _hex((142 - 11 * t / 500, 192 - 27 * t / 500, 124 + 28 * t / 500))
    t -= 500
    return _hex((131 + 80 * t / 500, 165 - 31 * t / 500, 152 + 3 * t / 500))


def ease_out(p: float) -> float:
    p = max(0.0, min(1.0, p))
    return 1 - (1 - p) ** 3


def gradient_text(s: str, bold: bool = False, shine: float | None = None) -> Text:
    """S coloured along the gradient; SHINE (0–1, or None) brightens a band."""
    out = Text()
    n = max(1, len(s) - 1)
    for i, ch in enumerate(s):
        c = grad(i / n)
        if shine is not None:
            d = abs(i / n - shine)
            if d < 0.12:
                c = mix(c, "#ffffff", 0.55 * (1 - d / 0.12))
        out.append(ch, style=f"{'bold ' if bold else ''}{c}")
    return out


def bar(frac: float, width: int, glint: float | None = None, empty: str = LINE) -> Text:
    """A gradient progress bar ━━━━━──── WIDTH cells long; GLINT (0–1) runs a
    bright spot along the filled part."""
    width = max(1, width)
    filled = frac * width
    t = Text()
    for k in range(width):
        if k < int(filled):
            c = grad(k / max(1, width - 1))
            if glint is not None:
                d = abs(k / max(1, filled) - glint)
                if d < 0.08:
                    c = mix(c, "#ffffff", 0.6 * (1 - d / 0.08))
            t.append("━", c)
        elif k == int(filled) and filled % 1 > 0.5:
            t.append("╸", grad(k / max(1, width - 1)))
        else:
            t.append("─", empty)
    return t


SPARK = "▁▂▃▄▅▆▇█"


def sparkline(values: list[float], width: int | None = None) -> Text:
    """▁▃▅▂▇ along the gradient: oldest on the left."""
    if not values:
        return Text("")
    vals = values[-width:] if width else values
    lo, hi = min(vals), max(vals)
    t = Text()
    for i, v in enumerate(vals):
        k = 0 if hi == lo else round((v - lo) / (hi - lo) * (len(SPARK) - 1))
        t.append(SPARK[k], grad(i / max(1, len(vals) - 1)))
    return t


def slide(widget: Widget, start: tuple[int, int], duration: float = 0.22, delay: float = 0.0) -> None:
    """Ease WIDGET from START (cells) back to where it belongs. (Textual can
    fade opacity itself, but won't tween a CSS offset — so this steps it.)"""
    widget.styles.offset = start

    def go() -> None:
        t0 = time.monotonic()

        def step() -> None:
            p = min(1.0, (time.monotonic() - t0) / duration)
            e = ease_out(p)
            widget.styles.offset = (round(start[0] * (1 - e)), round(start[1] * (1 - e)))
            if p >= 1:
                timer.stop()

        timer = widget.set_interval(1 / 60, step)

    if delay:
        widget.set_timer(delay, go)
    else:
        go()


def fade_in(widget: Widget, duration: float = 0.25, delay: float = 0.0, start: float = 0.0) -> None:
    widget.styles.opacity = start
    widget.styles.animate("opacity", 1.0, duration=duration, delay=delay)


def spinner(t: float | None = None) -> str:
    return SPIN[int((time.monotonic() if t is None else t) * 12) % len(SPIN)]


def pill(label: str, fg: str = FG, bg: str = LINE) -> Text:
    return Text.assemble((CAP_L, bg), (label, f"{fg} on {bg}"), (CAP_R, bg))


def clock(s: float) -> str:
    s = int(s)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"


# ── the logo ──────────────────────────────────────────────────────────────────
LOGO_SMALL = [
    "█▀▀▄ ▄▀▀▄ ▀▀█▀▀ ▄▀▀▀",
    "█  █ █  █   █    ▀▀▄",
    "█▄▄▀ ▀▄▄▀   █   ▄▄▄▀",
]
LOGO_BIG = [                              # figlet "ANSI Shadow"
    "██████╗  ██████╗ ████████╗███████╗",
    "██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝",
    "██║  ██║██║   ██║   ██║   ███████╗",
    "██║  ██║██║   ██║   ██║   ╚════██║",
    "██████╔╝╚██████╔╝   ██║   ███████║",
    "╚═════╝  ╚═════╝    ╚═╝   ╚══════╝",
]


def logo_rows(rows: list[str], reveal: float = 1.0, shine: float | None = None) -> list[Text]:
    """The logo along the gradient. Solid blocks take the colour; the box
    lines (the ANSI-shadow 'depth') take a darker shade of it. REVEAL (0–1)
    draws it in from the left with a bright edge; SHINE sweeps a diagonal band."""
    width = max(len(r) for r in rows)
    out = []
    for y, row in enumerate(rows):
        t = Text()
        for x, ch in enumerate(row):
            u = x / max(1, width - 1)
            if ch == " ":
                t.append(" ")
                continue
            edge = reveal * (width + 6) - (x + y)          # cells left of the edge are in
            if edge < 0:
                t.append(" ")
                continue
            base = grad(u)
            c = base if ch in "█▀▄" else mix(base, BG, 0.55)
            if edge < 4 and reveal < 1:
                c = mix(c, "#ffffff", 0.75 * (1 - edge / 4))
            if shine is not None:
                d = abs((x + y * 2) / (width + 2 * len(rows)) - shine)
                if d < 0.07:
                    c = mix(c, "#ffffff", 0.5 * (1 - d / 0.07))
            t.append(ch, c)
        out.append(t)
    return out


class Header(Widget):
    """The home screen's top: DOTS along the gradient — drawn in from the left
    the first time, a shine sweeping across it every few seconds — with up to
    six lines beside it and the time in the corner. Narrow terminals get the
    three-line logo and the first three lines."""

    DEFAULT_CSS = "Header { height: auto; padding: 1 2 0 3; }"
    lines: reactive[tuple] = reactive(tuple)
    played = False                 # the intro plays once per app, not per visit
    SHINE_EVERY = 10.0

    def on_mount(self) -> None:
        self.t0 = time.monotonic()
        self.intro = not Header.played
        Header.played = True
        self._minute = ""
        self.set_interval(1 / 15, self._tick)

    BIG_FROM = 96                  # columns: below this, the small logo

    @property
    def big(self) -> bool:
        return self.size.width >= self.BIG_FROM

    def get_content_height(self, container, viewport, width) -> int:
        return len(LOGO_BIG) if width >= self.BIG_FROM else len(LOGO_SMALL)

    def _phase(self) -> tuple[float, float | None]:
        age = time.monotonic() - self.t0
        reveal = min(1.0, age / 0.9) if self.intro else 1.0
        cycle = (age - (1.0 if self.intro else 0.0)) % self.SHINE_EVERY
        shine = (cycle / 1.3) * 1.3 - 0.15 if 0 <= cycle < 1.4 and age > (1.0 if self.intro else 0.4) else None
        return reveal, shine

    def _tick(self) -> None:
        reveal, shine = self._phase()
        if reveal >= 1 and not self.app.app_focus:       # in another window: just keep the clock right
            shine = None
        minute = time.strftime("%H:%M")
        if reveal < 1 or shine is not None or getattr(self, "_was", False) or minute != self._minute:
            self._was = reveal < 1 or shine is not None
            self._minute = minute
            self.refresh()

    def render(self) -> Text:
        reveal, shine = self._phase()
        rows = LOGO_BIG if self.big else LOGO_SMALL
        art = logo_rows(rows, ease_out(reveal), shine)
        width = self.size.width
        out = Text()
        info = self.lines
        for y, a in enumerate(art):
            line = Text.assemble(a, "    ")
            if y < len(info):
                txt = info[y].copy()
                if reveal < 1:                                    # the lines arrive just after the logo
                    txt.stylize(f"{mix(BG, FG, max(0.0, reveal * 2 - 1))}")
                line.append_text(txt)
            if y == 0:
                stamp = Text.assemble((f"{I_CLOCK} ", FAINT), (time.strftime("%H:%M"), DIM))
                pad = width - line.cell_len - stamp.cell_len
                if pad >= 2:
                    line.append(" " * pad)
                    line.append_text(stamp)
            line.truncate(width)
            out.append_text(line)
            if y < len(art) - 1:
                out.append("\n")
        return out


class Crumbs(Widget):
    """A section's top line:  DOTS › Remote › Asgard — and the host on the right."""

    DEFAULT_CSS = "Crumbs { height: 2; padding: 1 2 0 2; }"

    def __init__(self, crumbs: list[str], accent: str, right: str = "", **kw):
        super().__init__(**kw)
        self.crumbs, self.accent, self.right = crumbs, accent, right

    def render(self) -> Text:
        t = Text.assemble((f"{I_NIX}  ", BLUE), gradient_text("D O T S", bold=True))
        for i, c in enumerate(self.crumbs):
            t.append("  ›  ", DIM)
            t.append(c, f"bold {self.accent if i == len(self.crumbs) - 1 else FG}")
        if self.right:
            pad = max(2, self.size.width - t.cell_len - len(self.right))
            t.append(" " * pad)
            t.append(self.right, PURPLE)
        return t


class Hints(Widget):
    """The key hints along the bottom."""

    DEFAULT_CSS = "Hints { height: 1; dock: bottom; padding: 0 2; }"
    keys: reactive[tuple] = reactive(())

    def render(self) -> Text:
        for gap in ("   ", " "):
            t = Text()
            for k, what in self.keys:
                t.append_text(pill(f" {k} "))
                t.append(f" {what}{gap}", DIM)
            if t.cell_len <= self.size.width:
                return t
        t = Text()                               # still too wide: just the keys
        for k, _ in self.keys:
            t.append_text(pill(f" {k} "))
            t.append(" ")
        return t


# ── the menu ──────────────────────────────────────────────────────────────────
@dataclass
class Item:
    key: str
    icon: str
    label: str
    desc: str = ""
    meta: Text | str = ""
    accent: str = FG
    gap_before: bool = False     # a blank line above it
    numbered: bool = True
    preview: Callable[[], RenderableType] | None = None   # what the panel beside the menu shows
    title: str = ""              # the panel's title (else the label)


class Menu(Widget, can_focus=True):
    """Rows you move through with ↑↓/jk, pick with ⏎/→/l or 1–9 or a click.
    The highlight wipes in from the left as the old one fades."""

    DEFAULT_CSS = "Menu { height: auto; padding: 0 1; }"
    BLEND = 0.18

    class Picked(Message):
        def __init__(self, key: str) -> None:
            super().__init__()
            self.key = key

    class Highlighted(Message):
        def __init__(self, item: "Item | None", moved: bool) -> None:
            super().__init__()
            self.item, self.moved = item, moved

    def __init__(self, items: list[Item] | None = None, compact: bool = False, rows: int | None = None, **kw):
        super().__init__(**kw)
        self.items: list[Item] = items or []
        self.index = 0
        self.prev = -1
        self.t_moved = 0.0
        self.anim = None
        self.compact = compact      # no description column (a preview panel says it instead)
        self.rows = rows            # show at most this many, scrolling with the highlight (no gaps then)
        self.top = 0

    # contents ────────────────────────────────────────────────────────────────
    def set_items(self, items: list[Item], keep: str | None = None) -> None:
        cur = keep or (self.items[self.index].key if self.items else None)
        self.items = items
        keys = [i.key for i in items]
        self.index = keys.index(cur) if cur in keys else min(self.index, max(0, len(items) - 1))
        self.prev = -1
        self.refresh(layout=True)
        self.post_message(self.Highlighted(self.items[self.index] if self.items else None, False))

    def get_content_height(self, container, viewport, width) -> int:
        if self.rows:
            return max(1, min(self.rows, len(self.items)))
        return sum(2 if i.gap_before else 1 for i in self.items)

    def _window(self) -> range:
        """The rows on screen: all of them, or a window that keeps the highlight in view."""
        if not self.rows or len(self.items) <= self.rows:
            self.top = 0
            return range(len(self.items))
        self.top = max(0, min(self.top, len(self.items) - self.rows))
        if self.index < self.top:
            self.top = self.index
        elif self.index >= self.top + self.rows:
            self.top = self.index - self.rows + 1
        return range(self.top, self.top + self.rows)

    @property
    def current(self) -> str | None:
        return self.items[self.index].key if self.items else None

    # moving ──────────────────────────────────────────────────────────────────
    def move(self, to: int) -> None:
        to = max(0, min(len(self.items) - 1, to))
        if to == self.index:
            return
        self.prev, self.index, self.t_moved = self.index, to, time.monotonic()
        if self.anim is None:
            self.anim = self.set_interval(1 / 60, self._fade)
        self.refresh()
        self.post_message(self.Highlighted(self.items[self.index], True))

    def _fade(self) -> None:
        self.refresh()
        if time.monotonic() - self.t_moved > self.BLEND and self.anim:
            self.anim.stop()
            self.anim = None
            self.prev = -1

    def pick(self, i: int | None = None) -> None:
        if not self.items:
            return
        if i is not None:
            self.move(i)
        self.post_message(self.Picked(self.items[self.index].key))

    def on_key(self, event: events.Key) -> None:
        k = event.key
        if k in ("up", "k"):
            self.move(self.index - 1)
        elif k in ("down", "j"):
            self.move(self.index + 1)
        elif k == "home":
            self.move(0)
        elif k == "end":
            self.move(len(self.items) - 1)
        elif k in ("enter", "right", "l"):
            self.pick()
        elif k.isdigit() and k != "0":
            nums = [n for n, it in enumerate(self.items) if it.numbered]
            if int(k) - 1 < len(nums):
                self.pick(nums[int(k) - 1])
        else:
            return
        event.stop()

    def _row_at(self, y: int) -> int | None:
        if self.rows:
            n = self.top + y
            return n if 0 <= y < self.rows and n < len(self.items) else None
        top = 0
        for n, it in enumerate(self.items):
            top += 2 if it.gap_before else 1
            if y < top:
                return n
        return None

    def on_click(self, event: events.Click) -> None:
        n = self._row_at(event.y)
        if n is None:
            return
        if n == self.index:
            self.pick()
        else:
            self.move(n)

    def on_mouse_move(self, event: events.MouseMove) -> None:
        n = self._row_at(event.y)
        if n is not None and n != self.index:
            self.move(n)

    # drawing ─────────────────────────────────────────────────────────────────
    def render(self) -> Text:
        width = self.size.width
        p = min(1.0, (time.monotonic() - self.t_moved) / self.BLEND) if self.prev >= 0 else 1.0
        ease = ease_out(p)
        out = Text()
        num = 0
        lw = max([len(i.label) for i in self.items] + [8]) + 2
        shown = self._window()
        for n, it in enumerate(self.items):
            if it.numbered:
                num += 1
            if n not in shown:
                continue
            if it.gap_before and not self.rows:
                out.append("\n")
            sel, was = n == self.index, n == self.prev
            hl = ease if sel else (1 - ease if was else 0.0)
            row = Text()
            row.append("▌" if hl > 0.01 else " ", mix(BG, it.accent, hl) if hl > 0.01 else "")
            label = f"{num}" if it.numbered and num <= 9 else " "
            row.append(f" {label} ", FG if hl > 0.5 else FAINT)
            row.append(f" {it.icon}  ", mix(it.accent, "#ffffff", 0.25 * hl) if hl > 0.01 else it.accent)
            row.append(f"{it.label:<{lw}}", f"bold {mix(FG, it.accent, hl * 0.7)}" if hl > 0.01 else f"bold {FG}")
            if not self.compact:
                row.append(f" {it.desc}", mix(DIM, FG, hl * 0.5))
            meta = it.meta if isinstance(it.meta, Text) else Text(it.meta, DIM)
            pad = width - row.cell_len - meta.cell_len - 2
            if pad < 2:                       # too narrow: the description gives way
                row.truncate(max(10, width - meta.cell_len - 4), overflow="ellipsis")
                pad = max(1, width - row.cell_len - meta.cell_len - 2)
            row.append(" " * pad)
            row.append_text(meta)
            row.append("  ")
            row.truncate(width)
            if sel and hl > 0.01:                # the new row: the highlight wipes in from the left
                row.stylize(f"on {HL}", 0, max(1, round(width * ease)))
            elif was and hl > 0.01:              # the old one fades
                row.stylize(f"on {mix(BG, HL, hl)}")
            if self.rows and len(self.items) > self.rows and n in (shown.start, shown.stop - 1):
                more = shown.start if n == shown.start else len(self.items) - shown.stop
                if more:                             # a hint that there's more above / below
                    row.right_crop(2)
                    row.append("↑ " if n == shown.start else "↓ ", f"bold {DIM}")
            out.append_text(row)
            if n < shown.stop - 1:
                out.append("\n")
        return out


class Preview(Vertical):
    """The panel beside a menu: what the highlighted row will do, and what
    it's about to act on. Its contents cross-fade as the highlight moves."""

    DEFAULT_CSS = """
    Preview { height: auto; max-height: 100%; border: round #504945; padding: 0 1; }
    Preview > Static { height: auto; }
    """

    def compose(self):
        yield Static(id="pv")

    def show(self, item: Item | None, animate: bool = True) -> None:
        body = self.query_one("#pv", Static)
        if item is None or item.preview is None:
            self.display = False
            return
        self.display = True
        try:
            content = item.preview()
        except Exception as e:                      # a preview must never take the menu down
            content = Text(f"(couldn't draw this: {e})", DIM)
        self.border_title = f" {item.icon} {item.title or item.label} "
        self.styles.border_title_color = item.accent
        self.styles.border = ("round", mix(LINE, item.accent, 0.35))
        body.update(content)
        if animate:
            fade_in(body, 0.2, start=0.25)
            slide(body, (2, 0), 0.2)


# ── a job's stages ────────────────────────────────────────────────────────────
class Stages(Widget):
    """① Reach ── ② Build ── ③ Changes ── ④ Activate, with each stage's time
    under it. The running stage spins and counts, a finished one pops into a
    ✔, and the line to the next fills as it goes."""

    DEFAULT_CSS = "Stages { height: 2; padding: 0 2; }"

    def __init__(self, names: list[str], accent: str, **kw):
        super().__init__(**kw)
        self.names, self.accent = names, accent
        self.state = ["pending"] * len(names)
        self.changed = [0.0] * len(names)
        self.began: list[float | None] = [None] * len(names)
        self.took: list[float | None] = [None] * len(names)
        self.timer = None

    def on_mount(self) -> None:
        self.timer = self.set_interval(1 / 15, self.refresh)

    def set(self, i: int, state: str) -> None:
        if 0 <= i < len(self.state) and self.state[i] != state:
            now = time.monotonic()
            if state == "running":
                self.began[i] = now
            elif self.began[i] is not None and self.took[i] is None:
                self.took[i] = now - self.began[i]
            self.state[i], self.changed[i] = state, now
            self.refresh()

    def running(self) -> str | None:
        return next((n for n, s in zip(self.names, self.state) if s == "running"), None)

    def stop(self) -> None:
        """The job's over: let the last ✔ pop and its line finish filling,
        then stop drawing."""
        def halt() -> None:
            if self.timer:
                self.timer.stop()
                self.timer = None
            self.refresh()
        self.set_timer(0.8, halt)

    def render(self) -> Text:
        now = time.monotonic()
        top, under = Text(), Text()
        width = self.size.width
        seg = max(3, (width - sum(len(n) + 6 for n in self.names)) // max(1, len(self.names) - 1))
        for i, (name, st) in enumerate(zip(self.names, self.state)):
            age = now - self.changed[i]
            x0 = top.cell_len
            if st == "running":
                top.append(f" {spinner()} ", f"bold {self.accent}")
                top.append(name, f"bold {self.accent}")
            elif st == "done":
                pop = max(0.0, 1 - age / 0.6)
                top.append(" ✔ ", f"bold {mix(GREEN, '#ffffff', pop * 0.7)}")
                top.append(name, mix(FG, GREEN, 0.35 + pop * 0.4))
            elif st == "failed":
                flash = 0.5 + 0.5 * math.cos(age * 9) if age < 1.2 else 0.0
                top.append(" ✘ ", f"bold {mix(RED, '#ffffff', flash * 0.6)}")
                top.append(name, f"bold {RED}")
            elif st == "skipped":
                top.append(" – ", DIM)
                top.append(name, DIM)
            else:
                top.append(f" {'①②③④⑤⑥'[i]} ", FAINT)
                top.append(name, DIM)
            # the time under it, lined up with the name
            t = None
            if st == "running" and self.began[i] is not None:
                t, col = clock(now - self.began[i]), self.accent
            elif self.took[i] is not None and st in ("done", "failed"):
                t, col = _short(self.took[i]), (DIM if st == "done" else RED)
            if t:
                under.append(" " * max(0, x0 + 3 - under.cell_len))
                under.append(t, col)
            if i < len(self.names) - 1:
                fill = 0.0
                if st in ("done", "skipped"):
                    fill = min(1.0, age / 0.5)
                elif st == "running":
                    fill = 0.25 + 0.15 * math.sin(now * 3)
                filled = round(seg * fill)
                top.append(" ")
                for k in range(seg):
                    top.append("━" if k < filled else "─", grad((i + k / seg) / len(self.names)) if k < filled else LINE)
                top.append(" ")
        return Text.assemble(top, "\n", under)


def _short(s: float) -> str:
    s = int(round(s))
    return f"{s}s" if s < 60 else f"{s // 60}m {s % 60:02d}s"


class Rail(Widget):
    """The job's progress, edge to edge under the banner: how much of the
    whole job is done, a glint running along it while it works."""

    DEFAULT_CSS = "Rail { height: 1; padding: 0 2; }"

    def __init__(self, get: Callable[[], tuple[float, str]], **kw):
        super().__init__(**kw)
        self.get = get                 # → (fraction, state) — state: running / done / failed
        self.shown = 0.0

    def on_mount(self) -> None:
        self.timer = self.set_interval(1 / 20, self.refresh)

    def stop(self) -> None:
        self.timer.stop()
        self.refresh()

    def render(self) -> Text:
        frac, state = self.get()
        self.shown += (frac - self.shown) * 0.18          # ease towards it, never jump
        if abs(frac - self.shown) < 0.002:
            self.shown = frac
        w = self.size.width
        if state == "failed":
            t = bar(self.shown, w, empty=LINE)
            t.stylize(RED, 0, round(self.shown * w))
            return t
        glint = ((time.monotonic() * 0.45) % 1.3) - 0.15 if state == "running" else None
        return bar(self.shown, w, glint)


class Section(Vertical):
    """One step of a job in its journal: a heading, then whatever it shows."""

    DEFAULT_CSS = """
    Section { height: auto; margin: 1 0 0 0; }
    Section > .head { height: 1; }
    """

    def __init__(self, title: str, accent: str, icon: str = "", *children: Widget, **kw):
        super().__init__(*children, **kw)
        self.title, self.accent, self.icon = title, accent, icon

    def compose(self):
        yield Static(Text.assemble(("▍", self.accent), (f" {self.icon}  " if self.icon else " ", self.accent),
                                   (self.title, f"bold {FG}")), classes="head")

    def on_mount(self) -> None:
        fade_in(self, 0.35)
        slide(self, (0, 1), 0.3)


class Line(Static):
    """One status line in a section (✔ / ✘ / ! / ·)."""

    DEFAULT_CSS = "Line { height: auto; padding: 0 0 0 3; }"


def ok(msg: str, extra: str = "") -> Line:
    return Line(Text.assemble(("✔ ", f"bold {GREEN}"), (msg, FG), (f"  {extra}" if extra else "", DIM)))


def bad(msg: str, extra: str = "") -> Line:
    return Line(Text.assemble(("✘ ", f"bold {RED}"), (msg, FG), (f"  {extra}" if extra else "", DIM)))


def warn(msg: str) -> Line:
    return Line(Text.assemble(("! ", f"bold {YELLOW}"), (msg, FG)))


def info(msg: str) -> Line:
    return Line(Text.assemble(("· ", DIM), (msg, DIM)))


class SpinLine(Widget):
    """A line that spins while its thing runs, then settles into ✔ or ✘ (with
    the error under it)."""

    DEFAULT_CSS = "SpinLine { height: auto; padding: 0 0 0 3; }"

    def __init__(self, text: str, **kw):
        super().__init__(**kw)
        self.text, self.result = text, None
        self.t0 = time.monotonic()

    def on_mount(self) -> None:
        self.timer = self.set_interval(1 / 12, self.refresh)

    def finish(self, good: bool, label: str, extra: str = "") -> None:
        self.result = (good, label, extra)
        self.t_done = time.monotonic()
        self.timer.stop()
        self.timer = self.set_interval(1 / 30, self._settle)
        self.refresh(layout=True)

    def _settle(self) -> None:
        self.refresh()
        if time.monotonic() - self.t_done > 0.6:
            self.timer.stop()

    def get_content_height(self, container, viewport, width) -> int:
        if self.result and not self.result[0] and self.result[2]:
            return 1 + self.result[2].count("\n") + 1
        return 1

    def render(self) -> Text:
        if self.result is None:
            return Text.assemble((f"{spinner()} ", AQUA), (self.text, DIM),
                                 (f"  {time.monotonic() - self.t0:.0f}s", FAINT))
        good, label, extra = self.result
        pop = max(0.0, 1 - (time.monotonic() - self.t_done) / 0.6)
        if good:
            return Text.assemble(("✔ ", f"bold {mix(GREEN, '#ffffff', pop * 0.7)}"), (label, f"bold {FG}"), (f" {extra}", DIM))
        t = Text.assemble(("✘ ", f"bold {mix(RED, '#ffffff', pop * 0.7)}"), (label, f"bold {FG}"))
        for l in extra.splitlines():
            t.append("\n    " + l, RED)
        return t


class Waiting(Widget):
    """Waiting for a machine to come online: a pulse travels down the line
    from here to there, over and over, until it answers."""

    DEFAULT_CSS = "Waiting { height: 3; padding: 1 3 0 3; }"

    def __init__(self, here: str, there: str, **kw):
        super().__init__(**kw)
        self.here, self.there, self.t0 = here, there, time.monotonic()
        self.found = False

    def on_mount(self) -> None:
        self.timer = self.set_interval(1 / 20, self.refresh)

    def done(self) -> None:
        self.found = True
        self.timer.stop()
        self.refresh()

    def render(self) -> Text:
        now = time.monotonic()
        span = max(10, min(40, self.size.width - len(self.here) - len(self.there) - 12))
        t = Text()
        t.append(f"{self.here} ", f"bold {AQUA}")
        t.append("◉ ", AQUA)
        if self.found:
            for k in range(span):
                t.append("━", grad(k / span))
            t.append(" ● ", f"bold {GREEN}")
            t.append(self.there, f"bold {GREEN}")
            return t
        head = ((now - self.t0) * 0.7) % 1.0
        for k in range(span):
            d = k / span - head
            if -0.12 < d <= 0:
                t.append("•", mix(LINE, AQUA, 1 + d / 0.12))
            else:
                t.append("·", LINE)
        glow = 0.5 + 0.5 * math.sin(now * 4)
        t.append(" ○ ", mix(DIM, RED, glow * 0.6))
        t.append(self.there, f"bold {FG}")
        t.append(f"   waiting {int(now - self.t0)}s", DIM)
        return t


# ── the end of a job ──────────────────────────────────────────────────────────
class Confetti(Widget):
    """A job that worked ends with confetti: a burst from the middle that
    falls, tumbles and lands as a faint sprinkle along the bottom row."""

    DEFAULT_CSS = "Confetti { height: 3; padding: 0 2; }"
    GLYPHS = "✦✧⋆•▪◆✶✷*+"
    LIFE = 2.2

    def on_mount(self) -> None:
        self.t0 = time.monotonic()
        rnd = random.Random()
        self.bits = []
        for _ in range(70):
            self.bits.append(dict(
                x=0.5 + rnd.uniform(-0.08, 0.08), vx=rnd.uniform(-0.45, 0.45), vy=rnd.uniform(-5.5, -1.5),
                delay=rnd.uniform(0, 0.35), spin=rnd.uniform(4, 10), g=rnd.choice(self.GLYPHS),
                col=rnd.choice([grad(rnd.random()), grad(rnd.random()), YELLOW, GREEN, ORANGE, PURPLE])))
        self.timer = self.set_interval(1 / 30, self._tick)

    def _tick(self) -> None:
        self.refresh()
        if time.monotonic() - self.t0 > self.LIFE + 0.4:
            self.timer.stop()

    def render(self) -> Text:
        age = time.monotonic() - self.t0
        w, h = max(10, self.size.width), self.size.height or 3
        grid: list[list[tuple[str, str] | None]] = [[None] * w for _ in range(h)]
        for b in self.bits:
            a = age - b["delay"]
            if a < 0:
                continue
            y = h - 0.5 + b["vy"] * a + 4.2 * a * a              # up, then gravity brings it down
            x = b["x"] + b["vx"] * a * (1 - min(1.0, a / self.LIFE) * 0.5)
            landed = y >= h - 1
            y = min(y, h - 1)
            xi, yi = int(x * (w - 1)), int(y)
            if not (0 <= xi < w and 0 <= yi < h):
                continue
            if landed:                                            # a faint sprinkle where it fell
                if grid[yi][xi] is None:
                    grid[yi][xi] = ("·" if (xi % 3) else "⋆", mix(b["col"], BG, 0.7))
                continue
            g = b["g"] if int(a * b["spin"]) % 2 == 0 else "·✧"[int(a * 7) % 2]
            grid[yi][xi] = (g, mix(b["col"], BG, max(0.0, (a - self.LIFE * 0.6) / self.LIFE)))
        t = Text()
        for y, row in enumerate(grid):
            for cell in row:
                t.append(*(cell or (" ", "")))
            if y < h - 1:
                t.append("\n")
        return t


class Tile(Widget):
    """One number at the end of a job: TOOK 3m 12s, CLOSURE 14.2 GiB, …"""

    DEFAULT_CSS = """
    Tile { height: 4; width: 1fr; border: round #504945; padding: 0 1; margin: 0 1 0 0; }
    """

    def __init__(self, label: str, value: str, sub: str = "", accent: str = FG, **kw):
        super().__init__(**kw)
        self.label, self.value, self.sub, self.accent = label, value, sub, accent

    def on_mount(self) -> None:
        self.border_title = self.label.upper()
        self.styles.border_title_color = DIM

    def render(self) -> Text:
        return Text.assemble((self.value, f"bold {self.accent}"), "\n", (self.sub, DIM))


class Card(Vertical):
    """The end of a job: a green or red card saying what happened, a row of
    tiles with the numbers, then the details. It rises into place and the
    tiles pop in one by one; a failure gives a little shake."""

    DEFAULT_CSS = """
    Card { height: auto; margin: 0 1 1 1; padding: 0 1; }
    Card.good { border: round #b8bb26; }
    Card.bad { border: round #fb4934; }
    Card > .tiles { height: 4; margin: 1 0 0 0; }
    Card > .body { height: auto; padding: 1 1 1 1; }
    """

    def __init__(self, good: bool, title: str, rows: list[tuple[str, Text | str]],
                 tiles: list[tuple[str, str, str]] | None = None, accent: str = GREEN, **kw):
        super().__init__(classes="good" if good else "bad", **kw)
        self.good, self.title, self.rows, self.tiles, self.accent = good, title, rows, tiles or [], accent

    def compose(self):
        if self.tiles:
            with Horizontal(classes="tiles"):
                for label, value, sub in self.tiles:
                    yield Tile(label, value, sub, self.accent if self.good else RED)
        body = Text()
        for i, (k, v) in enumerate(self.rows):
            body.append(f"{k:<12}", DIM)
            body.append_text(v if isinstance(v, Text) else Text(v, FG))
            if i < len(self.rows) - 1:
                body.append("\n")
        if self.rows:
            yield Static(body, classes="body")

    def on_mount(self) -> None:
        self.border_title = f" {'✔' if self.good else '✘'} {self.title} "
        self.styles.border_title_color = GREEN if self.good else RED
        self.styles.border_title_style = "bold"
        fade_in(self, 0.4)
        slide(self, (0, 2), 0.4)
        for n, tile in enumerate(self.query(Tile)):
            fade_in(tile, 0.3, delay=0.25 + n * 0.09)
            slide(tile, (0, 1), 0.3, delay=0.25 + n * 0.09)
        if not self.good:
            for n, x in enumerate((3, -3, 2, -2, 1, 0)):
                self.set_timer(0.45 + n * 0.06, lambda x=x: setattr(self.styles, "offset", (x, 0)))


# ── asking things ─────────────────────────────────────────────────────────────
class _Modal(ModalScreen):
    DEFAULT_CSS = """
    _Modal { align: center middle; background: #1d2021 55%; }
    _Modal > Vertical { width: 66; height: auto; padding: 1 2; background: #282828; border: round #504945; }
    _Modal .q { margin-bottom: 1; }
    _Modal Input { margin-bottom: 1; }
    _Modal .hint { color: #928374; }
    """

    def on_mount(self) -> None:
        box = self.query_one(Vertical)
        fade_in(box, 0.18)
        slide(box, (0, -1), 0.18)


class PasswordModal(_Modal):
    """sudo (or anything) wants a password. Typed straight into that command."""

    def __init__(self, prompt: str, where: str = ""):
        super().__init__()
        self.prompt, self.where = prompt, where

    def compose(self):
        with Vertical():
            yield Static(Text.assemble((f"{I_KEY}  ", YELLOW), (self.prompt, f"bold {FG}")), classes="q")
            if self.where:
                yield Static(Text(self.where, DIM), classes="q")
            yield Input(password=True, placeholder="password")
            yield Static(Text("⏎ send   esc stop the command — it's never shown, logged or kept", DIM), classes="hint")

    def on_mount(self) -> None:
        super().on_mount()
        box = self.query_one(Vertical)
        box.styles.border = ("round", YELLOW)
        self.query_one(Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            event.stop()
            self.dismiss(None)


class InputModal(_Modal):
    def __init__(self, prompt: str, default: str = "", hint: str = ""):
        super().__init__()
        self.prompt, self.default, self.hint = prompt, default, hint

    def compose(self):
        with Vertical():
            yield Static(Text(self.prompt, f"bold {FG}"), classes="q")
            yield Input(value=self.default)
            yield Static(Text(self.hint or "⏎ ok   esc cancel", DIM), classes="hint")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one(Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            event.stop()
            self.dismiss(None)


class ChoiceModal(_Modal):
    """A question with a few answers, as a little menu. Esc → None."""

    def __init__(self, question: str, choices: list[tuple[str, str]], accent: str = AQUA,
                 detail: str = "", danger: bool = False):
        super().__init__()
        self.question, self.choices, self.accent, self.detail, self.danger = question, choices, accent, detail, danger

    def compose(self):
        with Vertical():
            yield Static(Text.assemble((f"{I_WARN}  " if self.danger else "", RED), (self.question, f"bold {FG}")), classes="q")
            if self.detail:
                yield Static(Text(self.detail, DIM), classes="q")
            yield Menu([Item(k, "›", label, accent=RED if self.danger and n == 0 else self.accent)
                        for n, (k, label) in enumerate(self.choices)])
            yield Static(Text("\n⏎ pick   esc cancel", DIM), classes="hint")

    def on_mount(self) -> None:
        super().on_mount()
        if self.danger:
            self.query_one(Vertical).styles.border = ("round", RED)
        self.query_one(Menu).focus()

    def on_menu_picked(self, event: Menu.Picked) -> None:
        event.stop()
        self.dismiss(event.key)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            event.stop()
            self.dismiss(None)


# ── jump ──────────────────────────────────────────────────────────────────────
@dataclass
class Action:
    key: str
    icon: str
    label: str
    desc: str
    accent: str
    where: str = ""          # the menu it lives in, shown on the right
    words: str = ""          # extra words it answers to


def fuzzy(query: str, hay: str) -> float | None:
    """A score if every word of QUERY appears in HAY as a subsequence (lower
    is better: earlier, tighter, at word starts); None if it doesn't match."""
    hay = hay.lower()
    score = 0.0
    for word in query.lower().split():
        pos, first, gaps = -1, None, 0
        for ch in word:
            nxt = hay.find(ch, pos + 1)
            if nxt < 0:
                return None
            if first is None:
                first = nxt
            elif nxt != pos + 1:
                gaps += 1
            pos = nxt
        start_bonus = -2 if first == 0 or hay[first - 1] in " ·-/›" else 0
        score += first * 0.05 + gaps + start_bonus
    return score


class JumpModal(_Modal):
    """ctrl+p (or /): type a few letters of anything the app can do — "sw
    asg", "gc", "update" — and ⏎ goes straight there."""

    DEFAULT_CSS = """
    JumpModal { align: center top; background: #1d2021 45%; }
    JumpModal > Vertical { width: 84; margin-top: 3; border: round #83a598; }
    JumpModal Menu { height: auto; }
    """

    def __init__(self, actions: list[Action]):
        super().__init__()
        self.actions = actions

    def compose(self):
        with Vertical():
            yield Input(placeholder=f"{I_SEARCH}  jump to…  (switch asgard · update · gc · help remote)")
            yield Menu(id="hits", rows=14)
            yield Static(Text("\n↑↓ move   ⏎ go   esc close", DIM), classes="hint")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one(Input).focus()
        self._filter("")

    def _filter(self, q: str) -> None:
        hits = []
        for a in self.actions:
            s = fuzzy(q, f"{a.label} {a.desc} {a.where} {a.words}") if q.strip() else 0.0
            if s is not None:
                hits.append((s, a))
        hits.sort(key=lambda p: p[0])
        menu = self.query_one(Menu)
        menu.set_items([Item(a.key, a.icon, a.label, a.desc, Text(a.where, DIM), a.accent, numbered=False)
                        for _, a in hits])
        menu.index = menu.top = 0
        menu.refresh(layout=True)

    def on_input_changed(self, event: Input.Changed) -> None:
        self._filter(event.value)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        menu = self.query_one(Menu)
        self.dismiss(menu.current)

    def on_menu_picked(self, event: Menu.Picked) -> None:
        event.stop()
        self.dismiss(event.key)

    def on_menu_highlighted(self, event: Menu.Highlighted) -> None:
        event.stop()

    def on_key(self, event: events.Key) -> None:
        menu = self.query_one(Menu)
        if event.key == "escape":
            self.dismiss(None)
        elif event.key in ("up", "ctrl+k", "ctrl+p"):
            menu.move(menu.index - 1)
        elif event.key in ("down", "ctrl+j", "ctrl+n", "tab"):
            menu.move(menu.index + 1)
        else:
            return
        event.stop()
