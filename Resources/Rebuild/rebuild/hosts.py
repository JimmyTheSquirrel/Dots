"""The machines, the flake, and what this machine is.

⚠ The host table is kept twice: here, and in host_info() at the top of
Resources/Scripts/system-rebuild.sh (the command-line half of system-rebuild,
which stays bash). A new machine is one line in each.
"""
from __future__ import annotations

import json
import os
import platform
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Host:
    name: str
    user: str       # flake user (the attr is user-name) and its ssh login
    ssh: str        # tailnet name, or "" for none
    profile: str    # "system", a named profile (-p), or "" for a stick
    mode: str       # "push" (deployed from whichever machine runs this) or "stick"
    role: str
    icon: str       # Nerd Font

    @property
    def key(self) -> str:
        return f"{self.user}-{self.name}"

    @property
    def target(self) -> str:
        return f"{self.user}@{self.ssh}"


HOSTS: list[Host] = [
    Host("Sisyphus", "rock", "sisyphus", "sisyphus", "push", "rock's desktop", ""),
    Host("Elektra", "kitkat", "elektra", "system", "push", "her machine", ""),
    Host("Asgard", "rock", "asgard", "system", "push", "media server", ""),
    Host("Apollo", "rock", "", "", "stick", "deployer USB", ""),
]
BY_NAME = {h.name: h for h in HOSTS}

# The machine this runs on, if it is one of ours (DOTS_HOST overrides).
_me = os.environ.get("DOTS_HOST") or platform.node()
THIS: Host | None = next((h for h in HOSTS if h.name.lower() == _me.lower()), None)

DOTS_FLAKE = "github:JimmyTheSquirrel/Dots"
DOTS_URL = "https://github.com/JimmyTheSquirrel/Dots"


@dataclass
class Repo:
    path: Path | None   # the checkout, or None (then rebuilds use DOTS_FLAKE)
    flake: str          # "." (run from path) or DOTS_FLAKE
    label: str          # for display: ~/Dots or the github flake


def find_repo() -> Repo:
    p = Path(os.environ.get("DOTS_DIR") or Path.home() / "Dots")
    if (p / "flake.nix").is_file():
        home = str(Path.home())
        label = "~" + str(p)[len(home):] if str(p).startswith(home + "/") else str(p)
        return Repo(p, ".", label)
    return Repo(None, DOTS_FLAKE, DOTS_FLAKE)


def profile_link(profile: str) -> Path:
    if profile == "system":
        return Path("/nix/var/nix/profiles/system")
    return Path("/nix/var/nix/profiles/system-profiles") / profile


def generation(profile: str) -> tuple[int | None, float | None]:
    """(generation number, when it was made) of this machine's PROFILE."""
    p = profile_link(profile)
    try:
        link = os.readlink(p)
    except OSError:
        return None, None
    num = link.removesuffix("-link").rsplit("-", 1)[-1]
    try:
        when = os.lstat(p.parent / link).st_mtime
    except OSError:
        when = None
    return (int(num) if num.isdigit() else None), when


def lock_age(repo: Repo) -> float | None:
    """When nixpkgs was last locked (epoch), from flake.lock."""
    if not repo.path:
        return None
    try:
        lock = json.loads((repo.path / "flake.lock").read_text())
        node = lock["nodes"]["root"]["inputs"]["nixpkgs"]
        if isinstance(node, list):
            node = node[-1]
        return float(lock["nodes"][node]["locked"]["lastModified"])
    except (OSError, KeyError, ValueError, TypeError):
        return None


def os_version() -> str:
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if line.startswith("VERSION_ID="):
                return line.split("=", 1)[1].strip('"')
    except OSError:
        pass
    return ""
