# Miscellaneous — Shell, Terminal, Discord, Media

## Starship Prompt

**Module:** `Modules/starship.nix`

Custom Gruvbox Rainbow theme:
- Sharp powerline arrows ( U+E0B0,  U+E0B2) for segment separators
- Format: `user @ hostname` → `directory` → `git` → `language` → `docker/conda`
- Command prompt uses `➜` arrow (green for success, red for error)
- Time display disabled
- Requires a Nerd Font (configured via kitty.nix: `FantasqueSansM Nerd Font Mono`)

**Important:** The powerline glyphs are special Unicode characters that can get stripped during editing. If the prompt renders with plain rectangles instead of arrows, check the hex values in starship.nix:
- Line 14 should contain `ee 82 b2` (U+E0B2) for start cap
- Transition lines should contain `ee 82 b0` (U+E0B0) for arrows

## Fastfetch

**Module:** `Modules/fastfetch.nix`

Custom system info display:
- Uses kitty image protocol for logo display (`assets/terminal-logo-small.png`)
- Grouped sections: Hardware, Graphics, Software, Session
- Gruvbox color scheme with box-drawing borders

## Navi Cheats

**Module:** `Modules/navi.nix`

Custom cheatsheet at `~/.config/navi/cheats/rhys.cheat`:
- **System Cleanup** — `nix-gc` (GC, store optimise, journal vacuum)
- **System Rebuild** — Interactive menu via `system-rebuild`
- **Git Sync** — `git-sync "message"` for quick commits
- **Edit Secrets** — `sops ~/Dots/Secrets/secrets.yaml`

Wrapper scripts provided:
- `system-rebuild` — Interactive or CLI system rebuild
- `git-sync` — Stash, pull --rebase, push workflow
- `nix-gc` — Full cleanup (GC + optimise + journal + podman prune)

## Audio

**Module:** `Modules/audio.nix` — minimal PipeWire setup (PulseAudio disabled, ALSA + PulseAudio compat enabled, rtkit for realtime scheduling).

**Hardware:** Corsair Virtuoso XT Wireless (USB dongle, default sink/source). USB autosuspend is NOT an issue — the receiver is hardlocked to `power/control = on` by the kernel.

**WirePlumber startup warnings** — `wp_event_dispatcher_unregister_hook: assertion ... failed` appears on every boot. Known WirePlumber 0.5.x bug, harmless, audio works fine.

### Known audio cutout causes and fixes

**Steam/CS2 — old libpipewire causing mid-session dropouts:**
Steam bundles its own old `libpipewire-0.3.so` (protocol v4 vs system's 1.4.9). Games using it directly (CS2) periodically lose sync with the PipeWire server, producing `mod.client-node: detected old client version 4` in the PipeWire log and audio cutting out.
Fix (already in `steam.nix`): add `pipewire` to `extraLibraries` alongside `libpulseaudio`.

**Discord/Vesktop — WebRTC using PulseAudio compat layer:**
Without `--enable-features=WebRTCPipeWireCapturer`, Discord's WebRTC voice engine talks to PipeWire through the PulseAudio compatibility shim instead of natively, causing periodic voice audio dropouts.
Fix (already in `discord.nix`): `xdg.configFile."vesktop/argv.json"` with `["--enable-features=WebRTCPipeWireCapturer"]`.

**Discord noise suppression/echo cancellation** — these run as a separate processing thread that can disconnect mid-call. If dropouts persist after the above fix, turn them off in Discord Settings → Voice & Video. Not configurable declaratively (stored per-account server-side).

**Steam Linux Runtime (pressure-vessel) — old libpipewire causing system-wide dropouts:**
Games running in the Steam Linux Runtime container (e.g. CS2) use their own bundled old `libpipewire-0.3` (protocol v4). Pressure-vessel overrides `LD_LIBRARY_PATH` entirely, so the `extraLibraries` fix in `steam.nix` does NOT reach these games. CS2 connecting with the old protocol desynchs from the PipeWire server and causes dropouts for all other audio clients (Spotify, Discord, everything).
Fix (already in `base.nix`): `environment.sessionVariables.SDL_AUDIODRIVER = "pulseaudio"` — forces all SDL apps to use the PulseAudio backend (routes through pipewire-pulse) instead of connecting to PipeWire directly with the old library. Propagates into pressure-vessel via Steam's inherited environment.

---

## Discord

**Module:** `Modules/discord.nix`

Uses Vesktop (Discord + Vencord) instead of regular Discord:
- Better Wayland/Linux support
- CSS injection for transparent theme
- Native transparency support
- `argv.json` sets `--enable-features=WebRTCPipeWireCapturer` for stable PipeWire voice audio

**Cache clearing:** The module clears Vesktop cache directories (`Cache`, `Code Cache`, `GPUCache`) on each rebuild to prevent EPIPE errors. Login session is preserved.

## Media Viewers

Both installed via `base.nix`:

**Video:** `mpv` — handles all formats including `.MOV`/QuickTime. Keyboard-driven, minimal.

**Images:** `imv` — Wayland-native image viewer. Arrow keys to browse, `q` to quit.

**Default app associations:** Declared via `xdg.mimeApps` in `base.nix`. Covers all common video MIME types → `mpv.desktop` and image MIME types → `imv.desktop`. Changes take effect after log out/in (session must refresh `XDG_DATA_DIRS`).
