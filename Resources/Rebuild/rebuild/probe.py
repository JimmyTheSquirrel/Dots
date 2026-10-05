"""Looking things up — the tailnet, the repo, other machines — without blocking.

Everything here is async with a timeout, so the app keeps drawing (and
animating) while a slow ssh or tailscale answers. The bash version asked one
thing at a time and froze while it waited.
"""
from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field
from datetime import datetime

from .hosts import Host, Repo, profile_link


# ── running things ────────────────────────────────────────────────────────────
async def run(argv: list[str], timeout: float = 8, cwd=None, stdin: bytes | None = None) -> tuple[int, str, str]:
    """(returncode, stdout, stderr); 124 on timeout, 127 if it isn't installed."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv, cwd=cwd,
            stdin=asyncio.subprocess.PIPE if stdin is not None else asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    except FileNotFoundError:
        return 127, "", f"{argv[0]}: not found"
    try:
        out, err = await asyncio.wait_for(proc.communicate(stdin), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return 124, "", "timed out"
    except asyncio.CancelledError:
        proc.kill()
        raise
    return proc.returncode or 0, out.decode(errors="replace"), err.decode(errors="replace")


SSH_QUIET = ["-o", "ConnectTimeout=5", "-o", "BatchMode=yes", "-o", "LogLevel=QUIET"]


# ── formatting ────────────────────────────────────────────────────────────────
def ago(epoch: float | None) -> str:
    if not epoch:
        return "never"
    s = max(0, time.time() - epoch)
    if s < 90:
        return "just now"
    if s < 5400:
        return f"{round(s / 60)}m ago"
    if s < 172800:
        return f"{round(s / 3600)}h ago"
    return f"{round(s / 86400)}d ago"


def duration(s: float) -> str:
    s = int(round(s))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m {s % 60:02d}s"
    return f"{s // 3600}h {s % 3600 // 60:02d}m"


def human_bytes(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024 or unit == "TiB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TiB"


def uptime_text(s: float) -> str:
    s = int(s)
    return f"{s // 86400}d {s % 86400 // 3600}h" if s >= 86400 else f"{s // 3600}h {s % 3600 // 60:02d}m"


# ── the tailnet ───────────────────────────────────────────────────────────────
@dataclass
class Peer:
    state: str = "unknown"   # online / offline / missing / unknown
    ip: str = ""
    path: str = ""           # direct / relay xyz / idle
    seen: float | None = None

    def seen_text(self) -> str:
        return "never seen" if not self.seen else f"seen {ago(self.seen)}"


@dataclass
class Tailnet:
    peers: list[dict] = field(default_factory=list)
    ok: bool = False

    def peer(self, name: str) -> Peer:
        """The best match for a HostName starting with NAME (online ones win,
        so "apollo" finds whichever stick is booted)."""
        if not self.ok:
            return Peer()
        n = name.lower()
        hits = [p for p in self.peers if (p.get("HostName") or "").lower().startswith(n)]
        if not hits:
            return Peer("missing")
        hits.sort(key=lambda p: not p.get("Online"))
        p = hits[0]
        path = "direct" if p.get("CurAddr") else (f"relay {p['Relay']}" if p.get("Relay") else "idle")
        seen = None
        ls = p.get("LastSeen") or ""
        if ls and not ls.startswith("0001-"):
            try:
                seen = datetime.fromisoformat(ls.replace("Z", "+00:00")).timestamp()
            except ValueError:
                pass
        return Peer("online" if p.get("Online") else "offline",
                    (p.get("TailscaleIPs") or ["-"])[0], path, seen)


async def tailnet() -> Tailnet:
    rc, out, _ = await run(["tailscale", "status", "--json"], timeout=3)
    if rc != 0 or not out.strip():
        return Tailnet()
    try:
        data = json.loads(out)
    except ValueError:
        return Tailnet()
    return Tailnet(list((data.get("Peer") or {}).values()), True)


async def ping(name: str) -> bool:
    rc, _, _ = await run(["tailscale", "ping", "-c", "1", "--until-direct=false", name], timeout=5)
    return rc == 0


# ── the repo ──────────────────────────────────────────────────────────────────
@dataclass
class RepoStatus:
    branch: str = "?"
    dirty: int = 0
    ahead: int = 0
    behind: int = 0
    files: list[str] = field(default_factory=list)


async def repo_status(repo: Repo) -> RepoStatus | None:
    if not repo.path:
        return None
    (rb, b, _), (rs, st, _), (rc, counts, _) = await asyncio.gather(
        run(["git", "branch", "--show-current"], cwd=repo.path),
        run(["git", "status", "--porcelain"], cwd=repo.path),
        run(["git", "rev-list", "--left-right", "--count", "@{u}...HEAD"], cwd=repo.path))
    files = [l for l in st.splitlines() if l.strip()] if rs == 0 else []
    behind = ahead = 0
    if rc == 0 and counts.split():
        behind, ahead = (int(x) for x in counts.split()[:2])
    return RepoStatus(b.strip() or "?", len(files), ahead, behind, files)


# ── other machines ────────────────────────────────────────────────────────────
@dataclass
class Remote:
    ok: bool = False
    generation: str = "?"
    uptime: float = 0
    checkout: tuple[str, str, str, int] | None = None   # branch, head, when, dirty


async def remote_probe(h: Host) -> Remote:
    """What H is running, how long it's been up, and its own ~/Dots if any."""
    cmd = (f"readlink {profile_link(h.profile)}; cut -d' ' -f1 /proc/uptime;"
           " if [ -d ~/Dots/.git ]; then git -C ~/Dots log -1 --format='%h|%cr';"
           " git -C ~/Dots branch --show-current; git -C ~/Dots status --porcelain | wc -l; fi")
    rc, out, _ = await run(["ssh", *SSH_QUIET, h.target, cmd], timeout=9)
    lines = out.splitlines()
    if rc != 0 or not lines:
        return Remote()
    gen = lines[0].removesuffix("-link").rsplit("-", 1)[-1]
    try:
        up = float(lines[1])
    except (IndexError, ValueError):
        up = 0
    co = None
    if len(lines) >= 5:
        head, _, when = lines[2].partition("|")
        co = (lines[3], head, when, int(lines[4].strip() or 0))
    return Remote(True, gen, up, co)


async def current_system(target: str | None) -> str:
    """The store path of what's running: here (None) or at user@host over ssh."""
    if target is None:
        rc, out, _ = await run(["readlink", "-f", "/run/current-system"], timeout=3)
    else:
        rc, out, _ = await run(["ssh", *SSH_QUIET, target, "readlink -f /run/current-system"], timeout=9)
    return out.strip() if rc == 0 else ""


async def passwordless_sudo(target: str) -> bool:
    rc, _, _ = await run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", target, "sudo -n true"], timeout=9)
    return rc == 0


async def closure_size(path: str) -> int | None:
    rc, out, _ = await run(["nix", "path-info", "-S", path], timeout=30)
    try:
        return int(out.split()[1]) if rc == 0 else None
    except (IndexError, ValueError):
        return None


async def store_free() -> int | None:
    rc, out, _ = await run(["df", "-B1", "--output=avail", "/nix/store"], timeout=3)
    try:
        return int(out.split()[-1]) if rc == 0 else None
    except (IndexError, ValueError):
        return None


async def apollo_mount() -> str:
    rc, out, _ = await run(["findmnt", "-rn", "-o", "TARGET", "-S", "LABEL=Apollo"], timeout=3)
    return out.strip() if rc == 0 else ""


def lock_table(path) -> dict[str, tuple[str, int]]:
    """input → (rev7, lastModified) for every root input of a flake.lock."""
    try:
        data = json.loads(open(path).read())
    except (OSError, ValueError):
        return {}
    nodes, out = data.get("nodes", {}), {}
    for k, v in nodes.get("root", {}).get("inputs", {}).items():
        node = v[-1] if isinstance(v, list) else v
        locked = nodes.get(node, {}).get("locked", {})
        rev = (locked.get("rev") or locked.get("narHash") or "?")[:7]
        out[k] = (rev, int(locked.get("lastModified") or 0))
    return out
