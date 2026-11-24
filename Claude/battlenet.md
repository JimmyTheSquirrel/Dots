# Battle.net — the Blizzard launcher under Proton, no Steam client

**Module:** `Modules/Gaming/battlenet.nix` · **Script:** `Resources/Scripts/battlenet.sh`
**Host:** Sisyphus only (`Hosts/Sisyphus/system.nix`)
**Status:** ✅ built, switched, launched and logged in — verified live 2026-11-22.
World of Warcraft installs to `C:\Program Files (x86)\World of Warcraft\` inside the
prefix, which is correct.

There is no Battle.net package in nixpkgs, nothing in nix-gaming, and the only
community flake calling itself one (`lytedev/battlenet-flake`) is a `nix develop`
shell last touched in 2023 that tells you to follow the wiki's wine steps by hand.
So this is ours.

## The commands

```bash
battlenet                    # launch; installs the client on the first run
battlenet --reinstall        # re-run the Blizzard installer over this prefix
battlenet --prefix DIR       # another prefix (absolute path or exit 2)
battlenet --exe PATH         # run some other .exe in this prefix
battlenet --log              # PROTON_LOG=1, log lands in ~/
battlenet --update-runtime   # let umu update the Steam Linux Runtime
battlenet -- ARGS...         # pass ARGS through to the launcher
```

Plus the desktop entry (**Battle.net**, real Blizzard logo, category Game).

## 🔑 Why `umu-run` and not wine

`umu-run` **is** Proton outside Steam — the Open-Wine-Components launcher that
Lutris, Heroic and Bottles all moved to. It takes the very same GE-Proton build
Steam uses here (`PROTONPATH` points straight at the store path
`programs.steam.extraCompatPackages` already pulls in), runs it inside the same
Steam Linux Runtime container, and involves **no Steam client at all**.

The alternative — the NixOS wiki's wine-staging prefix — is the route where the
login screen crashes and people trade `WINE_SIMULATE_WRITECOPY=1` hacks around.
Battle.net is a well-trodden *Proton* target; it is not a well-trodden *bare wine*
one. Don't "simplify" this to `pkgs.wine`.

## ⚠️ What is NOT declarative, and why it cannot be

Two genuine exceptions to the CLAUDE.md core principle, not oversights:

1. **The Wine prefix** (`~/Games/Battle.net`). Imperative state by construction,
   exactly like Steam's `compatdata`. Nothing reproduces a prefix from a config file.
2. **The Steam Linux Runtime container.** umu reads `require_tool_appid` out of the
   Proton's `toolmanifest.vdf` and downloads that runtime into `~/.local/share/umu`
   (cache `~/.cache/umu`) on first launch — a few hundred MB. nixpkgs has no
   sniper/steamrt4 container to substitute, so there is no Nix answer. It self-heals
   if deleted, and `UMU_RUNTIME_UPDATE=0` is pinned so it never moves under a working
   install (`--update-runtime` opts in).

And the Battle.net client self-updates the moment it starts, so pinning the installer
buys a reproducible **first byte** and nothing else.

**What Nix does own:** the launcher command, the Proton build, the installer's first
byte, the icon, the desktop entry, and the font-registry sweep. A fresh install needs
no manual steps — the first `battlenet` builds the prefix and installs the client —
but it does need **the network**, which is the honest limit here.

## The Proton knob

`my.battlenet.protonPackage` (default `pkgs.proton-ge-bin`) is deliberately an option
and not a constant:

- ⚠️ **`.steamcompattool`, not the package.** `proton-ge-bin`'s default output is a
  **112-byte file** (a marker `programs.steam` consumes); the actual tree — `proton`,
  `files/`, `protonfixes/`, `toolmanifest.vdf` — hangs off that passthru. `PROTONPATH`
  aimed at the package resolves to a non-directory and umu fails on it.
- The newest Proton is not automatically the right one. See
  `black-desert-proton-experimental-regression`: a game that worked in September broke
  in November with no local change and the fix was rolling Proton **back**. If the
  launcher breaks after a `nix flake update`, pinning an older GE here is the cheap
  first move — **not** a new prefix.
- It decides which container umu downloads. GE-Proton11 wants appid **4183110**
  (steamrt4); GE-Proton10 wants **1628350** (sniper), which has far more mileage.
  Changing this can mean a second few-hundred-MB fetch.

`GAMEID=umu-battlenet` / `STORE=battlenet`: `battlenet` is a real protonfixes store
namespace (GE-Proton ships a `gamefixes-battlenet` package), it just has no per-game
fix in it, so this resolves to the default fix — which is what we want.

## The prefix

`my.battlenet.prefix` (null → `$HOME/Games/Battle.net`). The C: drive is
`<prefix>/pfx/drive_c`, because Proton appends `/pfx` to `STEAM_COMPAT_DATA_PATH`.

- ⚠️ **Verified 2026-11-22, and it is NOT shaped like a Steam compatdata:** with
  `WINEPREFIX` set explicitly, umu builds the prefix *directly in it* and makes `pfx`
  a **symlink to `.`** — so `<prefix>/pfx` and `<prefix>` are the same directory, same
  inode, and `ls` shows `drive_c` twice. Going through `/pfx` is correct either way,
  so don't "fix" those paths in the script after seeing that symlink.
- ⛔ **This is where the installed games live.** Treat it exactly like `compatdata` —
  never sweep it (`sisyphus-disk-reclaim-sweep`).

## The font-registry sweep — recurs after every `nix-gc`

`sweep_dead_fonts()` in the script, run before every launch. Home Manager hands
fontconfig a **raw `/nix/store` path** for its font directory, which changes every
generation; Wine bakes whichever path it saw into the prefix registry. After a
`nix-gc` those paths are gone and the next `wineboot --init` drops into Wine's
case-insensitive path fallback: a full enumeration of `/nix/store`, **per dead font,
forever**. The symptom is not an error, it's the launcher never appearing. This
wedged six Steam prefixes on 2026-11-11, one with 12,339 dead entries
(`fontconfig-stale-cache-wedges-proton`).

Three things in it are load-bearing, all verified against a synthetic registry:

- ⛔ **It refuses to run while *any* `wineserver` is up** — a live wineserver holds its
  own copy of the registry in memory and writes it back over ours on exit. Any
  wineserver counts, including one from a Steam game in a different prefix, so
  *skipping* is the safe answer, not a narrower match. (This guard fired for real
  during testing.)
- It anchors on the literal `store\\` the registry writes, **not** on a bare 32-char
  run — an MD5-looking `"Checksum"` value would match that and lose its line.
- It deletes **value lines only** (those starting with `"`). Deleting a section header
  that happened to mention a dead path would orphan every value under it into the
  preceding key.

Backs up to `<reg>.bak` once, writes *through* the file (`cat tmp > reg`) to keep inode
and mode, and is idempotent.

## The icon

`battlenetIcon`, a `runCommand` that pulls the logo out of the **pinned installer FOD**
with `wrestool -x -t 14` at build time, into `share/icons/hicolor/<size>/apps/` at all
seven sizes (16 → 256). Blizzard's stub carries the same 112322-byte icon group as the
installed client, so nothing has to be committed or fetched separately.

- ⚠️ **`icotool` aborts partway on this `.ico` and exits 1:**
  `incorrect total size of bitmap (10068 specified; 4264 real)` — one entry in the
  group has a corrupt size field. It still writes everything it decoded *before*
  reaching that entry, so the exit code is ignored on purpose (`|| true`) and sizes are
  derived from the output filenames. ⛔ Do **not** "fix" this by looping with
  `icotool -w <size>`: only the sizes ordered before the bad entry survive, which
  silently yields **256x256 alone**.
- The derivation ends in a `test -e` so a future Blizzard restructure fails the
  **build** instead of quietly shipping a cog again.
- 🔑 **Postmortem (the "generic cog", 2026-11-22):** the art was always right. The
  first version extracted the icon at *runtime* into `~/.local/share/icons`, which is
  **not on `XDG_DATA_DIRS`** here, while the desktop entry is written to
  `/etc/profiles/per-user/<user>/share/applications`. `Icon=battlenet` was resolved
  against a directory the launcher never searched. It was also wrong on principle —
  no icon until after a successful first launch. The orphaned
  `~/.local/share/icons/hicolor/256x256/apps/battlenet.png` has been removed.

## ⚠️ The window: app-id is `steam_app_battlenet`

Verified live with `niri msg windows`, **not** the obvious `battle.net.exe`: umu sets
`SteamAppId=battlenet` from `GAMEID`, so Proton stamps `WM_CLASS` as
`steam_app_battlenet`. That is the desktop entry's `StartupWMClass`.

**⏸ Open, flagged not fixed:** it therefore **matches the generic games rule** in
`Modules/Desktop/niri.nix` —

```kdl
window-rule {
  match app-id="^steam_app_"
  open-on-output "DP-2"
  open-fullscreen true
}
```

— so a *launcher* gets opened fullscreen on DP-2 by a rule written for *games*.
Nothing is visibly broken with it (and `Claude/niri.md` explains why that rule must
not simply be deleted — `niri-rule-reapplies-on-window-recreate`), so an exclusion
was proposed and deliberately **not** applied. Decide it before adding any more
umu-launched apps, because every one of them will inherit the same collision.

## ⛔ The white screen is NOT a bug — it is the pre-login window

The large blank white window on first launch is simply Battle.net's main window before
you sign in. **Logging in resolves it.** Three hypotheses were burned on it; don't
repeat them:

1. ⛔ **GPU / hardware acceleration** — wrong. Zero GPU errors in any log.
2. ⛔ **Network** — wrong. The frontend log shows `UAuth: finished loading.
   statusCode=200`. The `connect failed: 10051` flood is IPv6 attempts dying on this
   LAN's dead v6 route (`lan-ipv6-broken`) and is harmless noise.
3. ⛔ **Setting `HardwareAcceleration=false` in `Battle.net.config`** — never took
   effect, and Battle.net **overwrote the config on exit**, dropping the key. ⚠️ That
   file is **CRLF**, so `$`-anchored sed/awk silently matches nothing and exits 0 —
   the same trap as `black-desert-proton-experimental-regression`.

**The working setup is stock.** No config edits, no env overrides.

## Steam independence — what was actually proven

Asked directly ("does it need Steam open?"), the answer is no, and structurally:

- Proton comes from `/nix/store`, not from a Steam library.
- The container is umu's own `~/.local/share/umu/steamrt4`; Steam's
  `SteamLinuxRuntime_4` sits untouched.
- `STEAM_COMPAT_CLIENT_INSTALL_PATH` is empty.
- The live process tree is
  `battlenet → bwrap → umu-run → srt-bwrap → pv-adverb → proton → umu.exe → Battle.net.exe`
  — no Steam process anywhere in it.

⚠️ **Caveat, stated honestly:** Steam happened to be running during every test, so this
is *structural* proof, not an observation with Steam closed.

## Bumping the installer pin

No hurry — it's a 4.7MB stub whose only job is to download a client that then
self-updates, so a stale pin costs nothing. The unversioned `getInstaller?...` URL
302s to a versioned one which **is** stable and so is pinnable; the redirect target
is not.

```bash
curl -sIL 'https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe' | grep -i ^location
nix store prefetch-file <that URL>
```

Then update `installerVersion` + `installerHash` at the top of the module. ⚠️ The icon
derivation reads this same FOD, so a bump re-extracts the icon — if upstream
restructures its resources the `test -e` fails the build, by design.

## Troubleshooting order

1. **Launcher won't appear at all after a `nix-gc`** → the font sweep. It runs
   automatically; if a wineserver was up it *skipped*, so close every Proton game and
   re-run `battlenet`.
2. **Broke after a `nix flake update`** → pin an older `my.battlenet.protonPackage`
   before touching anything else.
3. **Broke after a Battle.net client update** → `battlenet --reinstall` (upstream's
   own documented fix; re-runs the installer over the existing prefix, keeping games).
4. **Need a log** → `battlenet --log`, lands in `~/`.
5. ⚠️ **Installer copied out of the store first** (`$prefix/installer/`) on purpose:
   it unpacks beside itself and Proton exports the exe's directory as
   `STEAM_COMPAT_INSTALL_PATH`, which must not be read-only.
6. ⚠️ **Keep the prefix under `$HOME`.** A smoke test in a `/tmp` scratchpad produced
   an empty prefix and `WARNING: Executable not found` — umu's
   `Path.resolve(strict=True)` couldn't resolve the path from inside
   bwrap/pressure-vessel.
