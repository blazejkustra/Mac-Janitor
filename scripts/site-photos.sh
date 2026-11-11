#!/usr/bin/env bash
# Builds the site's hero photo and social card from the Unsplash original (see site/assets/photos/README.md).
# Usage: scripts/site-photos.sh <folder with the original, named glacier.jpg>
set -euo pipefail
SRC="${1:?folder with the original photo}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/site/assets/photos"
mkdir -p "$OUT"

encode() {
  local input="$1" name="$2" filter="$3" frame
  frame="$(mktemp -t site-photo).png"
  ffmpeg -v error -y -i "$input" -vf "$filter" "$frame"
  ffmpeg -v error -y -i "$frame" -q:v 5 "$OUT/$name.jpg"
  ffmpeg -v error -y -i "$frame" -vf format=yuv420p -c:v libsvtav1 -crf 36 -frames:v 1 "$OUT/$name.avif" 2>/dev/null
  cwebp -quiet -q 72 "$frame" -o "$OUT/$name.webp"
  rm "$frame"
}

wide() {
  encode "$SRC/$1.jpg" "$1-2560" "crop=iw:min(ih\,iw*10/16),scale=2560:1600:flags=lanczos"
}

tall() {
  encode "$SRC/$1.jpg" "$1-1080" "crop=min(iw\,ih*2/3):ih,scale=1080:1620:flags=lanczos"
}

wide glacier
tall glacier


og="$(mktemp -t site-og).png"
"$CHROME" --headless=new --hide-scrollbars --window-size=1200,630 --virtual-time-budget=5000 \
  --screenshot="$og" "file://$ROOT/scripts/og.html" 2>/dev/null
ffmpeg -v error -y -i "$og" -q:v 3 "$ROOT/site/assets/og.jpg"
rm "$og"
