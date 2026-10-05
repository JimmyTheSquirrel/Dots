#!/usr/bin/env bash
# Push this repo's Bingie skin overlay to Eclipse and restart Kodi.
#
# WHY THIS EXISTS. Eclipse is LibreELEC on an SD card, not a NixOS host, and the
# Bingie skin lives inside /storage/.kodi/addons/skin.bingie -- a directory the
# skin's own updater REPLACES WHOLESALE. Two layout changes her setup depends on
# are edits to files in there, so a skin update silently reverts them:
#
#   1080i/IncludesBingie.xml          the spotlight/details panel height
#                                     600px (55.6% of screen) -> 276px (26%)
#   1080i/View_526_BingieMainPoster.xml
#                                     the poster grid: moved up to meet the
#                                     smaller panel, and the tile grown from
#                                     131x186 (12 per row) to 279x396 (6 per row)
#
# The geometry closes exactly, which is why these numbers and not round ones:
#   panel 276 + container top 6 + grid 798          = 1080   (screen height)
#   grid width 1674 / tile width 279                = 6      (columns, exact)
#   grid height 798 / tile height 396               = 2.01   (two FULL rows)
#   tile aspect 279/396 = 0.7045 vs stock 131/186   = 0.7043 (no distortion)
#
# View_526 is the forced view for movies, TV shows AND sets, and the panel
# include is shared with View_523/View_528, so these two files cover everything.
#
# AFTER A BINGIE UPDATE: re-run this. Nothing else restores the layout.
# A card image restores the whole box but is not a way to recover a font size.
#
# Usage:  ./eclipse-skin-push.sh [--dry-run]
#         ECLIPSE_HOST=root@eclipse ./eclipse-skin-push.sh

set -euo pipefail

ECLIPSE="${ECLIPSE_HOST:-root@100.80.62.3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/storage/.kodi/addons/skin.bingie"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY=1

FILES=(
  "1080i/IncludesBingie.xml"
  "1080i/View_526_BingieMainPoster.xml"
)

say() { printf '  %s\n' "$*"; }

printf '\nEclipse skin overlay -> %s\n\n' "$ECLIPSE"

# Refuse to push into a skin that is not the one these edits were made against.
# A major Bingie version may have restructured these files entirely, in which
# case the edits must be REDONE by hand, not pasted over the top.
EXPECT_VERSION="2.0.2"
live_version="$(ssh -o BatchMode=yes "$ECLIPSE" \
  "sed -n 's/.*<addon id=\"skin.bingie\".*version=\"\([^\"]*\)\".*/\1/p' $DEST/addon.xml" 2>/dev/null || true)"
if [ -z "$live_version" ]; then
  say "ERROR: cannot read $DEST/addon.xml -- is the skin installed?"
  exit 1
fi
if [ "$live_version" != "$EXPECT_VERSION" ]; then
  say "REFUSING: skin.bingie on Eclipse is $live_version, these edits were made"
  say "against $EXPECT_VERSION. Diff the new upstream files against this repo's"
  say "copies and re-apply the geometry by hand before pushing."
  exit 1
fi
say "skin.bingie $live_version on the box matches this overlay"

for f in "${FILES[@]}"; do
  [ -f "$HERE/bingie/$f" ] || { say "ERROR: missing in repo: bingie/$f"; exit 1; }
done

# Validate before pushing. Kodi is forgiving about some malformed skin XML and
# simply renders nothing where the broken control was, which looks like a layout
# bug rather than a parse error and wastes a whole debug cycle. A real trap hit
# while writing this overlay: an XML comment may not contain a double hyphen, so
# writing "--action" inside a <!-- --> comment silently produces invalid XML.
if command -v xmllint >/dev/null 2>&1; then
  for f in "${FILES[@]}"; do
    xmllint --noout "$HERE/bingie/$f" || { say "ERROR: $f is not well-formed XML, refusing to push"; exit 1; }
  done
  say "XML well-formed"
else
  say "WARNING: xmllint not found, pushing unvalidated"
fi

if [ -n "$DRY" ]; then
  printf '\n  --dry-run, would push:\n'
  for f in "${FILES[@]}"; do say "  bingie/$f -> $DEST/$f"; done
  exit 0
fi

# Kodi reads these at skin load, so stop it first -- editing under a running
# Kodi gets you a half-applied layout and a confusing first look.
say "stopping kodi"
ssh -o BatchMode=yes "$ECLIPSE" "systemctl stop kodi" >/dev/null
sleep 3

for f in "${FILES[@]}"; do
  ssh -o BatchMode=yes "$ECLIPSE" "cp -a '$DEST/$f' '/storage/skin-overlay-backup-$STAMP-$(basename "$f")'" >/dev/null
  scp -q -o BatchMode=yes "$HERE/bingie/$f" "$ECLIPSE:$DEST/$f"
  say "pushed $f"
done

say "starting kodi"
ssh -o BatchMode=yes "$ECLIPSE" "systemctl start kodi" >/dev/null
sleep 6
state="$(ssh -o BatchMode=yes "$ECLIPSE" "systemctl is-active kodi" 2>/dev/null || true)"
say "kodi: $state"

printf '\n  backups on the box: /storage/skin-overlay-backup-%s-*\n' "$STAMP"
printf '  check the TV: movies, TV shows and sets should all show 6 posters per row\n\n'
