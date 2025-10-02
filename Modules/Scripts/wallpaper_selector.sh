#!/usr/bin/env bash
#  ██╗    ██╗ █████╗ ██╗     ██╗     ██████╗  █████╗ ██████╗ ███████╗██████╗
#  ██║    ██║██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗
#  ██║ █╗ ██║███████║██║     ██║     ██████╔╝███████║██████╔╝█████╗  ██████╔╝
#  ██║███╗██║██╔══██║██║     ██║     ██╔═══╝ ██╔══██║██╔═══╝ ██╔══╝  ██╔══██╗
#  ╚███╔███╔╝██║  ██║███████╗███████╗██║     ██║  ██║██║     ███████╗██║  ██║
#   ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝
#
#  ██╗      █████╗ ██╗   ██╗███╗   ██╗ ██████╗██╗  ██╗███████╗██████╗
#  ██║     ██╔══██╗██║   ██║████╗  ██║██╔════╝██║  ██║██╔════╝██╔══██╗
#  ██║     ███████║██║   ██║██╔██╗ ██║██║     ███████║█████╗  ██████╔╝
#  ██║     ██╔══██║██║   ██║██║╚██╗██║██║     ██╔══██║██╔══╝  ██╔══██╗
#  ███████╗██║  ██║╚██████╔╝██║ ╚████║╚██████╗██║  ██║███████╗██║  ██║
#  ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
#
# Heavily inspired by: develcooking - https://github.com/develcooking/hyprland-dotfiles
# This script runs a Rofi launcher to select wallpapers and sets them with swww.

# --- Configuration ---
wall_dir="${HOME}/Pictures/Wallpapers"
cache_dir="${HOME}/.cache/thumbnails/wal_selector"
rofi_config_path="${HOME}/.config/rofi/wallpaper-sel-config.rasi"
rofi_command="rofi -dmenu -config ${rofi_config_path}"

# --- Create cache dir if not exists ---
mkdir -p "${cache_dir}"

# --- Generate thumbnails ---
for imagen in "$wall_dir"/*.{jpg,jpeg,png,webp}; do
    [ -f "$imagen" ] || continue
    filename=$(basename "$imagen")
    if [ ! -f "${cache_dir}/${filename}" ]; then
        magick convert -strip "$imagen" -thumbnail 500x500^ -gravity center -extent 500x500 "${cache_dir}/${filename}"
    fi
done

# --- Launch Rofi to select wallpaper ---
wall_selection=$(ls "${wall_dir}" -t | while read -r A; do
    echo -en "$A\x00icon\x1f${cache_dir}/$A\n"
done | $rofi_command)

# --- Exit if nothing selected ---
[ -z "$wall_selection" ] && exit 0

# --- Full path of selected wallpaper ---
full_path="${wall_dir}/${wall_selection}"

# --- Ensure swww-daemon is running ---
if ! pgrep -x swww-daemon >/dev/null; then
    echo "Starting swww-daemon..."
    swww-daemon &
    sleep 0.5
fi

# --- Set wallpaper with swww ---
swww img "$full_path"

# --- Optional: trigger pywal if installed ---
if command -v wal &>/dev/null; then
    wal -i "$full_path"
fi

exit 0
