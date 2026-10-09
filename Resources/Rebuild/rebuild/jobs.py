"""The jobs: what each menu row actually does.

Each is an async function given the JobScreen it runs in (app.JobScreen) and
drawing into it — sections, live views, a result card. They run the same
commands the bash version did, in the same order, with the same safety: a
failed build never activates anything, the running system is only touched by
nixos-rebuild's own activation, and anything that can't be undone asks first.

Every rebuild is three steps (four when it's pushed to another machine):
   reach     a remote target must be on the tailnet — the job waits for it
   build     nix build <flake>#nixosConfigurations.<user>-<Host>.config.system.build.toplevel
   changes   dix <what's running> <what was built>
   activate  nixos-rebuild <switch|boot> --no-reexec --store-path <built path>
             (-p <profile> for a named one; --target-host + --sudo for another machine)
Building first and handing nixos-rebuild the finished store path evaluates
the flake once and keeps all of nixos-rebuild's activation logic: profiles,
the systemd-run wrapper that survives a dropped SSH session, and copying the
closure to a remote host.
"""
from __future__ import annotations

import asyncio
import os
import platform
import shutil
import tempfile
import time
from pathlib import Path

from rich.text import Text

from . import hosts as H
from . import probe as P
from .runner import plain
from .ui import AQUA, BLUE, DIM, FG, GREEN, PURPLE, RED, YELLOW, bad, info, ok, warn

try:
    from .nixmon import BuildMonitor, NixLog, nix_build
except Exception:                            # missing or broken: JobScreen.build falls back to the plain log
    BuildMonitor = NixLog = nix_build = None

I_BUILD, I_DIFF, I_GO, I_NET = "", "", "", ""


def kv(text: str, extra: str = "") -> Text:
    return Text.assemble((text, FG), (f"  ({extra})" if extra else "", DIM))


# ── rebuild ───────────────────────────────────────────────────────────────────
async def rebuild(job, system: H.Host, action: str, target: str | None = None) -> bool:
    """Build SYSTEM here; diff it against what it runs; switch/boot it — here
    when it's this machine, else pushed to TARGET (or its own tailnet name)."""
    repo = job.app.repo
    local = target is None and H.THIS is not None and system.name == H.THIS.name
    host = platform.node() if local else (target or system.ssh)
    if not local and not host and action != "build":
        job.card(False, f"{system.name} is a USB stick", [("", "It can only be built (Rebuild › Other host).")])
        return False
    ssh_target = f"{system.user}@{host}"
    pflag = ["-p", system.profile] if system.profile not in ("system", "") else []
    accent = AQUA if local else BLUE
    reach = not local and action != "build"
    stages = (["Reach"] if reach else []) + ["Build", "Changes"] + ([] if action == "build" else ["Activate"])
    job.begin(stages, accent, action.upper(), system.name,
              "this machine" if local else ("built here · nothing deployed" if action == "build" else f"→ {ssh_target}"),
              system.key, kind=action, host=system.name)
    started = time.monotonic()
    gen_before = H.generation(system.profile)[0] if local else None
    if repo.flake != ".":
        await job.add(info(f"no checkout here — building {repo.flake} (main)"))

    # reach ────────────────────────────────────────────────────────────────────
    if reach:
        job.stage("Reach", "running")
        if not await job.wait_online(host, system.name):
            job.stage("Reach", "failed")
            job.card(False, "Nothing done", [("", f"{host} never came online.")])
            return False
        job.stage("Reach", "done")

    # build ────────────────────────────────────────────────────────────────────
    job.stage("Build", "running")
    sec = await job.section("Build", accent, I_BUILD)
    tmp = None
    if action == "build" and repo.path:
        link = repo.path / "result"          # a plain build leaves ./result, like nix build
    else:
        tmp = tempfile.mkdtemp(prefix="system-rebuild-")
        link = Path(tmp) / "result"          # a GC root for exactly as long as this run needs it
    attr = f"{repo.flake}#nixosConfigurations.{system.key}.config.system.build.toplevel"
    argv = ["nix", "build", attr, "--out-link", str(link), "--print-out-paths"]
    try:
        rc, out = await job.build(sec, argv)
        if rc != 0:
            job.stage("Build", "failed")
            job.card(False, f"Build failed — {system.key}", [
                ("", "Nothing was activated; the running system is untouched."),
                ("full log", Text(f"nix build {attr} -L", AQUA))])
            return False
        built = (out[-1].strip() if out else "") or os.path.realpath(link)
        await sec.mount(ok(f"built in {P.duration(time.monotonic() - started)}", built.split("-", 1)[-1]))
        job.stage("Build", "done")

        # changes ──────────────────────────────────────────────────────────────
        job.stage("Changes", "running")
        sec = await job.section("Changes", accent, I_DIFF)
        current = await P.current_system(None) if local else await P.current_system(ssh_target) if host else ""
        same = bool(current) and current == built
        if same:
            await sec.mount(ok(f"identical to what's running on {system.name} — nothing changed"))
        elif current and os.path.exists(current):
            await job.diff(sec, current, built)
        elif current:
            await sec.mount(info(f"{system.name} runs a system this machine never built — no package diff"))
        elif not host:
            await sec.mount(info(f"{system.name} is a USB stick — nothing running to compare with"))
        else:
            await sec.mount(info(f"couldn't read what {system.name} is running — no package diff"))
        job.stage("Changes", "done")
        sizes = asyncio.gather(P.closure_size(built),
                               P.closure_size(current) if current and os.path.exists(current) else asyncio.sleep(0))

        # activate ─────────────────────────────────────────────────────────────
        verb, nxt = "built", ""
        if action == "build":
            nxt = "nothing activated · ./result → the new system" if repo.path else "nothing activated · in the store until the next GC"
        elif same and action == "switch":
            verb, nxt = "already up to date", "nothing to activate"
            job.stage("Activate", "skipped")
        else:
            job.stage("Activate", "running")
            sec = await job.section(f"Activate · {action}", accent, I_GO)
            if local:
                cmd = ["sudo", "nixos-rebuild", action, *pflag, "--no-reexec", "--store-path", built]
            else:
                # Passwordless sudo still needs --sudo: --ask-sudo-password is
                # what turns remote sudo on (system-rebuild.sh, 2026-10-06).
                quiet = await P.passwordless_sudo(ssh_target)
                await sec.mount(info(f"{host} has passwordless sudo — no password needed" if quiet else
                                     f"{host} will ask for {system.user}'s sudo password — the one on {system.name}"))
                cmd = ["nixos-rebuild", action, *pflag, "--no-reexec", "--store-path", built,
                       "--target-host", ssh_target, "--sudo" if quiet else "--ask-sudo-password"]
            job.cancellable = False                  # never stop an activation halfway
            rc = await job.run(sec, cmd, where=system.name)
            job.cancellable = True
            if rc != 0:
                job.stage("Activate", "failed")
                job.card(False, f"Activation failed — {system.name}", [
                    ("", "The new system is built (it's in the store) but did not activate cleanly."),
                    ("retry", Text(" ".join(cmd), AQUA))])
                return False
            job.stage("Activate", "done")
            verb = "switched" if action == "switch" else "ready for next boot"
            if action == "boot":
                nxt = (f"reboot and pick {system.name} under GRUB's System Select" if local and pflag else
                       "active after the next reboot" if local else f"active after {system.name}'s next reboot")

        # summary ──────────────────────────────────────────────────────────────
        # The numbers go in tiles across the card; the words under them.
        st = job.stats
        tiles = [("took", P.duration(time.monotonic() - started), f"build {P.duration(st.get('build', 0))}")]
        fetched = st.get("fetched", 0)
        tiles.append(("built", str(st.get("built", 0)),
                      f"{fetched} fetched" + (f" · {P.human_bytes(st['fetched_bytes'])}" if st.get("fetched_bytes") else "")))
        if same:
            tiles.append(("changes", "0", "identical to what runs"))
        elif "diff" in st:
            sym = {"upgraded": "↑", "added": "+", "removed": "−", "downgraded": "↓", "changed": "~"}
            tiles.append(("changes", str(st.get("changed", 0)),
                          "  ".join(f"{sym[k]}{n}" for k, n in st["diff"].items()) or "configuration only"))
        new_size, old_size = await sizes
        if new_size:
            st["closure"] = new_size
            delta = ""
            if isinstance(old_size, int):
                d = new_size - old_size
                delta = ("+" if d >= 0 else "−") + P.human_bytes(abs(d))
            tiles.append(("closure", P.human_bytes(new_size), delta or "the whole system"))
        if local and action != "build":
            gen, _ = H.generation(system.profile)
            if gen:
                tiles.append(("generation", str(gen), f"was {gen_before}" if gen_before and gen_before != gen else "unchanged"))
        elif action != "build" and target is None and not same:
            # Ask it what it runs now: the tile, and its card on the home screen.
            before = job.app.probes.get(system.name)
            r = await P.remote_probe(system)
            if r.ok:
                job.app.probes[system.name] = r
                was = before.generation if before and before.ok else ""
                tiles.append(("generation", r.generation, f"was {was}" if was and was != r.generation else "on " + system.name))
        rows: list[tuple[str, Text | str]] = [("host", kv(system.name, system.key))]
        if not local and host:
            rows.append(("target", ssh_target))
        if nxt:
            rows.append(("next", nxt))
        job.card(True, f"{system.name} {verb}", rows, tiles)
        return True
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


# ── utilities ─────────────────────────────────────────────────────────────────
async def check_hosts(job) -> bool:
    """Every host's toplevel evaluates (the drvPath check) — all four at once."""
    repo = job.app.repo
    job.begin(["Evaluate"], YELLOW, "CHECK", "every host evaluates", "nothing is built", repo.label, kind="check")
    t_all = time.monotonic()
    job.stage("Evaluate", "running")
    sec = await job.section(f"{len(H.HOSTS)} hosts, in parallel", YELLOW, "")
    rows = {h.name: await job.spin_line(sec, f"evaluating {h.key}…") for h in H.HOSTS}

    async def one(h: H.Host) -> bool:
        t0 = time.monotonic()
        rc, out, err = await P.run(["nix", "eval", "--raw",
                                    f"{repo.flake}#nixosConfigurations.{h.key}.config.system.build.toplevel.drvPath"],
                                   timeout=900)
        line = rows[h.name]
        if rc == 0:
            drv = out.strip().removeprefix("/nix/store/")
            line.finish(True, f"{h.key:<16}", f"{P.duration(time.monotonic() - t0)} · {drv[:12]}…")
            return True
        tail = [l for l in plain(err).splitlines() if l.strip()][-6:]
        line.finish(False, h.key, "\n".join(tail))
        return False

    results = await asyncio.gather(*(one(h) for h in H.HOSTS))
    fails = results.count(False)
    job.stage("Evaluate", "failed" if fails else "done")
    tiles = [("hosts", f"{len(H.HOSTS) - fails}/{len(H.HOSTS)}", "evaluate"),
             ("took", P.duration(time.monotonic() - t_all), "all at once")]
    if fails:
        job.card(False, f"{fails} of {len(H.HOSTS)} hosts don't evaluate",
                 [("", "The errors are above; nothing was built or changed.")], tiles)
        return False
    job.card(True, f"all {len(H.HOSTS)} hosts evaluate", [("flake", repo.label)], tiles)
    return True


async def update_inputs(job) -> bool:
    repo = job.app.repo
    job.begin(["Fetch", "Changelog"], YELLOW, "UPDATE", "flake inputs", "nix flake update", repo.label, kind="update")
    lock = repo.path / "flake.lock"
    before = P.lock_table(lock)
    job.stage("Fetch", "running")
    sec = await job.section("nix flake update", YELLOW, "")
    rc = await job.run(sec, ["nix", "flake", "update", "--log-format", "raw"])   # raw: no progress bar in the log
    if rc != 0:
        job.stage("Fetch", "failed")
        job.card(False, "nix flake update failed", [("", "The output is above; flake.lock is as it was.")])
        return False
    job.stage("Fetch", "done")
    job.stage("Changelog", "running")
    after = P.lock_table(lock)
    moved = [(n, rev, mod) for n, (rev, mod) in after.items() if rev != before.get(n, ("", 0))[0]]
    changed = len(moved)
    job.stats["changed"] = changed
    if moved:
        sec = await job.section("What moved", YELLOW, "")
        for name, rev, mod in moved:
            orev, omod = before.get(name, ("", 0))
            await sec.mount(_bump(name, orev or "new", rev, omod or mod, mod))
            await asyncio.sleep(0.06)             # one at a time, for the look of it
    job.stage("Changelog", "done")
    if not changed:
        job.card(True, "everything was already up to date", [("flake", repo.label)])
        return True
    newest = max((mod for _, _, mod in moved), default=0)
    job.card(True, f"{changed} input{'s' if changed > 1 else ''} updated",
             [("flake.lock", "changed, not committed")],
             [("moved", str(changed), f"of {len(after)} inputs"), ("newest", P.ago(newest), "commit pulled in")])
    if H.THIS:
        pick = await job.choose(f"Rebuild {H.THIS.name} on the new inputs?",
                                [("switch", "Switch now"), ("build", "Build only (see the diff)"), ("later", "Later")])
        if pick in ("switch", "build"):
            job.next_job(lambda j: rebuild(j, H.THIS, pick))
    return True


def _bump(name: str, old: str, new: str, omod: float, mod: float):
    from .ui import Line
    return Line(Text.assemble(("↑ ", f"bold {AQUA}"), (f"{name:<16}", f"bold {FG}"), (old, DIM), (" → ", DIM),
                              (new, FG), (f"   {P.ago(omod)} → {P.ago(mod)}", DIM)))


async def sync_repo(job) -> bool:
    repo = job.app.repo
    st = await P.repo_status(repo)
    job.begin(["Commit", "Sync"], YELLOW, "SYNC", "git sync", "commit · pull --rebase · push", st.branch if st else "",
              kind="sync")
    msg = ""
    if st and st.dirty:
        sec = await job.section(f"{st.dirty} file{'s' if st.dirty > 1 else ''} changed", YELLOW, "")
        await sec.mount(info("\n".join(st.files[:15]) + (f"\n… and {st.dirty - 15} more" if st.dirty > 15 else "")))
        msg = await job.ask_text("Commit message", "chore: sync")
        if msg is None:
            job.card(False, "Nothing done", [("", "No commit, nothing pushed.")])
            return False
    job.stage("Commit", "done" if msg else "skipped")
    job.stage("Sync", "running")
    sec = await job.section("git-sync", YELLOW, "")
    rc = await job.run(sec, ["git-sync", msg] if msg else ["git-sync"])
    job.stage("Sync", "done" if rc == 0 else "failed")
    if rc != 0:
        job.card(False, "Sync didn't finish", [("", "The output is above.")])
        return False
    job.card(True, "in sync with origin", [("branch", st.branch if st else "?")])
    return True


async def reset_repo(job) -> bool:
    """Make ~/Dots exactly GitHub's main — the "just overwrite it" pull. What
    would go (changed files, files git doesn't track, commits that are on no
    branch on GitHub) is listed first and asked about — twice when anything
    would be lost — and kept before the reset: the files in a stash, the
    commits on a backup/reset-<when> branch. Files git ignores (result links,
    .direnv) are left alone. Git sync is the one that keeps your changes and
    brings GitHub's in."""
    repo = job.app.repo
    job.begin(["Fetch", "Check", "Overwrite"], YELLOW, "RESET", "match GitHub", "overwrite ~/Dots with origin/main",
              repo.label, kind="reset")

    def git(*a: str):
        return P.run(["git", *a], timeout=30, cwd=repo.path)

    job.stage("Fetch", "running")
    sec = await job.section("git fetch", YELLOW, "")
    if await job.run(sec, ["git", "fetch", "--prune", "origin"]) != 0:
        job.stage("Fetch", "failed")
        job.card(False, "Couldn't reach GitHub", [("", "Nothing was changed. The output is above.")])
        return False
    job.stage("Fetch", "done")
    job.stage("Check", "running")
    if (await git("rev-parse", "-q", "--verify", "origin/main"))[0] != 0:
        job.stage("Check", "failed")
        job.card(False, "GitHub has no main branch", [("", "Nothing was changed.")])
        return False
    (_, branch, _), (_, st, _), (_, lost, _), (_, behind, _), (_, head, _), (_, main, _), (_, now, _), (_, then, _) = \
        await asyncio.gather(git("branch", "--show-current"), git("status", "--porcelain", "--untracked-files=all"),
                             git("log", "--format=%h %s", "HEAD", "--not", "--remotes"),
                             git("rev-list", "--count", "HEAD..origin/main"), git("rev-parse", "HEAD"),
                             git("rev-parse", "origin/main"), git("log", "-1", "--format=%h %s", "HEAD"),
                             git("log", "-1", "--format=%h %s", "origin/main"))
    files = [l for l in st.splitlines() if l.strip()]
    commits = [l for l in lost.splitlines() if l.strip()]
    branch, then = branch.strip(), then.strip()
    if not files and not commits and branch == "main" and head.strip() == main.strip():
        job.stage("Check", "done")
        job.stage("Overwrite", "skipped")
        job.card(True, "already exactly GitHub's main", [("main", then)])
        return True
    sec = await job.section("What changes", YELLOW, "")
    await sec.mount(info(f"now      {branch or 'no branch'} · {now.strip()}"))
    await sec.mount(info(f"becomes  main · {then}"))
    n = int(behind.strip() or 0)
    if n:
        await sec.mount(info(f"brings in {n} new commit{'s' if n > 1 else ''} from GitHub"))
    if files:
        sec = await job.section(f"{len(files)} file{'s' if len(files) > 1 else ''} changed or not in git — these go",
                                RED, "")
        await sec.mount(info("\n".join(files[:15]) + (f"\n… and {len(files) - 15} more" if len(files) > 15 else "")))
    if commits:
        one = len(commits) == 1
        sec = await job.section(f"{len(commits)} commit{'' if one else 's'} that {'isn' if one else 'aren'}'t on GitHub — "
                                f"{'it goes' if one else 'these go'}", RED, "")
        await sec.mount(info("\n".join(commits[:10]) + (f"\n… and {len(commits) - 10} more" if len(commits) > 10 else "")))
    job.stage("Check", "done")

    def cancelled() -> bool:
        job.stage("Overwrite", "skipped")
        job.card(False, "Nothing done", [("", "~/Dots is as it was.")])
        return False

    # The safe answer comes first, so a stray ⏎ never overwrites anything.
    if await job.choose("Overwrite ~/Dots with GitHub's main?", [("no", "Cancel"), ("go", "Overwrite")],
                        "~/Dots becomes exactly what's on GitHub.", danger=True) != "go":
        return cancelled()
    if files or commits:
        lose = " and ".join(x for x in (
            f"{len(files)} changed file{'s' if len(files) > 1 else ''}" if files else "",
            f"{len(commits)} unpushed commit{'s' if len(commits) > 1 else ''}" if commits else "") if x)
        if await job.choose(f"Sure? {lose} will leave ~/Dots.", [("no", "No, keep them"), ("go", "Yes, overwrite")],
                            "A copy is kept first (a stash for the files, a backup branch for the commits), "
                            "so they can still be got back.", danger=True) != "go":
            return cancelled()
    job.stage("Overwrite", "running")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    sec = await job.section("Overwrite", YELLOW, "")
    kept: list[tuple[str, str]] = []
    if files:
        if await job.run(sec, ["git", "stash", "push", "--include-untracked", "-m", f"before reset {stamp}"]) != 0:
            job.stage("Overwrite", "failed")
            job.card(False, "Couldn't put the changes aside", [("", "So nothing was overwritten. The output is above.")])
            return False
        kept.append(("files", f"stash \"before reset {stamp}\" — git stash list"))
    if commits:
        if await job.run(sec, ["git", "branch", f"backup/reset-{stamp}", "HEAD"]) != 0:
            job.stage("Overwrite", "failed")
            job.card(False, "Couldn't keep the commits", [("", "So nothing was overwritten. The output is above.")])
            return False
        kept.append(("commits", f"branch backup/reset-{stamp}"))
    rc = await job.run(sec, ["git", "checkout", "-B", "main", "origin/main"])
    if rc == 0:
        rc = await job.run(sec, ["git", "branch", "--set-upstream-to=origin/main", "main"])
    job.stage("Overwrite", "done" if rc == 0 else "failed")
    if rc != 0:
        job.card(False, "The overwrite didn't finish", [("", "The output is above.")] + kept)
        return False
    _, new, _ = await git("log", "-1", "--format=%h %s")
    job.card(True, "~/Dots is GitHub's main", [("main", new.strip())] + kept,
             [("pulled", str(n), "new commits"), ("kept", str(len(kept)), "copies of yours")])
    if H.THIS:
        pick = await job.choose(f"Rebuild {H.THIS.name} on it?",
                                [("switch", "Switch now"), ("build", "Build only (see the diff)"), ("later", "Later")])
        if pick in ("switch", "build"):
            job.next_job(lambda j: rebuild(j, H.THIS, pick))
    return True


async def clone_repo(job) -> bool:
    dest = Path(os.environ.get("DOTS_DIR") or Path.home() / "Dots")
    job.begin(["Clone"], YELLOW, "CLONE", "the repo", H.DOTS_URL, str(dest), kind="clone")
    if dest.exists():
        job.card(False, f"{dest} already exists", [])
        return False
    job.stage("Clone", "running")
    sec = await job.section("git clone", YELLOW, "")
    rc = await job.run(sec, ["git", "clone", H.DOTS_URL, str(dest)])
    job.stage("Clone", "done" if rc == 0 else "failed")
    if rc != 0:
        job.card(False, "Clone failed", [])
        return False
    job.app.reload_repo()
    job.card(True, "cloned", [("", "Rebuilds now use it; Git sync and Update inputs are in Utilities.")])
    return True


async def collect_garbage(job) -> bool:
    job.begin(["Collect"], YELLOW, "GC", "garbage collect", "old generations · store · docker", platform.node(),
              kind="gc")
    pick = await job.choose("Collect garbage now?", [("yes", "Yes — delete every old generation"), ("no", "No")],
                            detail="You can't roll back past the current generation afterwards.", danger=True)
    if pick != "yes":
        job.card(False, "Nothing done", [])
        return False
    before = await P.store_free()
    job.stage("Collect", "running")
    sec = await job.section("nix-gc", YELLOW, "")
    rc = await job.run(sec, ["nix-gc"], where=platform.node())
    after = await P.store_free()
    job.stage("Collect", "done" if rc == 0 else "failed")
    if rc != 0:
        job.card(False, "Garbage collection didn't finish", [("", "The output is above.")])
        return False
    freed = max(0, (after or 0) - (before or 0))
    job.card(True, f"freed {P.human_bytes(freed)}", [],
             [("freed", P.human_bytes(freed), "old generations + store"), ("free now", P.human_bytes(after or 0), "in /nix/store")])
    return True
