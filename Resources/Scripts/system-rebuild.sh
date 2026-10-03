# system-rebuild — rock's single entry point for building, pushing and deploying
# NixOS from Sisyphus. Packaged by Modules/Shell/deploy-tools.nix, which
# prepends lib/ui.sh (the shared look) and runs it all through
# writeShellApplication: errexit/nounset/pipefail on, shellcheck at build time.
#
#   system-rebuild                                    home screen + menus
#   system-rebuild USER SYSTEM [--boot|--build] [--target HOST]
#
# Every rebuild — menu or CLI — is the same three steps:
#   1. build  nom build .#nixosConfigurations.<user>-<Host>.config.system.build.toplevel
#   2. diff   dix <what is running> <what was built>
#   3. apply  nixos-rebuild <switch|boot> --store-path <built path>
#             (-p sisyphus locally; --target-host for another machine)
# Building first and handing nixos-rebuild the finished store path (supported
# since nixos-rebuild-ng) evaluates the flake once, gives the build nom's live
# tree, and keeps all of nixos-rebuild's own activation logic: profiles, the
# systemd-run wrapper that survives a dropped SSH session, and copying the
# closure to a remote host.
#
# The UI is inline — it draws in the normal scrollback and never takes over the
# screen, so what happened stays readable after it exits.

DOTS="${DOTS_DIR:-$HOME/Dots}"
cd "$DOTS" || { ui_err "$DOTS not found"; exit 1; }

# ── Machines ──────────────────────────────────────────────────────────────────
#   name      flake user   kind     ssh host (tailnet name)
host_meta() {
  case "$1" in
    Sisyphus) echo "rock local -" ;;
    Kit-Kat)  echo "kitkat remote kit-kat" ;;
    Asgard)   echo "rock remote asgard" ;;
    *)        echo "" ;;
  esac
}

# ── Tailnet status ────────────────────────────────────────────────────────────
TS_JSON=""
ts_load() { TS_JSON=$(timeout 3 tailscale status --json 2>/dev/null || true); }

# ts_peer PREFIX → "state<TAB>ip<TAB>path<TAB>lastSeen" for the best-matching
# peer whose HostName starts with PREFIX (online ones win, so "apollo" finds
# whichever stick is booted). state is online / offline / unknown.
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

# ── Home screen ───────────────────────────────────────────────────────────────
home_screen() {
  ts_load
  ui_header "system-rebuild" "$(uname -n) · $(id -un)"

  ui_rule "MACHINES"
  local gen="" built="" link
  link=$(readlink /nix/var/nix/profiles/system-profiles/sisyphus 2>/dev/null || true)
  if [[ -n "$link" ]]; then
    gen=${link#sisyphus-}; gen=${gen%-link}
    built=$(stat -c %Y "/nix/var/nix/profiles/system-profiles/$link" 2>/dev/null || echo "")
  fi
  printf '    %s %s %s\n' "$(dot online)" "$(ui_bold "$(printf '%-9s' Sisyphus)")" \
    "$(ui_dim "this machine")  generation ${gen:-?}${built:+ $(ui_dim "· built $(ui_ago "$built")")}"

  local name prefix state ip path seen detail
  for name in Kit-Kat Asgard Apollo; do
    prefix=$(tr '[:upper:]' '[:lower:]' <<<"$name")
    IFS=$'\t' read -r state ip path seen <<<"$(ts_peer "$prefix")"
    case "$state" in
      online)  detail="$(ui_c "$UI_GREEN" online) $(ui_dim "· $path")  $(ui_dim "$ip")" ;;
      offline) detail="$(ui_c "$UI_RED" offline) $(ui_dim "· $(seen_ago "$seen")")" ;;
      missing) detail="$(ui_dim "not on the tailnet")" ;;
      *)       detail="$(ui_dim "tailscale unavailable")" ;;
    esac
    printf '    %s %s %s\n' "$(dot "$state")" "$(ui_bold "$(printf '%-9s' "$name")")" "$detail"
  done

  echo
  ui_rule "REPO"
  local branch dirty counts ahead=0 behind=0 lockage
  branch=$(git branch --show-current 2>/dev/null || echo "?")
  dirty=$(git status --porcelain 2>/dev/null | wc -l)
  if counts=$(git rev-list --left-right --count "@{u}...HEAD" 2>/dev/null); then
    read -r behind ahead <<<"$counts"
  fi
  lockage=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.lastModified // 0' flake.lock 2>/dev/null || echo 0)
  ui_kv branch "$(ui_c "$UI_BLUE" "$branch")  $(
    if (( dirty == 0 )); then ui_c "$UI_GREEN" "✔ clean"; else ui_c "$UI_YELLOW" "● $dirty changed"; fi
  )  $(ui_dim "↑$ahead ↓$behind")"
  ui_kv nixpkgs "$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].original.ref // "?"' flake.lock 2>/dev/null) $(ui_dim "· locked $(ui_ago "$lockage")")"
  ui_kv last "$(git log -1 --format='%s' 2>/dev/null | cut -c1-$(( UI_WIDTH - 18 )))"
}

# ── Waiting for a machine ─────────────────────────────────────────────────────
# wait_online HOST — true once HOST answers on the tailnet; offers to wait.
wait_online() {
  local host="$1" state
  IFS=$'\t' read -r state _ _ _ <<<"$(ts_peer "$host")"
  [[ "$state" == "online" ]] && return 0
  if [[ "$state" == "unknown" && -z "$TS_JSON" ]]; then ts_load; IFS=$'\t' read -r state _ _ _ <<<"$(ts_peer "$host")"; fi
  [[ "$state" == "online" ]] && return 0

  ui_warn "$(ui_bold "$host") is $state on the tailnet"
  (( UI_INTERACTIVE )) || { ui_info "trying anyway"; return 0; }
  case "$(ui_choose "What now?" "Wait until it's online:wait" "Try anyway:try" "Cancel:cancel" || echo cancel)" in
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

# rebuild SYSTEM ACTION [TARGET-HOST]
rebuild() {
  local system="$1" action="$2" target="${3:-}"
  local user kind host
  read -r user kind host <<<"$(host_meta "$system")"
  [[ -n "${user:-}" ]] || { ui_err "unknown system '$system' (Sisyphus, Kit-Kat or Asgard)"; return 2; }
  if [[ -n "$target" ]]; then kind="remote"; host="$target"; fi
  local key="${user}-${system}" ssh_target="${user}@${host}"
  local profile; profile=$(tr '[:upper:]' '[:lower:]' <<<"$system")
  local started=$SECONDS

  local heading="$action · $system"
  [[ "$kind" == "remote" ]] && heading="$heading → $host"
  if [[ -n "${FROM_MENU:-}" ]]; then
    echo; ui_rule "$(tr '[:lower:]' '[:upper:]' <<<"$heading")"
  else
    ui_header "$heading" "$key"
  fi
  if [[ "$kind" == "remote" ]]; then
    if [[ "$action" != "build" ]]; then
      [[ -n "$TS_JSON" ]] || ts_load
      wait_online "$host" || { ui_info "nothing done"; return 1; }
    fi
  fi

  # 1 ── build ────────────────────────────────────────────────────────────────
  ui_step "Build"
  local link tmp=""
  if [[ "$action" == "build" ]]; then
    link="$DOTS/result"   # a plain build leaves ./result behind, like nix build
  else
    tmp=$(mktemp -d)
    link="$tmp/result"    # a GC root for exactly as long as this run needs it
  fi
  local attr=".#nixosConfigurations.${key}.config.system.build.toplevel"
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
  ui_step "Changes"
  local current="" same=0
  if [[ "$kind" == "local" ]]; then
    current=$(readlink -f /run/current-system 2>/dev/null || true)
  else
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
  else
    ui_info "couldn't read what $system is running — no package diff"
  fi

  # 3 ── apply ────────────────────────────────────────────────────────────────
  local verb="built" next=""
  if [[ "$action" == "build" ]]; then
    next="nothing activated · ./result → the new system"
  elif (( same )) && [[ "$action" == "switch" ]]; then
    verb="already up to date"
    next="nothing to activate"
  else
    ui_step "Activate · $action"
    local cmd
    if [[ "$kind" == "local" ]]; then
      cmd=(sudo nixos-rebuild "$action" -p "$profile" --store-path "$out")
    else
      ui_info "$host will ask for $(ui_bold "$user")'s sudo password — that's the password on $system"
      cmd=(nixos-rebuild "$action" --store-path "$out" --target-host "$ssh_target" --ask-sudo-password)
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
    if [[ "$action" == "boot" && "$kind" == "local" ]]; then
      next="reboot and pick $(ui_bold "Sisyphus") under GRUB's System Select"
    elif [[ "$action" == "boot" ]]; then
      next="active after $system's next reboot"
    fi
  fi

  # summary ──────────────────────────────────────────────────────────────────
  local lines=() size old_size delta=""
  lines+=("$(kvline host "$system  $(ui_dim "($key)")")")
  [[ "$kind" == "remote" ]] && lines+=("$(kvline target "$ssh_target")")
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
    local glink; glink=$(readlink "/nix/var/nix/profiles/system-profiles/$profile" 2>/dev/null || true)
    [[ -n "$glink" ]] && { glink=${glink#"$profile"-}; lines+=("$(kvline generation "${glink%-link}")"); }
  fi
  [[ -n "$next" ]] && lines+=("$(kvline next "$next")")
  ui_box "$UI_GREEN" "✔ $system $verb" "${lines[@]}"
  [[ -n "$tmp" ]] && rm -rf "$tmp"
  return 0
}

# ── Other jobs ────────────────────────────────────────────────────────────────

# lock_table FILE → "input<TAB>rev7<TAB>lastModified" for every root input.
lock_table() {
  jq -r '.nodes as $n | $n.root.inputs | to_entries[]
    | .key as $k | (.value | if type == "array" then .[-1] else . end) as $node
    | [$k, (($n[$node].locked.rev // $n[$node].locked.narHash // "?")[0:7]),
       ($n[$node].locked.lastModified // 0)] | @tsv' "$1"
}

update_inputs() {
  ui_header "update flake inputs" "$(git branch --show-current 2>/dev/null)"
  local before; before=$(mktemp)
  cp flake.lock "$before"
  ui_step "nix flake update"
  if ! ui_spin "fetching every input…" nix flake update; then
    rm -f "$before"; ui_err "nix flake update failed (output above)"; return 1
  fi
  local changed=0 name rev mod orev omod
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
  case "$(ui_choose "Rebuild Sisyphus on the new inputs?" "Switch now:switch" "Build only (see the diff):build" "Later:later" || echo later)" in
    switch) rebuild Sisyphus switch ;;
    build)  rebuild Sisyphus build ;;
    *)      ui_info "run system-rebuild when you're ready" ;;
  esac
}

sync_repo() {
  ui_header "git sync" "$(git branch --show-current 2>/dev/null)"
  local msg=""
  if [[ -n "$(git status --porcelain)" ]]; then
    git status --short | head -15 | sed 's/^/    /'
    msg=$(ui_input "commit message" "chore: sync") || return 1
  fi
  ui_step "Syncing"
  if [[ -n "$msg" ]]; then git-sync "$msg"; else git-sync; fi && ui_ok "in sync with origin"
}

collect_garbage() {
  ui_header "garbage collect" "$(uname -n)"
  ui_warn "deletes every old generation — you can't roll back past the current one"
  ui_confirm "Collect garbage now?" default-no || { ui_info "nothing done"; return 1; }
  local before after
  before=$(df -B1 --output=avail /nix/store | tail -1)
  nix-gc
  after=$(df -B1 --output=avail /nix/store | tail -1)
  ui_ok "freed $(ui_bytes $(( after > before ? after - before : 0 )))"
}

asgard_menu() {
  ui_box "$UI_YELLOW" "Asgard is managed on Asgard" \
    "Its checkout of this repo is where server changes are made, and it can be" \
    "ahead of this one. Pushing from here would replace the live config with" \
    "whatever this machine has."
  case "$(ui_choose "Asgard" "Open a shell on Asgard:ssh" "Push from here anyway…:push" "← Back:back" || echo back)" in
    ssh) exec ssh -t "rock@asgard" ;;
    push)
      ui_confirm "Really overwrite Asgard's live config with this machine's?" default-no || return 0
      local action
      action=$(ui_choose "Action" "Switch — activate now:switch" "Boot — on next reboot:boot" "← Back:back" || echo back)
      [[ "$action" == "back" ]] && return 0
      rebuild Asgard "$action" asgard ;;
    *) return 0 ;;
  esac
}

deploy_menu() {
  ui_box "$UI_RED" "Deploy onto NEW hardware" \
    "The target must already be booted from the Apollo USB (check: apollo-connect)." \
    "INSTALL erases the target's disks — apollo-deploy asks you to type the host name."
  local mode
  mode=$(ui_choose "Kit-Kat — her machine" \
    "Dry run — print the disk script, change nothing:dry" \
    "VM test — apply the layout in a throwaway VM:vm" \
    "INSTALL — erase and install:install" \
    "← Back:back" || echo back)
  case "$mode" in
    dry)     exec apollo-deploy --dry-run kitkat-Kit-Kat ;;
    vm)      exec apollo-deploy --vm-test kitkat-Kit-Kat ;;
    install) exec apollo-deploy kitkat-Kit-Kat ;;
    *)       return 0 ;;
  esac
}

apollo_menu() {
  case "$(ui_choose "Apollo USB" \
    "Build the ISO and copy it to the stick:iso" \
    "Write the tailnet key onto the stick:key" \
    "Connect to a booted stick:connect" \
    "← Back:back" || echo back)" in
    iso)     exec apollo-iso ;;
    key)     exec apollo-key ;;
    connect) exec apollo-connect ;;
    *)       return 0 ;;
  esac
}

action_menu() {  # action_menu SYSTEM → switch/boot/build/back
  ui_choose "$1 — how?" \
    "Switch — build, show changes, activate now:switch" \
    "Boot — build, show changes, activate on next boot:boot" \
    "Build — build and show changes only:build" \
    "← Back:back" || echo back
}

# ── Entry ─────────────────────────────────────────────────────────────────────
if [[ -z "${1:-}" ]]; then
  FROM_MENU=1
  (( UI_INTERACTIVE )) || { echo "Usage: system-rebuild USER SYSTEM [--boot|--build] [--target HOST]"; exit 2; }
  home_screen
  while :; do
    choice=$(ui_choose "What now?" \
      "Rebuild Sisyphus          switch · boot · build:sisyphus" \
      "Push to Kit-Kat           her machine, over the tailnet:kitkat" \
      "Asgard                    the server:asgard" \
      "Update flake inputs       nix flake update + changelog:update" \
      "Git sync                  commit, pull --rebase, push:sync" \
      "Garbage collect           old generations + store:gc" \
      "Deploy new hardware       via the Apollo USB:deploy" \
      "Apollo USB                ISO · key · connect:apollo" \
      "Quit:quit" || echo quit)
    case "$choice" in
      sisyphus) a=$(action_menu Sisyphus); [[ "$a" == back ]] && continue; rebuild Sisyphus "$a"; exit $? ;;
      kitkat)   a=$(action_menu Kit-Kat);  [[ "$a" == back ]] && continue; rebuild Kit-Kat "$a"; exit $? ;;
      asgard)   asgard_menu || true; continue ;;
      update)   update_inputs; exit $? ;;
      sync)     sync_repo; exit $? ;;
      gc)       collect_garbage; exit $? ;;
      deploy)   deploy_menu; continue ;;
      apollo)   apollo_menu; continue ;;
      *)        echo; exit 0 ;;
    esac
  done
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
    *) ui_err "unknown option: $1"; exit 2 ;;
  esac
  shift
done
if [[ -z "$system" ]]; then
  echo "Usage: system-rebuild USER SYSTEM [--boot|--build] [--target HOST]"
  echo "   or: system-rebuild            (home screen)"
  exit 2
fi
# Asgard's live config is edited on Asgard; refuse to overwrite it from here
# unless --target says that's deliberate (the menu asks instead).
if [[ "$system" == "Asgard" && -z "$target" ]]; then
  ui_err "Asgard is managed on Asgard, not from here."
  ui_info "ssh asgard && sudo nixos-rebuild switch --flake ~/Dots#rock-Asgard"
  ui_info "to override deliberately: system-rebuild rock Asgard --target asgard"
  exit 1
fi
rebuild "$system" "$action" "$target"
