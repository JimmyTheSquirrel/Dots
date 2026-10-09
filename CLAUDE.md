# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.
Detailed topic docs live in `Claude/` — read the relevant file before working on that area.

## Topic Docs (read before working on that area)

| Topic | File | Covers |
|-------|------|--------|
| **Architecture** | `Claude/architecture.md` | Folder layout, the module pattern, **the `/_` rule**, `mkHost`, per-host hardware/disko files, GRUB profiles, Plymouth |
| **Next up / backlog** | `Claude/next-up.md` | Open work. **Read before a fresh install or wipe** |
| **Deploying / installer USB** | `Claude/deploy.md` | `system-rebuild` — a **full-screen app** (Resources/Rebuild, Textual) with no args, the bash CLI with args — its menus (Rebuild · Remote · Utilities · Apollo · Help — every menu ends with a Help row; `?` opens the same page) and how to extend them. The Apollo stick: `apollo-iso` / `apollo-key` / `apollo-connect` / `apollo-deploy`. **nixos-anywhere skips kexec on our ISO, so an SSH-over-tailnet install survives.** Ventoy + Secure Boot caveats |
| **Elektra** (her machine — she is Kit-Kat) | `Claude/elektra.md` | Separate NVIDIA hardware running Hyprland. **Her own sops file**, disko + facter, what was left out |
| Niri compositor | `Claude/niri.md` | Layout, keybinds, window rules, startup, Spotify/Steam launchers |
| Noctalia shell | `Claude/noctalia.md` | Bar, IPC, font packaging, **idle/monitor power-save**. **Nix owns `settings.toml`** — the bar/lockscreen/widget layout lives in `lockedSettings` and a rebuild forces it back over any GUI change, so edit Nix, not the GUI |
| SKWD wallpaper | `Claude/skwd-wall.md` | skwd v2 (Rust) on Sisyphus + Elektra: matugen flow, integrations, troubleshooting |
| Spicetify | `Claude/spicetify.md` | Text theme, CDP color injection, CSS fixes |
| Helium browser | `Claude/helium.md` | Extensions, policies, dark theme, Bitwarden |
| Game streaming | `Claude/streaming.md` | Moonlight clients, Sunshine (installed, not autostarted), Tailscale |
| **Wolf** (Moonlight server) | `Claude/wolf.md` | The live streaming host on Sisyphus. **True 4K**, seat9 input isolation, Steam library sharing, and the **`fake-udev` gamepad fix** without which pads work in Steam but are invisible to games |
| Steam theming | `Claude/steam.md` | Millennium injector, SpaceTheme/Zehn, matugen colours, why opacity comes from Niri |
| Eclipse TV box | `Claude/eclipse.md` | Pi 5 LibreELEC/Kodi, Jellyfin addon, **HEVC-only decode (no H.264 HW)**, **no HDR output**, Dolby Vision, skin menu, CEC, headless workflow. **Not a Nix host** — `Resources/Eclipse-Skin/` + `Resources/Eclipse-Box/` mirror its hand-made state; DR is an SD card image, not a config push. Its **Bluetooth manager** (both dashboards' `#ec-ctl`: pair, rename, auto-connect, live search) and **Network card** (`#ec-net`: **wired-only** by default — Wired ⇄ Wi-Fi switch, search + join with a password, forget; every switch runs **on the Pi, detached and self-reverting** — `eclipse-net.sh`) live in eclipse-control so the two dashboards stay in sync |
| Emulators | `Claude/emulators.md` | RPCS3, Ryubing, PS3 game prep |
| Secrets | `Claude/secrets.md` | sops-nix, adding secrets, key locations |
| Shell/misc | `Claude/misc.md` | Starship, Fastfetch, btop, Navi, Discord, media viewers, Thunar, audio (PipeWire fixes) |
| Asgard server | `Claude/server-info.md` | Ports, nixflix quirks, Seerr API, Glance, recyclarr. Code is `Modules/Server/`. Glance's **HUD** (panel frame, grid, pines, line-art Yggdrasil, logo, icons) is **generated at build time** by `Resources/Glance/hud.py`, on a tech-grey ground that tiles down the page so it never runs out. Its colour is the viewer's: **`theme.js`'s picker** recolours it per browser, so **HUD colours must be `var(--hud…)`/`--s*`, never a literal**. Every pick is a **two-tone** (no single colours). Its *Just for fun* row is **one theme on Asgard: Ravens** (`ravens.css` + `ravens.js`) — Huginn and Muninn perch on the cards, fly between them, and tell you the news when tapped. MarsBar's row has the rest (files in `Resources/Glance/`): **Cats** (`cats.css` + `cats.js`) — living cats that idle, answer taps, chase a laser and react to the cards; **Snow, Sakura, Starry night, Spooky, Ocean** (`fx.css` + `fx.js`). A pick tints the **ground and glass** too, and card frames run from its first colour into its second. **Skins** (picker's top row, Asgard only): **Tech** and **Tech + Garden** (her `garden.css`/`garden.js` over the HUD via `garden-hud.css`, with switches for its parts). The **Overview** page is a top-down tree of how it all connects — Sisyphus → its machines → Asgard's services by who can reach them (internet / tailnet / VPN tunnel / house / disks) — with step-by-step "stories" (`overview.js` — its `NODES`/`ZONES`/`EDGES` tables must be kept in step with the services); a **Map ⇄ Living tree** slider at its top swaps in **the Living Yggdrasil** (`ygg-live.js`): the system grown as an ash, live — a leaf cluster per service that withers when its units stop (asgard-stats `units`, from cgroupfs; map in `stats.nix`'s `ASGARD_UNITS`), wells for the disks, sap for streams, seeds for downloads. A new service = a `LEAVES` line there too |
| Home Assistant | `Claude/home-assistant.md` | Smart plugs on Asgard `:8123`. `extraComponents` gates which integrations exist at all; device pairings are **not** declarative |
| MarsBar dashboard | `Claude/marsbar.md` | Partner-facing Glance on its **own tailnet node** (`marsbar:1111`) — why a node, not a path. Lights + Jellyfin/Seerr + the **full** Eclipse panel incl. the controller/subtitle card (shared with the admin dashboard — add new cards to BOTH `glance.nix` and `marsbar.nix` or they drift). Isolation is a Tailscale **ACL**, not in this repo. She has **her own colour picker** (theme.js, `marsbar` profile — marsbar.css colours are `hsl(var(--mb-h)…)`, never a literal), **Cats** and the other fun themes, and a living vine (**garden.js** + **garden.css**: blossoms that open and close, butterflies, fireflies — each its own switch in the picker's *Just for fun*; **shared with Asgard's Tech + Garden skin**, so check both). ⚠ Glance overrides `HTMLElement.prototype.animate` — use `Element.prototype.animate` |
| Dolphin (rejected) | `Claude/dolphin.md` | Decision record: Dolphin was trialled and rejected — **Thunar stays**. Don't re-propose it |

## Core Principles

**Everything must be declarative and fully reproducible.** A fresh NixOS install should be fully configured by cloning this repo and running a single rebuild command.

- **No manual configuration** — if it's not in Nix, it doesn't exist
- **No imperative state** — avoid runtime config files not generated by Nix; when unavoidable (e.g., `outOfStoreConfig`), use home-manager activation scripts
- **Reproducible builds** — `system-rebuild` on a fresh system produces an identical environment
- **Self-contained modules** — each module includes NixOS + Home Manager config in one file

When making changes, always ask: "Will this work on a fresh install without manual steps?"

## Build Commands

```bash
system-rebuild                          # Interactive menu (recommended)
system-rebuild rock Sisyphus            # Build and switch immediately
system-rebuild rock Sisyphus --boot     # Build for GRUB, don't switch
system-rebuild kitkat Elektra           # Push to her machine (on Elektra: rebuilds in place)
nix build .#apollo-iso                  # The Apollo ISO (or: apollo-iso)
nix flake update                        # Update flake inputs
```

`system-rebuild`, `git-sync`, `nix-gc` and the `apollo-*` helpers are
`writeShellApplication`s (shellchecked at build time) from
`Modules/Shell/deploy-tools.nix`, script bodies in `Resources/Scripts/*.sh`, the
shared look + menu engine in `Resources/Scripts/lib/ui.sh`. **`system-rebuild` with
no arguments opens a full-screen app** — `Resources/Rebuild/` (Python + Textual):
animated, the build drawn live, sudo/ssh prompts as pop-ups; `--classic` gives the
old inline menus. Machine cards, a preview panel beside every menu, ctrl+p to jump
to any action, a run history (`~/.local/state/system-rebuild/`). It keeps its own
host table + rebuild pipeline (`hosts.py`, `jobs.py`) — change both. See
`Claude/deploy.md` → The app. Sisyphus gets all of them;
Elektra gets `system-rebuild`/`git-sync`/`nix-gc` (`my.deploy-tools.admin = false`).
`system-rebuild` is **host-aware**: the machine it runs on rebuilds in place, any other
is pushed over the tailnet. Sisyphus builds into the named profile `-p sisyphus` (see
`Claude/architecture.md` → GRUB); the others use the default profile.
**Every machine is deployed from Sisyphus (2026-10-05).** Asgard used to be
self-managed (`H_MODE=managed`, *Pull & switch* from its own `~/Dots`) and
`system-rebuild` refused to push to it; that mode is gone and Asgard is now an
ordinary push target. **Asgard's `~/Dots` has been deleted** — there is no second
checkout anywhere, so this repo is the only copy. See `Claude/deploy.md`.

**Check a change evaluates** (all four hosts, no build):
`nix eval --raw .#nixosConfigurations.<attr>.config.system.build.toplevel.drvPath`
for `rock-Sisyphus`, `kitkat-Elektra`, `rock-Asgard`, `rock-Apollo`.

## Directory Structure

```
flake.nix                 # inputs + flake-parts; import-tree loads Hosts/ and Modules/
.sops.yaml                # sops creation rules — MUST live at the repo root
Hosts/
  Sisyphus/               # system.nix, _hardware.nix
  Elektra/                # system.nix, _hardware.nix (facter), _disko.nix, facter.json
  Asgard/                 # system.nix, _hardware.nix (+ it87 fans), _disko.nix
  Apollo/                 # system.nix — the deployer/rescue ISO
Modules/
  Core/                   # base (every host incl. the server), locale, audio, polkit,
                          #   sops (+ sops-kitkat), nvidia, tailscale, flake-lib (mkHost)
  Boot/                   # grub (Sisyphus profiles), grub-celeste (Elektra), plymouth,
                          #   sddm (qylock theme picked by my.sddm.theme)
  Desktop/                # desktop (GUI packages + bits both compositors share), niri,
                          #   hyprland, noctalia, skwd (v2), thunar, screenshot
  Shell/                  # zsh, starship, kitty, fastfetch, btop, git, navi,
                          #   deploy-tools (rock's admin scripts), sleepy-cat
  Apps/                   # helium, brave, vscodium, discord (Vesktop), spicetify
  Gaming/                 # steam (+ Millennium), rpcs3, sunshine, wolf
  Server/                 # Asgard. default.nix (nixflix import, shared constants),
                          #   storage, arr, recyclarr, jellyfin, downloads, books, manga,
                          #   photos, files, network, eclipse, glance, stats, ttyd — all one
                          #   nixosModules.server — plus home-assistant, marsbar, and the
                          #   _lib.nix / _plugs.nix (the one smart-plug list) / _origins.nix /
                          #   _livecard.nix helpers
Resources/                # static files the modules reference:
                          #   Glance/ (asgard.css/js, stats.js, hud.py, tailscale-status.py,
                          #   yggdrasil banner, overview.js/.css (the Overview map);
                          #   SHARED with MarsBar: cards.css, dash.js,
                          #   lights.js, eclipse.js, net.js, theme.js + cats.css/js + fx.css/js (the colour
                          #   picker)), MarsBar/ (css, vine svgs, garden.js),
                          #   HA-Bridge/, Asgard-Stats/, Eclipse-Control/, Network-Panel/,
                          #   Wolf-Bridge/ (Sisyphus), Scripts/ (deploy-tools + lib/ui.sh),
                          #   Rebuild/ (system-rebuild's full-screen app, Python + Textual),
                          #   Eclipse-Skin/ (Bingie layout overlay + eclipse-skin-push.sh —
                          #     re-run after any skin update or her layout reverts),
                          #   Eclipse-Box/ (the Pi's hand-made state: units, addon patches,
                          #     the Moonlight fork, keymaps; NOT applied automatically),
                          #   Fonts/, Spicetify-Text-Theme/, Steam-Glass-Theme/, Terminal-Images/
Secrets/                  # secrets.yaml (rock's hosts), kit-kat.yaml (her machine only)
Claude/                   # topic docs
```

## The Machines

| System | Desktop | Entry Point | Where | Key Modules |
|--------|---------|-------------|-------|-------------|
| **Sisyphus** | Niri | `Hosts/Sisyphus/system.nix` | rock's desktop, AMD | niri, noctalia, skwd, spicetify, wolf, sunshine, rpcs3, deploy-tools, grub, sddm (nier-automata) |
| **Elektra** | Hyprland | `Hosts/Elektra/system.nix` | her machine, **NVIDIA** | hyprland, noctalia, skwd, nvidia, grub-celeste, sddm (women-umbrella), sops-kitkat, brave, sleepy-cat, deploy-tools (no admin); disko + facter |
| **Asgard** | headless | `Hosts/Asgard/system.nix` | media server | server, home-assistant, marsbar; disko; systemd-boot |
| **Apollo** | Niri (live, not autostarted) | `Hosts/Apollo/system.nix` | USB stick | the deployer/rescue ISO — `Claude/deploy.md` |

Flake attributes are `<user>-<Host>`: `rock-Sisyphus`, `kitkat-Elektra`,
`rock-Asgard`, `rock-Apollo`. Sisyphus is the only machine on this disk; Elektra
and Asgard are separate hardware on the tailnet, pushed to with `--target-host`.

- **Every host:** locale, zsh, starship, git, fastfetch, btop.
- **Every installed host (not Apollo):** base.
- **Both desktops:** desktop, polkit, plymouth, sddm, thunar, audio, steam, kitty,
  helium, vscodium, noctalia, skwd, navi, spicetify, discord, tailscale.

**Displays (Sisyphus):** DP-2 (2560x1080 @ 144Hz primary, 8-bit) + HDMI-A-1
(1920x1080 @ 60Hz secondary). DP-2's 144Hz needs an explicit `mode` line — its
EDID advertises 60Hz as *preferred*. See `Claude/niri.md`. Elektra's monitors
(one pivoted) are in her host file under `my.hyprland.monitors`.

## Module Patterns

**Dendritic:** every `.nix` under `Hosts/` and `Modules/` is a flake-parts module,
auto-imported by import-tree. A module defines `flake.nixosModules.<name>` holding
both the NixOS and the Home Manager config for one feature. Hosts list modules by
**name**, so the folder a file sits in doesn't matter to Nix.

- **CRITICAL: new `.nix` files need `git add`** — import-tree only sees git-tracked files.
- **`_`-prefixed paths are skipped by import-tree** (`Hosts/*/_hardware.nix`,
  `_disko.nix`, `Modules/Server/_lib.nix`) — use them for plain NixOS modules and
  helpers you import by path.
- **Several files may define the same `nixosModules.<name>`; they merge** (that's how
  `Modules/Server/*.nix` all form `nixosModules.server`).
- **Hosts are built with `self.lib.mkHost`** (`Modules/Core/flake-lib.nix`), which
  wires Home Manager and hands every module `inputs`, `activeUser`, `hostName` and a
  single shared `pkgs-unstable`. Don't `import inputs.nixpkgs-unstable` in a module.
- Per-host knobs are `my.*` options declared by the module they configure
  (`my.hyprland.*`, `my.noctalia.*`, `my.sddm.theme`, `my.steam.millennium`, …).

**wrapper-modules:** used for Niri only — a wrapped package with its config baked in
via `perSystem`. See `Claude/architecture.md`.

## Flake Inputs

- `nixpkgs@nixos-26.05` (stable) + `nixpkgs-unstable`
- `home-manager@release-26.05`
- `flake-parts` + `import-tree` — modular flake organization
- `wrapper-modules` — wraps niri with its settings baked in
- `noctalia` — desktop shell (follows nixpkgs-unstable)
- `skwd-wall-v2` — wallpaper selector v2/Rust (`github:liixini/skwd-wall/nix`), Sisyphus + Elektra. **Never add `nixpkgs.follows`** — the binaries are autoPatchelf'd against upstream's pinned nixpkgs, and matching it keeps our derivations hash-identical to upstream's published store paths
- `qylock` — SDDM greeter themes (only the one picked by `my.sddm.theme` is copied)
- `helium` — browser (github:amaanq/helium-flake, not in nixpkgs)
- `spicetify-nix` — declarative Spotify theming
- `millennium` — Steam client CSS/JS injector (`?dir=packages/nix`). **Never add `nixpkgs.follows`** — upstream's pinned nixpkgs is load-bearing for a Bun FOD hash
- `sops-nix` — encrypted secrets with age keys
- `disko` — declarative disk partitioning (Elektra, Asgard)
- `nixflix` — declarative media server (arr stack + Jellyfin + Seerr), Asgard only
