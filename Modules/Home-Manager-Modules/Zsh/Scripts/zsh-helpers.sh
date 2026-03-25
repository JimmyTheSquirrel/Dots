#!/usr/bin/env bash
# --------------------------------
# --- Dots helpers ---------------
# --------------------------------

system-rebuild() {
  (
    set -euo pipefail
    cd ~/Dots || { echo "❌ ~/Dots not found"; exit 1; }

    local sys="${1:-}"
    if [[ -z "$sys" ]]; then
      echo "Usage: system-rebuild <flake-key>   e.g.  system-rebuild Sisyphus"
      echo "Available nixosConfigurations:"
      nix flake show . | sed -n 's/^ *nixosConfigurations\.\([A-Za-z0-9._-]\+\).*/  \1/p'
      exit 2
    fi

    sys="${sys#\#}"

    echo -e "\n\033[1;34m==> Rebuilding NixOS + Home Manager (#${sys})...\033[0m"
    echo "+ sudo nixos-rebuild switch --flake .#${sys}"
    if sudo nixos-rebuild switch --flake ".#${sys}"; then
      echo -e "\n\033[1;32m==> All done!\033[0m"
    else
      echo -e "\n\033[1;31m==> Build failed. Check the output above — if it mentions 'rock profile' or 'home-manager' it's a HM issue, otherwise it's a NixOS config issue.\033[0m"
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


