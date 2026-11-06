# ============================================================================
# Star Citizen — the RSI launcher under wine, via nix-citizen
# ============================================================================
#
# Star Citizen is not on Steam and never will be: it ships as the RSI Launcher,
# a Windows Electron app that downloads the game itself. nix-citizen packages
# that launcher together with the wine build, DXVK/VKD3D and prefix preparation
# the Linux Users Group knowledge base prescribes, so this module imports
# upstream's NixOS module and sets only what is ours.
#
# Sisyphus only. The game lives in $HOME/Games/rsi-launcher (~155 GB once
# installed) — the same path the March 2026 attempt used, so a reinstall lands
# where the old prefix was before the 2026-10-17 disk sweep deleted it.
#
# ── History ─────────────────────────────────────────────────────────────────
# This is the second time around. Commit 2546e64 (2026-03-26) added nix-citizen,
# the kernel tunables and a set of Hyprland window rules; the input was dropped
# again in 3caa1aa (2026-06-19, "Server V6") as collateral in a restructure,
# and the 155 GB wine prefix was deleted in the October sweep. The only things
# that survived are `vm.max_map_count` and zramSwap in Modules/Core/base.nix,
# which arrived as Star Citizen prerequisites and now apply to every host.
#
# ── The option namespace ────────────────────────────────────────────────────
# Upstream RENAMED `nix-citizen.starCitizen` to `programs.rsi-launcher`. The old
# namespace still exists, warns on eval, and is scheduled for removal — and its
# default package (`star-citizen`) is NOT in the cachix (404 as of 2026-11-06),
# while `rsi-launcher` is. Use `programs.rsi-launcher`.
# ============================================================================
{ inputs, ... }:
{
  flake.nixosModules.star-citizen = { lib, ... }: {
    imports = [ inputs.nix-citizen.nixosModules.StarCitizen ];

    # Upstream's binary cache. Without this, `wine-astral-full` is a multi-hour
    # local build of wine plus DXVK plus VKD3D.
    #
    # ⚠️ nix reads substituters from /etc/nix/nix.conf, which this rebuild is
    # only about to WRITE — so on the rebuild that first introduces this module
    # the cache is not yet configured and everything builds from source. Fetch
    # the closure once as root first (root is the only trusted user here):
    #
    #   sudo nix build --no-link \
    #     --extra-substituters https://nix-citizen.cachix.org \
    #     --extra-trusted-public-keys nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo= \
    #     .#nixosConfigurations.rock-Sisyphus.config.system.build.toplevel
    #
    # Every later rebuild picks it up from here. These two lists MERGE with the
    # cache.nixos.org entries nixpkgs' own nix.nix defines, rather than
    # replacing them — checked with `nix eval` on config.nix.settings.
    nix.settings = {
      substituters = [ "https://nix-citizen.cachix.org" ];
      trusted-public-keys = [
        "nix-citizen.cachix.org-1:lPMkWc2X8XD4/7YPEEwXKKBg+SVbYTVrAaLA2wQTKCo="
      ];
    };

    programs.rsi-launcher = {
      enable = true;

      # ⚠️ This is the whole reason the cachix works. With the overlay ON
      # (upstream's default) nix-citizen's packages are spliced into OUR pkgs
      # and therefore rebuilt against nixpkgs 26.05; with it OFF the module's
      # `smartPackage` falls back to `inputs.nix-citizen.packages.*`, built
      # against upstream's own lock — which is exactly what the cachix holds.
      # Same reasoning as the no-`follows` note in flake.nix. Verified
      # 2026-11-06: wine-astral and rsi-launcher both 200 on the cachix,
      # evaluated through upstream's lock.
      includeOverlay = false;

      # wine-astral (upstream's default `wine` package) over umu + Proton. It is
      # the LUG's own wine-tkg build, it is the variant the cachix has prebuilt,
      # and nix-citizen's `umu-launcher` is NOT cached (404, same check).
      #
      # setLimits (default true) is left on: it brings vm.max_map_count,
      # fs.file-max and a `nofile` soft limit of 16777216 via
      # security.pam.loginLimits, plus the lug-helper udev rules for joysticks
      # (udevRules defaults to setLimits). Those are the knowledge base's
      # prerequisites and keeping it on means a future addition to that set
      # arrives with an input update instead of being missed here.
      #
      # enableNTsync defaults to on for kernels >= 6.14 — Sisyphus runs 6.18 and
      # ships ntsync.ko, confirmed with modinfo.
      #
      # enforceWaylandDrv defaults to on, which is what we want under niri: it
      # makes wine use its Wayland driver instead of XWayland, which is the fix
      # for Star Citizen's cursor drift. If the game misbehaves the escape
      # hatches, in the order worth trying, are:
      #   enforceWaylandDrv = false;  # back to XWayland
      #   patchXwayland = true;       # then the patched XWayland (an overlay,
      #                               # so it costs a local build)
      #   gamescope.enable = true;    # last resort; also fixes mouse capture
      #
      # EAC stays ON (disableEAC default false) — Star Citizen refuses to go
      # online without it, so disabling it is not a troubleshooting step.

      # Env for the launcher and the game. Empty on purpose: DXVK_ASYNC, which
      # the 2026-03 Hyprland config exported globally, does nothing on a
      # mainline DXVK (it was a patch-only variable, since replaced by the
      # graphics pipeline library). Put MANGOHUD=1 / DXVK_HUD=compiler here when
      # actually diagnosing something.
      preCommands = "";
    };

    # lug-helper is already pulled in as a udev package by `udevRules` above
    # (its rules are what make a HOTAS/joystick usable), but the CLI itself is
    # not installed by the module. Install it: it is the Linux Users Group's own
    # maintenance script and the community's first troubleshooting step —
    # prefix checks, the DXVK/wine version switcher, shader-cache and
    # "remove a stuck install" chores, and the only sanctioned way to apply the
    # LUG's per-patch fixes. Taken from the flake's package set rather than
    # `pkgs` for the same reason as includeOverlay above (cachix hit, verified
    # 2026-11-06).
    environment.systemPackages = [
      inputs.nix-citizen.packages.x86_64-linux.lug-helper
    ];

    # Modules/Core/base.nix deliberately does NOT pin fs.file-max — systemd
    # already raises it to its maximum at boot, so setting a number only ever
    # LOWERS the limit. setLimits above reintroduces it at 524288 (mkOverride
    # 999), so take it straight back out; null drops the line from
    # /etc/sysctl.d/60-nixos.conf entirely rather than writing a value.
    #
    # vm.max_map_count needs no such treatment: base.nix sets the same 16777216
    # at normal priority, which already wins against upstream's mkOverride 999.
    boot.kernel.sysctl."fs.file-max" = lib.mkForce null;
  };
}
