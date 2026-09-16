# ============================================================================
# Skwd-wall v2 — TEMPORARY hand-rolled packaging
# ============================================================================
#
# WHY THIS FILE EXISTS
#
# skwd-wall v2 is a full Rust rewrite of the old QuickShell selector, split
# across four repos. Upstream ships no usable flake yet: the v2 repo's own
# flake.nix just forwards to `github:liixini/skwd-wall/nix`, and that branch
# does not exist. The README lists NixOS as WIP.
#
# So everything needed to build v2 lives here, in one file, on purpose.
#
# TO RETIRE THIS FILE when upstream NixOS support lands:
#   1. delete Modules/Skwd.nix
#   2. delete the four `skwd-*-src` inputs from flake.nix
#   3. point `skwd-wall.url` at the v2 flake and use its nixosModules
# Nothing else in the tree needs to change.
#
# THE FOUR REPOS
#   skwd-wall   the GPU picker UI          -> skwd-wall
#   skwd-deck   daemon + CLI + templates   -> skwd-walld, skwd-helm,
#                                             skwd-wall-scan, skwd-wall-effects,
#                                             skwd-steam
#   skwd-paper  wallpaper compositor       -> skwd-paper
#   skwd-lens   local visual search        -> skwd-lens
#
# They share one workspace version (currently 1.0.0-beta.11) and skwd-wall
# depends on skwd-deck/skwd-lens through *relative source paths*, not crates.io
# — hence the postUnpack copies below. Update all four inputs together or the
# path deps resolve against mismatched sources.
#
# Recipe adapted from a working community build posted while upstream NixOS
# support is pending; the extras (desktop entry, icon, template share dir) and
# the module wiring are ours.
# ============================================================================
{ self, inputs, ... }:
let
  # A callPackage-style function so both `perSystem.packages` and the NixOS
  # module below instantiate the exact same derivation from one definition.
  skwdWallPackage =
    { pkg-config
    , rustPlatform
    , lib
    , bash
    , python3
    , makeWrapper
    , inputs
    , coreutils
    , clang
    , cmake
    , git
    , shaderc
    , ffmpeg
    , libxkbcommon
    , wayland
    , vulkan-headers
    , alsa-lib
    , dav1d
    , libyuv
    , libGL
    , vulkan-loader
    }:
    let
      cargoWall = builtins.fromTOML (builtins.readFile "${inputs.skwd-wall-src}/Cargo.toml");
      cargoDeck = builtins.fromTOML (builtins.readFile "${inputs.skwd-deck-src}/Cargo.toml");
      cargoLens = builtins.fromTOML (builtins.readFile "${inputs.skwd-lens-src}/Cargo.toml");
      cargoPaper = builtins.fromTOML (builtins.readFile "${inputs.skwd-paper-src}/Cargo.toml");

      # Tests in these repos shell out to absolute FHS paths that do not exist
      # in the sandbox. Rewriting them to store paths keeps the test suites
      # runnable rather than having to disable checks wholesale.
      patchShebangsInRust = ''
        while IFS= read -r -d ""; do
          substituteInPlace "$REPLY" --replace-quiet '#!/bin/sh' '#!${bash}/bin/sh'
        done < <(find . -name '*.rs' -print0)
      '';

      # These three suites are full of tests that write a helper script to a
      # tempdir and immediately exec it. Run in parallel, one test's fork()
      # inherits another's still-open write fd and the exec dies with ETXTBSY
      # ("Text file busy"). It is a genuine race, so it fails intermittently:
      # skwd-wall's semantic_pack::helper_report_decodes passed one build and
      # failed the next on identical sources, 1079 passed / 1 failed.
      # RUST_TEST_THREADS=1 removes the race without skipping any test.
      serialTests = { dontUseCargoParallelTests = true; };

      # ----------------------------------------------------------------
      # skwd-deck — the daemon (skwd-walld) and CLI surface
      # ----------------------------------------------------------------
      skwd-deck = rustPlatform.buildRustPackage (serialTests // {
        pname = "skwd-deck";
        version = cargoDeck.workspace.package.version;
        src = inputs.skwd-deck-src;
        cargoLock.lockFile = "${inputs.skwd-deck-src}/Cargo.lock";

        # deck's crates reference ../skwd-paper and ../skwd-lens by path.
        # --no-preserve is required: store sources are read-only and cargo
        # needs to write into the tree.
        postUnpack = ''
          cp -r --no-preserve=mode,ownership ${inputs.skwd-paper-src} $NIX_BUILD_TOP/skwd-paper
          cp -r --no-preserve=mode,ownership ${inputs.skwd-lens-src} $NIX_BUILD_TOP/skwd-lens
        '';

        # Only /bin/true needs rewriting: the sandbox does provide /bin/sh, so
        # the many Command::new("/bin/sh") test helpers resolve fine.
        #
        # These patterns are deliberately single-line. A multi-line --replace-fail
        # pattern cannot survive Nix's '' indentation stripping — the continuation
        # line gets re-indented to the block's common prefix and silently stops
        # matching the file, which fails the build in patchPhase.
        postPatch = ''
          substituteInPlace crates/skwd-walld/src/infrastructure/processes/tests.rs \
            --replace-fail 'Path::new("/bin/true")' 'Path::new("${coreutils}/bin/true")' \
            --replace-fail 'Command::new("/bin/true")' 'Command::new("${coreutils}/bin/true")'
          ${patchShebangsInRust}
        '';

        nativeCheckInputs = [ coreutils ];

        nativeBuildInputs = [
          pkg-config
          clang
          cmake
          rustPlatform.bindgenHook
          git
          python3
          shaderc
        ];

        buildInputs = [
          ffmpeg
          libxkbcommon
          wayland
          shaderc
        ];

        # The matugen templates upstream ships with the daemon. Distro packaging
        # puts these at /usr/share/skwd-wall-v2/data/matugen/templates; the
        # module below seeds the user template dir from here.
        #
        # cargo also installs two test harnesses that upstream's own packaging
        # manifest excludes (it ships exactly skwd-walld, skwd-wall-scan,
        # skwd-wall-effects, skwd-steam, skwd-helm). `fake_renderer` in
        # particular is far too generic a name to leave on a user's PATH.
        # libsteam_api.so is left alone — skwd-steam has a DT_NEEDED on it and
        # its rpath already resolves to $out/lib.
        postInstall = ''
          mkdir -p $out/share/skwd-wall-v2/data/matugen
          cp -r data/matugen/templates $out/share/skwd-wall-v2/data/matugen/templates
          rm -f $out/bin/fake_renderer $out/bin/theme-provider-contract
        '';
      });

      # ----------------------------------------------------------------
      # skwd-lens — local semantic image search
      # ----------------------------------------------------------------
      skwd-lens = rustPlatform.buildRustPackage {
        pname = "skwd-lens";
        version = cargoLens.workspace.package.version;
        src = inputs.skwd-lens-src;
        cargoLock.lockFile = "${inputs.skwd-lens-src}/Cargo.lock";
        nativeBuildInputs = [ pkg-config ];
        buildInputs = [
          libxkbcommon
          wayland
        ];
      };

      # ----------------------------------------------------------------
      # skwd-paper — the Vulkan wallpaper compositor
      # ----------------------------------------------------------------
      skwd-paper = rustPlatform.buildRustPackage (serialTests // {
        pname = "skwd-paper";
        version = cargoPaper.workspace.package.version;
        src = inputs.skwd-paper-src;
        cargoLock.lockFile = "${inputs.skwd-paper-src}/Cargo.lock";

        VULKAN_INCLUDE_DIR = "${vulkan-headers}/include";

        postPatch = ''
          substituteInPlace crates/paper-cli/src/server_tests.rs \
            --replace-fail '#!/usr/bin/python3' '#!${python3}/bin/python3'
          ${patchShebangsInRust}
        '';

        nativeCheckInputs = [ python3 bash ];

        nativeBuildInputs = [
          pkg-config
          cmake
          clang
          rustPlatform.bindgenHook
          git
          shaderc
        ];

        buildInputs = [
          libxkbcommon
          wayland
          shaderc
          alsa-lib
          ffmpeg
          dav1d
          libyuv
        ];

        # This package installs four binaries, not one:
        #   skwd-paper         composition controller the daemon talks to
        #   skwd-wall-still    image renderer          (layer namespace skwd-paper)
        #   skwd-wall-vk       Vulkan video/WE renderer (namespace skwd-wall-vk)
        #   skwd-paper-tinier  helper
        # The renderers reach Vulkan, GL and Wayland through dlopen, so nothing
        # records a DT_NEEDED and the automatic rpath comes up empty. Without
        # this the daemon starts fine and wallpapers simply never paint.
        postFixup = ''
          for b in $out/bin/*; do
            patchelf --add-rpath "${lib.makeLibraryPath [ wayland libGL vulkan-loader libxkbcommon ]}" "$b"
          done
        '';
      });
    in
    # ----------------------------------------------------------------
    # skwd-wall — the picker UI, and the package that ties the suite together
    # ----------------------------------------------------------------
    rustPlatform.buildRustPackage (serialTests // {
      pname = cargoWall.package.name;
      version = cargoWall.workspace.package.version;

      src = inputs.skwd-wall-src;

      # skwd-wall's Cargo.toml pulls wall-proto, skwd-config, skwd-log and
      # skwd-palette from ../skwd-deck/crates/* and ../skwd-lens/crates/*.
      postUnpack = ''
        cp -r --no-preserve=mode,ownership ${inputs.skwd-deck-src} $NIX_BUILD_TOP/skwd-deck
        cp -r --no-preserve=mode,ownership ${inputs.skwd-lens-src} $NIX_BUILD_TOP/skwd-lens
      '';

      postPatch = patchShebangsInRust;

      cargoLock = {
        lockFile = "${inputs.skwd-wall-src}/Cargo.lock";
        # Two forks the author maintains outside crates.io. If a flake update
        # moves these revs the build fails with a hash mismatch — take the
        # "got:" hash from the error and replace it here.
        outputHashes = {
          "iced_layershell-0.19.1" = "sha256-KyJGgLMtMuo51u/rBlQYeBij1fDaIvhGoiNQ2GO9HJI=";
          "iced_wgpu-0.14.0" = "sha256-SHgpOzwEus8oVfJqUW4VZH5vad2N1BlxJ8uh8TkvUNk=";
        };
      };

      nativeBuildInputs = [
        pkg-config
        makeWrapper
      ];

      buildInputs = [
        libxkbcommon
        wayland
      ];

      # Upstream's desktop entry uses Exec=skwd-wall-v2 / Icon=skwd-wall-v2
      # (that is the name the AUR and COPR packages install), but cargo builds
      # the binary as `skwd-wall`. Ship the alias rather than patching the
      # entry, so the README's keybind examples work verbatim.
      postInstall = ''
        install -Dm644 data/skwd-wall.desktop \
          $out/share/applications/skwd-wall-v2.desktop
        install -Dm644 data/skwd-wall.svg \
          $out/share/icons/hicolor/scalable/apps/skwd-wall-v2.svg
      '';

      # Vulkan/GL/Wayland are dlopen'd, so they leave no DT_NEEDED for the
      # normal rpath machinery to pick up — hence the explicit --add-rpath.
      postFixup = ''
        patchelf --add-rpath "${lib.makeLibraryPath [ wayland libGL vulkan-loader libxkbcommon ]}" $out/bin/skwd-wall
        wrapProgram $out/bin/skwd-wall \
          --prefix PATH : "${lib.makeBinPath [ skwd-deck skwd-lens skwd-paper ]}"
        ln -s $out/bin/skwd-wall $out/bin/skwd-wall-v2
      '';

      passthru = {
        inherit skwd-deck skwd-lens skwd-paper;
      };

      meta = {
        description = "GPU-rendered wallpaper picker and daemon suite (v2, Rust)";
        homepage = "https://github.com/liixini/skwd-wall";
        license = lib.licenses.gpl3Plus;
        platforms = lib.platforms.linux;
        mainProgram = "skwd-wall";
      };
    });
in
{
  # Exposed so the suite can be built and tested on its own, without a full
  # system rebuild:  nix build .#skwd-wall-v2
  perSystem = { pkgs, ... }: {
    packages.skwd-wall-v2 = pkgs.callPackage skwdWallPackage { inherit inputs; };
  };

  # ==========================================================================
  # NixOS module — Sisyphus only for now
  # ==========================================================================
  # v1 (Modules/skwd-wall.nix) still serves Elektra and Odysseus. The two can
  # coexist on disk: v2 uses ~/.config/skwd-wall-v2 and ~/.cache/skwd-wall-v2,
  # so nothing here touches the v1 config. Upstream's own unit even declares
  # Conflicts=skwd-daemon.service, so only one daemon can run at a time.
  flake.nixosModules.skwd = { pkgs, activeUser, ... }:
  let
    skwd = pkgs.callPackage skwdWallPackage { inherit inputs; };
    inherit (skwd.passthru) skwd-deck skwd-lens skwd-paper;
  in {
    # `lib` comes from home-manager here, not the NixOS module args — the
    # activation script below needs lib.hm.dag, which only exists on HM's lib.
    home-manager.users.${activeUser} = { config, lib, ... }:
    let
      configPath = "${config.home.homeDirectory}/.config/skwd-wall-v2";
      templateDir = "${configPath}/data/matugen/templates";

      # Same store-backed templates v1 used, so btop's and Steam's colour
      # mappings still have exactly one definition (Modules/btop.nix,
      # Modules/steam.nix) shared with the static fallback themes.
      btopTemplate = pkgs.writeText "btop-theme.theme" self.lib.btop.matugenTemplate;
      steamTemplate = pkgs.writeText "steam-quick.css" self.lib.steam.matugenTemplate;
    in {
      # ============================================================
      # PACKAGES
      # ============================================================
      # skwd-wall is wrapped with deck/lens/paper on its PATH already; deck is
      # listed separately so skwd-helm and skwd-wall-scan are usable from a
      # shell. No binary names collide between the two.
      home.packages = [ skwd skwd-deck pkgs.matugen ];

      # ============================================================
      # DAEMON
      # ============================================================
      # v2 splits the old single skwd-daemon into a supervisor (skwd-walld,
      # from skwd-deck) that spawns skwd-paper per output. The picker itself is
      # no longer a resident process — it starts on demand and exits on close.
      systemd.user.services.skwd-walld = {
        Unit = {
          Description = "Skwd wallpaper daemon (v2)";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${skwd-deck}/bin/skwd-walld --wait-for-session";
          Restart = "on-failure";
          RestartSec = 2;
          # The daemon shells out to two different kinds of thing: its own
          # helpers (skwd-paper, skwd-lens) and our integration reload commands
          # (noctalia-sync-wallpaper, spotify-apply-colors, btop-reload-theme),
          # which are home.packages and therefore live in the user profile.
          # Both have to be on PATH here or reloads fail with exit status 127.
          Environment = [
            "PATH=${lib.makeBinPath [ skwd-deck skwd-paper skwd-lens pkgs.matugen pkgs.coreutils ]}:%h/.nix-profile/bin:/etc/profiles/per-user/${activeUser}/bin:/run/current-system/sw/bin"
          ];
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # ============================================================
      # CONFIG + MATUGEN TEMPLATES
      # ============================================================
      # Deliberately NOT a full seeded config.json like v1 had. v2's schema is
      # far larger and it normalises its own defaults on first run, so a
      # hand-written seed would go stale fast and fight the settings UI. We
      # create the file only if missing, then patch in just the parts Nix owns.
      home.activation.skwdWallV2Config = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${templateDir}"

        if [ ! -f "${configPath}/config.json" ]; then
          cat > "${configPath}/config.json" << 'EOF'
{
  "monitor": "DP-2",
  "paths": {
    "wallpaper": "~/Pictures/Wallpapers",
    "videoWallpaper": "~/Pictures/Wallpapers",
    "steam": "~/.local/share/Steam"
  },
  "features": {
    "matugen": true,
    "steam": true,
    "wallhaven": true
  },
  "matugen": {
    "schemeType": "scheme-tonal-spot",
    "mode": "dark"
  },
  "wallpaperMute": true
}
EOF
        fi

        # Pin the three renderer binaries to this generation's store paths.
        # They could be found on PATH instead, but pinning means a rebuild can
        # never leave the daemon talking to a renderer from an older build —
        # and skwd-wall-still / skwd-wall-vk are not names anything else would
        # resolve sensibly.
        ${pkgs.jq}/bin/jq \
          --arg paper "${skwd-paper}/bin/skwd-paper" \
          --arg still "${skwd-paper}/bin/skwd-wall-still" \
          --arg vk    "${skwd-paper}/bin/skwd-wall-vk" '
          .paths = ((.paths // {})
            | .paperBin = $paper
            | .paperStillBin = $still
            | .paperVkBin = $vk)
        ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
          && mv "${configPath}/config.json.tmp" "${configPath}/config.json"

        # ---- Integrations ----
        # Same contract as v1: matugen renders each template after a wallpaper
        # change, then runs the integration's `reload` command (no arguments).
        # Every entry is upserted by name so hand-edits in the settings UI
        # survive and repeated rebuilds cannot stack duplicates.
        ${pkgs.jq}/bin/jq '
          def upsert($entry):
            if (.integrations // []) | map(.name) | index($entry.name) then
              .integrations = (.integrations | map(if .name == $entry.name then . * $entry else . end))
            else
              .integrations = ((.integrations // []) + [$entry])
            end;

          # noctalia carries no reload command on purpose — see postProcessing below.
          upsert({name: "noctalia", template: "noctalia-colors.json", output: "~/.config/noctalia/colors.json"})
          | .integrations = (.integrations | map(if .name == "noctalia" then del(.reload) else . end))

          | upsert({name: "spicetify", template: "spicetify-text.ini", output: "~/.config/spicetify/Themes/text/color.ini"})
          | upsert({name: "spicetify-live", template: "spicetify-colors.json", output: "~/.config/spicetify/matugen-colors.json", reload: "spotify-apply-colors"})
          | upsert({name: "btop", template: "btop-theme.theme", output: "~/.config/btop/themes/${self.lib.btop.themeName}.theme", reload: "btop-reload-theme"})

          # Steam gets no reload: Millennium Quick CSS cannot be re-read from
          # outside the client, so a new accent lands at the next Steam launch.
          | upsert({name: "steam", template: "steam-quick.css", output: "~/${self.lib.steam.quickCssPath}"})

          # postProcessing, NOT integrations[].reload. Reload commands run with
          # no arguments, which forces reading the last-wallpaper cache — and
          # skwd writes that cache AFTER running its hooks, so every swap acted
          # on the previous wallpaper. %path% is substituted with the wallpaper
          # actually being applied. See Claude/skwd-wall.md for the measurement.
          | .postProcessing = (((.postProcessing // [])
              | map(select((.command // "") | test("noctalia-sync-wallpaper") | not)))
              + [{command: "noctalia-sync-wallpaper %path%", type: "all"}])
          | .postProcessOnRestore = true
        ' "${configPath}/config.json" > "${configPath}/config.json.tmp" \
          && mv "${configPath}/config.json.tmp" "${configPath}/config.json"

        # ---- Templates ----
        # Upstream's shipped set first (only where absent, so edits stick),
        # then the ones Nix owns, which are always refreshed.
        for t in ${skwd-deck}/share/skwd-wall-v2/data/matugen/templates/*; do
          [ -e "$t" ] || continue
          [ -e "${templateDir}/$(basename "$t")" ] || install -m 0644 "$t" "${templateDir}/"
        done

        # Mode 0644, not the 0444 of a store copy — the next rebuild has to be
        # able to overwrite these, and matugen only ever reads them.
        install -m 0644 ${btopTemplate} "${templateDir}/btop-theme.theme"
        install -m 0644 ${steamTemplate} "${templateDir}/steam-quick.css"

        cat > "${templateDir}/noctalia-colors.json" << 'EOF'
{
  "mPrimary": "{{colors.primary.default.hex}}",
  "mOnPrimary": "{{colors.on_primary.default.hex}}",

  "mSecondary": "{{colors.secondary.default.hex}}",
  "mOnSecondary": "{{colors.on_secondary.default.hex}}",

  "mTertiary": "{{colors.tertiary.default.hex}}",
  "mOnTertiary": "{{colors.on_tertiary.default.hex}}",

  "mError": "{{colors.error.default.hex}}",
  "mOnError": "{{colors.on_error.default.hex}}",

  "mSurface": "#0a0a0a",
  "mOnSurface": "#e0e0e0",

  "mSurfaceVariant": "#1a1a1a",
  "mOnSurfaceVariant": "#c0c0c0",

  "mOutline": "#333333",
  "mShadow": "#000000",

  "mHover": "{{colors.tertiary.default.hex}}",
  "mOnHover": "{{colors.on_tertiary.default.hex}}"
}
EOF

        cat > "${templateDir}/spicetify-colors.json" << 'EOF'
{
  "--spice-text": "{{colors.on_primary_container.default.hex}}",
  "--spice-subtext": "{{colors.on_surface_variant.default.hex}}",
  "--spice-main": "{{colors.surface.default.hex}}",
  "--spice-accent": "{{colors.primary.default.hex}}",
  "--spice-accent-active": "{{colors.primary_container.default.hex}}",
  "--spice-accent-inactive": "{{colors.surface.default.hex}}",
  "--spice-banner": "{{colors.primary.default.hex}}",
  "--spice-border-active": "{{colors.primary.default.hex}}",
  "--spice-border-inactive": "{{colors.outline.default.hex}}",
  "--spice-header": "{{colors.primary_container.default.hex}}",
  "--spice-highlight": "{{colors.surface_container.default.hex}}",
  "--spice-notification": "{{colors.primary_container.default.hex}}",
  "--spice-notification-error": "{{colors.error.default.hex}}"
}
EOF

        cat > "${templateDir}/spicetify-text.ini" << 'EOF'
[Matugen]
accent             = {{colors.primary.default.hex_stripped}}
accent-active      = {{colors.primary_container.default.hex_stripped}}
accent-inactive    = {{colors.surface.default.hex_stripped}}
banner             = {{colors.primary.default.hex_stripped}}
border-active      = {{colors.primary.default.hex_stripped}}
border-inactive    = {{colors.outline.default.hex_stripped}}
header             = {{colors.primary_container.default.hex_stripped}}
highlight          = {{colors.surface_container.default.hex_stripped}}
main               = {{colors.surface.default.hex_stripped}}
notification       = {{colors.primary_container.default.hex_stripped}}
notification-error = {{colors.error.default.hex_stripped}}
subtext            = {{colors.on_surface_variant.default.hex_stripped}}
text               = {{colors.on_primary_container.default.hex_stripped}}
EOF
      '';
    };
  };
}
