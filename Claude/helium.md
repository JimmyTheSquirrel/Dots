# Helium Browser

**Module:** `Modules/Apps/helium.nix`
**Flake input:** `github:amaanq/helium-flake` (not in nixpkgs)
**App-id on Wayland:** `helium` (used for Niri opacity rule)

Chromium-based privacy browser (de-googled, built on ungoogled-chromium) used alongside Brave.

## What the Module Manages Declaratively

- **Package** — wrapped binary via `pkgs.symlinkJoin` + `makeWrapper`. Wrapper flags: `--disk-cache-size=104857600` (100MB cache), `--enable-gpu-rasterization`, `--enable-zero-copy`, `--no-default-browser-check`
- **Dark theme** — custom Chrome theme extension (`helium-dark-theme` derivation) loaded via `--load-extension`. Sets exact colors for frame, toolbar, omnibox, and tabs. Loaded alongside Bitwarden as a comma-separated `--load-extension` list.
- **Bitwarden** — loaded via `--load-extension` pointing to a Nix-fetched derivation (ungoogled-chromium blocks Google's CWS, so `force_installed` doesn't work). Extension zip fetched from Bitwarden's GitHub releases, source maps stripped, Bitwarden's RSA public key injected into `manifest.json` so `--load-extension` assigns the correct extension ID (`nngceckbapebfimnlniiiahkandclblb`).
- **Bitwarden pinned** — `ExtensionSettings` policy with `toolbar_pin = "force_pinned"` targets the correct ID
- **Bookmarks** — two managed folders (Work: Outlook, Personal: GitHub/Reddit/ProtonDB) via `ManagedBookmarks` policy
- **New tab page** — blank via `NewTabPageLocation = "about:blank"`
- **Widevine DRM** — one file only: the hint `~/.config/net.imput.helium/WidevineCdm/latest-component-updated-widevine-cdm`, containing `{"Path": "<nix store CDM dir>"}`, written with `force = true` (Helium rewrites it at runtime). **Restart Helium after a rebuild** for the CDM to load.

  **The CDM comes from `nixpkgs-unstable`, deliberately — do not "simplify" it back to `pkgs.widevine-cdm`.** Stable pins `4.10.2934.0`, which **Crunchyroll's licence server rejects**: auth, `playback/v3/.../play` and the DASH manifest all return `200`, and only `POST /license/v1/license/widevine` returns **403** → "Not Available / **KAT-6005**". `4.10.3050.0` from unstable fixes it (verified 2026-09-16). Licence servers cut off deprecated CDM versions over time, so **expect to bump this again**; once stable ships >= 4.10.3050.0 the override can go.

  **VMP is a red herring on Linux** — host verification is unimplemented for *every* Linux browser (no `.sig` files exist, Chrome included), so licence servers must accept `PLATFORM_UNVERIFIED`. Don't chase missing signatures. Netflix refuses for unrelated reasons.

  **Why the hint file is load-bearing, and why it must point at the store — fixed 2026-09-16.** The Helium *package* bundles its own CDM (via the `widevine-cdm` override), but the component updater registers that copy ~400 ms **after** startup, whereas Chromium picks its CDM once, at process start, from the hint file. Miss the hint and the renderer logs `Widevine enabled but no library found` and `com.widevine.alpha` stays unavailable for the whole process.

  The old config also symlinked `WidevineCdm/<version>/` into the profile and pointed the hint at *that*. The component updater **deletes** a profile-local version dir (same version is already preinstalled in the package), leaving the hint dangling → Widevine dies → Crunchyroll **KAT-6005**. It presented as *intermittent* because Helium rewrites the hint to the store path mid-session, so the next launch works until the next rebuild restores the broken hint.

  Diagnosing: `helium --user-data-dir=<tmp> --remote-debugging-port=9333 --enable-logging=stderr --v=1`, then grep the log for `Registering hinted Widevine` (good) vs `no library found` (broken). Don't trust "the CDM file exists" — check registration at startup.

## Theme Colors

In `helium-dark-theme` derivation manifest:
- `frame`: `[42, 42, 42]` — tab strip background
- `toolbar`: `[48, 48, 48]` — address bar area
- `omnibox_background`: `[38, 38, 38]` — search bar input (darker for depth)
- `tab_text` / `tab_background_text`: `[230]` / `[150]` — active/inactive tab text
- To adjust: edit the color arrays in `helium-dark-theme` inside `helium.nix` and rebuild
- GTK/QT theme options in settings do nothing useful on Niri without a GTK theme — use the custom extension instead
- If theme doesn't apply after rebuild, go to `helium://settings/appearance` and reset the theme once

## Policy Setup

- Policies go in `/etc/chromium/policies/managed/helium.json` via `environment.etc`
- Helium reads from `/etc/chromium/policies/managed/` (standard ungoogled-chromium path)
- Verify policies loaded at `helium://policy` — all entries should show Status: OK
- Bitwarden extension ID: `nngceckbapebfimnlniiiahkandclblb` (locked by RSA key in manifest)
- Bitwarden version is pinned — update URL + hash in `helium.nix` when upgrading. RSA key stays the same across versions.

## Bitwarden Never Auto-Updates

`--load-extension` means there is **no CWS update channel** — the extension is frozen at whatever version is pinned in `helium.nix` until the URL + hash are bumped by hand. Check
`https://api.github.com/repos/bitwarden/clients/releases` for the latest `browser-v*` tag periodically.

Bump procedure:
```bash
nix-prefetch-url --unpack https://github.com/bitwarden/clients/releases/download/browser-vX.Y.Z/dist-chrome-X.Y.Z.zip
nix hash convert --hash-algo sha256 --to sri <base32-hash>
```
Then edit `url` + `hash` in the `bitwarden-zip` fetchzip. The ID is derived from the injected RSA key, not the version, so vault state and the `force_pinned` policy survive the bump.

**Symptom that means "you are overdue for a bump": popup opens blank / spins forever.** The popup shell
loads (`WASM SDK loaded`, `State version: NN` in its console) but the body stays empty, and the browser log
shows `Unchecked runtime.lastError: Could not establish connection. Receiving end does not exist.` — the popup
cannot reach the MV3 background service worker. Bitwarden 2026.6.0 shipped two fixes for this class
(PM-37932 "Recover browser IPC after process reload", CL-1207 missing `provideZoneChangeDetection()` in the
browser bootstrap), so anything pinned below that is a prime suspect.

Debugging it for real needs a headful browser: restart Helium with `--remote-debugging-port=9222`, open the
popup, then attach over CDP. Do **not** trust a headless reproduction — Bitwarden's `popup/index.html` renders
an empty body when opened as a plain tab under `--headless=new` in *any* Chromium (verified against Brave),
so a blank popup there proves nothing.
- `BookmarksBarEnabled` policy removed — Helium sets this internally, adding it causes a policy Error

## Transparency

- Niri opacity rule (`app-id="^helium$"`, opacity 0.96) handles compositor-level transparency
- **Niri opacity rule requires logout/login** — baked into wrapper-modules binary, not hot-reloaded
- Wallpaper colors bleed through at lower opacity values — keep at 0.95+ to avoid tinting web content
- No CSS-level transparency (Chromium doesn't support userChrome equivalent)

## ManagedBookmarks Format

```nix
ManagedBookmarks = [
  { toplevel_name = "Bookmarks"; }          # parent folder name on bar
  { name = "Work"; children = [
    { name = "Outlook"; url = "..."; }
  ]; }
  { name = "Personal"; children = [
    { name = "GitHub"; url = "..."; }
  ]; }
];
```

All managed bookmarks live under one parent folder — can't split into two independent top-level folders via policy.
