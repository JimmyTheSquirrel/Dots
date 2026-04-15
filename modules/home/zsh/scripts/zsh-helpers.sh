#!/usr/bin/env bash
# --------------------------------
# --- Dots helpers ---------------
# --------------------------------

system-rebuild() {
  (
    set -euo pipefail
    cd ~/Dots || { echo "❌ ~/Dots not found"; exit 1; }

    local user="${1:-}"
    local system="${2:-}"
    local boot_only=false

    # Check for --boot flag
    if [[ "${3:-}" == "--boot" ]] || [[ "${2:-}" == "--boot" ]]; then
      boot_only=true
      # If --boot is second arg, system wasn't provided
      if [[ "${2:-}" == "--boot" ]]; then
        system=""
      fi
    fi

    if [[ -z "$user" ]] || [[ -z "$system" ]]; then
      echo "Usage: system-rebuild USER SYSTEM [--boot]"
      echo "  e.g.  system-rebuild rock Sisyphus"
      echo "  e.g.  system-rebuild rock Sisyphus --boot  (build without switching)"
      echo ""
      echo "Available nixosConfigurations:"
      nix flake show . 2>/dev/null | sed -n 's/^ *nixosConfigurations\.\([A-Za-z0-9._-]\+\).*/  \1/p'
      exit 2
    fi

    # Build flake key (e.g., rock-Sisyphus)
    local flake_key="${user}-${system}"
    # Extract profile name (lowercase system name, e.g., sisyphus)
    local profile=$(echo "$system" | tr '[:upper:]' '[:lower:]')

    local action="switch"
    local action_desc="Rebuilding and switching to"
    if [[ "$boot_only" == true ]]; then
      action="boot"
      action_desc="Building (boot only, no switch)"
    fi

    echo -e "\n\033[1;34m==> ${action_desc} ${flake_key} (profile: ${profile})...\033[0m"
    echo "+ sudo nixos-rebuild ${action} -p ${profile} --flake .#${flake_key}"

    if sudo nixos-rebuild "${action}" -p "${profile}" --flake ".#${flake_key}"; then
      echo -e "\n\033[1;32m==> All done!\033[0m"
      if [[ "$boot_only" == true ]]; then
        echo -e "\033[1;33m==> Profile built but not activated. Reboot to use it.\033[0m"
      fi
    else
      echo -e "\n\033[1;31m==> Build failed. Check the output above.\033[0m"
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


