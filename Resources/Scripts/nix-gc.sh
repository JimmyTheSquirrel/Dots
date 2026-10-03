# nix-gc — packaged by Modules/Shell/deploy-tools.nix (lib/ui.sh prepended;
# writeShellApplication: errexit/nounset/pipefail on, shellcheck at build time).
#
# The weekly automatic nix.gc + nix.optimise and the journald size cap live in
# Modules/Core/base.nix; this is the "do it now, and delete every old
# generation" version. Also reachable from system-rebuild's menu.
ui_step "Deleting every old generation, then collecting garbage"
sudo nix-collect-garbage -d
ui_step "Optimising the store (hard-linking duplicates)"
sudo nix-store --optimise
# Wolf is the only Docker user (Sisyphus); elsewhere there's nothing to prune.
if command -v docker >/dev/null 2>&1; then
  ui_step "Pruning stopped containers, dangling images, unused networks"
  sudo docker system prune -f
fi
ui_ok "store cleaned"
