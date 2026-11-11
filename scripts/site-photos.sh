#!/usr/bin/env bash
# Builds the site's hero photos from the Unsplash originals (see site/assets/photos/README.md).
# Usage: scripts/site-photos.sh <folder with the originals, named mist.jpg, glacier.jpg and so on>
set -euo pipefail
SRC="${1:?folder with the original photos}"
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

for photo in mist glacier aurora ridge moss river coast; do
  wide "$photo"
  tall "$photo"
done

ffmpeg -v error -y -i "$OUT/mist-2560.jpg" -i "$ROOT/site/assets/panel-dark.png" -filter_complex "
  [0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,eq=brightness=-0.18:saturation=0.85[bg];
  [1:v]scale=-2:820[panel];[bg][panel]overlay=(W-w)/2:(H-h)/2" -q:v 4 "$ROOT/site/assets/demo-poster.jpg"
