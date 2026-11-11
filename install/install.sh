#!/usr/bin/env bash
# Build Mac Janitor.app and open it; its setup window grants access and turns on
# automatic cleaning. Re-runnable.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
"$HERE/build-app.sh"
open "$ROOT/build/Mac Janitor.app"
