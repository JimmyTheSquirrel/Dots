# Next Up — open work

Backlog for this repo. Nothing here is broken *today*; these are gaps that only
bite on a **fresh install**, plus a few loose ends worth closing.

Ordered roughly by value. Written 2026-09-15, extended 2026-09-27 (items 7–8).

⚠️ **Two exceptions to "nothing here is broken today":** item 8 — Sisyphus has real fixes
living only as hand-edits, waiting on a `nixos-rebuild switch` — and the **2026-11-01
media-stack section** at the bottom, where a film is occupying a TV episode slot and TV is
still acquiring unplayable Dolby Vision.

---

## 1. Wallpapers into the repo ⭐ planned

**Goal:** curated wallpapers live in `Resources/Wallpapers/`, and a fresh install
gets them automatically.

Today `~/Pictures/Wallpapers` (46 MB) is **not in the repo and not referenced by
it**, so a fresh install brings up a working selector with an empty library.

### ⚠️ It must be a COPY, not a symlink

skwd writes *into* the wallpaper directory:

```
~/Pictures/Wallpapers/effects/          recoloured theme-designer variants
~/Pictures/Wallpapers/.skwd-wall-v2/    skwd's own state — 13 MB
```

So `home.file."Pictures/Wallpapers"` (a read-only store symlink) would break the
theme designer and the effects workbench. Use an activation script with
**no-clobber** semantics instead, so repo wallpapers seed the directory while
anything added later by hand survives:

```nix
home.activation.seedWallpapers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  mkdir -p "$HOME/Pictures/Wallpapers"
  # -n: never overwrite. Repo is the seed, not the authority — skwd and the user
  # both write here, and a rebuild must not clobber that.
  ${pkgs.coreutils}/bin/cp -rn ${../Resources/Wallpapers}/. "$HOME/Pictures/Wallpapers/" || true
  # Store files are 0444; make the copies writable or skwd cannot manage them.
  ${pkgs.findutils}/bin/find "$HOME/Pictures/Wallpapers" -type f ! -writable \
    -exec ${pkgs.coreutils}/bin/chmod u+w {} +
'';
```

The `chmod` is not optional — files copied out of the nix store keep mode 0444,
and skwd needs to write alongside them.

### Before committing the images

- **Size.** Current set is 5 files / 35 MB, four of them ~8–9 MB JPGs. `.git` is
  already 68 MB. Git stores every version forever, so each future
  add/remove/recompress is permanent weight. Consider downscaling to display
  resolution (2560×1080 / 1920×1080) first — likely 10× smaller with no visible
  loss. If the library is going to churn a lot, prefer git-lfs or a separate
  wallpapers repo as a flake input.
- **Rename `wallpaper.jpg`.** A generically-named file directly in the wallpaper
  dir is exactly what `Claude/skwd-wall.md` warns about — skwd may create copies
  and produce duplicate library entries.
- **Do not commit `effects/` or `.skwd-wall-v2/`** — generated state. Add both to
  `.gitignore` if the directory is ever symlinked or mirrored.

---

## 2. ~~noctalia's visual design is not declarative~~ — ✅ DONE 2026-09-30

Nix now **owns** `~/.local/state/noctalia/settings.toml`. All the tables that were
listed here as GUI-only — `[bar.main]` and its capsule group, `[widget.*]`,
`[lockscreen_widgets]`, `[shell.*]`, `[location]`, `[lockscreen]`, `[theme]` — are
declared in `lockedSettings` in `Modules/Desktop/noctalia.nix` and re-forced on every
rebuild. A wipe reproduces the bar, widgets and lockscreen geometry.

**Note the approach changed.** The plan recorded here was to copy the tables into
`nix-config.toml` as fresh-install defaults, on the reasoning that "nothing needs to
be forced". That was wrong for the user's actual requirement (2026-09-30): they want
GUI changes to be *temporary experiments* that a rebuild undoes. Merged-under
defaults cannot do that — once the GUI has written a key, a Nix default beneath it is
inert forever, which is exactly the "I rebuilt and nothing reverted" symptom that
prompted the work. So `settings.toml` is written directly instead, by a deep-merge
activation script that forces declared keys and passes undeclared runtime state
(`config_version`, the `[wallpaper]` paths skwd owns) straight through.

Full mechanism, the re-snapshot workflow, and the `config-reload` verification are in
`Claude/noctalia.md` → "⚠️ Nix owns `settings.toml`".

✅ **Closed 2026-10-03:** `nix-config.toml` is gone — `[idle]`, `[shell.mpris]` and the
clock format moved into `lockedSettings`, so they are forced like everything else.

---

## 3. skwd's `config.json` is mostly UI state

Nix seeds `monitor`, `paths`, `features`, `matugen`, `wallpaperMute`, then patches
`integrations`, `postProcessing` and the two `niri.*` backdrop keys.

Everything else is UI-only: `theme`, `display` (incl. **`outputLocks`**),
`transition`, `motion`, `components`, `filterBar`, `launch`, `sources`.

`theme` is unpinned **deliberately** — it is actively tuned and a Nix value would
fight the settings UI. Accept the consequence: a fresh install reverts to the
default colour engine, i.e. the Material You path that produced the pink palette
from a desaturated wallpaper. If that becomes annoying, pin `theme.engine` /
`theme.authority` the same way the backdrop keys are pinned.

`display.outputLocks` is the one worth pinning on reproducibility grounds — a
locked output silently swallows applies while `skwd-helm` still reports success.

---

## 4. ✅ Ebook auto-download — FIXED 2026-09-17 (was: never worked)

Both halves are now automatic and reproducible. See the *Books* and *Manga* sections of
`Claude/server-info.md`.

What it was: Shelfarr had run since June 2026 with `0 acquisition_providers`,
`0 download_clients`, and **Audiobookshelf had never been initialised at all**
(`isInit: false` — no root user, no libraries). The "Post-boot (one-time)" comment in
the old `server.nix` was never carried out, so every component showed green on Glance
while nothing was wired *between* them.

Now done by **`books-setup.service`** — idempotent, runs every rebuild, converges a fresh
install: initialises ABS, creates the Ebooks/Audiobooks libraries, mints an API key, and
configures Shelfarr's indexer + download client from sops secrets. Verified live: Prowlarr
`test_connection: true`, SABnzbd `true`, and a real search returned 14 results.

Still open, small:

- **Nothing has actually been downloaded through Shelfarr yet** — the wiring is proven at
  the connection + search level, but no end-to-end request has completed into
  `/data/media/books`. Worth one real request to confirm the SAB category and the
  post-processing hand-off to ABS.
- **FlareSolverr deployed 2026-09-17** (`:8191`), wired into Suwayomi and Shelfarr. Verified
  working on its own — `{"status":"ok","message":"Challenge not detected!"}` against
  comick.dev, 6.4 MB returned. **But Comick and Manganato still fail.** Their error changed
  from *"Cloudflare bypass currently disabled"* to a plain **HTTP 403**, which means
  FlareSolverr is engaged and those two extensions are failing for their own reasons —
  note `comick.io` now redirects to `comick.dev`, and Manganato's domain has churned
  repeatedly. Treat them as **stale extensions, not a Cloudflare problem**, and don't
  re-debug FlareSolverr. MangaDex and MangaFire both work and cover the need.
- **Komga**, only if native Mihon on the tablet is wanted instead of Suwayomi's web UI.

✅ FIXED 2026-10-03 (config side): **group `media` is gid 169, and gid 1001 does not
exist** — yet the book containers run `PGID=1001`, which is why `/data/media/books` and
`audiobooks` are `0777` where every other media dir is `0775`. Shelfarr's PGID and tmpfiles now read
`config.users.groups.media.gid`. Still to do on the box: `chgrp -R media` both dirs, then
tighten them to `0775`.

---

## 5. Loose ends

- **Is `skwd-music` still on the MPRIS bus under v2?** With `skwd-walld` running
  and a **static** wallpaper, `playerctl --list-all` showed only `spotify`. If v2
  really dropped the inert player, two workarounds can go: the
  `--ignore-player=skwd-music` flags in `Modules/Desktop/niri.nix` and the
  `[shell.mpris] blacklist` in `Modules/Desktop/noctalia.nix`. **Check with a video /
  Wallpaper Engine wallpaper playing before removing either** — it may only
  register then. Both files carry a warning note.
- **`Claude/BACKUP.md` is pre-split and heavily stale** (v1 `skwd-daemon`,
  `noctalia/colors.json`, the old integration table). It is intentionally an
  archive, but it has no banner saying so — worth adding one, or dropping it.
- **Dead runtime files**, deliberately left to be cleared by the planned wipe:
  `~/.cache/skwd-wall` (45 MB, v1), `~/.config/skwd-wall` (208 K, v1),
  `~/.config/skwd-wall-v2/data` (196 K, wrong-path templates from the v2
  migration), and the now-unwritten `~/.config/noctalia/colors.json`,
  `~/.config/btop/themes/noctalia.theme`,
  `~/.config/vesktop/themes/noctalia*.css`, `discord-system24.css`.
  The vesktop ones are the only ones with any risk — leaving the opaque
  `noctalia.theme.css` on disk is what someone would re-enable by accident.
- ✅ **Odysseus** was retired 2026-10-03, together with skwd v1.

---

## 6. Off-repo state on Asgard (added 2026-09-19)

Three things Asgard depends on that **no rebuild can recreate**, because they
live in vendor consoles or firmware rather than in Nix:

| What | Where it lives | Breaks if lost |
|------|----------------|----------------|
| **Tailscale ACL policy** | Tailscale admin console → Access controls | Caitlin regains full access to every admin dashboard. Default is allow-all. |
| **`marsbar` node key expiry** | Tailscale admin console → Machines | Node expires (~6 months), her dashboard silently dies |
| **BIOS fan curves** | Motherboard BIOS (Smart Fan 6) | Cage fans return to 100%, or 3-pin fans run flat out if the header mode resets |

The ACL is the one that matters most — it is the *only* thing enforcing her
isolation. Its current form is in `memory/marsbar-partner-dashboard.md`; keep a
copy of the policy JSON somewhere restorable. Note it uses the newer **`grants`**
syntax, not legacy `acls`, and `autogroup:member` must never be used for the
admin rule (she is a member too).

`marsbar` itself re-authenticates from the sops `tailscale-auth-key`, so the node
*does* come back declaratively — but **Asgard's and Sisyphus's own tailscaled were
authenticated interactively** and would each need `tailscale up` by hand.

---

## 7. ⭐ Multi-session streaming — **WOLF** is the chosen path (trial built 2026-09-28)

**Goal:** someone games on the TV via Moonlight while Sisyphus stays fully usable —
independent display *and* input, no interference either way.

### ✅ Current status: LIVE and in daily use (switched; verified through 2026-10-02)

Streaming 4K60 to Eclipse, Moonlight going **straight into Steam Big Picture** with no
Wolf UI picker, and the Wolf session tearing down ~4 s after Moonlight exits. The old
"written but NOT switched" note here was stale. Full detail in `Claude/wolf.md`.
⚠️ One loose end: `~/fix-steam-home.sh` (Steam signed-out + windowed Big Picture — a
wrong container `$HOME`) staged but unconfirmed as of 2026-10-02.

[games-on-whales/wolf](https://github.com/games-on-whales/wolf) is a **Moonlight
server** — a Sunshine alternative, host-side only. It **creates virtual desktops on
demand** ("no monitor or dummy plug"), one per session, each with its own virtual
inputs, in containers.

**That deletes almost all of the design below**, which is kept only as a fallback:

| Was planned | With Wolf |
|---|---|
| EDID injection on DP-1 | not needed |
| Multi-seat + `loginctl attach` | not needed |
| A second Linux user | not needed — containers isolate |
| DRM master contention on `card0` | not needed — render nodes only |
| "does uinput land on seat1?" (the big risk) | **solved upstream** — see below |
| A reboot to even test the idea | still needed once, for kernel modules |

🔑 **The udev rules are the load-bearing part.** Wolf's virtual pads are created in
its container but appear as *real host devices*; without upstream's full
`85-wolf.rules`, logind ACLs them to the desktop user and **the streamed controller
also drives niri** (upstream issue #451 — the same shape as Sunshine's
"Mouse passthrough (absolute)" bug). The rules park each `Wolf *virtual*` device on
a phantom **`seat9`** and strip `uaccess`. ⚠️ **Never trim them to just the
uinput/uhid access lines.** Nothing niri-specific is needed on top — it works below
the compositor.

⚠️ **Wolf and Sunshine cannot both run** — identical Moonlight ports. `autoStart` is
`false`; swap between them. **Eclipse needs no changes at all** (it's the client).

Resume steps, config decisions and open risks: `memory/wolf-trial-multisession-streaming.md`.

Still open once it starts: the **shared 806 GB Steam library mount** (only 285 GB
free, so duplication is impossible — and two Steams writing one `steamapps` can
corrupt manifests, so only one may run at a time), and whether Wolf coexists cleanly
with a live niri session (unproven).

---

### 📦 Fallback only — the multi-seat design (superseded by Wolf)

Kept in case Wolf doesn't work out. Everything below was designed 2026-09-27 and
**never built**.

### Why the simpler ideas don't work

- **A virtual output alone is not enough.** It solves *display* isolation, but
  **one compositor = one focus**. Sunshine injects the client's input via uinput into
  the niri session, so those events go to whatever window *you* have focused. Click
  your browser and the remote player's controller follows. Gamescope-per-game doesn't
  fix this either — a gamescope window still only gets input when focused.
- **Multi-seat on one GPU:** impossible. Seats attach **whole DRM cards**, not connectors.
- **A second headless niri:** impossible. `niri --help` has no `--backend` flag at all.

### What makes it possible: there is a second, unused GPU

```
card0 = 1002:13c0  amdgpu   ← Ryzen iGPU. UNUSED. DP-3/4/5 + HDMI-A-2 all disconnected
card1 = 1002:7590  amdgpu   ← RX 9060 XT, drives DP-2 + HDMI-A-1
```

### 🔑 You do NOT lose the discrete GPU

Linux splits DRM into two node types, and **only one of them is seat-bound**:

| Node | Purpose | Exclusive? |
|---|---|---|
| `card0` / `card1` | **display** — DRM master, drives a monitor | yes — this is what seats assign |
| `renderD128` (RX 9060 XT) / `renderD129` (iGPU) | **rendering** | **no** — mode `crw-rw-rw-`, not seat-bound |

Verified 2026-09-27: **eight** processes had `renderD128` open simultaneously (electron,
helium, kitty, localsend, noctalia, steam, steamwebhelper, Xwayland). So games in the
console session render on the **full RX 9060 XT** and the iGPU only scans out the frame —
exactly how every gaming laptop works. **Rendering quality is unaffected.**

### The design

| | seat0 (desktop) | seat1 (console) |
|---|---|---|
| GPU (display) | RX 9060 XT `card1` | **iGPU `card0`** + phantom EDID output |
| GPU (render) | `renderD128` | **`renderD128`** — the same dGPU |
| Session | niri | **`steam-gamescope`** |
| Input | keyboard + mouse | **none local** — only Sunshine's injected devices |
| Sunshine | stopped | running, captures this session |

`programs.steam.gamescopeSession.enable = true` is **already set** in `Modules/Gaming/steam.nix`,
and SDDM already lists `steam.desktop` alongside `niri.desktop`. `steam-gamescope` is just:

```bash
gamescope --steam -- steam -tenfoot -pipewire-dmabuf
```

**You can already log out and pick the Steam session today** — it simply replaces the
desktop rather than running beside it. The project is making it *concurrent*.

### 🎁 It deletes a lot of existing complexity

A session with exactly one output needs no per-game screen management at all:

| Currently required | With the console session |
|---|---|
| `open-on-output "HDMI-A-1"` window rules | gone — one output |
| CotL's fragile `title="^Cult Of The Lamb$"` match (gamescope unsets app-id) | gone |
| Per-game gamescope launch options | gone — the session *is* gamescope |
| Stray opening on the ultrawide (item 8) | cannot happen |
| Game pausing when the pointer leaves HDMI-A-1 | gone — gamescope owns focus |
| Sunshine's virtual pointer hijacking the desktop mouse (item 8) | gone — different seat |

### ⚠️ Open risks — verify in this order, cheapest first

1. **Can the iGPU drive a phantom display at all?** It enumerates with `amdgpu` bound, but
   enumeration ≠ usable output, and it may be disabled in BIOS. **This is the gate — test
   it before building anything else.**
2. **Can `steam-gamescope` run on `card0` while niri keeps `card1`?** Make-or-break, and
   testable without seats.
3. **Do Sunshine's uinput devices land on seat1?** uinput defaults to **seat0** unless
   tagged. If they land on seat0 the remote player drives *your* desktop — the exact
   problem being solved. **Most likely thing to bite.**
4. **Which encoder does Sunshine pick?** Currently `hevc_vaapi` on the RX 9060 XT. In an
   iGPU-hosted session it may choose the iGPU's VCN. Raphael's VCN does HEVC fine, but the
   dGPU's is better — pin it with `adapter_name` in `sunshine.conf`.
5. **Cross-GPU present cost:** ~8 MB/frame, ~500 MB/s at 1080p60. Small, but a real copy
   and a sub-millisecond latency add. Measure, don't assume.

### ⚠️ Steam is single-instance per USER

```
/home/rock/.steam/steam.pid     ← the lock
```

The console session needs its **own Linux user**. Consequences:

- Separate Steam config. The library can live on a shared path, but **two Steams writing
  one library is a known way to corrupt it** — needs care.
- The **same Steam account cannot actively play in two places at once.** Fine for "someone
  games on the TV while I work"; a blocker for "we both game simultaneously", which would
  need a second account and separately-owned games.

### Running cost (measured 2026-09-27, not estimated)

Current desktop Steam stack idle: **2,812 MB RSS, ~9% of one core**. Sisyphus has 30 GB
RAM (23 GB free) and 12 cores.

| Resource | 24/7 cost | Against available |
|---|---|---|
| RAM | **~3 GB** | 10% of 30 GB |
| CPU | ~10–15% of **one** core | **~1% of total** |
| Main GPU | **zero** | different silicon |
| Power | **~15–30 W** | **≈ $40–80/year** at AU rates |

**Don't run it 24/7.** Steam is nearly all of that; gamescope + Sunshine idle are only
~200–300 MB. Keep those up so Eclipse can always connect, and have Sunshine's `prep-cmd`
launch Steam when a stream actually starts.

---

## 8. Eclipse / streaming loose ends (added 2026-09-27)

Read `Claude/streaming.md` and `Claude/eclipse.md` first — all of these are written up
there in detail.

- **⚠️ Sisyphus has not been switched.** HEVC (`hevc_mode = 2`), Millennium 3.5.0, the
  dark-mode `color-scheme` key, and the Dolphin/Ark/Kvantum removal are all **built but
  live only as hand-edits**. `hevc_mode` is force-enforced on activation, so an unrelated
  rebuild would silently revert it.
  `sudo nixos-rebuild switch --flake /home/rock/Dots#rock-Sisyphus`
- ✅ **~~Eclipse stream audio is a live `pactl` hack~~ — RESOLVED, verified 2026-10-05.**
  The durable fix landed: the Moonlight launch passes `--setenv=SDL_AUDIODRIVER="alsa"`
  and writes its own `asoundrc`, bypassing PulseAudio entirely. ⚠️ It keys off Kodi's
  `audiooutput.audiodevice` starting with `"ALSA"` — switching Kodi to a PULSE device
  silently takes the other code path.
- **Stray needs a niri output rule.** It opened on DP-2 while Sunshine captured HDMI-A-1,
  so the TV showed the desktop. `app_id` is a clean `steam_app_1332010`. *Obsoleted by
  item 7 if that gets built.*
- **Don't leave Sunshine running when not streaming.** It holds a virtual **absolute**
  pointer mapped to the captured output, which pins the desktop cursor to that monitor.
  Restarting Sunshine does NOT clear it — only stopping it does.
- **Untested: does gamepad B quit Moonlight at the root PC list?** The QML has
  `Keys.onBackPressed` → `Qt.quit()`, but those are *keyboard* handlers and it is unproven
  the pad reaches them. Two-minute test: back out past the PC list and watch
  `/storage/moonlight-exit.log` for a new line.
- **Consider a Kodi-restore safety net.** The bash `trap` in the addon's `start.sh` has
  failed at least once unprovoked. An `ExecStopPost=systemctl start kodi` on the unit would
  make stranding impossible regardless of how Moonlight exits.
  📌 **Partly addressed 2026-10-05, and the premise was wrong.** The trap's backstop,
  `hdmi-hotplug.service`, turned out to have **never once survived a reboot** — an
  ordering cycle made systemd delete its job from every boot transaction while the unit
  sat `enabled` + `inactive (dead)` with no failure to notice. Fixed and reboot-verified,
  so the backstop now actually exists. Also: the 2026-10-01 "unprovoked trap failure" was
  **not** the trap — the crashlog shows Kodi segfaulting on the way *down*, in
  `XBMCAddon::RetardedAsyncCallbackHandler::~RetardedAsyncCallbackHandler()`, racing
  Jellyfin's service thread as it exited. `ExecStopPost` is still worth adding.

### ⭐ Open — Moonlight into Sisyphus's real desktop (added 2026-10-05)

Rock wants to reach Sisyphus's actual desktop from his phone. **~90% is already written:**
Sunshine captures the real seat (`capture = wlr`, `output_name` force-enforced each
activation), and `sunshine_state.json` already holds five paired clients including his
phone. It is simply never started.

- **Run it on base port `48989`** so it coexists with Wolf instead of replacing it — the
  overlap is only four ports. See the corrected note in `Claude/wolf.md`.
- ⚠️ **Do not set `services.sunshine.settings.port`** — it makes the nixpkgs module feed
  Sunshine a `/nix/store` config and ignore `~/.config/sunshine/sunshine.conf`, orphaning
  the `output_name`/`capture`/`hevc_mode` enforcement. Add an `enforce port 48989` line.
- **Capture DP-2, not HDMI-A-1.** HDMI-A-1 is the mostly-empty 1080p secondary; DP-2 is
  the 2560x1080 primary where he works. Bonus: the absolute-pointer trap maps to the
  *captured* output, so capturing DP-2 pins the stray cursor to a monitor already in use.
- Rock wants to pick the screen at connect time. `output_name` is global, not per-app, so
  that needs either two instances (two pairings per device) or a dashboard toggle that
  flips it and restarts — the latter reuses the existing `wolf-bridge` pattern.
- Clean up while there: `Modules/Desktop/niri.nix` (~918) has an unconditional
  `^steam_app_` → `open-on-output "HDMI-A-1"` rule that is obsolete under Wolf and becomes
  actively wrong if capture moves to DP-2. And `wolf.nix`'s `allowedUDPPorts` lists 47998
  and 48000, which Wolf never binds.

---

## Wolf: make `/etc/wolf` declarative (deferred 2026-09-29)

Wolf stopped being a trial — it auto-starts and is now **the** streaming host,
Sunshine is demoted to fallback. But its whole configuration is imperative state
that Docker created, outside Nix. A wipe loses all of it, and none of it is
rediscoverable without repeating a long debugging session. See `Claude/wolf.md`.

Living only in `/etc/wolf/cfg/config.toml`:

1. **Steam library mount** — `'/home/rock/.local/share/Steam:/home/rock/.local/share/Steam:rw'`
   at the *identical* path (a different path silently fails — `libraryfolders.vdf`
   records an absolute host path).
2. **`/dev/uinput` device** — `'/dev/uinput:/dev/uinput:rwm'` (three-part form;
   a bare path throws `invalid device definition`).
3. **`/dev/input` mount** — half of the gamepad fix.
4. **Encoder quality tuning** — `target-usage=4`, `min-qp=16` in both `va` HEVC blocks.
5. **Caitlin profile** — `name` + `icon_png_path`. ⚠️ never change the profile `id`.

Also imperative, elsewhere:

6. `/etc/wolf/10376776459688695541/Steam/.config/sway/custom-cfg` — hides the
   waybar top bar and keeps Big Picture fullscreen. The container **overwrites
   `~/.config/sway/config` every start**, so this file is the only durable hook.
7. The container's `.steam/steam/steamapps/libraryfolders.vdf` entry for the
   host library.
8. **On Eclipse:** `Moonlight.conf` (4K/100 Mbps/perf overlay) and the
   skinshortcuts `mainmenu.DATA.xml` Gaming entry pointing at Wolf UI.

Approach: generate `config.toml` from Nix and place it with an activation script
or tmpfiles, **but** Wolf rewrites that file at runtime (it stores
`paired_clients` there), so a naive read-only symlink will break pairing. Needs a
seed-if-absent + enforce-specific-keys strategy, like the `hevc_mode` handling in
`Modules/Gaming/sunshine.nix`.

⚠️ Also still runtime-pulled and unpinned: `ghcr.io/games-on-whales/wolf:stable`.

---

## Before any fresh wipe

Back these up, or land items 1–3 first:

```bash
~/.config/skwd-wall-v2/config.json        # theme, display, transition, motion
~/Pictures/Wallpapers/                    # 46 MB, not in the repo
/etc/wolf/cfg/config.toml                 # ALL Wolf config — see the Wolf section
/etc/wolf/10376776459688695541/Steam/.config/sway/custom-cfg
```

`~/.local/state/noctalia/settings.toml` no longer needs backing up — item 2 landed
and `lockedSettings` in `Modules/Desktop/noctalia.nix` reproduces it.

Plus the off-repo Asgard state in item 6 above — Tailscale ACL policy, the
`marsbar` machine's key-expiry setting, and the BIOS fan curves.

⚠️ And **Shelfarr's user account**, which nothing in the repo creates: `books-setup.service`
writes its `Setting` rows but never a `User`, so a fresh Asgard comes up with Shelfarr at
`/session/new` and zero accounts, waiting to be registered by hand. The password is a bcrypt
digest and is not recoverable from the old box — decide the new one before the wipe. See
`Claude/server-info.md` → *The Shelfarr login is not declarative*.

The *functional* config is genuinely declarative. It is specifically the
desktop's **appearance**, and anything living in a vendor console, that is not.

---

## Opened 2026-10-02 — Apollo USB + Elektra's machine

See `Claude/deploy.md` and `Claude/elektra.md`. Phases 1-3 of the plan are built and
verified; what follows is what is genuinely still open.

### Blocking the first install of Elektra

1. **Tailnet policy, in the admin console** (not in this repo): create
   `tag:installer`, grant yourself ownership, add a grant so your devices can reach a
   `tag:installer` node, and an `ssh` rule for that tag if you want Tailscale SSH as a
   backup path. Include a `tests` block — Tailscale runs it on save and refuses to save
   on failure.
2. **Mint the installer auth key** — ephemeral + reusable + pre-approved + tagged
   `tag:installer` — and store it as sops `tailscale-installer-key`:
   ```bash
   sops set Secrets/secrets.yaml '["tailscale-installer-key"]' '"tskey-auth-…"'
   ```
   `apollo-key` reads exactly that key. Max validity is 90 days; rotating means
   re-running `apollo-key`, not rebuilding the ISO.
3. **Confirm `installDisk`** in `Hosts/Elektra/system.nix` (currently `/dev/nvme0n1`).
   Everything on that device is destroyed. `apollo-connect` then
   `lsblk -o NAME,SIZE,MODEL`.
4. ~~Her `&kitkat` age key~~ ✅ **DONE 2026-10-02.** Host key at
   `~/.local/share/apollo/Elektra/` (`…/Kit-Kat/` until the next `apollo-deploy` moves it), recipient in `.sops.yaml`, `kit-kat.yaml`
   re-encrypted, and `apollo-deploy` plants it automatically.
5. **Swap is a guess.** 16 G with `resumeDevice = true` (hibernate intent), chosen
   without knowing her RAM. Revisit alongside `installDisk` once `facter.json`
   reports it. Note this also puts the layout over disko's hardcoded 4 GiB VM-test
   disk, so use `apollo-deploy --dry-run`, not `--vm-test`, to check it.
5. **`Hosts/Elektra/facter.json` does not exist.** The host evaluates and builds
   without it and emits a warning, but it must not be switched onto real hardware until
   `apollo-deploy` has generated it and you have committed it.
6. **Her initial password** is in `Secrets/kit-kat.yaml`. It is declarative, so `passwd`
   will not survive a rebuild — changing it means `sops Secrets/kit-kat.yaml`.

### Done overnight 2026-10-02 → 03

- ✅ Her **disk confirmed**: KINGSTON SNV3S1000G, 931.5 GB at `/dev/nvme0n1` — the
  guessed default was right. Read off the machine over SSH.
- ✅ **GPU confirmed**: RTX 3070 (GA104, Ampere) → `hardware.nvidia.open = true`.
- ✅ **RAM 31.3 GB** → swap raised 16G → 32G so `resumeDevice` is not a lie.
- ✅ Her **ssh host key + `&kitkat` age recipient** generated and wired; `apollo-deploy`
  now plants it automatically from `~/.local/share/apollo/<Host>/`.
- ✅ Her **password** set by her, stored in `Secrets/kit-kat.yaml`.
- ✅ **Greeter + bootloader**: `sddm` with `my.sddm.theme = "women-umbrella"` (qylock) and
  `grub-celeste` (CelesteGRUB 1080p). Both build; greeter verified present in her
  system path with its font.
- ✅ ISO console fixed (text status page) and SSH fixed (`--ssh` removed).

### Known-incomplete, not blocking

7. **Per-host niri outputs.** The wrapped niri config is a `perSystem` package
   (`Modules/Desktop/niri.nix:626-633`), one store path for every host, so her monitor
   layout falls through to auto-placement and the `output "DP-2"` / `"HDMI-A-1"` blocks
   and `open-on-output` rules silently no-op on her machine. Fixing it means moving the
   wrapper out of `perSystem` so it can take per-host settings.
8. **`hardware.nvidia.open = false`** is the safe-everywhere choice. Once `facter.json`
   names her GPU, flip it to `true` if it is Turing or later (RTX, GTX 16xx).
9. **Her wallpaper library starts empty** — same root cause as item 1 at the top of this
   file (`~/Pictures/Wallpapers` is not in the repo). Worth landing that item before she
   first boots, or her first login has a blank wall.
10. ~~**`rain-effect` on NVIDIA is unverified.**~~ Moot: rain-effect was retired 2026-10-03. GLES2 `wlr-layer-shell` overlay; expected
    to work with modesetting on, but nothing has tested it. Nothing depends on it.
11. **Stale Elektra profile on this disk.** `/nix/var/nix/profiles/system-profiles/elektra`
    still exists and still holds GC roots, but nothing builds it any more. Clean up with
    `sudo nix-env -p /nix/var/nix/profiles/system-profiles/elektra --delete-generations old`
    and remove the symlink.
12. **This repo is public** (`visibility: public`). `Claude/server-info.md`,
    `streaming.md` and `marsbar.md` expose the tailnet name, every node's 100.x IP, the
    service/port tables, the `*.bifrost-vault.com` hostnames and a partner's email
    address. No credentials leak — sops is doing its job. Going private costs nothing
    operationally now that deploys are push-only (her machine never fetches the flake).
13. **`tailscale-api-key` in sops is referenced by nothing.** It is an admin key that can
    rewrite ACLs and mint auth keys. Rotate or delete it.
14. **`Modules/Core/sops.nix`'s original module still needs a hand-copied age key** on every
    new machine (`/home/<user>/.config/sops/age/keys.txt`). The `sops-kitkat` module shows
    the better pattern — `sops.age.sshKeyPaths` against the host's own ssh key. rock's
    hosts have not been migrated.

## Opened 2026-10-04 — Elektra: Bluetooth + GPU noise, and what they exposed

Both faults are **closed** — see `Claude/elektra.md` → Bluetooth and "Her graphics card is
taking off", and `Claude/misc.md` → Audio. These are the gaps they uncovered.

1. ⚠️ **Her tailnet join is imperative, and it caused the whole episode.**
   `Modules/Core/tailscale.nix` sets no `authKeyFile`, so every host joins by a hand-run
   `tailscale up`. Hers had never been done (she joined 2026-10-04), so she had never
   received a single push and her only config path was a local clone rebuilt on her own
   machine — which is how she ended up running a build from before the `10-disable-bluez`
   removal. `services.tailscale.authKeyFile` exists and her `sops-kitkat` module is ready;
   it needs `tailscale-auth-key` added to `Secrets/kit-kat.yaml`. A node-join key is not
   the admin key that file is deliberately kept away from. **Until this lands she drifts
   again.**
2. **`tailscale-api-key` is confirmed DEAD** — `401 {"message":"API token invalid"}` as of
   2026-10-04, so it cannot be used to inspect the tailnet. It is also referenced by
   nothing and is an admin key that can rewrite ACLs and mint auth keys. Tailscale API keys
   expire after 90 days, so a stored one always rots — mint on demand, or delete it.
3. ~~`system-rebuild`'s remote activation is broken~~ ✅ **FIXED 2026-10-04.**
   `nixos-rebuild-ng` re-execs itself before switch/boot and, with `--store-path` and no
   `--flake`, looks for `nixos-config` on NIX_PATH. `system-rebuild` now passes
   `--no-reexec` (local and `--target-host`). Detail and the manual fallback:
   `Claude/deploy.md` → Things that will bite.
4. **Neither desktop has `lm_sensors`** — only `Hosts/Asgard/_hardware.nix` installs it. A
   "her GPU is taking off" report could not be answered with a temperature reading;
   everything had to come from `nvidia-smi` plus raw `/sys/class/hwmon` reads. Worth adding
   to the desktop module. Note her board exposes **no fan-RPM inputs at all**, so CPU fan
   speed is unmeasurable on Elektra even with it installed.
5. **Only DXVK titles are frame-capped globally; native Vulkan relies on MangoHud.** Her
   host now sets both (`programs.mangohud` with `fps_limit = 60`, plus
   `DXVK_FRAME_RATE=60` for D3D titles). Sisyphus has neither — it is AMD, where
   `MESA_VK_WSI_PRESENT_MODE=fifo` can force vsync externally, so it has an escape hatch
   NVIDIA does not. Consider whether rock's host wants an equivalent cap.

## Opened 2026-10-09 — Eclipse streaming: path fixed, bitrate still open

Diagnosed from a live Cult of the Lamb session. Evidence and all the numbers:
**`Resources/Eclipse-Box/evidence/cotl-lag-2026-10-09.md`**; summary in `Claude/wolf.md`.

1. ✅ **DONE — Eclipse pinned to wired.** It had silently dual-homed (`eth0` .182 wired →
   extender *and* `wlan0` .183 at −66 dBm), with **Wi-Fi holding the default route**; the whole
   4K60 stream went over the Pi's own radio. Idle: **eth0 376 Mbps / 2.99 ms** vs
   **wlan0 158 Mbps / 5.79 ms**. Enforced by `SingleConnectedTechnology = true` in
   `/storage/.config/connman_main.conf` plus `AutoConnect=false` on every saved Wi-Fi.
   Mirrored in **`Resources/Eclipse-Box/network/`**; standing rule is wired-only on the LAN.
2. ⏳ **Open — does `bitrate=100000` still spike on the good path?** At 376 Mbps a 101 Mbps
   stream is ~28 % utilisation, so there should be far less loss. But the **255-packet FEC
   block ceiling is still crossed**, so whatever loss remains is unrecoverable.
   **Play a session at 100000 and re-check the client log**; if freezes persist, drop to
   40000-50000. ⚠️ Set it in Moonlight's own settings screen on the TV, or with Moonlight
   stopped — `Moonlight.conf` is Qt `QSettings` and is rewritten on exit.
3. **The dashboard's *Test link* measures whatever holds the default route**, and will happily
   run during a stream. A 64.3 ↓ reading was leftover capacity on the saturated radio, not an
   extender fault. Worth making the panel refuse to test while a Wolf session is live, and label
   which interface it measured.
4. **`Moonlight.conf` is not mirrored in `Resources/Eclipse-Box/`.** Bitrate, resolution and
   codec live only on the SD card — exactly the kind of setting nobody will remember after a
   re-flash. (`network/` now is mirrored; this one still is not.)
5. Consider whether Wolf should **cap what it accepts** rather than honouring any bitrate a
   client asks for. Nothing on the host side warns that a request is unservable — the only
   symptom is 27,628 FEC warnings buried in the journal.

## Opened 2026-10-31 — Asgard into a cupboard: thermal headroom

A temp/humidity sensor now reports the room Asgard is in
(`sensor.asgard_temp_humidity_sensor_temperature` / `…_humidity`, ESPHome; ~22.9 °C /
59 % at install). **Asgard is now IN the cupboard — moved 2026-11-23** (measurements below), and the point of the sensor is to
see how hot that enclosed space gets and cross-reference it with the CPU and drive temps
— so a thermal problem is visible, and something can be shut down, before hardware
cooks.

### Measured 2026-11-23 — the move happened, and the cupboard passes

Asgard went into the cupboard **2026-11-23** (clean `systemd-poweroff` 18:44 → up 19:07;
no power pull, so nothing on `/data/.state` was at risk). Verified after the move: both
HDDs **CRC / reallocated / pending / uncorrectable all 0** and SMART healthy, both links
renegotiated **6.0 Gb/s**, NIC **0 errors / 0 dropped / 0 carrier**, ext4 mounted with no
journal recovery, `it87` survived its **first true cold boot** since the `hwmon_vid` fix.

Then a **12-minute synthetic soak** — 16 × `sha256sum /dev/zero` plus sequential reads off
both HDDs, i.e. far harsher than anything the box really does:

| | idle | peak soak | limit |
|---|---|---|---|
| cupboard air | 27.4 °C | **28.8–29.2 °C** | — |
| humidity | 52 % | 45 % | — |
| CPU package | 35 °C | **73 °C** | 100 °C crit |
| Disk 1 / Disk 2 | 34 / 35 °C | **37 / 39 °C** | 70 / 65 °C |
| NVMe | 37 °C | **42 °C** | 79.8 °C crit |

`core_throttle_count` and `package_throttle_count` stayed at **0** and the CPU held full
all-core boost (3950 MHz avg, 4100 peak), so 73 °C was never near a limit. The kernel log
for the whole soak: *no entries* at warning or above. CPU fell to 48 °C within ~30 s of the
load stopping.

⛔⛔ **THE WEATHER TRAP — do not repeat this mistake.** The first reading of these numbers
was "the cupboard costs +4.5 °C" (27.4 vs the 22.9 °C install baseline). **Wrong.** rock:
*"it is a 28 degree day today"* — the cupboard air is **at or below the outdoor
temperature**, so essentially all of that rise is **weather**, and the Oct 31 baseline was
simply a cooler day. ⭐ The cupboard's own penalty is small (~0 to a couple of °C) and
**cannot be pinned down more precisely, because the only sensor is inside the cupboard** —
there is no house-interior reference to subtract. A second sensor outside it is the only
way to ever measure the enclosure itself. This is exactly the delta reasoning point 1
describes, and it is why a bare room temperature can mislead.

⭐ **Consequence: the risk is the weather, not the workload.** A transcode on a mild day is
a non-event — proven with a load that will never occur naturally. But if air ≈ ambient,
a **40 °C summer day** puts the cupboard near 40 °C and the drives near **46–50 °C**, which
*is* the longevity zone. That single scenario is the only thing on these numbers worth an
automation, and it is what point 3 should be built around.

1. ~~**Show it where the other temps are.**~~ ✅ **Done 2026-10-31, deployed 2026-11-01.**
   It is the fourth ring in the Asgard page's host card, beside the CPU temperature, with
   humidity under it (`stats.js`, declared as `room` in `_plugs.nix`). ⚠ The ring's
   `warn`/`bad` are **30/35 °C and are a guess** — that is what point 3 is for.
   ⚠ **A `cpu over room` delta row was added and removed the same day at rock's
   request** — he wants the room temperature on the card, not a derived figure. Don't put
   it back on the dashboard. The delta is still the right thing to *reason* with when
   judging the cupboard (a rising delta is a cooling problem; a rising room temp with a
   flat delta is just the weather) — work it out from the recorder when the time comes.
2. ⛔ **Baseline before the move — NO LONGER POSSIBLE.** The move happened 2026-11-23
   before any pre-move baseline was recorded, so the clean in-the-open comparison is gone
   for good. ⚠ **Do not substitute the 2026-10-31 install reading (22.9 °C) for it** — see
   the weather trap in the measurements above. HA's recorder still holds whatever it
   captured in the open during Nov; that is the only surviving source if this is ever
   worth reconstructing.
3. **Then decide the thresholds.** Any "shut things down when hot" automation needs
   numbers that came from measurement, not from a guess. Candidates: warn on the dashboard,
   stop transcoding / downloads, spin down the array, hard power-off at the top end.
   ⚠ Asgard's own relay (`switch.server_power_switch`) is a mains feed and is deliberately
   **not** in ha-bridge's allowlist — cutting it is an unclean stop, so an emergency path
   must be a clean `systemctl poweroff`, never that switch.
   ⭐ **Now partly measurable — 2026-11-23 gives the shape, not the final numbers.**
   The ring's live **30/35 °C** are demonstrably too tight: the cupboard **idles at
   27.4 °C**, so 30 is ~2 °C above resting and will sit amber on any warm evening until
   rock learns to ignore it — the one failure mode that leaves him blind. On the measured
   relationship (air ≈ outdoor; drives run **8–10 °C over air** under load; drive
   longevity line ~45 °C) **warn 34 / bad 39** tracks reality: it stays quiet year-round
   and fires in a genuine heatwave. ⚠ **Still unvalidated at the top end** — nothing has
   been measured above 29 °C of air, so 39 is an extrapolation, not an observation. Wants
   one hot-day datapoint before any *automation* hangs off it; the dashboard colours are
   safe to change now. ⚠ Changing them is a `_plugs.nix` edit **plus a deploy rock must
   run himself** (Asgard's sudo needs a password).
4. ~~**Fans.**~~ ✅ **Closed in hardware 2026-11-23.** rock fitted **new fans in a
   different header**, so the Molex dead-end is gone and `fan3` now reads ~1100 RPM where
   the 2026-09-19 baseline recorded 0. ⚠ **They are not slaved to the CPU's PWM**, despite
   the wiring sounding like it: in the soak below `fan1` rose **+120%** while `fan2`/`fan3`
   moved **+5%** at a pinned **32%** duty. ⛔ **No BIOS curve can react to drive
   temperature** — it is not an available source — and Asgard's heavy workload (SAB, a
   library scan) loads the disks while leaving the CPU idle, so the case fans sit at 32%
   exactly when the drives work hardest. **Left alone deliberately**: the drives peaked at
   37/39 °C with the fans flat. `Claude/server-info.md` → *Fans and sensors*.
5. ~~**A cupboard is a humidity question too.**~~ ✅ **Answered 2026-11-23 — retire it.**
   27.4 °C at 52 % RH is a dewpoint of **~16.7 °C**, and every surface in there is ≥27 °C.
   Condensation needs a surface *below* dewpoint, so it cannot form on a running machine in
   that cupboard. RH also *falls* as the box heats the air (52 → 45 % during the soak), so
   load makes this safer, not riskier. Only a long cold shutdown could invert it.

## Opened 2026-11-01 — Bedside bulbs: the ladder is live, two rungs unjudged

The reflash, the eight-rung colour ladder, the Custom swatch and the five-slider mix
panel are all deployed (`Claude/home-assistant.md` → *The bedside bulbs*). What is left is
taste, and it can only be settled on the lamps:

1. **Ember** (`255 104 0 0 155`) is the "super warm" rung — redder than Amber, more lift
   so it stays bright. It was put on Caitlin's lamp for judgement and has not been
   confirmed.
2. **Gold** (`255 152 15 0 175`) is the rung closest to the edge: green **160** is where
   rock saw "a really light green colour", and Gold sits at 152. If it reads green, pull
   it back toward 145 — and pull `Warm` (168) with it, since it is further out again and
   only gets away with it because the white behind it is near full.
3. ⭐ **Retune the way these were tuned**: change ONE channel, put a different value on
   each of the two (identical) bulbs, and look at them side by side. Do not recompute the
   table — three separate derivations gave three wrong answers, because `gamma_correct:
   2.8` and the green die's luminosity make the problem perceptual, not radiometric.
4. **Not built, and not to be built unasked:** per-bulb mixes (deliberately one shared
   mix — two lamps at the same bed want the same colour, and ten sliders is not a control
   panel), and saving a mix as a named preset (presets are Nix, in `_plugs.nix`, which is
   where a colour that matters should live).

## Opened 2026-11-01 — Media stack: Dolby Vision, Doctor Who specials, three wrong files

One session, three complaints, mostly closed. Background and the diagnostic order are in
`memory/eclipse-dolby-vision-p5-green.md`,
`memory/jellyfin-specials-misfiled-two-causes.md` and
`memory/sonarr-upgrade-destroyed-correct-file.md`. What follows is only what is still open.

### ⭐ 1. Ted Lasso S02E12 is fixed but **unproven**

The original complaint ("green and pink on the TV") was DV Profile 5 with the addon patch
clobbered. `patch_dv.py` has been re-run and the `CodecProfile` block is verified in place at
`playutils.py:510-520`, Kodi restarted. **Nobody has played the file.**

Proof is one play plus Asgard's Jellyfin log showing
`TranscodeReasons=VideoRangeTypeNotSupported` and `hevc-rangetype=` with **no bare `DOVI`**.
⚠️ Expect a **multi-minute stall before the first frame** regardless — this title carries
**42 subtitle tracks**. Don't read that stall as a failure.

### ⭐ 2. The DV patch has no guard, and that is the actual bug

It was clobbered by an addon update on **2026-09-17 15:46** and stayed broken for ~6 weeks
across **42** P5 files, with no symptom until someone happened to reach one. A hand-applied
addon patch will be removed again.

`patch_dv.py` is idempotent and is already mirrored at
**`Resources/Eclipse-Box/patches/patch_dv.py`**. Run it from a oneshot unit on the Pi —
`Resources/Eclipse-Box/system.d/` is where Eclipse's units are mirrored — ordered after the
addon directory is writable and before/with `kodi.service`. Also **diff the mirrored copy
against the one living at `/storage/patch_dv.py`** before trusting it; nothing enforces that
they match.

### 3. Sonarr has no DV Profile 5 penalty — only Radarr does

`Modules/Server/recyclarr.nix:543` scores `923b6abef9b17f937fab56cfcf89e1f1`
(*DV (w/o HDR fallback)*) at **-10000**, but only under `Asgard - Movies`. `sonarr-main` has
no equivalent, so TV keeps acquiring P5 — which is why there are 42 of them. Mirroring the
line into the Sonarr block closes the acquisition hole; offered and not yet decided.
⚠️ Remembered `trash_id`s go stale — fetch, don't trust ([[recyclarr-upstream-restructure]]).

### 4. The last 5 Doctor Who specials — a real numbering divergence, pick a route

19 specials, correct order, seasons `0..10`, 14/19 titles right. The remaining five are **not**
a config fault: TVDB and Sonarr/skyhook are genuinely **off by one** from E157, and the 2023
trio live under a **separate TVDB series, `Doctor Who (2023)` tvdb 449991**.

Two routes, neither started:

- **(a) Edit + lock** `Name`/`Overview` on the five Jellyfin items by hand. Durable (locked
  fields survive refreshes), 5 items, no structural change. Doesn't fix the underlying split.
- **(b) Split the 2023 trio** into a `Doctor Who (2023)` series in Sonarr against tvdb 449991
  so both halves of the stack agree. Fixes 3 of 5 structurally, leaves the
  Revolution-of-the-Daleks off-by-one, and moves files.

⛔ **Do not use `POST /Items/RemoteSearch/Apply/{id}`** on an episode. It returns 204, ignores
the provider id, and **nulls `IndexNumber`** — i.e. unnumbers the episode. Recovery is a
per-item `Refresh` with `replaceAllMetadata=true`.

⛔ **Specials inside their aired seasons is not achievable** and was asked for explicitly.
`airsAfterSeason`/`airsBeforeSeason`/`airsBeforeEpisode` are populated on **0 of 19** even with
TVDB first, *and* the jellyfin-kodi addon contains no code for those fields at all. Don't
re-attempt it via `DisplaySpecialsWithinSeasons`; there is nothing for it to act on.

### 5. JJK 0 — a feature film occupying a TV episode slot

*Jujutsu Kaisen 0* (2021 film, **104m57s**) is attached to **S1E10 "Idle Transfiguration"**,
whose neighbours run 24m03s. So `hasFile=true`, Sonarr will never search S1E10, and playing it
gives the film. Move the film out of the series folder (it is a Radarr item), then
`EpisodeSearch` the slot. Rock deprioritised it — "outside of all of this".

For the record, JJK has **three complete seasons** (S1 24/24, S2 23/23, S3 12/12) plus an S4
holding one unaired episode — not "only season 1".

### 6. Sword Art Online S4E2/E3 show as "Ripped by KaiDubs"

Jellyfin read those titles out of the files' **embedded tags**. Sonarr maps both episodes
correctly, so a single `RenameSeries` on **series 53** writes clean filenames and fixes it.
Offered, not yet authorised.

### 7. Housekeeping

- **Delete `Doctor.Who.2005-2022.S04E00...mkv.DUPLICATE-of-E17`** (~5.6 GB). It is the
  mislabelled Part Two, moved aside rather than deleted so the bytes survived the recovery.
  Safe to remove once item 1's sibling work is trusted.
- ⚠️ **Sonarr's `recycleBin` is empty**, so every delete through Sonarr is **permanent**.
  Setting it would make this class of mistake recoverable. Until then, move files aside with a
  changed extension — Sonarr drops them on rescan.
- **`/data/media/music` logs as inaccessible or empty on every Jellyfin scan.** A configured
  library with nothing in it. Either populate it or remove the library so the warning stops
  being noise ([[eclipse-litebox-not-harmless-noise]] — quantify before dismissing).

### What was closed

✅ `renameEpisodes` on for Sonarr, declaratively (`Modules/Server/recyclarr.nix`, commit
`7b3afbf`) — 146 files renamed, specials no longer scattered into numbered or phantom seasons.
✅ TheTVDB first for episode metadata (rock, in the UI) — 15/19 specials now carry a `Tvdb` id,
0 carry `Tmdb`. ✅ *The End of Time* Part 1 recovered after Sonarr deleted it and imported Part
Two twice. ✅ Kodi re-synced itself; no action was needed there. ✅ A library-wide sweep of 3551
episodes found Doctor Who was the **only** misfiled show.

---

## Opened 2026-11-11 — Tailscale kills phone internet on every network handover

Both phones (Samsung S25, Android) lose all app traffic whenever the network changes —
**wifi→wifi as well as wifi→4G**. Calls and SMS keep working; toggling Tailscale off/on
fixes it instantly, every time. She also sees an explicit DNS error. Live since at least
2026-10-21, and the reason WhatsApp messages and Discord calls get missed.

**It is not Tailscale carrying their traffic.** Verified 2026-11-11: no exit node is
offered or selected anywhere on the tailnet (`ExitNodeOption: true` count = **0**) and
there are no subnet routes, so Tailscale installs no default route and their internet
traffic never enters the tunnel. What it *does* take over is **DNS** — Android's
VpnService hands every lookup to `100.100.100.100`.

**Root cause is upstream and still open.** The Android client does not rebind its
interface on a network change, so the forwarder keeps relaying to the previous network's
resolver, which is unreachable from the new one. Every lookup times out; calls and SMS
need no DNS, which is why they survive. A toggle wakes the app and forces the rebind.
- [tailscale#19783](https://github.com/tailscale/tailscale/issues/19783) — Android 16 /
  Samsung One UI, `dns` label. **Still reproduces on client 1.104.1**, so an app update is
  NOT a fix.
- [tailscale-android#717](https://github.com/tailscale/tailscale-android/pull/717) fixed
  one variant in Nov 2025. Also #17747, #10107, #7328, #10362 (wifi→wifi), #19297, #19756.

### ✅ Done — global nameservers pinned

Admin console → DNS → Google + Cloudflare, **Override DNS servers ON**. Verified actually
pushed to clients rather than merely stored: `tailscale dns status` went from `(no
resolvers configured)` to 8 entries, lookups 49-58 ms on Sisyphus (incl. whatsapp.com,
discord.com), Asgard fine, `marsbar` still resolves via MagicDNS. This removes the
dependency on network-learned resolvers, so a *late* rebind can no longer strand DNS.
Details and the IPv6 caveat in `Claude/server-info.md` → *Tailnet DNS*.

### ⚠️ Open — the phone-side steps, neither done yet

1. **Battery optimisation → Unrestricted** for Tailscale on both phones (Settings → Apps →
   Tailscale → Battery). Targets the actual cause — Android freezing the app through the
   handover — and is the one workaround that outright stopped it for a reporter on #19783.
   The nameserver change does **not** substitute for it: a frozen forwarder relays nothing.
2. **Toggle Tailscale off/on once** on each phone, to pull the new DNS map.

### If it recurs

Run the raw-IP test **before** toggling: open `http://1.1.1.1` in a browser.
- **Loads** → still DNS, so the app is being frozen. Push step 1 harder: force-stop and
  reopen, or reauthenticate — both reported to work where a plain toggle did not.
- **Does not load** → routing, or Android's "Block connections without VPN" kill-switch.
  A different fix entirely.

Last resort is `accept-dns=false` on the phones — the only genuinely app-independent fix,
since Android then resolves via the real network and never consults Tailscale. ⚠️ **It
kills her MarsBar dashboard.** Read `Claude/marsbar.md` → *Her phone cannot run
`--accept-dns=false` either* first, including the **unverified** HTTPS-certificates escape
hatch and the fact that HTTPS on that node has broken Brave before.

### Noticed while measuring — unrelated, low priority

`marsbar` is reached over **DERP(syd) at 26 ms**, `direct connection not established` —
from Sisyphus, which shares a LAN with the box marsbar runs on. `asgard` from the same
machine is **direct in 1 ms**, and the phone on home wifi is direct too. Not an IPv6
problem (plain IPv4 direct already works between those two); most likely endpoint
discovery for a second node running `--tun=userspace-networking` with `--port=0`, which
cannot take 41641. Cosmetic at 26 ms, but it means her dashboard traffic leaves the house
and comes back even when she is on home wifi.

---

## Trialled and removed 2026-11-11 — Odysseus AI workspace ⛔ dormant

`Modules/Apps/odysseus.nix` puts the self-hosted AI workspace
(github.com/odysseus-dev/odysseus, AGPL-3.0) on **Sisyphus** as four containers —
app + ChromaDB + SearXNG + ntfy — with the UI on `127.0.0.1:7011`.

### ⛔ Outcome: ran end to end, then taken back out the same day

Everything worked: ROCm on gfx1200, the GPU fix below, `qwen2.5-coder:14b` at
**30–38 tok/s** with 13.7 GiB resident in VRAM. It was removed on model
**quality**, not on plumbing. Asked to review `Hosts/Sisyphus/system.nix`, the
14B summarised it accurately and then invented four nixpkgs options that do not
exist (`services.sddm.themes`, `.writingSystem`, `.x11DisplayServer`,
`.defaultUser` — the real one is `services.displayManager.sddm.theme`, renamed
in 24.11), proposed a package that isn't one, told us to extract
`my.sddm.theme` into a "custom module" when `Modules/Boot/sddm.nix:46` already
declares it, and wrote its example as a bare `{ ... }: { ... }` instead of
`flake.nixosModules.<name>` — with `architecture.md` in its context.

**The honest read:** fine at *reading* Nix (summaries, "what does this module
do"), actively costly at *writing* it — fluent, confident, wrong. RAG over the
repo would fix the conventions half but NOT the invented option names, which
come from the weights. That is the 14B ceiling, not a prompt problem.

**The module stays in the tree, inert** — no host lists it, so it defines an
unused attribute and costs nothing to evaluate. Re-enabling is one line in
`Hosts/Sisyphus/system.nix`. ⚠️ If you come back: `Devstral-Small-2-24B` was the
untried candidate (better coder, PERFECT fit, but fills VRAM → ~4k context), and
the workspace mount + retrieval was the untried quality lever.

### Everything below is what it took to get it working — keep it if it returns

### Why Sisyphus, which looks like the wrong host

The app is CPU-only and every other service lives on Asgard, but **Odysseus is not
a model** — it's an interface that calls one over HTTP. rock chose to install models
through the app's own **Cookbook** page, which downloads from HuggingFace and
pip-installs a serve engine *inside the container*, serving on whatever GPU Docker
shows it. That pins the app to the machine with the card. Asgard's only GPU is the
i5-14400's UHD 730 iGPU: fine for Jellyfin's QSV, useless for inference.

**Accepted trade:** the workspace is only up while the desktop is.

**The declarative alternative, offered and declined for now:** `services.ollama`
with `acceleration = "rocm"` on Sisyphus + the app on Asgard, models listed in
`loadModels` — fully in Nix, workspace up 24/7. It stays available, and adding an
endpoint does not turn Cookbook off, so it is additive rather than a migration.

### ⚠️ The open question: does ROCm work here at all

The slim image bundles **no ROCm userspace** — Cookbook has to fetch a ROCm build of
the engine itself, and this card is **gfx1200 (RDNA4)**, which needs ROCm ≥ 6.4.
Nothing about that is proven yet. Order of checks after the first switch:

```bash
# 1. the right card is visible, and only the right card
docker exec odysseus sh -lc 'ls -l /dev/kfd /dev/dri/renderD*'
# 2. the first-run admin password, printed once
journalctl -u docker-odysseus | grep -i password
# 3. then: Cookbook → Dependencies, install a ROCm llama.cpp, serve a small GGUF
```

If an engine installs but cannot see the card, **`HSA_OVERRIDE_GFX_VERSION` is the
first knob** — deliberately not set in the module, because a wrong override is worse
than none. Start with a GGUF/Q4 model on llama.cpp before trying vLLM, per upstream.

### ⭐ Pass ONE render node, never all of `/dev/dri`

`renderD128` is the RX 9060 XT (`1002:7590`); `renderD129` is the Ryzen iGPU
(`1002:13C0`). Upstream warns Cookbook "sees the iGPU, another card, or CPU instead
of your intended GPU" when passthrough is loose, so the module passes `/dev/kfd` +
`renderD128` only. Both are mode 0666, so the `--group-add` for video(26)/render(303)
is belt-and-braces rather than load-bearing.

### Not declarative, by necessity

Everything Cookbook installs: models in `/var/lib/odysseus/data/huggingface`, engines
in `data/local`, and the app's own settings/chats/notes in its SQLite DB under
`data/`. Same category as *Before any fresh wipe* above — a wipe brings the app back
empty and ready, not populated. Nix owns images, ports, devices and paths only.

### Loose ends

- **Disk.** Sisyphus is at 80% (356 G free) before a single model is downloaded.
  Weights are tens of GB each; this is the thing most likely to bite.
- **SearXNG's `secret_key`** is generated once into `/var/lib/odysseus/searxng/secret`
  because it cannot live in the Nix store. Move it to sops if it ever needs to be
  reproducible across machines (`Claude/secrets.md`).
- **The image is digest-pinned** (resolved from `:latest` 2026-11-11) because upstream's
  own compose warns ":latest and bare :X.Y.Z tags move on every main push" — and this
  project pushes to main most days. Take upgrades deliberately:
  `skopeo inspect docker://ghcr.io/odysseus-dev/odysseus:latest | grep Digest`.
- **No topic doc yet.** If this survives the trial it wants a `Claude/odysseus.md` and a
  row in CLAUDE.md's table; for now the module header carries the detail.
- **The Docker socket is deliberately unmounted** — upstream's `host-docker.yml` overlay
  is only for Cookbook's "manage the local Docker daemon" flow, and on this host that
  socket is what Wolf drives.
- **Idle cost measured 2026-11-11**, first boot, nothing connected: **≈2.0 GiB** resident
  (1.76 GiB of it anonymous, in the one uvicorn process — FastEmbed's MiniLM loads at
  startup whether the app is used or not) and **0.15% of the 12 threads** across two
  samples. Left on `autoStart` on that basis: Sisyphus has 48 GiB of unused swap (15.2 GiB
  zram + 33.5 GiB on NVMe), so idle anonymous pages get evicted under game pressure rather
  than competing with it. ⚠️ That CPU figure is a **floor** — `ODYSSEUS_INPROCESS_POLLERS=1`
  is on but has nothing to poll until email/calendar are connected. Re-measure after that.

### ⭐⭐ The engine: "llama.cpp ready" can mean a CPU-only pip wheel

The single most expensive thing to rediscover. Cookbook's serve script runs a bare
`llama-server`. **The slim image ships no inference engine at all**, so it tries to
*compile* llama.cpp in-container, fails for want of a toolchain, and silently falls
back to a pip `llama-cpp-python` wheel — which is **CPU-only**. The UI then shows a
green *"llama.cpp ready on local server"* banner, the launch command still reads
`HIP_VISIBLE_DEVICES=0 llama-server …`, and the model loads into **system RAM**.

**Three tells, in order of how fast you can check them:**
1. `free -h` jumps by the model's size (+8.4 GB) while
   `/sys/class/drm/card1/device/mem_info_vram_used` stays at the desktop's ~1.5 GiB.
2. The serve log: `done_getting_tensors: … cannot be used with preferred buffer type
   CPU_REPACK, using CPU instead`.
3. ~3 tok/s. "Hello" takes half a minute.

**The fix (in the module):** mount a nixpkgs `llama-cpp` built with `rocmSupport = true`
at `/usr/local/bin/llama-server` — a path already on the image's PATH, so no PATH
override that could shadow Cookbook's own pip CLIs in `/app/.local/bin`. ⚠️ The binary
resolves ~50 libraries by absolute `/nix/store` path, so **`/nix/store:/nix/store:ro`
must be mounted too** — the bin alone is inert. 0 packages to build, ~2.1 GiB to fetch,
and `CMAKE_HIP_ARCHITECTURES` already lists **gfx1200** against ROCm 7.2.3. Working
log line: `ROCm0 : AMD Radeon RX 9060 XT (16304 MiB …)`, then 13.7 GiB of VRAM in use.

### ⚠️ Two more traps that cost an hour each

- **Ollama-engine catalogue rows can never work here.** A row whose ENGINE column says
  `Ollama` makes Cookbook run `ollama pull` in a tmux session; there is no ollama binary
  in the container, so it dies instantly and the badge sticks on `downloading` **forever**
  with zero bytes transferred. Those rows also show `? t/s` and `?` CTX because Cookbook
  never benchmarked them. ⭐ **Only use `llama.cpp` rows, or Direct Download a GGUF URL.**
- **Direct Download the FILE, not the repo.** `Qwen/Qwen2.5-Coder-14B-Instruct-GGUF`
  holds 24 GGUFs (every quant plus fp16) and the request logs `include=None` — a repo-level
  pull is 100+ GB. Pasting the full file URL makes it log
  `backend=hf, include=qwen2.5-coder-14b-instruct-q4_k_m.gguf` and fetch just 8.37 GiB.

### Context arithmetic on a 16 GB card — weights and KV cache share it

Measured from Cookbook's own scan: a 15.2–15.9 G model leaves **1–4k context**; ~9 G
leaves **32k**. For reading this repo's docs, context is worth more than parameters —
`eclipse.md` alone is ~35k tokens and `CLAUDE.md` + every `Claude/*.md` is ~190k, so
RAG is the only way to use them whole. ⚠️ llama.cpp's auto-fit defaults to
`n_parallel = 4` and divides the KV cache four ways — **set slots to 1** for a single
user and 20224 becomes 32k+.

---

## Opened 2026-11-14 — Asgard audit: version lag, image pinning, one non-declarative login

Full sweep on 2026-11-13/14. **The box is healthy** — no crash loops (`NRestarts` 0 everywhere),
no zombie or D-state processes, zero OOM kills ever, PSI ≈ 0, SMART clean on all three disks
(0 reallocated / 0 pending / 0 uncorrectable / 0 CRC). The NVMe's 191 unsafe shutdowns all cluster
on **2026-08-10**, the RAM-failure period — not ongoing. What follows is what is actually open.

### ⭐ Jellyfin is two majors behind, and it is the one that matters

> ⏸ **Re-verified 2026-11-24: unchanged.** `/System/Info/Public` still reports **10.11.11**, and
> no `package` override exists in `Modules/Server/`. Still the highest-value open item.

`10.11.11` running; upstream is **12.4**, and **unstable already has exactly 12.4**. One line
through nixflix's `package` option moves it. It is the highest-value item because Jellyfin is
**internet-exposed through cloudflared**, so the gap is a security one, not just a feature one.

⚠️ Not a drop-in: two majors means DB migration and breaking changes, and nixflix's own
`lib/jellyfin-plugins.nix` set has to be checked against 12.x first. Back up
`/data/.state/services/jellyfin`. Full table and the escape-hatch pattern:
`Claude/server-info.md` → *Nixflix Notes → Versions*.

### Home Assistant is six releases behind

> ⏸ **Re-verified 2026-11-24: unchanged** — `homeassistant/const.py` on the live box reads
> `MAJOR 2026 / MINOR 5 / PATCH "4"`.

`2026.5.4` running (stable's pin); upstream is **2026.11.0**, unstable has **2026.10.4**.
⚠️ 2026.11 folds HACS into a built-in Marketplace and the standalone HACS installer stops there,
so that transition is coming either way. Run `check_config` first — see
[[ha-config-validate-check-config]] for why it aborts on a pinned `colorlog`.

Everything else (Sonarr, Radarr, Prowlarr, SABnzbd, Glance, Immich, Suwayomi) is **identical to
or within one point release of** upstream. Sonarr and Radarr are byte-identical.

### ~~All five~~ **Four of five** container images are `:latest` — pin them by digest

> ✅ **Shelfarr is done (2026-11-23)** — pinned by multi-arch index digest to `2026.11.16.1`, and
> the bump itself is proven safe (five months of migrations ran clean). ✅ **FlareSolverr left the
> list entirely (2026-11-24)** by going native, so this is now **three** unpinned images:
> `audiobookshelf`, `filebrowser`, `decluttarr`.
>
> ✅ **And the last three went in on 2026-11-24** — `audiobookshelf`, `filebrowser`, `decluttarr`,
> each pinned to the digest it was **already running** (read with
> `ssh -t asgard 'sudo podman images --digests | …'`, which needs root). ⭐ Pinning to the
> *running* digest rather than upstream's current one is what makes it a no-op instead of a
> three-way bump of stateful services. **There is now no `:latest` anywhere in the repo.**
> ⚠️ They were 5 / 5 / 6 months old at pin time, so the staleness is recorded, not fixed — each
> is still owed its own bump, with its own backup. Decluttarr is the easy one: stateless.
>
> ⚠️ And the Shelfarr bump surfaced a cost the text below does not anticipate: it installed
> **new** settings keys at upstream defaults and broke Shelfarr's search. See the 2026-11-23
> Books section.

The only genuine reproducibility hole in the setup. Images live outside the Nix store, so a
generation rollback restores the unit but not the image, and `oci-containers` only pulls when the
image is *absent* — each is frozen at whatever was first pulled, with no version in the config and
no way back. Pinning moves no service and costs nothing.

**⭐ Upgraded from "reproducibility hole" to a fault that has actually bitten (2026-11-15).**
A frozen image does not merely lack features — it misses upstream **data migrations**, so the
database keeps values upstream has since retired. Shelfarr's image is the **2026-06-15** build
(newest applied migration `20260607120000`). Migration `20261012090000` replaces the Z-Library
mirror list; it has never run here, so `zlibrary_url` still held three dead domains while
`zlibrary_configured?` returned true. Enabled, credentialled, and resolving nowhere — and Shelfarr
runs no health check on Z-Library, so nothing would ever have reported it.

Fixed by pinning `zlibrary_url` in `books.nix`. **But that is a patch on one setting, not on the
cause** — any other migration-borne default is still stale and undetected.

Two things follow, and they pull in opposite directions:
- Pinning by digest makes the staleness *visible and deliberate* rather than accidental.
- Pinning alone does **not** fix it. Something still has to pull a newer image and let the
  migrations run. A digest pin that is never bumped is the current situation with a version number
  attached.

Worth deciding together with how often these get refreshed at all. Check any instance with
`select max(version) from schema_migrations` against upstream `db/migrate/`.

### ✅ DONE 2026-11-24 — FlareSolverr went native (5 containers → 4)

> ✅ `services.flaresolverr.enable = true` in `manga.nix`, replacing the container. It moved **no
> version** (nixpkgs 3.5.2 = exactly what the container served), so this really was the free win.
> Three things moved with it in the same deploy: `books-setup`'s `after`/`wants` now name
> `flaresolverr.service`, and `stats.nix`'s `ASGARD_UNITS` has `flare = [ "flaresolverr" ]`.
> ✅ Live since 2026-11-24 — 200 from localhost:8191, NRestarts=0. Full note, including why the module having no `host`
> option is load-bearing: `Claude/server-info.md` → *FlareSolverr is native*.

`services.flaresolverr` exists, nixflix even wraps it as `nixflix.flaresolverr.enable` with a
readiness probe the container lacks, and **nixpkgs 3.5.2 = upstream 3.5.2**. All three consumers
reach it on host `:8191`. Audiobookshelf could follow (4 → 3) but needs a data migration and
`books-setup` re-pointing. ⚠️ **FileBrowser cannot** — the container is the *Quantum* fork, a
different project from the `filebrowser` in nixpkgs. Detail in
`Claude/server-info.md` → *Podman containers*.

⛔ The reverse — everything into podman — was considered and rejected: it means dropping nixflix,
which is what declaratively manages the quality profiles, indexers and arr wiring.

### Shelfarr's login is the one piece of non-declarative auth

`books-setup.service` writes its `Setting` rows but never creates a `User`. One account exists,
registered by hand 2026-06-24. Added to *Before any fresh wipe* above;
mechanism and reset command in `Claude/server-info.md`.

### Pending, needs root on Asgard (sudo now wants a password)

In this order — **the order is load-bearing**, see `Claude/deploy.md` → *A retired named profile is
invisible to GC*:

1. `sudo rm -rf /var/lib/qBittorrent` — 8.1 MB, owner is a bare uid **70 with no user behind it**,
   last written 2026-06-27, app long removed
2. `sudo rm -rf /var/lib/arr-policy-backup-20260823-184908` — 2.3 MB; **optional**, it is the only
   snapshot of the pre-arr-policy config (`server.nix.before`, `sonarr-series.json`)
3. `sudo rm -rf /tmp/sonarr_backup` — ⚠️ **re-verified 2026-11-24: it is no longer empty** (3
   entries, last written 2026-11-22), so the `rmdir` this line used to say would just fail
4. `sudo rm /nix/var/nix/profiles/system-profiles/asgard{,-21-link}` — unpins **17.8 GiB**
5. `system-rebuild rock Asgard` — purges the stale `[asgard]` boot entry. ⚠️ This step is **only**
   about the boot entry now: the Shelfarr icon fix and the Bleach TYBW profile it used to also
   carry were deployed 2026-11-14/15. It still has to run *after* step 4, not before.
6. ~~**Reboot**~~ — ✅ **DONE: the box rebooted 2026-11-23 ~19:08.** `it87` is loaded and
   healthy — `hwmon5 = it8689` with **three fan inputs reading real RPM** (1283 / 1108 / 1144
   on 2026-11-24), so fan monitoring and the dashboard fan card are alive again.
7. Remote → Asgard → **Garbage collect**

⚠️ **The reboot happened out of order, which changes what is left.** It was step 6; it ran
before steps 4–5. That costs nothing — it unpinned the old `booted-system` closure as intended
— but the **named profile is still pinning its 17.8 GiB**, so a GC run *now* would recover only
part of the ~29 GiB. The remaining sequence is therefore **4 → 5 → 7**, and the ordering between
those three is still load-bearing.

✅ **Re-verified on the live box 2026-11-24** (what is genuinely still there):
`/nix/var/nix/profiles/system-profiles/asgard → asgard-21-link →
nixos-system-Asgard-26.05.20260727.2f5a153`, `/var/lib/qBittorrent` (uid **70**, 2026-06-27),
`/var/lib/arr-policy-backup-20260823-184908`, `/tmp/sonarr_backup`.

### Books — two one-click jobs in the UI, neither will happen on its own

Both need a human in a web UI; nothing retries either automatically.

- **Re-request *The Dungeon Anarchist's Cookbook*** (Shelfarr request 7). It is marked
  **completed** holding the single azw3 that started the epub-only policy, and a completed request
  is never re-searched. Z-Library went live 2026-11-15 and should now have an epub — this is the
  book that motivated adding it, and it is still the one book that has not benefited.
  ⏸ Re-verified 2026-11-24: `/data/media/books/Matt Dinniman/The Dungeon Anarchist's Cookbook/`
  still holds **only the `.azw3`**. ⚠️ And it cannot be actioned right now anyway — Shelfarr's
  search is down on the metadata-provider fault (2026-11-23 Books section).
- **Match All in Audiobookshelf** — two covers still missing (*The Hunger Games*, and the
  Cookbook, whose azw3 has no extractable cover by design). Library → ⋯ → Match All.

### Two decisions waiting on rock

- **Immich runs completely empty** — 4 services, ~730 MB RAM, admin seeded, exposed via Cloudflare
  tunnel, and `/data/photos` is **4 KB**. Use it or turn it off.
  ⏸ Re-verified 2026-11-24: still exactly **4.0 K**. Nothing has been put in it.
- **Anchorman 2** — 5 GB in `/downloads`, genuinely not in the library. Keep or delete.
  ⏸ Re-verified 2026-11-24: still there —
  `/downloads/usenet/complete/radarr/Anchorman.2.…DUAL-100REAL/…mkv`. It and one Silo S01E04
  torrent file are the only two things over 1 GB in `/downloads` (5.3 G total).

### Noted, not worth acting on

- Jellyfin trickplay is **9.6 GB** of its 13 GB state — a legitimate feature, just the biggest
  single consumer. Subtitles are another 2.2 GB.
- `/var/lib/jellyfin/metadata` (4.5 GB) sits on the **NVMe** while the rest of Jellyfin's state is
  on disk1. Both work.
- Decluttarr's ~83 "errors" a week are **podman mapping its INFO output to `err` priority** — pure
  false positives, but they poison `journalctl -p err` for real triage.
- NVMe sensor 3 runs **72 °C**, the hottest thing in the box; everything else is 27–38 °C. 7% life
  used, 77.65 TB written.
- Pool at **86%** (2.6 TB free): disk1 82%, disk2 88% — 2026-11-24, up from 84% / 80% / 87% on
  2026-11-14. ⚠️ `/data` itself is not a mount; the pool is `mediapool` on **`/data/media`**, so
  `df /data` reports the root filesystem and looks reassuringly empty.
- SABnzbd never prunes `nzb-backup` — roughly 1.9 GB per 5 months, regrows forever.

---

## Opened 2026-11-20 — Luciole replaced Thunar on Sisyphus

Done and building: `Modules/Desktop/luciole.nix`, flake input `luciole`, Mod+E via the
`file-manager` shim. Full picture in `Claude/luciole.md`. Sisyphus **no longer imports
`Modules/Desktop/thunar.nix`**; Elektra kept Thunar, Apollo keeps it for the ISO's Mod+E.

**Not yet exercised on real hardware.** The build is proven (Sisyphus toplevel exit 0,
`luciole-0.1.0` compiled, `luciole config validate` passed over the generated
`config.toml`), but nothing below has been *looked at* on a live session yet:

- **Does it come up at all** — it is 0.1.0 and draws straight onto Wayland/GLES. Mod+E,
  then an actual browse: thumbnails, the side preview, drag-and-drop out to other apps.
- **`org.freedesktop.FileManager1`** — the module claims the name through
  `~/.local/share/dbus-1/services/`. Unverified end to end: test with VSCodium's *Reveal
  in File Explorer* or a browser download's *Show in folder*. Nothing else on Sisyphus
  provides the name any more, Thunar having gone.
- **Archive extraction.** Thunar had `thunar-archive-plugin` + xarchiver wired up with an
  overlay (the nixpkgs `.tap` bug). Luciole bundles `7zz` on its own PATH, but whether
  right-click extract exists and works is unchecked. If it does not, that overlay
  workaround is *not* the thing to resurrect — look at Luciole's scripts directory
  (`~/.local/share/luciole/scripts/`) instead.

### Open, deliberately not done

- **The FileChooser portal is NOT wired.** Luciole ships a backend that would become the
  Open/Save dialog for every app; left alone at 0.1.0. One `portals.conf` stanza away —
  `Claude/luciole.md` → *Not done*.
- **Fonts fall back to Fontconfig `sans-serif` 14px**, not the shell's 42dot Sans, because
  this repo sets neither GNOME's `font-name` nor a `gtk-font-name`. A one-liner in
  `Modules/Desktop/desktop.nix` beside the existing `color-scheme` key would fix it, but
  that key is read by **every** GTK app, so it changes more than Luciole.
- **Thumbnails on `/data`.** `thumbnail_policy = "local"` skips network shares, and Asgard's
  pool is a network share from here. `"all"` turns them on if that is wanted.

### Fresh-wipe gap (feeds `fresh-wipe-reproducibility-gaps`)

Luciole deliberately splits config: Nix owns `config.toml`, **the GUI owns
`settings.toml` and wins over Nix**. That is the opposite of noctalia, and it is the
*designed* seam, so GUI tweaks survive rebuilds — but it also means **a wipe loses every
GUI tweak**, plus:

- `~/.config/gtk-3.0/bookmarks` — sidebar bookmarks (shared with Nautilus/Nemo)
- `~/.local/state/luciole/state.toml` — Places layout, custom bookmark icons, last tabs

Same class of gap as noctalia's layout and the wallpapers: if a tweak is worth keeping,
promote it into the module's `settings` block rather than leaving it in `settings.toml`.

### After a `nix flake update`

A rebuild failure naming `luciole-config.toml` means a **setting's type or accepted values
changed upstream** — revisit the `settings` block, nothing is broken. Unknown keys only
warn at runtime, but `checkConfig` runs the strict `luciole config validate`, which is
exactly why it is left on: a schema change fails the build instead of silently
half-applying. Don't "fix" it by turning `checkConfig` off.

### Colours (added same day)

Wired: `my.noctalia.lockedSettingsExtra.theme.templates.user.luciole` in
`Modules/Desktop/luciole.nix`. Luciole ships its own noctalia template, so there is
nothing of ours to maintain. Proven by rendering it against the live
`~/.config/noctalia/palettes/skwd-wall.json` — all 30 tokens resolved.

- ⚠️ **After the switch, run `noctalia-apply-palette` once** (or change the wallpaper).
  `templates-apply` alone can report ok and write nothing.
- ⛔ **Icon recolouring was deliberately NOT wired.** It needs a
  `FollowsColorScheme=true` theme (Breeze/Tela/Colloid) selected through GNOME's
  `icon-theme` dconf key, which every GTK app reads — and a desktop-wide
  adw-gtk3-dark + Papirus pass was rejected on taste on 2026-09-25. **Ask before
  building it.**
- ⚠️ **Found in passing, not fixed:** noctalia 5.5.0 warns on every start that our
  `settings.toml` uses the **renamed** palette role `surface_variant` (now
  `surface_container`) in three places — `bar.main.capsule_group[0].fill` and both
  `lockscreen-login-box` `background_color`s. It comes from our own `lockedSettings`
  in `Modules/Desktop/noctalia.nix`, so it is a one-line-each rename there. Harmless
  today (noctalia falls back), but it is real config drift against upstream.

### Folder icon shape (added same day)

rock didn't like Adwaita's soft folder corners. Added `my.luciole.iconTheme`, an enum
of six themes ranked by **measured** folder corner radius (see `Claude/luciole.md` →
Folder shape). Default `papirus` (4.4%, vs Adwaita's 7.8%, already installed, follows
the palette).

- ⏸ **He chose to judge it on the monitor before going sharper.** If Papirus still reads
  soft, `zafiro` is the square one (1.6%) — but it keeps its own hue instead of tracking
  the wallpaper. `flat-remix` (2.8%) is the sharp option that *does* follow the palette.
  Comparison page with the real icons at size:
  https://claude.ai/artifact/N9HP9SBUxSi7K1aV19CZZx
- ⚠️ `icon-theme` is read by **every GTK app**, so this is a desktop-wide change that
  happens to live in a Sisyphus-only module. If the look is wrong it is one word, **not**
  a reason to revisit the adw-gtk3-dark pass rejected on 2026-09-25.
- ⛔ `numix-icon-theme-square` is excluded on purpose: "square **apps** icons", inherits
  Numix folders at 10.2% — softer than Adwaita.

### Chrome went olive — fixed with our own template (2026-11-21)

Upstream's `colors.toml` template takes **every** token from the palette, surfaces
included, so the toolbar, search field and file area all took the wallpaper's tint
(`surface #131408`, olive). rock: colour belongs in the sidebar, not the top bar or the
background. Fixed by shipping `Resources/Luciole/colors.toml`, which runs the surface
family through noctalia's `grayscale` filter (lightness kept, hue removed) and leaves
the accent families alone. `Claude/luciole.md` → Colours.

- ⚠️ **Token parity with upstream is not enforced.** A token added upstream is missing
  from ours and Luciole falls back to its built-in value **without erroring** — it fails
  quietly. The `diff` one-liner is in the template's own header; run it after a bump.

### ⏸ Fresh-wipe gap, now concrete

rock has tuned Luciole through the GUI and `settings.toml` **wins over Nix** — that is
the designed seam, not drift, so don't "fix" it by editing the module. But it means
**a wipe loses the look**. As of 2026-11-21 his GUI holds values the Nix baseline does
not: `background_opacity = 0.54` (baseline 0.9), `corner_radius_scale = 0.1`,
`grid_icon_size = 80`, `always_show_tab_bar = false`, `hidden_last = true`,
`show_preview = false`, `sidebar_width = 176`, `miller_column_width = 212`.

**Offered, not done** — promoting these into `programs.luciole.settings` is the only
way a fresh install comes up looking like this. Ask before doing it: he may still be
tuning, and once promoted a GUI *Reset* returns to these rather than to stock.

---

## Opened 2026-11-22 — Battle.net under Proton: live, with one parked decision

`Modules/Gaming/battlenet.nix` + `Resources/Scripts/battlenet.sh`, Sisyphus only.
Built, switched, installed and logged in the same day. Full story in
`Claude/battlenet.md`; only the loose ends are here.

### ⏸ 1. niri's `^steam_app_` rule now catches a launcher — decide it

Battle.net's window is `steam_app_battlenet` (umu sets `SteamAppId` from `GAMEID`),
so the generic games rule in `Modules/Desktop/niri.nix` opens it **fullscreen on
DP-2**. Nothing visibly misbehaves, and that rule must **not** simply be deleted
(`niri-rule-reapplies-on-window-recreate`), so an exclusion was **proposed and not
applied** — it wasn't proven harmful and rock hadn't asked. ⚠️ Every future
umu-launched app inherits the same collision, so this wants settling before the
second one, not after.

### ⏸ 2. The icon + `StartupWMClass` fix is BUILT, not switched

The 2026-11-22 icon work (build-time extraction from the pinned installer; the
corrected `StartupWMClass = "steam_app_battlenet"`, which had been a wrong guess of
`battle.net.exe`) evaluates on all four hosts and the derivations build, but needs
`system-rebuild rock Sisyphus` to reach the system. Until then the launcher still
shows the generic cog. ⚠️ Same class of thing as item 8 — a real fix living only in
the tree.

### 3. The honest fresh-install gap

Nix owns the launcher, Proton, the installer's first byte, the icon and the desktop
entry. It does **not** own, and cannot:

- the Wine prefix `~/Games/Battle.net` — imperative by construction, like `compatdata`;
- the Steam Linux Runtime container umu downloads into `~/.local/share/umu` (a few
  hundred MB; nixpkgs has no steamrt4/sniper to substitute).

So a wipe comes back with a working `battlenet` command and **re-downloads the client
and every game** (WoW alone is ~52.6 GB). That is the limit, not a bug — but don't
plan a wipe assuming the Blizzard games come back for free. ⛔ And never sweep that
prefix to reclaim disk: it *is* the games (`sisyphus-disk-reclaim-sweep`).

## Opened 2026-11-23 — Elektra: reconnected, her fixes landed, three things left

Her machine was never actually off the tailnet — it had registered as node `kit-kat`
and the 2026-10-09 rename was never deployed, so the host tables asked for `elektra`,
which did not exist, and every push failed for six weeks. Broken with one
`system-rebuild kitkat Elektra --target kit-kat`; the node renamed itself on reboot
and plain pushes work now. Detail in `Claude/elektra.md` and
`Claude/elektra-handover.md`.

Landed and verified the same day: her USB/BT power pinning (`btusb.enable_autosuspend=0`
+ three udev rules), her Wi-Fi-scanning fix (`wifi-radio-off-at-boot`), `sleepy-cat`
removed from her shell, and every window opaque except the terminal.

**Still open:**

1. **Her play/pause media keys do nothing in Spotify.** Ruled out: binds live in
   Hyprland, `playerctl` resolves and targets spotify, only `spotify` on the MPRIS bus
   (the `skwd-music` trap does not apply — and our own `niri.nix:20` comment already
   suspected skwd v2 dropped that inert player; her box confirms it), and her 2.4G
   receiver's Consumer Control interface advertises `KEY_PLAYPAUSE`. **Untested:**
   whether the press reaches the compositor; suspect an Fn-lock on the F-row.
   ⚠️ Capture evdev **to a file** — `timeout 15 od …` buffers and silently loses short
   output, which cost one false "nothing happens" result:
   `timeout 15 cat /dev/input/event3 > /tmp/ev.bin` then `od -An -tx1 -w24 /tmp/ev.bin`
   (`0xa4` = `KEY_PLAYPAUSE`).

2. **Her headset powers off entirely** — distinct from the Wi-Fi stutters, which are
   fixed. Headset-initiated (`lost RFCOMM connection`, `Connection reset by peer`
   18 ms later), audio healthy until that instant, not on a timer (14 min – 1 h 39).
   Next step: catch one inside a `btmon` trace and read the HCI disconnect reason.

3. **Lockscreen login boxes are still `background_opacity = 0.88`** — the last
   transparent surface besides her terminal. Deliberately not changed: the value is
   hardcoded in the `loginBox` helper in `Modules/Desktop/noctalia.nix`, which
   **Sisyphus imports too**, so editing it there would also make rock's lockscreen
   solid. The fix belongs in her `my.noctalia.lockedSettingsExtra` — see the
   shared-module trap. Awaiting a decision.

4. **Her clone at `/home/kitkat/Dots` is still a diverged fork** and her own Claude
   session still works in it. Now that pushes work it is redundant, and Asgard's
   second checkout was deleted for exactly this reason. The handover protocol
   (`Claude/elektra-handover.md`) contains the risk meanwhile. Deleting it is rock's
   call.

---

## Opened 2026-11-23 — Books: fixed and live, three things left open

Full detail in `Claude/server-info.md` → *Books*. Three Mistborn books were parked on dead
Usenet releases; `preferred_download_types` is now `[direct, usenet]`, the Shelfarr image is
pinned by digest at `2026.11.16.1`, `books-setup` un-parks failed requests and waits for
Prowlarr, and ✅ **all seven books are on disk** (verified as real `.epub` *files*, not just
folder names).

⭐ The bump also delivered more than was credited at the time: `2026.11.16.1` **blocklists a
failed release and auto-selects the next one** (`release_blocklisted` / `fallback_selected` in
`request_events`), so the structural no-fallback bug is fixed upstream. It was written up here
as unverified; it is now proven live. ⛔ It also **moved the request status enum** — `status = 3`
no longer means `failed`.

### ✅ 1. Container images — ALL pinned by digest 2026-11-24, nothing left on `:latest`

`audiobookshelf`, `filebrowser`, `flaresolverr` and `decluttarr`. Same latent staleness that
had Shelfarr frozen on a five-month-old build while reading as current: images live outside
the Nix store, `oci-containers` only pulls when one is *absent*, and a generation rollback
restores the unit but **not** the image — so each is pinned to whatever was first pulled,
with no version in the config and no way back.

Shelfarr proved the bump path is safe (five months of migrations ran clean, both services
came back 200, every pinned `Setting` survived). **Deliberately not done in the same pass:**
bumping four *working* services at once is a separate and riskier change, and each wants its
own backup-and-verify. One at a time, with the DB/state backed up first where it has any.

### ⏸ 2. A build-time guard for the `rails runner` payloads

⛔ **`bash -n` cannot catch a stray `"` or `'` inside a `rails runner` payload, and neither
can `nix build`.** The payload sits inside the outer script's `'…'`, so the outer shell stays
balanced whatever goes in it — the breakage is in the **inner** `sh -c` parse, at runtime.
This shipped a broken deploy on 2026-11-23 (a comment reading `so "it downloaded" and "it
worked" are`); `books-setup` restart-looped 6× and the switch reported `status 4`, which took
a second rebuild to clear.

The working check — extract each payload and `ruby -c` it — is documented in
`Claude/server-info.md`, but it is a thing you have to *remember to run*. It could be made
impossible to get wrong with an assertion in the derivation that each payload contains no
`"`, `'` or backtick: cheap with `grep` in a `runCommand`, **no ruby in the closure**, and the
same spirit as `writeShellApplication` shellchecking `Resources/Scripts/*.sh` at build time.

Not implemented — it adds a step to Asgard's build graph, so it is rock's call.

### ✅ 3. Shelfarr search — FIXED AND DEPLOYED 2026-11-24

**Was a live fault blocking every search.** The Search page returned *Unable to connect to metadata
service* on any query. ⛔ Not an indexer problem — metadata lookup runs *before* any indexer, so
no search was happening at all.

The bump introduced metadata-provider settings that `books-setup` has **never** written, so they
landed on upstream's defaults: `metadata_provider_priority = hardcover,openlibrary,google_books,
comic_vine` with `hardcover_enabled = true` and an **empty** `hardcover_api_token`. Egress from
Asgard is healthy — Open Library **200** (needs no token), Hardcover 400 on a bare GET
(reachable, needs a token), Google Books **429** (rate-limited without a key). So the first
provider in the chain has no credentials and the second is throttled.

✅ **Fixed by pinning all three keys in `books-setup`** — `metadata_provider_priority =
openlibrary,google_books,comic_vine`, `open_library_enabled = true`, `hardcover_enabled = false`.
✅ **Deployed 18:12 on 2026-11-24**, generation `h81w4rx9…`: `SETTINGS_CHANGED=2`,
`ok=true sab=true`, `NRestarts=0`, no failed units. ⭐ The count of **2** is the tell that it hit
the right keys — only two of the three differed from the bump's defaults.

⏸ Still available if the metadata ever looks thin: a Hardcover API token in sops, then flip
`hardcover_enabled` back on with `hardcover` first. It is off for want of a credential, not on
merit.

⭐ **The generalised lesson, worth more than the fix:** the digest-pin note already said to
re-check the keys `books-setup` writes after a bump. That is not enough — a bump can introduce
*new* keys that change behaviour, and `books-setup` only pins what it once had to change. It
should pin every setting the pipeline **depends on**.

---

## Opened 2026-11-23 — Asgard renamed itself to `asgard-1`: fixed, one rebuild pending

Reported as "my entire Tailscale connection is down, I can't access Asgard's services on
my phone". It was not: every service answered on `100.126.205.100` and every node was
online. `asgard` had simply stopped resolving — the node's MagicDNS name was now
**`asgard-1`**, so every by-name URL died at once.

Self-inflicted, the same day. The `extraSetFlags = [ "--hostname=…" ]` line added to
`Modules/Server/network.nix` (a copy of one written for Elektra) fired on generation
190's activation at 20:06 and pushed `asgard` at a node registered as `Asgard` — a
case-only change that Tailscale treats as a rename, which collided with the node's own
name and took the `-1` suffix. Full post-mortem, the evidence and the
`extraSetFlags` vs `extraUpFlags` rule: `Claude/server-info.md` → *Tailnet node name*.

Done:

- Recovered by renaming the machine back to `asgard` in the Tailscale admin console,
  which also pins the name against later client-side pushes. `asgard` resolves again.
- `Modules/Server/network.nix` — `extraSetFlags` → **`extraUpFlags`**, which only fires
  on a node that is not registered yet, so it still names a freshly installed Asgard but
  can never rename the live one.
- `Modules/Core/tailscale.nix` — the flag **removed**, replaced by a ⛔ comment. Sisyphus
  and Elektra set no `authKeyFile`, so the safe form would be a silent no-op there.
- Verified: all four hosts evaluate, `tailscaled-set` is no longer defined for Asgard,
  `extraUpFlags = ["--hostname=asgard"]` and `extraSetFlags = []`.

**Still open:**

### ✅ 1. Asgard switched — this is CLOSED (2026-11-24)

The fix needed `system-rebuild rock Asgard`, which needs rock's password (sudo there is no
longer passwordless). ✅ **That rebuild happened 2026-11-24 18:12** (generation `h81w4rx9…`) and
`tailscaled-set.service` **no longer exists on the system** — the unit that ran
`tailscale set '--hostname=asgard'` on every activation is gone, so the mechanism that caused
the rename cannot fire again.

Both halves are now fixed: the node has resolved as **`asgard`** on `100.126.205.100` since the
console rename, and the client-side push that renamed it is gone from the config.

⚠️ Item 2 below is still open — nothing in the repo recreates the node *names*.

### ⏸ 2. Nothing in the repo recreates the node names

The recovery was a console edit, like the tailnet's ACL and its DNS settings. A rebuilt
tailnet would hand Asgard whatever name it derives, and if a stale entry holds `asgard`
it would land on `asgard-1` again with no warning. A fresh-install reproducibility gap of
the same family as the ACL one in the 2026-10-02 section above — worth listing there if
that gap is ever closed properly.
