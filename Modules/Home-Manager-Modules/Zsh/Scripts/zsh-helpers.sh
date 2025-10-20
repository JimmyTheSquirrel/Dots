#!/usr/bin/env bash
# --------------------------------
# --- Dots helpers ---------------
# --------------------------------

system-rebuild() {
  (
    set -euo pipefail
    cd ~/Dots || { echo "❌ ~/Dots not found"; exit 1; }

    # Require an explicit key to avoid falling back to hostname ("nixos")
    local sys="${1:-}"
    if [[ -z "$sys" ]]; then
      echo "Usage: system-rebuild <flake-key>   e.g.  system-rebuild Sisyphus"
      echo "Available nixosConfigurations:"
      nix flake show . | sed -n 's/^ *nixosConfigurations\.\([A-Za-z0-9._-]\+\).*/  \1/p'
      exit 2
    fi

    # Allow '#Sisyphus' muscle memory
    sys="${sys#\#}"

    echo -e "\n\033[1;34m==> Rebuilding NixOS system (#${sys})...\033[0m"
    echo "+ sudo nixos-rebuild switch --flake .#${sys}"
    sudo nixos-rebuild switch --flake ".#${sys}"

    echo -e "\n\033[1;34m==> Rebuilding Home Manager (#${sys})...\033[0m"
    echo "+ home-manager switch --flake .#${sys}"
    home-manager switch --flake ".#${sys}"

    echo -e "\n\033[1;32m==> All done!\033[0m"
  )
}

git-sync() {
  (
    set -e
    cd ~/Dots || exit 1
    if [[ -n "$1" ]]; then git add -A; git commit -m "$1" || echo "Nothing to commit."; fi
    if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
      STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
      echo "↪ repo dirty — stashing as $STASH_MSG"
      git stash push -u -m "$STASH_MSG"; HAD_STASH=1
    fi
    echo "↪ pulling (rebase)…"; git pull --rebase
    if [[ -n "$HAD_STASH" ]]; then echo "↪ restoring stashed changes…"; git stash pop || echo "⚠ stash pop had conflicts"; fi
    echo "↪ pushing…"; git push
  )
}
