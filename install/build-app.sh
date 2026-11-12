#!/usr/bin/env bash
# Build a menu-bar-only "Mac Janitor.app" (LSUIElement, no Dock icon) in build/.
# The bundle carries the LaunchAgent that runs its own executable headless
# (Contents/Library/LaunchAgents), registered from the app's setup.
# Usage: ./install/build-app.sh     then: open "build/Mac Janitor.app"
# MACJANITOR_ARCHS="arm64 x86_64" builds a universal binary.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="${MACJANITOR_BUNDLE_ID:-com.blazejkustra.macjanitor}"
APP="build/Mac Janitor.app"
VERSION="$(cat VERSION)"
SPARKLE_FEED="https://github.com/blazejkustra/Mac-Janitor/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="roWmokCEW+JHPVgFVc4jzZanyKzDLRE45efZn/iLhF8="
ARCH_FLAGS=""
for arch in ${MACJANITOR_ARCHS:-}; do ARCH_FLAGS="$ARCH_FLAGS --arch $arch"; done

# swiftc hands the SDK to the linking clang as --sysroot, which clang does not read the SDK
# version from, so the binary records the deployment target as its SDK and AppKit falls back
# to the pre-Tahoe look. -isysroot records the real SDK.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_FLAGS="$ARCH_FLAGS -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc $SDK"

echo "Building release $VERSION${MACJANITOR_ARCHS:+ for $MACJANITOR_ARCHS}..."
swift build -c release $BUILD_FLAGS --product MacJanitor
BIN_DIR="$(swift build -c release $BUILD_FLAGS --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MacJanitor" "$APP/Contents/MacOS/MacJanitor"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
# The XPC services are only for sandboxed apps.
rm -rf "$SPARKLE/XPCServices" "$SPARKLE/Versions/B/XPCServices"
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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>SUFeedURL</key><string>$SPARKLE_FEED</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
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
for part in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
  codesign --force --sign "$IDENTITY" "$part"
done
echo "Signed with: $IDENTITY"
echo "Built $ROOT/$APP"
