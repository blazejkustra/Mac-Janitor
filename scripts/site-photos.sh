#!/usr/bin/env bash
# Builds the site's hero photos, demo poster and social card from the originals (see site/assets/photos/README.md).
# Usage: scripts/site-photos.sh <folder with the originals, named glacier.jpg and ice.png>
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

original() {
  ls "$SRC/$1".* | head -n 1
}

wide() {
  encode "$(original "$1")" "$1-$2" "crop=iw:min(ih\,iw*10/16),scale=$2:-2:flags=lanczos"
}

tall() {
  encode "$(original "$1")" "$1-$2" "crop=min(iw\,ih*2/3):ih,scale=$2:-2:flags=lanczos"
}

wide glacier 2560
tall glacier 1080
wide ice 1672
tall ice 720

ffmpeg -v error -y -i "$OUT/glacier-2560.jpg" -i "$ROOT/site/assets/panel-dark.png" -filter_complex "
  [0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,eq=brightness=-0.18:saturation=0.85[bg];
  [1:v]scale=-2:820[panel];[bg][panel]overlay=(W-w)/2:(H-h)/2" -q:v 4 "$ROOT/site/assets/demo-poster.jpg"

og="$(mktemp -t site-og).png"
"$CHROME" --headless=new --hide-scrollbars --window-size=1200,630 --virtual-time-budget=5000 \
  --screenshot="$og" "file://$ROOT/scripts/og.html" 2>/dev/null
ffmpeg -v error -y -i "$og" -q:v 3 "$ROOT/site/assets/og.jpg"
rm "$og"
