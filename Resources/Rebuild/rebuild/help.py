"""The help pages: one per section, plus the basics, the machines, the command
line and the words. A page is a list of blocks — (head, text), (text, …),
(note, …), (item, label, text), (key, label, text), (cmd, command, text) —
drawn by app.HelpScreen. `?` on a menu opens that menu's page.

The bash half (`system-rebuild help`, the classic menus) keeps its own copy of
these pages in system-rebuild.sh — that's what the command line prints.
"""
from __future__ import annotations

from .hosts import HOSTS

AQUA, BLUE, PURPLE, YELLOW, RED, GREEN = "#8ec07c", "#83a598", "#d3869b", "#fabd2f", "#fb4934", "#b8bb26"

BASICS = [
    ("head", "What this is"),
    ("text", "The control panel for this repo: rebuild the machine you're on, deploy to the others over the "
             "tailnet, keep the repo and the Nix store tidy, and drive the Apollo USB. Every job is also a "
             "plain command (see Command line)."),
    ("head", "The home screen"),
    ("item", "DOTS line", "Where the repo is up to: the branch; ✔ clean or ● N changed (files not committed "
             "yet); ↑ commits waiting to be pushed, ↓ waiting to be pulled; and locked, how long ago the flake "
             "inputs were last updated."),
    ("item", "MACHINES", "◆ this machine, and its generation (how many times it has been rebuilt). For the "
             "others: ● online, ○ offline (with when it was last seen) or ◌ not on the tailnet; direct or relay "
             "is how Tailscale reaches it, then its tailnet IP. It refreshes by itself every half minute."),
    ("text", "Every menu ends with Help — what each of its rows does — and Back."),
    ("head", "Keys"),
    ("key", "↑ ↓  j k", "move"),
    ("key", "⏎  →  l", "pick the highlighted row"),
    ("key", "1 – 9", "pick a numbered row straight away"),
    ("key", "esc  ←  h", "back one menu"),
    ("key", "?", "help for the menu you're in — or pick its Help row"),
    ("key", "r", "refresh the machines and the repo now"),
    ("key", "q", "quit"),
    ("note", "A job takes the screen while it runs: the build drawn live, then the package changes, then the "
             "activation's own output. When it's done, ⏎ or esc goes back to the menu and q leaves. The mouse "
             "works too: click a row, scroll a log."),
    ("head", "Passwords and questions"),
    ("text", "When sudo wants a password, or ssh asks whether to trust a machine it hasn't met, a box pops up "
             "and asks you instead — the password is typed straight into that one command, never shown, logged "
             "or kept. esc in the box stops the command."),
    ("head", "Colours"),
    ("item", "red rows", "overwrite or erase something you can't easily undo (INSTALL). They always ask before "
             "doing anything."),
    ("item", "green card", "the job worked: what it did, how long it took, the new generation."),
    ("item", "red card", "it didn't, and what that left behind. A failed build never activates anything."),
]

REBUILD = [
    ("text", "Rebuild works on the machine you're sitting at. Every rebuild is the same three steps: Build (drawn "
             "live — every derivation building, every download, how far along it all is), Changes (dix lists "
             "every package added, removed or updated against what's running now), then Activate. If the build "
             "fails, nothing is activated — the running system is untouched."),
    ("head", "This machine"),
    ("item", "Switch", "Build, show the changes, and switch to the new system now. Services restart as needed; "
             "no reboot."),
    ("item", "Boot", "Build and show the changes, but only make it the system the NEXT boot starts. For kernel, "
             "driver or boot changes, or when you don't want things restarting under you. Sisyphus has its own "
             "boot entry: reboot and pick Sisyphus under GRUB's System Select."),
    ("item", "Build", "Build and show the changes, activate nothing. ./result points at the new system. The safe "
             "way to see what an edit does."),
    ("item", "Other host", "Build another machine's config here and diff it against what that machine runs. "
             "Deploys nothing — a quick check that a change to Kit-Kat or Asgard builds."),
    ("head", "Going back"),
    ("text", "Each Switch or Boot adds a generation, and the boot menu lists them: to undo a bad rebuild, reboot "
             "and pick the one before. Garbage collect deletes the old ones."),
    ("note", "No ~/Dots on this machine? It builds GitHub's main instead, and Utilities offers to clone the repo."),
]

REMOTE = [
    ("text", "Remote deploys to the other machines over Tailscale. The build happens HERE; the finished system "
             "is copied across and activated there. A machine with passwordless sudo (Asgard) just goes; one "
             "that wants a password asks for it in a box — the password on THAT machine, not this one's."),
    ("note", "Opening a machine shows it live: online or offline and, asked over ssh, the generation it runs, "
             "how long it's been up, and its own ~/Dots if it has one. If it's offline when you pick a job, the "
             "job waits for it — power it on and it carries on by itself — or press t to try anyway."),
    ("head", "Every machine is pushed from here"),
    ("item", "Switch", "build here, copy it over, activate now"),
    ("item", "Boot", "the same, but active from its next reboot"),
    ("item", "Build", "build here and diff against what it runs — nothing is deployed"),
    ("item", "SSH", "open a shell on it (the app steps aside until you log out)"),
]

UTILS = [
    ("item", "Git sync", "Commit every change (it asks for a message), pull --rebase, push. Anything it can't "
             "commit is stashed and put back. The same as running git-sync."),
    ("item", "Update inputs", "nix flake update: fetch the newest nixpkgs, home-manager and every other input, "
             "then list what moved (old → new, and how old each was). flake.lock changes but isn't committed. "
             "Then it offers to Switch, Build only (to see the diff), or leave it for later."),
    ("item", "Garbage collect", "Delete every old generation, then everything in the Nix store only they used; "
             "hard-link duplicate files; on Sisyphus also prune stopped Docker containers. Frees disk space, but "
             "you can't roll back past the current generation afterwards — it asks first."),
    ("item", "Check hosts", "Evaluate all four machines' configs at once, building nothing. A fast \"did my "
             "edit break something\" check; a failure shows its error."),
    ("item", "Get the repo", "Only on a machine without ~/Dots (Kit-Kat, usually): clone it, so Git sync and "
             "Update inputs work there. Until then, rebuilds use GitHub's main."),
    ("note", "A weekly automatic garbage collect runs anyway; this one is \"do it now, and delete every old "
             "generation\"."),
]

APOLLO = [
    ("text", "Apollo is the deployer USB stick: a NixOS live system that joins the tailnet by itself when a "
             "computer boots from it, so a machine can be installed from here. On the Apollo menu, stick says "
             "whether a computer booted from it is on the tailnet, and usb whether the stick is plugged into "
             "THIS machine."),
    ("item", "Deploy", "Install one of the machines onto the computer booted from the stick. Pick the machine, "
             "then:"),
    ("item", "  Dry run", "print the script that will partition the disks. Read the disk name in it. Changes "
             "nothing."),
    ("item", "  VM test", "try that disk layout in a throwaway VM. Changes nothing."),
    ("item", "  INSTALL", "ERASES that computer's disks and installs the machine. You type its name to confirm."),
    ("item", "SSH", "connect to the booted stick (waits for it to appear first)"),
    ("item", "Build ISO", "build the Apollo image and copy it onto the stick"),
    ("item", "Tailnet key", "write the Tailscale auth key onto the stick so it can join the tailnet by itself. "
             "Keys expire after 90 days: run this again then."),
    ("note", "These run as their own commands: the app steps aside while they do, and comes back after."),
]


def _machines():
    out = []
    for h in HOSTS:
        mode = ("Pushed: rebuilt from whichever machine runs this (in place when it's this one)."
                if h.mode == "push" else
                "A USB stick: its image is built (Apollo › Build ISO), never switched to.")
        extra = "" if h.profile in ("system", "") else f" Its own profile ({h.profile}): its own entry under GRUB's System Select."
        out.append(("item", f"{h.icon}  {h.name}", f"{h.role} · {h.key}. {mode}{extra}"))
    out.append(("note", "\"This machine\" is whichever one system-rebuild runs on: the same menu on Kit-Kat "
                        "rebuilds Kit-Kat in place."))
    return out


CLI = [
    ("cmd", "system-rebuild", "this app"),
    ("cmd", "system-rebuild --classic", "the old inline menus, drawn in the scrollback"),
    ("cmd", "system-rebuild help", "every help page, printed"),
    ("cmd", "system-rebuild rock Sisyphus", "switch Sisyphus — in place on Sisyphus, pushed from anywhere else"),
    ("cmd", "system-rebuild rock Sisyphus --boot", "the same, for the next boot instead"),
    ("cmd", "system-rebuild rock Sisyphus --build", "build and show the changes only"),
    ("cmd", "system-rebuild kitkat Kit-Kat", "push to Kit-Kat (on Kit-Kat: rebuild in place)"),
    ("cmd", "system-rebuild rock Asgard", "push to Asgard (every machine is deployed from here now)"),
    ("cmd", 'git-sync ["message"]', "commit, pull --rebase, push"),
    ("cmd", "nix-gc", "garbage collect now"),
    ("cmd", "apollo-iso · apollo-key · apollo-connect", "build the stick's image · its tailnet key · SSH to it"),
    ("cmd", "apollo-deploy [--dry-run|--vm-test] kitkat-Kit-Kat", "install a machine onto the computer booted "
            "from the stick"),
]

WORDS = [
    ("item", "generation", "One numbered version of a machine's system. Every Switch or Boot makes a new one, and "
             "the boot menu lists them, so an older one can always be booted."),
    ("item", "profile", "A machine's list of generations. Sisyphus keeps its own (sisyphus), which is its own "
             "entry under GRUB's System Select."),
    ("item", "switch · boot", "Make the new system live now · from the next reboot."),
    ("item", "closure", "A system plus everything it needs: what gets built, and what's copied to another "
             "machine. The summary shows its size, and how much it grew or shrank."),
    ("item", "flake inputs", "The outside sources this repo builds from — nixpkgs, home-manager, noctalia and "
             "the rest — pinned to exact versions in flake.lock. Update inputs moves the pins forward."),
    ("item", "tailnet", "The private Tailscale network the machines reach each other over. direct means a "
             "straight connection; relay means through Tailscale's relay — it works, just slower."),
    ("item", "store · GC", "/nix/store holds everything ever built; garbage collection deletes whatever no "
             "remaining generation uses."),
    ("item", "derivation", "One thing to build — a package, a config file, the system itself. The build view "
             "lists the ones building right now."),
    ("item", "dix", "Lists the package changes between two systems: the Changes step."),
]

# key → (title, accent, icon, blocks)
PAGES = {
    "basics": ("Getting around", GREEN, "", BASICS),
    "rebuild": ("Rebuild", AQUA, "", REBUILD),
    "remote": ("Remote", BLUE, "", REMOTE),
    "utils": ("Utilities", YELLOW, "", UTILS),
    "apollo": ("Apollo", PURPLE, "", APOLLO),
    "machines": ("The machines", GREEN, "", _machines()),
    "cli": ("Command line", GREEN, "", CLI),
    "words": ("Words", GREEN, "", WORDS),
}
