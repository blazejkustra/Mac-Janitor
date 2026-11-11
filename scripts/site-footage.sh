#!/usr/bin/env bash
# Cuts the site's background loops from the original footage (see site/assets/footage/README.md).
# Usage: scripts/site-footage.sh <folder with sun.mp4, dandelion.mp4, moon.mp4>
set -euo pipefail
SRC="${1:?folder with the source clips}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/site/assets/footage"
mkdir -p "$OUT"

GRADE="eq=brightness=-0.035:saturation=0.96,vignette=angle=PI/5"

encode() {
  local input="$1" name="$2" width="$3" crf="$4"
  ffmpeg -v error -y -i "$input" -vf "scale=$width:-2:flags=lanczos,format=yuv420p" -an \
    -c:v libx264 -preset slow -crf "$crf" -profile:v high -movflags +faststart "$OUT/$name"
}

poster() {
  local input="$1" name="$2"
  ffmpeg -v error -y -i "$input" -frames:v 1 -vf "scale=1600:-2:flags=lanczos" -q:v 4 "$OUT/$name"
}

# A loop of `length` seconds whose last `fade` seconds dissolve into its first frame.
crossfade_loop() {
  local input="$1" start="$2" length="$3" fade="$4" output="$5"
  ffmpeg -v error -y -ss "$start" -t "$(echo "$length + $fade" | bc)" -i "$input" -filter_complex "
    [0:v]$GRADE,split=3[a][b][c];
    [a]trim=0:$fade,setpts=PTS-STARTPTS[head];
    [b]trim=$length:$(echo "$length + $fade" | bc),setpts=PTS-STARTPTS[tail];
    [c]trim=$fade:$length,setpts=PTS-STARTPTS[body];
    [tail][head]xfade=transition=fade:duration=$fade:offset=0[joint];
    [joint][body]concat=n=2:v=1[v]" -map "[v]" -an -c:v libx264 -crf 12 -preset fast "$output"
}

# The clip forwards then backwards, for subjects that sway (seeds, drifting cloud).
pingpong_loop() {
  local input="$1" output="$2"
  ffmpeg -v error -y -i "$input" -filter_complex "
    [0:v]$GRADE,scale=1600:-2,split[f][r];[r]reverse,trim=start_frame=1,setpts=PTS-STARTPTS[back];
    [f][back]concat=n=2:v=1[v]" -map "[v]" -an -c:v libx264 -crf 12 -preset fast "$output"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

crossfade_loop "$SRC/sun.mp4" 2 11 2 "$TMP/sailboat.mp4"
pingpong_loop "$SRC/dandelion.mp4" "$TMP/dandelion.mp4"
pingpong_loop "$SRC/moon.mp4" "$TMP/moon.mp4"

for name in sailboat dandelion moon; do
  encode "$TMP/$name.mp4" "$name.mp4" 1600 27
  encode "$TMP/$name.mp4" "$name-720.mp4" 720 29
  poster "$TMP/$name.mp4" "$name.jpg"
done

ffmpeg -v error -y -i "$OUT/sailboat.jpg" -i "$ROOT/site/assets/panel-dark.png" -filter_complex "
  [0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,eq=brightness=-0.12[bg];
  [1:v]scale=-2:820[panel];[bg][panel]overlay=(W-w)/2:(H-h)/2" -q:v 4 "$ROOT/site/assets/demo-poster.jpg"

ls -la "$OUT"
