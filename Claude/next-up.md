# Next Up — open work

Backlog for this repo. Nothing here is broken *today*; these are gaps that only
bite on a **fresh install**, plus a few loose ends worth closing.

Ordered roughly by value. Written 2026-09-15, extended 2026-09-27 (items 7–8).

⚠️ **Item 8 is the exception to "nothing here is broken today"** — Sisyphus has real
fixes live only as hand-edits, waiting on a `nixos-rebuild switch`.

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
- **Odysseus** is on skwd v1 and the user expects to retire it. Until then it
  shares `Modules/Desktop/noctalia.nix`, so check the host import matrix before editing
  shared modules — see `Claude/skwd-wall.md`.

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
- **Eclipse stream audio is a live `pactl` hack and dies on reboot.** PulseAudio there has
  only `auto_null` and never claims the HDMI card. Durable fix: add
  `--setenv=SDL_AUDIODRIVER=alsa` to the Moonlight launch so it bypasses PulseAudio
  entirely — the same ALSA path Kodi already proves works.
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

The *functional* config is genuinely declarative. It is specifically the
desktop's **appearance**, and anything living in a vendor console, that is not.

---

## Opened 2026-10-02 — Apollo USB + Kit-Kat's machine

See `Claude/deploy.md` and `Claude/kit-kat.md`. Phases 1-3 of the plan are built and
verified; what follows is what is genuinely still open.

### Blocking the first install of Kit-Kat

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
3. **Confirm `installDisk`** in `Hosts/Kit-Kat/system.nix` (currently `/dev/nvme0n1`).
   Everything on that device is destroyed. `apollo-connect` then
   `lsblk -o NAME,SIZE,MODEL`.
4. ~~Her `&kitkat` age key~~ ✅ **DONE 2026-10-02.** Host key at
   `~/.local/share/apollo/Kit-Kat/`, recipient in `.sops.yaml`, `kit-kat.yaml`
   re-encrypted, and `apollo-deploy` plants it automatically.
5. **Swap is a guess.** 16 G with `resumeDevice = true` (hibernate intent), chosen
   without knowing her RAM. Revisit alongside `installDisk` once `facter.json`
   reports it. Note this also puts the layout over disko's hardcoded 4 GiB VM-test
   disk, so use `apollo-deploy --dry-run`, not `--vm-test`, to check it.
5. **`Hosts/Kit-Kat/facter.json` does not exist.** The host evaluates and builds
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
10. **`rain-effect` on NVIDIA is unverified.** GLES2 `wlr-layer-shell` overlay; expected
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
