#!/usr/bin/env bash
# Builds the site's panel preview and the demo poster from the app's own snapshot render.
# Usage: scripts/site-panel.sh
set -euo pipefail
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/site/assets"
WORK="$(mktemp -d -t site-panel)"
trap 'rm -rf "$WORK"' EXIT

swift build -c release --product MacJanitor --package-path "$ROOT"
"$ROOT/.build/release/MacJanitor" --snapshot "$WORK/snap" >/dev/null

"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=3 --window-size=440,620 \
  --default-background-color=00000000 --virtual-time-budget=3000 --allow-file-access-from-files \
  --screenshot="$WORK/panel-3x.png" "file://$ROOT/scripts/panel.html?panel=file://$WORK/snap/site-panel.png" 2>/dev/null

ffmpeg -v error -y -i "$WORK/panel-3x.png" -vf scale=880:-1:flags=lanczos "$WORK/panel-2x.png"
for scale in 2x 3x; do
  cwebp -quiet -q 88 -alpha_q 100 "$WORK/panel-$scale.png" -o "$ASSETS/panel-$scale.webp"
done
cp "$WORK/panel-2x.png" "$ASSETS/panel-2x.png"

ffmpeg -v error -y -i "$ASSETS/photos/glacier-2560.jpg" -i "$WORK/panel-3x.png" -filter_complex "
  [0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,eq=brightness=-0.18:saturation=0.85[bg];
  [1:v]scale=-2:1060:flags=lanczos[panel];[bg][panel]overlay=(W-w)/2:0" -q:v 4 "$ASSETS/demo-poster.jpg"
