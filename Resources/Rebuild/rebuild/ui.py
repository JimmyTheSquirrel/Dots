"""The look: palette, gradient, and the widgets every screen is made of.

Gruvbox brights, the same family kitty uses, and the signature gradient —
aqua → blue → purple, the logo's colours — exactly as lib/ui.sh draws it, so
the app and the command-line half look like one thing.

Everything that moves moves on a timer that only runs while there's something
to animate (a spinner while a job runs, a shine every few seconds on the
logo), so an idle menu costs next to nothing.
"""
from __future__ import annotations

import math
import random
import time
from dataclasses import dataclass

from rich.text import Text
from textual import events
from textual.containers import Vertical
from textual.message import Message
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widget import Widget
from textual.widgets import Input, Static

AQUA, BLUE, PURPLE, YELLOW = "#8ec07c", "#83a598", "#d3869b", "#fabd2f"
RED, GREEN, FG, DIM, LINE, BG = "#fb4934", "#b8bb26", "#ebdbb2", "#928374", "#504945", "#1d2021"
HL = "#3c3836"
SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

I_NIX, I_BACK, I_QUIT = "", "", ""


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


def slide(widget: Widget, start: tuple[int, int], duration: float = 0.22) -> None:
    """Ease WIDGET from START (cells) back to where it belongs. (Textual can
    fade opacity itself, but won't tween a CSS offset — so this steps it.)"""
    t0 = time.monotonic()
    widget.styles.offset = start

    def step() -> None:
        p = min(1.0, (time.monotonic() - t0) / duration)
        e = 1 - (1 - p) ** 3
        widget.styles.offset = (round(start[0] * (1 - e)), round(start[1] * (1 - e)))
        if p >= 1:
            timer.stop()

    timer = widget.set_interval(1 / 60, step)


def spinner(t: float | None = None) -> str:
    return SPIN[int((time.monotonic() if t is None else t) * 12) % len(SPIN)]


def pill(label: str, fg: str = FG, bg: str = LINE) -> Text:
    return Text.assemble(("", bg), (label, f"{fg} on {bg}"), ("", bg))


# ── the logo ──────────────────────────────────────────────────────────────────
LOGO = [
    "█▀▀▄ ▄▀▀▄ ▀▀█▀▀ ▄▀▀▀",
    "█  █ █  █   █    ▀▀▄",
    "█▄▄▀ ▀▄▄▀   █   ▄▄▄▀",
]


class Header(Widget):
    """The home screen's top: DOTS in block letters along the gradient, a
    shine sweeping across them every few seconds, and three lines beside it."""

    DEFAULT_CSS = "Header { height: 4; padding: 1 0 0 3; }"
    lines: reactive[tuple] = reactive((Text(), Text(), Text()))

    def on_mount(self) -> None:
        self.t0 = time.monotonic()
        self.set_interval(1 / 20, self._tick)

    def _tick(self) -> None:
        phase = (time.monotonic() - self.t0) % 6.0
        if phase < 1.6 or getattr(self, "_shining", False):
            self._shining = phase < 1.6
            self.refresh()

    def render(self) -> Text:
        phase = (time.monotonic() - getattr(self, "t0", 0)) % 6.0
        shine = (phase / 1.4) * 1.4 - 0.2 if phase < 1.6 else None
        out = Text()
        for row, art in enumerate(LOGO):
            out.append_text(gradient_text(art, shine=shine))
            out.append("    ")
            out.append_text(self.lines[row] if row < len(self.lines) else Text())
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
        t = Text()
        for k, what in self.keys:
            t.append_text(pill(f" {k} "))
            t.append(f" {what}   ", DIM)
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


class Menu(Widget, can_focus=True):
    """Rows you move through with ↑↓/jk, pick with ⏎/→/l or 1–9 or a click.
    The highlight glides: the new row brightens in as the old one fades."""

    DEFAULT_CSS = "Menu { height: auto; padding: 0 1; }"
    BLEND = 0.16

    class Picked(Message):
        def __init__(self, key: str) -> None:
            super().__init__()
            self.key = key

    def __init__(self, items: list[Item] | None = None, **kw):
        super().__init__(**kw)
        self.items: list[Item] = items or []
        self.index = 0
        self.prev = -1
        self.t_moved = 0.0
        self.anim = None

    # contents ────────────────────────────────────────────────────────────────
    def set_items(self, items: list[Item], keep: str | None = None) -> None:
        cur = keep or (self.items[self.index].key if self.items else None)
        self.items = items
        keys = [i.key for i in items]
        self.index = keys.index(cur) if cur in keys else min(self.index, max(0, len(items) - 1))
        self.prev = -1
        self.refresh(layout=True)

    def get_content_height(self, container, viewport, width) -> int:
        return sum(2 if i.gap_before else 1 for i in self.items)

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

    def on_click(self, event: events.Click) -> None:
        y = 0
        for n, it in enumerate(self.items):
            y += 2 if it.gap_before else 1
            if event.y < y:
                if n == self.index:
                    self.pick()
                else:
                    self.move(n)
                return

    # drawing ─────────────────────────────────────────────────────────────────
    def render(self) -> Text:
        width = self.size.width
        p = min(1.0, (time.monotonic() - self.t_moved) / self.BLEND) if self.prev >= 0 else 1.0
        ease = 1 - (1 - p) ** 3
        out = Text()
        num = 0
        for n, it in enumerate(self.items):
            if it.gap_before:
                out.append("\n")
            if it.numbered:
                num += 1
            hl = ease if n == self.index else (1 - ease if n == self.prev else 0.0)
            bg = mix(BG, HL, hl) if hl > 0.01 else None
            row = Text()
            bar = mix(BG, it.accent, hl) if hl > 0.01 else None
            row.append("▌" if bar else " ", bar or "")
            label = f"{num}" if it.numbered and num <= 9 else " "
            row.append(f" {label} ", DIM if hl < 0.5 else FG)
            row.append(f" {it.icon}  ", it.accent)
            row.append(f"{it.label:<14}", f"bold {mix(FG, it.accent, hl * 0.6)}" if hl > 0.01 else f"bold {FG}")
            row.append(f" {it.desc}", mix(DIM, FG, hl * 0.5))
            meta = it.meta if isinstance(it.meta, Text) else Text(it.meta, DIM)
            pad = width - row.cell_len - meta.cell_len - 2
            if pad < 2:                       # too narrow: the description gives way
                row.truncate(max(10, width - meta.cell_len - 4), overflow="ellipsis")
                pad = max(1, width - row.cell_len - meta.cell_len - 2)
            row.append(" " * pad)
            row.append_text(meta)
            row.append("  ")
            if bg:
                row.stylize(f"on {bg}")
            out.append_text(row)
            if n < len(self.items) - 1:
                out.append("\n")
        return out


# ── a job's stages ────────────────────────────────────────────────────────────
class Stages(Widget):
    """① Reach ── ② Build ── ③ Changes ── ④ Activate. The running stage spins,
    a finished one pops into a ✔, and the line to the next fills as it goes."""

    DEFAULT_CSS = "Stages { height: 1; padding: 0 2; }"

    def __init__(self, names: list[str], accent: str, **kw):
        super().__init__(**kw)
        self.names, self.accent = names, accent
        self.state = ["pending"] * len(names)
        self.changed = [0.0] * len(names)
        self.timer = None

    def on_mount(self) -> None:
        self.timer = self.set_interval(1 / 15, self.refresh)

    def set(self, i: int, state: str) -> None:
        if 0 <= i < len(self.state) and self.state[i] != state:
            self.state[i], self.changed[i] = state, time.monotonic()
            self.refresh()

    def stop(self) -> None:
        if self.timer:
            self.timer.stop()
            self.timer = None
        self.refresh()

    def render(self) -> Text:
        now = time.monotonic()
        out = Text()
        width = self.size.width
        seg = max(3, (width - sum(len(n) + 6 for n in self.names)) // max(1, len(self.names) - 1))
        for i, (name, st) in enumerate(zip(self.names, self.state)):
            age = now - self.changed[i]
            if st == "running":
                out.append(f" {spinner()} ", f"bold {self.accent}")
                out.append(name, f"bold {self.accent}")
            elif st == "done":
                pop = max(0.0, 1 - age / 0.6)
                out.append(" ✔ ", f"bold {mix(GREEN, '#ffffff', pop * 0.7)}")
                out.append(name, mix(FG, GREEN, 0.35 + pop * 0.4))
            elif st == "failed":
                out.append(" ✘ ", f"bold {RED}")
                out.append(name, f"bold {RED}")
            elif st == "skipped":
                out.append(" – ", DIM)
                out.append(name, DIM)
            else:
                out.append(f" {'①②③④⑤⑥'[i]} ", LINE)
                out.append(name, DIM)
            if i < len(self.names) - 1:
                fill = 0.0
                if st in ("done", "skipped"):
                    fill = min(1.0, age / 0.5)
                elif st == "running":
                    fill = 0.25 + 0.15 * math.sin(now * 3)
                filled = round(seg * fill)
                out.append(" ")
                for k in range(seg):
                    out.append("━" if k < filled else "─", grad((i + k / seg) / len(self.names)) if k < filled else LINE)
                out.append(" ")
        return out


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
        self.styles.opacity = 0.0
        self.styles.animate("opacity", 1.0, duration=0.35)


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
        self.timer.stop()
        self.refresh(layout=True)

    def get_content_height(self, container, viewport, width) -> int:
        if self.result and not self.result[0] and self.result[2]:
            return 1 + self.result[2].count("\n") + 1
        return 1

    def render(self) -> Text:
        if self.result is None:
            return Text.assemble((f"{spinner()} ", AQUA), (self.text, DIM),
                                 (f"  {time.monotonic() - self.t0:.0f}s", LINE))
        good, label, extra = self.result
        if good:
            return Text.assemble(("✔ ", f"bold {GREEN}"), (label, f"bold {FG}"), (f" {extra}", DIM))
        t = Text.assemble(("✘ ", f"bold {RED}"), (label, f"bold {FG}"))
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


class Sparkle(Widget):
    """A short burst of sparkles over a result card that worked."""

    DEFAULT_CSS = "Sparkle { height: 1; padding: 0 3; }"
    GLYPHS = "✦✧⋆·✶✷"

    def on_mount(self) -> None:
        self.t0 = time.monotonic()
        self.seed = [(random.random(), random.random(), random.choice(self.GLYPHS)) for _ in range(28)]
        self.timer = self.set_interval(1 / 24, self._tick)

    def _tick(self) -> None:
        self.refresh()
        if time.monotonic() - self.t0 > 1.8:
            self.timer.stop()

    def render(self) -> Text:
        age = time.monotonic() - self.t0
        width = max(10, self.size.width)
        cells = [" "] * width
        colours = [""] * width
        for x0, delay, g in self.seed:
            a = age - delay * 0.6
            if 0 <= a < 1.0:
                x = int((x0 + (x0 - 0.5) * a * 0.3) * (width - 1))
                if 0 <= x < width:
                    cells[x] = g
                    colours[x] = mix(grad(x0), BG, a)
        t = Text()
        for c, col in zip(cells, colours):
            t.append(c, col or "")
        return t


class Card(Static):
    """The end of a job: a green or red card saying what happened. It rises
    into place; a failure gives a little shake."""

    DEFAULT_CSS = """
    Card { height: auto; margin: 0 1 1 1; padding: 1 2; }
    Card.good { border: round #b8bb26; }
    Card.bad { border: round #fb4934; }
    """

    def __init__(self, good: bool, title: str, rows: list[tuple[str, Text | str]], **kw):
        body = Text()
        for i, (k, v) in enumerate(rows):
            body.append(f"{k:<12}", DIM)
            body.append_text(v if isinstance(v, Text) else Text(v, FG))
            if i < len(rows) - 1:
                body.append("\n")
        super().__init__(body, classes="good" if good else "bad", **kw)
        self.border_title = f" {'✔' if good else '✘'} {title} "
        self.good = good

    def on_mount(self) -> None:
        self.styles.border_title_color = GREEN if self.good else RED
        self.styles.border_title_style = "bold"
        self.styles.opacity = 0.0
        self.styles.animate("opacity", 1.0, duration=0.4)
        slide(self, (0, 2), 0.4)
        if not self.good:
            for n, x in enumerate((3, -3, 2, -2, 1, 0)):
                self.set_timer(0.45 + n * 0.06, lambda x=x: setattr(self.styles, "offset", (x, 0)))


# ── asking things ─────────────────────────────────────────────────────────────
class _Modal(ModalScreen):
    DEFAULT_CSS = """
    _Modal { align: center middle; background: #1d2021 60%; }
    _Modal > Vertical { width: 64; height: auto; padding: 1 2; background: #282828; border: round #504945; }
    _Modal .q { margin-bottom: 1; }
    _Modal Input { margin-bottom: 1; }
    _Modal .hint { color: #928374; }
    """

    def on_mount(self) -> None:
        box = self.query_one(Vertical)
        box.styles.opacity = 0.0
        box.styles.animate("opacity", 1.0, duration=0.18)
        slide(box, (0, -1), 0.18)


class PasswordModal(_Modal):
    """sudo (or anything) wants a password. Typed straight into that command."""

    def __init__(self, prompt: str, where: str = ""):
        super().__init__()
        self.prompt, self.where = prompt, where

    def compose(self):
        with Vertical():
            yield Static(Text.assemble(("  ", YELLOW), (self.prompt, f"bold {FG}")), classes="q")
            if self.where:
                yield Static(Text(self.where, DIM), classes="q")
            yield Input(password=True, placeholder="password")
            yield Static(Text("⏎ send   esc stop the command — it's never shown, logged or kept", DIM), classes="hint")

    def on_mount(self) -> None:
        super().on_mount()
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
            yield Static(Text.assemble(("  " if self.danger else "", RED), (self.question, f"bold {FG}")), classes="q")
            if self.detail:
                yield Static(Text(self.detail, DIM), classes="q")
            yield Menu([Item(k, "›", label, accent=RED if self.danger and n == 0 else self.accent)
                        for n, (k, label) in enumerate(self.choices)])
            yield Static(Text("\n⏎ pick   esc cancel", DIM), classes="hint")

    def on_mount(self) -> None:
        super().on_mount()
        self.query_one(Menu).focus()

    def on_menu_picked(self, event: Menu.Picked) -> None:
        event.stop()
        self.dismiss(event.key)

    def on_key(self, event: events.Key) -> None:
        if event.key == "escape":
            event.stop()
            self.dismiss(None)
