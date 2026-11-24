# ============================================================================
# Battle.net — the Blizzard launcher under Proton, with no Steam involved
# ============================================================================
#
# There is no Battle.net package in nixpkgs, nothing for it in nix-gaming, and
# the only community flake calling itself one (lytedev/battlenet-flake) is a
# `nix develop` shell last touched in 2023 that tells you to follow the wiki's
# wine steps by hand. So this is ours.
#
# ── Why umu-run and not wine ─────────────────────────────────────────────────
# `umu-run` IS Proton outside Steam: the Open-Wine-Components launcher that
# Lutris, Heroic and Bottles all moved to. It takes the very same GE-Proton
# build Steam uses here (PROTONPATH points straight at the store path that
# programs.steam.extraCompatPackages already pulls in), runs it inside the same
# Steam Linux Runtime container, and involves no Steam client at all.
#
# The alternative — the NixOS wiki's wine-staging prefix — is the route where
# the login screen crashes and people trade WINE_SIMULATE_WRITECOPY=1 hacks.
# Battle.net is a well-trodden Proton target; it is not a well-trodden
# bare-wine one.
#
# ── What is NOT declarative here, and why it cannot be ───────────────────────
# Two things, both genuine exceptions to the CLAUDE.md core principle rather
# than oversights:
#
#   1. The Wine prefix (~/Games/Battle.net). Imperative state by construction,
#      exactly like Steam's compatdata. Nothing reproduces a prefix from a
#      config file.
#   2. The Steam Linux Runtime container. umu reads `require_tool_appid` out of
#      the Proton's toolmanifest.vdf and downloads that runtime into
#      ~/.local/share/umu on first launch — a few hundred MB. nixpkgs has no
#      sniper/steamrt4 container to substitute, so there is no Nix answer to
#      this. It self-heals if deleted.
#
# And the Battle.net client itself self-updates the moment it starts, so
# pinning the installer below buys a reproducible first byte and nothing else.
#
# What that leaves Nix owning: the launcher command, the Proton build, the
# installer's first byte, the desktop entry, and the font-registry sweep that
# keeps the prefix from wedging after a nix-gc. A fresh install needs no manual
# steps — the first `battlenet` builds the prefix and installs the client — but
# it does need the network, which is the honest limit here.
#
# ── Sisyphus only ────────────────────────────────────────────────────────────
# Listed in Hosts/Sisyphus/system.nix. Nothing stops Elektra importing it, but
# it drags umu-launcher and a second GE-Proton reference onto her machine for
# no reason — see `shared-module-cross-host-trap`.
{ ... }:
let
  # Blizzard's installer stub. The unversioned
  # downloader.battle.net/download/getInstaller?... URL 302s to this versioned
  # one, which IS stable and so is pinnable; the redirect target is not.
  #
  # To refresh:
  #   curl -sIL 'https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe' | grep -i ^location
  #   nix store prefetch-file <that URL>
  #
  # No hurry about it, though: this is a 4.7MB stub whose only job is to
  # download a client that then self-updates. A stale pin costs nothing.
  installerVersion = "1.0.69";
  installerHash = "sha256-9GQ6IIbAzssatozGAb84waCm9+9ZFK0DN1zJRJOFvsY=";
in {
  flake.nixosModules.battlenet = { config, lib, pkgs, activeUser, ... }:
  let
    cfg = config.my.battlenet;

    installer = pkgs.fetchurl {
      name = "Battle.net-Setup-${installerVersion}.exe";
      url = "https://downloader.battle.net/download/installer/win/${installerVersion}/Battle.net-Setup.exe";
      hash = installerHash;
    };

    # ⚠️ `.steamcompattool`, NOT the package itself. proton-ge-bin's default
    # output is a 112-byte FILE (a marker that programs.steam consumes); the
    # actual tree — `proton`, `files/`, `protonfixes/`, toolmanifest.vdf — hangs
    # off this passthru. PROTONPATH pointed at the package resolves to a
    # non-directory and umu fails on it.
    protonDir = "${cfg.protonPackage.steamcompattool}";

    # Same shape as Modules/Shell/deploy-tools.nix: the body is plain bash in
    # ── The icon, extracted at BUILD time from the pinned installer ───────────
    # Blizzard ships the Battle.net logo as an icon resource inside
    # Battle.net-Setup.exe — byte-identical to the one in the installed client
    # (same 112322-byte group), so the pinned FOD above is a complete source and
    # nothing has to be committed to the repo or fetched separately.
    #
    # ⚠️ This REPLACED a runtime extraction in the launcher script, which was
    # wrong twice over: it could not produce an icon until after the first
    # successful launch, and it wrote to ~/.local/share/icons — which is NOT on
    # XDG_DATA_DIRS here, while the desktop entry lands on the profile path. The
    # entry resolved Icon=battlenet against a directory it never searched, so
    # the launcher fell back to a generic cog. Verified 2026-11-22.
    #
    # The trailing `test` is deliberate: if Blizzard ever restructures the
    # resources, this fails the BUILD rather than silently shipping no icon.
    battlenetIcon = pkgs.runCommand "battlenet-icon" {
      nativeBuildInputs = [ pkgs.icoutils ];
    } ''
      wrestool -x -t 14 -o . ${installer}

      # ⚠️ icotool ABORTS PARTWAY on this .ico and exits 1:
      #   "incorrect total size of bitmap (10068 specified; 4264 real)"
      # One entry in Blizzard's icon group has a corrupt size field. It still
      # writes every image it decoded BEFORE reaching that entry, so the exit
      # code is ignored on purpose. Do NOT "fix" this by looping with
      # `icotool -w <size>`: only the sizes that happen to be ordered before
      # the bad entry survive, which silently yields 256x256 alone.
      icotool -x -o . ./*.ico || true

      for png in ./*x32.png; do
        [ -e "$png" ] || continue
        size=''${png##*_}        # ..._4_256x256x32.png -> 256x256x32.png
        size=''${size%x32.png}   #                      -> 256x256
        install -Dm644 "$png" "$out/share/icons/hicolor/$size/apps/battlenet.png"
      done

      # The real guard: if Blizzard restructures the resources this fails the
      # BUILD rather than silently shipping a cog.
      test -e "$out/share/icons/hicolor/256x256/apps/battlenet.png"
    '';

    # Resources/Scripts so `shellcheck` works on it directly and there is no
    # ''${ } escaping to get wrong. The one difference is this preamble — two
    # store paths cannot arrive over PATH, so they arrive as defaulted env
    # vars, which also leaves them overridable for a one-off test.
    battlenet = pkgs.writeShellApplication {
      name = "battlenet";
      runtimeInputs = [
        pkgs.umu-launcher
        pkgs.coreutils
        pkgs.diffutils    # cmp, in the registry sweep
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.procps       # pgrep, to refuse the sweep under a live wineserver
      ];
      text = ''
        # ── Generated by Modules/Gaming/battlenet.nix ──
        : "''${BATTLENET_PROTON:=${protonDir}}"
        : "''${BATTLENET_INSTALLER:=${installer}}"
      '' + lib.optionalString (cfg.prefix != null) ''
        : "''${BATTLENET_PREFIX:=${cfg.prefix}}"
      '' + builtins.readFile ../../Resources/Scripts/battlenet.sh;
    };

    battlenetOptions = { lib, ... }: {
      options.my.battlenet.protonPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.proton-ge-bin;
        defaultText = lib.literalExpression "pkgs.proton-ge-bin";
        description = ''
          The Proton build Battle.net runs under. Must be a package with a
          `steamcompattool` passthru — i.e. proton-ge-bin, or any of the
          `proton-ge-bin.overrideAttrs` variants.

          Deliberately a knob and not a constant. Two reasons:

          1. The newest Proton is not automatically the right one. See
             `black-desert-proton-experimental-regression`: a game that worked
             in September broke in November with no local change, and the fix
             was rolling Proton BACK. If the launcher breaks after a
             `nix flake update`, pinning an older GE here is the cheap first
             move — not a new wine prefix.
          2. It decides which runtime container umu downloads. GE-Proton11
             requires appid 4183110 (steamrt4); GE-Proton10 requires 1628350
             (sniper), which has far more mileage on it. Changing this can mean
             a second few-hundred-MB fetch.
        '';
      };

      options.my.battlenet.prefix = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/mnt/games/Battle.net";
        description = ''
          Absolute path to the Proton prefix. null leaves the script's own
          default, $HOME/Games/Battle.net — which is where it belongs unless
          the games are going on another disk.

          Note the C: drive is `<prefix>/pfx/drive_c`: Proton appends /pfx to
          STEAM_COMPAT_DATA_PATH, which umu sets to this directory. ⚠️ With
          WINEPREFIX set explicitly umu makes `pfx` a symlink to `.`, so
          `<prefix>/pfx` and `<prefix>` are the same directory — verified
          2026-11-22. Both spellings work.

          ⚠️ Treat this directory like Steam's compatdata — it is where the
          installed games live. Never sweep it (see
          `sisyphus-disk-reclaim-sweep`).
        '';
      };
    };
  in {
    imports = [ battlenetOptions ];

    environment.systemPackages = [ battlenet battlenetIcon ];

    home-manager.users.${activeUser} = {
      xdg.desktopEntries.battlenet = {
        name = "Battle.net";
        exec = "battlenet";
        # Resolved from battlenetIcon above, which is in systemPackages — so it
        # lands on /run/current-system/sw/share/icons, which IS on
        # XDG_DATA_DIRS, and it exists before the first launch ever happens.
        # ⚠️ ~/.local/share/icons is NOT on XDG_DATA_DIRS here, while this
        # entry is written to /etc/profiles/per-user/<user>/share/applications —
        # see the icon derivation's header for the generic cog that cost.
        icon = "battlenet";
        comment = "Blizzard launcher, under Proton";
        categories = [ "Game" ];
        terminal = false;
        settings = {
          # ⚠️ VERIFIED LIVE 2026-11-22 with `niri msg windows`. NOT "battle.net.exe":
          # umu sets SteamAppId=battlenet (from GAMEID umu-battlenet), so Proton
          # stamps the X11 WM_CLASS as steam_app_battlenet — which also means it
          # MATCHES the generic `^steam_app_` games rule in Modules/Desktop/niri.nix.
          StartupWMClass = "steam_app_battlenet";
        };
      };
    };
  };
}
