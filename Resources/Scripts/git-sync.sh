# git-sync [MESSAGE] — packaged by Modules/Shell/deploy-tools.nix.
#
# Commit everything (when given a message), stash whatever is left, pull
# --rebase, restore the stash, push. The `cd` below only moves THIS process —
# a script cannot change its caller's directory — so there is nothing to
# restore on exit. (There used to be a `trap 'cd "$ORIG_DIR"' EXIT` here,
# which therefore did nothing.)
cd "$HOME/Dots" || { echo ":: $HOME/Dots not found"; exit 1; }

if [[ -n "${1:-}" ]]; then
  git add -A
  git commit -m "${1}" || echo ":: Nothing to commit."
fi

HAD_STASH=0
if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
  STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
  echo ":: repo dirty - stashing as $STASH_MSG"
  git stash push -u -m "$STASH_MSG"
  HAD_STASH=1
fi

branch="$(git branch --show-current)"
if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
  echo ":: no upstream for '$branch' - setting origin/$branch"
  git fetch origin
  git push -u origin "$branch"
fi

echo ":: pulling (rebase)..."
git pull --rebase

if [[ "$HAD_STASH" -eq 1 ]]; then
  echo ":: restoring stashed changes..."
  git stash pop || echo "!! stash pop had conflicts"
fi

echo ":: pushing..."
git push
