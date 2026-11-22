#!/usr/bin/env bash
# Build Mac Janitor.app and open it; its setup window grants access and turns on
# automatic cleaning. Re-runnable.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
"$HERE/build-app.sh"
open "$ROOT/build/Mac Janitor.app"

SKILL_DIR="$HOME/.claude/skills/mac-janitor"
if [ -t 0 ]; then
  read -r -p "Install the Claude Code skill to $SKILL_DIR? [y/N] " answer
  if [[ "$answer" == [yY]* ]]; then
    mkdir -p "$SKILL_DIR"
    cp "$ROOT/skill/mac-janitor/SKILL.md" "$SKILL_DIR/SKILL.md"
    echo "Installed $SKILL_DIR/SKILL.md"
  fi
fi
