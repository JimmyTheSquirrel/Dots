"""system-rebuild — the full-screen app (Textual).

`system-rebuild` with no arguments, in a terminal, opens this. It is the same
control panel the bash menus were — rebuild this machine, deploy the others,
look after the repo and the store, drive the Apollo USB — but it owns the
screen: menus slide in, the status of every machine refreshes by itself, a
build is drawn live (nixmon.py), the package changes roll in, sudo and ssh
questions pop up as boxes, and a job ends in a card (a sparkle when it
worked, a shake when it didn't).

The command-line half — `system-rebuild rock Asgard [--boot|--build]`,
`system-rebuild help`, and the old inline menus as `--classic` — stays in
Resources/Scripts/system-rebuild.sh.

Layout of this package:
  hosts.py   the machines, the flake, generations      probe.py  async lookups
  runner.py  commands in a pty, prompts → modals        jobs.py   what each row does
  ui.py      palette, gradient, widgets, modals         help.py   the help pages
  nixmon.py  the live build view (nix's internal-json log)
"""
from __future__ import annotations

import asyncio
import getpass
import math
import os
import platform
import shutil
import subprocess
import time
import traceback
from typing import Awaitable, Callable

from rich.console import Group
from rich.table import Table
from rich.text import Text
from textual import events, work
from textual.app import App, ComposeResult
from textual.containers import Vertical, VerticalScroll
from textual.screen import Screen
from textual.widget import Widget
from textual.widgets import RichLog, Static

from . import help as HELP
from . import hosts as H
from . import jobs as J
from . import probe as P
from .runner import PtyRun
from .ui import (AQUA, BG, BLUE, DIM, FG, GREEN, LINE, PURPLE, RED, YELLOW, Card, ChoiceModal, Crumbs, Header,
                 Hints, I_BACK, I_NIX, I_QUIT, InputModal, Item, Menu, PasswordModal, Section, SpinLine, Sparkle,
                 Stages, Waiting, gradient_text, mix, pill, slide, spinner)

I = dict(rebuild="", remote="", utils="", apollo="", switch="", boot="",
         build="", other="", ssh="", git="", update="", gc="", check="",
         clone="", deploy="", iso="", key="", dry="", vm="", warn="",
         help="")

Job = Callable[["JobScreen"], Awaitable[bool]]


def dot(state: str, t: float = 0.0) -> Text:
    if state == "online":
        return Text("●", mix(GREEN, "#d5d77a", 0.5 + 0.5 * math.sin(t * 2.4)))   # a slow heartbeat
    if state == "offline":
        return Text("○", RED)
    return Text("◌", DIM)


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


# ── the app ───────────────────────────────────────────────────────────────────
class RebuildApp(App):
    CSS_PATH = "app.tcss"
    TITLE = "system-rebuild"

    def __init__(self) -> None:
        super().__init__()
        self.reload_repo()
        self.tailnet = P.Tailnet()
        self.repo_st: P.RepoStatus | None = None
        self.free: int | None = None
        self.mount_point = ""
        self.has_apollo = shutil.which("apollo-deploy") is not None
        self.probes: dict[str, P.Remote] = {}

    def reload_repo(self) -> None:
        self.repo = H.find_repo()
        if self.repo.path:
            os.chdir(self.repo.path)        # nix build "." and git run from the checkout

    def on_mount(self) -> None:
        self.push_screen(HomeScreen())
        self.refresh_state()
        self.set_interval(30, self.refresh_state)

    @work(exclusive=True, group="state")
    async def refresh_state(self) -> None:
        ts, st, free, mnt = await asyncio.gather(
            P.tailnet(), P.repo_status(self.repo), P.store_free(),
            P.apollo_mount() if self.has_apollo else asyncio.sleep(0, ""))
        self.tailnet, self.repo_st, self.free, self.mount_point = ts, st, free, mnt or ""
        for s in self.screen_stack:
            if isinstance(s, MenuScreen):
                s.rebuild()

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
        self.refresh_state()


# ── menus ─────────────────────────────────────────────────────────────────────
class MenuScreen(Screen):
    """A menu: a top (the home header, or crumbs), notes, rows, key hints.
    Subclasses give spec() → (notes, items) and pick(key)."""

    accent = AQUA
    crumbs: list[str] = []
    topic = "basics"
    home = False

    def top(self) -> ComposeResult:
        yield Crumbs(self.crumbs, self.accent, f"{H.THIS.name if H.THIS else platform.node()} · {getpass.getuser()}")

    def compose(self) -> ComposeResult:
        with Vertical(id="body"):
            yield from self.top()
            yield Static(id="notes")
            yield Menu(id="menu")
        yield Hints()

    def on_mount(self) -> None:
        self.rebuild()
        self.query_one(Menu).focus()
        self.query_one(Hints).keys = (("↑↓", "move"), ("⏎", "pick"), ("esc", "back") if not self.home else ("r", "refresh"),
                                      ("?", "help"), ("q", "quit"))
        body = self.query_one("#body")
        body.styles.opacity = 0.0
        body.styles.animate("opacity", 1.0, duration=0.22)
        if not self.home:
            slide(body, (6, 0))

    def on_screen_resume(self) -> None:
        self.rebuild()
        self.query_one(Menu).focus()

    def rebuild(self) -> None:
        if not self.is_mounted:
            return
        notes, items = self.spec()
        n = self.query_one("#notes", Static)
        n.display = bool(notes)
        n.update(Text("\n").join(notes) if notes else "")
        self.query_one(Menu).set_items(items)

    def spec(self) -> tuple[list[Text], list[Item]]:
        return [], []

    def pick(self, key: str) -> None:
        pass

    def tail(self, items: list[Item]) -> list[Item]:
        items.append(Item("help", I["help"], "Help", "what each of these does", Text("?", DIM), GREEN, gap_before=True))
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
        elif k == "q":
            self.app.exit()
        elif k == "r":
            self.app.refresh_state()
            self.notify("refreshing…", timeout=1.5)
        else:
            return
        event.stop()

    def job(self, fn: Job) -> None:
        self.app.push_screen(JobScreen(fn))


class Machines(Widget):
    """The MACHINES panel: this one, and every other on the tailnet."""

    DEFAULT_CSS = "Machines { height: auto; }"

    def on_mount(self) -> None:
        self.border_title = "MACHINES"
        self.set_interval(1 / 10, self.refresh)    # the online dots breathe

    def get_content_height(self, container, viewport, width) -> int:
        return len(H.HOSTS)

    def render(self) -> Text:
        app, t = self.app, time.monotonic()
        out = Text()
        for n, h in enumerate(H.HOSTS):
            if H.THIS and h.name == H.THIS.name:
                gen, when = H.generation(h.profile)
                glyph, state = Text("◆", AQUA), Text(f"{'this machine':<13}", AQUA)
                detail = Text(f"generation {gen or '?'}" + (f" · built {P.ago(when)}" if when else ""), DIM)
            else:
                p = app.tailnet.peer(h.name)
                glyph = dot(p.state, t + n)
                stick = h.mode == "stick"
                if p.state == "online":
                    state, detail = Text(f"{'booted' if stick else 'online':<13}", GREEN), Text(f"{p.path} · {p.ip}", DIM)
                elif p.state == "offline":
                    state, detail = Text(f"{'not booted' if stick else 'offline':<13}", RED), Text(p.seen_text(), DIM)
                elif p.state == "missing":
                    state, detail = Text(f"{'—':<13}", DIM), Text("not on the tailnet", DIM)
                else:
                    state, detail = Text(f"{'?':<13}", DIM), Text("tailscale unavailable", DIM)
            out.append_text(Text.assemble(" ", glyph, "  ", (h.icon, FG), "  ", (f"{h.name:<9}", f"bold {FG}"), " ",
                                          state, " ", detail))
            if n < len(H.HOSTS) - 1:
                out.append("\n")
        return out


class HomeScreen(MenuScreen):
    accent = AQUA
    home = True

    def top(self) -> ComposeResult:
        yield Header(id="header")
        yield Machines()

    def rebuild(self) -> None:
        if not self.is_mounted:
            return
        app = self.app
        here = H.THIS.name if H.THIS else platform.node()
        ver = H.os_version()
        repo = Text()
        if not app.repo.path:
            repo = Text.assemble((H.DOTS_FLAKE, YELLOW), ("  · no checkout here", DIM))
        elif app.repo_st:
            st = app.repo_st
            repo = Text.assemble((st.branch[:22], BLUE), "  ",
                                 ("✔ clean", GREEN) if not st.dirty else (f"● {st.dirty} changed", YELLOW),
                                 (f"  ↑{st.ahead} ↓{st.behind}", DIM), (f"  · locked {P.ago(H.lock_age(app.repo))}", DIM))
        else:
            repo = Text(f"{spinner()} reading the repo…", DIM)
        self.query_one(Header).lines = (
            Text.assemble(("system-rebuild", f"bold {FG}"), ("  rebuild · deploy · maintain", DIM)),
            Text.assemble((here, f"bold {AQUA}"), (" · ", DIM), getpass.getuser(),
                          (f" · NixOS {ver}" if ver else "", DIM)),
            repo)
        super().rebuild()

    def spec(self):
        app = self.app
        items: list[Item] = []
        if H.THIS:
            items.append(Item("rebuild", I["rebuild"], "Rebuild", f"{H.THIS.name} · this machine",
                              Text("switch · boot · build", DIM), AQUA))
        else:
            items.append(Item("rebuild", I["rebuild"], "Rebuild", "build any host's config here", "", AQUA))
        remotes = Text()
        for h in H.HOSTS:
            if (H.THIS and h.name == H.THIS.name) or h.mode == "stick":
                continue
            remotes.append(f"{h.name} ", DIM)
            remotes.append_text(dot(app.tailnet.peer(h.name).state))
            remotes.append("  ")
        items.append(Item("remote", I["remote"], "Remote", "deploy over the tailnet", remotes, BLUE))
        items.append(Item("utils", I["utils"], "Utilities", "keep the repo and the store tidy",
                          Text("sync · update · gc", DIM), YELLOW))
        if app.has_apollo:
            p = app.tailnet.peer("Apollo")
            items.append(Item("apollo", I["apollo"], "Apollo", "the deployer USB",
                              Text.assemble(("stick ", DIM), dot(p.state), ("  usb ", DIM),
                                            ("✔", GREEN) if app.mount_point else ("–", DIM)), PURPLE))
        items.append(Item("help", I["help"], "Help", "what everything here does", Text("?", DIM), GREEN))
        items.append(Item("quit", I_QUIT, "Quit", "", Text("q", DIM), DIM, gap_before=True))
        return [], items

    def pick(self, key: str) -> None:
        self.app.push_screen({"rebuild": RebuildMenu, "remote": RemoteMenu, "utils": UtilsMenu,
                              "apollo": ApolloMenu, "help": HelpMenu}[key]())


class RebuildMenu(MenuScreen):
    accent, crumbs, topic = AQUA, ["Rebuild"], "rebuild"

    def spec(self):
        notes, items = [], []
        if H.THIS:
            gen, when = H.generation(H.THIS.profile)
            notes.append(Text.assemble(("◆ ", AQUA), (H.THIS.name, f"bold {FG}"),
                                       (f"  {H.THIS.key} · generation {gen or '?'}" + (f", built {P.ago(when)}" if when else ""), DIM)))
            if H.THIS.profile != "system":
                notes.append(Text.assemble(("profile ", DIM), H.THIS.profile, (" · its own entry under GRUB's System Select", DIM)))
            if self.app.repo.flake != ".":
                notes.append(Text.assemble(("! ", YELLOW), ("no ~/Dots here — builds ", DIM), H.DOTS_FLAKE, (" (main)", DIM)))
            items += [
                Item("switch", I["switch"], "Switch", "build · diff · activate now", "", AQUA),
                Item("boot", I["boot"], "Boot", "build · diff · on next boot",
                     Text("next reboot" if H.THIS.profile == "system" else f"GRUB › {H.THIS.name}", DIM), AQUA),
                Item("build", I["build"], "Build", "build · diff · activate nothing",
                     Text("./result" if self.app.repo.path else "", DIM), AQUA),
            ]
        else:
            notes.append(Text.assemble(("! ", YELLOW), platform.node(), (" isn't one of ", DIM),
                                       " ".join(h.name for h in H.HOSTS)))
        items.append(Item("other", I["other"], "Other host", "build another machine's config, deploy nothing", "",
                          AQUA, gap_before=bool(items)))
        return notes, self.tail(items)

    def pick(self, key: str) -> None:
        if key in ("switch", "boot", "build"):
            self.job(lambda j, k=key: J.rebuild(j, H.THIS, k))
        elif key == "other":
            self.app.push_screen(OtherHostMenu())


class OtherHostMenu(MenuScreen):
    accent, crumbs, topic = AQUA, ["Rebuild", "Other host"], "rebuild"

    def spec(self):
        items = [Item(h.name, h.icon, h.name, h.role, Text(h.key, DIM), AQUA)
                 for h in H.HOSTS if not (H.THIS and h.name == H.THIS.name)]
        return [Text("builds the config and diffs it against what that machine runs", DIM)], self.tail(items)

    def pick(self, key: str) -> None:
        self.job(lambda j: J.rebuild(j, H.BY_NAME[key], "build"))


class RemoteMenu(MenuScreen):
    accent, crumbs, topic = BLUE, ["Remote"], "remote"

    def spec(self):
        items = []
        for h in H.HOSTS:
            if (H.THIS and h.name == H.THIS.name) or h.mode == "stick":
                continue
            items.append(Item(h.name, h.icon, h.name, h.role, peer_short(self.app.tailnet.peer(h.name)), BLUE))
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
        if self.asking:
            self.rebuild()
        else:
            self.spin.stop()

    @work(exclusive=True)
    async def probe(self) -> None:
        self.app.probes[self.host.name] = await P.remote_probe(self.host)
        self.asking = False
        self.rebuild()

    def spec(self):
        h, p = self.host, self.app.tailnet.peer(self.host.name)
        notes = [peer_phrase(p)]
        r = self.app.probes.get(h.name)
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
            Item("switch", I["switch"], "Switch", "build here, push, activate now", "", BLUE),
            Item("boot", I["boot"], "Boot", "build here, push, activate on its next reboot", "", BLUE),
            Item("build", I["build"], "Build", "build here and diff — nothing deployed", "", BLUE),
            Item("ssh", I["ssh"], "SSH", f"open a shell on {h.name}", Text(h.target, DIM), BLUE),
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
            items.append(Item("sync", I["git"], "Git sync", "commit · pull --rebase · push", meta, YELLOW))
            items.append(Item("update", I["update"], "Update inputs", "nix flake update + changelog",
                              Text(f"locked {P.ago(H.lock_age(app.repo))}", DIM), YELLOW))
        else:
            items.append(Item("clone", I["clone"], "Get the repo", "clone it to ~/Dots, for sync and update",
                              Text("github", DIM), YELLOW))
        items.append(Item("gc", I["gc"], "Garbage collect", "old generations · store · docker",
                          Text(f"{P.human_bytes(app.free)} free" if app.free else "", DIM), YELLOW))
        items.append(Item("check", I["check"], "Check hosts", "evaluate every host, build nothing",
                          Text(f"{len(H.HOSTS)} hosts", DIM), YELLOW))
        return [], self.tail(items)

    def pick(self, key: str) -> None:
        self.job({"sync": J.sync_repo, "update": J.update_inputs, "clone": J.clone_repo,
                  "gc": J.collect_garbage, "check": J.check_hosts}[key])


class ApolloMenu(MenuScreen):
    accent, crumbs, topic = PURPLE, ["Apollo"], "apollo"

    def spec(self):
        app = self.app
        p = app.tailnet.peer("Apollo")
        stick = {"online": Text.assemble(("● booted", GREEN), (f" · {p.path} · {p.ip}", DIM)),
                 "offline": Text.assemble(("○ not booted", RED), (f" · {p.seen_text()}", DIM))}.get(
                     p.state, Text("◌ never seen on the tailnet", DIM))
        if app.mount_point:
            usb = Text.assemble(("✔ mounted", GREEN), (f" · {app.mount_point}", DIM))
        elif os.path.exists("/dev/disk/by-label/Apollo"):
            usb = Text.assemble(("! plugged in, not mounted", YELLOW), (" · udisksctl mount -b /dev/disk/by-label/Apollo", DIM))
        else:
            usb = Text("– not plugged in", DIM)
        notes = [Text.assemble(("stick ", DIM), stick), Text.assemble(("usb   ", DIM), usb)]
        items = [
            Item("deploy", I["deploy"], "Deploy", "install onto the booted machine", Text("wipes its disks", RED), PURPLE),
            Item("ssh", I["ssh"], "SSH", "connect to the booted stick", Text("apollo-connect", DIM), PURPLE),
            Item("iso", I["iso"], "Build ISO", "build the image, copy it to the stick", Text("apollo-iso", DIM), PURPLE),
            Item("key", I["key"], "Tailnet key", "write the auth key onto the stick", Text("apollo-key", DIM), PURPLE),
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
                items.append(Item(h.name, h.icon, h.name, h.role, Text(f"{h.key} · disko{' + facter' if facter else ''}", DIM), PURPLE))
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
        items = [
            Item("dry", I["dry"], "Dry run", "print the disk script, change nothing", "", PURPLE),
            Item("vm", I["vm"], "VM test", "apply the layout in a throwaway VM", "", PURPLE),
            Item("install", I["warn"], "INSTALL", f"erase its disks, install {h.name}", Text(f"you type {h.name}", RED), RED, gap_before=True),
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
        items = [Item(k, icon, title, descs[k], "", accent if k not in ("basics", "machines", "cli", "words") else FG)
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
        body.styles.opacity = 0.0
        body.styles.animate("opacity", 1.0, duration=0.2)

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


# ── a job ─────────────────────────────────────────────────────────────────────
class Banner(Widget):
    """ SWITCH   Asgard  → rock@asgard                         rock-Asgard """

    DEFAULT_CSS = "Banner { height: 2; padding: 1 2 0 2; }"

    def __init__(self, **kw):
        super().__init__(**kw)
        self.parts = ("", "", "", "", AQUA)

    def set(self, tag: str, title: str, sub: str, right: str, accent: str) -> None:
        self.parts = (tag, title, sub, right, accent)
        self.refresh()

    def render(self) -> Text:
        tag, title, sub, right, accent = self.parts
        if not tag:
            return Text.assemble((f"{I_NIX}  ", BLUE), gradient_text("D O T S", bold=True))
        t = Text.assemble(pill(f" {tag} ", BG, accent), "  ", (title, f"bold {FG}"), "  ", (sub, DIM))
        pad = max(2, self.size.width - t.cell_len - len(right))
        t.append(" " * pad)
        t.append(right, PURPLE)
        return t


class JobScreen(Screen):
    """Where a job runs: its banner, the stage rail, and a journal it writes
    into — sections, live views, logs, and finally a card."""

    def __init__(self, fn: Job):
        super().__init__()
        self.fn = fn
        self.cancellable = True
        self.finished = False
        self.next: Job | None = None
        self.stages: Stages | None = None
        self.pty: PtyRun | None = None
        self.try_anyway: asyncio.Event | None = None

    def compose(self) -> ComposeResult:
        yield Banner(id="banner")
        yield Vertical(id="stagebox")
        yield VerticalScroll(id="journal")
        yield Hints()

    def on_mount(self) -> None:
        self.journal = self.query_one("#journal", VerticalScroll)
        self.hints(("esc", "stop"), ("q", "quit"))
        self.worker = self.run_worker(self._go(), exclusive=True)

    def hints(self, *keys) -> None:
        for h in self.query(Hints):          # none left if the app is closing under us
            h.keys = keys

    async def _go(self) -> None:
        good = False
        try:
            good = await self.fn(self)
        except asyncio.CancelledError:
            if self.pty:
                self.pty.stop()
            if not self.is_attached:             # the app is closing: nothing to draw on
                return
            self.card(False, "Stopped", [("", "You stopped it. A build that didn't finish activated nothing.")])
        except Exception as e:                   # show it rather than crash out of the terminal
            self.card(False, "Something went wrong", [("error", f"{type(e).__name__}: {e}"),
                                                      ("where", traceback.format_exc().strip().splitlines()[-3].strip())])
        self.finished = True
        if self.stages:
            for i, st in enumerate(self.stages.state):
                if st == "running":
                    self.stages.set(i, "failed" if not good else "done")
            self.stages.stop()
        self.hints(("⏎", "back to the menu"), ("q", "quit"))
        self.app.refresh_state()
        if good and self.next:
            fn, self.next = self.next, None
            self.app.push_screen(JobScreen(fn))

    # what jobs call ───────────────────────────────────────────────────────────
    def begin(self, stages: list[str], accent: str, tag: str, title: str, sub: str, right: str) -> None:
        self.accent = accent
        self.query_one(Banner).set(tag, title, sub, right, accent)
        self.stages = Stages(stages, accent)
        self.query_one("#stagebox").mount(self.stages)

    def stage(self, name: str, state: str) -> None:
        if self.stages and name in self.stages.names:
            self.stages.set(self.stages.names.index(name), state)

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
        if J.nix_build is None:                  # no live view: the plain log
            return await self.run(sec, argv + ["-L"]), []
        log = J.NixLog()
        mon = J.BuildMonitor(log)
        await sec.mount(mon)
        self.follow()
        follow = self.set_interval(0.5, self.follow)
        try:
            rc, out = await J.nix_build(argv, log)
        finally:
            follow.stop()
        mon.finish(rc == 0)
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
        lines = [l for l in out.splitlines() if not P_strip(l).startswith(("<<<", ">>>"))]
        if rc != 0 or not lines:
            from .ui import info
            await sec.mount(info("dix couldn't compare these two systems"))
            return
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
        here, label = H.THIS.name if H.THIS else platform.node(), label or host
        sec = await self.section(f"Waiting for {label}", self.accent, "")
        wait = Waiting(here, label)
        await sec.mount(wait)
        from .ui import info
        await sec.mount(info(f"{label} is {self.app.tailnet.peer(host).state} on the tailnet — power it on and this "
                             "carries on by itself"))
        self.follow()
        self.try_anyway = asyncio.Event()
        self.hints(("t", "try anyway"), ("esc", "stop"), ("q", "quit"))
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
        if kind == "password":
            return await self.modal(PasswordModal(text, f"for the command running on {where}" if where else ""))
        pick = await self.modal(ChoiceModal(text, [("yes", "Yes"), ("no", "No")], self.accent))
        return None if pick is None else pick

    async def choose(self, question: str, choices: list[tuple[str, str]], detail: str = "", danger: bool = False):
        return await self.modal(ChoiceModal(question, choices, self.accent, detail, danger))

    async def ask_text(self, prompt: str, default: str = ""):
        return await self.modal(InputModal(prompt, default))

    def next_job(self, fn: Job) -> None:
        self.next = fn

    def card(self, good: bool, title: str, rows) -> None:
        if good:
            self.journal.mount(Sparkle())
        self.journal.mount(Card(good, title, rows))
        self.follow()

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


def P_strip(s: str) -> str:
    from .runner import plain
    return plain(s)


def main() -> None:
    RebuildApp().run()
