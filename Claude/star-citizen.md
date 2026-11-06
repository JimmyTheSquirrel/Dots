# Star Citizen — the RSI launcher under wine

**Sisyphus only.** Module: `Modules/Gaming/star-citizen.nix`. Input:
`nix-citizen` (`github:LovingMelody/nix-citizen`). Installs to
`$HOME/Games/rsi-launcher`, desktop entry **RSI Launcher**.

Star Citizen is not on Steam and never will be — it ships as the RSI Launcher,
a Windows Electron app that downloads the game itself. nix-citizen packages that
launcher together with the wine build, DXVK/VKD3D and prefix preparation the
[LUG knowledge base](https://github.com/starcitizen-lug/knowledge-base/wiki)
prescribes, so our module imports upstream's NixOS module and sets only what is
ours.

## ⚠️ The cachix is not optional, and the first rebuild misses it

`wine-astral-full` is a from-source build of wine + wine-tkg + Proton patches +
vkd3d-proton + DXVK. Upstream's cache has it prebuilt; **without the cache that
rebuild is hours of CPU.**

The trap: nix reads substituters from `/etc/nix/nix.conf`, which the rebuild that
introduces this module has not written yet. So the *first* rebuild would build
wine from source even though the module adds the cache. `trusted-users` here is
`root` alone, so the pre-fetch must be run with sudo:

```bash
sudo nix build --no-link \
  --extra-substituters https://nix-citizen.cachix.org \
  --extra-trusted-public-keys nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo= \
  .#nixosConfigurations.rock-Sisyphus.config.system.build.toplevel
```

Then `system-rebuild rock Sisyphus` as usual. Every later rebuild picks the cache
up from `nix.settings` and needs no flags.

Measured 2026-11-06 on the 97 derivations that rebuild: **25 are cachix hits**,
including `wine-astral-full`, `wine`, `wine-tkg-git`, `vkd3d-proton`,
`x86_64-w64-mingw32-gcc-16.2.0`, `rsi-installer` and `lug-helper`. What still
builds locally is cheap: the `rsi-launcher` wrapper (we `.override` it, so it can
never be the cached path), the git/exe fetches, and the kernel-modules closure
for `v4l2loopback`.

## ⚠️ `includeOverlay = false` is what makes the cache work

Upstream defaults it to **true**, which splices nix-citizen's packages into *our*
`pkgs` — i.e. rebuilds them against nixpkgs 26.05, and every cache hit becomes a
local build. With it **false**, the module's `smartPackage` falls back to
`inputs.nix-citizen.packages.*`, built against upstream's own lock, which is
exactly what the cachix holds. Verified by store path: with the overlay off,
`programs.rsi-launcher.wine` resolves to the same
`bw26kh1ak990dcs54jgc30i1imsgr4mj-wine-astral-full-11.16-2ecc2f8` the cachix
serves.

For the same reason the flake input carries **no `follows` of any kind, not even
`nix-gaming`** — see the comment in `flake.nix`. Same doctrine as `skwd-wall-v2`
and `millennium`.

## The option namespace moved

Upstream renamed `nix-citizen.starCitizen` → **`programs.rsi-launcher`**. The old
namespace still evaluates, emits a warning, and is scheduled for removal. It also
defaults to the `star-citizen` package, which is **not in the cachix** (404,
checked 2026-11-06) while `rsi-launcher` is. Use `programs.rsi-launcher`.

## What the module sets, and what it deliberately leaves alone

| Setting | Value | Why |
|---------|-------|-----|
| `includeOverlay` | **false** | cache hits — see above |
| `wine` | `wine-astral` (default) | the LUG's own wine-tkg build, and the cached one. umu + Proton is the alternative, but nix-citizen's `umu-launcher` is **not** cached |
| `setLimits` | true (default) | `vm.max_map_count`, `fs.file-max`, `nofile` soft 16777216 via `security.pam.loginLimits`, plus lug-helper's joystick udev rules (`udevRules` defaults to it). Left on so a future addition to that set arrives with an input update |
| `enableNTsync` | true (auto, kernel ≥ 6.14) | Sisyphus runs 6.18 and ships `ntsync.ko` |
| `enforceWaylandDrv` | true (default) | wine's Wayland driver instead of XWayland — the fix for Star Citizen's cursor drift under niri |
| `disableEAC` | false (default) | **not a troubleshooting step.** The game refuses to go online without EAC |
| `gamescope` | off | adds a layer; only worth it for mouse-capture trouble |
| `preCommands` | empty | `DXVK_ASYNC`, which the 2026-03 attempt exported globally, does nothing on mainline DXVK — it was a patch-only variable, since replaced by the graphics pipeline library |

### `fs.file-max` is forced back off

`setLimits` pins `fs.file-max = 524288` (at `mkOverride 999`). `Modules/Core/base.nix`
documents why that is wrong — systemd already raises it to its maximum at boot, so
pinning a number only ever *lowers* the limit. The module sets
`boot.kernel.sysctl."fs.file-max" = lib.mkForce null`; a null **drops the line
from `/etc/sysctl.d/60-nixos.conf` entirely** rather than writing a value.

`vm.max_map_count` needs no such treatment: base.nix already sets the same
16777216 at normal priority, which beats upstream's `mkOverride 999`.

## If it misbehaves

In order, cheapest first:

1. **`lug-helper`** (installed). The LUG's own maintenance script: prefix checks,
   the DXVK/wine version switcher, shader-cache clearing, per-patch fixes. This is
   the community's first step, not a last resort.
2. `enforceWaylandDrv = false` — back to XWayland.
3. `patchXwayland = true` — the patched XWayland for cursor issues. It is an
   overlay, so it costs a local build.
4. `gamescope.enable = true` — last resort; also fixes mouse capture.

## Open / unverified

- **No niri window rules.** The launcher's and the game's `app-id` under wine's
  Wayland driver is not knowable without running it — read it off `niri msg
  windows` on first launch before writing any rule, the way every other rule in
  `Modules/Desktop/niri.nix` was derived. ⚠️ And see
  `niri-rule-reapplies-on-window-recreate`: a game that rebuilds its window
  re-runs its rules, so an `open-on-output` rule can yank it off DP-2 mid-session.
  Star Citizen is **not** a `steam_app_*` window, so the generic
  "streamed games go to HDMI-A-1" rule does not touch it.
- **Disk.** The install is ~155 GB (that is what the October sweep reclaimed from
  the previous prefix). `/` had **363 GB free** on 2026-11-06 — enough, with not
  much room for a second large game alongside it.
- **Nothing has been launched yet.** The module evaluates and the closure
  substitutes; whether the game runs is untested.
- Needs an RSI account with a game package — the launcher alone installs nothing.

## History — this is the second attempt

- **2026-03-26** (`2546e64`, "Added Star Citizen to Flake") — `nix-citizen` +
  `nix-gaming`, the cachix, the kernel tunables, zramSwap, and Hyprland
  `windowrulev2` entries for the launcher and the game.
- **2026-06-19** (`3caa1aa`, "Server V6") — both inputs dropped from `flake.nix`
  as collateral in a restructure. Not a deliberate removal.
- **ff89743** — the window rules died with the Hyprland → niri move on Sisyphus.
- **2026-10-17** — the 155 GB `/home/rock/Games/rsi-launcher` prefix deleted in
  the disk sweep (`sisyphus-disk-reclaim-sweep`).
- Only `vm.max_map_count` and `zramSwap` in `Modules/Core/base.nix` survived;
  both arrived as Star Citizen prerequisites and now apply to every host.
