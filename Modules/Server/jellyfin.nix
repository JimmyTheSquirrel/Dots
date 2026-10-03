{ ... }: {
  # Asgard — Jellyfin and Jellyseerr (both through nixflix), the Jellyseerr
  # first-boot fallback, Jellyfin's TV metadata provider order, and the Intel
  # QSV runtime Jellyfin transcodes with.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    inherit (import ./_lib.nix { inherit pkgs; }) waitForHttp;
  in
  {

    nixflix = {
      jellyfin = {
        enable = true;
        apiKey._secret = config.sops.secrets."jellyfin-api-key".path;
        users.admin = {
          password._secret = config.sops.secrets."jellyfin-admin-password".path;
          policy.isAdministrator = true;
        };

        network = {
          # Off-site clients reach us through the Cloudflare tunnel, and
          # cloudflared connects to Jellyfin over loopback — so every remote
          # session presented as 127.0.0.1 and Jellyfin classified it as LAN,
          # where bandwidth is assumed unlimited. It therefore never adapted
          # anything: a 35 Mbit 4K HEVC remux was shipped to a TV behind a
          # 30 Mbit shaped uplink, stalling every few seconds.
          #
          # Trusting the proxy's X-Forwarded-For restores the real client IP,
          # which is what makes remoteClientBitrateLimit below fire at all.
          # localNetworkSubnets stays empty (= all RFC1918 is local), so LAN
          # clients are still uncapped and direct-play as before.
          knownProxies = [ "127.0.0.1" ];
        };

        # Bits per second. Raised from the original 12 Mbps on 2026-09-11 when
        # Eclipse (the Pi 5 TV box) became a permanent remote client after
        # moving to a second house — 12 Mbps forced every remux into an HLS
        # transcode, which turned out not even to be the main problem (see
        # wan-egress-shaping below), but a stricter cap than Eclipse's typical
        # ~15-20 Mbps HEVC remuxes need is still real quality loss for what is
        # now a primary device, not an occasional public share.
        #
        # Trade-off, accepted deliberately: 40 Mbps is most of the 30 Mbit WAN
        # egress cap on its own, so this no longer comfortably fits "two
        # concurrent remote streams" the way 12 Mbps did. A second simultaneous
        # remote/CF-tunnel viewer while Eclipse is direct-streaming will
        # contend for the same shaped pipe. Revisit if that starts happening.
        system.remoteClientBitrateLimit = 40000000;

        # Intel QuickSync on i5-14400 (UHD 730) — /dev/dri/renderD128
        encoding = {
          hardwareAccelerationType = "qsv";
          qsvDevice = "/dev/dri/renderD128";
          enableHardwareEncoding = true;
          allowHevcEncoding = true;
          hardwareDecodingCodecs = [ "h264" "hevc" "mpeg2video" "vc1" "vp9" "av1" ];
          enableTonemapping = true;
          enableVppTonemapping = true;

          # Unthrottled, ffmpeg transcodes to the end of the film regardless of
          # playback position and nothing reaps the output — a single 4K title
          # nine minutes in had already left 34 GB / 1399 segments in
          # /var/cache/jellyfin/transcodes. Throttle once the encoder is far
          # enough ahead, and drop segments the client has already fetched.
          enableThrottling = true;
          enableSegmentDeletion = true;
        };

        # Hides the chapter tick marks on the seek bar. This used to be a
        # one-off curl in the Fresh Deploy Checklist and was WIPED ON EVERY
        # BOOT: nixflix's jellyfin-branding-config.service POSTs this option to
        # /System/Configuration/Branding each time it runs, and its default is
        # "" — so the hand-pasted CSS lasted only until the next reboot.
        branding.customCss = ".sliderMarker { display: none !important; }";
      };

      # Jellyseerr — media request portal (exposed via Cloudflare tunnel).
      # Package left at nixflix's default (pkgs.seerr); naming the old
      # `jellyseerr` attribute only bought a rename warning on every eval.
      seerr = {
        enable = true;
        apiKey._secret = config.sops.secrets."jellyseerr-api-key".path;

        # ── Default quality profiles for requests ──
        # nixflix's seerr-radarr / seerr-sonarr units PUT the instance config on
        # every boot, and on every rebuild that restarts them. With no profile
        # name set they pick `.profiles[0]` — the first profile Radarr/Sonarr
        # list — so every request (anime included) fell back to whichever
        # profile sorted first. The old fix was a pair of hand-written timer
        # units that re-set the profiles 12 min after boot; they lost the race
        # on every `nixos-rebuild switch`, and anime requests then used the TV
        # profile. Naming the profiles here makes nixflix's own PUT the right one.
        #
        # The profiles are created by recyclarr-sync, and recyclarr.nix orders
        # both units after it. nixflix exits 1 if a named profile is missing —
        # on a fresh install that means "recyclarr has not managed a sync yet",
        # and it converges on the next boot/rebuild.
        #
        # ⚠ mkOptionDefault is LOAD-BEARING. nixflix builds the Radarr/Sonarr
        # instances (hostname, apiKey, root folder…) as the option's *default*;
        # an ordinary definition would REPLACE that default wholesale and drop
        # all of it. Defining at the same mkOptionDefault priority makes the two
        # merge instead.
        radarr = lib.mkOptionDefault {
          Radarr.activeProfileName = "Asgard - Movies";
        };
        sonarr = lib.mkOptionDefault {
          Sonarr = {
            activeProfileName = "Asgard - TV";
            # Jellyseerr keeps a separate anime profile; left unset it reuses the
            # TV profile, and anime never got the fansub-tier scoring.
            activeAnimeProfileName = "Asgard - Anime";
            # Absolute episode numbering, matching what arr-policy sets on the
            # anime series it knows about. mkForce: nixflix's default instance
            # pins "standard", and both definitions sit at the same priority.
            animeSeriesType = lib.mkForce "anime";
          };
        };
      };
    };

    # Fallback for a first boot where nixflix's seerr-setup dies half-way.
    #
    # nixflix's seerr-setup connects Jellyfin, enables the libraries and POSTs
    # /settings/initialize — but on the original deploy it died at the library
    # fetch (`curl -sf` exit 22) AFTER connecting Jellyfin and BEFORE initialising.
    # From that state it can never recover on its own: every later run re-sends
    # the full connect payload, which Jellyseerr rejects as "already configured".
    # This unit finishes the job from there: logs in with credentials only,
    # syncs + enables all libraries, marks the wizard initialised.
    #
    # On any install where seerr-setup completed — i.e. the live box, every
    # boot — its first check sees `initialized == true` and exits. Kept because
    # a fresh install cannot be tested here; drop it once one has been seen to
    # come up without it. Uses session cookie auth (same as nixflix's seerr-setup).
    systemd.services.seerr-library-setup = {
      description = "Activate all Jellyfin libraries in Jellyseerr";
      after    = [ "seerr.service" "seerr-setup.service" "network.target" ];
      wants    = [ "seerr.service" "seerr-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        SEERR="http://localhost:5055"
        COOKIE="/tmp/seerr-library-setup-cookie"

        ${waitForHttp { name = "Jellyseerr"; url = "$SEERR/api/v1/status"; tries = 24; interval = 5; }}

        # Skip if already initialized
        if curl -s "$SEERR/api/v1/settings/public" | jq -e '.initialized == true' > /dev/null; then
          echo "Jellyseerr already initialized — nothing to do."
          exit 0
        fi

        # Log in with credentials only (no server config — Jellyfin is already wired by nixflix).
        # The body is built by jq from the environment and piped to curl, so the
        # password is neither spliced into JSON by hand (a quote in it would
        # break the body) nor visible in any process's argv under /proc.
        echo "Logging in..."
        ADMIN_PASS=$(cat ${config.sops.secrets."jellyfin-admin-password".path})
        export ADMIN_PASS
        LOGIN_CODE=$(jq -n '{username: "admin", password: $ENV.ADMIN_PASS}' \
          | curl -s -c "$COOKIE" -X POST \
              -H "Content-Type: application/json" \
              --data-binary @- \
              -w "%{http_code}" -o /dev/null \
              "$SEERR/api/v1/auth/jellyfin")

        if [ "$LOGIN_CODE" != "200" ] && [ "$LOGIN_CODE" != "201" ]; then
          echo "Login failed (HTTP $LOGIN_CODE)" >&2; exit 1
        fi
        echo "Logged in."

        # Sync libraries from Jellyfin and enable all of them
        echo "Syncing libraries..."
        LIBS=$(curl -s -b "$COOKIE" "$SEERR/api/v1/settings/jellyfin/library?sync=true")
        echo "Found: $(echo "$LIBS" | jq -r '.[].name' | tr '\n' ' ')"
        LIBRARY_IDS=$(echo "$LIBS" | jq -r '.[].id' | paste -sd,)

        if [ -n "$LIBRARY_IDS" ]; then
          curl -sf -b "$COOKIE" \
            "$SEERR/api/v1/settings/jellyfin/library?enable=$LIBRARY_IDS" > /dev/null
          echo "Libraries enabled: $LIBRARY_IDS"
        else
          echo "Warning: no libraries found"
        fi

        # Mark setup as complete (dismisses wizard permanently)
        curl -sf -b "$COOKIE" -X POST "$SEERR/api/v1/settings/initialize" > /dev/null

        rm -f "$COOKIE"
        echo "Jellyseerr setup complete."
      '';
    };

    # Jellyfin ships with TheMovieDb as the only TV provider, and TMDB models
    # some anime as ONE long season: JUJUTSU KAISEN is a single "Season 1" of
    # 59 episodes there, while TVDB (and therefore Sonarr, and therefore the
    # folder layout) splits the same 59 into 24 / 23 / 12. Jellyfin then looks
    # up "Season 2, Episode 1", finds nothing in TMDB, and degrades badly:
    # no season posters at all, and 300x169 / 9 KB episode thumbnails against
    # 1920x1080 for season 1. Adding TheTVDB fixes every season TMDB cannot
    # describe. Found 2026-08-28.
    #
    # TheTVDB is added BELOW TheMovieDb everywhere, deliberately — TMDB stays
    # authoritative so nothing that already looks right can change, and TVDB
    # only fills the gaps. But it must sit ABOVE "The Open Movie Database",
    # "Embedded Image Extractor" and "Screen Grabber" in the episode image
    # order: those are what were producing the 300x169 images, so a TVDB entry
    # below them would never win.
    #
    # EnableEmbeddedTitles is forced off. It is on by default and makes
    # Jellyfin take the episode name from the mkv container title tag, which
    # release groups stuff with their own naming — the JJK season 2/3 files
    # carry titles like "Jujutsu Kaisen (2023) - S02E01 - Hidden Inventory"
    # and "[AnoZu] JUJUTSU KAISEN - S03E01 - Execution", and those were being
    # shown verbatim in the UI. Season 1's files happen to have an empty title
    # tag, which is the only reason that season looked correct.
    systemd.services.jellyfin-providers = {
      description = "Install TheTVDB and pin Jellyfin TV metadata/image provider order";
      after    = [ "jellyfin.service" "network-online.target" ];
      wants    = [ "jellyfin.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Best-effort, like arr-policy: each library is tried and reported on
        # its own. Without this, the `set -e` NixOS prepends to every unit
        # script aborted the whole run on the first jq or curl that failed
        # inside the library loop.
        set +e
        set -u
        JF=http://localhost:8096
        JK=$(cat ${config.sops.secrets."jellyfin-api-key".path})
        AUTH="Authorization: MediaBrowser Token=$JK"

        # Fails the unit if Jellyfin never answers. This used to log "skipping"
        # and exit 0, which left the unit green with nothing applied.
        ${waitForHttp { name = "Jellyfin"; url = "$JF/System/Info"; tries = 60; interval = 5; curlArgs = ''-H "$AUTH"''; }}

        # --- TheTVDB plugin ------------------------------------------------
        # Installing it needs a restart before the fetcher becomes selectable,
        # so do that first and re-wait. Guarded so this is a no-op after the
        # first successful run.
        if ! curl -sf -m 15 -H "$AUTH" $JF/Plugins | jq -e '.[]|select(.Name=="TheTVDB")' >/dev/null; then
          # Pick the newest catalogue version whose targetAbi the running
          # server satisfies, rather than pinning a version that will rot.
          SRV=$(curl -sf -m 15 -H "$AUTH" $JF/System/Info | jq -r .Version)
          PKG=$(curl -sf -m 30 -H "$AUTH" $JF/Packages | jq -r --arg s "$SRV" '
            def norm: split(".")|map(tonumber)|(.+[0,0,0,0])[0:4];
            .[] | select(.name=="TheTVDB")
            | .guid as $g
            | [ .versions[] | select((.targetAbi|norm) <= ($s|norm)) ][0]
            | select(.!=null) | "\(.version) \($g)"')
          if [ -n "$PKG" ]; then
            set -- $PKG
            if curl -sf -m 60 -X POST -H "$AUTH" \
                 "$JF/Packages/Installed/TheTVDB?version=$1&assemblyGuid=$2" >/dev/null; then
              echo "jellyfin-providers: installed TheTVDB $1, restarting Jellyfin"
              sleep 10
              systemctl restart jellyfin
              ${waitForHttp { name = "Jellyfin (after restart)"; url = "$JF/System/Info"; tries = 60; interval = 5; curlArgs = ''-H "$AUTH"''; }}
            else
              echo "jellyfin-providers: FAILED to install TheTVDB"
            fi
          else
            echo "jellyfin-providers: no TheTVDB build compatible with $SRV"
          fi
        fi

        # --- Library options -----------------------------------------------
        VF=$(curl -sf -m 15 -H "$AUTH" $JF/Library/VirtualFolders) || exit 0
        echo "$VF" | jq -c '.[]|select(.CollectionType=="tvshows")' | while read -r LIB; do
          NAME=$(echo "$LIB" | jq -r .Name)
          WANT=$(echo "$LIB" | jq -c '{Id:.ItemId, LibraryOptions:(.LibraryOptions
            | .EnableEmbeddedTitles=false
            | .TypeOptions|=map(
                if .Type=="Series" then
                  .MetadataFetchers=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .MetadataFetcherOrder=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .ImageFetchers=["TheMovieDb","TheTVDB"]
                  | .ImageFetcherOrder=["TheMovieDb","TheTVDB"]
                elif .Type=="Season" then
                  .MetadataFetchers=["TheMovieDb","TheTVDB"]
                  | .MetadataFetcherOrder=["TheMovieDb","TheTVDB"]
                  | .ImageFetchers=["TheMovieDb","TheTVDB"]
                  | .ImageFetcherOrder=["TheMovieDb","TheTVDB"]
                elif .Type=="Episode" then
                  .MetadataFetchers=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .MetadataFetcherOrder=["TheMovieDb","TheTVDB","The Open Movie Database"]
                  | .ImageFetchers=["TheMovieDb","TheTVDB","The Open Movie Database","Embedded Image Extractor","Screen Grabber"]
                  | .ImageFetcherOrder=["TheMovieDb","TheTVDB","The Open Movie Database","Embedded Image Extractor","Screen Grabber"]
                else . end))}')
          # Only POST when something actually differs — this unit runs on every
          # boot and a no-op must stay a no-op.
          CUR=$(echo "$LIB" | jq -c '{Id:.ItemId, LibraryOptions:.LibraryOptions}')
          if [ "$CUR" != "$WANT" ]; then
            echo "$WANT" | curl -sf -m 30 -X POST -H "$AUTH" \
                   -H 'Content-Type: application/json' --data-binary @- \
                   "$JF/Library/VirtualFolders/LibraryOptions" >/dev/null \
              && echo "jellyfin-providers: updated provider order on library $NAME" \
              || echo "jellyfin-providers: FAILED to update library $NAME"
          fi
        done

        echo "jellyfin-providers: done"
      '';
    };

    # Intel QSV / VAAPI runtime for Jellyfin hardware transcoding (UHD 730 / Gen13).
    # Without these, ffmpeg's "vaapi=va:/dev/dri/renderD128,driver=iHD" fails with
    # "unknown libva error" and clients see "fatal playback error".
    # No enable32Bit: that is for 32-bit games/Wine on a desktop. Jellyfin's
    # ffmpeg is 64-bit, and on a headless box it only pulled in i686 Mesa.
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver        # iHD VAAPI driver (required by QSV)
        intel-compute-runtime     # OpenCL — needed for tonemapping filters
        vpl-gpu-rt                # Intel oneVPL runtime (modern QSV)
        libvdpau-va-gl
      ];
    };

    sops.secrets."jellyseerr-api-key"       = {};
    sops.secrets."jellyfin-api-key"         = {};
    sops.secrets."jellyfin-admin-password"  = {};

  };
}
