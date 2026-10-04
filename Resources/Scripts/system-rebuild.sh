# system-rebuild — the control panel for this repo: rebuild the machine you're
# on, deploy to the others over the tailnet, look after the repo and the store,
# and drive the Apollo USB. Packaged by Modules/Shell/deploy-tools.nix, which
# prepends lib/ui.sh (the look, panels and the menu engine) and runs it all
# through writeShellApplication: errexit/nounset/pipefail on, shellcheck at
# build time.
#
#   system-rebuild                                    home screen + menus
#   system-rebuild USER SYSTEM [--boot|--build] [--target HOST]
#
# WHERE IT RUNS DECIDES WHAT "LOCAL" MEANS. The machine is matched by hostname
# (DOTS_HOST overrides it). On Sisyphus, `system-rebuild kitkat Kit-Kat` pushes
# to her machine over the tailnet; on Kit-Kat itself the very same command
# rebuilds Kit-Kat in place. No flag to remember, no "can't reach kit-kat"
# when you're sitting at it.
#
# Every rebuild — menu or CLI, local or remote — is the same three steps:
#   1. build  nom build <flake>#nixosConfigurations.<user>-<Host>.config.system.build.toplevel
#   2. diff   dix <what is running> <what was built>
#   3. apply  nixos-rebuild <switch|boot> --no-reexec --store-path <built path>
#             (-p <profile> for a named one; --target-host for another machine)
# Building first and handing nixos-rebuild the finished store path (supported
# since nixos-rebuild-ng) evaluates the flake once, gives the build nom's live
# tree, and keeps all of nixos-rebuild's own activation logic: profiles, the
# systemd-run wrapper that survives a dropped SSH session, and copying the
# closure to a remote host.
#
# The flake is ~/Dots (DOTS_DIR overrides it). A machine with no checkout —
# Kit-Kat, usually — builds github:JimmyTheSquirrel/Dots (main) instead, and
# the jobs that need a working tree (git sync, update inputs) step aside.
#
# The UI is inline: it draws in the normal scrollback and never takes over the
# screen, so what happened stays readable after it exits.
#
# ── Adding to the menus ───────────────────────────────────────────────────────
# Each menu is one function (menu_main, menu_rebuild, menu_remote, …). It lists
# its rows — `ui_item KEY ICON LABEL DESC META [COLOUR]` — shows them with
# `ui_menu ACCENT CRUMB…`, and dispatches on $UI_CHOICE in a case. A new job is
# one ui_item line plus one case arm calling `job <function> [args]`; a new
# section is a menu_* function plus its row in menu_main. The engine — keys,
# drawing, breadcrumbs — is lib/ui.sh. A new machine is one line in host_info.

# ── Machines ──────────────────────────────────────────────────────────────────
HOSTS=(Sisyphus Kit-Kat Asgard Apollo)

# host_info NAME — sets, for that machine:
#   H_USER     flake user (the attr is H_USER-NAME) and its ssh login
#   H_SSH      tailnet name, or "-" for none
#   H_PROFILE  "system", or a named profile (-p). Sisyphus keeps its own, one
#              entry among GRUB's System Select (Claude/architecture.md)
#   H_MODE     push     deployed from whichever machine runs this
#              managed  edited and rebuilt on itself; pushing to it is opt-in
#              stick    a USB stick: built, never activated from here
#   H_ROLE, H_ICON — how the menus show it
host_info() {
  case "$1" in
    Sisyphus) H_USER=rock   H_SSH=sisyphus H_PROFILE=sisyphus H_MODE=push    H_ROLE="rock's desktop" H_ICON=$'' ;;
    Kit-Kat)  H_USER=kitkat H_SSH=kit-kat  H_PROFILE=system   H_MODE=push    H_ROLE="her machine"    H_ICON=$'' ;;
    Asgard)   H_USER=rock   H_SSH=asgard   H_PROFILE=system   H_MODE=managed H_ROLE="media server"   H_ICON=$'' ;;
    Apollo)   H_USER=rock   H_SSH=-        H_PROFILE=-        H_MODE=stick   H_ROLE="deployer USB"   H_ICON=$'' ;;
    *) return 1 ;;
  esac
}

# The machine this is running on, if it is one of ours.
THIS_HOST=""
_me=${DOTS_HOST:-$(uname -n)}
for _h in "${HOSTS[@]}"; do
  if [[ "${_h,,}" == "${_me,,}" ]]; then THIS_HOST=$_h; fi
done
unset _h _me

# ── Where the flake is ────────────────────────────────────────────────────────
DOTS_FLAKE="github:JimmyTheSquirrel/Dots"
DOTS_URL="https://github.com/JimmyTheSquirrel/Dots"
DOTS="" FLAKE="" FLAKE_LABEL=""
find_repo() {
  local tilde='~'
  DOTS="${DOTS_DIR:-$HOME/Dots}"
  if [[ -f "$DOTS/flake.nix" ]]; then
    cd "$DOTS"
    FLAKE="."
    FLAKE_LABEL=$DOTS
    [[ "$DOTS" == "$HOME"/* ]] && FLAKE_LABEL="$tilde/${DOTS#"$HOME"/}"
  else
    DOTS="" FLAKE="$DOTS_FLAKE" FLAKE_LABEL="$DOTS_FLAKE"
  fi
  return 0
}
find_repo

# ── Icons (Nerd Font, Font Awesome range) ─────────────────────────────────────
I_REBUILD=$'' I_REMOTE=$'' I_UTILS=$'' I_APOLLO=$''
I_SWITCH=$'' I_BOOT=$'' I_BUILD=$'' I_OTHER=$''
I_SSH=$'' I_PULL=$'' I_PUSH=$'' I_DIFF=$''
I_GIT=$'' I_UPDATE=$'' I_GC=$'' I_CHECK=$'' I_CLONE=$''
I_DEPLOY=$'' I_ISO=$'' I_KEY=$'' I_DRY=$'' I_VM=$'' I_WARN=$''

# ── Tailnet ───────────────────────────────────────────────────────────────────
TS_JSON=""
ts_load() { TS_JSON=$(timeout 3 tailscale status --json 2>/dev/null || true); }

# ts_peer PREFIX → "state<TAB>ip<TAB>path<TAB>lastSeen" for the best-matching
# peer whose HostName starts with PREFIX (online ones win, so "apollo" finds
# whichever stick is booted). state is online / offline / missing / unknown.
ts_peer() {
  if [[ -z "$TS_JSON" ]]; then printf 'unknown\t-\t-\t-\n'; return; fi
  jq -r --arg n "$1" '
    [ .Peer[]? | select((.HostName // "" | ascii_downcase) | startswith($n)) ]
    | sort_by(.Online | not) | first
    | if . == null then "missing\t-\t-\t-" else
        [ (if .Online then "online" else "offline" end),
          (.TailscaleIPs[0] // "-"),
          (if (.CurAddr // "") != "" then "direct"
           elif (.Relay // "") != "" then "relay " + .Relay else "idle" end),
          (.LastSeen // "-") ] | @tsv
      end' <<<"$TS_JSON"
}
# peer NAME — P_STATE P_IP P_PATH P_SEEN for one of HOSTS.
peer() { IFS=$'\t' read -r P_STATE P_IP P_PATH P_SEEN <<<"$(ts_peer "${1,,}")"; }

seen_ago() {
  local e
  [[ "$1" == "-" || "$1" == 0001-* ]] && { printf 'never seen'; return; }
  e=$(date -d "$1" +%s 2>/dev/null) || { printf 'unknown'; return; }
  printf 'seen %s' "$(ui_ago "$e")"
}

dot() {
  case "$1" in
    online)  ui_c "$UI_GREEN" "●" ;;
    offline) ui_c "$UI_RED" "○" ;;
    *)       ui_c "$UI_DIM" "◌" ;;
  esac
}
# peer_status — the current peer as one coloured phrase.
peer_status() {
  case "$P_STATE" in
    online)  printf '%s %s' "$(ui_c "$UI_GREEN" "● online")" "$(ui_dim "· $P_PATH · $P_IP")" ;;
    offline) printf '%s %s' "$(ui_c "$UI_RED" "○ offline")" "$(ui_dim "· $(seen_ago "$P_SEEN")")" ;;
    missing) ui_dim "◌ not on the tailnet" ;;
    *)       ui_dim "◌ tailscale unavailable" ;;
  esac
}

# ── Generations ───────────────────────────────────────────────────────────────
profile_link() {
  if [[ "$1" == system ]]; then echo /nix/var/nix/profiles/system
  else echo "/nix/var/nix/profiles/system-profiles/$1"; fi
}
# gen_info PROFILE — G_NUM, G_WHEN (epoch it was made) for this machine's profile.
gen_info() {
  local p link
  G_NUM="" G_WHEN=""
  p=$(profile_link "$1")
  link=$(readlink "$p" 2>/dev/null) || return 0
  G_NUM=${link%-link}; G_NUM=${G_NUM##*-}
  G_WHEN=$(stat -c %Y "${p%/*}/$link" 2>/dev/null || true)   # the link's own mtime
  return 0
}

uptime_text() {
  local s=${1%.*}
  if (( s >= 86400 )); then printf '%dd %dh' $(( s / 86400 )) $(( s % 86400 / 3600 ))
  else printf '%dh %02dm' $(( s / 3600 )) $(( s % 3600 / 60 )); fi
}

# ── Home screen ───────────────────────────────────────────────────────────────
repo_line() {
  if [[ -z "$DOTS" ]]; then
    printf '%s %s' "$(ui_c "$UI_YELLOW" "$DOTS_FLAKE")" "$(ui_dim "· no checkout here")"
    return
  fi
  local branch dirty counts ahead=0 behind=0 lockage
  branch=$(git branch --show-current 2>/dev/null || echo "?")
  ui_fit_v "$branch" 22; branch=$UI_FIT
  dirty=$(git status --porcelain 2>/dev/null | wc -l)
  if counts=$(git rev-list --left-right --count "@{u}...HEAD" 2>/dev/null); then
    read -r behind ahead <<<"$counts"
  fi
  lockage=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.lastModified // 0' flake.lock 2>/dev/null || echo 0)
  printf '%s  %s  %s  %s' "$(ui_c "$UI_BLUE" "$branch")" \
    "$(if (( dirty == 0 )); then ui_c "$UI_GREEN" "✔ clean"; else ui_c "$UI_YELLOW" "● $dirty changed"; fi)" \
    "$(ui_dim "↑$ahead ↓$behind")" "$(ui_dim "· locked $(ui_ago "$lockage")")"
}

machines_panel() {
  local rows=() h glyph state detail word
  for h in "${HOSTS[@]}"; do
    host_info "$h"
    if [[ "$h" == "$THIS_HOST" ]]; then
      gen_info "$H_PROFILE"
      glyph=$(ui_c "$UI_AQUA" "◆")
      state=$(ui_c "$UI_AQUA" "$(printf '%-13s' "this machine")")
      detail=$(ui_dim "generation ${G_NUM:-?}${G_WHEN:+ · built $(ui_ago "$G_WHEN")}")
    else
      peer "$h"
      glyph=$(dot "$P_STATE")
      case "$P_STATE" in
        online)
          word=online; [[ "$H_MODE" == stick ]] && word=booted
          state=$(ui_c "$UI_GREEN" "$(printf '%-13s' "$word")")
          detail=$(ui_dim "$P_PATH · $P_IP") ;;
        offline)
          word=offline; [[ "$H_MODE" == stick ]] && word="not booted"
          state=$(ui_c "$UI_RED" "$(printf '%-13s' "$word")")
          detail=$(ui_dim "$(seen_ago "$P_SEEN")") ;;
        missing) state=$(ui_dim "$(printf '%-13s' "—")"); detail=$(ui_dim "not on the tailnet") ;;
        *)       state=$(ui_dim "$(printf '%-13s' "?")"); detail=$(ui_dim "tailscale unavailable") ;;
      esac
    fi
    rows+=("$(printf ' %s  %s  %s %s %s' "$glyph" "$(ui_c "$UI_FG" "$H_ICON")" \
      "$(ui_bold "$(printf '%-9s' "$h")")" "$state" "$detail")")
  done
  ui_panel "$UI_LINE" MACHINES "${rows[@]}"
}

home_screen() {
  find_repo
  ts_load
  local os here
  os=$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null || true)
  here=${THIS_HOST:-$(uname -n)}
  ui_logo \
    "$(ui_bold "$(ui_c "$UI_FG" system-rebuild)")  $(ui_dim "rebuild · deploy · maintain")" \
    "$(ui_bold "$(ui_c "$UI_AQUA" "$here")") $(ui_dim "·") $(id -un)${os:+ $(ui_dim "·") NixOS $os}" \
    "$(repo_line)"
  echo
  machines_panel
}

# ── Waiting for a machine ─────────────────────────────────────────────────────
# wait_online HOST — true once HOST answers on the tailnet; offers to wait.
wait_online() {
  local host="$1" state
  [[ -n "$TS_JSON" ]] || ts_load
  IFS=$'\t' read -r state _ _ _ <<<"$(ts_peer "$host")"
  [[ "$state" == "online" ]] && return 0
  ui_warn "$(ui_bold "$host") is $state on the tailnet"
  (( UI_INTERACTIVE )) || { ui_info "trying anyway"; return 0; }
  case "$(ui_choose "$host is $state" "Wait until it's online:wait" "Try anyway:try" "Cancel:cancel" || echo cancel)" in
    wait)
      ui_spin "waiting for $host — power it on, ^C to give up" \
        bash -c "until timeout 4 tailscale ping -c 1 --until-direct=false '$host' >/dev/null 2>&1; do sleep 2; done"
      ui_ok "$host is online" ;;
    try) return 0 ;;
    *) return 1 ;;
  esac
}

# ── The rebuild itself ────────────────────────────────────────────────────────
kvline() { printf '%s %s' "$(ui_dim "$(printf '%-11s' "$1")")" "$2"; }

closure_size() { nix path-info -S "$1" 2>/dev/null | awk '{print $2}'; }

# rebuild SYSTEM ACTION [TARGET-HOST] — ACTION is switch, boot or build.
# Local when SYSTEM is this machine (and no TARGET); otherwise built here and
# pushed to TARGET, or SYSTEM's own tailnet name.
rebuild() {
  local system="$1" action="$2" target="${3:-}"
  host_info "$system" || { ui_err "unknown system '$system' — one of: ${HOSTS[*]}"; return 2; }
  local user=$H_USER profile=$H_PROFILE kind=remote host=${target:-$H_SSH}
  if [[ -z "$target" && "$system" == "$THIS_HOST" ]]; then kind=local; host=$(uname -n); fi
  if [[ "$kind" == remote && "$host" == "-" && "$action" != build ]]; then
    ui_err "$system is a USB stick — it can only be built (--build)"; return 2
  fi
  local key="${user}-${system}" ssh_target="${user}@${host}"
  local -a pflag=()
  [[ "$profile" != system && "$profile" != "-" ]] && pflag=(-p "$profile")
  local accent=$UI_AQUA sub="this machine"
  if [[ "$kind" == remote ]]; then
    accent=$UI_BLUE
    if [[ "$action" == build ]]; then sub="built here · nothing deployed"; else sub="→ $ssh_target"; fi
  fi
  local started=$SECONDS

  [[ -n "${FROM_MENU:-}" ]] || ui_header "system-rebuild" "${THIS_HOST:-$(uname -n)} · $(id -un)"
  ui_banner "$accent" "${action^^}" "$system" "$sub" "$key"
  [[ "$FLAKE" == "." ]] || ui_info "no checkout here — building $(ui_bold "$FLAKE") (main)"
  if [[ "$kind" == remote && "$action" != build ]]; then
    wait_online "$host" || { ui_info "nothing done"; return 1; }
  fi

  # 1 ── build ────────────────────────────────────────────────────────────────
  ui_stage "$accent" 1 "Build"
  local link tmp=""
  if [[ "$action" == "build" && -n "$DOTS" ]]; then
    link="$DOTS/result"   # a plain build leaves ./result behind, like nix build
  else
    tmp=$(mktemp -d)
    link="$tmp/result"    # a GC root for exactly as long as this run needs it
  fi
  local attr="${FLAKE}#nixosConfigurations.${key}.config.system.build.toplevel"
  local ok=1
  if (( UI_COLOR && UI_INTERACTIVE )); then
    nom build "$attr" --out-link "$link" || ok=0
  else
    nix build "$attr" --out-link "$link" -L || ok=0
  fi
  if (( ! ok )); then
    ui_box "$UI_RED" "✘ Build failed — $key" \
      "Nothing was activated; the running system is untouched." "" \
      "$(ui_dim "full log:")  nix build $attr -L"
    [[ -n "$tmp" ]] && rm -rf "$tmp"
    return 1
  fi
  local out; out=$(readlink -f "$link")
  local outname=${out#/nix/store/}; outname=${outname#*-}
  ui_ok "built in $(ui_duration $(( SECONDS - started )))  $(ui_dim "$outname")"

  # 2 ── diff against what is running ─────────────────────────────────────────
  ui_stage "$accent" 2 "Changes"
  local current="" same=0
  if [[ "$kind" == "local" ]]; then
    current=$(readlink -f /run/current-system 2>/dev/null || true)
  elif [[ "$host" != "-" ]]; then
    current=$(timeout 8 ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" readlink -f /run/current-system 2>/dev/null || true)
  fi
  if [[ -n "$current" && "$current" == "$out" ]]; then
    same=1
    ui_ok "identical to what's running on $system — nothing changed"
  elif [[ -n "$current" && -e "$current" ]]; then
    local dixcolor=never; (( UI_COLOR )) && dixcolor=always
    dix --color "$dixcolor" "$current" "$out" 2>/dev/null \
      | awk '{ p = $0; gsub(/\033\[[0-9;]*m/, "", p); if (p !~ /^(<<<|>>>)/) print }' \
      | sed 's/^/    /' || ui_info "dix couldn't compare these two systems"
  elif [[ -n "$current" ]]; then
    ui_info "$system runs a system this machine never built — no package diff"
  elif [[ "$host" == "-" ]]; then
    ui_info "$system is a USB stick — nothing running to compare with"
  else
    ui_info "couldn't read what $system is running — no package diff"
  fi

  # 3 ── apply ────────────────────────────────────────────────────────────────
  local verb="built" next=""
  if [[ "$action" == "build" ]]; then
    if [[ "$link" == "$DOTS/result" ]]; then next="nothing activated · ./result → the new system"
    else next="nothing activated · it's in the store until the next GC"; fi
  elif (( same )) && [[ "$action" == "switch" ]]; then
    verb="already up to date"
    next="nothing to activate"
  else
    ui_stage "$accent" 3 "Activate · $action"
    # --no-reexec: before switch/boot, nixos-rebuild-ng swaps itself for the
    # new system's copy by building config.system.build.nixos-rebuild — from
    # --flake if given, otherwise from <nixpkgs/nixos> + NIX_PATH's
    # nixos-config, which a flake system doesn't have. It does this even with
    # --store-path, so without the flag every activation dies with "file
    # 'nixos-config' was not found". The running nixos-rebuild is fine.
    local cmd
    if [[ "$kind" == "local" ]]; then
      cmd=(sudo nixos-rebuild "$action" "${pflag[@]}" --no-reexec --store-path "$out")
    else
      ui_info "$host will ask for $(ui_bold "$user")'s sudo password — that's the password on $system"
      cmd=(nixos-rebuild "$action" "${pflag[@]}" --no-reexec --store-path "$out" --target-host "$ssh_target" --ask-sudo-password)
    fi
    if ! "${cmd[@]}"; then
      ui_box "$UI_RED" "✘ Activation failed — $system" \
        "The new system is built (it's in the store) but did not activate cleanly." \
        "Check the output above. To retry exactly this step:" "" \
        "${cmd[*]}"
      [[ -n "$tmp" ]] && rm -rf "$tmp"
      return 1
    fi
    if [[ "$action" == "switch" ]]; then verb="switched"; else verb="ready for next boot"; fi
    if [[ "$action" == "boot" && "$kind" == "local" && ${#pflag[@]} -gt 0 ]]; then
      next="reboot and pick $(ui_bold "$system") under GRUB's System Select"
    elif [[ "$action" == "boot" && "$kind" == "local" ]]; then
      next="active after the next reboot"
    elif [[ "$action" == "boot" ]]; then
      next="active after $system's next reboot"
    fi
  fi

  # summary ──────────────────────────────────────────────────────────────────
  local lines=() size old_size delta=""
  lines+=("$(kvline host "$system  $(ui_dim "($key)")")")
  [[ "$kind" == "remote" && "$host" != "-" ]] && lines+=("$(kvline target "$ssh_target")")
  lines+=("$(kvline took "$(ui_duration $(( SECONDS - started )))")")
  size=$(closure_size "$out")
  if [[ -n "$size" ]]; then
    if [[ -n "$current" && -e "$current" ]] && old_size=$(closure_size "$current") && [[ -n "$old_size" ]]; then
      if (( size >= old_size )); then delta="+$(ui_bytes $(( size - old_size )))"; else delta="−$(ui_bytes $(( old_size - size )))"; fi
      delta="  $(ui_dim "($delta)")"
    fi
    lines+=("$(kvline closure "$(ui_bytes "$size")$delta")")
  fi
  if [[ "$kind" == "local" && "$action" != "build" ]]; then
    gen_info "$profile"
    [[ -n "$G_NUM" ]] && lines+=("$(kvline generation "$G_NUM")")
  fi
  [[ -n "$next" ]] && lines+=("$(kvline next "$next")")
  ui_box "$UI_GREEN" "✔ $system $verb" "${lines[@]}"
  [[ -n "$tmp" ]] && rm -rf "$tmp"
  return 0
}

# ── Jobs on other machines ────────────────────────────────────────────────────

# remote_probe NAME — what NAME is running, and its checkout if it has one, as
# menu notes (PROBE_NOTES). Quiet and quick: BatchMode, short timeouts.
PROBE_NOTES=()
remote_probe() {
  local name="$1" out rcmd
  local -a l
  PROBE_NOTES=()
  host_info "$name"
  rcmd="readlink $(profile_link "$H_PROFILE"); cut -d' ' -f1 /proc/uptime;"
  rcmd+=" if [ -d ~/Dots/.git ]; then git -C ~/Dots log -1 --format='%h|%cr'; git -C ~/Dots branch --show-current;"
  rcmd+=" git -C ~/Dots status --porcelain | wc -l; fi"
  out=$(ui_spin_out "asking $name…" timeout 8 ssh -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=QUIET "$H_USER@$H_SSH" "$rcmd") || true
  [[ -n "$out" ]] || { PROBE_NOTES=("$(ui_dim "couldn't ask over ssh — key not authorised, or it's busy")"); return 0; }
  mapfile -t l <<<"$out"
  local gen=${l[0]%-link}; gen=${gen##*-}
  PROBE_NOTES+=("$(ui_dim "running") generation ${gen:-?} $(ui_dim "· up") $(uptime_text "${l[1]:-0}")")
  if [[ -n "${l[2]:-}" ]]; then
    local dirty="${l[4]:-0}" state
    if (( dirty == 0 )); then state=$(ui_c "$UI_GREEN" "✔ clean"); else state=$(ui_c "$UI_YELLOW" "● $dirty changed"); fi
    PROBE_NOTES+=("$(ui_dim "its ~/Dots") $(ui_c "$UI_BLUE" "${l[3]:-?}") $(ui_dim "@") ${l[2]%%|*} $(ui_dim "(${l[2]#*|})")  $state")
  fi
}

ssh_to() {
  host_info "$1"
  ui_banner "$UI_BLUE" SSH "$1" "$H_USER@$H_SSH"
  wait_online "$H_SSH" || { ui_info "nothing done"; return 1; }
  ssh -t "$H_USER@$H_SSH"
}

# on_host NAME pull|switch — rebuild a managed machine on itself, from its own
# checkout (pull: fast-forward it to origin first; refuses if it has diverged).
on_host() {
  local name="$1" how="$2" cmd tag=SWITCH
  host_info "$name"
  local key="$H_USER-$name"
  cmd="sudo nixos-rebuild switch --flake .#$key"
  if [[ "$how" == pull ]]; then cmd="git pull --ff-only && $cmd"; tag=UPDATE; fi
  cmd="cd ~/Dots && $cmd"
  ui_banner "$UI_BLUE" "$tag" "$name" "on $name, from its own ~/Dots" "$key"
  wait_online "$H_SSH" || { ui_info "nothing done"; return 1; }
  ui_info "$(ui_dim "$H_USER@$H_SSH \$") $cmd"
  echo
  if ssh -t "$H_USER@$H_SSH" "$cmd"; then
    ui_box "$UI_GREEN" "✔ $name switched" "$(kvline host "$name  $(ui_dim "($key)")")" "$(kvline from "$name's ~/Dots$([[ "$how" == pull ]] && echo ", fast-forwarded")")"
  else
    ui_box "$UI_RED" "✘ $name didn't switch" "Check the output above — a diverged checkout makes" "git pull --ff-only refuse, and changes nothing."
    return 1
  fi
}

# push_managed NAME — the opt-in override: overwrite a managed machine's live
# config with this machine's checkout.
push_managed() {
  local name="$1" action
  host_info "$name"
  ui_box "$UI_YELLOW" "$name is managed on $name" \
    "Its checkout of this repo is where its changes are made, and it can be" \
    "ahead of this one. Pushing from here replaces the live config with" \
    "whatever this machine has."
  ui_confirm "Really overwrite $name's live config with this machine's?" default-no || { ui_info "nothing done"; return 1; }
  action=$(ui_choose "Push to $name — how?" "Switch — activate now:switch" "Boot — on next reboot:boot") || { ui_info "nothing done"; return 1; }
  rebuild "$name" "$action" "$H_SSH"
}

# ── Jobs on the repo and the store ────────────────────────────────────────────

# lock_table FILE → "input<TAB>rev7<TAB>lastModified" for every root input.
lock_table() {
  jq -r '.nodes as $n | $n.root.inputs | to_entries[]
    | .key as $k | (.value | if type == "array" then .[-1] else . end) as $node
    | [$k, (($n[$node].locked.rev // $n[$node].locked.narHash // "?")[0:7]),
       ($n[$node].locked.lastModified // 0)] | @tsv' "$1"
}

update_inputs() {
  ui_banner "$UI_YELLOW" UPDATE "flake inputs" "nix flake update" "$(git branch --show-current 2>/dev/null)"
  local before; before=$(mktemp)
  cp flake.lock "$before"
  if ! ui_spin "fetching every input…" nix flake update; then
    rm -f "$before"; ui_err "nix flake update failed (output above)"; return 1
  fi
  local changed=0 name rev mod orev omod
  echo
  while IFS=$'\t' read -r name rev mod; do
    orev="" omod=""
    IFS=$'\t' read -r _ orev omod <<<"$(lock_table "$before" | awk -F'\t' -v k="$name" '$1 == k')" || true
    if [[ "$rev" != "${orev:-}" ]]; then
      changed=$(( changed + 1 ))
      printf '    %s %s %s %s %s\n' "$(ui_c "$UI_AQUA" "↑")" "$(ui_bold "$(printf '%-16s' "$name")")" \
        "$(ui_dim "${orev:-new}")" "$(ui_dim "→")" "$(ui_c "$UI_FG" "$rev")  $(ui_dim "$(ui_ago "${omod:-$mod}") → $(ui_ago "$mod")")"
    fi
  done < <(lock_table flake.lock)
  rm -f "$before"
  if (( changed == 0 )); then ui_ok "everything was already up to date"; return 0; fi
  ui_ok "$changed input$( (( changed > 1 )) && echo s) updated  $(ui_dim "· flake.lock changed, not committed")"
  [[ -n "$THIS_HOST" ]] || return 0
  case "$(ui_choose "Rebuild $THIS_HOST on the new inputs?" "Switch now:switch" "Build only (see the diff):build" "Later:later" || echo later)" in
    switch) rebuild "$THIS_HOST" switch ;;
    build)  rebuild "$THIS_HOST" build ;;
    *)      ui_info "run system-rebuild when you're ready" ;;
  esac
}

sync_repo() {
  ui_banner "$UI_YELLOW" SYNC "git sync" "commit · pull --rebase · push" "$(git branch --show-current 2>/dev/null)"
  local msg=""
  if [[ -n "$(git status --porcelain)" ]]; then
    git status --short | head -15 | sed 's/^/    /'
    msg=$(ui_input "commit message" "chore: sync") || return 1
  fi
  if [[ -n "$msg" ]]; then git-sync "$msg"; else git-sync; fi
  ui_ok "in sync with origin"
}

clone_repo() {
  local dest="${DOTS_DIR:-$HOME/Dots}"
  ui_banner "$UI_YELLOW" CLONE "the repo" "$DOTS_URL" "$dest"
  [[ -e "$dest" ]] && { ui_err "$dest already exists"; return 1; }
  git clone "$DOTS_URL" "$dest"
  ui_ok "cloned — rebuilds now use it, and sync / update are in Utilities"
}

collect_garbage() {
  ui_banner "$UI_YELLOW" GC "garbage collect" "old generations · store · docker" "$(uname -n)"
  ui_warn "deletes every old generation — you can't roll back past the current one"
  ui_confirm "Collect garbage now?" default-no || { ui_info "nothing done"; return 1; }
  local before after
  before=$(df -B1 --output=avail /nix/store | tail -1)
  nix-gc
  after=$(df -B1 --output=avail /nix/store | tail -1)
  ui_ok "freed $(ui_bytes $(( after > before ? after - before : 0 )))"
}

# check_hosts — every host's toplevel evaluates (the drvPath check from
# CLAUDE.md). Builds nothing.
check_hosts() {
  ui_banner "$UI_YELLOW" CHECK "every host evaluates" "nothing is built" "$FLAKE_LABEL"
  echo
  local h key t0 drv fails=0 out err
  out=$(mktemp); err=$(mktemp)
  for h in "${HOSTS[@]}"; do
    host_info "$h"
    key="$H_USER-$h"; t0=$SECONDS
    # gum spin runs a command, not a function: a tiny bash -c writes nix's
    # stdout and stderr to the two files. $1–$3 are its own arguments.
    # shellcheck disable=SC2016
    if ui_spin "evaluating $key…" bash -c 'nix eval --raw "$1" >"$2" 2>"$3"' _ \
         "${FLAKE}#nixosConfigurations.${key}.config.system.build.toplevel.drvPath" "$out" "$err"; then
      drv=$(<"$out"); drv=${drv#/nix/store/}
      ui_ok "$(ui_bold "$(printf '%-16s' "$key")") $(ui_dim "$(ui_duration $(( SECONDS - t0 ))) · ${drv:0:12}…")"
    else
      fails=$(( fails + 1 ))
      ui_err "$(ui_bold "$key")"
      grep -v '^\s*$' "$err" | tail -6 | sed 's/^/      /' >&2 || true
    fi
  done
  rm -f "$out" "$err"
  if (( fails )); then
    ui_box "$UI_RED" "✘ $fails of ${#HOSTS[@]} hosts don't evaluate" "The errors are above; nothing was built or changed."
    return 1
  fi
  ui_box "$UI_GREEN" "✔ all ${#HOSTS[@]} hosts evaluate" "$(kvline flake "$FLAKE_LABEL")"
}

# ── Apollo ────────────────────────────────────────────────────────────────────
has_apollo() { command -v apollo-deploy >/dev/null 2>&1; }
apollo_mount() { findmnt -rn -o TARGET -S LABEL=Apollo 2>/dev/null || true; }

# apollo_run TAG TITLE CMD… — one of the apollo-* commands, under a banner.
apollo_run() {
  local tag="$1" title="$2"; shift 2
  ui_banner "$UI_PURPLE" "$tag" "$title" "$*"
  "$@"
}

# ── Menus ─────────────────────────────────────────────────────────────────────

# job FUNC [ARGS] — run a job picked from a menu, then offer the menu back.
# It runs in a subshell with errexit on (a bare `f || rc=$?` would switch
# errexit off inside f); a job that cd's or exits only affects itself.
job() {
  local rc
  set +e
  ( set -e; "$@" )
  rc=$?
  set -e
  if ui_keys_wait; then home_screen; return 0; fi
  echo
  exit "$rc"
}
bye() { echo; exit 0; }

menu_main() {
  local last="" h remotes usb
  while :; do
    remotes=""
    for h in "${HOSTS[@]}"; do
      host_info "$h"
      [[ "$h" == "$THIS_HOST" || "$H_MODE" == stick ]] && continue
      peer "$h"
      remotes+="$(ui_dim "$h") $(dot "$P_STATE")  "
    done
    ui_menu_new
    if [[ -n "$THIS_HOST" ]]; then
      ui_item rebuild "$I_REBUILD" Rebuild "$THIS_HOST · this machine" "switch · boot · build" "$UI_AQUA"
    else
      ui_item rebuild "$I_REBUILD" Rebuild "build any host's config here" "" "$UI_AQUA"
    fi
    ui_item remote "$I_REMOTE" Remote "deploy over the tailnet" "$remotes" "$UI_BLUE"
    ui_item utils "$I_UTILS" Utilities "keep the repo and the store tidy" "sync · update · gc" "$UI_YELLOW"
    if has_apollo; then
      peer Apollo
      if [[ -n "$(apollo_mount)" ]]; then usb=$(ui_c "$UI_GREEN" ✔); else usb=$(ui_dim –); fi
      ui_item apollo "$I_APOLLO" Apollo "the deployer USB" "$(ui_dim stick) $(dot "$P_STATE")  $(ui_dim usb) $usb" "$UI_PURPLE"
    fi
    ui_item_quit
    UI_MENU_SEL=$last
    ui_menu grad DOTS
    last=$UI_CHOICE
    case "$UI_CHOICE" in
      rebuild) menu_rebuild ;;
      remote)  menu_remote ;;
      utils)   menu_utilities ;;
      apollo)  menu_apollo ;;
      *)       bye ;;
    esac
  done
}

menu_rebuild() {
  local last="" bmeta
  while :; do
    ui_menu_new
    if [[ -n "$THIS_HOST" ]]; then
      host_info "$THIS_HOST"
      gen_info "$H_PROFILE"
      ui_note "$(ui_c "$UI_AQUA" "◆") $(ui_bold "$THIS_HOST")  $(ui_dim "$H_USER-$THIS_HOST · generation ${G_NUM:-?}${G_WHEN:+, built $(ui_ago "$G_WHEN")}")"
      [[ "$H_PROFILE" != system ]] && ui_note "$(ui_dim "profile") $H_PROFILE $(ui_dim "· its own entry under GRUB's System Select")"
      [[ "$FLAKE" == "." ]] || ui_note "$(ui_c "$UI_YELLOW" "!") $(ui_dim "no ~/Dots here — builds") $DOTS_FLAKE $(ui_dim "(main)")"
      ui_gap
      ui_item switch "$I_SWITCH" Switch "build · diff · activate now"
      bmeta="next reboot"; [[ "$H_PROFILE" != system ]] && bmeta="GRUB › $THIS_HOST"
      ui_item boot "$I_BOOT" Boot "build · diff · on next boot" "$bmeta"
      ui_item build "$I_BUILD" Build "build · diff · activate nothing" "$([[ -n "$DOTS" ]] && echo ./result)"
      ui_gap
    else
      ui_note "$(ui_c "$UI_YELLOW" "!") $(uname -n) $(ui_dim "isn't one of") ${HOSTS[*]}"
      ui_gap
    fi
    ui_item other "$I_OTHER" "Other host" "build another machine's config, deploy nothing"
    ui_item_back
    UI_MENU_SEL=$last
    ui_menu "$UI_AQUA" DOTS Rebuild
    last=$UI_CHOICE
    case "$UI_CHOICE" in
      switch | boot | build) job rebuild "$THIS_HOST" "$UI_CHOICE" ;;
      other) menu_build_other ;;
      quit)  bye ;;
      *)     return 0 ;;
    esac
  done
}

menu_build_other() {
  local h
  ui_menu_new
  ui_note "$(ui_dim "builds the config and diffs it against what that machine runs")"
  ui_gap
  for h in "${HOSTS[@]}"; do
    [[ "$h" == "$THIS_HOST" ]] && continue
    host_info "$h"
    ui_item "$h" "$H_ICON" "$h" "$H_ROLE" "$H_USER-$h"
  done
  ui_item_back
  ui_menu "$UI_AQUA" DOTS Rebuild "Other host"
  case "$UI_CHOICE" in
    back) return 0 ;;
    quit) bye ;;
    *)    job rebuild "$UI_CHOICE" build ;;
  esac
}

menu_remote() {
  local last="" h
  while :; do
    ui_menu_new
    ui_note "$(ui_dim "builds here, copies the closure over the tailnet, activates there")"
    ui_gap
    for h in "${HOSTS[@]}"; do
      host_info "$h"
      [[ "$h" == "$THIS_HOST" || "$H_MODE" == stick ]] && continue
      peer "$h"
      ui_item "$h" "$H_ICON" "$h" "$H_ROLE$([[ "$H_MODE" == managed ]] && echo " · managed there")" \
        "$(case "$P_STATE" in online) ui_c "$UI_GREEN" "● online" ;; offline) ui_c "$UI_RED" "○ offline" ;; missing) ui_dim "◌ not on the tailnet" ;; *) ui_dim "◌ unknown" ;; esac)"
    done
    ui_item_back
    UI_MENU_SEL=$last
    ui_menu "$UI_BLUE" DOTS Remote
    last=$UI_CHOICE
    case "$UI_CHOICE" in
      back) return 0 ;;
      quit) bye ;;
      *)    menu_host "$UI_CHOICE" ;;
    esac
  done
}

# menu_host NAME — everything you can do to one remote machine.
menu_host() {
  local name="$1" last="" n
  peer "$name"
  local -a probe=()
  if [[ "$P_STATE" == online ]]; then remote_probe "$name"; probe=("${PROBE_NOTES[@]}"); fi
  while :; do
    host_info "$name"
    peer "$name"
    ui_menu_new
    ui_note "$(peer_status)"
    for n in "${probe[@]}"; do ui_note "$n"; done
    if [[ "$H_MODE" == managed ]]; then
      ui_note "$(ui_c "$UI_YELLOW" "! managed on $name") $(ui_dim "— its own ~/Dots is the source of truth")"
      ui_gap
      ui_item pull "$I_PULL" "Pull & switch" "git pull --ff-only, then switch, on $name"
      ui_item there "$I_SWITCH" "Switch there" "switch from its ~/Dots as it is"
      ui_item ssh "$I_SSH" "SSH" "open a shell on $name" "$H_USER@$H_SSH"
      ui_item build "$I_DIFF" "Compare" "build ours here, diff against what it runs"
      ui_gap
      ui_item push "$I_PUSH" "Push ours…" "overwrite its config with ours" "asks first" "$UI_RED"
    else
      ui_gap
      ui_item switch "$I_SWITCH" Switch "build here, push, activate now"
      ui_item boot "$I_BOOT" Boot "build here, push, activate on its next reboot"
      ui_item build "$I_BUILD" Build "build here and diff — nothing deployed"
      ui_item ssh "$I_SSH" SSH "open a shell on $name" "$H_USER@$H_SSH"
    fi
    ui_item_back
    UI_MENU_SEL=$last
    ui_menu "$UI_BLUE" DOTS Remote "$name"
    last=$UI_CHOICE
    case "$UI_CHOICE" in
      switch | boot | build) job rebuild "$name" "$UI_CHOICE" ;;
      ssh)   job ssh_to "$name" ;;
      pull)  job on_host "$name" pull ;;
      there) job on_host "$name" switch ;;
      push)  job push_managed "$name" ;;
      quit)  bye ;;
      *)     return 0 ;;
    esac
  done
}

menu_utilities() {
  local last="" dirty meta
  while :; do
    ui_menu_new
    if [[ -n "$DOTS" ]]; then
      dirty=$(git status --porcelain 2>/dev/null | wc -l)
      if (( dirty )); then meta=$(ui_c "$UI_YELLOW" "● $dirty changed")
      else meta=$(ui_c "$UI_GREEN" "✔ clean"); fi
      ui_item sync "$I_GIT" "Git sync" "commit · pull --rebase · push" "$meta"
      ui_item update "$I_UPDATE" "Update inputs" "nix flake update + changelog" \
        "locked $(ui_ago "$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.lastModified // 0' flake.lock 2>/dev/null || echo 0)")"
    else
      ui_item clone "$I_CLONE" "Get the repo" "clone it to ~/Dots, for sync and update" "github"
    fi
    ui_item gc "$I_GC" "Garbage collect" "old generations · store · docker" \
      "$(df -h --output=avail /nix/store 2>/dev/null | tail -1 | tr -d ' ') free"
    ui_item check "$I_CHECK" "Check hosts" "evaluate every host, build nothing" "${#HOSTS[@]} hosts"
    ui_item_back
    UI_MENU_SEL=$last
    ui_menu "$UI_YELLOW" DOTS Utilities
    last=$UI_CHOICE
    case "$UI_CHOICE" in
      sync)   job sync_repo ;;
      update) job update_inputs ;;
      clone)  job clone_repo ;;
      gc)     job collect_garbage ;;
      check)  job check_hosts ;;
      quit)   bye ;;
      *)      return 0 ;;
    esac
  done
}

menu_apollo() {
  local last="" mnt
  while :; do
    peer Apollo
    mnt=$(apollo_mount)
    ui_menu_new
    case "$P_STATE" in
      online)  ui_note "$(ui_dim "stick") $(ui_c "$UI_GREEN" "● booted") $(ui_dim "· $P_PATH · $P_IP")" ;;
      offline) ui_note "$(ui_dim "stick") $(ui_c "$UI_RED" "○ not booted") $(ui_dim "· $(seen_ago "$P_SEEN")")" ;;
      *)       ui_note "$(ui_dim "stick") $(ui_dim "◌ never seen on the tailnet")" ;;
    esac
    if [[ -n "$mnt" ]]; then ui_note "$(ui_dim "usb  ") $(ui_c "$UI_GREEN" "✔ mounted") $(ui_dim "· $mnt")"
    elif [[ -e /dev/disk/by-label/Apollo ]]; then ui_note "$(ui_dim "usb  ") $(ui_c "$UI_YELLOW" "! plugged in, not mounted") $(ui_dim "· udisksctl mount -b /dev/disk/by-label/Apollo")"
    else ui_note "$(ui_dim "usb  ") $(ui_dim "– not plugged in")"; fi
    ui_gap
    ui_item deploy "$I_DEPLOY" Deploy "install onto the booted machine" "$(ui_c "$UI_RED" "wipes its disks")"
    ui_item ssh "$I_SSH" SSH "connect to the booted stick" "apollo-connect"
    ui_item iso "$I_ISO" "Build ISO" "build it and copy it onto the stick" "apollo-iso"
    ui_item key "$I_KEY" "Tailnet key" "write the auth key onto the stick" "apollo-key"
    ui_item_back
    UI_MENU_SEL=$last
    ui_menu "$UI_PURPLE" DOTS Apollo
    last=$UI_CHOICE
    case "$UI_CHOICE" in
      deploy) menu_apollo_deploy ;;
      ssh)    job apollo_run SSH "the booted stick" apollo-connect ;;
      iso)    job apollo_run ISO "build + copy to the stick" apollo-iso ;;
      key)    job apollo_run KEY "tailnet key → the stick" apollo-key ;;
      quit)   bye ;;
      *)      return 0 ;;
    esac
  done
}

menu_apollo_deploy() {
  local h
  while :; do
    ui_menu_new
    ui_note "$(ui_c "$UI_RED" "$I_WARN  the target must be booted from the stick · INSTALL erases its disks")"
    ui_gap
    for h in "${HOSTS[@]}"; do
      [[ -n "$DOTS" && -f "$DOTS/Hosts/$h/_disko.nix" ]] || continue
      host_info "$h"
      ui_item "$h" "$H_ICON" "$h" "$H_ROLE" "$H_USER-$h · disko$([[ -f "$DOTS/Hosts/$h/facter.json" ]] && echo " + facter")"
    done
    ui_item_back
    ui_menu "$UI_PURPLE" DOTS Apollo Deploy
    case "$UI_CHOICE" in
      back) return 0 ;;
      quit) bye ;;
      *)    menu_apollo_mode "$UI_CHOICE" ;;
    esac
  done
}

menu_apollo_mode() {
  local name="$1" key
  host_info "$name"
  key="$H_USER-$name"
  ui_menu_new
  ui_note "$(ui_dim "apollo-deploy") $key $(ui_dim "→ the machine booted from the stick")"
  ui_gap
  ui_item dry "$I_DRY" "Dry run" "print the disk script, change nothing"
  ui_item vm "$I_VM" "VM test" "apply the layout in a throwaway VM"
  ui_gap
  ui_item install "$I_WARN" "INSTALL" "erase its disks, install $name" "you type $name" "$UI_RED"
  ui_item_back
  ui_menu "$UI_PURPLE" DOTS Apollo Deploy "$name"
  case "$UI_CHOICE" in
    dry)     job apollo_run DRY-RUN "$key" apollo-deploy --dry-run "$key" ;;
    vm)      job apollo_run VM-TEST "$key" apollo-deploy --vm-test "$key" ;;
    install) job apollo_run INSTALL "$key" apollo-deploy "$key" ;;
    quit)    bye ;;
    *)       return 0 ;;
  esac
}

# ── Entry ─────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: system-rebuild USER SYSTEM [--boot|--build] [--target HOST]"
  echo "   or: system-rebuild            (home screen + menus)"
  echo "SYSTEM is one of: ${HOSTS[*]}. This machine${THIS_HOST:+ ($THIS_HOST)} rebuilds in place;"
  echo "any other is built here and pushed over the tailnet."
}

if [[ -z "${1:-}" ]]; then
  FROM_MENU=1
  (( UI_INTERACTIVE )) || { usage; exit 2; }
  home_screen
  menu_main
fi

# CLI: system-rebuild USER SYSTEM [--boot|--build] [--target HOST]
system="${2:-}"
action="switch"
target=""
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --boot) action="boot" ;;
    # --test kept as an alias: it always meant "build only" here, never
    # nixos-rebuild's own `test`.
    --build|--test) action="build" ;;
    --target) target="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ui_err "unknown option: $1"; exit 2 ;;
  esac
  shift
done
[[ -n "$system" ]] || { usage; exit 2; }
host_info "$system" || { ui_err "unknown system '$system' — one of: ${HOSTS[*]}"; exit 2; }
# A managed machine's live config is edited on it; refuse to overwrite it from
# elsewhere unless --target says that's deliberate (the menu asks instead).
if [[ "$H_MODE" == managed && -z "$target" && "$system" != "$THIS_HOST" ]]; then
  ui_err "$system is managed on $system, not from here."
  ui_info "update it in place:  system-rebuild → Remote → $system → Pull & switch"
  ui_info "by hand:             ssh $H_SSH 'cd ~/Dots && sudo nixos-rebuild switch --flake .#$H_USER-$system'"
  ui_info "push ours anyway:    system-rebuild $H_USER $system --target $H_SSH"
  exit 1
fi
rebuild "$system" "$action" "$target"
