# Wolf — multi-session Moonlight server (games-on-whales)

**Status: working end-to-end as of 2026-09-28.** Sisyphus hosts, Eclipse streams.
Module: `Modules/Gaming/wolf.nix`. Started as a trial alongside Sunshine and is now the **live**
streaming host. Sunshine stays installed as the fallback, with `autoStart = false`.

> ⚠️ **Wolf and Sunshine cannot run together *on the default ports*.**
> Wolf is now `autoStart = true` (changed 2026-09-28; this doc said `false` until
> 2026-10-03). That is only safe because `Modules/Gaming/sunshine.nix` has
> `autoStart = false` — a matched pair, never set both true.
> **Sunshine is a USER unit:** `systemctl --user stop sunshine` (NOT `sudo systemctl`).
>
> 📌 **Corrected 2026-10-05 — "cannot run together" is too strong.** Measured with
> `ss` against a live Wolf: they collide on exactly **four** ports — TCP 47984,
> 47989, 48010 and UDP 47999. Wolf does **not** bind 47998, 48000 or 47990, so the
> first two entries in this module's `allowedUDPPorts` are dead weight. Sunshine's
> `port` key is a single *base* and every other port is an offset from it, so
> `port = 48989` yields 48984/48989/48990/49010 + UDP 48998/48999/49000/49002/49010
> — **zero overlap**, and both daemons can run at once. Moonlight supports it: the
> 6.1.0 binary has `manualaddress`/`manualport` and learns the HTTPS port from
> `serverinfo`. Offset **Sunshine**, never Wolf — Wolf keeps the defaults every
> paired client already points at. ⚠️ **Not yet implemented**; see
> `Claude/next-up.md`. ⚠️ **Do not set `services.sunshine.settings.port`** to do it
> — see the nixpkgs trap in `Modules/Gaming/sunshine.nix`.
>
> ⚠️ **Because Wolf always runs, a left-open session coexists with desktop Steam
> by default** — which is both the shared-`steamapps` hazard below *and* the
> input bleed in "Quit-by-chord strands the virtual pad".

## Why Wolf over Sunshine

Sunshine *captures an existing output*, so a stream occupies a real monitor and
shares the desktop's single input focus. Wolf *creates a virtual desktop per
session* with its own virtual inputs, in containers. Consequences here:

- **No longer capped at 1080p.** Sunshine captured the physical `HDMI-A-1`
  (1920x1080). Wolf's virtual output is whatever the client asks for — 4K works.
- **Per-game niri output rules are obsolete.** Games render into Wolf's virtual
  display, never on a physical output, so the old "Stray opens on DP-2" class of
  bug cannot occur. No `open-on-output` rule needed.
- Deleted a whole planned project: EDID injection, multi-seat, a second user.

**Eclipse needed NO changes** — it runs the Moonlight *client*, which speaks to
Wolf exactly as it did to Sunshine.

## 🔑 The gamepad fix — the hard-won one

**Symptom:** pad works perfectly in Steam Big Picture, is completely invisible to
the game. Costs hours if you chase it from the wrong end.

**Cause:** games enumerate gamepads through **udev**. Wolf's `fake-udev` shim does
not relay udev events for the virtual pad into the container — the kernel events
exist, the udev ones never arrive. **Steam is immune because it also scans
`/dev/input` directly**, which is exactly what makes the symptom so misleading.
Upstream: [wolf#81](https://github.com/games-on-whales/wolf/issues/81).

**Fix** (`WOLF_DOCKER_FAKE_UDEV_PATH = ""` lives in `Modules/Gaming/wolf.nix`):

```nix
WOLF_DOCKER_FAKE_UDEV_PATH = "";   # image defaults it to /etc/wolf/fake-udev
```
Wolf's check is `use_fake_udev = !path.empty() || exists(path)`, so an **empty
string is the only way to disable it** — leaving it unset does nothing.

Plus, in `config.toml`'s Steam app: `'/dev/input:/dev/input:rw'` and
`devices = [ '/dev/uinput:/dev/uinput:rwm' ]`.

⚠️ **Do NOT also add `/run/udev:/run/udev:ro`.** Upstream issue #81 lists it
because it assumes a hand-written compose file; **Wolf's runner mounts /run/udev
itself** once fake-udev is off. Adding it makes Docker reject the container with
`400 Duplicate mount point: /run/udev` — which Moonlight reports to the user as
**"lobby is full"**. That error names nothing useful; check the Wolf log.

**Trade-off (accepted):** exposes input devices across containers, so concurrent
streamers would see each other's pads. Fine — Eclipse is a single-seat couch box.
Does **not** weaken the seat9 desktop isolation, which is a different boundary.

### Diagnosing gamepad problems — order that works

1. **Is the pad emitting at all?** On the host, `dd if=/dev/input/event<N> bs=24
   count=40`. Bytes flowing = pad fine *and* nothing holds an `EVIOCGRAB`.
2. `udevadm info /dev/input/eventN | grep ID_INPUT_JOYSTICK` — must be `1`.
3. Only then look inside the container.

## 🔑 Desktop input isolation (seat9) — verified working

Wolf's virtual pads are created in its container but appear as **real devices in
the host kernel**. Without upstream's `85-wolf.rules`, logind grants the desktop
user a `uaccess` ACL and the streamed controller drives niri too
([wolf#451](https://github.com/games-on-whales/wolf/issues/451)).

Our rules park them on a phantom **`seat9`** and strip `uaccess`.
**Verified 2026-09-28:** all three `Wolf DualSense (virtual) pad*` devices show
`ID_SEAT=seat9`, `CURRENT_TAGS` without `uaccess`, and no `user:rock` ACL — and
the user confirmed niri does not react while the pad drives the stream.

⚠️ The devices are still `crw-rw---- root:input` and rock **is** in `input`, so
file bits alone would permit an open. **The protection is the seat assignment** —
compositors enumerate via libseat/logind for seat0 only.
⚠️ `niri msg devices` is **not a real subcommand**; don't use it as evidence.

## ⭐ Quit-by-chord strands the virtual pad, and Steam picks it up (2026-10-03)

**Reported as:** "the Wolf session is bleeding into my Steam" — controller input
flashing, keyboard/mouse intermittently locking up, desktop Steam feeling glitchy.
All three are one cause.

### The chain

1. **Moonlight's quit-stream shortcut is the pad chord L1 + R1 + Select + Start.**
   Quit that way and Moonlight sends the four presses, then tears the connection
   down *before* the releases arrive.
2. **Wolf never reaps the session**, so its virtual DualSense stays alive with all
   four buttons held. `EVIOCGKEY` is the only thing that sees it — the pad emits
   nothing, so a raw read looks like a perfectly healthy device:
   ```
   event256 "Wolf DualSense (virtual) pad"
     -> BTN_TL(310), BTN_TR(311), BTN_SELECT(314), BTN_START(315)   held, silent
   ```
3. **Desktop Steam adopts it**, because the seat9 rules don't stop Steam (below).
   Its own log, with no physical DualSense attached to Sisyphus at all:
   ```
   Product: DualSense Wireless Controller
   Controller using HIDAPI driver, vid=0x054c, pid=0x0ce6
   ConfigSet - found config set file on-disk: .../configset_controller_ps5.vdf
   ```
4. **Steam re-emits it to the game** as `Microsoft X-Box 360 pad 0` (`28de:11ff`,
   Valve's Steam Input virtual pad), carrying the stuck chord with it. Both
   devices showed the identical four held codes — that is the propagation, not a
   coincidence.
5. A permanently-held chord means Steam Input never settles, so it re-adopts
   bindings every ~30 s (`adopting binding 101, 102, 103, …` in `controller.txt`)
   — **the flashing** — and the same layer synthesises keyboard/mouse from a pad
   it believes is active — **the lockups**.

### 🔑 seat9 protects niri, NOT Steam

This is the load-bearing correction to the section above. The rules park the pads
on `seat9` and strip `uaccess`, and that genuinely works for the compositor —
verified again here, niri held **no** FD on `event256`. But:

**Steam does not ask logind. It scans `/dev/input` and `/dev/hidraw*` directly.**

The nodes stay `crw-rw---- root:input` and `rock` is in `input`, so the open
succeeds. The existing warning in that section ("file bits alone would permit an
open… the protection is the seat assignment") is exactly right — it just only
holds for things that consult libseat/logind, and Steam is not one of them.

⚠️ **Permissions cannot separate the two Steams, so don't try.** Both run as
**uid 1000**: the container holds gid 174 (`input`) through its own supplementary
groups, and niri reads the *real* mouse through that same group (there is no
`user:rock` ACL on `/dev/input/event15`). Tightening mode/group breaks niri and
the container together; removing `rock` from `input` breaks niri.

### ⚠️ The niri.md latched-button *fix* does not work here

`Claude/niri.md` → "Pointer works but `Mod`+drag does nothing" has a release-
injection snippet that needs no root. **The probe half applies; the fix half does
not.** These pads are **uhid-backed**, so the HID driver owns the key state: the
write to the evdev node is accepted and changes nothing. Tried on `event256`
2026-10-03 — `EVIOCGKEY` read back the same four codes. (It *did* clear the
derived `event259`.) **A stuck virtual pad has to be destroyed, not released.**

### Fix — `wolf-stuck-pad-reaper` in `Modules/Gaming/wolf.nix`

Detects the harm directly: a `Wolf * virtual *` device that reports held buttons
via `EVIOCGKEY` **and** emits nothing for a full 60 s window. Both halves matter —
a real player holding buttons still produces a constant event stream, while the
orphaned pad is completely silent. On a hit it restarts `docker-wolf`, which ends
the session and takes the pads with it (verified: stopping the unit removed
`event256-258`, `hidraw16` and `js1-js3`, leaving only the real `js0`).

❌ **Do not re-propose counting `[ENET] Failed to send packet`.** Wolf spams it
when sending to a client that has gone, so it looks like the ideal orphan signal.
Measured over the real 15.6 h orphaned session: only **75 minutes contained any
failures at all** (median 3/min, p90 13) — and a *healthy* stream also hits 3-4 in
a minute. The spam is bursty, not sustained; no count-per-window threshold
separates them. This was built that way first and had to be rewritten.

Second, narrower guard, set in `Modules/Gaming/wolf.nix` because it only exists
for Wolf: `my.steam.extraEnv.SDL_GAMECONTROLLER_IGNORE_DEVICES = "0x054c/0x0ce6"`.
`Modules/Gaming/steam.nix` passes `my.steam.extraEnv` into the host Steam
package's FHS environment, so desktop Steam won't adopt a virtual DualSense even
while one is live. RPCS3 and other apps launched outside Steam never see it.
(It used to sit inside steam.nix's Millennium-only build. The value is unchanged.
It was verified present and auto-exported (`set -a`) in the built FHS profile,
next to the known-working `MILLENNIUM_RUNTIME_PATH`.) Because wolf.nix sets an
option that steam.nix declares, **wolf.nix requires steam.nix**. Every Wolf host
here is a Steam host, and a missing import fails eval loudly.
⚠️ **Not yet verified at runtime** that Steam's bundled SDL honours it for its own
HIDAPI enumeration as opposed to for games. To check: start a Wolf session, start
desktop Steam, confirm no new `vid=0x054c` line appears in
`~/.local/share/Steam/logs/controller.txt`.
⚠️ It is a VID/PID match, so a **genuine** DualSense plugged into Sisyphus is
ignored too. Accepted — the real pad lives on Eclipse and reaches games through
the stream.

### Diagnosing a repeat

```bash
# 1. is anything latched? (the only test that can see it)
#    full snippet: Claude/niri.md -> "Pointer works but Mod+drag does nothing"
#    run it across ALL /dev/input/event*, not just the pad you suspect
# 2. did desktop Steam adopt a pad that isn't physically there?
grep -aiE 'dualsense|vid=0x054c' ~/.local/share/Steam/logs/controller.txt | tail
# 3. is Steam Input thrashing bindings?
grep -ao 'adopting binding [0-9]*' ~/.local/share/Steam/logs/controller.txt | tail
# 4. what virtual pads exist, and does niri hold any of them?
grep -E '^N: Name=.*(Wolf|X-Box)' /proc/bus/input/devices
```

## 🔑 Launch options do NOT carry over from the desktop

**The library is shared; the per-user Steam config is not.** There are two
independent `localconfig.vdf` files, one per Steam instance, even though both run
the *same account* (`9518132`):

| | path |
|---|---|
| host desktop | `~/.local/share/Steam/userdata/9518132/config/localconfig.vdf` |
| Wolf container | `/etc/wolf/10376776459688695541/Steam/.steam/steam/userdata/9518132/config/localconfig.vdf` |

Measured 2026-09-30: the host held **6** `LaunchOptions` entries (`gamescope`,
`PROTON_LOG=1 %command%`, …) and Wolf's held **0**. Setting a launch option in
desktop Steam does nothing for a streamed session, and vice versa.

⚠️ **What makes this genuinely misleading: `Playtime` *is* identical in both**
(Steam cloud sync), so the two configs look like one Steam. Cloud sync covers
playtime and per-game state; it does **not** cover launch options.

Mounting the host library as a second library folder (below) only shares
`steamapps` — game files. `userdata/` is never part of a library folder.

**To set a launch option for streaming,** either use the Steam UI *inside the
stream*, or edit Wolf's `localconfig.vdf` directly — it is `rock`-owned and
world-writable, so no sudo. Same rule as `config.toml`: **Steam rewrites the file
on exit, so the container's Steam must not be running.** Check with
`pgrep -x steam` filtered on whether `/proc/<pid>/cgroup` contains `docker`; the
host's Steam appears in that list too (see below).

⚠️ This is imperative state under `/etc/wolf` and would be lost if the profile
directory is recreated.

### The Witcher 3 — skipping REDprelauncher

`"LaunchOptions" "%command% --launcher-skip"` on app **292030**. The flag is real:
`REDprelauncher.exe` contains `launcher-skip`, `launcher_skipped`,
`onLauncherSkipped` and `sendLauncherSkippedEvent`.

Nothing is lost by skipping it on this install — `launcher-configuration.json`
declares a **single** executable, `bin\x64_dx12\witcher3.exe`, with
`"fallback": "DirectX 12"` and edition `remasteredEdition`. There is no DX11 build
installed, so the launcher's only real choice is already made.

## Steam library sharing — two traps

**1. Steam's data root is `.steam/steam`, NOT `.steam/debian-installation`.**
The latter exists but holds only `.cef-enable-remote-debugging`. Confirm from the
running process: `-logdir=/home/retro/.steam/steam/logs`. Mounting into
`debian-installation` silently does nothing.

**2. `libraryfolders.vdf` lives *inside* the shared `steamapps`.** It records an
absolute path (`/home/rock/.local/share/Steam`). Inside the container that path
doesn't exist, and **Steam silently discards a library whose declared path is
missing** — presenting as "install" instead of "play". You cannot rewrite that
file; it's the host's, and desktop Steam reads it.

**Working setup:** mount the host Steam dir at the **identical path**, and add it
as a second library in the container's *own*
`.steam/steam/steamapps/libraryfolders.vdf`:

```toml
mounts = [ '/home/rock/.local/share/Steam:/home/rock/.local/share/Steam:rw',
           '/dev/input:/dev/input:rw' ]
```
Steam validates and rewrites the vdf on next start — it filled in `totalsize`
and all 24 apps itself, which is how you know it accepted the library.

⚠️ **806 GB library, ~285 GB free — it is shared, not duplicated. Only one Steam
may touch `steamapps` at a time** or `appmanifest_*.acf` can corrupt. Don't run
desktop Steam while streaming.
⚠️ When guarding against that in a script, `pgrep -x steam` **false-positives** —
the host PID namespace also sees Wolf's containerised Steam. Filter on whether
`/proc/<pid>/cgroup` contains `docker`.

## The sway config inside the Steam container

`launch-comp.sh` does an **unconditional** `cp /cfg/sway/config
$HOME/.config/sway/config` on every container start — edits there are wiped every
launch. Waybar's config uses `cp -u`, so *that* one persists.

Overrides go in **`~/.config/sway/custom-cfg`** (host:
`/etc/wolf/10376776459688695541/Steam/.config/sway/custom-cfg`), which is never
copied over. It's `include`d at **line 2**, i.e. *before* upstream's `bar` and
`for_window` lines, so a plain redefinition loses. **Use `exec_always`**, which
runs after the whole config parses:

```
exec_always swaymsg 'for_window [class="steam"] fullscreen enable'
```

Upstream ships `for_window [class="steam"] fullscreen disabled` (Big Picture
windowed, waybar visible above it) and `[class="steam_app_.*"] fullscreen
enabled` (games fullscreen). The override above gives fullscreen BPM with no bar.

⚠️ sway `class` criteria are **regex and unanchored**, so `"steam"` also matches
`steam_app_1332010`.

### ⚠️ Two traps that make the bar *look* fixed when it isn't

**1. Hiding the bar needs retrying.** waybar is launched by sway's
`swaybar_command`, so a single `exec_always swaymsg bar mode invisible` can fire
before waybar exists and silently do nothing. Loop it.

**2. A fullscreen window only *covers* the bar.** If the bar was never really
hidden, fullscreen Steam masks it — and the illusion survives right up until you
quit a game. `for_window` matches **only at window creation**, so when the game
exits and Big Picture becomes the top window again it does *not* re-apply, Steam
returns un-fullscreened, and the bar reappears. **Symptom to recognise: bar is
absent on first launch and back after quitting a game.**

Fix both by re-asserting on a loop, and gate the fullscreen one on no
`steam_app_` window existing so it never fights a running game:
```
exec_always sh -c 'while :; do swaymsg bar mode invisible; swaymsg bar bar-0 mode invisible; sleep 5; done >/dev/null 2>&1'
exec_always sh -c 'while :; do sleep 5; swaymsg -t get_tree | grep -q "steam_app_" || swaymsg "[class=\"steam\"] fullscreen enable"; done >/dev/null 2>&1'
```

Also appended by the script: `output * resolution ${GAMESCOPE_WIDTH}x${...}`,
which **defaults to 1920x1080** — Wolf overrides it with the client's request, so
check it says `3840x2160` if 4K is expected.

## ⭐ Moonlight straight into Steam — no Wolf UI picker (2026-10-01)

Goal: one Moonlight tile that goes directly into Steam Big Picture. Two undocumented
Wolf rules make this harder than it looks, and I got both wrong first.

### 🔑 Rule 1: `moonlight-profile-id` is the profile served to paired clients

`[[paired_clients]]` has **no profile field** — only `app_state_folder`,
`client_cert` and `[paired_clients.settings]`. The client is handed the profile whose
`id` is **`moonlight-profile-id`**, and Wolf UI exists to reach the others.

**Proof:** before any change, the client's app list was exactly that profile's
contents (`Test ball` + `Wolf UI`) and *not* the `user`/Caitlin profile's nine apps.

❌ **Deleting it does NOT promote the remaining profile to default.** Do that and the
client has no profile, so Wolf cannot build an app list — every poll is aborted:

```
WARN | HTTPS error during request at /applist error code: 125 - Operation canceled
```

once per Moonlight poll (~8 s), forever. The client's cached list then never updates,
so it keeps asking for the deleted app and gets
`[HTTP] Requested wrong app_id: not found` → `Bad Request (Error 302)` on the TV.

✅ **Do this instead:** keep `id = 'moonlight-profile-id'` and put the Steam app
*in it*. One app in that profile = one Moonlight tile = straight in.

### 🔑 Rule 2: a directly-launched app's home is NOT under `profile-data/`

**Symptom:** Steam streams fine but is **signed out**, and Big Picture is windowed with
the waybar visible — because `~/.config/sway/custom-cfg` is missing too. Both at once is
the giveaway: it is one cause, a wrong `$HOME`, not two problems.

The live home is keyed by the client's **`app_state_folder` + the app's `title`**:

```
/etc/wolf/10376776459688695541/Steam/            ← live. 3256 files touched in 2 h
/etc/wolf/profile-data/moonlight-profile-id/…    ← NOT mounted. 0 files touched
```

`profile-data/<profile-id>/<container-name>/` is where Steam lived when it was reached
**through Wolf UI**. Launch it directly from the client's own profile and Wolf uses the
client path instead, leaving a complete, signed-in Steam home stranded where nothing
reads it.

**The one check that settles it** — `bootstrap_log.txt` gains a
`Steam Client launched with:` line on *every* launch, so a stale mtime is conclusive:

```bash
stat -c %y /etc/wolf/10376776459688695541/Steam/.steam/steam/logs/bootstrap_log.txt
find -L /etc/wolf -mmin -120 -type f | wc -l     # then see WHICH tree the files are in
```

✅ **Fix — swap the directories.** Same filesystem and both already `1000:1000`, so these
are instant renames, not copies:

```bash
sudo systemctl stop docker-wolf
C=/etc/wolf/10376776459688695541
sudo mv "$C/Steam" "$C/Steam.signedout-$(date +%F)"            # keep, don't delete
sudo mv /etc/wolf/profile-data/moonlight-profile-id/WolfSteam "$C/Steam"
sudo chown 1000:1000 "$C/Steam"
sudo systemctl start docker-wolf
```

Verify `loginusers.vdf`, `userdata/9518132/config/localconfig.vdf` (holds
`--launcher-skip`) and `.config/sway/custom-cfg` are all present at the new path before
streaming. Script kept at `~/fix-steam-home.sh`.

⚠️ **Two fixes aimed at the wrong tree first** — a `ln -s user moonlight-profile-id`
symlink (Wolf does not follow it), then renaming `profile-data/user` →
`profile-data/moonlight-profile-id`. Neither could ever have worked, and
`bootstrap_log.txt` said so each time. **Check which tree is being written before
changing anything.**

### Ruled out — do not re-investigate

- **The profile's `icon_png_path`.** `https://cataas.com/...` measures **5.3 s** from
  Sisyphus and had logged `Timeout was reached`, and a profile icon *is* newly on the
  `/applist` path once that profile is the one served. Plausible, and wrong: removing
  it changed nothing. Left removed anyway since it is pure latency. The Steam app's
  own github.io icon measures 0.28 s.
- **Wolf's API socket** cannot be used to debug this unprivileged: `/run/wolf/wolf.sock`
  is `srwxr-xr-x`, and connecting to a unix socket needs **write** permission, so every
  `curl --unix-socket` returns empty with no error.

### Applying it safely

⚠️ Wolf **rewrites `config.toml` on exit**, so it must be stopped to edit — and an
`&&` chain is the wrong shape: a failing step left `docker-wolf` stopped for ~40
minutes, after which Moonlight simply reported `"Wolf" is now offline`. Use a script
with `trap restart_wolf EXIT` so Wolf always comes back.
⚠️ There is **no `python3` on PATH** on this host (and sudo resets PATH), so a bare
`python3` pre-flight check silently aborts such a script. Use an absolute store path
or skip the check.

### After changing the app list, the client must re-poll

`host_id`/`game_id` in the Kodi shortcut are **indices into Moonlight's own cache**.
Only the running Moonlight client rewrites that cache, and it only does so when
`/applist` succeeds — so fix Wolf first, open Moonlight once, *then* read the new
index:

```bash
grep -aE '^1\\apps\\[0-9]+\\(name|id)|^1\\apps\\size' "…/Moonlight.conf"
```

Going from `Test ball`+`Wolf UI` to Steam alone moved Steam to **index 1**, so the
Gaming tile became `game_id=1`. See the skinshortcuts section below for the rebuild.

## Config / module gotchas

| Thing | Note |
|---|---|
| `oci-containers.backend` | must be **`"docker"`** — NixOS defaults to podman; Wolf drives the *Docker* socket to spawn children |
| `XDG_RUNTIME_DIR` | **never override.** The image sets `/run/user/wolf` + a VOLUME; we bind-mount `/run/wolf` there. It holds **both `wolf.sock` and `pulse-socket`**, and Wolf maps container→host paths by reading its own mount list. Break it and games get no audio and no API |
| `/run/wolf` host path | must be exactly this — the default `config.toml` mounts `/var/run/wolf/wolf.sock` into Wolf-UI, and `/var/run` → `/run` |
| `devices` format | three-part, like mounts: `'/dev/uinput:/dev/uinput:rwm'`. A bare path throws `[TOML] Docker, invalid device definition` |
| `DeviceCgroupRules` | Wolf **overwrites** these at runtime with the hidraw + input majors. Upstream's shipped `"c 244:* rmw"` (244 = *nvme*) is dead weight |
| app home (live) | **`/etc/wolf/<app_state_folder>/<app TITLE>/`** — e.g. `/etc/wolf/10376776459688695541/Steam`. Keyed by the **client's numeric `app_state_folder` + the app's `title`**. This is where a directly-launched app actually lives. ⚠️ An earlier revision of this table said profile data was keyed by profile `id` "not the numeric client folder" — **that was backwards**, see below |
| `profile-data/` | `/etc/wolf/profile-data/<profile-id>/<container name>/` exists and holds the *old* Steam home from when Steam was reached **through Wolf UI**. For a direct launch it is **not mounted at all** |
| profile fields | `id`, `name`, `icon_png_path`, `pin`, `apps`. Editing `name`/icon works; **never change `id`** or the profile data is orphaned |
| editing `config.toml` | Wolf **rewrites it on exit** — stop Wolf before editing, or changes are clobbered |

⚠️ `/etc/wolf` is imperative state created by Docker — against the repo's
declarative principle. It was acceptable for the trial. Wolf is now the live host, so
converting it is outstanding work.
⚠️ `ghcr.io/games-on-whales/wolf:stable` is pulled at runtime, not pinned.

## Startup race that looks fatal but isn't

First session attempt can log, twice:
```
ERROR | Wayland endpoint /run/user/wolf/ exists but is not a socket (mode=40755)
ERROR | [STREAM_SESSION] Wayland socket  was not ready, aborting runner startup
```
Note the **double space** — the socket name is empty. Wolf allows the compositor
5 s; on first run it can take ~20 s. It **retries and succeeds**:
`Wayland display ready, listening on: wayland-1`. Don't debug this.

Also benign: `WARN smithay ... Unable to become drm master, assuming unprivileged
mode` — this is *good*, it's why Wolf coexists with a live niri session.

## Measured performance — 2026-09-28, Stray, 4K60 @ 60 Mbps

240 samples. Game rendered at **1080p** internally (upscaled to the 4K stream),
so GPU figures are *1080p render + 4K encode*.

| Metric | Avg | Max |
|---|---|---|
| Stream bitrate | **60.1 Mbps** | 63.4 |
| Eclipse CPU (decode) | **4.2 %** | 10.5 |
| Eclipse temp | 56.7 °C | 57.6 (`throttled=0x0`) |
| GPU busy | 57.8 % | 87.0 |
| GPU power | 60.8 W | 218 W |
| **Packet-loss events** | **0** | — |

The Pi decodes 4K60 at ~4 % CPU via `Hwaccel V4L2 HEVC stateless V4` with
**DMABuf on both ends**. Confirm the hardware path with `grep "Hwaccel V4L2"` in
the client log — the later `FFmpeg-based video decoder chosen` line is a wrapper
label and does **not** mean software decode.

⚠️ `Network dropped audio data` bursts cluster within seconds of `Waiting for IDR
frame` at **stream start** and do not recur in steady state. Don't read startup
turbulence as a link problem.

### Resolution: check what the GAME renders, not just the stream

The stream can be 4K while the game renders 1080p and gets upscaled — worst of
both, 4K cost for 1080p detail. Ground truth is the Proton log
(`PROTON_LOG=1` → `/etc/wolf/10376776459688695541/Steam/steam-<appid>.log`):

```
info:  Setting display mode: 1920x1080@60
info:  Presenter: Actual swapchain properties:
info:    Buffer size:     1920x1080
```

**Set for next test (2026-09-28):** 3840x2160 @ 60, **bitrate 100000**,
`showperfoverlay=true`. Rationale: ~75 Mbps of video after Moonlight's ~25 % FEC
reserve; 60 Mbps ran with zero loss so there's headroom, and 100 Mbps is ~half
the repeater's 196 Mbps 5 GHz link rate.
⚠️ **Open question:** the 4K choppiness may be GPU-bound, not bitrate-bound — the
GPU already peaked at 87 % while rendering only 1080p. The perf overlay settles
it: 60 fps but soft = bitrate; sub-60 fps = GPU, so lower in-game settings.

## ⭐ GPU clock governor — the 4K choppiness trap (2026-09-29)

**Symptom:** 4K60 feels choppy. **Wrong conclusion:** "the link can't carry it."

The RX 9060 XT sat at DPM clock **step 1 of 3 (1668 MHz)** drawing 83 W of a
182 W cap at 50 °C under the default `auto` governor — nowhere near any limit,
it simply never ramped. Render+encode is bursty enough not to trip the
heuristic. Forcing `high` fixed it:

| | `auto` | `high` |
|---|---|---|
| clock | 999–1820 MHz | 2519–2779 MHz |
| power | 40–75 W | 88–154 W |
| **stream TX** | **76–82 Mbps** | **95–117 Mbps** |
| packet loss | 0 | 0 |

🔑 **The fingerprint is stream TX falling BELOW the requested bitrate** — that
means the encoder is starved of frames, not that the network is struggling.
Packet loss was **zero throughout** the choppy period, so more bandwidth would
have achieved nothing. **Check `pp_dpm_sclk` before touching bitrate.**

Automated by `systemd.services.wolf-gpu-perf` in `Modules/Gaming/wolf.nix`: sets `high`
while a `Wolf<App>_<uuid>` container runs, reverts to `auto` otherwise (the menu
container `Wolf-UI_<uuid>` has a hyphen and deliberately doesn't match). Verified
in the journal: `GPU perf level: high -> auto`. Scoped to sessions because
`high` also pins max clocks at **idle**, wasting power and spinning fans.

⚠️ It resolves the card by finding whoever owns `renderD128` — card0/card1
enumeration is **not stable across boots**, so never hardcode it.

**Thermals are a non-issue** (measured under 4K load): edge 63 °C, junction
70 °C, memory 80 °C, 154 W of 182 W, fan ~700 RPM. Junction throttles at
110–115 °C, and review samples of this card run 78–80 °C — ours is *cooler*.
Idle after a session: 45/48/64 °C, 17 W, fan stopped.

## Encoder tuned for quality (2026-09-29, untested)

Wolf's VA HEVC default is speed-biased: `target-usage=6` (scale is **1 = best
quality, 7 = fastest**) and `min-qp=20`. Changed to **`target-usage=4`** and
**`min-qp=16`** in both `va` blocks (`vah265enc` and `vah265lpenc` — same
`plugin_name = 'va'`, Wolf picks whichever element exists).

- `target-usage` = how hard the encoder searches for inter-frame matches. A poor
  match costs many bits to describe, leaving fewer for detail inside a fixed CBR
  budget. Searching harder buys quality **at the same bitrate**.
- `min-qp` is a quality *floor*: at 20 the encoder can't go finer even when bits
  are spare, and under CBR it pads instead — wasting paid-for bandwidth.
  Lowering it reallocates bits; it does **not** raise total bitrate or cost
  encode time.

⚠️ **Risk is confined to `target-usage`** — more search = more encode latency. If
choppiness returns or GPU busy pins in the 90s, step back to `5`.

## Pairing

Wolf logs a URL when a client requests pairing:
`INFO | Insert pin at http://<host>:47989/pin/#<secret>`. Submit with:
```bash
curl -X POST "http://192.168.0.13:47989/pin/" -H "Content-Type: application/json" \
     -d '{"pin":"1234","secret":"<secret>"}'
```
Returns `OK`; a bad secret returns 400. Wolf reports its hostname as **`Wolf`**,
not `Sisyphus` — remove the old Moonlight host entry first, since the certs are
new. Pairing is **by client certificate**, not IP, so pairing over LAN doesn't
prevent adding a tailnet host entry later.

## Eclipse: Kodi "Gaming" tile launches Steam directly

The Bingie home menu is driven by **skinshortcuts**. It shipped as
`RunPlugin(plugin://plugin.program.moonlight-qt/?mode=launch)` — `mode=launch` with
**no** `host_id`/`game_id` hits the addon's else-branch (`addon.py:188`) and just
opens Moonlight's GUI. Adding both params streams an app directly:

```xml
<action>RunPlugin(plugin://plugin.program.moonlight-qt/?mode=launch&amp;host_id=1&amp;game_id=1)</action>
```

### 🔑 There are TWO `mainmenu.DATA.xml` files and only one is built from

**This is why the Gaming tab silently did nothing until 2026-10-01.** The params had
been added — to the wrong file.

| path | role |
|---|---|
| `/storage/.kodi/addons/skin.bingie/shortcuts/mainmenu.DATA.xml` | ✅ **what skinshortcuts actually compiles from — edit THIS** |
| `/storage/.kodi/userdata/addon_data/script.skinshortcuts/mainmenu.DATA.xml` | ❌ was edited for 3 weeks and ignored |

An earlier revision of this doc named only the `userdata` path. That was wrong.

⚠️ The skin-side file is inside the **addon**, so a skin update overwrites it.
Backup kept as `mainmenu.DATA.xml.bak-paramless`.

**Forcing a rebuild** — editing alone is not enough, the built menu is cached:

```bash
rm -f /storage/.kodi/userdata/addon_data/script.skinshortcuts/skin.bingie.hash
systemctl restart kodi        # wait ~40s for the rebuild
```

**Always verify against the compiled output**, never the source file — that is the
whole trap:

```bash
grep -ao "mode=launch[^<]*" /storage/.kodi/addons/skin.bingie/1080i/script-skinshortcuts-includes.xml
# want: mode=launch&amp;host_id=1&amp;game_id=1)      NOT bare mode=launch)
```

A stale build is obvious from mtimes: the includes file sat at **Sep 12** while the
source had been edited **Sep 29**.

⚠️ **`host_id`/`game_id` are INDICES into Moonlight's cached config**, not stable
ids. Verify by running the addon's own parser over `Moonlight.conf` —
`hosts["1"]["apps"]["1"]["name"]` must resolve to the app you want (now `Steam`). If Wolf's app
list changes, the index shifts and the Gaming tab launches the wrong app.

Two things that are *not* bugs, having been chased: the URL args and the dict keys
are **both strings** (`configparser` + splitting on `\`), so there is no type
mismatch; and `moonlight.py:62`'s `f'"{hostname}"'` quoting is correct because
line 100 runs it through `os.system()`, a shell string.

> ⚠️ **Superseded 2026-10-01.** An earlier revision said here that *"Moonlight can
> therefore never list Steam"* and that the chain had to be
> Moonlight → Wolf UI → Caitlin → Steam. **That is no longer true and was never a hard
> limit** — it followed from the default profile containing only `Wolf UI` + `Test ball`.
> Put Steam in the `moonlight-profile-id` profile and Moonlight lists it directly; the
> picker is gone entirely. See "Moonlight straight into Steam" above. `game_id` moved
> from `2` (Wolf UI) to `1` (Steam) as a result.

A `favourites.xml` entry with the same URL also exists, for pinning elsewhere.
⚠️ skinshortcuts caches the built menu — **restart Kodi** after editing.

## LAN vs tailnet — use LAN

Both boxes are on the same LAN and `tailscale ping eclipse` resolves **direct**
(`via 192.168.0.182:41641`), so the tailnet routes over the same wire while
adding WireGuard CPU on the Pi and a **1280 MTU vs 1500** (~17 % more packets).
mDNS auto-discovery is LAN-only too. Use `192.168.0.13`.
⚠️ Both ends are on **DHCP** and Eclipse's lease has drifted twice
(`.184` → `.183` → `.182`). Fix with router reservations, not by tunnelling.

## Two findings about non-Steam shortcuts (2026-10-03)

Found while scoping emulator streaming. That project was dropped, but both of
these are general Wolf facts and cost nothing to keep.

### 🔑 `shortcuts.vdf` is per-Steam-instance, like `localconfig.vdf`

Non-Steam shortcuts do **not** carry over between the desktop and the stream.
`shortcuts.vdf` lives in `userdata/<id>/config/` — the same per-instance
directory as the `LaunchOptions` finding above — and is **not** cloud-synced.
Measured 2026-10-03:

| | `shortcuts.vdf` |
|---|---|
| host desktop | present (336 B) |
| Wolf container | **absent entirely** |

So a non-Steam shortcut has to be added from **inside the stream**. Adding it in
desktop Steam does nothing for the TV, and vice versa. Same trap, same cause,
one more file to add to the list.

### 🔑 The `custom-cfg` fullscreen loop fights any NON-SDL window

The reassert loop's gate was `grep -q "steam_app_"`. That class comes from
Steam exporting `SDL_VIDEO_X11_WMCLASS` — so it only appears on **SDL-based**
games. Anything else launched as a non-Steam shortcut keeps its own WM_CLASS,
never matches, and the loop therefore concludes "no game is running" and
re-fullscreens **Steam on top of it, every 5 seconds**.

Verified against Ryujinx, whose Avalonia UI ignores that variable entirely and
keeps `StartupWMClass=Ryujinx`. The gate is now
`grep -qe steam_app_ -e Ryujinx`, with a matching
`for_window [class="Ryujinx"] fullscreen enable`.

⚠️ **Before blaming the stream for a window that keeps losing focus, check the
app's WM_CLASS.** Any non-SDL shortcut — an emulator, a launcher, a browser —
will hit this, and the symptom (Big Picture popping back in front on a timer)
points nowhere near the real cause. Add its class to the gate.

## Session control — `wolf-bridge` (added 2026-10-03)

The Eclipse panel lists Wolf's sessions and can end one (two taps) — on the admin
Glance AND on MarsBar, which share the panel (`Resources/Glance/eclipse.js`) — the
fix for the "Wolf never reaps the session" problem above when it happens outside
the stuck-pad case the reaper catches. Every end is logged in the panel's shared
activity list, whichever dashboard did it.

- **Service:** `wolf-bridge` on Sisyphus (`Modules/Gaming/wolf.nix`, script
  `Resources/Wolf-Bridge/wolf-bridge.py`), port **9560**.
- **API:** `GET /sessions` → `{"wolf":"up"|"down","sessions":[{id, app, client,
  client_ip, started, video, audio_channels}]}`; `POST /sessions/<id>/stop` with
  header `X-Dash: 1`; `GET /health`.
- **Wolf API used** (games-on-whales/wolf `stable`,
  `src/moonlight-server/api/`): `GET /api/v1/sessions`,
  `POST /api/v1/sessions/stop {"session_id"}`, `GET /api/v1/apps` for titles.
  The session's `client_id` field **is the session id**. The list also carries
  the stream's `aes_key`/`aes_iv` — the bridge never passes those on.
- **No start time in Wolf's API** — `started` is when the bridge first saw the
  session (kept in `/run/wolf-bridge`, survives a bridge restart, not a reboot).
- **Who can call it:** not in the firewall's open ports, so the LAN can't;
  tailscale0 is trusted, so systemd `IPAddressAllow` + the bridge's own
  allowlist narrow it to Asgard (`self.lib.tailnet.asgard`) and localhost.
  Browsers never call it directly — Asgard's eclipse-control proxies it.
- **Check by hand on Sisyphus:** `curl -s localhost:9560/sessions | jq`.

## ⭐ Lag spikes on Eclipse = 100 Mbps over its own Wi-Fi (2026-10-09)

**Reported as:** "crazy lag spikes" playing Cult of the Lamb, suspected Proton.
Full measured write-up: **`Resources/Eclipse-Box/evidence/cotl-lag-2026-10-09.md`**.

Eclipse's Moonlight asks for **4K60 at `bitrate=100000`** and Wolf delivers it — 101 Mbps
measured on `enp9s0`. One session logged **16,283 lost frames (7.1 %)** and **437 freezes
during gameplay** — a visible stutter every ~7 s.

### ⭐ First: find out which interface Eclipse is actually using

**Eclipse has both NICs up on the same subnet, and `wlan0` wins the route.**

| iface | address | path | rx during the stream |
|---|---|---|---|
| `eth0` | 192.168.0.182 | wired → RP-BE58 extender | **0 Mbps** |
| `wlan0` | 192.168.0.183 | direct to "Kandy Cane", 5 GHz ch36, **−67 dBm** | **101 Mbps** |

connman carries **both** `Wired` and `Kandy Cane` with `AutoConnect=true`. On 2026-10-09 the
Wi-Fi had been associated 5 h on a box up 4 days — it joined mid-afternoon and silently took
the default route. `eth0` stayed healthy and unused.

```bash
ssh root@eclipse 'ip route get 192.168.0.13; ip -o addr show | grep -v inet6'
# and the decisive one — which interface is actually moving bytes:
ssh root@eclipse 'for i in eth0 wlan0; do echo -n "$i "; cat /sys/class/net/$i/statistics/rx_bytes; done'
```

**So every extender tuning is bypassed, and every dashboard reading measures the radio.**

### The mechanism, and the bit that is easy to miss

At 100 Mbps a 4K frame is ~294 packets across **3 FEC blocks**. Moonlight's FEC block index is
8-bit, so **a block over 255 packets gets no FEC at all** — Wolf says
`Size of frame too large, N packets is bigger than the max (255); skipping FEC`
(27,628 times). **83 % of the frames that failed had zero parity**, so a single lost packet was
fatal; the decoder then discards every dependent frame and sits in `Waiting for IDR frame` for
up to 46 frames ≈ **0.77 s of frozen picture**.

101 Mbps of *bursty* UDP on a −67 dBm link is ~60 % airtime before retries. Bursts overrun the
queues. So it is two faults compounding: the link sheds packets at the peaks, *and* the frames
that matter most are shipped unprotected.

### ✅ Settled 2026-10-09: eth0 (the extender) is the right path — measured idle

| path | throughput | ping (idle, 1400 B) |
|---|---|---|
| `eth0` → RP-BE58 extender | **376 Mbps** | **2.17 / 2.99 / 7.03 ms**, mdev 0.96 |
| `wlan0` → router direct, −66 dBm | 158 Mbps | 5.79 / 14.3 ms, mdev 2.65 |

**2.4× faster and lower latency.** Fixed by turning the Wi-Fi off for good:

```bash
connmanctl config wifi_88a29ed653de_4b616e64792043616e65_managed_psk --autoconnect off
connmanctl disconnect wifi_88a29ed653de_4b616e64792043616e65_managed_psk
# run detached via systemd-run — it kills its own transport
```
`AutoConnect=false` persists in `/storage/.cache/connman/<svc>/settings`, so it survives a reboot.
Tailscale re-homed onto eth0 by itself.

### ⚠️ Two traps that gave the wrong answer first time

1. **Never compare two wireless paths while one carries a stream.** eth0 first measured
   8.92 avg / 35.7 max — *because wlan0 was saturated beside it in the same airspace*. Idle, the
   same interface measures **2.99 / 7.03**.
2. ⭐ **Latency does not predict throughput, and hop count does not either.** wlan0 pinged better
   and moved less than half the data; "eth0 adds a hop so it's worse" was wrong, because the extra
   hop is on far better radios. **Measure throughput — never infer it.**
3. ⚠️ And a clean ping never clears a path: 5.79 ms avg with 0 % ICMP loss, while 7.1 % of frames
   died. Small probes sail through; loss only hits the 60 Hz bursts.

### Bitrate: now second-order

At 364 Mbps a 101 Mbps stream is ~28 % utilisation (was ~60 % airtime on wlan0). The 255-packet
FEC ceiling is still crossed at `bitrate=100000`, so what loss remains is unrecoverable — but
there should be far less of it. **Play at 100000 first; if spikes persist, drop to 40000-50000.**
⚠️ Set it from Moonlight's settings screen on the TV, or with Moonlight stopped — `Moonlight.conf`
is Qt `QSettings`, rewritten on exit.

### Don't re-diagnose these — all measured clean

- **Proton Experimental 11.0-100** ran the game at a steady 59.6 fps throughout.
- **GPU 54-74 %, 74 W.** Genuinely GPU-bound on this box looks like 86-100 % and
  **172 W of a 182 W cap** (the Witcher 3 4K test). Not close.
- **The Pi is fine** — HEVC **V4L2 stateless hardware** decode, `throttled=0x0`,
  59.3 °C, load 1.36.
