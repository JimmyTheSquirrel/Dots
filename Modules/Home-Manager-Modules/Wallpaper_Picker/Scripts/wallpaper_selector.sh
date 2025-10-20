#!/usr/bin/env bash
set -euo pipefail

# --- User dirs ---------------------------------------------------------------
WALL_DIR="${HOME}/Pictures/Wallpapers"

# --- Rofi & swww checks ------------------------------------------------------
command -v rofi  >/dev/null 2>&1 || { echo "Error: rofi not found." >&2;  exit 1; }
command -v swww  >/dev/null 2>&1 || { echo "Error: swww not found." >&2;  exit 1; }
command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || {
  echo "Error: ImageMagick not found (magick/convert)." >&2; exit 1; }

[[ -d "$WALL_DIR" ]] || { echo "Error: wallpapers dir not found: $WALL_DIR" >&2; exit 1; }

# --- Monitor width -----------------------------------------------------------
get_mon_w() {
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl monitors | awk '/focused: yes/{f=1} f&&/width:/{print $2; exit}'
  elif command -v swww >/dev/null 2>&1; then
    swww query | awk -F'[x+ ]' '/^res/ {print $2; exit}'
  fi
}
MON_W="${MON_W:-$(get_mon_w || echo 1920)}"
[[ -n "$MON_W" ]] || MON_W=1920

# --- Portrait card geometry (adaptive) ---------------------------------------
# Use *portrait* thumbnails: ICON_W x ICON_H (e.g., 300 x 560)
if (( MON_W >= 2500 )); then
  ICON_W=270
  ICON_H=540
  USABLE=$(( MON_W * 78 / 100 ))   # window width
  GAP=28                           # spacing between cards
  PAD=14                           # inner padding per card
else
  ICON_W=300
  ICON_H=560
  USABLE=$(( MON_W * 80 / 100 ))
  GAP=24
  PAD=12
fi

# choose columns so columnWidth ≈ ICON_W + padding + border allowance
choose_cols() {
  local usable="$1" want="$2" gap="$3"
  local bestCols=5
  local bestDiff=999999
  for cols in {4..8}; do
    local cw=$(( (usable - gap*(cols-1)) / cols ))
    local diff=$(( cw>want ? cw-want : want-cw ))
    if (( diff < bestDiff )); then bestDiff=$diff; bestCols=$cols; fi
  done
  echo "$bestCols"
}
WANT_W=$(( ICON_W + 2*PAD + 2 ))    # selection outline ~2px total
COLS="$(choose_cols "$USABLE" "$WANT_W" "$GAP")"

# cache dir keyed by WxH so we never mix shapes
CACHE_DIR="${HOME}/.cache/thumbnails/wal_selector/${ICON_W}x${ICON_H}"
mkdir -p "$CACHE_DIR"

# --- Thumbnail maker (portrait crop) -----------------------------------------
make_thumb () {
  local src="$1" dst="$2"
  if command -v magick >/dev/null 2>&1; then
    magick convert -strip "$src" -thumbnail "${ICON_W}x${ICON_H}^" \
      -gravity center -extent "${ICON_W}x${ICON_H}" "$dst"
  else
    convert -strip "$src" -thumbnail "${ICON_W}x${ICON_H}^" \
      -gravity center -extent "${ICON_W}x${ICON_H}" "$dst"
  fi
}

# Build thumbs (newest first)
while IFS= read -r -d '' img; do
  bn="$(basename "$img")"
  thumb="$CACHE_DIR/$bn"
  [[ -f "$thumb" ]] || make_thumb "$img" "$thumb"
done < <(find "$WALL_DIR" -maxdepth 1 -type f \
          \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

# --- Theme file path ---------------------------------------------------------
THEME_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/rofi-wallpaper-sel.rasi"

# --- Rofi launcher -----------------------------------------------------------
SELECTION="$(
  find "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf '%T@|%f\n' \
  | sort -nr | cut -d'|' -f2- \
  | while IFS= read -r bn; do
      printf '%s\x00icon\x1f%s\n' "$bn" "$CACHE_DIR/$bn"
    done \
  | rofi -no-config -dmenu -show-icons \
      -name "rofi-wal" \
      -theme "$THEME_FILE" \
      -theme-str "window { width: ${USABLE}px; } listview { spacing: ${GAP}px; columns: ${COLS}; } element-icon { size: ${ICON_H}px; }"
)"

[[ -n "${SELECTION:-}" ]] || exit 0
CHOSEN="$WALL_DIR/$SELECTION"

# --- swww: set on all outputs -------------------------------------------------
if ! swww query >/dev/null 2>&1; then
  swww init
  sleep 0.15
fi

SWWW_ARGS=( --transition-type any --transition-fps 60 --transition-duration 1.0 --resize crop )

mapfile -t OUTPUTS < <(swww query | awk '/^OUTPUT/ {print $2}')
if ((${#OUTPUTS[@]}==0)); then
  swww img "$CHOSEN" "${SWWW_ARGS[@]}"
else
  for out in "${OUTPUTS[@]}"; do
    swww img -o "$out" "$CHOSEN" "${SWWW_ARGS[@]}"
  done
fi
