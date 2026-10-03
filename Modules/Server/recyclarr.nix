{ ... }: {
  # Asgard — Recyclarr: TRaSH-guide quality profiles and custom-format scores for
  # Sonarr and Radarr, generated from sops and synced on boot + daily.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, ... }:
  {

# ══════════════════════════════════════════════════════════════════════════════
# QUALITY — Recyclarr (TRaSH Guides quality profile sync)
# Syncs quality profiles + custom formats to Sonarr + Radarr on boot + daily.
#   Sonarr: Asgard - TV (default) / Asgard TV - 1080p / Asgard - Anime
#   Radarr: Asgard - Movies (default)
# This fixes grab issues like "only getting Redux" — proper CF scoring applied.
#
# "Asgard - Movies" / "Asgard - TV" (2026-08-16): custom (non-trash_id) merged
# profiles — best compressed quality first (4K, no remux), falling back down
# to whatever's actually available, in one ladder. Remuxes were causing real
# problems (Eclipse's Pi decoder choking on 4K HDR remuxes, WAN bandwidth
# saturation for remote streams — see Claude/eclipse.md) for negligible
# perceptible quality gain. Set as Jellyseerr's defaults by name through
# nixflix.seerr.{radarr,sonarr} (see jellyfin.nix), so every user's
# request uses these without having to pick a profile manually.
# ══════════════════════════════════════════════════════════════════════════════

    systemd.services.recyclarr-config = {
      description = "Generate Recyclarr config from sops secrets";
      before   = [ "recyclarr-sync.service" ];
      wantedBy = [ "recyclarr-sync.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/recyclarr
        SONARR_KEY=$(cat ${config.sops.secrets."sonarr-api-key".path})
        RADARR_KEY=$(cat ${config.sops.secrets."radarr-api-key".path})
        # TRaSH's config-templates repo deleted includes.json in 2026-07 and renamed everything;
        # `include: - template: …` no longer resolves ANYTHING (there are no include templates any
        # more) and recyclarr hard-errors, so the sync silently did nothing from 2026-07-11 until
        # this was migrated on 2026-08-11.
        #
        # The replacements are whole-config templates, not includes, so their contents are inlined
        # here by trash_id instead. That is deliberate: trash_ids are stable content hashes, whereas
        # template *names* have now churned twice. Scores and CF definitions still come live from
        # the guide on every sync — only the selection is pinned.
        #
        # Equivalent to the old templates: radarr-remux-web-1080p + radarr-remux-web-2160p and
        # sonarr web-1080p + web-2160p, merged into one instance per service (matching how the old
        # include list put both profiles on one instance).
        #
        # Verified 2026-08-11 by diffing every profile before/after: allowed qualities, cutoffs,
        # cutoffFormatScore (10000), minUpgradeFormatScore (1) and upgradeAllowed are all
        # IDENTICAL — the profiles did not get looser. The only change is a month of TRaSH audio
        # scoring (TrueHD ATMOS +5000, DTS X +4500, FLAC/PCM/DD+ …) plus new negatives
        # (Bad Dual Groups, Line/Mic Dubbed, Black and White Editions at -10000). Sonarr's manual
        # "Any 1080p" profile is not managed here and was untouched.
        cat > /var/lib/recyclarr/recyclarr.yml << EOF
sonarr:
  sonarr-main:
    base_url: http://localhost:8989
    api_key: $SONARR_KEY
    quality_definition:
      type: series
    quality_profiles:
      # The stock TRaSH "WEB-1080p" and "WEB-2160p" profiles were REMOVED from
      # this list on 2026-08-23 and deleted from Sonarr by arr-policy.service.
      # They must stay out of here: recyclarr recreates any profile it is
      # told to manage, so leaving the trash_ids would resurrect them on the
      # next sync and put them back in Jellyseerr's dropdown. Everything now
      # sits on the Asgard profiles below.
      # Custom (not trash_id-based) — mirrors "Asgard - Movies": one ladder,
      # best quality first, remux excluded. Deeper fallback than the stock
      # WEB-only profiles above (which allow WEB and nothing else) because
      # older/catalog shows (Voyager, Kitchen Nightmares back-catalog) often
      # only exist as Bluray-1080p, HDTV, or even DVD/SDTV — a WEB-only
      # profile just never grabs them. Upgrading stays on, so anything
      # grabbed low will get replaced automatically if a better release
      # (still non-remux) shows up later.
      - name: Asgard - TV
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: WEB 2160p
        quality_sort: bottom
        qualities:
          - name: WEB 2160p
            qualities:
              - WEBDL-2160p
              - WEBRip-2160p
          - name: Bluray-2160p
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-1080p
          - name: HDTV-1080p
          - name: WEB 720p
            qualities:
              - WEBDL-720p
              - WEBRip-720p
          - name: Bluray-720p
          - name: HDTV-720p
          - name: DVD
          - name: SDTV
      # Custom (not trash_id-based) — "Asgard - TV" with every 2160p tier
      # removed. For shows whose ONLY 4K source is a Blu-ray remaster rather
      # than a WEB-DL: there the "upgrade to 4K" is a huge size jump for a
      # disc rip, not a like-for-like swap. Measured 2026-08-23 on Game of
      # Thrones — 3.4 GB/ep on disk vs a 17.1 GB/ep median 2160p release
      # (5x), which alone would have added ~1 TB. Everything else that has
      # real 4K WEB-DLs costs only +1.6 to +8.8 GB/ep and stays on Asgard - TV.
      # Assign this per-series; it is not a default for anything.
      - name: Asgard TV - 1080p
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: WEB 1080p
        quality_sort: bottom
        qualities:
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-1080p
          - name: HDTV-1080p
          - name: WEB 720p
            qualities:
              - WEBDL-720p
              - WEBRip-720p
          - name: Bluray-720p
          - name: HDTV-720p
          - name: DVD
          - name: SDTV
      # Custom (not trash_id-based) — anime needs its own profile because
      # scoring is fundamentally different: release quality is judged by
      # FANSUB/BD GROUP reputation (the Anime Release Groups CFs below), not
      # by resolution/source the way normal TV is. Structure mirrors TRaSH's
      # own "[Anime] Remux-1080p" guide profile (1080p BD as the top tier,
      # HDTV/WEB-1080p merged into a middle tier, 720p as final fallback) —
      # deliberately DROPPING remux from the top tier (TRaSH merges
      # "Bluray-1080p Remux" + "Bluray-1080p" into one tier and lets the
      # Remux Tier custom format bias toward remux; we just don't allow
      # remux at all, same as Asgard - Movies / Asgard - TV). Anime rarely
      # has meaningful 2160p releases, so no 2160p tier here.
      - name: Asgard - Anime
        reset_unmatched_scores:
          enabled: true
        # ENGLISH DUB IS A HARD REQUIREMENT for anime — no dub, no download.
        #
        # Scoring "Anime Dual Audio" highly is NOT enough on its own, which
        # was proved empirically on 2026-08-23: Sonarr ranks QUALITY TIER
        # ahead of custom-format score, so a Japanese Bluray-1080p (score 0)
        # beat a WEB-DL 720p dual-audio release (score 4100) and was grabbed.
        # CF score only breaks ties WITHIN one quality tier.
        #
        # A minimum score is the only lever that rejects non-dubs outright.
        # 2000 is chosen to sit in the gap between the two populations:
        #   best possible non-dub = WEB Tier 01 1700 + boosts 150 + repack 7 = 1857
        #   any dub               = Anime Dual Audio 2000, before any tier
        # Raising the tier scores above ~1990 would close that gap and break
        # this — keep the arithmetic in mind before editing scores below.
        #
        # Consequence, accepted deliberately: an episode with no dub on the
        # indexers stays MISSING rather than grabbing a sub. For a currently
        # airing season the dub can lag the sub by weeks.
        min_format_score: 2000
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
        quality_sort: bottom
        qualities:
          # NO 2160p TIER — deliberate, and re-confirmed 2026-08-23.
          #
          # It was briefly added that day and then removed the same evening.
          # The reasoning for adding it was wrong: JUJUTSU KAISEN S1 looked
          # like it only had English dubs at 2160p, but that was an artefact
          # of the x265 penalty (see the TV-only block above) suppressing the
          # real 1080p dual-audio releases. Once x265 was un-penalised and
          # "Dubs Only" was added, 1080p dubs were plentiful — S01E02 alone
          # had 150 dual-audio releases including Bluray-1080p and WEBDL-1080p.
          #
          # More importantly there is no 4K master to rip. TV anime is
          # mastered at 1080p (often 720p); native 4K anime is essentially
          # nonexistent, and a WEB-DL cannot exceed what the platform
          # streamed. The "2160p B-Global WEB-DL" files were 2.03 GB against
          # 1.54 GB for the native 1080p Crunchyroll rips already on disk —
          # 4x the pixels for 32% more data, i.e. an upscale. TRaSH's own
          # anime profile has no 2160p tier at all and tops out at
          # Bluray-1080p Remux.
          #
          # Do not re-add this because a show "only has dubs at 4K" — check
          # whether a scoring rule is hiding the 1080p ones first.
          - name: Bluray-1080p
          - name: 1080p
            qualities:
              - HDTV-1080p
              - WEBDL-1080p
              - WEBRip-1080p
          - name: 720p
            qualities:
              - HDTV-720p
              - WEBDL-720p
              - WEBRip-720p
    custom_format_groups:
      add:
        - trash_id: 158188097a58d7687dee647e04af0da3  # [Optional] Golden Rule HD
        - trash_id: e3f37512790f00d0e89e54fe5e790d1c  # [Optional] Golden Rule UHD
        - trash_id: 74aff4168620ed49dcc67e92b2c2a5b4  # [Optional] Language Profiles
        - trash_id: f206572b1147d0221bb1c96765b349e8  # [Release Groups] Anime
        - trash_id: 4d3dc16c3ab3adc640afb8d6e3dc2266  # [Optional] Anime Optional (dual audio, uncensored, 10bit)
        - trash_id: 4b196eed652c65ea98d615212040ebe2  # [Required] Anime Versions (v0-v4)
        - trash_id: 85fae4a2294965b75710ef2989c850eb  # [Streaming Services] HD/UHD boost
        - trash_id: 59c3af66780d08332fdc64e68297098f  # [Unwanted] Unwanted Formats
        - trash_id: bad5bc85573a0134e1e1987c46f67e98  # [Optional] Accessibility (WiTH AD/ASL/BASL/BSL)
    # Explicit scores for Asgard - TV / Asgard - Anime (custom, non-trash_id
    # profiles). NEEDED — custom_format_groups.add only creates the formats,
    # it does NOT score them for a non-trash_id profile; reset_unmatched_scores
    # then zeroes everything. This is what let 100+ fake "AI Upscale" Star
    # Trek Voyager releases through on 2026-08-17 before it was caught.
    # Every trash_id/score below is the real trash-guide default, fetched
    # directly from TRaSH-Guides/Guides docs/json/sonarr/cf/*.json — not
    # guessed. Re-verify against that repo if these ever look wrong.
    custom_formats:
      - trash_ids:
          - 23297a736ca77c0fc8e70f8edd7ee56c  # Upscaled
          - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
          - e2315f990da2e2cbfc9fa5b7a6fcfe48  # LQ (Release Title)
          - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
          - 32b367365729d530ca1c124a0b180c64  # Bad Dual Groups
          - fbcb31d8dabd2a319072b84fc0b7249c  # Extras
          # AV1 — on TRaSH's anime unwanted list, and a hard playback
          # constraint here: Eclipse is a Pi 5, which has HEVC hardware
          # decode but NO AV1 decoder, so AV1 falls back to software and
          # struggles. Added 2026-08-23 after raising the dub scores caused
          # Sonarr to grab three [Breeze] "[1080p.AV1][Dual.Audio]" releases
          # — they satisfied "has English audio" and nothing objected.
          - 15a05bc7c1a36e2b57fd628f8977e2fc  # AV1
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # Accessibility variants — releases where the ONLY audio track is an
      # alternate accessibility mix, not the normal one. Added 2026-08-28
      # after Mythic Quest was found unwatchable: 15 of its episodes were
      # Kitsune "with Audio Description" releases, and ffprobe confirmed they
      # carry exactly ONE audio stream, titled "Descriptive" — there is no
      # normal English track to switch to in the player, so the narrator
      # talks over the whole episode. All the Light We Cannot See (4 eps) and
      # Invincible S04 (4 eps) had the same problem.
      #
      # Nothing else in the config objected: the releases are genuine 1080p
      # WEB-DL DDP5.1 Atmos from a decent group, so they scored *well*.
      #
      # NOTE the mkv disposition flag `visual_impaired` is 0 on these files,
      # so Jellyfin cannot detect or avoid them client-side either. The
      # release title is the only signal, which is exactly what this CF
      # matches. ASL/BASL/BSL are the sign-language equivalents from the same
      # TRaSH group — same problem, same score.
      - trash_ids:
          - 44ccbcbc74506f208973e1463b11705f  # WiTH AD
          - c196536ea8122397c5854040d01f2aa7  # WiTH ASL
          - b40dc2e630723745aab9f1b94f4aab74  # WiTH BASL
          - 0aef382c4ed4c5eb5d40109dfd351b72  # WiTH BSL
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # TV-ONLY negatives. Both of these are correct for live-action TV and
      # actively harmful for anime, so they are deliberately NOT assigned to
      # Asgard - Anime. TRaSH's anime profile does not use either.
      #
      # "Language: Not Original" rejects releases whose language is not the
      # series' ORIGINAL language. Right for English-origin TV (blocks
      # foreign dubs); backwards for anime, where the original IS Japanese,
      # so an English-dub-only release trips it and takes -10000.
      #
      # "x265 (HD)" targets wasteful x265 re-encodes of live-action HD.
      # Anime is different: 10-bit x265 is the normal, high-quality format
      # for fansub/BD groups, and TRaSH's anime unwanted list is only
      # Anime Raws / Anime LQ Groups / AV1 / Dubs Only / VOSTFR / v0 — no
      # x265 at all. Applying it here scored real 1080p dual-audio releases
      # at -8000 (e.g. [EMBER] Sakamoto Days S01E03 [1080p] [Dual Audio
      # HEVC WEBRip DDP]), which forced a 720p grab on 2026-08-23 because
      # the only unpenalised dub was 720p.
      - trash_ids:
          - ae575f95ab639ba5d15f663bf019e3e8  # Language: Not Original
          - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)
        score: -10000
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
      - trash_ids:
          - d0c516558625b04b363fa6c5c2c7cfd4  # WEB Scene
        score: 1600
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - e6258996055b9fbab7e9cb2f75819294  # WEB Tier 01
        score: 1700
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 58790d4e2fdcd9733aa7ae68ba2bb503  # WEB Tier 02
        score: 1650
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - d84935abd3f8556dcd51d4f27e22d0a6  # WEB Tier 03
        score: 1600
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 218e93e5702f44a68ad9e3c6ba87d2f0  # HD Streaming Boost
          - 43b3cf48cb385cd3eac608ee6bca7f09  # UHD Streaming Boost
        score: 75
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - ec8fa7296b64e8cd390a1600981f3923  # Repack/Proper
        score: 5
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - eb3d5cc0a2be0db205fb823640db6a3c  # Repack2
        score: 6
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      - trash_ids:
          - 44e7c4de10ae50265753082e5dc76047  # Repack3
        score: 7
        assign_scores_to:
          - name: Asgard - TV
          - name: Asgard TV - 1080p
          - name: Asgard - Anime
      # Anime-only: fansub/BD release-group reputation tiers. This IS the
      # scoring that actually matters for anime — release quality there is
      # judged by which group did the encode, not resolution/source.
      - trash_ids:
          - 949c16fe0a8147f50ba82cc2df9411c9  # Anime BD Tier 01
        score: 1400
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - ed7f1e315e000aef424a58517fa48727  # Anime BD Tier 02
        score: 1300
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 096e406c92baa713da4a72d88030b815  # Anime BD Tier 03
        score: 1200
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 30feba9da3030c5ed1e0f7d610bcadc4  # Anime BD Tier 04
        score: 1100
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 545a76b14ddc349b8b185a6344e28b04  # Anime BD Tier 05
        score: 1000
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 25d2afecab632b1582eaf03b63055f72  # Anime BD Tier 06
        score: 900
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 0329044e3d9137b08502a9f84a7e58db  # Anime BD Tier 07
        score: 800
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - c81bbfb47fed3d5a3ad027d077f889de  # Anime BD Tier 08
        score: 700
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - e0014372773c8f0e1bef8824f00c7dc4  # Anime Web Tier 01
        score: 600
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 19180499de5ef2b84b6ec59aae444696  # Anime Web Tier 02
        score: 500
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - c27f2ae6a4e82373b0f1da094e2489ad  # Anime Web Tier 03
        score: 400
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 4fd5528a3a8024e6b49f9c67053ea5f3  # Anime Web Tier 04
        score: 300
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 29c2a13d091144f63307e4a8ce963a39  # Anime Web Tier 05
        score: 200
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - dc262f88d74c651b12e9d90b39f6c753  # Anime Web Tier 06
        score: 100
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - b4a1b3d705159cdca36d71e57ca86871  # Anime Raws
          - e3515e519f3b1360cbfc17651944354c  # Anime LQ Groups
        score: -10000
        assign_scores_to:
          - name: Asgard - Anime
      - trash_ids:
          - 418f50b10f1907201b6cfdf881f467b7  # Anime Dual Audio (no guide default)
        # DECISIVE, not a nudge. The release-group tiers above top out at
        # 1700, so the old score of 25 was ~50x too small to ever change an
        # outcome — a Japanese-only release from a better fansub group won
        # every time. Audited 2026-08-23: 28 of 162 anime files had no
        # English track at all (JUJUTSU KAISEN S1 was a French Blu-ray rip,
        # SAKAMOTO DAYS had Portuguese and raw-Japanese files). At 2000 a
        # dual-audio release outranks any tier, which is the intended
        # trade — audio language wins over encode quality for this library.
        score: 2000
        assign_scores_to:
          - name: Asgard - Anime
      # "Dubs Only" catches English-dub releases that do NOT advertise dual
      # audio — titles like "Sakamoto Days - 03 [English Dub][1080p]", plus
      # the known dub groups (Yameii, KamiFS, Golumpa, KaiDubs...). The
      # "Anime Dual Audio" CF above cannot match these: its regex looks for
      # a DUAL token or a JA+EN language pair, so a dub-only release scores
      # 0 and is rejected by min_format_score.
      #
      # TRaSH scores this -10000, because their anime guide is written for
      # people who want the ORIGINAL Japanese audio with subs. This library
      # wants the opposite, so the sign is deliberately inverted. Same 2000
      # as dual audio: either one satisfies "has English audio".
      - trash_ids:
          - 9c14d194486c4014d422adc64092d794  # Dubs Only
        score: 2000
        assign_scores_to:
          - name: Asgard - Anime
radarr:
  radarr-main:
    base_url: http://localhost:7878
    api_key: $RADARR_KEY
    quality_definition:
      type: movie
    quality_profiles:
      # "Remux + WEB 1080p" / "Remux + WEB 2160p" were REMOVED here on
      # 2026-08-23 and deleted from Radarr by arr-policy.service — they held
      # zero movies (all 237 are on Asgard - Movies) and only cluttered
      # Jellyseerr. Same rule as the Sonarr block above: if the trash_ids go
      # back in this list, recyclarr recreates the profiles.
      # Custom (not trash_id-based) — no official TRaSH profile spans both
      # resolutions in one ladder. Merges HD Bluray + WEB (d1d67249…) and
      # UHD Bluray + WEB (64fb5f98…) qualities into one profile, remux
      # excluded entirely, so this can never grab/keep a remux release.
      # Upgrading is allowed up to Bluray-2160p, so a 1080p grab will later
      # get replaced by a 4K one if a clean (non-remux) release shows up.
      - name: Asgard - Movies
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-2160p
        quality_sort: bottom
        qualities:
          - name: Bluray-2160p
          - name: WEB 2160p
            qualities:
              - WEBRip-2160p
              - WEBDL-2160p
          - name: Bluray-1080p
          - name: WEB 1080p
            qualities:
              - WEBRip-1080p
              - WEBDL-1080p
    custom_format_groups:
      add:
        - trash_id: f8bf8eab4617f12dfdbd16303d8da245  # [Optional] Golden Rule HD
        - trash_id: ff204bbcecdd487d1cefcefdbf0c278d  # [Optional] Golden Rule UHD
        - trash_id: a3ac6af01d78e4f21fcb75f601ac96df  # [Unwanted] Unwanted Formats
        - trash_id: bc3c13e52f2971319bc1748ffa3d1078  # [Optional] Accessibility (WiTH AD/ASL/BASL/BSL)
    # Explicit scores for Asgard - Movies (custom, non-trash_id profile) —
    # see the matching comment under sonarr-main above for why this is
    # necessary. Real trash-guide defaults, fetched directly from
    # TRaSH-Guides/Guides docs/json/radarr/cf/*.json.
    custom_formats:
      - trash_ids:
          - bfd8eb01832d646a0a89c4deb46f8564  # Upscaled
          - 90a6f9a284dff5103f6346090e6280c8  # LQ
          - e204b80c87be9497a8a6eaff48f72905  # LQ (Release Title)
          - ed38b889b31be83fda192888e2286d83  # BR-DISK
          - b6832f586342ef70d9c128d40c07b872  # Bad Dual Groups
          - dc98083864ea246d05a42df0d05f81cc  # x265 (HD)
          - 0a3f082873eb454bde444150b70253cc  # Extras
          - b8cd450cbfa689c0259a01d9e29ba3d6  # 3D
          - 712d74cd88bceb883ee32f773656b1f5  # Sing-Along Versions
          - cc444569854e9de0b084ab2b8b1532b2  # Black and White Editions
          - c465ccc73923871b3eb1802042331306  # Line/Mic Dubbed
          # Accessibility variants — the audio-description / sign-language
          # cuts. No movie had been caught by this yet (the 2026-08-28 sweep
          # found AD releases only in TV), but the failure mode is identical
          # and there is no reason to leave Radarr exposed. See the matching
          # block under sonarr-main for the full write-up.
          - 127bdbadcf3e4463a8c707759fbaad75  # WiTH AD
          - 09c60ba54fadb511c6986a7edec4da4b  # WiTH ASL
          - 41e4baea7b10ddefc6609d52f742dacd  # WiTH BASL
          - e205c5ba6be76b472903f4aec97fdb4b  # WiTH BSL
          # Dolby Vision Profile 5 — no HDR10 fallback. Its base layer is IPT-C2, so any
          # player without DV support decodes it as YCbCr and the picture comes out GREEN.
          # Eclipse (Pi 5 / LibreELEC) has no DV support at all, so P5 is unwatchable there
          # without a server-side transcode. Radarr picked one for Tomorrowland (2026-09-07)
          # because nothing above scores video range: it ranked on TrueHD ATMOS (+5000) and
          # took the DV twin of an otherwise identical release from the same group and WEB
          # source. Full write-up in Claude/eclipse.md.
          # Matches "Dolby Vision AND WEBDL AND NOT HDR", i.e. exactly P5 — releases named
          # DV.HDR (Profile 8.1) carry an HDR10 base layer, direct-play correctly, and are
          # deliberately NOT caught by this.
          - 923b6abef9b17f937fab56cfcf89e1f1  # DV (w/o HDR fallback)
        score: -10000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - c20f169ef63c5f40c2def54abaf4438e  # WEB Tier 01
        score: 1700
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 403816d65392c79236dcb6dd591aeda4  # WEB Tier 02
        score: 1650
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - af94e0fe497124d1f9ce732069ec8c3b  # WEB Tier 03
        score: 1600
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - e7718d7a3ce595f289bfee26adc178f5  # Repack/Proper
        score: 5
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - ae43b294509409a6a13919dedd4764c4  # Repack2
        score: 6
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 5caaaa1c08c1742aa4342d8c4cc463f2  # Repack3
        score: 7
        assign_scores_to:
          - name: Asgard - Movies
      # Audio format hierarchy — real trash-guide defaults
      - trash_ids:
          - 496f355514737f7d83bf7aa4d24f8169  # TrueHD ATMOS
        score: 5000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 2f22d89048b01681dde8afe203bf2e95  # DTS X
        score: 4500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 1af239278386be2919e1bcee0bde047e  # DD+ ATMOS
        score: 3000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 3cafb66171b47f226146a0770576870f  # TrueHD
        score: 2750
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - dcf3ec6938fa32445f590a4da84256cd  # DTS-HD MA
        score: 2500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - a570d4a0e56a2874b64e5bfa55202a1b  # FLAC
          - e7c2fcae07cbada050a0af3357491d7b  # PCM
        score: 2250
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 8e109e50e0a0b83a5098b056e13bf6db  # DTS-HD HRA
        score: 2000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 185f1dd7264c4562b9022d963ac37424  # DD+
        score: 1750
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - f9f847ac70a0af62ea4a08280b859636  # DTS-ES
        score: 1500
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 1c1a4c5e823891c75bc50380a6866f73  # DTS
        score: 1250
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - 240770601cc226190c367ef59aba7463  # AAC
        score: 1000
        assign_scores_to:
          - name: Asgard - Movies
      - trash_ids:
          - c2998bd0d90ed5621d8df281e839436e  # DD
        score: 750
        assign_scores_to:
          - name: Asgard - Movies
EOF
        chmod 600 /var/lib/recyclarr/recyclarr.yml
      '';
    };

    systemd.services.recyclarr-sync = {
      description = "Sync TRaSH Guides quality profiles via Recyclarr";
      after  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      wants  = [ "recyclarr-config.service" "sonarr.service" "radarr.service" "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config /var/lib/recyclarr/recyclarr.yml";
        # RECYCLARR_APP_DATA was removed upstream — recyclarr now hard-errors on it and the sync
        # never runs. CONFIG_DIR replaces it; DATA_DIR is optional and defaults to CONFIG_DIR.
        Environment = "RECYCLARR_CONFIG_DIR=/var/lib/recyclarr";
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Daily Recyclarr sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "24h";
      };
    };

    # nixflix's Jellyseerr wiring picks the default request profiles BY NAME
    # (nixflix.seerr.{radarr,sonarr} in jellyfin.nix) and fails if one is
    # missing — and recyclarr is what creates them. So both run after a sync.
    # The `wants` is what makes that ordering real: recyclarr-sync is otherwise
    # only started by its timer, and `after` on a unit that is not part of the
    # same transaction orders nothing. (arr-policy, in arr.nix, wants it too.)
    systemd.services.seerr-radarr = {
      wants = [ "recyclarr-sync.service" ];
      after = [ "recyclarr-sync.service" ];
    };
    systemd.services.seerr-sonarr = {
      wants = [ "recyclarr-sync.service" ];
      after = [ "recyclarr-sync.service" ];
    };

  };
}
