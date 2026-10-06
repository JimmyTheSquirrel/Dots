"""What the app has done before: one JSON line per job.

$XDG_STATE_HOME/system-rebuild/history.jsonl (~/.local/state/…), appended
when a job ends. It's a log, not configuration — delete it and the app just
forgets (no "last switched", no "usually takes"). It feeds:
  · the machine cards and previews  ("✔ switched 2h ago · 3m 12s")
  · a job's banner                  ("usually ~3m") and its ETA
  · the History screen

Only the app writes it; `system-rebuild rock Asgard` from the command line
doesn't (it would need to share the format from bash — not worth it).
"""
from __future__ import annotations

import json
import os
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

KEEP = 500          # lines kept when the file is trimmed


def path() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "system-rebuild" / "history.jsonl"


@dataclass
class Run:
    kind: str                 # switch / boot / build / update / sync / gc / check / clone
    host: str = ""            # the machine it was for ("" for repo/store jobs)
    ok: bool = False
    t: float = 0.0            # when it started (epoch)
    took: float = 0.0         # seconds, start to finish
    build: float = 0.0        # seconds the nix build itself took (rebuilds)
    result: str = ""          # "switched", "build failed", "stopped", "freed 3.1 GiB", …
    closure: int = 0          # bytes (rebuilds)
    changed: int = 0          # packages that changed (rebuilds), inputs moved (update)
    built: int = 0            # derivations built (rebuilds)
    extra: dict = field(default_factory=dict)


def record(run: Run) -> None:
    """Append RUN; never let the log's trouble become the job's."""
    try:
        p = path()
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("a") as f:
            f.write(json.dumps(asdict(run), separators=(",", ":")) + "\n")
        if p.stat().st_size > KEEP * 600:            # trim now and then, not every time
            lines = p.read_text().splitlines()[-KEEP:]
            p.write_text("\n".join(lines) + "\n")
    except OSError:
        pass
    _cache.clear()


_cache: dict[str, tuple[float, list[Run]]] = {}


def load() -> list[Run]:
    """Every run, oldest first (cached until the file changes)."""
    p = path()
    try:
        m = p.stat().st_mtime
    except OSError:
        return []
    hit = _cache.get("all")
    if hit and hit[0] == m:
        return hit[1]
    runs: list[Run] = []
    try:
        for line in p.read_text().splitlines():
            try:
                d = json.loads(line)
                runs.append(Run(**{k: v for k, v in d.items() if k in Run.__dataclass_fields__}))
            except (ValueError, TypeError):
                continue
    except OSError:
        return []
    _cache["all"] = (m, runs)
    return runs


def last(host: str = "", kinds: tuple[str, ...] = (), ok: bool | None = None) -> Run | None:
    for r in reversed(load()):
        if host and r.host != host:
            continue
        if kinds and r.kind not in kinds:
            continue
        if ok is not None and r.ok != ok:
            continue
        return r
    return None


def typical(host: str, kinds: tuple[str, ...] = ("switch", "boot", "build")) -> float | None:
    """The median time a good rebuild of HOST took, over its last few."""
    took = [r.took for r in reversed(load()) if r.host == host and r.kind in kinds and r.ok and r.took > 0][:7]
    if not took:
        return None
    took.sort()
    return took[len(took) // 2]


def recent(n: int = 40) -> list[Run]:
    """The last N runs, newest first (by when they started — the file is in
    the order they finished)."""
    return sorted(load(), key=lambda r: r.t, reverse=True)[:n]


def durations(host: str, n: int = 16) -> list[float]:
    """Oldest → newest build times of HOST's good rebuilds, for a sparkline."""
    return [r.took for r in load() if r.host == host and r.ok and r.kind in ("switch", "boot", "build")][-n:]


def now() -> float:
    return time.time()
