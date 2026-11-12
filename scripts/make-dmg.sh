#!/usr/bin/env bash
# Wrap an app in the installer DMG laid out by install/dmg (background, icon positions, volume icon).
# Usage: scripts/make-dmg.sh "build/Mac Janitor.app" release/MacJanitor-<version>.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMGBUILD_VERSION="1.6.7"

[ $# -eq 2 ] || { echo "usage: $0 <app> <out.dmg>" >&2; exit 1; }
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$2"

VENV="$(mktemp -d)"
trap 'rm -rf "$VENV"' EXIT
python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
"$VENV/bin/dmgbuild" -s "$ROOT/install/dmg/settings.py" \
  -D app="$APP" -D icon="$ROOT/assets/AppIcon.icns" -D dmg_dir="$ROOT/install/dmg" \
  "Mac Janitor" "$OUT"
