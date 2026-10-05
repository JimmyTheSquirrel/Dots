# Start kodi when the launch-script exits.
# Hardened restart: wait for moonlight-qt to fully exit and release DRM master
# before Kodi grabs the GPU again, otherwise Kodi's GBM backend fails to init
# ("failed to initialize Atomic/Legacy DRM") and comes up on a dead/dummy display,
# which looks like a hang on returning to the Kodi menu.
_moonlight_restart_kodi() {
  LOG=/storage/moonlight-exit.log
  echo "$(date -Iseconds) moonlight exited, waiting for DRM release" >>"$LOG"

  # Wait up to 10s for the moonlight-qt process to be gone.
  for i in $(seq 1 20); do
    pgrep moonlight-qt >/dev/null 2>&1 || break
    sleep 0.5
  done

  # Settle so the kernel reaps the DRM master fd before Kodi reopens card1.
  sleep 3

  echo "$(date -Iseconds) starting kodi (drm status: $(cat /sys/class/drm/card1-HDMI-A-1/status 2>/dev/null))" >>"$LOG"
  systemctl start kodi
}
trap _moonlight_restart_kodi EXIT
