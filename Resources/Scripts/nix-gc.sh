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
# Wolf is the only Docker user (Sisyphus). Asgard runs its containers under
# PODMAN (virtualisation.oci-containers.backend = "podman"), so a docker-only
# check found nothing there and the step silently did nothing — prune whichever
# engine the machine actually has.
#
# ⚠ `system prune -f` only, never `image prune -af`: -a removes every image not
# attached to a running container, which on Sisyphus eats the Wolf images.
for engine in docker podman; do
  if command -v "$engine" >/dev/null 2>&1; then
    ui_step "Pruning stopped containers, dangling images, unused networks ($engine)"
    sudo "$engine" system prune -f
  fi
done
ui_ok "store cleaned"
