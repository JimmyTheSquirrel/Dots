"""Running a command inside the app: a pseudo-terminal we own.

nixos-rebuild, sudo and ssh all want a terminal — sudo and nixos-rebuild's
--ask-sudo-password read the password from /dev/tty, ssh asks "yes/no" about
a new host key there. The app has the real terminal in full-screen mode, so
each command gets a pty of its own instead, made its CONTROLLING terminal (a
new session + TIOCSCTTY), which is where /dev/tty points. Its output streams
into the job's log; when it stops at something that looks like a prompt
("[sudo] password for rock:", "(yes/no/[fingerprint])?"), the app shows a
modal, and the answer is typed into the pty. The password is never echoed,
logged or kept.
"""
from __future__ import annotations

import asyncio
import codecs
import fcntl
import os
import pty
import re
import signal
import struct
import termios
from typing import Awaitable, Callable

# CSI sequences: keep colour (…m), drop the rest (cursor moves, erase line…).
CSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)")
OTHER_ESC = re.compile(r"\x1b[@-Z\\-_]")

PROMPTS = [
    ("password", re.compile(r"(?i)(password|passphrase)[^\n:]*:\s*$")),
    ("yesno", re.compile(r"\(yes/no[^)]*\)\?\s*$")),
    ("yesno", re.compile(r"\[[yY]/[nN]\]\s*[:?]?\s*$")),
]

Ask = Callable[[str, str], Awaitable["str | None"]]


def clean(text: str) -> str:
    """Strip every escape but SGR colour."""
    text = OSC.sub("", text)
    text = CSI.sub(lambda m: m.group(0) if m.group(0).endswith("m") else "", text)
    return OTHER_ESC.sub("", text)


def plain(text: str) -> str:
    return CSI.sub("", OSC.sub("", text))


class PtyRun:
    """argv in a pty. on_line(text) for every finished line (colour kept),
    on_partial(text) for the line being written (progress, a prompt), ask(kind,
    prompt) for a prompt — return the answer, or None to stop the command."""

    def __init__(self, argv: list[str], *, on_line: Callable[[str], None],
                 on_partial: Callable[[str], None] | None = None, ask: Ask | None = None,
                 cols: int = 100, rows: int = 30, env: dict | None = None, cwd=None):
        self.argv, self.on_line, self.on_partial, self.ask = argv, on_line, on_partial, ask
        self.cols, self.rows, self.env, self.cwd = cols, rows, env, cwd
        self.proc: asyncio.subprocess.Process | None = None
        self.master = -1
        self.partial = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.prompt_timer: asyncio.TimerHandle | None = None
        self.asking = False
        self.closed = asyncio.Event()

    async def run(self) -> int:
        loop = asyncio.get_running_loop()
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", self.rows, self.cols, 0, 0))
        attrs = termios.tcgetattr(slave)
        attrs[1] &= ~termios.ONLCR                       # \n stays \n
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        env = dict(os.environ if self.env is None else self.env)
        env.setdefault("TERM", "xterm-256color")
        env["COLUMNS"], env["LINES"] = str(self.cols), str(self.rows)

        def ctty():                                      # in the child, after setsid
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        try:
            self.proc = await asyncio.create_subprocess_exec(
                *self.argv, stdin=slave, stdout=slave, stderr=slave, cwd=self.cwd, env=env,
                start_new_session=True, preexec_fn=ctty)
        except FileNotFoundError:
            os.close(master)
            os.close(slave)
            self.on_line(f"{self.argv[0]}: not found")
            return 127
        os.close(slave)
        self.master = master
        os.set_blocking(master, False)
        loop.add_reader(master, self._readable)
        try:
            rc = await self.proc.wait()
            # The pty may still hold output the reader hasn't taken yet.
            await asyncio.wait_for(self.closed.wait(), 2)
        except asyncio.TimeoutError:
            pass
        except asyncio.CancelledError:
            self.stop()
            raise
        finally:
            self._close()
        if self.partial.strip():
            self.on_line(self.partial)
            self.partial = ""
        return rc if rc is not None else 1

    def stop(self) -> None:
        """Hang up on it, like closing its terminal."""
        if self.proc and self.proc.returncode is None:
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def write(self, text: str) -> None:
        if self.master >= 0:
            os.write(self.master, text.encode())

    # ── output ────────────────────────────────────────────────────────────────
    def _close(self) -> None:
        if self.master >= 0:
            try:
                asyncio.get_running_loop().remove_reader(self.master)
            except (RuntimeError, ValueError):
                pass
            os.close(self.master)
            self.master = -1
        self.closed.set()

    def _readable(self) -> None:
        try:
            data = os.read(self.master, 65536)
        except BlockingIOError:
            return
        except OSError:                                  # EIO: the child closed its end
            data = b""
        if not data:
            asyncio.get_running_loop().remove_reader(self.master)
            self.closed.set()
            return
        self._feed(self.decoder.decode(data))

    def _feed(self, text: str) -> None:
        text = clean(text).replace("\r\n", "\n")
        for ch_line in re.split(r"(\n|\r)", text):
            if ch_line == "\n":
                self.on_line(self.partial)
                self.partial = ""
            elif ch_line == "\r":
                self.partial = ""                        # a progress line redrawing itself
            else:
                self.partial += ch_line
        if self.on_partial:
            self.on_partial(self.partial)
        self._watch_prompt()

    # ── prompts ───────────────────────────────────────────────────────────────
    def _watch_prompt(self) -> None:
        if self.prompt_timer:
            self.prompt_timer.cancel()
            self.prompt_timer = None
        if self.ask is None or self.asking or not self.partial:
            return
        text = plain(self.partial)
        for kind, rx in PROMPTS:
            if rx.search(text):
                # Only once it has gone quiet: a prompt is the last thing written.
                self.prompt_timer = asyncio.get_running_loop().call_later(
                    0.15, lambda k=kind, t=text: asyncio.ensure_future(self._prompt(k, t)))
                return

    async def _prompt(self, kind: str, text: str) -> None:
        self.asking = True
        try:
            answer = await self.ask(kind, text.strip())
        finally:
            self.asking = False
        if answer is None:
            self.on_line(plain(self.partial) + "  (cancelled)")
            self.partial = ""
            self.stop()
            return
        if kind == "password":
            # Echo is off for a password: say it was typed, without it. The
            # newline the program prints after it ends this line.
            self.partial = plain(self.partial) + "  ••••••"
        self.write(answer + "\n")              # anything else, the pty echoes
