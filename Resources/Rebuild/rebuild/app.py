"""system-rebuild — the full-screen app (Textual).

`system-rebuild` with no arguments, in a terminal, opens this. It is the same
control panel the bash menus were — rebuild this machine, deploy the others,
look after the repo and the store, drive the Apollo USB — but it owns the
screen: the logo draws itself in, every machine is a live card, a panel
beside each menu previews exactly what ⏎ will do (the steps, the command, the
target, how it went last time), ctrl+p jumps straight to anything, a build is
drawn live (nixmon.py) under a progress rail, sudo and ssh questions pop up
as boxes, and a job ends in a card with its numbers — confetti when it
worked, a shake when it didn't. The terminal's title follows the job, and a
long one that finishes while you're in another window sends a notification.

The command-line half — `system-rebuild rock Asgard [--boot|--build]`,
`system-rebuild help`, and the old inline menus as `--classic` — stays in
Resources/Scripts/system-rebuild.sh.

Layout of this package:
  hosts.py    the machines, the flake, generations     probe.py   async lookups
  runner.py   commands in a pty, prompts → modals       jobs.py    what each row does
  ui.py       palette, gradient, widgets, modals        panels.py  machine cards, previews
  history.py  what ran before (~/.local/state)          help.py    the help pages
  nixmon.py   the live build view (nix's internal-json log)
"""
from __future__ import annotations

import asyncio
import getpass
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import traceback
from typing import Awaitable, Callable

from rich.console import Group
from rich.table import Table
from rich.text import Text
from textual import events, work
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import Screen
from textual.widget import Widget
from textual.widgets import RichLog, Static

from . import help as HELP
from . import history as HIST
from . import hosts as H
from . import jobs as J
from . import panels as PN
from . import probe as P
from .panels import dot
from .runner import PtyRun, plain
from .ui import (AQUA, BG, BLUE, DIM, FAINT, FG, GREEN, LINE, ORANGE, PURPLE, RED, YELLOW, Action, Card,
                 ChoiceModal, Confetti, Crumbs, Header, Hints, I_BACK, I_NIX, I_QUIT, InputModal, Item, JumpModal,
                 Menu, PasswordModal, Preview, Rail, Section, SpinLine, Stages, Waiting, clock, fade_in,
                 gradient_text, info, mix, pill, slide, sparkline, spinner)

I = dict(rebuild="", remote="", utils="", apollo="", switch="", boot="",
         build="", other="", ssh="", git="", update="", gc="", check="",
         clone="", deploy="", iso="", key="", dry="", vm="", warn="",
         help="", history="", wait="", tip="")

Job = Callable[["JobScreen"], Awaitable[bool]]
WIDE = 110          # columns from which a menu gets its preview panel


def peer_short(p: P.Peer) -> Text:
    """For a menu row's right-hand side: just the state and how it's reached."""
    if p.state == "online":
        return Text.assemble(("● online", GREEN), (f" · {p.path.split()[0]}", DIM))
    if p.state == "offline":
        return Text.assemble(("○ offline", RED), (f" · {P.ago(p.seen) if p.seen else 'never seen'}", DIM))
    return Text("◌ not on the tailnet" if p.state == "missing" else "◌ unknown", DIM)


def peer_phrase(p: P.Peer) -> Text:
    if p.state == "online":
        return Text.assemble(("● online", GREEN), (f" · {p.path} · {p.ip}", DIM))
    if p.state == "offline":
        return Text.assemble(("○ offline", RED), (f" · {p.seen_text()}", DIM))
    if p.state == "missing":
        return Text("◌ not on the tailnet", DIM)
    return Text("◌ tailscale unavailable", DIM)


def here_name() -> str:
    return H.THIS.name if H.THIS else platform.node()


# ── the app ───────────────────────────────────────────────────────────────────
class RebuildApp(App):
    CSS_PATH = "app.tcss"
    TITLE = "system-rebuild"
    ENABLE_COMMAND_PALETTE = False          # ours is JumpModal: same idea, in the app's own look

    def __init__(self) -> None:
        super().__init__()
        self.reload_repo()
        self.tailnet = P.Tailnet()
        self.repo_st: P.RepoStatus | None = None
        self.free: int | None = None
        self.mount_point = ""
        self.has_apollo = shutil.which("apollo-deploy") is not None
        self.probes: dict[str, P.Remote] = {}
        self.probed_at = 0.0

    def reload_repo(self) -> None:
        self.repo = H.find_repo()
        if self.repo.path:
            os.chdir(self.repo.path)        # nix build "." and git run from the checkout

    def on_mount(self) -> None:
        self.term("\x1b[22;0t")             # keep the terminal's own title, to give it back on exit
        self.set_title("system-rebuild")
        self.push_screen(HomeScreen())
        self.refresh_state()
        self.set_interval(30, self.refresh_state)

    @work(exclusive=True, group="state")
    async def refresh_state(self) -> None:
        ts, st, free, mnt = await asyncio.gather(
            P.tailnet(), P.repo_status(self.repo), P.store_free(),
            P.apollo_mount() if self.has_apollo else asyncio.sleep(0, ""))
        self.tailnet, self.repo_st, self.free, self.mount_point = ts, st, free, mnt or ""
        self.redraw_menus()
        if time.monotonic() - self.probed_at > 300:
            self.probed_at = time.monotonic()
            self.probe_remotes()

    @work(exclusive=True, group="probe")
    async def probe_remotes(self) -> None:
        """Ask every online machine what it runs, all at once, in the background
        (ssh in batch mode: a machine that would ask for anything just says no)."""
        hosts = [h for h in H.HOSTS if h.mode == "push" and not (H.THIS and h.name == H.THIS.name)
                 and self.tailnet.peer(h.name).state == "online"]
        results = await asyncio.gather(*(P.remote_probe(h) for h in hosts))
        for h, r in zip(hosts, results):
            if r.ok or h.name not in self.probes:
                self.probes[h.name] = r
        self.redraw_menus()

    def redraw_menus(self) -> None:
        for s in self.screen_stack:
            if isinstance(s, MenuScreen):
                s.rebuild()

    # the terminal ────────────────────────────────────────────────────────────
    def term(self, seq: str) -> None:
        """Write an escape straight to the terminal (between Textual's frames)."""
        try:
            if self._driver is not None and not self.is_headless:
                self._driver.write(seq)
        except Exception:
            pass

    def set_title(self, text: str) -> None:
        self.term(f"\x1b]2;{text}\x07")

    def alert(self, title: str, body: str, good: bool = True) -> None:
        """Something wants you (a job ended, a password is wanted) and you've
        gone to another window: a desktop notification, and the terminal's
        bell (kitty marks the tab)."""
        if self.app_focus:
            return
        self.bell()
        if shutil.which("notify-send"):
            try:
                subprocess.Popen(["notify-send", "-a", "system-rebuild", "-u", "normal" if good else "critical",
                                  "-i", "emblem-default" if good else "dialog-error", title, body],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            except OSError:
                pass

    def run_outside(self, argv: list[str], title: str, pause: bool = True) -> None:
        """A command that needs the real terminal (ssh, the apollo tools):
        the app steps aside, runs it, and comes back."""
        with self.suspend():
            print(f"\n  \033[1m{title}\033[0m  \033[2m{' '.join(argv)}\033[0m\n")
            try:
                rc = subprocess.call(argv)
            except FileNotFoundError:
                rc = 127
                print(f"{argv[0]}: not found")
            if pause:
                try:
                    input(f"\n  \033[2m(exit {rc}) — ⏎ back to system-rebuild\033[0m ")
                except EOFError:
                    pass
        self.notify(f"{title} — exit {rc}", severity="information" if rc == 0 else "error")
        self.set_title("system-rebuild")
        self.refresh_state()

    # jump ─────────────────────────────────────────────────────────────────────
    def actions(self) -> list[Action]:
        """Everything the jump palette can go to — the same rows as the menus."""
        out: list[Action] = []
        if H.THIS:
            for a, d in (("switch", "build · diff · activate now"), ("boot", "build · diff · on next boot"),
                         ("build", "build · diff · activate nothing")):
                out.append(Action(f"job:{a}:{H.THIS.name}", I[a], f"{a.title()} {H.THIS.name}", d, AQUA,
                                  "Rebuild", "this machine local"))
        for h in H.HOSTS:
            if (H.THIS and h.name == H.THIS.name):
                continue
            if h.mode == "stick":
                out.append(Action(f"job:build:{h.name}", I["build"], f"Build {h.name}", "build its config here",
                                  AQUA, "Rebuild › Other host"))
                continue
            for a, d in (("switch", "build here, push, activate now"),
                         ("boot", "build here, push, activate on its next reboot"),
                         ("build", "build here and diff — nothing deployed")):
                out.append(Action(f"job:{a}:{h.name}", I[a], f"{a.title()} {h.name}", d, BLUE, "Remote",
                                  f"push deploy {h.ssh}"))
            out.append(Action(f"ssh:{h.name}", I["ssh"], f"SSH {h.name}", f"a shell on {h.target}", BLUE, "Remote"))
            out.append(Action(f"go:host:{h.name}", h.icon, h.name, h.role, BLUE, "Remote", "menu machine"))
        if self.repo.path:
            out.append(Action("job:sync", I["git"], "Git sync", "commit · pull --rebase · push", YELLOW, "Utilities"))
            out.append(Action("job:update", I["update"], "Update inputs", "nix flake update + changelog", YELLOW,
                              "Utilities", "flake lock"))
        else:
            out.append(Action("job:clone", I["clone"], "Get the repo", "clone it to ~/Dots", YELLOW, "Utilities"))
        out.append(Action("job:gc", I["gc"], "Garbage collect", "old generations · store · docker", YELLOW,
                          "Utilities", "gc clean free space"))
        out.append(Action("job:check", I["check"], "Check hosts", "evaluate every host, build nothing", YELLOW,
                          "Utilities", "eval"))
        out.append(Action("go:history", I["history"], "History", "every job the app has run", YELLOW, "Utilities",
                          "log runs"))
        if self.has_apollo:
            out.append(Action("go:apollo", I["apollo"], "Apollo", "the deployer USB", PURPLE, "Apollo", "usb stick"))
            for k, cmd in (("iso", "apollo-iso"), ("key", "apollo-key"), ("ssh", "apollo-connect")):
                out.append(Action(f"out:{cmd}", I[k], cmd, PN.APOLLO_TEXT[k][0][:60], PURPLE, "Apollo"))
        for k, (title, accent, icon, _) in HELP.PAGES.items():
            out.append(Action(f"help:{k}", icon, f"Help · {title}", "", accent, "Help"))
        out.append(Action("quit", I_QUIT, "Quit", "", DIM, ""))
        return out

    def do_action(self, key: str | None) -> None:
        if not key:
            return
        kind, _, rest = key.partition(":")
        if kind == "job":
            what, _, host = rest.partition(":")
            if host:
                h = H.BY_NAME[host]
                self.push_screen(JobScreen(lambda j, a=what, h=h: J.rebuild(j, h, a)))
            else:
                self.push_screen(JobScreen({"sync": J.sync_repo, "update": J.update_inputs, "clone": J.clone_repo,
                                            "gc": J.collect_garbage, "check": J.check_hosts}[what]))
        elif kind == "ssh":
            h = H.BY_NAME[rest]
            self.run_outside(["ssh", "-t", h.target], f"SSH · {h.name}", pause=False)
        elif kind == "out":
            self.run_outside([rest], f"Apollo · {rest}", pause=rest != "apollo-connect")
        elif kind == "go":
            if rest == "history":
                self.push_screen(HistoryScreen())
            elif rest == "apollo":
                self.push_screen(ApolloMenu())
            elif rest.startswith("host:"):
                self.push_screen(HostMenu(H.BY_NAME[rest[5:]]))
        elif kind == "help":
            self.push_screen(HelpPage(rest))
        elif kind == "quit":
            self.exit()

    @work
    async def jump(self) -> None:
        fut = asyncio.get_running_loop().create_future()
        self.push_screen(JumpModal(self.actions()), callback=lambda r: fut.done() or fut.set_result(r))
        self.do_action(await fut)


# ── menus ─────────────────────────────────────────────────────────────────────
class MenuScreen(Screen):
    """A menu: a top (the home header and cards, or crumbs), notes, the rows,
    and — on a wide terminal — a preview of the highlighted row beside them.
    Subclasses give spec() → (notes, items) and pick(key)."""

    accent = AQUA
    crumbs: list[str] = []
    topic = "basics"
    home = False

    def top(self) -> ComposeResult:
        yield Crumbs(self.crumbs, self.accent, f"{here_name()} · {getpass.getuser()}")

    def compose(self) -> ComposeResult:
        with Vertical(id="body"):
            yield from self.top()
            yield Static(id="notes")
            with Horizontal(id="main"):
                yield Menu(id="menu")
                yield Preview(id="preview")
        yield Hints()

    def on_mount(self) -> None:
        self.wide = self.size.width >= WIDE
        self.rebuild()
        self.query_one(Menu).focus()
        self.query_one(Hints).keys = (("↑↓", "move"), ("⏎", "pick"), ("esc", "back") if not self.home else ("r", "refresh"),
                                      ("ctrl+p", "jump"), ("?", "help"), ("q", "quit"))
        body = self.query_one("#body")
        fade_in(body, 0.22)
        if not self.home:
            slide(body, (6, 0))

    def on_screen_resume(self) -> None:
        self.rebuild()
        self.query_one(Menu).focus()
        self.app.set_title("system-rebuild")

    def on_resize(self, event: events.Resize) -> None:
        wide = event.size.width >= WIDE
        if wide != getattr(self, "wide", None):
            self.wide = wide
            self._preview(self.query_one(Menu), False)

    def rebuild(self) -> None:
        if not self.is_mounted:
            return
        notes, items = self.spec()
        n = self.query_one("#notes", Static)
        n.display = bool(notes)
        n.update(Text("\n").join(notes) if notes else "")
        self.query_one(Menu).set_items(items)

    def _preview(self, menu: Menu, moved: bool) -> None:
        pv = self.query_one(Preview)
        if not self.wide:
            pv.display = False
            return
        pv.show(menu.items[menu.index] if menu.items else None, animate=moved)

    def on_menu_highlighted(self, event: Menu.Highlighted) -> None:
        event.stop()
        self._preview(self.query_one(Menu), event.moved)

    def spec(self) -> tuple[list[Text], list[Item]]:
        return [], []

    def pick(self, key: str) -> None:
        pass

    def tail(self, items: list[Item]) -> list[Item]:
        topic = self.topic
        items.append(Item("help", I["help"], "Help", "what each of these does", Text("?", DIM), GREEN, gap_before=True,
                          preview=lambda: PN.pv_help_page(topic), title=f"Help · {HELP.PAGES[topic][0]}"))
        items.append(Item("back", I_BACK, "Back", "", Text("esc", DIM), DIM))
        return items

    def on_menu_picked(self, event: Menu.Picked) -> None:
        event.stop()
        if event.key == "back":
            self.app.pop_screen()
        elif event.key == "help":
            self.app.push_screen(HelpPage(self.topic))
        elif event.key == "quit":
            self.app.exit()
        else:
            self.pick(event.key)

    def on_key(self, event: events.Key) -> None:
        k = event.key
        if k in ("escape", "left", "h") and not self.home:
            self.app.pop_screen()
        elif k == "question_mark":
            self.app.push_screen(HelpPage(self.topic))
        elif k in ("ctrl+p", "slash", "colon"):
            self.app.jump()
        elif k == "q":
            self.app.exit()
        elif k == "r":
            self.app.probed_at = 0
            self.app.refresh_state()
            self.notify("refreshing…", timeout=1.5)
        else:
            return
        event.stop()

    def job(self, fn: Job) -> None:
        self.app.push_screen(JobScreen(fn))


class HomeScreen(MenuScreen):
    accent = AQUA
    home = True

    def top(self) -> ComposeResult:
        yield Header(id="header")
        yield PN.MachineStrip()

    def rebuild(self) -> None:
        if not self.is_mounted:
            return
        app = self.app
        ver = H.os_version()
        last = HIST.last(kinds=("switch", "boot", "build"))
        lines = [
            Text.assemble(("system-rebuild", f"bold {FG}"), ("  rebuild · deploy · maintain", DIM)),
            Text.assemble((here_name(), f"bold {AQUA}"), (" · ", DIM), getpass.getuser(),
                          (f" · NixOS {ver}" if ver else "", DIM)),
            PN.repo_line(app),
        ]
        if app.repo.path:
            age = H.lock_age(app.repo)
            lines.append(Text.assemble((f"{'inputs':<7}", DIM), ("locked ", DIM), (P.ago(age), FG)) if age else
                         Text.assemble((f"{'inputs':<7}", DIM), ("no nixpkgs in flake.lock", DIM)))
        lines.append(Text.assemble((f"{'store':<7}", DIM), PN.store_line(16)))
        lines.append(Text.assemble((f"{'last':<7}", DIM), (f"{last.host} " if last else "", f"bold {FG}"),
                                   PN.run_line(last, "nothing run from the app yet")))
        self.query_one(Header).lines = tuple(lines)
        for card in self.query(PN.MachineCard):
            card.refresh()
        super().rebuild()

    def on_machine_card_picked(self, event: PN.MachineCard.Picked) -> None:
        h = H.BY_NAME[event.name]
        if H.THIS and h.name == H.THIS.name:
            self.app.push_screen(RebuildMenu())
        elif h.mode == "stick":
            if self.app.has_apollo:
                self.app.push_screen(ApolloMenu())
        else:
            self.app.push_screen(HostMenu(h))

    def spec(self):
        app = self.app
        items: list[Item] = []
        if H.THIS:
            items.append(Item("rebuild", I["rebuild"], "Rebuild", f"{H.THIS.name} · this machine",
                              Text("switch · boot · build", DIM), AQUA, preview=lambda: PN.pv_this(app),
                              title=f"Rebuild · {H.THIS.name}"))
        else:
            items.append(Item("rebuild", I["rebuild"], "Rebuild", "build any host's config here", "", AQUA,
                              preview=lambda: PN.pv_any_host(app)))
        remotes = Text()
        for h in H.HOSTS:
            if (H.THIS and h.name == H.THIS.name) or h.mode == "stick":
                continue
            remotes.append(f"{h.name} ", DIM)
            remotes.append_text(dot(app.tailnet.peer(h.name).state))
            remotes.append("  ")
        items.append(Item("remote", I["remote"], "Remote", "deploy over the tailnet", remotes, BLUE,
                          preview=lambda: PN.pv_remotes(app)))
        items.append(Item("utils", I["utils"], "Utilities", "keep the repo and the store tidy",
                          Text("sync · update · gc", DIM), YELLOW, preview=lambda: PN.pv_utils(app)))
        if app.has_apollo:
            p = app.tailnet.peer("Apollo")
            items.append(Item("apollo", I["apollo"], "Apollo", "the deployer USB",
                              Text.assemble(("stick ", DIM), dot(p.state), ("  usb ", DIM),
                                            ("✔", GREEN) if app.mount_point else ("–", DIM)), PURPLE,
                              preview=lambda: PN.pv_apollo(app)))
        items.append(Item("help", I["help"], "Help", "what everything here does", Text("?", DIM), GREEN,
                          preview=PN.pv_help_topics))
        items.append(Item("quit", I_QUIT, "Quit", "", Text("q", DIM), DIM, gap_before=True, preview=PN.pv_tip,
                          title="Quit — and a tip"))
        return [], items

    def pick(self, key: str) -> None:
        self.app.push_screen({"rebuild": RebuildMenu, "remote": RemoteMenu, "utils": UtilsMenu,
                              "apollo": ApolloMenu, "help": HelpMenu}[key]())


class RebuildMenu(MenuScreen):
    accent, crumbs, topic = AQUA, ["Rebuild"], "rebuild"

    def spec(self):
        app = self.app
        notes, items = [], []
        if H.THIS:
            h = H.THIS
            gen, when = H.generation(h.profile)
            notes.append(Text.assemble(("◆ ", AQUA), (h.name, f"bold {FG}"),
                                       (f"  {h.key} · generation {gen or '?'}" + (f", built {P.ago(when)}" if when else ""), DIM)))
            if app.repo.flake != ".":
                notes.append(Text.assemble(("! ", YELLOW), ("no ~/Dots here — builds ", DIM), H.DOTS_FLAKE, (" (main)", DIM)))
            items += [
                Item("switch", I["switch"], "Switch", "build · diff · activate now", "", AQUA,
                     preview=lambda: PN.pv_action(app, h, "switch", True), title=f"Switch · {h.name}"),
                Item("boot", I["boot"], "Boot", "build · diff · on next boot",
                     Text("next reboot" if h.profile == "system" else f"GRUB › {h.name}", DIM), AQUA,
                     preview=lambda: PN.pv_action(app, h, "boot", True), title=f"Boot · {h.name}"),
                Item("build", I["build"], "Build", "build · diff · activate nothing",
                     Text("./result" if app.repo.path else "", DIM), AQUA,
                     preview=lambda: PN.pv_action(app, h, "build", True), title=f"Build · {h.name}"),
            ]
        else:
            notes.append(Text.assemble(("! ", YELLOW), platform.node(), (" isn't one of ", DIM),
                                       " ".join(h.name for h in H.HOSTS)))
        items.append(Item("other", I["other"], "Other host", "build another machine's config, deploy nothing", "",
                          AQUA, gap_before=bool(items), preview=lambda: PN.pv_other_hosts(app)))
        return notes, self.tail(items)

    def pick(self, key: str) -> None:
        if key in ("switch", "boot", "build"):
            self.job(lambda j, k=key: J.rebuild(j, H.THIS, k))
        elif key == "other":
            self.app.push_screen(OtherHostMenu())


class OtherHostMenu(MenuScreen):
    accent, crumbs, topic = AQUA, ["Rebuild", "Other host"], "rebuild"

    def spec(self):
        app = self.app
        items = [Item(h.name, h.icon, h.name, h.role, Text(h.key, DIM), AQUA,
                      preview=lambda h=h: PN.pv_action(app, h, "build", False), title=f"Build · {h.name}")
                 for h in H.HOSTS if not (H.THIS and h.name == H.THIS.name)]
        return [Text("builds the config and diffs it against what that machine runs", DIM)], self.tail(items)

    def pick(self, key: str) -> None:
        self.job(lambda j: J.rebuild(j, H.BY_NAME[key], "build"))


class RemoteMenu(MenuScreen):
    accent, crumbs, topic = BLUE, ["Remote"], "remote"

    def spec(self):
        app, items = self.app, []
        for h in H.HOSTS:
            if (H.THIS and h.name == H.THIS.name) or h.mode == "stick":
                continue
            items.append(Item(h.name, h.icon, h.name, h.role, peer_short(app.tailnet.peer(h.name)), BLUE,
                              preview=lambda h=h: PN.pv_host(app, h)))
        return [Text("builds here, copies the closure over the tailnet, activates there", DIM)], self.tail(items)

    def pick(self, key: str) -> None:
        self.app.push_screen(HostMenu(H.BY_NAME[key]))


class HostMenu(MenuScreen):
    accent, topic = BLUE, "remote"

    def __init__(self, host: H.Host):
        super().__init__()
        self.host = host
        self.crumbs = ["Remote", host.name]
        self.asking = True

    def on_mount(self) -> None:
        super().on_mount()
        self.probe()
        self.spin = self.set_interval(1 / 10, self._spin)

    def _spin(self) -> None:
        if self.asking and self.host.name not in self.app.probes:
            self.rebuild()
        elif not self.asking:
            self.spin.stop()

    @work(exclusive=True)
    async def probe(self) -> None:
        r = await P.remote_probe(self.host)
        if r.ok or self.host.name not in self.app.probes:
            self.app.probes[self.host.name] = r
        self.asking = False
        self.rebuild()

    def spec(self):
        app, h, p = self.app, self.host, self.app.tailnet.peer(self.host.name)
        notes = [peer_phrase(p)]
        r = app.probes.get(h.name)
        if self.asking and r is None:
            notes.append(Text(f"{spinner()} asking {h.name}…", DIM))
        elif r and r.ok:
            notes.append(Text.assemble(("running ", DIM), f"generation {r.generation}", (" · up ", DIM), P.uptime_text(r.uptime)))
            if r.checkout:
                br, head, when, dirty = r.checkout
                notes.append(Text.assemble(("its ~/Dots ", DIM), (br, BLUE), (" @ ", DIM), head, (f" ({when})  ", DIM),
                                           ("✔ clean", GREEN) if not dirty else (f"● {dirty} changed", YELLOW)))
        elif r is not None:
            notes.append(Text("couldn't ask over ssh — key not authorised, or it's busy", DIM))
        items = [
            Item("switch", I["switch"], "Switch", "build here, push, activate now", "", BLUE,
                 preview=lambda: PN.pv_action(app, h, "switch", False), title=f"Switch · {h.name}"),
            Item("boot", I["boot"], "Boot", "build here, push, activate on its next reboot", "", BLUE,
                 preview=lambda: PN.pv_action(app, h, "boot", False), title=f"Boot · {h.name}"),
            Item("build", I["build"], "Build", "build here and diff — nothing deployed", "", BLUE,
                 preview=lambda: PN.pv_action(app, h, "build", False), title=f"Build · {h.name}"),
            Item("ssh", I["ssh"], "SSH", f"open a shell on {h.name}", Text(h.target, DIM), BLUE,
                 preview=lambda: PN.pv_ssh(app, h), title=f"SSH · {h.name}"),
        ]
        return notes, self.tail(items)

    def pick(self, key: str) -> None:
        if key == "ssh":
            self.app.run_outside(["ssh", "-t", self.host.target], f"SSH · {self.host.name}", pause=False)
        else:
            self.job(lambda j, k=key: J.rebuild(j, self.host, k))


class UtilsMenu(MenuScreen):
    accent, crumbs, topic = YELLOW, ["Utilities"], "utils"

    def spec(self):
        app, items = self.app, []
        if app.repo.path:
            st = app.repo_st
            meta = Text("…", DIM) if not st else (Text("✔ clean", GREEN) if not st.dirty else Text(f"● {st.dirty} changed", YELLOW))
            items.append(Item("sync", I["git"], "Git sync", "commit · pull --rebase · push", meta, YELLOW,
                              preview=lambda: PN.pv_sync(app)))
            items.append(Item("update", I["update"], "Update inputs", "nix flake update + changelog",
                              Text(f"locked {P.ago(H.lock_age(app.repo))}", DIM), YELLOW,
                              preview=lambda: PN.pv_update(app)))
        else:
            items.append(Item("clone", I["clone"], "Get the repo", "clone it to ~/Dots, for sync and update",
                              Text("github", DIM), YELLOW, preview=lambda: PN.pv_clone(app)))
        items.append(Item("gc", I["gc"], "Garbage collect", "old generations · store · docker",
                          Text(f"{P.human_bytes(app.free)} free" if app.free else "", DIM), YELLOW,
                          preview=lambda: PN.pv_gc(app)))
        items.append(Item("check", I["check"], "Check hosts", "evaluate every host, build nothing",
                          Text(f"{len(H.HOSTS)} hosts", DIM), YELLOW, preview=lambda: PN.pv_check(app)))
        n = len(HIST.load())
        items.append(Item("history", I["history"], "History", "every job the app has run",
                          Text(f"{n} run{'s' if n != 1 else ''}" if n else "", DIM), YELLOW,
                          preview=lambda: PN.pv_history(app)))
        return [], self.tail(items)

    def pick(self, key: str) -> None:
        if key == "history":
            self.app.push_screen(HistoryScreen())
            return
        self.job({"sync": J.sync_repo, "update": J.update_inputs, "clone": J.clone_repo,
                  "gc": J.collect_garbage, "check": J.check_hosts}[key])


class ApolloMenu(MenuScreen):
    accent, crumbs, topic = PURPLE, ["Apollo"], "apollo"

    def spec(self):
        app = self.app
        notes = [Text.assemble((f"{k:<6}", DIM), v) for k, v in PN.apollo_rows(app)]
        items = [
            Item("deploy", I["deploy"], "Deploy", "install onto the booted machine", Text("wipes its disks", RED), PURPLE,
                 preview=lambda: PN.pv_apollo_item(app, "deploy")),
            Item("ssh", I["ssh"], "SSH", "connect to the booted stick", Text("apollo-connect", DIM), PURPLE,
                 preview=lambda: PN.pv_apollo_item(app, "ssh")),
            Item("iso", I["iso"], "Build ISO", "build the image, copy it to the stick", Text("apollo-iso", DIM), PURPLE,
                 preview=lambda: PN.pv_apollo_item(app, "iso")),
            Item("key", I["key"], "Tailnet key", "write the auth key onto the stick", Text("apollo-key", DIM), PURPLE,
                 preview=lambda: PN.pv_apollo_item(app, "key")),
        ]
        return notes, self.tail(items)

    def pick(self, key: str) -> None:
        if key == "deploy":
            self.app.push_screen(ApolloDeployMenu())
        else:
            cmd = {"ssh": "apollo-connect", "iso": "apollo-iso", "key": "apollo-key"}[key]
            self.app.run_outside([cmd], f"Apollo · {cmd}", pause=key != "ssh")


class ApolloDeployMenu(MenuScreen):
    accent, crumbs, topic = PURPLE, ["Apollo", "Deploy"], "apollo"

    def spec(self):
        repo, items = self.app.repo, []
        for h in H.HOSTS:
            if repo.path and (repo.path / "Hosts" / h.name / "_disko.nix").is_file():
                facter = (repo.path / "Hosts" / h.name / "facter.json").is_file()
                items.append(Item(h.name, h.icon, h.name, h.role, Text(f"{h.key} · disko{' + facter' if facter else ''}", DIM), PURPLE,
                                  preview=lambda h=h: Group(
                                      Text(f"Install {h.name} onto the machine booted from the stick: disko partitions "
                                           f"its disks{', facter.json describes its hardware' if facter else ''}, then "
                                           "nixos-anywhere installs it.", FG), Text(""),
                                      PN.cmd(f"apollo-deploy {h.key}", PURPLE))))
        return [Text.assemble((f"{I['warn']}  the target must be booted from the stick · INSTALL erases its disks", RED))], self.tail(items)

    def pick(self, key: str) -> None:
        self.app.push_screen(ApolloModeMenu(H.BY_NAME[key]))


class ApolloModeMenu(MenuScreen):
    accent, topic = PURPLE, "apollo"

    def __init__(self, host: H.Host):
        super().__init__()
        self.host = host
        self.crumbs = ["Apollo", "Deploy", host.name]

    def spec(self):
        h = self.host

        def pv(text: str, flag: str, danger: bool = False):
            return lambda: Group(Text(text, RED if danger else FG), Text(""),
                                 PN.cmd(f"apollo-deploy {flag}{h.key}", RED if danger else PURPLE))

        items = [
            Item("dry", I["dry"], "Dry run", "print the disk script, change nothing", "", PURPLE,
                 preview=pv("Prints what disko would do to its disks. Touches nothing.", "--dry-run ")),
            Item("vm", I["vm"], "VM test", "apply the layout in a throwaway VM", "", PURPLE,
                 preview=pv("Builds a VM with the same disk layout and installs into that — proves the config "
                            "boots before any real disk is touched.", "--vm-test ")),
            Item("install", I["warn"], "INSTALL", f"erase its disks, install {h.name}", Text(f"you type {h.name}", RED), RED,
                 gap_before=True, preview=pv(f"Erases every disk disko names on the booted machine and installs "
                                             f"{h.name}. You'll be asked to type {h.name} first.", "", True)),
        ]
        return [Text.assemble(("apollo-deploy ", DIM), h.key, (" → the machine booted from the stick", DIM))], self.tail(items)

    def pick(self, key: str) -> None:
        flag = {"dry": ["--dry-run"], "vm": ["--vm-test"], "install": []}[key]
        self.app.run_outside(["apollo-deploy", *flag, self.host.key], f"Apollo · {key} · {self.host.key}")


class HelpMenu(MenuScreen):
    accent, crumbs, topic = GREEN, ["Help"], "basics"

    def spec(self):
        descs = {"basics": "the home screen, the keys, the colours", "rebuild": "switch · boot · build · other host",
                 "remote": "deploying to the other machines", "utils": "sync · update · garbage collect · check",
                 "apollo": "the deployer USB", "machines": "who's who, and how each is deployed",
                 "cli": "the same jobs without the menus", "words": "generation, profile, closure, inputs…"}
        items = [Item(k, icon, title, descs[k], "", accent if k not in ("basics", "machines", "cli", "words") else FG,
                      preview=lambda k=k: PN.pv_help_page(k))
                 for k, (title, accent, icon, _) in HELP.PAGES.items()]
        items.append(Item("back", I_BACK, "Back", "", Text("esc", DIM), DIM, gap_before=True))
        return [Text("what everything in system-rebuild does — pick a topic", DIM)], items

    def pick(self, key: str) -> None:
        self.app.push_screen(HelpPage(key))


class HelpPage(Screen):
    """One help page, scrollable. esc back, q quit."""

    def __init__(self, topic: str):
        super().__init__()
        self.topic = topic

    def compose(self) -> ComposeResult:
        title, accent, icon, blocks = HELP.PAGES[self.topic]
        yield Crumbs(["Help", title], accent)
        with VerticalScroll(id="helpbody"):
            yield Static(self.page(accent, blocks), id="page")
        yield Hints()

    def on_mount(self) -> None:
        self.query_one(Hints).keys = (("↑↓", "scroll"), ("esc", "back"), ("q", "quit"))
        body = self.query_one("#helpbody")
        body.focus()
        fade_in(body, 0.2)
        slide(body, (4, 0))

    @staticmethod
    def page(accent: str, blocks) -> Group:
        parts, table = [], None

        def flush():
            nonlocal table
            if table is not None:
                parts.append(table)
                parts.append(Text(""))
                table = None

        for b in blocks:
            kind = b[0]
            if kind in ("item", "key"):
                if table is None:
                    table = Table.grid(padding=(0 if kind == "key" else 1, 2))
                    table.add_column(width=17, no_wrap=True)
                    table.add_column(ratio=1)
                table.add_row(Text(b[1], f"bold {accent}"), Text(b[2], FG))
                continue
            flush()
            if kind == "head":
                parts.append(Text.assemble("\n", ("◆ ", accent), (b[1], f"bold {accent}")))
            elif kind == "text":
                parts.append(Text(b[1], FG))
            elif kind == "note":
                parts.append(Text(b[1], DIM))
            elif kind == "cmd":
                parts.append(Text.assemble(("$ ", DIM), (b[1], accent), ("\n    " + b[2], FG)))
            parts.append(Text(""))
        flush()
        return Group(*parts)

    def on_key(self, event: events.Key) -> None:
        if event.key in ("escape", "left", "h", "enter"):
            self.app.pop_screen()
        elif event.key == "q":
            self.app.exit()
        else:
            return
        event.stop()


class HistoryScreen(Screen):
    """Every job the app has run, newest first, and how long each machine's
    rebuilds have been taking."""

    def compose(self) -> ComposeResult:
        yield Crumbs(["Utilities", "History"], YELLOW, HIST.path().as_posix().replace(os.path.expanduser("~"), "~"))
        with VerticalScroll(id="helpbody"):
            yield Static(self.page(), id="page")
        yield Hints()

    def on_mount(self) -> None:
        self.query_one(Hints).keys = (("↑↓", "scroll"), ("esc", "back"), ("q", "quit"))
        body = self.query_one("#helpbody")
        body.focus()
        fade_in(body, 0.2)
        slide(body, (4, 0))

    @staticmethod
    def page() -> Group:
        runs = HIST.recent(200)
        if not runs:
            return Group(Text("Nothing yet. Every job the app runs — rebuilds, syncs, updates, garbage collection — "
                              "lands here with how it went and how long it took.", DIM))
        parts: list = [Text.assemble(("◆ ", YELLOW), ("Rebuild times", f"bold {YELLOW}")), Text("")]
        t = Table.grid(padding=(0, 2))
        for _ in range(4):
            t.add_column(no_wrap=True)
        for h in H.HOSTS:
            d = HIST.durations(h.name, 30)
            if d:
                t.add_row(Text(f"{h.icon}  {h.name}", f"bold {FG}"), sparkline(d),
                          Text(f"usually {P.duration(HIST.typical(h.name) or 0)}", FG),
                          Text(f"fastest {P.duration(min(d))} · slowest {P.duration(max(d))}", DIM))
        parts += [t, Text(""), Text.assemble(("◆ ", YELLOW), ("Runs", f"bold {YELLOW}")), Text("")]
        r = Table.grid(padding=(0, 2))
        for _ in range(5):
            r.add_column(no_wrap=True)
        day = ""
        for run in runs:
            d = time.strftime("%a %d %b", time.localtime(run.t))
            if d != day:
                day = d
                r.add_row(Text(d, f"bold {DIM}"), Text(""), Text(""), Text(""), Text(""))
            r.add_row(Text(time.strftime("  %H:%M", time.localtime(run.t)), DIM),
                      Text("✔" if run.ok else "✘", f"bold {GREEN if run.ok else RED}"),
                      Text(f"{run.kind:<7}", FG), Text(run.host or "—", f"bold {FG}"),
                      Text.assemble((run.result, FG if run.ok else RED), (f"  {P.duration(run.took)}" if run.took >= 1 else "", DIM)))
        parts.append(r)
        return Group(*parts)

    def on_key(self, event: events.Key) -> None:
        if event.key in ("escape", "left", "h", "enter"):
            self.app.pop_screen()
        elif event.key == "q":
            self.app.exit()
        else:
            return
        event.stop()


# ── a job ─────────────────────────────────────────────────────────────────────
class Banner(Widget):
    """ SWITCH   Asgard  → rock@asgard              ⏱ 1:23 · usually ~3m · rock-Asgard """

    DEFAULT_CSS = "Banner { height: 2; padding: 1 2 0 2; }"

    def __init__(self, **kw):
        super().__init__(**kw)
        self.parts = ("", "", "", "", AQUA)
        self.t0: float | None = None
        self.t_end: float | None = None
        self.usual: float | None = None

    def set(self, tag: str, title: str, sub: str, right: str, accent: str, usual: float | None = None) -> None:
        self.parts = (tag, title, sub, right, accent)
        self.t0, self.usual = time.monotonic(), usual
        self.refresh()

    def on_mount(self) -> None:
        self.set_interval(0.5, self.refresh)

    def render(self) -> Text:
        tag, title, sub, right, accent = self.parts
        if not tag:
            return Text.assemble((f"{I_NIX}  ", BLUE), gradient_text("D O T S", bold=True))
        t = Text.assemble(pill(f" {tag} ", BG, accent), "  ", (title, f"bold {FG}"), "  ", (sub, DIM))
        r = Text()
        if self.t0 is not None:
            el = (self.t_end or time.monotonic()) - self.t0
            r.append(f"{PN_CLOCK} {clock(el)}", f"bold {FG}" if self.t_end is None else DIM)
            if self.usual and self.t_end is None:
                left = self.usual - el
                r.append(f"  · usually {P.duration(self.usual)}" if left > 0 else "  · longer than usual", DIM)
            r.append("   ")
        r.append(right, PURPLE)
        pad = max(2, self.size.width - t.cell_len - r.cell_len)
        t.append(" " * pad)
        t.append_text(r)
        return t


PN_CLOCK = ""


class JobScreen(Screen):
    """Where a job runs: its banner, a progress rail, the stage chips, and a
    journal it writes into — sections, live views, logs, and finally a card."""

    def __init__(self, fn: Job):
        super().__init__()
        self.fn = fn
        self.cancellable = True
        self.finished = False
        self.next: Job | None = None
        self.stages: Stages | None = None
        self.pty: PtyRun | None = None
        self.try_anyway: asyncio.Event | None = None
        self.nixlog = None
        self.kind, self.host, self.tag, self.title = "", "", "", ""
        self.stats: dict = {}
        self.outcome: tuple[bool, str] | None = None
        self.accent = AQUA

    def compose(self) -> ComposeResult:
        yield Banner(id="banner")
        yield Rail(self.progress, id="rail")
        yield Vertical(id="stagebox")
        yield VerticalScroll(id="journal")
        yield Hints()

    def on_mount(self) -> None:
        self.journal = self.query_one("#journal", VerticalScroll)
        self.hints(("esc", "stop"), ("q", "quit"))
        self.t_start, self.wall_start = time.monotonic(), time.time()
        self.worker = self.run_worker(self._go(), exclusive=True)

    def hints(self, *keys) -> None:
        for h in self.query(Hints):          # none left if the app is closing under us
            h.keys = keys

    def progress(self) -> tuple[float, str]:
        """How far the whole job is: done stages, plus the build's own
        fraction while it builds (nixmon knows), for the rail."""
        st = self.stages
        if self.finished:
            return 1.0, "done" if self.outcome and self.outcome[0] else "failed"
        if not st:
            return 0.0, "running"
        n = len(st.names)
        done = sum(1 for s in st.state if s in ("done", "skipped"))
        part = 0.0
        run = st.running()
        if run == "Build" and self.nixlog is not None:
            part = self.nixlog.fraction() * 0.95
        elif run:
            part = 0.3
        return min(1.0, (done + part) / n), "running"

    async def _go(self) -> None:
        good = False
        try:
            good = await self.fn(self)
        except asyncio.CancelledError:
            if self.pty:
                self.pty.stop()
            if not self.is_attached:             # the app is closing: nothing to draw on
                self._record(False, "stopped")
                return
            self.card(False, "Stopped", [("", "You stopped it. A build that didn't finish activated nothing.")])
        except Exception as e:                   # show it rather than crash out of the terminal
            self.card(False, "Something went wrong", [("error", f"{type(e).__name__}: {e}"),
                                                      ("where", traceback.format_exc().strip().splitlines()[-3].strip())])
        self.finished = True
        took = time.monotonic() - self.t_start
        if self.stages:
            for i, st in enumerate(self.stages.state):
                if st == "running":
                    self.stages.set(i, "failed" if not good else "done")
            self.stages.stop()
        banner = self.query_one(Banner)
        banner.t_end = time.monotonic()
        title = self.outcome[1] if self.outcome else ("done" if good else "failed")
        self._record(good, title)
        self.app.set_title(f"{'✔' if good else '✘'} {title} — system-rebuild")
        if took >= 15:
            self.app.alert(f"{'✔' if good else '✘'} {title}", f"took {P.duration(took)}", good)
        self.hints(("⏎", "back to the menu"), ("q", "quit"))
        self.app.refresh_state()
        if good and self.next:
            fn, self.next = self.next, None
            self.app.push_screen(JobScreen(fn))

    def _record(self, good: bool, result: str) -> None:
        if not self.kind:
            return
        s = self.stats
        HIST.record(HIST.Run(kind=self.kind, host=self.host, ok=good, t=self.wall_start,
                             took=round(time.monotonic() - self.t_start, 1), build=round(s.get("build", 0), 1),
                             result=result, closure=s.get("closure") or 0, changed=s.get("changed", 0),
                             built=s.get("built", 0)))

    # what jobs call ───────────────────────────────────────────────────────────
    def begin(self, stages: list[str], accent: str, tag: str, title: str, sub: str, right: str,
              kind: str = "", host: str = "") -> None:
        self.accent, self.kind, self.host, self.tag, self.title = accent, kind, host, tag, title
        usual = HIST.typical(host, (kind,)) if host and kind else None
        self.query_one(Banner).set(tag, title, sub, right, accent, usual)
        self.stages = Stages(stages, accent)
        self.query_one("#stagebox").mount(self.stages)
        self.app.set_title(f"{tag} {title} — system-rebuild")

    def stage(self, name: str, state: str) -> None:
        if self.stages and name in self.stages.names:
            self.stages.set(self.stages.names.index(name), state)
            if state == "running":
                self.app.set_title(f"⋯ {self.tag} {self.title} · {name} — system-rebuild")

    async def add(self, widget: Widget) -> Widget:
        await self.journal.mount(widget)
        self.follow()
        return widget

    async def section(self, title: str, accent: str, icon: str = "") -> Section:
        return await self.add(Section(title, accent, icon))

    def follow(self) -> None:
        self.call_after_refresh(self.journal.scroll_end, animate=False)

    async def spin_line(self, sec: Section, text: str) -> SpinLine:
        line = SpinLine(text)
        await sec.mount(line)
        return line

    async def build(self, sec: Section, argv: list[str]) -> tuple[int, list[str]]:
        t0 = time.monotonic()
        if J.nix_build is None:                  # no live view: the plain log
            rc = await self.run(sec, argv + ["-L"])
            self.stats["build"] = time.monotonic() - t0
            return rc, []
        log = J.NixLog()
        self.nixlog = log
        mon = J.BuildMonitor(log)
        await sec.mount(mon)
        self.follow()
        follow = self.set_interval(0.5, self.follow)
        try:
            rc, out = await J.nix_build(argv, log)
        finally:
            follow.stop()
        mon.finish(rc == 0)
        self.stats.update(build=time.monotonic() - t0, built=log.builds_done, fetched=log.transfers_done,
                          fetched_bytes=log.bytes_done)
        self.follow()
        return rc, out

    async def run(self, sec: Section, argv: list[str], where: str = "") -> int:
        log = RichLog(max_lines=5000, wrap=False, markup=False, highlight=False, classes="log")
        part = Static("", classes="partial")
        await sec.mount(log)
        await sec.mount(part)
        self.follow()

        def line(text: str) -> None:
            if text.strip():
                log.write(Text.from_ansi(text))
                self.follow()

        async def ask(kind: str, text: str):
            return await self.ask(kind, text, where)

        self.pty = PtyRun(argv, on_line=line, on_partial=lambda t: part.update(Text.from_ansi(t, style=DIM)),
                          ask=ask, cols=max(60, self.size.width - 10))
        try:
            rc = await self.pty.run()
        finally:
            self.pty = None
            part.display = False
        return rc

    async def diff(self, sec: Section, old: str, new: str) -> None:
        rc, out, err = await P.run(["dix", "--color", "always", old, new], timeout=120)
        lines = [l for l in out.splitlines() if not plain(l).startswith(("<<<", ">>>"))]
        while lines and not plain(lines[0]).strip():
            lines.pop(0)
        if rc != 0 or not lines:
            await sec.mount(info("dix couldn't compare these two systems"))
            return
        counts = diff_counts(lines)
        self.stats["changed"] = sum(counts.values())
        self.stats["diff"] = counts
        await sec.mount(DiffSummary(counts))
        log = RichLog(max_lines=10000, wrap=False, markup=False, highlight=False, classes="log diff")
        await sec.mount(log)
        # Roll the changes in rather than dropping them all at once.
        for i in range(0, len(lines), 6):
            for l in lines[i:i + 6]:
                log.write(Text.from_ansi(l))
            self.follow()
            await asyncio.sleep(1 / 60)

    async def wait_online(self, host: str, label: str = "") -> bool:
        self.app.tailnet = await P.tailnet()
        if self.app.tailnet.peer(host).state == "online":
            return True
        here, label = here_name(), label or host
        sec = await self.section(f"Waiting for {label}", self.accent, I["wait"])
        wait = Waiting(here, label)
        await sec.mount(wait)
        await sec.mount(info(f"{label} is {self.app.tailnet.peer(host).state} on the tailnet — power it on and this "
                             "carries on by itself"))
        self.follow()
        self.try_anyway = asyncio.Event()
        self.hints(("t", "try anyway"), ("esc", "stop"), ("q", "quit"))
        self.app.set_title(f"◌ waiting for {label} — system-rebuild")
        try:
            while not self.try_anyway.is_set():
                if await P.ping(host):
                    wait.done()
                    await sec.mount(J.ok(f"{label} is online"))
                    return True
                try:
                    await asyncio.wait_for(self.try_anyway.wait(), 2.5)
                except asyncio.TimeoutError:
                    pass
            wait.done()
            return True
        finally:
            self.try_anyway = None
            self.hints(("esc", "stop"), ("q", "quit"))

    async def modal(self, screen):
        fut = asyncio.get_running_loop().create_future()
        self.app.push_screen(screen, callback=lambda r: fut.done() or fut.set_result(r))
        return await fut

    async def ask(self, kind: str, text: str, where: str = ""):
        self.app.set_title(f"? {self.title} wants an answer — system-rebuild")
        self.app.alert(f"{self.title} is waiting on you", text)   # a password or a question
        if kind == "password":
            r = await self.modal(PasswordModal(text, f"for the command running on {where}" if where else ""))
        else:
            r = await self.modal(ChoiceModal(text, [("yes", "Yes"), ("no", "No")], self.accent))
        run = self.stages.running() if self.stages else None
        self.app.set_title(f"⋯ {self.tag} {self.title}{f' · {run}' if run else ''} — system-rebuild")
        return r

    async def choose(self, question: str, choices: list[tuple[str, str]], detail: str = "", danger: bool = False):
        return await self.modal(ChoiceModal(question, choices, self.accent, detail, danger))

    async def ask_text(self, prompt: str, default: str = ""):
        return await self.modal(InputModal(prompt, default))

    def next_job(self, fn: Job) -> None:
        self.next = fn

    def card(self, good: bool, title: str, rows, tiles: list[tuple[str, str, str]] | None = None) -> None:
        self.outcome = (good, title)
        if good:
            self.journal.mount(Confetti())
        self.journal.mount(Card(good, title, rows, tiles, self.accent if self.accent != YELLOW else GREEN))
        self.follow()
        self.set_timer(0.5, self.follow)

    # keys ────────────────────────────────────────────────────────────────────
    def on_key(self, event: events.Key) -> None:
        k = event.key
        if self.finished:
            if k in ("enter", "escape", "left", "h"):
                self.app.pop_screen()
            elif k == "q":
                self.app.exit()
            else:
                return
        elif k == "t" and self.try_anyway is not None:
            self.try_anyway.set()
        elif k in ("escape", "q"):
            self.confirm_stop(quit_after=k == "q")
        else:
            return
        event.stop()

    @work
    async def confirm_stop(self, quit_after: bool = False) -> None:
        if not self.cancellable:
            self.notify("It's activating — stopping now could leave the machine half-switched. Let it finish.",
                        severity="warning")
            return
        pick = await self.modal(ChoiceModal("Stop this job?", [("stop", "Stop it"), ("keep", "Keep going")],
                                            self.accent, "Nothing is activated until the build has finished.", danger=True))
        if pick == "stop" and not self.finished:
            # nix takes a moment to wind down (SIGTERM, then it cleans up):
            # say so now rather than look like nothing happened.
            self.cancellable = False
            self.hints(("…", "stopping"),)
            self.notify("Stopping — letting nix wind down…", timeout=3)
            self.worker.cancel()
            if quit_after:
                self.app.exit()


DIX_KIND = {"A": "added", "R": "removed", "U": "upgraded", "D": "downgraded"}


def diff_counts(lines: list[str]) -> dict[str, int]:
    """dix's [A.] / [R.] / [U.] … rows, counted by kind."""
    counts: dict[str, int] = {}
    for l in lines:
        m = re.match(r"\s*\[([A-Z])[^\]]*\]", plain(l))
        if m:
            k = DIX_KIND.get(m.group(1), "changed")
            counts[k] = counts.get(k, 0) + 1
    return counts


class DiffSummary(Static):
    """+6 added  −6 removed  ↑3 upgraded — chips above the full diff."""

    DEFAULT_CSS = "DiffSummary { height: auto; padding: 0 0 0 3; margin: 0 0 1 0; }"

    def __init__(self, counts: dict[str, int]):
        t = Text()
        style = {"added": ("+", GREEN), "removed": ("−", RED), "upgraded": ("↑", AQUA), "downgraded": ("↓", ORANGE),
                 "changed": ("~", YELLOW)}
        for k in ("upgraded", "added", "removed", "downgraded", "changed"):
            n = counts.get(k)
            if n:
                sym, col = style[k]
                t.append_text(pill(f" {sym}{n} {k} ", BG, col))
                t.append("  ")
        if not counts:
            t.append("no package changes — only configuration", DIM)
        super().__init__(t)


def main() -> None:
    try:
        RebuildApp().run()
    finally:
        sys.stdout.write("\x1b[23;0t")      # the terminal's own title back
        sys.stdout.flush()
