#!/usr/bin/env bash
# Remove the LaunchAgent older developer installs wrote. Turn off "Clean automatically"
# in the app's settings before deleting the app, so macOS drops its background job.
# Logs, last-run.json and salvaged work in ~/Library/Application Support/MacJanitor are kept.
set -euo pipefail
LABEL="com.ignacy.mac-janitor"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Removed $LABEL if it was there."
