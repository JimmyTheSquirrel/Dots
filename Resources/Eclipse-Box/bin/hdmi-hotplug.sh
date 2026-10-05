#!/bin/sh
# Restart Kodi when the HDMI link comes back up.
#
# Kodi picks its DRM connector ONCE at startup and never re-probes. If it
# starts with no display attached it logs
#   CWinSystemGbm::InitWindowSystem - failed to initialize Atomic/Legacy DRM
# and falls back to a headless 1280x720 dummy, so plugging the TV in later
# brings the connector up while Kodi keeps painting the dummy -> "no signal"
# forever until someone restarts it by hand.
#
# Busybox shell: no `timeout`, and `pgrep -x` returns nothing on this box, so
# match moonlight without -x.

CONN=/sys/class/drm/card1-HDMI-A-1
TAG=hdmi-hotplug
prev=""

log() { logger -t "$TAG" "$1"; echo "$(date '+%F %T') $1" >> /storage/hdmi-hotplug.log; }

log "watcher started (connector $(basename $CONN))"

while :; do
    st=$(cat "$CONN/status" 2>/dev/null)

    if [ "$st" = "connected" ] && [ "$prev" != "connected" ] && [ -n "$prev" ]; then
        # Let HPD settle and the EDID read complete before judging anything.
        sleep 5

        st=$(cat "$CONN/status" 2>/dev/null)
        en=$(cat "$CONN/enabled" 2>/dev/null)
        edid=$(wc -c < "$CONN/edid" 2>/dev/null)

        # `enabled` is the field that says whether this connector is the one
        # actually being driven -- `status` only says a cable is present.
        # enabled=disabled while connected == Kodi is on the dummy.
        if [ "$st" != "connected" ]; then
            log "link bounced back to '$st' within settle window - ignoring"
        elif [ "$en" = "enabled" ]; then
            log "link up (edid ${edid}b) and Kodi already driving it - no action"
        elif pgrep moonlight-qt > /dev/null 2>&1; then
            # Moonlight stops Kodi deliberately and owns DRM; restarting Kodi
            # here would fight it for the display mid-stream.
            log "link up but moonlight-qt is running - leaving Kodi stopped"
        elif ! systemctl is-active --quiet kodi; then
            log "link up but kodi is not active (deliberate?) - not starting it"
        else
            log "link up (edid ${edid}b), Kodi not driving it - restarting kodi"
            systemctl restart kodi
        fi
    fi

    prev=$st
    sleep 2
done
