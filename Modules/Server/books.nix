{ ... }: {
  # Asgard — books: Audiobookshelf (the server), Shelfarr (the request portal)
  # and books-setup, which wires the two to Prowlarr and SABnzbd.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    inherit (import ./_lib.nix { inherit pkgs; }) waitForHttp;
    inherit (config.asgard) vethHostIp;
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# BOOKS — Audiobookshelf (server) + Shelfarr (request portal)
# Audiobookshelf: port 13378 — serves ebooks + audiobooks (Jellyfin-style UI)
# Shelfarr:       port 5056  — Jellyseerr-style request portal for books
#   Connects to Prowlarr (search) + SABnzbd (download) → delivers to ABS
#
# All the wiring between the three (ABS root user + libraries + API key,
# Shelfarr's indexer / download client / ABS connection) is done by
# books-setup.service below — there is no post-boot clicking.
# ══════════════════════════════════════════════════════════════════════════════

    # Audiobookshelf — ebook + audiobook server
    virtualisation.oci-containers.containers.audiobookshelf = {
      # ⭐ Pinned by digest 2026-11-24 (was `:latest`). This is the digest it was
      # ALREADY running — captured from `podman images --digests` on the box — so
      # the pin changed nothing at the time it was made. That is the whole point:
      # a tag is resolved once on first pull and podman never re-checks it, so
      # `:latest` here meant "whatever was pulled months ago" with no version in
      # the config and no way back. See `Claude/next-up.md` → image pinning.
      #
      # ⚠️ This image was already ~5 months old when pinned, so the staleness is
      # now explicit rather than fixed. Shelfarr proved what that costs: a frozen
      # image misses upstream DATA migrations, so the app keeps values upstream
      # has retired. ABS has far less settings-in-migrations surface, but a bump
      # is still owed.
      #
      # ⚠️ This is the amd64 MANIFEST digest, not the multi-arch INDEX digest
      # used for Shelfarr above. Both pin fine; this one is arch-specific, which
      # is correct for Asgard. Do not mistake one form for the other when bumping.
      #
      # To bump: pull the new digest, then back up `/var/lib/audiobookshelf`
      # first — the library DB lives there and ABS runs its own migrations.
      image = "ghcr.io/advplyr/audiobookshelf@sha256:1eef6716183c52abafe5405e7d6be8390248ecd59c7488c44af871757ac8fc4d";
      ports = [ "13378:80" ];
      volumes = [
        "/var/lib/audiobookshelf/config:/config"
        "/var/lib/audiobookshelf/metadata:/metadata"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
      ];
      environment = {
        TZ = "Australia/Sydney";
      };
      autoStart = true;
    };

    # Shelfarr — Jellyseerr-style book request portal
    # RAILS_MASTER_KEY is auto-generated on first run and stored in /var/lib/shelfarr.
    # As long as the volume persists, the key is preserved across rebuilds.
    virtualisation.oci-containers.containers.shelfarr = {
      # ⚠️ PINNED BY DIGEST, deliberately not `:latest`. A tag is resolved once on
      # the first pull and podman never re-checks it, so this container ran the
      # 2026-06-15 build (revision d56a07ea) until 2026-11-23 while reading as
      # up to date in every way anyone looks.
      #
      # ⭐ That is worse than merely missing features here: Shelfarr keeps some
      # DEFAULTS in **data migrations**, so a stale image holds *retired values*
      # in `settings`. `zlibrary_url` sat on three dead domains for months
      # because migration 20261012090000 had never run — enabled, configured,
      # and resolving nowhere. See the zlibrary_url note below, which is pinned
      # here for exactly that reason.
      #
      # Bumped 2026-11-23: 2026-06-15 (d56a07ea) → 2026.11.16.1 (985df977).
      # This is the multi-arch *index* digest, so it stays correct per-platform.
      # To bump, resolve the new index digest and paste it here:
      #   TOK=$(curl -s 'https://ghcr.io/token?scope=repository:pedro-revez-silva/shelfarr:pull&service=ghcr.io' | jq -r .token)
      #   curl -sI -H "Authorization: Bearer $TOK" \
      #     -H 'Accept: application/vnd.oci.image.index.v1+json' \
      #     https://ghcr.io/v2/pedro-revez-silva/shelfarr/manifests/latest \
      #     | grep -i docker-content-digest
      #
      # ⚠️ After a bump, re-read the `Setting` keys written by books-setup below.
      # A migration that renames one turns that write into a no-op against a key
      # the app no longer reads — which fails silently, the same way everything
      # else in this pipeline fails. The `shelfarr: indexer=… ok=… sab=…` line at
      # the end of books-setup is the check.
      #
      # ⚠️ A bump runs five months of migrations against the SQLite DB in the
      # storage volume. Back it up first — the DB is owned by rock, so this
      # needs no root, and `-wal` is load-bearing (the main file alone is an
      # incomplete snapshot):
      #   cp /var/lib/shelfarr/production.sqlite3{,-wal,-shm} ~/some-backup-dir/
      image = "ghcr.io/pedro-revez-silva/shelfarr@sha256:97270513a75354d1b8cf2fa68f22cd31f021d03c3695186437e448f2a9255d9e";
      ports = [ "5056:4000" ];
      volumes = [
        "/var/lib/shelfarr:/rails/storage"
        "/data/media/audiobooks:/audiobooks"
        "/data/media/books:/ebooks"
        "/downloads:/downloads"
      ];
      environment = {
        PUID                = "1000";
        # The real `media` gid. This was a literal "1001", copied from a
        # `users.groups.media.gid = 1001` that never took effect — nixflix
        # mkForces the group to 169 — so the container ran in a group that
        # does not exist on the host. That is also why /data/media/books and
        # audiobooks are 0777 (see the tmpfiles rules).
        PGID                = toString config.users.groups.media.gid;
        SOLID_QUEUE_IN_PUMA = "1";
        HTTP_PORT           = "4000";  # Go proxy port — must differ from Rails/Puma (3000)
      };
      autoStart = true;
    };

    # ── books-setup.service ───────────────────────────────────────────────────
    # Makes the ebook pipeline reproducible. Until 2026-09-17 this was a
    # "Post-boot (one-time)" comment telling you to click through two web UIs —
    # and it had never been done, so Audiobookshelf sat uninitialised and
    # Shelfarr had zero indexers for three months while Glance showed both
    # green. A running container is not a working pipeline.
    #
    # Idempotent, runs on every rebuild, converges a fresh install:
    #   1. Audiobookshelf — create the root user, then the two libraries
    #   2. Audiobookshelf — mint an API key for Shelfarr
    #   3. Shelfarr       — point it at Prowlarr, SABnzbd and Audiobookshelf
    #
    # ⚠️ Shelfarr's config MUST go through `bin/rails runner`, never sqlite3.
    # `AcquisitionProvider` and `DownloadClient` declare `encrypts :api_key`, so
    # a raw SQL insert stores the key in plaintext and Rails then throws on
    # decrypt. The ActiveRecord::Encryption keys live in the storage volume
    # (`.encryption_keys`), alongside `.secret_key_base` — both are generated by
    # the container's entrypoint on first run and must be sourced before
    # `bin/rails` will even boot.
    #
    # ⚠️ Prowlarr is NOT an `AcquisitionProvider`. That model is for *custom*
    # direct-download providers and its `test_connection` returns false for a
    # Prowlarr URL. Prowlarr is configured through `Setting` rows
    # (`indexer_provider` / `prowlarr_url` / `prowlarr_api_key`) instead. Getting
    # this wrong looks like a working config that silently finds nothing.
    #
    # ⚠️ `prowlarr_url` is `http://10.200.1.1:9696` — the veth host address,
    # `asgard.vethHostIp` — and is deliberately DIFFERENT from every other URL here.
    # Shelfarr builds each result's download_url from it and gives SABnzbd
    # `mode=addurl`, so SAB fetches the NZB itself. SAB lives in the Mullvad
    # network namespace and is *not* a podman container, so it cannot resolve
    # `host.containers.internal`. 10.200.1.1 is the one address reachable from
    # both the Shelfarr container and the VPN namespace (both verified 302).
    # Symptom when wrong: the item sits in SAB at 0% showing "Fetch NZB from
    # URL" with an exponentially growing WAIT, and never fails outright.
    # This also needs `veth-vpn-br` in `firewall.trustedInterfaces` (default.nix),
    # without which the namespace can ping the host but every TCP connect drops.
    #
    # ⚠️ QUOTING: the Ruby below is passed as `bin/rails runner "..."` nested
    # inside `sh -c '...'`. Inside that Ruby block you must avoid **double
    # quotes**, **backticks** and **apostrophes** — a double quote ends the
    # runner argument, a backtick becomes command substitution, and an
    # apostrophe ends the sh -c string. All three produce confusing build-time
    # or run-time syntax errors far from the real edit. Keep commentary that
    # needs punctuation out here, at Nix level, where it never reaches a shell.
    systemd.services.books-setup = {
      description = "Configure Audiobookshelf + Shelfarr (idempotent)";
      # `prowlarr.service` is here because step 4 ends by calling
      # `IndexerClient.test_connection` against it. Without the ordering it was
      # a coin toss: on the 2026-11-23 boot books-setup probed Prowlarr three
      # seconds before Prowlarr listened and logged `indexer=prowlarr ok=false`
      # on a perfectly healthy Prowlarr — a false negative in the one line that
      # exists to prove the pipeline works. Ordering alone is not enough either;
      # see the waitForHttp in step 4.
      after = [ "podman-shelfarr.service" "podman-audiobookshelf.service" "flaresolverr.service" "prowlarr.service" ];
      wants = [ "podman-shelfarr.service" "podman-audiobookshelf.service" "flaresolverr.service" "prowlarr.service" ];
      wantedBy = [ "multi-user.target" ];
      # Retry a failed run, but give up after 5 tries instead of looping forever.
      # These are UNIT settings: under [Service] StartLimitBurst has no interval
      # to count against, so it never tripped. 30 min rather than the 10 its
      # siblings use, because one attempt can legitimately spend 5 min waiting
      # for Audiobookshelf — five slow attempts must still land in one window.
      unitConfig = {
        RequiresMountsFor = [ "/data/media" ];
        StartLimitIntervalSec = 1800;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      path = with pkgs; [ curl jq gnugrep gnused coreutils podman ];
      script = ''
        # Fail fast, on purpose. This was written as `set -uo pipefail` — but
        # NixOS prepends `set -e` to every unit script, so it has always been
        # fail-fast in practice, and that is the right behaviour here: every
        # step feeds the next (no token, no libraries, no API key → a Shelfarr
        # that "succeeds" with half a config), and Restart=on-failure above is
        # what turns an early exit into a retry. Spelled out so it is not an
        # accident any more.
        set -euo pipefail
        ABS=http://localhost:13378

        ${waitForHttp { name = "Audiobookshelf"; url = "$ABS/status"; tries = 60; interval = 5; }}

        U=$(cat ${config.sops.secrets."admin-username".path})
        P=$(cat ${config.sops.secrets."admin-password".path})
        # Credentials go into JSON via jq reading the environment, never spliced
        # in by hand: a quote in the password used to break the body, and on the
        # command line it was readable by anyone in /proc/<pid>/cmdline.
        export U P
        creds() { jq -n '{username: $ENV.U, password: $ENV.P}'; }

        # ── 1. root user (only if the server has never been initialised) ──
        if ! curl -sf --max-time 10 "$ABS/status" | grep -q '"isInit":true'; then
          echo "ABS: initialising root user"
          creds | jq '{newRoot: .}' \
            | curl -sf --max-time 20 -X POST "$ABS/init" -H 'Content-Type: application/json' \
                --data-binary @- >/dev/null
        fi

        # `|| true`: under set -e a failed login would abort inside the command
        # substitution, before the explicit message below could say why.
        TOK=$(creds | curl -sf --max-time 20 -X POST "$ABS/login" -H 'Content-Type: application/json' \
          --data-binary @- \
          | grep -oE '"(accessToken|token)":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//') || true
        [ -n "$TOK" ] || { echo "ABS: login failed"; exit 1; }

        # ── 2. libraries, keyed by name so a re-run never duplicates them ──
        LIBS=$(curl -sf --max-time 20 -H "Authorization: Bearer $TOK" "$ABS/api/libraries")
        mklib() { # $1 = name, $2 = container path, $3 = icon
          echo "$LIBS" | grep -q "\"name\":\"$1\"" && return 0
          echo "ABS: creating library $1 -> $2"
          curl -sf --max-time 20 -X POST "$ABS/api/libraries" \
            -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"$1\",\"folders\":[{\"fullPath\":\"$2\"}],\"mediaType\":\"book\",\"icon\":\"$3\"}" >/dev/null
        }
        mklib Ebooks /ebooks book
        mklib Audiobooks /audiobooks audiobookshelf

        LIBS=$(curl -sf --max-time 20 -H "Authorization: Bearer $TOK" "$ABS/api/libraries")
        libid() { echo "$LIBS" | sed 's/},{/}\n{/g' | grep "\"name\":\"$1\"" \
          | grep -oE '"id":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//'; }
        EBOOK_LIB=$(libid Ebooks)
        AUDIO_LIB=$(libid Audiobooks)

        # ── 3. API key for Shelfarr ──
        # The key's plaintext is only ever returned at creation, so it cannot be
        # re-read later. Only mint a new one when Shelfarr has no usable key.
        HAVE=$(podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "print Setting.find_by(key: %q(audiobookshelf_api_key))&.value.to_s.length"' 2>/dev/null || echo 0)
        if [ "''${HAVE:-0}" -lt 20 ]; then
          MYID=$(curl -sf --max-time 20 -H "Authorization: Bearer $TOK" "$ABS/api/me" \
            | grep -oE '"id":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//')
          ABS_KEY=$(curl -sf --max-time 20 -X POST "$ABS/api/api-keys" \
            -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"shelfarr\",\"userId\":\"$MYID\",\"isActive\":true}" \
            | grep -oE '"apiKey":"[^"]+"' | head -1 | sed 's/.*:"//;s/"//')
          echo "ABS: minted a new API key for Shelfarr"
        else
          ABS_KEY=""   # keep whatever Shelfarr already holds
          echo "ABS: Shelfarr already holds an API key, leaving it alone"
        fi

        # ── 4. Shelfarr ──
        # Wait for Prowlarr to ANSWER, not merely to have been started. A systemd
        # unit counts as started well before this ASP.NET app is listening, so
        # `after = prowlarr.service` on its own still loses the race. /ping is a
        # plain 200 and needs no API key — `/` is a 302 and `/api/v1/health` is a
        # 401, so neither is a clean readiness probe.
        ${waitForHttp { name = "Prowlarr"; url = "http://localhost:9696/ping"; tries = 30; interval = 2; }}

        podman exec \
          -e PROWLARR_KEY="$(cat ${config.sops.secrets."prowlarr-api-key".path})" \
          -e SAB_KEY="$(cat ${config.sops.secrets."sabnzbd-api-key".path})" \
          -e ZLIB_EMAIL="$(cat ${config.sops.secrets."zlibrary-email".path})" \
          -e ZLIB_PASS="$(cat ${config.sops.secrets."admin-password".path})" \
          -e ABS_KEY="$ABS_KEY" \
          -e ABS_URL="http://host.containers.internal:13378" \
          -e ABS_EBOOK_LIB="$EBOOK_LIB" \
          -e ABS_AUDIO_LIB="$AUDIO_LIB" \
          shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "
            H = %q(http://host.containers.internal)
            d = DownloadClient.find_or_initialize_by(name: %q(SABnzbd))
            d.assign_attributes(client_type: %q(sabnzbd), url: %(#{H}:8080),
              api_key: ENV.fetch(%q(SAB_KEY)), category: %q(books),
              download_path: %q(/downloads), enabled: true, priority: 0)
            changed = 0
            # api_key is encrypted non-deterministically, so re-assigning the
            # same plaintext still reports as changed. Counting it would bounce
            # the container on every single rebuild, so ignore that one field.
            changed += 1 if d.new_record? || d.changed.any? { |a| a != %q(api_key) }
            d.save!
            vals = {
              %q(indexer_provider)  => %q(prowlarr),

              # veth host address, NOT host.containers.internal. See the note
              # above the service definition - do not change without reading it.
              %q(prowlarr_url)      => %q(http://${vethHostIp}:9696),
              %q(prowlarr_api_key)  => ENV.fetch(%q(PROWLARR_KEY)),
              %q(audiobookshelf_url) => ENV.fetch(%q(ABS_URL)),
              %q(audiobookshelf_ebook_library_id)     => ENV.fetch(%q(ABS_EBOOK_LIB)),
              %q(audiobookshelf_audiobook_library_id) => ENV.fetch(%q(ABS_AUDIO_LIB)),
              # Container -> host, so NOT localhost. Shelfarr uses this for
              # Cloudflare-protected book indexers the same way Suwayomi does
              # for manga sources.
              %q(flaresolverr_url) => %(#{H}:8191),

              # Jellyseerr-style behaviour: a request should grab on its own.
              # Upstream ships this OFF, which leaves every request parked at
              # status=pending forever waiting for someone to hand-pick a
              # release in the UI — it looks like the download silently failed.
              %q(auto_select_enabled) => %q(true),

              # Upstream puts torrent FIRST. SABnzbd is the only download client
              # here, so that order makes Shelfarr prefer releases it physically
              # cannot fetch. Built via to_json so no literal double quotes
              # appear in this block.
              #
              # ⭐⭐ DIRECT (Z-Library) BEFORE USENET from 2026-11-23. This list is
              # ordered by TYPE and type beats score outright, so whatever is
              # first here wins even against a better-scoring result of the other
              # type. Three Mistborn books proved why usenet-first is wrong for
              # ebooks:
              #
              #   The Well of Ascension  Repair failed, not enough repair blocks (2 short)
              #   The Bands of Mourning  Repair failed, not enough repair blocks (3 short)
              #   The Lost Metal         Aborted, cannot be completed
              #
              # Ebook NZBs are a few MB posted years ago; they lose articles to
              # retention and par2 cannot rebuild them. ⚠️ Each of those reached
              # **100% progress** and still failed — SAB fetched the articles and
              # the *repair* came up short, so it-downloaded and it-worked are
              # different questions. Meanwhile every one of the three had a
              # Z-Library copy scoring 95 that was never tried, because usenet
              # outranked it on type.
              #
              # Z-Library is a direct HTTP fetch of a single file: no articles, no
              # par2, nothing to be short of. It is also far deeper for books than
              # three general-purpose Usenet indexers.
              #
              # ⚠️ PRIVACY: this moves the DEFAULT path for book downloads off the
              # VPN. A direct download is fetched by Shelfarr itself over the
              # normal WAN — it does NOT go through the Mullvad namespace that
              # SABnzbd sits in (NetworkNamespacePath, downloads.nix). That was
              # already true of Z-Library as a fallback; it is now the common case.
              #
              # ⚠️ Z-Library enforces a per-account DAILY DOWNLOAD LIMIT. When it
              # is reached, results still appear and the fetch fails. Usenet stays
              # second rather than being removed precisely so there is somewhere to
              # fall through to — but note that a failed pick does NOT currently
              # fall through on its own; see step 5.
              %q(preferred_download_types) => [%q(direct), %q(usenet)].to_json,

              # Upstream threshold is 90 and nothing reached it: the best real
              # match for a book scored 88, so every request stalled awaiting
              # manual selection. Lowered again 85 -> 80 on 2026-11-14 after
              # This Inevitable Ruin (request 10) parked with the message
              # Search results found but none matched auto-select criteria,
              # while holding SIX copies of the right book, including a RETAIL
              # EPUB. Its scores were 83, 83, 64, 63, 63, 63 -- the correct
              # release topped out at 83 against a gate of 85.
              #
              # 80 is chosen for the GAP, not for the miss: there is nothing
              # between 83 and 64 in that result set, so the band is wide and
              # empty and 80 does not sit near any junk. min_match_confidence
              # stays at 50, so weak matches are still refused outright.
              #
              # NOTE a dotted scene filename (Author.Title.2026.RETAIL.EPUB.
              # eBook-CTO) scores far WORSE on title matching than a plain
              # Author - [Series 07] - Title, even though it is the better
              # file and names its format. So the top-scoring release is often
              # not the format-explicit one, and raising ebook_preferred_formats
              # cannot rescue a title-match penalty. If auto-select ever starts
              # taking junk, tighten this back before touching the formats.
              %q(auto_select_confidence_threshold) => %q(80),

              # Ships empty, which leaves format unscored. Naming the formats
              # lifted the winning result from 88 to 100, and is what makes the
              # threshold comfortable rather than marginal.
              #
              # EPUB ONLY from 2026-11-14. Three settings, three strengths, per
              # upstream FormatPreferenceService:
              #   rejected  -35 AND auto_select_allowed = false
              #   approved  an ALLOWLIST: anything not listed takes -20 and is
              #             likewise barred from auto-select (empty = no effect)
              #   preferred scoring only: +12 for the first entry, then +8/+4/+2,
              #             and -6 for a format that is not preferred at all
              #
              # approved is used rather than rejected because it is the positive
              # statement (epub, full stop) and it still LISTS a non-epub result
              # for manual selection instead of burying it -- which matters,
              # because some books exist in no other format.
              #
              # ⚠ The cost is real: The Dungeon Anarchist-s Cookbook returned
              # exactly ONE result and it was azw3. Under this policy a book
              # like that will never auto-download; it waits for an epub to
              # appear, or for someone to pick the azw3 by hand.
              #
              # Why epub at all: Audiobookshelf extracts embedded covers from
              # epub but NOT from Mobipocket/KF8 (azw3), so an azw3 lands with
              # no cover art and reads worse on the reader.
              %q(ebook_preferred_formats) => [%q(epub)].to_json,
              # Z-Library, enabled 2026-11-14. A second acquisition source
              # because the three Prowlarr indexers are general-purpose Usenet
              # and their ebook coverage is shallow: The Dungeon Anarchist-s
              # Cookbook returned exactly ONE result and it was azw3, which the
              # epub-only policy above now refuses to auto-select.
              #
              # ⚠ This is a DIRECT download, so Shelfarr fetches it itself over
              # the normal WAN. It does NOT go through the Mullvad namespace
              # that SABnzbd sits in (NetworkNamespacePath in downloads.nix).
              #
              # ⚠ The mirror list rots: z-library moves domains often, which is
              # why the setting holds several, and why it is pinned HERE rather
              # than left to the image. Upstream ships a default list and then
              # revises it by MIGRATION: 20261012090000 replaced the three
              # z-library.sk/.bz/.rs domains with six newer ones in front.
              #
              # Our container is the 2026-06-15 build - its newest applied
              # migration is 20260607120000 - so that October migration has
              # NEVER RUN here. Verified 2026-11-15: the stored value was
              # byte-identical to that migration-s PREVIOUS_DEFAULT, i.e. the
              # three retired domains and nothing else. Z-Library would have
              # been enabled and configured and still resolved nowhere.
              #
              # Pinning it also means a newer image cannot quietly fix this for
              # us, so if Z-Library stops returning results, re-copy this list
              # from upstream db/migrate instead of assuming the image did it.
              #
              # PROVEN 2026-11-15: first search after this landed logged
              # ZLibraryClient Login succeeded via z-lib.gd - the FIRST of the
              # added domains, none of the three it previously held. Request 10
              # went from 6 results to 23 and completed.
              %q(zlibrary_url) => [
                %q(https://z-lib.gd), %q(https://z-lib.gl),
                %q(https://z-library.ec), %q(https://zlib.bz),
                %q(https://article.sk), %q(https://articles.sk),
                %q(https://z-library.sk), %q(https://z-library.bz),
                %q(https://z-library.rs)
              ].join(10.chr),
              %q(zlibrary_enabled) => %q(true),
              %q(zlibrary_email) => ENV.fetch(%q(ZLIB_EMAIL)),
              %q(zlibrary_password) => ENV.fetch(%q(ZLIB_PASS)),
              %q(ebook_approved_formats) => [%q(epub)].to_json,

              # Search the moment a request is made, instead of up to 5 minutes
              # later. Upstream RequestCreationService#after_create enqueues the
              # SearchJob only when
              #   immediate_search_enabled || (!user_admin? && auto_approve_requests?)
              # and it ships the first as false. The rock account is role=1
              # (admin), so NEITHER branch fired and every request sat at
              # status=pending until the 5-minute RequestQueueJob sweep swept it
              # up. Measured 2026-11-14: three books requested at 10:27-10:28 had
              # zero search_results and zero request_events until 10:30:07, then
              # all three completed in 13 seconds.
              #
              # This is indistinguishable from the auto_select_enabled fault
              # above - same pending status, same nothing-is-happening - but it
              # is the opposite half of the pipeline: auto_select picks a release
              # ONCE a search has run, this decides whether a search runs at all.
              #
              # NOTE no apostrophes anywhere in this block. The whole rails
              # runner payload is inside sh -c SINGLE quotes, so one apostrophe
              # closes the shell string and the build dies with a shell syntax
              # error on the following Ruby line.
              %q(immediate_search_enabled) => %q(true),

              # ===== Metadata providers - pinned 2026-11-24 =====
              #
              # The 2026.11.16.1 bump INTRODUCED these keys, so they arrived on
              # upstream defaults: hardcover first in the priority list, with
              # hardcover_enabled true and an EMPTY hardcover_api_token. That
              # broke Search outright - Unable to connect to metadata service -
              # and NOT in the way it reads: metadata lookup identifies the book
              # and runs BEFORE any indexer is touched, so no search ran at all
              # and neither Prowlarr nor Z-Library was ever involved.
              #
              # Measured from Asgard 2026-11-24: openlibrary 200 and needs no
              # token, api.hardcover.app reachable but wants one, googleapis 429
              # without an API key. So Open Library leads, Google Books stays as
              # a second chance, and Hardcover is off until a token exists.
              #
              # These three are pinned even though we never chose to change them
              # from a working value. That is the point: an UNPINNED key is one a
              # future bump can re-default underneath us, which is exactly what
              # happened here. books-setup should pin every setting the pipeline
              # depends on, not only the ones it had to change.
              %q(metadata_provider_priority) => %q(openlibrary,google_books,comic_vine),
              %q(open_library_enabled) => %q(true),
              %q(hardcover_enabled) => %q(false)
            }
            k = ENV[%q(ABS_KEY)].to_s
            vals[%q(audiobookshelf_api_key)] = k unless k.empty?
            vals.each { |key, v| s = Setting.find_or_initialize_by(key: key); s.value = v; changed += 1 if s.changed?; s.save! }
            IndexerClient.reset_all_connections!
            puts %(SETTINGS_CHANGED=#{changed})
            puts %(shelfarr: indexer=#{IndexerClient.provider} ok=#{IndexerClient.test_connection} sab=#{DownloadClient.first.adapter.test_connection})
          "' | tee /tmp/books-setup-out

        # ── 5. Restart Shelfarr if anything actually changed ───────────────────
        # Settings are read ONCE at boot and cached in the long-lived Puma and
        # SolidQueue processes. Writing the DB from a short-lived `rails runner`
        # updates the row but NOT the running app — and
        # `IndexerClient.reset_all_connections!` only resets the runner process,
        # not the workers that serve requests.
        #
        # Without this restart the service reports success, the DB looks right,
        # and the app keeps emitting the OLD value indefinitely. That is exactly
        # how a corrected `prowlarr_url` kept producing unreachable NZB URLs and
        # books kept stalling in SAB on "Fetch NZB from URL".
        #
        # Conditional so a no-op rebuild does not bounce the container.
        if grep -qE 'SETTINGS_CHANGED=[1-9]' /tmp/books-setup-out; then
          echo "books-setup: settings changed, restarting shelfarr to clear its cache"
          ${pkgs.systemd}/bin/systemctl restart podman-shelfarr

          ${waitForHttp { name = "Shelfarr"; url = "http://localhost:5056/session/new"; tries = 24; interval = 5; }}

          # Stored `SearchResult.download_url` rows keep whatever prowlarr_url
          # was in effect when that search ran. A URL change therefore strands
          # every in-flight request on a dead link — and because SAB retries a
          # bad fetch forever with a growing WAIT rather than failing, it looks
          # identical to the bug having never been fixed. Drop them and reset
          # those requests so the app re-searches and rebuilds the links.
          podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "
            good = Setting.find_by(key: %q(prowlarr_url))&.value.to_s
            stale = SearchResult.where.not(download_url: nil).reject { |s| s.download_url.start_with?(good) }
            if stale.any?
              reqs = stale.map(&:request_id).uniq
              stale.each(&:destroy)
              Request.where(id: reqs).where.not(status: %q(completed)).update_all(status: %q(pending))
              # Resetting to pending is not enough on its own — nothing re-scans
              # pending requests, so they would sit there forever looking like a
              # silent failure. Re-enqueue the search for each one.
              Request.where(id: reqs, status: %q(pending)).each { |q| SearchJob.perform_later(q.id) }
              puts %(books-setup: purged #{stale.size} stale-host search results, re-queued #{reqs.size} requests)
            end
          "' || true

          # Un-park requests whose download FAILED, so a settings change actually
          # reaches them. A failed grab is a THIRD terminal state, distinct from
          # the two pending ones documented above, and the only one nothing ever
          # recovers from by itself:
          #
          #   status = failed, attention_needed = true,
          #   next_retry_at = NULL, retry_count = 0
          #
          # ⭐ With next_retry_at NULL and retry_count 0, max_retries (10) and
          # retry_base_delay_hours (24) never come into play at all — the request
          # is parked permanently, which is indistinguishable from auto-download
          # being broken. That is what three Mistborn books did for six days.
          #
          # ⭐ Shelfarr also never DEMOTES the release that failed:
          # search_results.status only ever holds 1 (selected) or 2 (everything
          # else), with no rejected state, so re-dispatching a parked request
          # re-grabs the identical dead NZB. Request 14 was sent to SAB twice
          # against the same search_result_id and failed the same way both times.
          # Hence destroying the stored results rather than just resetting the
          # request: the next search rebuilds them and re-picks under the current
          # preferred_download_types order.
          #
          # Selected on attention_needed rather than on status, so it does not
          # depend on which integer the `failed` enum happens to be — that can
          # move under an image bump.
          #
          # Guarded by SETTINGS_CHANGED, so this fires once after a real change
          # and a no-op rebuild never re-searches anything. A book that genuinely
          # cannot be found is therefore retried once per settings change, not in
          # a loop.
          podman exec shelfarr sh -c '. /rails/storage/.encryption_keys; export SECRET_KEY_BASE=$(cat /rails/storage/.secret_key_base); cd /rails && ./bin/rails runner "
            stuck = Request.where(attention_needed: true).where.not(status: %q(completed))
            if stuck.any?
              ids = stuck.pluck(:id)
              SearchResult.where(request_id: ids).each(&:destroy)
              Request.where(id: ids).update_all(status: %q(pending), attention_needed: false, next_retry_at: nil, retry_count: 0)
              ids.each { |i| SearchJob.perform_later(i) }
              puts %(books-setup: re-queued #{ids.size} stuck requests #{ids.inspect})
            end
          "' || true
        fi
        rm -f /tmp/books-setup-out
      '';
    };

  };
}
