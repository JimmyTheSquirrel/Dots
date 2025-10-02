#!/usr/bin/env bash
set -euo pipefail

# --- User settings ------------------------------------------------------------
WALL_DIR="${HOME}/Pictures/Wallpapers"
CACHE_DIR="${HOME}/.cache/thumbnails/wal_selector"
THEME="${HOME}/.config/rofi/wallpaper-sel-config.rasi"

# Rofi: ignore global config; force our theme
ROFI=(rofi -no-config -dmenu -theme "$THEME" -show-icons)

# Thumbnails
THUMB_SIZE=500

# swww transition defaults
SWWW_ARGS=(
  --transition-type any
  --transition-fps 60
  --transition-duration 1.0
  --resize crop
)

# --- Checks -------------------------------------------------------------------
command -v rofi >/dev/null 2>&1 || { echo "Error: rofi not found." >&2; exit 1; }
command -v swww >/dev/null 2>&1 || { echo "Error: swww not found." >&2; exit 1; }

[[ -f "$THEME" ]] || { echo "Error: theme not found: $THEME" >&2; exit 1; }
[[ -d "$WALL_DIR" ]] || { echo "Error: wallpapers dir not found: $WALL_DIR" >&2; exit 1; }

mkdir -p "$CACHE_DIR"

# --- Thumb helper -------------------------------------------------------------
make_thumb () {
  local src="$1" dst="$2"
  if command -v magick >/dev/null 2>&1; then
    magick convert -strip "$src" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" \
      -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$dst"
  elif command -v convert >/dev/null 2>&1; then
    convert -strip "$src" -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" \
      -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$dst"
  else
    echo "Error: ImageMagick (magick/convert) not found." >&2
    exit 1
  fi
}

# --- Build thumbnails ---------------------------------------------------------
while IFS= read -r -d '' img; do
  bn="$(basename "$img")"
  thumb="$CACHE_DIR/$bn"
  [[ -f "$thumb" ]] || make_thumb "$img" "$thumb"
done < <(find "$WALL_DIR" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

# --- Rofi menu (newest first) -------------------------------------------------
SELECTION="$(
  find "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf "%T@|%f\n" \
  | sort -nr \
  | cut -d'|' -f2- \
  | while IFS= read -r bn; do
      printf '%s\x00icon\x1f%s\n' "$bn" "$CACHE_DIR/$bn"
    done \
  | "${ROFI[@]}"
)"

[[ -n "${SELECTION:-}" ]] || exit 0
CHOSEN="$WALL_DIR/$SELECTION"

# --- swww: ensure daemon, then set on ALL outputs -----------------------------
# Start daemon if needed
if ! swww query >/dev/null 2>&1; then
  swww init
  # tiny wait so the socket is ready
  sleep 0.15
fi

# Get output names and apply on each
# (works on Hyprland, sway, wlroots generally)
mapfile -t OUTPUTS < <(swww query | awk '/^OUTPUT/ {print $2}')
if ((${#OUTPUTS[@]}==0)); then
  # Fallback: try once without explicit output (swww will pick focused)
  swww img "$CHOSEN" "${SWWW_ARGS[@]}"
else
  for out in "${OUTPUTS[@]}"; do
    swww img -o "$out" "$CHOSEN" "${SWWW_ARGS[@]}"
  done
fi

exit 0
