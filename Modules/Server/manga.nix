{ ... }: {
  # Asgard — manga: Suwayomi (headless Tachiyomi/Mihon) and FlareSolverr.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  {

# ══════════════════════════════════════════════════════════════════════════════
# MANGA — Suwayomi (headless Tachiyomi/Mihon server), port 4567
# Tracks ongoing series from web sources and auto-downloads new chapters as they
# release. Mihon on the phone/tablet connects over the tailnet and reads from here.
#
# Native NixOS module (services.suwayomi-server), not a container — so everything
# except the per-library source/series picks is declarative. Those live in
# Suwayomi's own DB and are genuinely UI state, like noctalia's settings.toml.
#
# TWO PATHS ON PURPOSE:
#   dataDir       /var/lib/suwayomi-server  — H2 database + config, on the NVMe
#   downloadsPath /data/media/manga         — the chapters themselves, on the pool
# The database must NOT sit on /data/media: that is mergerfs (FUSE), and SQLite/H2
# on FUSE is the locking-corruption trap this repo already dodges for the arrs via
# the /data/.state bind mount. Only the media goes on the pool.
# ══════════════════════════════════════════════════════════════════════════════

    # ── FlareSolverr — Cloudflare challenge solver (port 8191) ────────────────
    # A headless-Chrome proxy: other services hand it a URL, it clears the
    # Cloudflare interstitial and hands back the response + cookies.
    #
    # Added because Comick and Manganato both failed in Suwayomi with a bare
    # "Cloudflare bypass currently disabled", which silently removed a large
    # share of usable manga sources — MangaFire and MangaDex were carrying
    # everything on their own.
    #
    # Shared by three consumers — it sits here beside its first one, but it is
    # a container of its own rather than part of any of them:
    #   Suwayomi  — native service on the host  -> http://localhost:8191
    #   Shelfarr  — container                   -> http://host.containers.internal:8191
    #   Prowlarr  — could use it as an indexer proxy (NOT configured; see below)
    #
    # It runs a real browser, so it is the heaviest thing in the stack per
    # request (~500 MB resident under load). Asgard has ~22 GB free, so this is
    # noted rather than a concern.
    virtualisation.oci-containers.containers.flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = [ "8191:8191" ];
      environment = {
        LOG_LEVEL = "info";
        TZ = "Australia/Sydney";
      };
      autoStart = true;
    };

    services.suwayomi-server = {
      enable = true;

      # ⚠️ Version override is LOAD-BEARING, not a routine bump.
      #
      # nixpkgs pins 2.1.1867 (Jul 2025), which only understands the LEGACY flat
      # `index.min.json` extension-repo format. Keiyoushi — the community successor
      # to the archived Tachiyomi repo, and effectively the only source repo that
      # matters — migrated to the Mihon 0.20.1+ manifest (`index.pb`, protobuf) and
      # now serves the old path as a TWO-ENTRY DEPRECATION STUB ("Outdated App",
      # "Update to Mihon 0.20.1+").
      #
      # On 2.1 that means the service starts, reports active, answers HTTP 200, and
      # finds exactly ZERO usable sources — a textbook healthy-looking dead end.
      # This was confirmed live on Asgard, not inferred: /api/v1/extension/list
      # returned precisely those two stubs.
      #
      # 2.3.x added the new format (NetworkExtensionStore, @ProtoNumber) while
      # keeping a legacy path. Jar sha256 821141b3… was cross-checked against
      # upstream's published Checksums.sha256 before pinning.
      #
      # Drop this whole override once nixpkgs ships >= 2.3 — and when you do, re-read
      # the note on `extensionStores` below, because the key name moved in the same
      # jump.
      package = pkgs.suwayomi-server.overrideAttrs (_: {
        version = "2.3.2243";
        src = pkgs.fetchurl {
          url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v2.3.2243/Suwayomi-Server-v2.3.2243.jar";
          hash = "sha256-ghFBsy4XDUoC08vf7Vd+2PB70iOD/19BMuu1rkDpjdU=";
        };
      });

      # Primary group `media` (gid 169, nixflix's) is what grants write access to
      # /data/media/manga. The module still creates the `suwayomi` user itself —
      # only the group is overridden, so it does not try to create `media` twice.
      group = "media";

      # tailnet-only; tailscale0 is already in trustedInterfaces, so no port opens.
      openFirewall = false;

      settings.server = {
        ip = "0.0.0.0";

        # 4567 is Suwayomi's own default. The NixOS module defaults to 8080, which
        # on this box is SABnzbd's socat proxy — leaving it at the module default
        # would collide with a live service.
        port = 4567;

        downloadsPath = "/data/media/manga";
        # CBZ so the files stay portable — Mihon, Komga, Kavita and plain readers
        # all open them. The default (loose images in a folder) does not travel.
        downloadAsCbz = true;

        # --- auto-download ---
        autoDownloadNewChapters = true;
        # Upstream defaults this to `true`, which skips auto-download for any entry
        # that still has an unread chapter — i.e. exactly the ongoing series this
        # exists for. Left at the default, the feature does almost nothing.
        excludeEntryWithUnreadChapters = false;
        autoDownloadNewChaptersLimit = 0; # 0 = no cap

        # --- updater: what gets checked for new chapters ---
        globalUpdateInterval = 6; # hours — 6 is the minimum the server accepts
        # Both of these default to `true` and both would exclude ongoing series:
        # a series not opened yet counts as "not started", and any series with a
        # backlog has unread chapters. Completed series really have nothing left
        # to fetch, so that one exclusion stays on.
        excludeNotStarted = false;
        excludeUnreadChapters = false;
        excludeCompleted = true;

        # Suwayomi ships with NO sources at all. Without at least one store there is
        # nothing to search or download, and the UI looks healthy while being empty.
        #
        # ⚠️ The key is `extensionStores` on 2.3 — it was `extensionRepos` on 2.1 and
        # renamed in the same release that added the new format. server.conf is HOCON
        # and unknown keys are silently ignored, so the OLD name fails without a word.
        # The NixOS module still declares the old `extensionRepos` option (it targets
        # 2.1), so that key is also emitted, harmlessly, as an empty list.
        #
        # This is the `.pb` URL Keiyoushi documents for Mihon 0.20.1+. The legacy
        # `…/repo/index.min.json` also resolves on 2.3 — it reads `repo.json` and
        # follows its `index_v2` pointer here — but pointing straight at the real
        # index skips a redirect that only exists for old clients.
        extensionStores = [
          "https://github.com/keiyoushi/extensions/raw/repo/index.pb"
        ];

        # --- Cloudflare ---
        # Without this, Comick and Manganato fail every search with
        # "Cloudflare bypass currently disabled" — the sources install and look
        # fine, they just never return a result. localhost works because
        # Suwayomi is a native host service, not a container.
        flareSolverrEnabled = true;
        flareSolverrUrl = "http://localhost:8191";
        flareSolverrTimeout = 60;      # seconds
        flareSolverrSessionName = "suwayomi";
        flareSolverrSessionTtl = 15;   # minutes
        # Only route through FlareSolverr when a request actually hits a
        # challenge, rather than sending every request through a browser.
        flareSolverrAsResponseFallback = true;
      };
    };

  };
}
