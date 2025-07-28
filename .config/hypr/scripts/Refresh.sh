#!/bin/bash
# 💫 AGS + SwayNC refresh without killing or flickering Waybar

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

file_exists() {
    [ -e "$1" ]
}

# Only kill rofi and swaync — not AGS or Waybar
_ps=(rofi swaync)
for _prs in "${_ps[@]}"; do
    if pidof "${_prs}" >/dev/null; then
        pkill "${_prs}"
    fi
done

# Send a safe CSS refresh to Waybar
#killall -SIGUSR2 waybar

# Hot-reload AGS (no window restart = no flicker)
ags -r

# Reload swaync
sleep 0.5
swaync > /dev/null 2>&1 &
swaync-client --reload-config

# Relaunch rainbow borders if present
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
    ${UserScripts}/RainbowBorders.sh &
fi

exit 0
