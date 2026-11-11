#!/usr/bin/env bash
# Build a menu-bar-only "Mac Janitor.app" (LSUIElement, no Dock icon) in build/.
# The bundle carries the LaunchAgent that runs its own executable headless
# (Contents/Library/LaunchAgents), registered from the app's setup.
# Usage: ./install/build-app.sh     then: open "build/Mac Janitor.app"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="${MACJANITOR_BUNDLE_ID:-com.blazejkustra.macjanitor}"
APP="build/Mac Janitor.app"

echo "Building release..."
swift build -c release --product MacJanitor
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN_DIR/MacJanitor" "$APP/Contents/MacOS/MacJanitor"
cp assets/MenuBarIcon.pdf "$APP/Contents/Resources/MenuBarIcon.pdf"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/Logo.pdf "$APP/Contents/Resources/Logo.pdf"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mac Janitor</string>
  <key>CFBundleDisplayName</key><string>Mac Janitor</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>MacJanitor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Hourly wake; the run itself decides from config.json (intervalHours, lowDiskGB,
# paused) whether to clean. Wakes missed during sleep coalesce.
cat > "$APP/Contents/Library/LaunchAgents/$BUNDLE_ID.agent.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID.agent</string>
  <key>BundleProgram</key><string>Contents/MacOS/MacJanitor</string>
  <key>ProgramArguments</key>
  <array><string>MacJanitor</string><string>run</string><string>--scheduled</string></array>
  <key>AssociatedBundleIdentifiers</key><array><string>$BUNDLE_ID</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST

# macOS remembers Full Disk Access by code identity. Ad-hoc code is identified by its
# hash, which every rebuild changes; a certificate identity stays the same.
# MACJANITOR_SIGN_IDENTITY picks one, "-" is ad hoc.
IDENTITY="${MACJANITOR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')}"
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  echo "warning: signing ad hoc; macOS will forget Full Disk Access after every rebuild" >&2
  IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "Signed with: $IDENTITY"
echo "Built $ROOT/$APP"
