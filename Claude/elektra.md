# Elektra — her machine

`Hosts/Elektra/system.nix`, flake attr **`kitkat-Elektra`**, login `kitkat`
("Kit Kat" — she is Kit-Kat; the machine is Elektra), tailnet node `elektra`. Runs
**Hyprland** (`Modules/Desktop/hyprland.nix` — she is its only host now that Odysseus
is retired) with noctalia and skwd v2, on her own NVIDIA hardware.

**The name has history.** "Elektra" was first a KDE boot profile on *Sisyphus's own
disk* (all three local profiles shared one root UUID, one ESP and one swap, selected
from the GRUB "System Select" submenu). This box replaced it as **Kit-Kat**, and on
2026-10-09 the machine got the name **Elektra** back — her user stayed `kitkat`. Older
notes elsewhere that say "Elektra" and KDE mean that first one.

### The 2026-10-09 rename, Kit-Kat → Elektra

- **Brave keeps her profile.** Its folder is named after the host
  (`Brave-Browser-<name>`), so `my.brave.profileName = "Kit-Kat"` keeps it pointing at
  the existing one — bookmarks, logins, extensions stay put. `brave.nix` also clears a
  profile lock left under the *old* hostname (it would read as "in use by another
  computer"), and only when Brave isn't running.
- **The first push goes to the old tailnet name**, because `elektra` doesn't resolve
  until the rename is live: `system-rebuild kitkat Elektra --target kit-kat` (from
  Sisyphus, after Sisyphus has the new `system-rebuild`). From then on, plain
  `system-rebuild kitkat Elektra`.
- **Tailscale renames the node itself** from the new OS hostname — unless the machine
  name was ever edited by hand in the admin console, in which case set it back to
  auto-generate there (Machines → kit-kat → Edit machine name). Her MarsBar grants are
  by *user*, not machine name, so they don't change.
- **Sisyphus's ssh** will ask once to trust `elektra` (same host key, new name).
- **Reinstalls**: `apollo-deploy` reads her pre-generated host key from
  `~/.local/share/apollo/<Host>` — on Sisyphus, `mv ~/.local/share/apollo/Elektra
  ~/.local/share/apollo/Elektra` before the next install.
- Not renamed: her user (`kitkat`), her sops file (`Secrets/kit-kat.yaml`, module
  `sops-kitkat`) — those are hers, not the machine's.

## Her Mod+B cheatsheet (2026-10-09)

Same panel as rock's (noctalia's `kenn/keybind-cheatsheet`), and now the same look: every
bind titled and grouped into the same six categories as his niri one — Applications,
Window Management, Workspace - Navigation, Workspace - Movement, Screenshots, Media.

- **One list, two readers.** `keybinds` at the top of `Modules/Desktop/hyprland.nix`
  holds every Hyprland bind with a `title` and `category` (`type` = `bindm` / `bindel` /
  `bindl` where it isn't a plain `bind`). It is rendered into `extraConfig` as
  `# N. Category` headings and `bind = … #"Title"` lines: Hyprland drops both as
  comments (hyprlang cuts a line at an unescaped `#`; a literal `#` in a command is
  written `##`, which the renderer does for you), and the plugin reads exactly that
  format for Hyprland. `settings.bind` can't carry comments, so **add or change a bind in
  `keybinds`, never in `settings.bind`** — or it works but shows untitled on Mod+B.
- The screenshot binds moved there from `Modules/Desktop/screenshot.nix` (which keeps the
  grim/slurp/wl-clipboard/jq packages), so they're listed too.
- Workspace 1–5 render as one "Workspace N" row — the plugin folds number runs itself.
- `home.activation.hyprCheatsheet` deletes the plugin's `bindings-cache.json`:
  `hyprland.conf` is a store symlink (mtime 1970), so the plugin can't tell it changed.
- Checked 2026-10-09: the rendered binds are the same 47 as before (same keys, same
  actions), Hyprland 0.55.4's `--verify-config` says `config ok`, and the plugin's own
  parser (`parseHyprContent`, run under luau) reads all 47 with their titles and categories.

## Deploy / rebuild

```bash
apollo-deploy --vm-test kitkat-Elektra   # prove the disk layout first
apollo-deploy kitkat-Elektra             # first install — ERASES the disk
system-rebuild kitkat Elektra            # every rebuild after that
```

`system-rebuild` is on her machine too (`deploy-tools` with
`my.deploy-tools.admin = false`), and it knows where it is: run on Sisyphus it
pushes over the tailnet; run on Elektra — the command above, or Rebuild in the
menu — it rebuilds Elektra in place. With no `~/Dots` there it builds
`github:JimmyTheSquirrel/Dots` (main), so push to main first; *Utilities → Get the
repo* clones one if you want to edit on her machine.

See `Claude/deploy.md` for the Apollo USB side.

### She joined the tailnet by hand on 2026-10-04 — she was never on it before

`Modules/Core/tailscale.nix` only runs `tailscaled`; it sets **no `authKeyFile`**, so
joining is a one-time manual `tailscale up` on every host in this repo. Hers had never
been done, so a push had nothing to reach for her machine's whole existence and the only
config she ever received came from a **local clone rebuilt on her own machine**. That is
the root of every "her machine has drifted" symptom, including the Bluetooth fault below.
Her node is `elektra` (`kit-kat` until the 2026-10-09 rename; the address stays) / `100.122.12.125`.

- An absent node and an offline node look different: `tailscale status` lists an offline
  peer as `offline, last seen …`. **Missing from the list entirely means it is not in the
  tailnet at all** — never joined, or deleted.
- ⚠️ **Never `tailscale up --ssh` here.** She runs real `openssh`, and tailscaled would
  seize port 22 — see `Claude/deploy.md`.
- Her LAN address is `192.168.0.147`, but **port 22 was closed from the LAN** while
  tailscale worked fine. Don't conclude "the machine is off" from a refused SSH alone.
- She has **`wheelNeedsPassword = true`** and no passwordless sudo, so a push cannot be
  activated unattended from Sisyphus. Build and `nix copy` need no sudo (she is in
  `nix.settings.trusted-users`); only the final activation prompts.
- ⚠️ **Until `services.tailscale.authKeyFile` is wired she will drift again.** The option
  exists and her `sops-kitkat` module is ready; it needs `tailscale-auth-key` adding to
  `Secrets/kit-kat.yaml`. A node-join key is not the admin key that file is deliberately
  kept away from (see "Her password").
- `tailscale-api-key` in `Secrets/secrets.yaml` is **expired** — `401 API token invalid` —
  so the admin API is not available as a cross-check. Tailscale API keys expire after 90
  days, so a stored one always rots.

## Before the first install

1. **Confirm `installDisk`** in `Hosts/Elektra/_disko.nix`. It is `/dev/nvme0n1`
   by default and it is the one value that must be right — everything on that
   device is destroyed. Check from the booted stick: `apollo-connect`, then
   `lsblk -o NAME,SIZE,MODEL`.
2. ~~Pre-generate her ssh host key~~ ✅ **DONE 2026-10-02.** The key lives at
   `~/.local/share/apollo/Elektra/etc/ssh/ssh_host_ed25519_key` (outside the repo —
   this repo is public), its age identity
   `age185mqahaq2pac7szxvzkmlg5mdv4lcjgvtjkwu2ly24cc3mva3pssh4yuw2` is in `.sops.yaml`
   as `&kitkat`, and `Secrets/kit-kat.yaml` has been re-encrypted to include it.
   `apollo-deploy` now finds `~/.local/share/apollo/<Host>/` automatically and plants
   it — no env var to remember, and it refuses to proceed silently if it is missing.
3. ✅ `Hosts/Elektra/facter.json` has been generated and committed. Without it the
   host still evaluates (and warns), but **must not be switched onto real hardware**
   — there is no microcode, no detected kernel modules and no firmware without it.

## Her password

From `Secrets/kit-kat.yaml` → `user-password-hash` →
`users.users.kitkat.hashedPasswordFile`. **Not** from `Secrets/secrets.yaml`.

That separation is deliberate: sops encrypts a whole file to every recipient, so
adding her machine to `secrets.yaml` would hand it `mullvad-wg-private-key`,
`cloudflare-tunnel`, `eclipse-ssh-key`, `anthropic-api-key` and
`tailscale-api-key` — an **admin** key that can rewrite tailnet ACLs and mint auth
keys. Her file holds one secret and nothing else.

With `users.mutableUsers` at its default (`true`), the hash is applied only when
the account is **created** — it is what gives a fresh install a working login.
After that `passwd` works and survives rebuilds, and editing the secret changes
nothing on an existing machine.

`rock` works the same way since 2026-10-03: the `sops` module sets his
`hashedPasswordFile` from `Secrets/secrets.yaml`'s `user-password-hash`, so a fresh
Sisyphus or Asgard gets his password, and the existing machines are untouched.

## Her look

| Piece | Module | Source |
|---|---|---|
| Greeter | `Modules/Boot/sddm.nix`, `my.sddm.theme = "women-umbrella"` | qylock `women-umbrella` (Totoro) |
| Bootloader | `Modules/Boot/grub-celeste.nix` | CelesteGRUB 1080p |

- **The greeter is a theme choice on the shared SDDM module.** It used to be its own
  `sddm-umbrella.nix` beside rock's `sddm-nier.nix`; both called qylock's
  `mkSddmThemes {}` (all ~40 themes, 526 MB) and could collide if imported
  together. Since 2026-10-03 one `Modules/Boot/sddm.nix` copies just the chosen
  theme directory (3.3 MB for hers), and the enum makes two greeters impossible.
- Unlike the NieR theme, hers needs **no font patching** — upstream ships
  `font/Itim-Regular.ttf` inside the theme directory, which is exactly where its
  `FontLoader` looks. The FOT-Rodin step in `sddm.nix` runs for `nier-automata` only.
- **`grub-celeste` is a separate module, not an option on `Modules/Boot/grub.nix`:**
  that one is Sisyphus's multi-profile loader and hardcodes Sisyphus's
  `rootFsUuid` plus a System Select submenu for profiles that do not exist on her disk.
- `useOSProber = false`: her only disk is disko's, so the one thing os-prober could
  find is the Apollo stick (or any drive) left plugged in during a rebuild — a boot
  entry that dangles once it is removed.
- The theme is pinned to a **commit**, not a branch: upstream is a handful of release
  tarballs with no tags, so `main` moving would silently change her boot screen.
- CelesteGRUB ships **one tarball per resolution** and is not scalable. The 1080p
  build matches her two 1920x1080 panels (read off the machine over SSH). On a
  different resolution the layout is mispositioned, not broken — swap the filename
  and hash in the module. `gfxmodeEfi` is pinned for the same reason: left to EFI's
  choice GRUB often picks 1024x768 and the background is cropped.

## NVIDIA

`Modules/Core/nvidia.nix`, imported only here. Every other machine is AMD:

- `services.xserver.videoDrivers = [ "amdgpu" ]` is set by Sisyphus's own
  `Hosts/Sisyphus/_hardware.nix` (it used to be in both compositor modules), so
  nothing shared hardcodes it any more; nvidia.nix's `lib.mkForce [ "nvidia" ]`
  is now just belt-and-braces.
- `Modules/Boot/plymouth.nix` defaults its initrd GPU module to `amdgpu` → the host sets
  `my.plymouth.initrdGpuModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ]`.

`hardware.nvidia.modesetting.enable = true` is **required** — Hyprland renders
through GBM. It is also what adds `nvidia-drm.modeset=1`, so that param is not
repeated in `boot.kernelParams`.

`hardware.nvidia.open` is not optional in the code sense: on driver >= 560 the
option defaults to `null` and the nvidia module *asserts* that you have chosen. Her
RTX 3070 is Ampere (Turing or later), where upstream recommends the open modules,
so it is `true`.

If Hyprland black-screens from a TTY, in order of likelihood:
1. plymouth's early KMS — drop `plymouth` from her imports to rule it out.
2. the GBM/GLX env vars listed in the comment at the bottom of `Modules/Core/nvidia.nix`.

The Apollo stick is the recovery path for all of these. Keep it to hand.

## Bluetooth headphones — ✅ fixed 2026-10-04

Her **Razer Barracuda X (BT)** (`44:5E:CD:64:04:07`) could not connect at all. Nothing was
wrong with the headset or bluez: it was paired, bonded, **trusted**, advertised
`Audio Sink`/`Headset`/`Handsfree`, and `bluetoothd` was active, unblocked in `rfkill`,
controller `Powered: yes`.

**Cause: her stale local build still carried `10-disable-bluez.conf`**, removed from
`Modules/Core/audio.nix` on 2026-10-03. She had never been on the tailnet (above), so she
had never received the removal. Full mechanism and the `bluetoothctl show` fingerprint are
in **`Claude/misc.md` → Audio** — read that before diagnosing any Bluetooth-audio
complaint on any host.

**Fix: a plain rebuild from `main`.** No repo change was needed. The switch diff showed
`[R.] 10-disable-bluez.conf` removed, and her controller then gained all four audio UUIDs,
matching Sisyphus. Confirmed still correct across a second switch.

- **The repo's own comment described the wrong symptom** and has been corrected. A
  documented trap is a hypothesis — confirm the mechanism, don't pattern-match the prose.
- Her nixpkgs rev was **identical** (`2f5a153`), so this was config-only: cached build,
  8.5 s `nix copy`. Check the rev before assuming a long-drifted machine is an expensive
  rebuild.
- Expect a switch from a stale clone to also snap her noctalia bar back to
  `my.noctalia.lockedSettingsExtra`. That is the force-write working, not new breakage.

## "Her graphics card is taking off" — ✅ fixed 2026-10-04

Reported as the GPU screaming under **PEAK**. The card was always **healthy**; the game has
no working frame limiter.

| | Before | After |
|---|---|---|
| Power | 232–260 W / 270 W | **56–67 W** |
| Temp | 79–81 °C | **45–48 °C** |
| Fan | 89–100 % | **57 %** |
| GPU util | 60–100 % | **18–41 %** |
| `sw_power_cap` | **Active** | **NotActive** |

**~75 % less power, 34 °C cooler, audibly quiet.** The 18–41 % utilisation is the point:
PEAK is trivial for a 3070. It only looked demanding because nothing capped it, so it
rendered ~500 fps into two 60 Hz panels and burned ~183 W on invisible frames.
**Counterintuitive rule: the lighter the game, the harder an uncapped GPU works.** High
utilisation means "nothing is holding it back", never "this card is outmatched".

- ⭐ **Search the game's own community FIRST.** PEAK has multiple dedicated Steam threads on
  this. Its in-game vsync and FPS-cap options are documented as having **no effect** (hence
  zero vsync keys in its Proton prefix — they never get written), its default max framerate
  is reported ~500, Windows users report identical fans, and the devs acknowledged it.
  Doing this first would have skipped a wrong diagnosis entirely. Secondary in-game lever
  players rate highest: **Render Scale**.
- **Her 270 W cap is the card's FACTORY DEFAULT**, not a raised setting: `nvidia-smi -q -d
  POWER` gives `Default` = `Max` = 270.00 W (`Min` 100.00 W). `pci.sub_device_id 0x404D1458`
  → subsystem vendor **`1458` = Gigabyte**, whose higher-tier 3070s ship at 270 W against
  the Founders Edition's 220 W. **Reference TGP is the wrong baseline for an AIB card.**
- **Only `sw_power_cap` was ever active** — every thermal reason read `Not Active`, at 80 °C
  against a **95 °C slowdown / 93 °C max / 98 °C shutdown**. Power stayed pinned near 240 W
  even when utilisation fell to 60 %, so falling utilisation did not mean the load easing.
- ⚠️ **It is a NATIVE Vulkan app, and the environment lies about that.** Steam sets
  `DXVK_STATE_CACHE_PATH` and `DXVK_ASYNC` for **every** Proton game regardless of renderer,
  so their presence proves nothing — `DXVK_FRAME_RATE=60` was tried on that basis and did
  nothing. Check the shader caches instead: **227 M in `fozpipelinesv6/`** (Vulkan pipeline
  caches) with an **empty `DXVK_state_cache/`**. Steam's own command line settles it:
  `PEAK.exe -force-vulkan`.
- **No driver setting can fix this on NVIDIA.** In Vulkan the application owns the present
  mode, so MAILBOX/IMMEDIATE is throttled by nothing outside the process.
  `__GL_SYNC_TO_VBLANK`/`vblank_mode` are OpenGL-only, and `allow_tearing = false` in
  `hyprland.nix` does not help — the compositor shows 60 while the GPU renders hundreds.
  ⭐ **Mesa honours `MESA_VK_WSI_PRESENT_MODE=fifo` to override an app's present mode; the
  NVIDIA proprietary driver has NO equivalent.** That asymmetry, plus rock's **182 W** AMD
  power ceiling against her **270 W**, is the whole reason the same game behaves on his
  machine and screams on hers. Nothing is misconfigured on hers.
- **Fix: MangoHud's `fps_limit`, because it is a Vulkan *layer*** — it caps native Vulkan,
  DXVK and vkd3d alike. Wired in `Hosts/Elektra/system.nix` as `programs.mangohud` with
  `enableSessionWide = true` (sets `MANGOHUD=1` so the implicit layer loads) and
  `no_display = true`. It reaches the game because `mangohud` is in
  `programs.steam.extraPackages` (`Modules/Gaming/steam.nix`), putting the layer **inside
  Steam's pressure-vessel container** — which is also why `mangohud` is not on her PATH.
  ⚠️ Needs a **re-login** and a game relaunch; a switch cannot change a running session.
- ⚠️ **Verify MangoHud on the RENDER process, not the wrappers.** `grep -c mangohud
  /proc/<pid>/maps` is the test — a Proton game is a tree of `srt-bwrap` / `pv-adverb` /
  `proton` / `steam.exe` processes that legitimately have zero mappings, and reading one of
  those wrongly looks like the layer failed to load. The renderer showed **6** mappings.
- ⚠️ **Sample while the complaint is actually happening.** The first reading was taken
  between Steam's shader pre-caching finishing and the game loading: fan 0 %, 44 °C, 0 %
  util, 29 W, beside a dozen `fossilize_replay` processes and a climbing load average. It
  read as a CPU/shader-cache problem and was wrong.
- `sensors` is **not installed** on either desktop (only `Hosts/Asgard/_hardware.nix` has
  `lm_sensors`), and her board exposes **no fan-RPM inputs at all** (`gigabyte_wmi` gives
  `temp1..6`; no `nct6775`). GPU fan % comes from `nvidia-smi`, CPU temp from the hwmon
  named `k10temp` (`Tctl`/`Tccd1`). **CPU fan RPM is not measurable on Elektra** — don't
  promise a reading you cannot take.

## Deliberately left out

| Module | Why |
|---|---|
| `grub` | hardcodes Sisyphus's `rootFsUuid` and emits Sisyphus's profile entries. She is single-boot on `grub-celeste`. |
| `sops` | that module is keyed to rock's hand-copied age key at `/home/rock/.config/sops/age/keys.txt` |
| `wolf` | pulls full Docker and hardcodes `WOLF_RENDER_NODE=/dev/dri/renderD128` (Sisyphus's RX 9060 XT) |
| `sunshine` | pins `output_name=HDMI-A-1`, re-patches it every activation, grabs the desktop cursor whenever it runs |
| `rpcs3` | large, needs firmware she may never want |

## Known-wrong-but-harmless

Her skwd wallpaper library starts **empty** — `~/Pictures/Wallpapers` is not in the
repo. See `Claude/next-up.md`.

## Hyprland, not niri

She was briefly configured for niri (a straight clone of Sisyphus) and moved to
Hyprland before ever being installed. The swap is clean because everything the
two compositors share — the X server for SDDM's greeter, keymap, `XCURSOR_*` /
`NIXOS_OZONE_WL`, Bluetooth, `hardware.graphics` — lives in
`Modules/Desktop/desktop.nix`, the greeter in `Modules/Boot/sddm.nix`, and each
compositor module only sets its own `defaultSession`, portal routing and cursor
bits. `steam-open` / `spotify-open` / `wrappedNiri` are internal to `niri.nix` and
exist only to work around a niri spawn bug.

**Portals:** `xdg.portal.config.hyprland.default = [ "hyprland" "gtk" ]`. Until
2026-10-03 the module set `config.common.default = "gtk"`, and because
xdg-desktop-portal reads `/etc/xdg/xdg-desktop-portal/portals.conf` before the
`hyprland-portals.conf` Hyprland ships in `share/`, **everything** went to the gtk
portal — screen sharing and screenshots included, which gtk does not implement.

**Window rules mirror niri's app-ids:** `^steam$`, `^(discord|vesktop)$`,
`^brave-browser$`, `^[Tt]hunar$`. The old `^(Steam)$` / `^(discord)$` / `^(brave)$`
/ `^(thunar)$` never matched (wrong case, or the wrong client), so those windows
were opaque whatever `opacityStrong` / `opacityLight` said. Media keys use the
same `--ignore-player=skwd-music` playerctl string as niri.

**One real difference, and it matters here.** niri silently ignores `output` blocks
for connectors that do not exist, so a wrong monitor name is harmless. Hyprland is
not so forgiving: a config naming only `DP-2` and `HDMI-A-1` gives a machine with
`DP-3`/`DP-4` no matching rule at all. So:

- `Modules/Desktop/hyprland.nix` takes `my.hyprland.monitors` (default `[ ]` — the
  old Odysseus default and the never-read `primaryMonitor` / `secondaryMonitor` /
  `secondaryWorkspace` options are gone).
- It appends `",preferred,auto,1"` unconditionally **after** the host's rules, so an
  unlisted output still lights up. A specific rule always wins over the catch-all.
- Her host names `DP-3` (the pivoted Dell, `transform,3`) and `DP-2` (the Philips),
  read with `hyprctl monitors` on the installed system. **Not** the names the
  Apollo ISO reported (`DP-3` / `DP-4`): nouveau on the stick enumerates the
  connectors differently from the proprietary driver.

`Modules/Core/nvidia.nix` also sets `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`,
`LIBVA_DRIVER_NAME` and `NVD_BACKEND`. Hyprland is noticeably fussier about these
than niri — without `GBM_BACKEND` it commonly starts and renders nothing. If the
desktop misbehaves in a GL-ish way, comment those out first.

skwd forces `niri.overviewBackdrop = false` in her config (it used to force it
`true` on every host): there is no niri overview on Hyprland and no
`place-within-backdrop` rule to keep a backdrop surface out of the way. Her skwd
config also has no `steam` integration (no Millennium) and no `spicetify*` ones
(she runs the Sleek theme) — see `Claude/skwd-wall.md`.
