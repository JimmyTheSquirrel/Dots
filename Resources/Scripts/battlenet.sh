# battlenet — the Battle.net launcher under Proton, with Steam out of the picture.
#
# Packaged by Modules/Gaming/battlenet.nix, which prepends two store paths as
# defaults (BATTLENET_PROTON, BATTLENET_INSTALLER) and may prepend a third
# (BATTLENET_PREFIX). writeShellApplication puts errexit/nounset/pipefail on and
# runs shellcheck at build time.
#
# ── What this actually is ─────────────────────────────────────────────────────
# `umu-run` is Proton outside Steam: the same GE-Proton build that Steam uses
# (PROTONPATH points straight at the one in the store), run inside the same
# Steam Linux Runtime container, with none of the Steam client involved. It is
# what Lutris, Heroic and Bottles all call now, so this is the maintained path
# rather than a hand-rolled wine prefix.
#
# ⚠️ One unavoidable download. umu reads `require_tool_appid` out of the
# Proton's toolmanifest.vdf and fetches that Steam Linux Runtime itself, into
# ~/.local/share/umu (cache in ~/.cache/umu). Nix cannot supply it — nixpkgs has
# no sniper/steamrt container — so the first launch pulls a few hundred MB. It
# self-heals if deleted, and UMU_RUNTIME_UPDATE is pinned to 0 below so it never
# silently moves under a working install afterwards (see
# `black-desert-proton-experimental-regression` for what an auto-updating Proton
# costs).
#
# ── The prefix is NOT declarative, and cannot be ──────────────────────────────
# A Wine prefix is imperative state by construction, and the Battle.net client
# is a self-updating installer besides. What Nix owns here is the launcher, the
# Proton build, the installer's first byte and the desktop entry; what lives in
# ~/Games/Battle.net is the same class of thing as Steam's compatdata. A fresh
# install needs no manual steps — the first `battlenet` builds the prefix and
# installs the client — but it does need the network.

prefix="${BATTLENET_PREFIX:-$HOME/Games/Battle.net}"
reinstall=0
update_runtime=0
proton_log=0
exe=""
args=()

usage() {
  cat <<'EOF'
battlenet — Battle.net under Proton, without Steam

  battlenet                    launch it; installs the client on first run
  battlenet --reinstall        re-run the Blizzard installer in this prefix
  battlenet --prefix DIR       use another prefix (default ~/Games/Battle.net)
  battlenet --exe PATH         run some other .exe in this prefix
  battlenet --log              PROTON_LOG=1; the log lands in ~/
  battlenet --update-runtime   let umu update the Steam Linux Runtime
  battlenet -- ARGS...         pass ARGS through to the launcher

The launcher breaks after some Proton updates — upstream's documented fix is
--reinstall, which re-runs the installer over the existing prefix.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reinstall)      reinstall=1; shift ;;
    --update-runtime) update_runtime=1; shift ;;
    --log)            proton_log=1; shift ;;
    --prefix)
      if [ "$#" -lt 2 ]; then
        printf 'battlenet: --prefix needs a directory\n' >&2
        exit 2
      fi
      prefix="$2"
      shift 2
      ;;
    --exe)
      if [ "$#" -lt 2 ]; then
        printf 'battlenet: --exe needs a path\n' >&2
        exit 2
      fi
      exe="$2"
      shift 2
      ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; args=("$@"); break ;;
    *)
      printf 'battlenet: unknown argument: %s (try --help)\n' "$1" >&2
      exit 2
      ;;
  esac
done

case "$prefix" in
  /*) ;;
  *)
    printf 'battlenet: --prefix must be an absolute path: %s\n' "$prefix" >&2
    exit 2
    ;;
esac

# Everything that inspects the prefix goes through $prefix/pfx, because Proton
# appends /pfx to STEAM_COMPAT_DATA_PATH (which umu sets to WINEPREFIX).
#
# ⚠️ VERIFIED 2026-11-22, and it is NOT what a Steam compatdata looks like:
# when WINEPREFIX is set explicitly, umu builds the prefix directly in it and
# makes `pfx` a SYMLINK TO `.` — so $prefix/pfx and $prefix are the same
# directory, same inode, and an `ls` shows drive_c twice. Going through /pfx is
# correct either way, so do not "fix" these paths after seeing that symlink.
pfx="$prefix/pfx"
launcher="$pfx/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"

# ── Sweep garbage-collected font paths out of the prefix registry ─────────────
# Home Manager hands fontconfig a RAW /nix/store path for its font directory,
# which changes with every generation, alongside the stable
# /etc/profiles/per-user/... one. Wine bakes whichever it sees into the prefix
# registry. After a nix-gc those paths are gone, and the next `wineboot --init`
# drops into Wine's case-insensitive path fallback: a full enumeration of
# /nix/store, per dead font, forever. The symptom is not an error — it is the
# launcher never appearing at all.
#
# This is a diagnosed repeat offender on this machine (it wedged six Steam
# prefixes on 2026-11-11, one with 12,339 dead font entries), and it recurs
# after every nix-gc, so sweep rather than wait to be bitten.
sweep_dead_fonts() {
  local reg tmp list token dead swept=0

  [ -d "$pfx" ] || return 0

  # NEVER edit a registry under a live wineserver: it holds its own copy in
  # memory and writes it back over ours when it exits. Any wineserver counts,
  # including one belonging to a Steam game in a different prefix — so skipping
  # is the safe answer, not a narrower match.
  if pgrep -u "$(id -u)" -x wineserver >/dev/null 2>&1; then
    return 0
  fi

  for reg in "$pfx/system.reg" "$pfx/user.reg"; do
    [ -f "$reg" ] || continue

    dead=()
    while read -r token; do
      [ -n "$token" ] || continue
      [ -e "/nix/store/$token" ] || dead+=("$token")
      # Anchored on the literal `store\\` the registry writes, not on a bare
      # 32-char run — an MD5 in some unrelated value would match that and get
      # its line deleted.
    done < <(grep -oE 'store\\\\[0-9a-z]{32}-[A-Za-z0-9._+-]+' "$reg" \
               | sed 's/^.*store\\\\//' | sort -u)

    [ "${#dead[@]}" -gt 0 ] || continue

    list="$(mktemp)"
    tmp="$(mktemp "$reg.sweep.XXXXXX")"
    printf '%s\n' "${dead[@]}" > "$list"

    # VALUE lines only — they start with a quote. A section header that
    # happened to mention a dead path would orphan all of its values into the
    # preceding key if it were deleted.
    awk '
      NR == FNR { dead[$0]; next }
      substr($0, 1, 1) == "\"" { for (t in dead) if (index($0, t)) next }
      { print }
    ' "$list" "$reg" > "$tmp"

    if ! cmp -s "$reg" "$tmp"; then
      [ -f "$reg.bak" ] || cp -p "$reg" "$reg.bak"
      # Write THROUGH the file rather than renaming over it, so the registry
      # keeps its mode and inode.
      cat "$tmp" > "$reg"
      swept=1
    fi
    rm -f "$tmp" "$list"
  done

  if [ "$swept" = 1 ]; then
    printf 'battlenet: swept garbage-collected font paths out of the prefix registry\n' >&2
  fi
}

run_proton() {
  local -a vars=(
    "WINEPREFIX=$prefix"
    # umu wants a GAMEID. `battlenet` is a real STORE namespace in protonfixes
    # (GE-Proton ships a gamefixes-battlenet package), it just has no per-game
    # fixes in it — so this resolves to the default fix, which is what we want.
    "GAMEID=umu-battlenet"
    "STORE=battlenet"
    "PROTONPATH=$BATTLENET_PROTON"
    "UMU_RUNTIME_UPDATE=$update_runtime"
  )

  if [ "$proton_log" = 1 ]; then
    vars+=("PROTON_LOG=1")
  fi

  env "${vars[@]}" umu-run "$@"
}

mkdir -p "$prefix"
sweep_dead_fonts

if [ -z "$exe" ] && { [ ! -f "$launcher" ] || [ "$reinstall" = 1 ]; }; then
  # Battle.net-Setup.exe is a ~4.7MB stub that downloads the real client, so
  # this step needs the network and takes a few minutes. Pinning it in Nix buys
  # a reproducible FIRST byte and nothing more — the client self-updates to
  # whatever Blizzard is shipping the moment it starts.
  #
  # Copied out of the store first: the installer unpacks beside itself, and
  # Proton exports the exe's own directory as STEAM_COMPAT_INSTALL_PATH, which
  # must not be a read-only store path.
  mkdir -p "$prefix/installer"
  install -m 0755 "$BATTLENET_INSTALLER" "$prefix/installer/Battle.net-Setup.exe"
  printf 'battlenet: running the Blizzard installer in %s (downloads the client)\n' "$prefix" >&2
  run_proton "$prefix/installer/Battle.net-Setup.exe"
fi

if [ -z "$exe" ]; then
  if [ ! -f "$launcher" ]; then
    printf 'battlenet: the installer finished but there is no launcher at:\n  %s\n' "$launcher" >&2
    printf 'battlenet: if you cancelled it, re-run with --reinstall.\n' >&2
    exit 1
  fi
  exe="$launcher"
fi

run_proton "$exe" "${args[@]}"
