#!/usr/bin/env bash
# --------------------------------
# --- Dots helpers ---------------
# --------------------------------

system-rebuild() {
  (
    set -euo pipefail
    cd ~/Dots || { echo "❌ ~/Dots not found"; exit 1; }

    local user="rock"
    local system=""
    local action="switch"

    # Interactive mode if no arguments
    if [[ -z "${1:-}" ]]; then
      echo -e "\033[1;36m╭──────────────────────────────╮\033[0m"
      echo -e "\033[1;36m│     System Rebuild Menu      │\033[0m"
      echo -e "\033[1;36m╰──────────────────────────────╯\033[0m"
      echo ""
      echo -e "\033[1;33mSelect System:\033[0m"
      echo "  1) Sisyphus  (Niri)"
      echo "  2) Odysseus  (Hyprland)"
      echo "  3) Elektra   (KDE Plasma)"
      echo "  4) Asgard    (Media Server)"
      echo ""
      echo -n "System [1-4]: "
      read sys_choice

      case "$sys_choice" in
        1) system="Sisyphus" ;;
        2) system="Odysseus" ;;
        3) system="Elektra" ;;
        4) system="Asgard" ;;
        *) echo "Invalid choice"; exit 1 ;;
      esac

      echo ""
      echo -e "\033[1;33mSelect Action:\033[0m"
      echo "  1) Switch  (rebuild & activate now)"
      echo "  2) Boot    (rebuild for GRUB menu)"
      echo "  3) Test    (test the build)"
      echo ""
      echo -n "Action [1-3]: "
      read action_choice

      case "$action_choice" in
        1) action="switch" ;;
        2) action="boot" ;;
        3) action="build" ;;
        *) echo "Invalid choice"; exit 1 ;;
      esac
    else
      # CLI mode: system-rebuild USER SYSTEM [--boot]
      user="${1:-}"
      system="${2:-}"

      if [[ "${3:-}" == "--boot" ]]; then
        action="boot"
      fi

      if [[ -z "$system" ]]; then
        echo "Usage: system-rebuild USER SYSTEM [--boot]"
        echo "   or: system-rebuild  (interactive menu)"
        exit 2
      fi
    fi

    local flake_key="${user}-${system}"
    local profile=$(echo "$system" | tr '[:upper:]' '[:lower:]')

    if [[ "$action" == "switch" ]]; then
      echo -e "\n\033[1;34m==> Rebuilding and switching to ${system}...\033[0m"
    else
      echo -e "\n\033[1;34m==> Building ${system} (select from GRUB)...\033[0m"
    fi

    if sudo nixos-rebuild "${action}" -p "${profile}" --flake ".#${flake_key}"; then
      echo -e "\n\033[1;32m==> Done!\033[0m"
      if [[ "$action" == "boot" ]]; then
        echo -e "\033[1;33m==> Reboot and select ${system} from GRUB.\033[0m"
      fi
    else
      echo -e "\n\033[1;31m==> Build failed.\033[0m"
      exit 1
    fi
  )
}

git-sync() {
  (
    set -euo pipefail

    ORIG_DIR="$PWD"
    trap 'cd "$ORIG_DIR"' EXIT

    cd ~/Dots || { echo "❌ ~/Dots not found"; exit 1; }

    # Optional commit message
    if [[ -n "${1:-}" ]]; then
      git add -A
      git commit -m "$1" || echo "↪ Nothing to commit."
    fi

    # Stash if dirty (including untracked)
    HAD_STASH=0
    if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
      STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
      echo "↪ repo dirty — stashing as $STASH_MSG"
      git stash push -u -m "$STASH_MSG"
      HAD_STASH=1
    fi

    # Ensure upstream exists
    branch="$(git branch --show-current)"
    if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
      echo "↪ no upstream for '$branch' — setting origin/$branch"
      git fetch origin
      git push -u origin "$branch"
    fi

    echo "↪ pulling (rebase)…"
    git pull --rebase

    if [[ "$HAD_STASH" -eq 1 ]]; then
      echo "↪ restoring stashed changes…"
      git stash pop || echo "⚠ stash pop had conflicts"
    fi

    echo "↪ pushing…"
    git push
  )
}


