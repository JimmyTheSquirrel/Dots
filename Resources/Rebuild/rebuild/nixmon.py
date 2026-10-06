"""nixmon — a live, animated view of a `nix build`, in place of nom.

Three pieces:

* ``NixLog``  — a pure parser + state machine for nix's machine-readable log
  (``--log-format internal-json -v``). No Textual; feed it every stderr line.
* ``BuildMonitor`` — a Textual widget that draws a ``NixLog`` at ~12 fps while
  the build runs, and a still summary (or the failure) once ``finish()`` is
  called.
* ``nix_build()`` — runs ``nix build …`` as an asyncio subprocess, feeding its
  stderr to a ``NixLog`` line by line. Cancel the awaiting task to stop nix.

What nix actually emits (checked against nix 2.34, `-v`):

* ``start``  — ``{"action":"start","id","level","parent","text","type","fields"?}``
    * 105 Build:        fields ``[drvPath, machine ("" = local), curRound, nrRounds]``
    * 100 CopyPath:     fields ``[storePath, from, to]`` — one per substituted path
    * 101 FileTransfer: fields ``[url]``; ``.narinfo`` lookups (cache queries) and
      the ``/nar/…`` download itself, whose parent is the CopyPath
    * 108 Substitute:   fields ``[storePath, cacheUri]`` — parent of the CopyPath
    * 102 Realise / 103 CopyPaths / 104 Builds: the three top-level counters
    * 109 QueryPathInfo: fields ``[storePath, cacheUri]`` — "is it in the cache?"
    * 0 (unknown): free text, e.g. ``copying "/home/user/Dots" to the store``
* ``result``
    * 101 BuildLogLine ``[line]``, 107 PostBuildLogLine ``[line]``
    * 104 SetPhase ``[phase]`` — only stdenv builds (runCommand has none)
    * 105 Progress ``[done, expected, running, failed]``:
        - on 104 Builds: counts of builds. ``expected`` is NOT exact (it counts
          goals and runs one high), so the "these N derivations will be built:"
          message is the source of truth for the total.
        - on 103 CopyPaths: counts of substituted paths.
        - on 101 FileTransfer: compressed bytes (``expected`` is 0 until known).
        - on 100 CopyPath: NAR (unpacked) bytes.
      This is by far the most frequent line (~40k for a 45 MB fetch).
    * 106 SetExpected ``[activityType, n]`` on Realise: 101 → total download
      bytes, 100 → total unpacked bytes. Grows as substitution goals start.
* ``msg`` — ``level`` 0 error, 1 warning, 3 info, 4 talkative. Level 4 is mostly
  ``evaluating file '…'`` (thousands while a NixOS config evaluates). Errors
  carry ANSI colour, may span lines, and have a ``raw_msg`` without the
  "error:" prefix / trace. ``builtins.trace`` is level 0 too ("trace: …").
  nix 2.34's build-failure message no longer embeds the log tail
  ("Cannot build '…drv'.\\n Reason: builder failed with exit code 1."), so the
  failing build's log comes from the BuildLogLine results we kept.
* A Build's Builds-progress ``done`` (or ``failed``) is bumped *before* its
  ``stop`` arrives; builds killed because another one failed stop with neither
  bumped — that's how a stop is classified as built / failed / cancelled.
"""

from __future__ import annotations

import asyncio
import json
import math
import re
import signal
import time
from collections import deque
from functools import lru_cache

from rich.cells import cell_len
from rich.style import Style
from rich.text import Text
from textual.widget import Widget

__all__ = ["NixLog", "BuildMonitor", "nix_build", "Build", "Transfer"]

# ── nix activity / result types (nix/src/libutil/logging.hh) ──────────────────
ACT_UNKNOWN = 0
ACT_COPY_PATH = 100
ACT_FILE_TRANSFER = 101
ACT_REALISE = 102
ACT_COPY_PATHS = 103
ACT_BUILDS = 104
ACT_BUILD = 105
ACT_OPTIMISE = 106
ACT_VERIFY = 107
ACT_SUBSTITUTE = 108
ACT_QUERY_PATH_INFO = 109
ACT_POST_BUILD_HOOK = 110
ACT_BUILD_WAITING = 111
ACT_FETCH_TREE = 112

RES_FILE_LINKED = 100
RES_BUILD_LOG_LINE = 101
RES_SET_PHASE = 104
RES_PROGRESS = 105
RES_SET_EXPECTED = 106
RES_POST_BUILD_LOG_LINE = 107
RES_FETCH_STATUS = 108

# Starting any of these means evaluation is over and the build proper has begun.
_WORK_TYPES = frozenset(
    {ACT_COPY_PATH, ACT_REALISE, ACT_COPY_PATHS, ACT_BUILDS, ACT_BUILD, ACT_SUBSTITUTE}
)
# Activities whose text is worth showing while evaluating.
_DETAIL_TYPES = frozenset({ACT_UNKNOWN, ACT_FETCH_TREE, ACT_FILE_TRANSFER, ACT_QUERY_PATH_INFO})

LOG_KEEP = 200          # log lines kept per build (for failed_log)
_BIN = 0.5              # throughput histogram bin, seconds

# ── text helpers ──────────────────────────────────────────────────────────────
_ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[@-_]")
_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
_STORE_NAME = re.compile(r"^/nix/store/[0-9a-z]{32}-(.+?)(?:\.drv)?$")
_STORE_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-([^\s'\"`,;:()«»]+)")
_VERSION = re.compile(r"^(.+?)-(\d.*)$")
_PLAN = re.compile(
    r"^(?:these (\d+)|this) (derivations?|paths?) will be (built|fetched)"
    r"(?: \(([\d.]+) (B|KiB|MiB|GiB|TiB) download, ([\d.]+) (B|KiB|MiB|GiB|TiB) unpacked\))?:"
)
_UNITS = {"B": 1, "KiB": 1 << 10, "MiB": 1 << 20, "GiB": 1 << 30, "TiB": 1 << 40}
_PROGRESS_FAST = re.compile(
    r'@nix \{"action":"result","fields":\[(\d+),(\d+),(\d+),(\d+)\],"id":(\d+),"type":105\}\s*$'
)
_EVAL_FAST = '@nix {"action":"msg","level":4,"msg":"evaluating file '
_FAILED_DRV = (
    re.compile(r"builder for '(/nix/store/[^']+\.drv)' failed"),
    re.compile(r"Cannot build '(/nix/store/[^']+\.drv)'\.\s*Reason: (?!\d+ dependenc)"),
    re.compile(r"hash mismatch in fixed-output derivation '(/nix/store/[^']+\.drv)'"),
)
_DEP_FAILED = re.compile(r"dependenc(?:y|ies) failed|dependencies of derivation")


def strip_ansi(s: str) -> str:
    """Drop escape sequences and control characters (tabs become spaces)."""
    if "\x1b" in s:
        s = _ANSI.sub("", s)
    if "\t" in s:
        s = s.expandtabs(4)
    return _CTRL.sub("", s)


def clean_log_line(s: str) -> str:
    """One build-log line as it would look on screen: last \\r-overwrite wins."""
    if len(s) > 4000:
        s = s[:4000]
    s = s.rstrip("\r\n")
    if "\r" in s:
        s = s.rsplit("\r", 1)[-1]
    return strip_ansi(s).rstrip()


def store_name(path: str) -> str:
    """``/nix/store/<hash>-glance-assets.drv`` → ``glance-assets``."""
    m = _STORE_NAME.match(path or "")
    return m.group(1) if m else (path or "").rsplit("/", 1)[-1]


def split_version(name: str) -> tuple[str, str]:
    """``pandoc-cli-3.7.0.2`` → (``pandoc-cli``, ``3.7.0.2``) — like parseDrvName."""
    m = _VERSION.match(name)
    return (m.group(1), m.group(2)) if m else (name, "")


_SOURCE_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-source/")


def shorten_store_paths(s: str) -> str:
    """Replace ``/nix/store/<hash>-name(.drv)`` with just ``name`` (and drop
    a flake's ``/nix/store/<hash>-source/`` prefix entirely)."""
    if "/nix/store/" not in s:
        return s
    return _STORE_PATH.sub(_short_store_path, _SOURCE_PATH.sub("", s))


def _short_store_path(m: re.Match) -> str:
    name = m.group(1)
    tail = ""
    while name.endswith("."):           # a full stop after the path
        name, tail = name[:-1], "." + tail
    if name.endswith(".drv"):
        name = name[:-4]
    return name + tail


_FLAKE_REF = re.compile(r"«([^»?]*?)(?:/[0-9a-f]{40})?(?:\?[^»]*)?»")


def _tidy(text: str) -> str:
    """Activity text for humans: no escapes, store hashes or pinned revs."""
    return shorten_store_paths(_FLAKE_REF.sub(r"\1", strip_ansi(text)))


def fmt_bytes(n: float, unit_of: float | None = None) -> str:
    """Decimal units: 512 B, 12.3 kB, 45.2 MB, 1.23 GB."""
    ref = n if unit_of is None else unit_of
    for div, u in ((1e9, "GB"), (1e6, "MB"), (1e3, "kB")):
        if ref >= div * 0.9995:
            v = n / div
            if v >= 99.95:
                return f"{v:.0f} {u}"
            return f"{v:.2f} {u}" if u == "GB" and v < 9.995 else f"{v:.1f} {u}"
    return f"{n:.0f} B"


def fmt_pair(done: float, total: float) -> str:
    """``45.2/120 MB`` — both numbers in the unit of the total."""
    t = fmt_bytes(total)
    num, unit = t.rsplit(" ", 1)
    d = fmt_bytes(done, unit_of=total).rsplit(" ", 1)[0]
    return f"{d}/{num} {unit}"


def fmt_dur(s: float) -> str:
    s = max(0.0, s)
    if s < 10:
        return f"{s:.1f}s"
    if s < 60:
        return f"{s:.0f}s"
    if s < 3600:
        m, sec = divmod(int(s), 60)
        return f"{m}m{sec:02d}s"
    h, rem = divmod(int(s), 3600)
    return f"{h}h{rem // 60:02d}m"


_PHASE_LABEL = {
    "unpackPhase": "unpack",
    "patchPhase": "patch",
    "updateAutotoolsGnuConfigScriptsPhase": "autotools",
    "autoreconfPhase": "autoreconf",
    "configurePhase": "configure",
    "buildPhase": "build",
    "checkPhase": "check",
    "installPhase": "install",
    "fixupPhase": "fixup",
    "installCheckPhase": "check",
    "distPhase": "dist",
}


def phase_label(phase: str | None) -> str:
    """``buildPhase`` → ``build``; unknown phases are shortened the same way."""
    if not phase:
        return ""
    if phase in _PHASE_LABEL:
        return _PHASE_LABEL[phase]
    p = phase[:-5] if phase.endswith("Phase") else phase
    return p[:10]


# ── state objects ─────────────────────────────────────────────────────────────
class Build:
    """One derivation being built (a nix Build activity)."""

    __slots__ = ("id", "drv", "name", "pname", "version", "machine", "started",
                 "ended", "phase", "last_line", "lines", "status", "nlines")

    def __init__(self, aid: int, drv: str, machine: str, started: float):
        self.id = aid
        self.drv = drv
        self.name = store_name(drv)
        self.pname, self.version = split_version(self.name)
        self.machine = machine or ""
        self.started = started
        self.ended: float | None = None
        self.phase: str | None = None
        self.last_line = ""
        self.lines: deque[str] | None = deque(maxlen=LOG_KEEP)
        self.nlines = 0
        # running → ok | failed | cancelled ("stopped" while undecided)
        self.status = "running"

    kind = "build"

    @property
    def phase_label(self) -> str:
        return phase_label(self.phase)

    def duration(self, now: float) -> float:
        return (self.ended if self.ended is not None else now) - self.started

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<Build {self.name} {self.status} phase={self.phase}>"


class Transfer:
    """A path being fetched (CopyPath from a cache), or a bare download."""

    __slots__ = ("id", "name", "pname", "version", "started", "ended", "status",
                 "kind", "dl", "nar_done", "nar_expected", "source")

    def __init__(self, aid: int, name: str, started: float, kind: str = "fetch", source: str = ""):
        self.id = aid
        self.name = name
        self.pname, self.version = split_version(name)
        self.started = started
        self.ended: float | None = None
        self.status = "running"
        self.kind = kind            # "fetch" (substitution) | "download" (bare URL)
        self.dl: _Act | None = None  # the FileTransfer carrying the bytes
        self.nar_done = 0
        self.nar_expected = 0
        self.source = source

    def progress(self) -> tuple[int, int]:
        """(done, expected) bytes — download bytes when known, else unpacked."""
        if self.dl is not None and self.dl.expected:
            return self.dl.done, self.dl.expected
        if self.nar_expected:
            return self.nar_done, self.nar_expected
        if self.dl is not None:
            return self.dl.done, 0
        return 0, 0

    def duration(self, now: float) -> float:
        return (self.ended if self.ended is not None else now) - self.started

    def __repr__(self) -> str:  # pragma: no cover
        return f"<Transfer {self.name} {self.status} {self.progress()}>"


class _Act:
    __slots__ = ("type", "parent", "text", "obj", "kind", "done", "expected",
                 "running", "failed", "started")

    def __init__(self, typ: int, parent: int, text: str, started: float):
        self.type = typ
        self.parent = parent
        self.text = text
        self.obj = None
        self.kind = ""
        self.done = 0
        self.expected = 0
        self.running = 0
        self.failed = 0
        self.started = started


# ── the parser ────────────────────────────────────────────────────────────────
class NixLog:
    """Pure parser + state for ``nix … --log-format internal-json -v``.

    Feed every stderr line to ``feed()``; read the public fields at any time.
    ``feed()`` never raises. ``end(returncode)`` marks the run finished
    (``nix_build`` calls it).
    """

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.started = clock()
        self.ended: float | None = None
        self.returncode: int | None = None
        self.phase = "evaluating"           # → "building" → "done"
        self.build_started: float | None = None

        self.running_builds: list[Build] = []
        self.downloads: list[Transfer] = []   # running fetches + bare downloads
        self.recent: deque = deque(maxlen=48)  # finished Build/Transfer, newest last
        self.builds: dict[str, Build] = {}    # every build seen, by drv path

        self.builds_done = 0
        self.builds_expected = 0
        self.builds_failed = 0
        self.builds_cancelled = 0             # killed by a failure elsewhere, or by us
        self.transfers_done = 0
        self.transfers_expected = 0
        self.bytes_done = 0
        self.bytes_expected = 0

        self.errors: list[str] = []
        self.error_summaries: list[str] = []  # raw_msg (no trace), ANSI-stripped
        self.error_positions: list[str] = []  # "file:line:col" when nix gave one
        self.warnings: list[str] = []
        self.plain: deque[str] = deque(maxlen=50)  # non-JSON stderr lines
        self.eval_files = 0
        self.failed_drvs: list[str] = []
        self.lines_fed = 0
        self.junk = 0

        self._acts: dict[int, _Act] = {}
        self._detail: list[int] = []         # running activities worth naming
        self._queries = 0
        self._eval_file_raw = ""
        self._eval_file_at = -1e9            # when the last "evaluating file" came
        self._plan: str | None = None
        self.planned_builds: set[str] = set()
        self.planned_fetches: set[str] = set()
        self._fetch_estimate = 0
        self._expected: dict[tuple[int, int], int] = {}
        self._exp_sum: dict[int, int] = {}
        self._bprog_live: list[_Act] = []    # 104 Builds activities
        self._bprog_closed = [0, 0, 0]       # done, expected, failed of stopped ones
        self._cprog_live: list[_Act] = []    # 103 CopyPaths activities
        self._cprog_closed = [0, 0]
        self._ok_builds = 0
        self._failed_builds = 0
        self._undecided: deque[Build] = deque()
        self._stopped_copies = 0
        self._dl_done = 0                    # compressed bytes of substitutions
        self._nar_done = 0
        self._seen_dl = False
        self._bins: deque[list] = deque(maxlen=240)
        self._last_build: Build | None = None

    # ── feeding ──────────────────────────────────────────────────────────────
    def feed(self, line: str) -> None:
        """Take one stderr line (``@nix {...}`` or plain text). Never raises."""
        try:
            self.lines_fed += 1
            if not line:
                return
            if line.startswith("@nix "):
                if line.startswith(_EVAL_FAST):
                    self.eval_files += 1
                    self._eval_file_raw = line
                    self._eval_file_at = self.clock()
                    return
                m = _PROGRESS_FAST.match(line)
                if m is not None:
                    self._on_progress(int(m.group(5)), int(m.group(1)), int(m.group(2)),
                                      int(m.group(3)), int(m.group(4)))
                    return
                d = json.loads(line[5:])
                if type(d) is not dict:
                    self.junk += 1
                    return
                action = d.get("action")
                if action == "result":
                    self._on_result(d)
                elif action == "start":
                    self._on_start(d)
                elif action == "stop":
                    self._on_stop(d.get("id"))
                elif action == "msg":
                    self._on_msg(d)
                else:
                    self.junk += 1
            else:
                self._on_plain(line)
        except Exception:  # junk, truncated JSON, unexpected field types…
            self.junk += 1

    def feed_many(self, lines) -> None:
        for line in lines:
            self.feed(line)

    def mark_started(self) -> None:
        """Restart the clock (called when the nix process is spawned)."""
        if self.lines_fed == 0:
            self.started = self.clock()

    def end(self, returncode: int | None) -> None:
        """The nix process is gone: settle every undecided state."""
        now = self.clock()
        self.returncode = returncode
        self.ended = now
        self.phase = "done"
        ok = returncode == 0
        while self._undecided:
            b = self._undecided.popleft()
            if ok:
                b.status = "ok"
                self._ok_builds += 1
            else:
                b.status = "cancelled"
        for b in list(self.running_builds):
            b.status = "ok" if ok else "cancelled"
            b.ended = now
            self.recent.append(b)
        self.running_builds.clear()
        for t in list(self.downloads):
            t.status = "ok" if ok else "cancelled"
            t.ended = now
        self.downloads.clear()
        self.builds_cancelled = sum(1 for b in self.builds.values() if b.status == "cancelled")
        self._recount()

    @property
    def ok(self) -> bool:
        return self.returncode == 0

    # ── event handlers ───────────────────────────────────────────────────────
    def _on_start(self, d: dict) -> None:
        aid = d.get("id")
        if aid in self._acts:           # a reused id: the old one is over
            self._on_stop(aid)
        typ = d.get("type", 0)
        now = self.clock()
        text = d.get("text")
        act = _Act(typ, d.get("parent") or 0, text if isinstance(text, str) else "", now)
        self._acts[aid] = act
        fields = [f if isinstance(f, str) else "" for f in (d.get("fields") or ())][:3]
        if typ in _WORK_TYPES and self.phase == "evaluating":
            self.phase = "building"
            self.build_started = now
        if typ == ACT_BUILD:
            drv = str(fields[0]) if fields else ""
            b = Build(aid, drv, str(fields[1]) if len(fields) > 1 else "", now)
            act.obj = b
            self.builds[drv] = b
            self.running_builds.append(b)
            if drv and drv not in self.planned_builds:
                self.planned_builds.add(drv)
            self._last_build = b
        elif typ == ACT_COPY_PATH:
            path = str(fields[0]) if fields else ""
            t = Transfer(aid, store_name(path), now, "fetch",
                         str(fields[1]) if len(fields) > 1 else "")
            act.obj = t
            self.downloads.append(t)
        elif typ == ACT_FILE_TRANSFER:
            url = str(fields[0]) if fields else ""
            parent = self._acts.get(act.parent)
            if url.endswith(".narinfo") or url.endswith("/nix-cache-info"):
                act.kind = "narinfo"
            elif parent is not None and parent.type == ACT_COPY_PATH and parent.obj is not None:
                act.kind = "nar"
                parent.obj.dl = act
                self._seen_dl = True
            else:
                act.kind = "dl"
                if self.phase != "evaluating":
                    name = url.rstrip("/").rsplit("/", 1)[-1].split("?", 1)[0] or url
                    t = Transfer(aid, name, now, "download", url)
                    t.dl = act
                    act.obj = t
                    self.downloads.append(t)
                else:
                    self._detail.append(aid)
        elif typ == ACT_BUILDS:
            self._bprog_live.append(act)
        elif typ == ACT_COPY_PATHS:
            self._cprog_live.append(act)
        elif typ == ACT_QUERY_PATH_INFO:
            self._queries += 1
            self._detail.append(aid)
        elif typ in (ACT_UNKNOWN, ACT_FETCH_TREE) and act.text:
            self._detail.append(aid)
        self._recount()

    def _on_stop(self, aid) -> None:
        act = self._acts.pop(aid, None)
        if act is None:
            return
        typ = act.type
        now = self.clock()
        if typ == ACT_BUILD:
            b: Build = act.obj
            b.ended = now
            try:
                self.running_builds.remove(b)
            except ValueError:
                pass
            if self._bprog_live or self._bprog_closed[0] or self._bprog_closed[2]:
                done, failed = self._bprog_totals()[0::2]
                if done > self._ok_builds:
                    self._decide(b, "ok")
                elif failed > self._failed_builds:
                    self._decide(b, "failed")
                elif b.drv in self.failed_drvs:
                    self._decide(b, "failed")
                else:
                    b.status = "stopped"
                    self._undecided.append(b)
            else:
                self._decide(b, "failed" if b.drv in self.failed_drvs else "ok")
            self.recent.append(b)
        elif typ == ACT_COPY_PATH:
            t: Transfer = act.obj
            t.ended = now
            t.status = "ok"
            try:
                self.downloads.remove(t)
            except ValueError:
                pass
            self._stopped_copies += 1
            self.recent.append(t)
        elif typ == ACT_FILE_TRANSFER:
            if act.kind == "dl" and act.obj is not None:
                t = act.obj
                t.ended = now
                t.status = "ok"
                try:
                    self.downloads.remove(t)
                except ValueError:
                    pass
                self.recent.append(t)
        elif typ == ACT_BUILDS:
            try:
                self._bprog_live.remove(act)
            except ValueError:
                pass
            self._bprog_closed[0] += act.done
            self._bprog_closed[1] += act.expected
            self._bprog_closed[2] += act.failed
        elif typ == ACT_COPY_PATHS:
            try:
                self._cprog_live.remove(act)
            except ValueError:
                pass
            self._cprog_closed[0] += act.done
            self._cprog_closed[1] += act.expected
        if act.type in _DETAIL_TYPES:
            try:
                self._detail.remove(aid)
            except ValueError:
                pass
            if act.type == ACT_QUERY_PATH_INFO:
                self._queries -= 1
        self._recount()

    def _decide(self, b: Build, status: str) -> None:
        b.status = status
        if status == "ok":
            self._ok_builds += 1
            if b is not self._last_build:
                b.lines = None          # nobody will ask for its log any more
        elif status == "failed":
            self._failed_builds += 1

    def _on_result(self, d: dict) -> None:
        typ = d.get("type")
        aid = d.get("id")
        fields = d.get("fields") or ()
        if typ == RES_PROGRESS:
            f = list(fields) + [0, 0, 0, 0]
            self._on_progress(aid, int(f[0]), int(f[1]), int(f[2]), int(f[3]))
            return
        act = self._acts.get(aid)
        if act is None:
            return
        if typ in (RES_BUILD_LOG_LINE, RES_POST_BUILD_LOG_LINE):
            b = act.obj
            if isinstance(b, Build) and fields and isinstance(fields[0], str):
                line = clean_log_line(fields[0])
                if b.lines is not None:
                    b.lines.append(line)
                b.nlines += 1
                if line.strip():
                    b.last_line = line.strip()
        elif typ == RES_SET_PHASE:
            if isinstance(act.obj, Build) and fields and isinstance(fields[0], str):
                act.obj.phase = fields[0]
        elif typ == RES_SET_EXPECTED:
            if len(fields) >= 2:
                key = (aid, int(fields[0]))
                n = int(fields[1])
                old = self._expected.get(key, 0)
                self._expected[key] = n
                self._exp_sum[key[1]] = self._exp_sum.get(key[1], 0) + n - old
                self._recount()
        elif typ == RES_FETCH_STATUS:
            if fields:
                act.text = strip_ansi(str(fields[0]))

    def _on_progress(self, aid, done: int, expected: int, running: int, failed: int) -> None:
        act = self._acts.get(aid)
        if act is None:
            return
        typ = act.type
        if typ == ACT_FILE_TRANSFER:
            if act.kind == "narinfo":
                return
            delta = done - act.done
            act.done = done
            act.expected = expected
            if delta > 0:
                self._add_bytes(delta)
                if act.kind == "nar":
                    self._dl_done += delta
                    self.bytes_done = self._bytes_done()
        elif typ == ACT_COPY_PATH:
            delta = done - act.done
            act.done = done
            act.expected = expected
            t = act.obj
            if t is not None:
                t.nar_done = done
                t.nar_expected = expected
            if delta > 0:
                self._nar_done += delta
                if not self._seen_dl:
                    self.bytes_done = self._bytes_done()
        elif typ == ACT_BUILDS:
            act.done, act.expected, act.running, act.failed = done, expected, running, failed
            # A build whose stop came first gets its verdict now.
            tot_done, _, tot_failed = self._bprog_totals()
            while self._undecided and tot_done > self._ok_builds:
                self._decide(self._undecided.popleft(), "ok")
            while self._undecided and tot_failed > self._failed_builds:
                self._decide(self._undecided.popleft(), "failed")
            self._recount()
        elif typ == ACT_COPY_PATHS:
            act.done, act.expected, act.running, act.failed = done, expected, running, failed
            self._recount()
        else:
            act.done, act.expected = done, expected

    def _on_msg(self, d: dict) -> None:
        level = d.get("level", 3)
        msg = d.get("msg")
        if not isinstance(msg, str):
            msg = str(msg)
        if level >= 4:
            if msg.startswith("evaluating file "):
                self.eval_files += 1
                self._eval_file_raw = msg
                self._eval_file_at = self.clock()
            return
        clean = strip_ansi(msg)
        if level <= 0:
            if clean.startswith("trace:"):
                self._warn(clean)
                return
            raw = d.get("raw_msg")
            pos = d.get("file")
            self._error(clean, strip_ansi(raw) if isinstance(raw, str) and raw else clean,
                        pos if isinstance(pos, str) and not pos.startswith("«none»") else "")
            return
        if level == 1:
            self._warn(clean)
            return
        m = _PLAN.match(clean)
        if m is not None:
            self._plan = "build" if m.group(3) == "built" else "fetch"
            if m.group(4):
                self._fetch_estimate += int(float(m.group(4)) * _UNITS.get(m.group(5), 1))
            return
        if self._plan and clean.startswith("  /nix/store/"):
            path = clean.strip()
            (self.planned_builds if self._plan == "build" else self.planned_fetches).add(path)
            self._recount()
            return
        self._plan = None

    def _on_plain(self, line: str) -> None:
        clean = strip_ansi(line.rstrip("\r\n"))
        if not clean.strip():
            return
        low = clean.lstrip().lower()
        if low.startswith("error"):
            self._error(clean, clean)
        elif low.startswith("warning") or low.startswith("trace:"):
            self._warn(clean)
        else:
            self.plain.append(clean)

    def _error(self, clean: str, summary: str, pos: str = "") -> None:
        self.errors.append(clean)
        self.error_summaries.append(summary)
        self.error_positions.append(pos)
        if len(self.errors) > 200:      # keep the first ones: the root cause
            del self.errors[20:70], self.error_summaries[20:70], self.error_positions[20:70]
        self._scan_failed(clean)

    def _warn(self, s: str) -> None:
        self.warnings.append(s)
        if len(self.warnings) > 100:
            del self.warnings[:50]

    def _scan_failed(self, clean: str) -> None:
        if _DEP_FAILED.search(clean) and not _FAILED_DRV[0].search(clean):
            return
        for rx in _FAILED_DRV:
            for m in rx.finditer(clean):
                drv = m.group(1)
                if drv not in self.failed_drvs:
                    self.failed_drvs.append(drv)
                    b = self.builds.get(drv)
                    if b is not None and b.status in ("stopped", "ok"):
                        if b.status == "stopped":
                            try:
                                self._undecided.remove(b)
                            except ValueError:
                                pass
                            self._decide(b, "failed")
                        # an "ok" verdict that an error names was wrong
                        else:
                            b.status = "failed"
                            self._ok_builds -= 1
                            self._failed_builds += 1

    # ── derived numbers ──────────────────────────────────────────────────────
    def _bprog_totals(self) -> tuple[int, int, int]:
        done, exp, failed = self._bprog_closed
        for a in self._bprog_live:
            done += a.done
            exp += a.expected
            failed += a.failed
        return done, exp, failed

    def _bytes_done(self) -> int:
        return self._dl_done if (self._seen_dl or not self._nar_done) else self._nar_done

    def _recount(self) -> None:
        have_prog = bool(self._bprog_live) or any(self._bprog_closed)
        pdone, pexp, pfailed = self._bprog_totals()
        if have_prog:
            self.builds_done = max(pdone, self._ok_builds)
            self.builds_failed = max(pfailed, self._failed_builds)
        else:
            self.builds_done = self._ok_builds
            self.builds_failed = self._failed_builds
        floor = self.builds_done + self.builds_failed + len(self.running_builds) + len(self._undecided)
        planned = len(self.planned_builds) or pexp
        self.builds_expected = max(planned, floor)

        cdone = self._cprog_closed[0] + sum(a.done for a in self._cprog_live)
        cexp = self._cprog_closed[1] + sum(a.expected for a in self._cprog_live)
        self.transfers_done = max(cdone, self._stopped_copies)
        running_fetches = sum(1 for t in self.downloads if t.kind == "fetch")
        planned_f = len(self.planned_fetches) or cexp
        self.transfers_expected = max(planned_f, self.transfers_done + running_fetches)

        self.bytes_done = self._bytes_done()
        if self._seen_dl or not self._exp_sum.get(ACT_COPY_PATH):
            # nix's exact total; its rounded "(45.4 MiB download…)" only until then
            exp_b = self._exp_sum.get(ACT_FILE_TRANSFER, 0) or self._fetch_estimate
        else:
            exp_b = self._exp_sum.get(ACT_COPY_PATH, 0)
        self.bytes_expected = max(exp_b, self.bytes_done)

    # ── throughput ───────────────────────────────────────────────────────────
    def _add_bytes(self, n: int) -> None:
        idx = int(self.clock() / _BIN)
        bins = self._bins
        if bins and bins[-1][0] == idx:
            bins[-1][1] += n
        else:
            bins.append([idx, n])

    def rate(self, window: float = 2.0) -> float:
        """Smoothed download speed in bytes/s (a sliding ``window``-second mean)."""
        now = self.clock()
        cur = int(now / _BIN)
        nbins = max(1, int(window / _BIN))
        lo = cur - nbins
        total = 0
        for idx, n in reversed(self._bins):
            if idx < lo:
                break
            total += n
        span = nbins * _BIN + (now - cur * _BIN)
        return total / span if span > 0 else 0.0

    def throughput(self, n: int = 12) -> list[float]:
        """The last ``n`` complete half-second bins, as bytes/s (oldest first)."""
        cur = int(self.clock() / _BIN)
        out = [0.0] * n
        for idx, b in reversed(self._bins):
            k = cur - 1 - idx
            if k >= n:
                break
            if k >= 0:
                out[n - 1 - k] = b / _BIN
        return out

    # ── questions the UI asks ────────────────────────────────────────────────
    def elapsed(self) -> float:
        return (self.ended if self.ended is not None else self.clock()) - self.started

    def failed_build(self) -> Build | None:
        """The build that broke the run, if one did."""
        for drv in self.failed_drvs:
            b = self.builds.get(drv)
            if b is not None:
                return b
        for item in reversed(self.recent):
            if isinstance(item, Build) and item.status == "failed":
                return item
        return None

    def failed_log(self, n: int = 25) -> list[str]:
        """The last ``n`` log lines of the failed build (or of the last build)."""
        b = self.failed_build() or self._last_build
        if b is not None and b.lines:
            return list(b.lines)[-n:]
        # Older nix put the tail in the error itself ("> line").
        for err in self.errors:
            tail = [ln.split(">", 1)[1][1:] for ln in err.splitlines() if ln.lstrip().startswith(">")]
            if tail:
                return tail[-n:]
        return []

    FETCH_WEIGHT = 0.5   # a fetched path counts as half a build in fraction()

    def fraction(self) -> float:
        """Overall progress 0–1: builds and fetches (the fetched share by bytes)."""
        B = self.builds_expected
        T = self.transfers_expected * self.FETCH_WEIGHT
        if B + T == 0:
            return 1.0 if self.phase == "done" and self.ok else 0.0
        if self.bytes_expected > 0:
            f = min(1.0, self.bytes_done / self.bytes_expected)
        elif self.transfers_expected:
            f = self.transfers_done / self.transfers_expected
        else:
            f = 0.0
        return max(0.0, min(1.0, (self.builds_done + f * T) / (B + T)))

    def detail(self, stale_after: float | None = None) -> str:
        """What nix is doing besides building, in a few words: the running
        fetch/copy/query, else the file being evaluated (``""`` if that's
        older than ``stale_after`` seconds)."""
        for aid in reversed(self._detail):
            act = self._acts.get(aid)
            if act is None:
                continue
            if act.type == ACT_QUERY_PATH_INFO:
                return f"asking the cache about {self._queries} path{'s' if self._queries != 1 else ''}"
            if act.type == ACT_FILE_TRANSFER:
                txt = act.text.replace("downloading ", "fetching ", 1)
                if act.done:
                    txt += f"  {fmt_bytes(act.done)}"
                return _tidy(txt)
            if act.text:
                return _tidy(act.text)
        raw = self._eval_file_raw
        if raw and stale_after is not None and self.clock() - self._eval_file_at > stale_after:
            return ""
        if raw:
            if raw.startswith("@nix "):
                try:
                    raw = json.loads(raw[5:]).get("msg", "")
                except Exception:
                    raw = ""
                self._eval_file_raw = raw
            m = re.match(r"evaluating file '(.*)'", raw)
            if m:
                p = m.group(1)
                p = re.sub(r"^/nix/store/[0-9a-z]{32}-source/", "", p)
                p = re.sub(r"^/nix/store/[0-9a-z]{32}-", "", p)
                return p
        return ""

    def summary(self) -> str:
        """``8 built · 6 fetched (47.6 MB) · in 16.0s`` — plain text."""
        parts = []
        if self.builds_done:
            parts.append(f"{self.builds_done} built")
        if self.transfers_done:
            s = f"{self.transfers_done} fetched"
            if self.bytes_done:
                s += f" ({fmt_bytes(self.bytes_done)})"
            parts.append(s)
        if self.builds_failed:
            parts.append(f"{self.builds_failed} failed")
        if not parts:
            parts.append("nothing to build")
        return " · ".join(parts) + f" · in {fmt_dur(self.elapsed())}"


# ── running nix ───────────────────────────────────────────────────────────────
_MAX_LINE = 4 << 20  # a single stderr line longer than this is cut (it's junk)


async def nix_build(argv: list[str], log: NixLog) -> tuple[int, list[str]]:
    """Run ``argv`` (a ``nix build …`` without log flags) feeding ``log``.

    Appends ``--log-format internal-json -v``; stdin is /dev/null. Returns
    ``(returncode, stdout lines)``. Cancelling the awaiting task sends SIGTERM
    to nix (SIGKILL after 5 s), which makes the daemon drop the builds, and
    re-raises ``CancelledError``. nix stays in the app's process group, so if
    the terminal goes away it goes with it (Textual's raw mode means no
    keyboard signals reach it meanwhile).
    """
    cmd = list(argv) + ["--log-format", "internal-json", "-v"]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except OSError as exc:              # no nix on PATH, not executable…
        log.feed(f"error: cannot run {cmd[0]}: {exc.strerror or exc}")
        log.end(127)
        return 127, []
    log.mark_started()
    out: list[str] = []

    async def pump_stderr() -> None:
        buf = bytearray()
        skipping = False
        feed = log.feed
        while True:
            chunk = await proc.stderr.read(1 << 16)
            if not chunk:
                break
            buf += chunk
            start = 0
            while True:
                nl = buf.find(b"\n", start)
                if nl < 0:
                    break
                if skipping:
                    skipping = False
                else:
                    feed(buf[start:nl].decode("utf-8", "replace"))
                start = nl + 1
            del buf[:start]
            if len(buf) > _MAX_LINE:
                if not skipping:
                    feed(buf[:2000].decode("utf-8", "replace"))
                skipping = True
                buf.clear()
        if buf and not skipping:
            feed(buf.decode("utf-8", "replace"))

    async def pump_stdout() -> None:
        data = await proc.stdout.read()
        out.extend(ln for ln in data.decode("utf-8", "replace").splitlines() if ln.strip())

    def send(sig: int) -> None:
        try:
            proc.send_signal(sig)
        except ProcessLookupError:
            pass

    async def drain() -> None:
        # keep the pipes empty so nix can't block writing while it shuts down
        for stream in (proc.stderr, proc.stdout):
            while await stream.read(1 << 16):
                pass

    try:
        await asyncio.gather(pump_stderr(), pump_stdout())
        rc = await proc.wait()
    except asyncio.CancelledError:
        if proc.returncode is None:
            drainer = asyncio.ensure_future(drain())
            send(signal.SIGTERM)
            try:
                await asyncio.wait_for(proc.wait(), 5)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                send(signal.SIGKILL)
                try:
                    await asyncio.wait_for(proc.wait(), 2)
                except (asyncio.TimeoutError, asyncio.CancelledError):
                    pass
            drainer.cancel()
        log.end(proc.returncode if proc.returncode is not None else -signal.SIGTERM)
        raise
    log.end(rc)
    return rc, out


# ── colours ───────────────────────────────────────────────────────────────────
AQUA = "#8ec07c"
BLUE = "#83a598"
PURPLE = "#d3869b"
YELLOW = "#fabd2f"
RED = "#fb4934"
GREEN = "#b8bb26"
FG = "#ebdbb2"
DIM = "#928374"
LINE = "#504945"
BG = "#1d2021"
SHINE = "#fbf1c7"


def _rgb(h: str) -> tuple[int, int, int]:
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)


@lru_cache(maxsize=8192)
def mix(a: str, b: str, t: float) -> str:
    """``t`` of colour ``a`` over ``b`` (t=1 → a)."""
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    ra, ga, ba = _rgb(a)
    rb, gb, bb = _rgb(b)
    return "#%02x%02x%02x" % (round(ra * t + rb * (1 - t)), round(ga * t + gb * (1 - t)),
                              round(ba * t + bb * (1 - t)))


_GRAD = [mix(BLUE, AQUA, i / 127) for i in range(128)] + [mix(PURPLE, BLUE, i / 127) for i in range(128)]


def grad(t: float) -> str:
    """The house gradient, aqua → blue → purple, at ``t`` in 0–1."""
    i = int(t * 255 + 0.5)
    return _GRAD[0 if i < 0 else 255 if i > 255 else i]


@lru_cache(maxsize=8192)
def _st(color: str, bold: bool = False, italic: bool = False) -> Style:
    return Style(color=color, bold=bold, italic=italic)


_PHASE_COLOR = {
    "unpack": AQUA, "patch": AQUA, "autotools": YELLOW, "autoreconf": YELLOW,
    "configure": YELLOW, "build": BLUE, "check": GREEN, "install": PURPLE,
    "fixup": mix(PURPLE, DIM, 0.55), "dist": DIM,
}

_SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
_SPIN_BIG = "⣾⣽⣻⢿⡿⣟⣯⣷"
_SPARK = "▁▂▃▄▅▆▇█"


# ── the widget ────────────────────────────────────────────────────────────────
class BuildMonitor(Widget):
    """Live view of a ``NixLog``: animated while running, a still once finished.

    Animates on its own interval timer (``FPS``) from mount until ``finish()``;
    the log is only read on those ticks, never per line. Call ``finish()`` on
    the app's event loop (from a thread, use ``app.call_from_thread``).
    """

    DEFAULT_CSS = """
    BuildMonitor {
        height: auto;
        width: 1fr;
        padding: 0 1;
    }
    """

    FPS = 12
    MAX_BUILDS = 8
    MAX_DOWNLOADS = 4
    MAX_RECENT = 3
    RECENT_TTL = 10.0

    def __init__(self, log: NixLog, *, max_lines: int = 20, name: str | None = None,
                 id: str | None = None, classes: str | None = None):
        super().__init__(name=name, id=id, classes=classes)
        self.nixlog = log
        self.max_lines = max_lines
        self.state = "running"          # running | ok | failed
        self._shown = 0.0               # eased progress fraction
        self._last_tick: float | None = None
        self._timer = None
        self._lines: list[Text] = []
        self._text = Text()
        self._width = -1
        self._rate_shown = 0.0
        self._rate_at = -1.0
        self._spark: list[float] = []
        self._detail = ""
        self._detail_at = -1.0

    # ── lifecycle ────────────────────────────────────────────────────────────
    def on_mount(self) -> None:
        if self.state == "running":
            self._timer = self.set_interval(1 / self.FPS, self._tick)

    def on_unmount(self) -> None:
        if self._timer is not None:
            self._timer.stop()
            self._timer = None

    def finish(self, ok: bool) -> None:
        """Stop animating and show the final state (summary, or the failure)."""
        log = self.nixlog
        if log.phase != "done":
            log.end(log.returncode if log.returncode is not None else (0 if ok else 1))
        self.state = "ok" if ok else "failed"
        if self._timer is not None:
            self._timer.stop()
            self._timer = None
        self._rebuild(self.nixlog.clock())
        self.refresh(layout=True)

    def _tick(self) -> None:
        now = self.nixlog.clock()
        dt = 0.0 if self._last_tick is None else max(0.0, now - self._last_tick)
        self._last_tick = now
        target = self.nixlog.fraction()
        k = 1 - math.exp(-dt / 0.28) if dt else 0.0
        self._shown += (target - self._shown) * k
        if abs(target - self._shown) < 0.0005:
            self._shown = target
        before = len(self._lines)
        self._rebuild(now)
        self.refresh(layout=len(self._lines) != before)

    # ── Textual hooks ────────────────────────────────────────────────────────
    def render(self) -> Text:
        w = self.content_size.width
        if w and w != self._width:
            self._rebuild(self.nixlog.clock(), w)
        return self._text

    def get_content_height(self, container, viewport, width: int) -> int:
        if width != self._width:
            self._rebuild(self.nixlog.clock(), width)
        return len(self._lines)

    def get_content_width(self, container, viewport) -> int:
        return container.width

    # ── frame building ───────────────────────────────────────────────────────
    def _rebuild(self, now: float, width: int | None = None) -> None:
        W = width or self.content_size.width or self._width
        if not W or W < 0:
            W = 80
        log = self.nixlog
        try:
            if self.state == "ok":
                lines = self._frame_ok(W, now)
            elif self.state == "failed":
                lines = self._frame_failed(W, now)
            elif log.phase == "evaluating":
                lines = self._frame_eval(W, now)
            else:
                lines = self._frame_build(W, now)
        except Exception as exc:  # never let a drawing bug take the app down
            lines = [Text(f" nixmon: {type(exc).__name__}: {exc}", style=_st(RED))]
        out = []
        for ln in lines[: max(1, self.max_lines)]:
            if ln.cell_len > W:
                ln.truncate(W, overflow="ellipsis")
            ln.no_wrap = True
            out.append(ln)
        self._lines = out
        self._width = W
        self._text = Text("\n").join(out) if out else Text("")
        self._text.no_wrap = True

    # pieces ─────────────────────────────────────────────────────────────────
    @staticmethod
    def _lr(left: Text, right: Text, width: int) -> Text:
        gap = width - left.cell_len - right.cell_len
        if gap < 1:
            left = left.copy()
            left.truncate(max(0, width - right.cell_len - 1), overflow="ellipsis")
            gap = width - left.cell_len - right.cell_len
        line = left.copy()
        line.append(" " * max(1, gap))
        line.append_text(right)
        return line

    @staticmethod
    def _bar(width: int, frac: float, now: float | None, *, shine: bool = True,
             tint: str | None = None, track: str = LINE) -> Text:
        """A gradient bar with half-cell precision and a travelling shine."""
        t = Text()
        if width <= 0:
            return t
        halves = int(round(max(0.0, min(1.0, frac)) * width * 2))
        full, half = divmod(halves, 2)
        lit = full + half
        span = max(1, lit - 1)
        sx = -99.0
        bw = max(2.5, min(7.0, width / 9))
        if shine and now is not None and lit >= 2:
            period = 1.6 + lit / 60
            p = (now % period) / period
            sx = -bw + p * (lit + 2 * bw)
        run_style = None
        run = []
        for i in range(width):
            if i < lit:
                c = tint or grad(i / span if lit > 1 else 0.0)
                d = abs(i - sx)
                if d < bw:
                    c = mix(SHINE, c, 0.62 * (1 - d / bw) ** 1.6)
                ch = "━" if i < full else "╸"
                st = _st(c)
            else:
                ch = "━"
                st = _st(track)
            if st is not run_style and run:
                t.append("".join(run), run_style)
                run = []
            run_style = st
            run.append(ch)
        if run:
            t.append("".join(run), run_style)
        return t

    @staticmethod
    def _scanner(width: int, now: float) -> Text:
        """An indeterminate bar: a soft gradient glow gliding back and forth."""
        t = Text()
        if width <= 0:
            return t
        seg = max(4.0, width / 4.5)
        period = 2.4
        ph = (now % period) / period
        pos = (0.5 - 0.5 * math.cos(ph * 2 * math.pi))  # ease in-out ping-pong
        cx = -seg / 2 + pos * (width + seg) - 0.5
        for i in range(width):
            d = abs(i - cx) / (seg / 2)
            if d < 1:
                a = (1 - d * d)
                c = mix(grad(i / max(1, width - 1)), LINE, 0.25 + 0.75 * a)
                if d < 0.22:
                    c = mix(SHINE, c, 0.35 * (1 - d / 0.22))
            else:
                c = LINE
            t.append("━", _st(c))
        return t

    @staticmethod
    def _shimmer(text: str, now: float, bold: bool = True) -> Text:
        """Gradient lettering with a highlight sweeping across it."""
        t = Text()
        n = len(text)
        period = 2.2
        sx = -4 + ((now % period) / period) * (n + 8)
        for i, ch in enumerate(text):
            c = grad(i / max(1, n - 1) * 0.9)
            d = abs(i - sx)
            if d < 4:
                c = mix(SHINE, c, 0.75 * (1 - d / 4) ** 1.5)
            t.append(ch, _st(c, bold=bold))
        return t

    @staticmethod
    def _item_name(item, width: int, color: str = FG, vcolor: str = DIM, bold: bool = False) -> Text:
        """``pname version`` padded/truncated to ``width`` cells."""
        t = Text()
        pname = item.pname
        ver = item.version
        if cell_len(pname) >= width:
            t.append(pname, _st(color, bold))
            t.truncate(width, overflow="ellipsis")
            return t
        t.append(pname, _st(color, bold))
        if ver:
            room = width - cell_len(pname) - 1
            if len(ver) <= room or room >= 6:
                v = ver if len(ver) <= room else ver[: room - 1] + "…"
                t.append(" " + v, _st(vcolor))
        t.pad_right(width - t.cell_len)
        return t

    def _rate_text(self, now: float, busy: bool) -> float:
        """The displayed rate: re-sampled twice a second, lightly smoothed."""
        if now - self._rate_at >= 0.5 or self._rate_at < 0:
            r = self.nixlog.rate()
            if not busy and r == 0:
                self._rate_shown = 0.0
            elif self._rate_at < 0 or self._rate_shown == 0:
                self._rate_shown = r
            else:
                self._rate_shown = self._rate_shown * 0.35 + r * 0.65
            self._rate_at = now
            self._spark = self.nixlog.throughput(16)
        return self._rate_shown

    def _held_detail(self, now: float, stale_after: float | None = None) -> str:
        """``NixLog.detail()``, changing at most ~4×/s so it reads, not flickers."""
        if now - self._detail_at >= 0.25 or self._detail_at < 0:
            self._detail = self.nixlog.detail(stale_after)
            self._detail_at = now
        return self._detail

    def _sparkline(self, n: int) -> Text:
        vals = self._spark[-n:] if self._spark else []
        t = Text()
        if not vals:
            return t
        top = max(vals) or 1.0
        for i, v in enumerate(vals):
            if v <= 0:
                t.append("▁", _st(LINE))
            else:
                lvl = min(7, int(v / top * 7.999))
                t.append(_SPARK[lvl], _st(grad(i / max(1, len(vals) - 1))))
        return t

    def _stats(self, W: int, now: float, final: bool = False, indent: str = "   ") -> Text:
        """``8/9 built · 4/6 fetched · 45.2/120 MB  ▁▂▅▇ 12.3 MB/s``."""
        log = self.nixlog
        segs: list[Text] = []

        def seg(num: str, label: str, color: str) -> Text:
            s = Text()
            s.append(num, _st(color, bold=True))
            s.append(" " + label, _st(DIM))
            return s

        if log.builds_expected or log.builds_done:
            num = (f"{log.builds_done}" if final else f"{log.builds_done}/{log.builds_expected}")
            segs.append(seg(num, "built", AQUA))
        if log.transfers_expected or log.transfers_done:
            num = (f"{log.transfers_done}" if final else f"{log.transfers_done}/{log.transfers_expected}")
            segs.append(seg(num, "fetched", BLUE))
        if log.builds_failed:
            segs.append(seg(str(log.builds_failed), "failed", RED))
        if final and log.builds_cancelled:
            segs.append(seg(str(log.builds_cancelled), "cancelled", YELLOW))
        have_bytes = log.bytes_expected > 0 or log.bytes_done > 0
        if have_bytes:
            if final or log.bytes_done >= log.bytes_expected:
                b = Text(fmt_bytes(log.bytes_done), _st(PURPLE, bold=True))
            else:
                pair = fmt_pair(log.bytes_done, log.bytes_expected)
                num, unit = pair.rsplit(" ", 1)
                b = Text(num, _st(PURPLE, bold=True))
                b.append(" " + unit, _st(DIM))
            segs.append(b)
        sep = Text(" · ", _st(LINE))
        line = Text(indent)
        for i, s in enumerate(segs):
            add = (sep.cell_len if i else 0) + s.cell_len
            if line.cell_len + add > W:
                break
            if i:
                line.append_text(sep)
            line.append_text(s)
        # live throughput — only while something is downloading (or just was)
        if not final and have_bytes:
            busy = any(t.kind in ("fetch", "download") for t in log.downloads)
            r = self._rate_text(now, busy)
            if r > 0:
                rate = Text(f"{fmt_bytes(r)}/s", _st(FG))
                spark_n = 12 if W >= 110 else 8 if W >= 84 else 0
                spark = self._sparkline(spark_n) if spark_n else Text()
                if line.cell_len + 3 + spark.cell_len + 1 + rate.cell_len <= W and spark_n:
                    line.append("   ")
                    line.append_text(spark)
                    line.append(" ")
                    line.append_text(rate)
                elif line.cell_len + 3 + rate.cell_len <= W:
                    line.append("   ")
                    line.append_text(rate)
        return line

    # frames ─────────────────────────────────────────────────────────────────
    def _frame_eval(self, W: int, now: float) -> list[Text]:
        log = self.nixlog
        el = Text(fmt_dur(log.elapsed()) if log.elapsed() >= 10 else f"{log.elapsed():.0f}s",
                  _st(DIM))
        left = Text(" ")
        left.append(_SPIN_BIG[int(now * self.FPS) % len(_SPIN_BIG)], _st(AQUA, bold=True))
        left.append(" ")
        label = "Evaluating the flake…" if W >= 64 else "Evaluating…"
        left.append_text(self._shimmer(label, now))
        left.append("  ")
        bar_w = W - left.cell_len - el.cell_len - 2
        if bar_w >= 8:
            left.append_text(self._scanner(bar_w, now))
        head = self._lr(left, el, W)

        sub = Text("   ")
        if log.eval_files:
            sub.append(f"{log.eval_files:,}", _st(FG))
            sub.append(" files", _st(DIM))
        det = self._held_detail(now)
        if det:
            if log.eval_files:
                sub.append(" · ", _st(LINE))
            sub.append(det, _st(DIM))
        lines = [head, sub]
        if log.warnings:
            w = Text("   ")
            w.append("▲ ", _st(YELLOW))
            last = log.warnings[-1].splitlines()[0] if log.warnings[-1] else ""
            last = re.sub(r"^(?:evaluation )?warning:\s*", "", last)
            w.append(_tidy(last), _st(mix(YELLOW, DIM, 0.55)))
            lines.append(w)
        return lines

    def _frame_build(self, W: int, now: float) -> list[Text]:
        log = self.nixlog
        frac = self._shown
        # header ───────────────────────────────────────────────────────────
        nbuild = len(log.running_builds)
        label = "Building" if nbuild or not log.downloads else "Fetching"
        left = Text(" ")
        left.append(_SPIN_BIG[int(now * self.FPS) % len(_SPIN_BIG)], _st(AQUA, bold=True))
        left.append(" ")
        left.append(label, _st(FG, bold=True))
        left.append("  ")
        right = Text()
        right.append(f"{int(frac * 100):>3d}%", _st(FG, bold=True))
        right.append("  ")
        right.append(fmt_dur(log.elapsed()).rjust(6), _st(DIM))
        bar_w = W - left.cell_len - right.cell_len - 2
        if bar_w >= 6:
            left.append_text(self._bar(bar_w, frac, now))
        lines = [self._lr(left, right, W), self._stats(W, now)]

        # rows ─────────────────────────────────────────────────────────────
        budget = self.max_lines - len(lines) - 1
        builds = log.running_builds
        dls = log.downloads
        recent = [r for r in reversed(log.recent) if now - (r.ended or now) < self.RECENT_TTL]
        nb = min(len(builds), self.MAX_BUILDS)
        nd = min(len(dls), self.MAX_DOWNLOADS)
        nr = min(len(recent), self.MAX_RECENT)
        more_b = 1 if len(builds) > nb else 0
        more_d = 1 if len(dls) > nd else 0
        while nb + nd + nr + more_b + more_d > budget and nr > 0:
            nr -= 1
        while nb + nd + nr + more_b + more_d > budget and nd > 1:
            nd -= 1
            more_d = 1
        while nb + nd + nr + more_b + more_d > budget and nb > 1:
            nb -= 1
            more_b = 1

        shown = builds[:nb] + dls[:nd] + recent[:nr]
        name_w = max([cell_len(x.name) for x in shown] + [12])
        name_w = min(name_w, max(14, int(W * 0.30)), 40)
        # columns: icon · name · [phase|verb] · time · detail
        phase_w = 10 if W >= 72 else 0
        if phase_w and not (nd or nr or any(b.phase for b in builds[:nb])):
            phase_w = 0
        time_w = 6
        tick = int(now * self.FPS)

        def cols(row: Text, mid: Text | None, tm: Text, det: Text | None) -> Text:
            if phase_w:
                row.append("  ")
                m = mid if mid is not None else Text()
                if m.cell_len > phase_w:
                    m.truncate(phase_w, overflow="ellipsis")
                row.append_text(m)
                row.append(" " * (phase_w - m.cell_len))
            row.append(" " * (2 + time_w - tm.cell_len))
            row.append_text(tm)
            if det is not None and det.cell_len:
                room = W - row.cell_len - 2
                if room >= 6:
                    if det.cell_len > room:
                        det.truncate(room, overflow="ellipsis")
                    row.append("  ")
                    row.append_text(det)
            return row

        if shown or more_b or more_d:
            lines.append(Text(""))
        # running builds
        for i, b in enumerate(builds[:nb]):
            row = Text("   ")
            sc = grad(i / max(1, nb - 1)) if nb > 1 else AQUA
            off = (b.id * 7) % len(_SPIN)
            row.append(_SPIN[(tick + off) % len(_SPIN)], _st(sc, bold=True))
            row.append(" ")
            nm = self._item_name(b, name_w)
            if b.machine:
                host = re.sub(r"^[a-z+-]+://", "", b.machine).split("@")[-1]
                nm = self._item_name(b, max(4, name_w - len(host) - 2))
                nm.append(f" @{host}", _st(BLUE))
                nm.pad_right(name_w - nm.cell_len)
            row.append_text(nm)
            pl = b.phase_label
            mid = Text(pl, _st(_PHASE_COLOR.get(pl, DIM))) if pl else None
            dur = b.duration(now)
            dc = DIM if dur < 60 else mix(YELLOW, DIM, 0.6) if dur < 600 else YELLOW
            det = Text(b.last_line, _st(mix(DIM, BG, 0.85))) if b.last_line else None
            lines.append(cols(row, mid, Text(fmt_dur(dur), _st(dc)), det))
        if more_b:
            m = Text("     ")
            m.append(f"+{len(builds) - nb} more building", _st(DIM, italic=True))
            lines.append(m)
        # running downloads: the bar spans the phase + time columns
        for i, t in enumerate(dls[:nd]):
            row = Text("   ")
            pulse = 0.5 + 0.5 * math.sin(now * 5 + t.id % 7)
            row.append("↓", _st(mix(AQUA, BLUE, pulse), bold=True))
            row.append(" ")
            row.append_text(self._item_name(t, name_w))
            row.append("  ")
            done, exp = t.progress()
            f = done / exp if exp else 0.0
            bw = (phase_w + 2 + time_w) if phase_w else 10
            row.append_text(self._bar(bw, f, now, shine=False))
            if exp:
                det = Text(fmt_pair(done, exp), _st(DIM))
            elif done:
                det = Text(fmt_bytes(done), _st(DIM))
            else:
                det = Text("waiting", _st(LINE))
            row.append("  ")
            row.append_text(det)
            lines.append(row)
        if more_d:
            m = Text("     ")
            m.append(f"+{len(dls) - nd} more fetching", _st(DIM, italic=True))
            lines.append(m)
        # the fading tail of finished items
        for r in recent[:nr]:
            age = now - (r.ended or now)
            a = 1.0 if age < 1.5 else 0.72 if age < 3.5 else 0.5 if age < 6 else 0.32
            row = Text("   ")
            if r.status == "failed":
                icon, ic, verb = "✘", RED, "failed"
            elif r.status in ("cancelled", "stopped"):
                icon, ic, verb = "◌", DIM, "cancelled" if r.status == "cancelled" else "stopped"
            else:
                icon, ic = "✔", GREEN
                verb = "fetched" if isinstance(r, Transfer) else "built"
            row.append(icon, _st(mix(ic, BG, a), bold=True))
            row.append(" ")
            row.append_text(self._item_name(r, name_w, mix(FG, BG, a * 0.9), mix(DIM, BG, a)))
            dcol = mix(DIM, BG, a)
            vcol = mix(RED, BG, a) if r.status == "failed" else dcol
            det = None
            if isinstance(r, Transfer):
                done, exp = r.progress()
                if exp or done:
                    det = Text(fmt_bytes(exp or done), _st(dcol))
            lines.append(cols(row, Text(verb, _st(vcol)), Text(fmt_dur(r.duration(now)), _st(dcol)), det))
        if not (shown or more_b or more_d):
            lines.append(Text(""))
            idle = Text("   ")
            idle.append(_SPIN[int(now * self.FPS) % len(_SPIN)], _st(DIM))
            det = self._held_detail(now, stale_after=1.5)
            idle.append(" " + (det or "waiting for nix…"), _st(DIM))
            lines.append(idle)
        return lines

    def _frame_ok(self, W: int, now: float) -> list[Text]:
        """One line: ``✔ Done  8 built · 6 fetched · 47.6 MB  ━━━━━━  16s``."""
        log = self.nixlog
        left = Text(" ")
        left.append("✔", _st(GREEN, bold=True))
        left.append(" ")
        nothing = not (log.builds_done or log.transfers_done)
        left.append("Up to date" if nothing else "Done", _st(FG, bold=True))
        if nothing:
            left.append("  nothing to build or fetch", _st(DIM))
        else:
            left.append_text(self._stats(W - 9, now, final=True, indent="  "))
        right = Text(fmt_dur(log.elapsed()), _st(DIM))
        bar_w = W - left.cell_len - right.cell_len - 4
        if bar_w >= 6:
            left.append("  ")
            left.append_text(self._bar(bar_w, 1.0, None, shine=False))
        return [self._lr(left, right, W)]

    def _frame_failed(self, W: int, now: float) -> list[Text]:
        log = self.nixlog
        fb = log.failed_build()
        evaluated = log.build_started is not None
        if fb is not None:
            title, tc = "Build failed", RED
        elif log.errors and not evaluated:
            title, tc = "Evaluation failed", RED
        elif log.errors:
            title, tc = "Build failed", RED
        else:
            title, tc = "Build stopped", YELLOW
        left = Text(" ")
        left.append("✘", _st(tc, bold=True))
        left.append(" ")
        left.append(title, _st(tc, bold=True))
        if fb is not None:
            left.append("  ")
            left.append(fb.name, _st(FG, bold=True))
        right = Text(f"after {fmt_dur(log.elapsed())}", _st(DIM))
        lines = [self._lr(left, right, W)]
        if evaluated:
            lines.append(self._stats(W, now, final=True))

        # the box: the failed build's log tail, or nix's own error text
        err_head = _headline(log.errors, log.error_summaries, log.error_positions) if log.errors else ""
        head_rows = min(3, _wrapped_count(err_head, W - 3))
        n = max(3, min(self.max_lines - len(lines) - 2 - head_rows, 25))
        box_title, body = "", []
        if fb is not None:
            box_title = f"{fb.name} · last lines of the log"
            body = log.failed_log(n)
        elif log.errors:
            # the root error in full (an eval trace, a download failure…),
            # unless it says no more than the headline below
            pick = next((i for i, e in enumerate(log.errors) if not _DEP_FAILED.search(e)), 0)
            text = _dedent(log.errors[pick].splitlines())
            if len([t for t in text if t.strip()]) > 1:
                box_title, body = "nix error", text
        body = [shorten_store_paths(b) for b in body][-n:]
        if body:
            lines.extend(self._box(box_title, body, W))
        for i, piece in enumerate(_wrap(err_head, W - 3)[:3] if err_head else []):
            t = Text("   ")
            t.append(piece, _st(RED if i == 0 else mix(RED, FG, 0.55)))
            lines.append(t)
        return lines

    @staticmethod
    def _box(title: str, body: list[str], W: int) -> list[Text]:
        """A rounded box from column 3 to W-1, with ``title`` set in its top edge."""
        B = max(16, W - 4)              # outer width
        inner = B - 4                   # text width (a space either side)
        edge = _st(LINE)
        out = []
        top = Text("   ╭─ ", edge)
        tt = Text(title, _st(RED, bold=True))
        if tt.cell_len > B - 7:
            tt.truncate(B - 7, overflow="ellipsis")
        top.append_text(tt)
        top.append(" " + "─" * max(0, B - tt.cell_len - 5) + "╮", edge)
        out.append(top)
        hot = re.compile(r"\b(error|fatal|failed|failure|cannot|undefined reference|no such)\b", re.I)
        for i, raw in enumerate(body):
            row = Text("   │ ", edge)
            txt = Text(raw)
            if txt.cell_len > inner:
                txt.truncate(inner, overflow="ellipsis")
            last = i == len(body) - 1
            if hot.search(raw):
                color = mix(RED, FG, 0.8)
            elif raw.lstrip().startswith("…"):
                color = DIM
            else:
                color = FG if last else mix(FG, DIM, 0.45)
            txt.stylize(_st(color))
            row.append_text(txt)
            row.append(" " * max(0, inner - txt.cell_len))
            row.append(" │", edge)
            out.append(row)
        out.append(Text("   ╰" + "─" * (B - 2) + "╯", edge))
        return out


def _dedent(lines: list[str]) -> list[str]:
    body = [ln.rstrip() for ln in lines]
    if body and body[0].strip() == "error:" and len(body) > 1:
        body.pop(0)                     # a bare "error:" heading a trace
    while body and not body[0].strip():
        body.pop(0)
    ind = min((len(ln) - len(ln.lstrip()) for ln in body[1:] if ln.strip()), default=0)
    return [body[0].strip()] + [ln[ind:] for ln in body[1:]] if body else []


def _headline(errors: list[str], summaries: list[str], positions: list[str] | None = None) -> str:
    """The one error worth reading: the root failure, in one tidy sentence."""
    pick = 0
    for i, e in enumerate(errors):
        if not _DEP_FAILED.search(e) and "Build failed due to failed dependency" not in e:
            pick = i
            break
    e = errors[pick]
    summary = summaries[pick] if pick < len(summaries) else ""
    pos = positions[pick] if positions and pick < len(positions) else ""
    lines = [ln.strip() for ln in e.splitlines() if ln.strip()]
    if "Cannot build" in e or "builder for" in e or not summary:
        # a build failure: everything up to the list of output paths
        k = next((j for j, ln in enumerate(lines) if ln.startswith("Output paths:")
                  or ln.startswith("last ") or ln.startswith(">")), len(lines))
        s = " ".join(lines[:k])
    else:
        # an evaluation error: nix's own one-liner, plus where it happened
        s = " ".join(ln.strip() for ln in summary.splitlines() if ln.strip())
        if pos:
            s += f"  ({_SOURCE_PREFIX.sub('', pos)})"
    if not s.startswith("error"):
        s = "error: " + s
    return shorten_store_paths(s)


_SOURCE_PREFIX = re.compile(r"^/nix/store/[0-9a-z]{32}-source/|^/nix/store/[0-9a-z]{32}-")


def _wrap(s: str, width: int) -> list[str]:
    width = max(10, width)
    words = s.split(" ")
    out, cur = [], ""
    for w in words:
        if not cur:
            cur = w
        elif cell_len(cur) + 1 + cell_len(w) <= width:
            cur += " " + w
        else:
            out.append(cur)
            cur = w
        while cell_len(cur) > width:
            out.append(cur[:width])
            cur = cur[width:]
    if cur:
        out.append(cur)
    return out


def _wrapped_count(s: str, width: int) -> int:
    return len(_wrap(s, width)) if s else 0
