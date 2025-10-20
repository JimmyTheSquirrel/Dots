#!/usr/bin/env bash
set -euo pipefail

# --- User settings ------------------------------------------------------------
WALL_DIR="${HOME}/Pictures/Wallpapers"
THEME="${HOME}/.config/rofi/wallpaper-sel-config.rasi"

# swww transition defaults
SWWW_ARGS=(
  --transition-type any
  --transition-fps 60
  --transition-duration 1.0
  --resize crop
)

# --- helpers ------------------------------------------------------------------
get_mon_w() {
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl monitors | awk '/focused: yes/{f=1} f&&/width:/{print $2; exit}'
  elif command -v swww >/dev/null 2>&1; then
    swww query | awk -F'[x+ ]' '/^res/ {print $2; exit}'
  fi
}

# --- geometry (choose per monitor) -------------------------------------------
MON_W="$(get_mon_w)"

# Defaults for 1080p-ish
THUMB_W=300
THUMB_H=520
WINW="80%"       # window width
COLS=5
SPACING=28
PAD_Y=10
PAD_X=14
ICON_SIZE=$(( THUMB_H - 16 ))

# Ultrawide (≈2560x1080): slightly thinner cards
if [ -n "$MON_W" ] && [ "$MON_W" -ge 2500 ]; then
  THUMB_W=270
  THUMB_H=500
  WINW="78%"
  COLS=5          # keep same columns for a consistent feel; more gutter on UW
  SPACING=30
  PAD_Y=12
  PAD_X=16
  ICON_SIZE=$(( THUMB_H - 16 ))
fi

# Cache per size so shapes never clash
CACHE_DIR="${HOME}/.cache/thumbnails/wal_selector/${THUMB_W}x${THUMB_H}"

# --- checks -------------------------------------------------------------------
command -v rofi   >/dev/null 2>&1 || { echo "Error: rofi not found." >&2;  exit 1; }
command -v swww   >/dev/null 2>&1 || { echo "Error: swww not found." >&2;  exit 1; }
command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || {
  echo "Error: ImageMagick not found." >&2; exit 1; }

[[ -f "$THEME" ]] || { echo "Error: theme not found: $THEME" >&2; exit 1; }
[[ -d "$WALL_DIR" ]] || { echo "Error: wallpapers dir not found: $WALL_DIR" >&2; exit 1; }

mkdir -p "$CACHE_DIR"

# --- thumbnail maker ----------------------------------------------------------
make_thumb () {
  local src="$1" dst="$2"
  if command -v magick >/dev/null 2>&1; then
    magick convert -strip "$src" -thumbnail "${THUMB_W}x${THUMB_H}^" \
      -gravity center -extent "${THUMB_W}x${THUMB_H}" "$dst"
  else
    convert -strip "$src" -thumbnail "${THUMB_W}x${THUMB_H}^" \
      -gravity center -extent "${THUMB_W}x${THUMB_H}" "$dst"
  fi
}

# --- build thumbnails ---------------------------------------------------------
while IFS= read -r -d '' img; do
  bn="$(basename "$img")"
  thumb="$CACHE_DIR/$bn"
  [[ -f "$thumb" ]] || make_thumb "$img" "$thumb"
done < <(find "$WALL_DIR" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

# --- rofi (newest first, labels hidden) --------------------------------------
SELECTION="$(
  find "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf "%T@|%f\n" \
  | sort -nr \
  | cut -d'|' -f2- \
  | while IFS= read -r bn; do
      printf '%s\x00icon\x1f%s\n' "$bn" "$CACHE_DIR/$bn"
    done \
  | rofi -no-config -dmenu -theme "$THEME" -show-icons \
      -columns "$COLS" \
      -theme-str "window { width: ${WINW}; }" \
      -theme-str "mainbox { padding: 14px; }" \
      -theme-str "listview { spacing: ${SPACING}px; }" \
      -theme-str "element { orientation: vertical; padding: ${PAD_Y}px ${PAD_X}px; margin: 6px 10px; }" \
      -theme-str "element-icon { size: ${ICON_SIZE}px; }" \
      -theme-str "element-text { width: 0px; padding: 0px; margin: 0px; font-size: 0px; }" \
      -p "Search Wallpaper"
)"

[[ -n "${SELECTION:-}" ]] || exit 0
CHOSEN="$WALL_DIR/$SELECTION"

# --- swww on all outputs ------------------------------------------------------
if ! swww query >/dev/null 2>&1; then
  swww init
  sleep 0.15
fi

mapfile -t OUTPUTS < <(swww query | awk '/^OUTPUT/ {print $2}')
if ((${#OUTPUTS[@]}==0)); then
  swww img "$CHOSEN" "${SWWW_ARGS[@]}"
else
  for out in "${OUTPUTS[@]}"; do
    swww img -o "$out" "$CHOSEN" "${SWWW_ARGS[@]}"
  done
fi

exit 0
