# nix-gc — packaged by Modules/Shell/deploy-tools.nix.
#
# The deliberate, do-it-now cleanup. The routine version runs on its own:
# base.nix schedules a weekly nix.gc + store optimise and caps the journal, and
# Modules/Gaming/wolf.nix auto-prunes Docker weekly. So this is only for "I need
# the space back right now".
#
# What it no longer does, and why:
#   - `podman system prune` — podman is not installed on the desktops, so the
#     command exited 127 under errexit before the summary ever printed.
#   - `journalctl --vacuum-time` — it ran without sudo (so it could not touch
#     the system journal), and the journald cap makes it unnecessary anyway.
#   - `du -sh /nix/store` — walking the whole store just to print one number
#     took longer than the cleanup.

echo -e "\n\033[1;34m==> Deleting every old generation, then collecting garbage...\033[0m"
sudo nix-collect-garbage -d

echo -e "\n\033[1;34m==> Optimising the nix store (hard-linking duplicates)...\033[0m"
sudo nix-store --optimise

# Only where Docker exists (Sisyphus, for Wolf). sudo because membership of
# the docker group is not something this repo grants.
if command -v docker >/dev/null 2>&1; then
  echo -e "\n\033[1;34m==> Pruning stopped Docker containers, dangling images, unused networks...\033[0m"
  sudo docker system prune -f
fi

echo -e "\n\033[1;32m==> All done!\033[0m"
