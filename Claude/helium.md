# Helium Browser

**Module:** `Modules/helium.nix`
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
