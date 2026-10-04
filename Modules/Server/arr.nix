{ ... }: {
  # Asgard — the arr stack: Sonarr, Radarr, Lidarr and Prowlarr (configured
  # through nixflix), the daily missing-content searches, and arr-policy, which
  # applies the per-series / per-user state recyclarr cannot express.
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
      sonarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."sonarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      radarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."radarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      lidarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."lidarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
        };
      };

      prowlarr = {
        enable = true;
        config = {
          apiKey._secret = config.sops.secrets."prowlarr-api-key".path;
          hostConfig.password._secret = config.sops.secrets."admin-password".path;
          indexers = [
            # Usenet (primary)
            {
              name = "Miatrix";
              apiKey._secret = config.sops.secrets."indexer-api-keys/Miatrix".path;
            }
            {
              name = "NZBgeek";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBGeek".path;
            }
            {
              name = "NzbPlanet";
              apiKey._secret = config.sops.secrets."indexer-api-keys/NZBPlanet".path;
            }
          ];
        };
      };
    };

    # ── Missing content search ─────────────────────────────────────────────────
    # Radarr: daily search for all monitored movies without files.
    # Persistent = true → runs immediately on boot if the 4am window was missed.
    #
    # That catch-up fires as soon as timers.target is reached — early in boot,
    # while the arr may still be migrating its DB — so each script first waits
    # for the API to answer. The `after` on radarr.service usually covers it
    # (nixflix's ExecStartPost polls the API before the unit counts as started),
    # but that poll gives up after 90s; this wait is the one that fails loudly
    # instead of POSTing into a half-started arr.
    systemd.services.radarr-missing-search = {
      description = "Search all missing monitored movies in Radarr";
      after    = [ "radarr.service" ];
      requires = [ "radarr.service" ];
      # Fail closed if the media pool is not mounted — an empty /data/media would make Radarr
      # consider the entire library missing and trigger a mass re-download.
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/.state" ];
      path     = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        ${waitForHttp { name = "Radarr"; url = "http://localhost:7878/api/v3/system/status"; curlArgs = ''-H "X-Api-Key: $RADARR_KEY"''; }}
        curl -sf -X POST \
          -H "X-Api-Key: $RADARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"MissingMoviesSearch"}' \
          http://localhost:7878/api/v3/command
        echo "Radarr missing movies search triggered."
      '';
    };

    systemd.timers.radarr-missing-search = {
      description = "Radarr missing movies search — on boot + daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "04:00:00";
        Persistent = true;
      };
    };

    # Sonarr: daily search for all monitored episodes without files.
    systemd.services.sonarr-missing-search = {
      description = "Search all missing monitored episodes in Sonarr";
      after    = [ "sonarr.service" ];
      requires = [ "sonarr.service" ];
      # Fail closed if the media pool is not mounted — an empty /data/media would make Sonarr
      # consider the entire library missing and trigger a mass re-download.
      unitConfig.RequiresMountsFor = [ "/data/media" "/data/.state" ];
      path     = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        ${waitForHttp { name = "Sonarr"; url = "http://localhost:8989/api/v3/system/status"; curlArgs = ''-H "X-Api-Key: $SONARR_KEY"''; }}
        curl -sf -X POST \
          -H "X-Api-Key: $SONARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"MissingEpisodeSearch"}' \
          http://localhost:8989/api/v3/command
        echo "Sonarr missing episodes search triggered."
      '';
    };

    systemd.timers.sonarr-missing-search = {
      description = "Sonarr missing episodes search — on boot + daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "04:00:00";
        Persistent = true;
      };
    };

    # Per-item state that recyclarr cannot express. Recyclarr owns quality
    # profiles and custom-format SCORES; it has no concept of "which series
    # uses which profile", series type, release profiles, or Jellyfin user
    # settings. Those are per-record database state, so they are applied here
    # over the APIs instead — idempotently, so a fresh install converges to
    # the same place and re-running is a no-op.
    #
    # Ordered after recyclarr-sync: it reads profiles BY NAME and bails out
    # harmlessly if they do not exist yet (first boot, before the first sync).
    systemd.services.arr-policy = {
      description = "Apply per-series / per-user policy to Sonarr, Radarr and Jellyfin";
      # Ordered after nixflix's seerr-sonarr / seerr-radarr on purpose:
      # Jellyseerr was pointing at the stock "Any" profile (id 1), which this
      # service deletes. Repoint Jellyseerr first, then delete, or requests land
      # on a profile that no longer exists. (This used to name the hand-written
      # seerr-*-profile units, which only a 12-min timer started — at boot the
      # ordering against them was a no-op. nixflix's units are wantedBy
      # multi-user, so they are in the same transaction and it holds.)
      after    = [ "recyclarr-sync.service" "sonarr.service" "radarr.service" "jellyfin.service"
                   "seerr-sonarr.service" "seerr-radarr.service" "network-online.target" ];
      wants    = [ "recyclarr-sync.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Best-effort by design: one series or user that will not update must
        # not stop the rest, and each step reports its own FAILED line. NixOS
        # prepends `set -e` to every unit script, which silently turned that
        # into "abort at the first unguarded failed curl" (e.g. the ATLA series
        # fetch below) — so it is switched back off explicitly.
        set +e
        set -u
        SONARR=http://localhost:8989
        RADARR=http://localhost:7878
        JELLYFIN=http://localhost:8096
        SK=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RK=$(cat ${config.sops.secrets."radarr-api-key".path})
        JK=$(cat ${config.sops.secrets."jellyfin-api-key".path})

        # Wait for Sonarr (and fail loudly if it never comes); everything after
        # this is best-effort within the run.
        ${waitForHttp { name = "Sonarr"; url = "$SONARR/api/v3/system/status"; tries = 30; interval = 5; curlArgs = ''-H "X-Api-Key: $SK"''; }}

        QP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/qualityprofile) || QP="[]"
        TV=$(echo "$QP"     | jq -r '.[]|select(.name=="Asgard - TV")|.id')
        TV1080=$(echo "$QP" | jq -r '.[]|select(.name=="Asgard TV - 1080p")|.id')
        ANIME=$(echo "$QP"  | jq -r '.[]|select(.name=="Asgard - Anime")|.id')

        if [ -z "$TV" ] || [ -z "$TV1080" ] || [ -z "$ANIME" ]; then
          echo "arr-policy: Asgard profiles not present yet (recyclarr has not synced) - skipping"
          exit 0
        fi

        # --- Sonarr: series -> profile + series type -------------------------
        # Anime gets seriesType=anime so absolute episode numbering parses.
        # Game of Thrones is pinned to the 1080p ladder: its only 4K source is
        # a Blu-ray remaster at ~17 GB/ep vs 3.4 GB/ep on disk (measured
        # 2026-08-23), which would have added ~1 TB on its own.
        SERIES=$(curl -sf -m 30 -H "X-Api-Key: $SK" $SONARR/api/v3/series) || SERIES="[]"
        echo "$SERIES" | jq -c '.[]' | while read -r S; do
          ID=$(echo "$S" | jq -r .id)
          TITLE=$(echo "$S" | jq -r .title)
          case "$TITLE" in
            "SAKAMOTO DAYS"|"Good Night World"|"Sword Art Online"|"Solo Leveling"|"JUJUTSU KAISEN")
              WANT_P=$ANIME;  WANT_T=anime ;;
            # The 2005 cartoon was animated for 4:3 SD and remastered no
            # higher than 1080p — there is no 4K master to grab. Pinning it
            # to the 1080p ladder is therefore free, and it doubles as the
            # first line of defence against the 2024 Netflix live-action
            # remake, whose releases are all 2160p (see the block below).
            "Avatar: The Last Airbender"|"Game of Thrones")
              WANT_P=$TV1080; WANT_T=standard ;;
            *)
              WANT_P=$TV;     WANT_T=standard ;;
          esac
          CUR_P=$(echo "$S" | jq -r .qualityProfileId)
          CUR_T=$(echo "$S" | jq -r .seriesType)
          if [ "$CUR_P" != "$WANT_P" ] || [ "$CUR_T" != "$WANT_T" ]; then
            echo "$S" | jq --argjson p "$WANT_P" --arg t "$WANT_T" \
                  '.qualityProfileId=$p | .seriesType=$t' \
              | curl -sf -m 30 -X PUT -H "X-Api-Key: $SK" \
                     -H 'Content-Type: application/json' --data-binary @- \
                     "$SONARR/api/v3/series/$ID" >/dev/null \
              && echo "arr-policy: $TITLE -> profile $WANT_P / $WANT_T" \
              || echo "arr-policy: FAILED to update $TITLE"
          fi
        done

        # --- Sonarr: block the fake-dual-audio group -------------------------
        # "Anime Dual Audio" matches on the literal token DUAL, so a
        # Portuguese+Japanese release like
        #   SAKAMOTO.DAYS.S01E03.1080p.NF.WEB-DL.DDP5.1.H.264.DUAL-sh4down
        # scores as if it were an English dub. TRaSH's own "Bad Dual Groups"
        # list does NOT include sh4down (checked 2026-08-23, all 34 entries),
        # so it is blocked here. A release profile is used rather than a
        # custom format because recyclarr's reset_unmatched_scores would zero
        # a locally-scored CF on its next sync; it does not touch these.
        # "AV1" is also blocked here, NOT only via the AV1 custom format.
        # TRaSH's AV1 CF regex is \bAV1\b, which does not match a title like
        #   [Breeze].Sakamoto.Days-S01E13.1080p.AV1Dual.Audio.weekly
        # because there is no word boundary between AV1 and Dual. That
        # release scored +2000 on Anime Dual Audio alone and was grabbed on
        # 2026-08-23 despite the CF being at -10000. A release-profile
        # ignored term is a plain substring match, so it has no such gap.
        DESIRED='["sh4down","AV1"]'
        RP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/releaseprofile) || RP="[]"
        EXISTING=$(echo "$RP" | jq -c '.[]|select(.name=="Asgard - fake dual audio")')
        if [ -z "$EXISTING" ]; then
          curl -sf -m 15 -X POST -H "X-Api-Key: $SK" -H 'Content-Type: application/json' \
            -d "{\"name\":\"Asgard - fake dual audio\",\"enabled\":true,\"required\":[],\"ignored\":$DESIRED,\"indexerId\":0,\"tags\":[]}" \
            $SONARR/api/v3/releaseprofile >/dev/null \
            && echo "arr-policy: created release profile (sh4down, AV1)" \
            || echo "arr-policy: FAILED to create release profile"
        elif [ "$(echo "$EXISTING" | jq -c '.ignored|sort')" != "$(echo "$DESIRED" | jq -c 'sort')" ]; then
          RPID=$(echo "$EXISTING" | jq -r .id)
          echo "$EXISTING" | jq --argjson ig "$DESIRED" '.ignored=$ig' \
            | curl -sf -m 15 -X PUT -H "X-Api-Key: $SK" \
                   -H 'Content-Type: application/json' --data-binary @- \
                   "$SONARR/api/v3/releaseprofile/$RPID" >/dev/null \
            && echo "arr-policy: updated release profile ignored terms" \
            || echo "arr-policy: FAILED to update release profile"
        fi

        # --- Sonarr: keep the live-action remake out of the 2005 cartoon -----
        # Netflix's 2024 live-action "Avatar: The Last Airbender" has its own
        # TVDB entry, but its releases are titled identically to the cartoon's
        #   Avatar.The.Last.Airbender.S01E02.2024.2160p.NF.WEB-DL...
        # so Sonarr matched them straight onto tvdb 74852 (the 2005 series).
        # Found 2026-08-28: 14 live-action episodes had been imported into the
        # cartoon — S01E02-E08 and S02E01-E07 — and because they filled those
        # slots Sonarr reported both seasons as complete. Runtime is the
        # giveaway: 47-69 min against 23-25 min for real episodes.
        #
        # A TAGGED release profile, not a global one: HHWEB/XEBEC/BYNDR are
        # ordinary groups that do other shows legitimately, so these terms
        # must only ever apply to this one series.
        #
        # The term targets audio, which is the most durable discriminator
        # available: all 14 live-action files carry DDP5.1 Atmos, and a 2005
        # Nickelodeon cartoon will never gain a genuine Atmos mix. Group names
        # and the "2024" token would both drift as new releases appear.
        #
        # Deliberately ONLY "Atmos", not "DDP5.1" — Netflix does carry 5.1
        # audio for parts of the animated series, so blocking DDP5.1 outright
        # risks rejecting a legitimate release. Atmos alone already matches
        # every live-action file observed.
        #
        # "SKST" is a SECOND, unrelated problem that the 2026-08-28 redo
        # exposed. That release set collapses the show's two-parters into one
        # file and then renumbers everything after it, so its episode numbers
        # drift out of step with TVDB:
        #   SKST S03E12 = "The Firebending Masters"  (TVDB E13)
        #   SKST S03E14 = "The Southern Raiders"     (TVDB E16)
        # Sonarr matches on the S/E in the release title and never checks the
        # episode name, so these import into the wrong slots and every episode
        # from the first two-parter onward plays the NEXT one. That is exactly
        # how S02E13-E18 and S03E11-E16 ended up wrong the first time round,
        # and re-searching reproduced it within minutes.
        #
        # The AMZN set (CtrlHD / SiGMA) numbers correctly because it ships
        # two-parters as real multi-episode releases that Sonarr parses into
        # both slots — S02E12E13, S03E10E11, S03E14E15, S03E18E19E20E21 — so
        # blocking SKST leaves a complete, correctly-numbered alternative at
        # the same WEBDL-1080p tier. Verified across all 61 episodes.
        ATLA_ID=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/series \
                  | jq -r '.[]|select(.tvdbId==74852)|.id')
        if [ -n "$ATLA_ID" ] && [ "$ATLA_ID" != "null" ]; then
          TAGID=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/tag \
                  | jq -r '.[]|select(.label=="atla-animated")|.id')
          if [ -z "$TAGID" ] || [ "$TAGID" = "null" ]; then
            TAGID=$(curl -sf -m 15 -X POST -H "X-Api-Key: $SK" \
                      -H 'Content-Type: application/json' \
                      -d '{"label":"atla-animated"}' $SONARR/api/v3/tag | jq -r .id)
          fi
          if [ -n "$TAGID" ] && [ "$TAGID" != "null" ]; then
            # Tag the series (idempotent — only PUTs when the tag is absent).
            ASER=$(curl -sf -m 15 -H "X-Api-Key: $SK" "$SONARR/api/v3/series/$ATLA_ID")
            if [ "$(echo "$ASER" | jq --argjson t "$TAGID" '.tags|index($t)')" = "null" ]; then
              echo "$ASER" | jq --argjson t "$TAGID" '.tags += [$t]' \
                | curl -sf -m 30 -X PUT -H "X-Api-Key: $SK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$SONARR/api/v3/series/$ATLA_ID" >/dev/null \
                && echo "arr-policy: tagged Avatar with atla-animated"
            fi
            ATLA_IGN='["Atmos","SKST"]'
            ARP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/releaseprofile) || ARP="[]"
            AEX=$(echo "$ARP" | jq -c '.[]|select(.name=="Asgard - ATLA live-action block")')
            if [ -z "$AEX" ]; then
              curl -sf -m 15 -X POST -H "X-Api-Key: $SK" -H 'Content-Type: application/json' \
                -d "{\"name\":\"Asgard - ATLA live-action block\",\"enabled\":true,\"required\":[],\"ignored\":$ATLA_IGN,\"indexerId\":0,\"tags\":[$TAGID]}" \
                $SONARR/api/v3/releaseprofile >/dev/null \
                && echo "arr-policy: created ATLA live-action release profile" \
                || echo "arr-policy: FAILED to create ATLA release profile"
            elif [ "$(echo "$AEX" | jq -c '.ignored|sort')" != "$(echo "$ATLA_IGN" | jq -c 'sort')" ] \
              || [ "$(echo "$AEX" | jq -c '.tags')" != "[$TAGID]" ]; then
              ARPID=$(echo "$AEX" | jq -r .id)
              echo "$AEX" | jq --argjson ig "$ATLA_IGN" --argjson t "$TAGID" \
                    '.ignored=$ig | .tags=[$t]' \
                | curl -sf -m 15 -X PUT -H "X-Api-Key: $SK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$SONARR/api/v3/releaseprofile/$ARPID" >/dev/null \
                && echo "arr-policy: updated ATLA live-action release profile" \
                || echo "arr-policy: FAILED to update ATLA release profile"
            fi
          fi
        fi

        # --- Delete the profiles Jellyseerr should not offer -----------------
        # Deliberately an explicit NAME list, not "everything unused": a
        # profile created later on purpose must not be silently destroyed.
        # Sonarr/Radarr refuse to delete a profile still in use, which is the
        # backstop if the reassignment above did not fully land.
        QP=$(curl -sf -m 15 -H "X-Api-Key: $SK" $SONARR/api/v3/qualityprofile) || QP="[]"
        for NAME in "Any" "SD" "HD-720p" "HD-1080p" "Ultra-HD" "HD - 720p/1080p" "Any 1080p" "WEB-1080p" "WEB-2160p"; do
          PID=$(echo "$QP" | jq -r --arg n "$NAME" '.[]|select(.name==$n)|.id')
          if [ -n "$PID" ]; then
            curl -sf -m 15 -X DELETE -H "X-Api-Key: $SK" "$SONARR/api/v3/qualityprofile/$PID" >/dev/null \
              && echo "arr-policy: deleted Sonarr profile $NAME" \
              || echo "arr-policy: kept Sonarr profile $NAME (still in use)"
          fi
        done

        RQP=$(curl -sf -m 15 -H "X-Api-Key: $RK" $RADARR/api/v3/qualityprofile) || RQP="[]"

        # Radarr COLLECTIONS carry their own qualityProfileId, and Radarr
        # counts that as "in use" — so a profile with zero movies still
        # refuses to delete. Found 2026-08-23: 29 collections pinned to
        # "Remux + WEB 1080p" and 19 to "Remux + WEB 2160p", which is why
        # those two survived the first run. Repoint them at Asgard - Movies
        # before the delete loop below.
        MOVIE_P=$(echo "$RQP" | jq -r '.[]|select(.name=="Asgard - Movies")|.id')
        if [ -n "$MOVIE_P" ]; then
          COLS=$(curl -sf -m 30 -H "X-Api-Key: $RK" $RADARR/api/v3/collection) || COLS="[]"
          echo "$COLS" | jq -c '.[]' | while read -r C; do
            CID=$(echo "$C" | jq -r .id)
            CP=$(echo "$C" | jq -r .qualityProfileId)
            if [ "$CP" != "$MOVIE_P" ]; then
              echo "$C" | jq --argjson p "$MOVIE_P" '.qualityProfileId=$p' \
                | curl -sf -m 30 -X PUT -H "X-Api-Key: $RK" \
                       -H 'Content-Type: application/json' --data-binary @- \
                       "$RADARR/api/v3/collection/$CID" >/dev/null \
                && echo "arr-policy: collection $CID -> profile $MOVIE_P" \
                || echo "arr-policy: FAILED to move collection $CID"
            fi
          done
        fi

        for NAME in "Any" "SD" "HD-720p" "HD-1080p" "Ultra-HD" "HD - 720p/1080p" "Remux + WEB 1080p" "Remux + WEB 2160p"; do
          PID=$(echo "$RQP" | jq -r --arg n "$NAME" '.[]|select(.name==$n)|.id')
          if [ -n "$PID" ]; then
            curl -sf -m 15 -X DELETE -H "X-Api-Key: $RK" "$RADARR/api/v3/qualityprofile/$PID" >/dev/null \
              && echo "arr-policy: deleted Radarr profile $NAME" \
              || echo "arr-policy: kept Radarr profile $NAME (still in use)"
          fi
        done

        # --- Jellyfin: make English actually play ----------------------------
        # PlayDefaultAudioTrack=true makes Jellyfin honour the file's default
        # track and IGNORE AudioLanguagePreference entirely. Most anime here
        # ships with Japanese (JUJUTSU KAISEN: French) flagged default, so
        # accounts with a preference set were still getting subs. Rhys is
        # skipped - already configured correctly and left as the control.
        USERS=$(curl -sf -m 15 -H "X-Emby-Token: $JK" $JELLYFIN/Users) || USERS="[]"
        echo "$USERS" | jq -c '.[]' | while read -r U; do
          UNAME=$(echo "$U" | jq -r .Name)
          [ "$UNAME" = "Rhys" ] && continue
          UID_J=$(echo "$U" | jq -r .Id)
          CUR_A=$(echo "$U" | jq -r '.Configuration.AudioLanguagePreference // ""')
          CUR_D=$(echo "$U" | jq -r '.Configuration.PlayDefaultAudioTrack')
          if [ "$CUR_A" != "eng" ] || [ "$CUR_D" != "false" ]; then
            echo "$U" | jq '.Configuration | .AudioLanguagePreference="eng" | .PlayDefaultAudioTrack=false' \
              | curl -sf -m 15 -X POST -H "X-Emby-Token: $JK" \
                     -H 'Content-Type: application/json' --data-binary @- \
                     "$JELLYFIN/Users/$UID_J/Configuration" >/dev/null \
              && echo "arr-policy: Jellyfin user $UNAME -> eng / no default-track override" \
              || echo "arr-policy: FAILED to update Jellyfin user $UNAME"
          fi
        done

        echo "arr-policy: done"
      '';
    };

    sops.secrets."sonarr-api-key"           = {};
    sops.secrets."radarr-api-key"           = {};
    sops.secrets."lidarr-api-key"           = {};
    sops.secrets."prowlarr-api-key"         = {};
    sops.secrets."indexer-api-keys/Miatrix"        = {};
    sops.secrets."indexer-api-keys/NZBGeek"        = {};
    sops.secrets."indexer-api-keys/NZBPlanet"      = {};

  };
}
