#!/usr/bin/env bash
# Build a universal Mac Janitor.app, sign it with a Developer ID Application identity (hardened
# runtime, secure timestamp), notarize and staple it, wrap it in a DMG that is signed, notarized
# and stapled too, and write release/MacJanitor-<version>.dmg plus release/MacJanitor.dmg.
#
# Identity: MACJANITOR_SIGN_IDENTITY, or the first "Developer ID Application" in the keychain.
# Notarization credentials, one of:
#   MACJANITOR_NOTARY_PROFILE                      a `notarytool store-credentials` profile
#                                                  (MACJANITOR_NOTARY_KEYCHAIN if not in login)
#   MACJANITOR_NOTARY_KEY, _KEY_ID, _ISSUER        an App Store Connect API key (.p8 path)
# --adhoc: no Developer ID, no notarization; a DMG that other Macs open only via Open Anyway.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
APP="build/Mac Janitor.app"
OUT="release"
VERSIONED_DMG="$OUT/MacJanitor-$VERSION.dmg"
STABLE_DMG="$OUT/MacJanitor.dmg"
ADHOC=false

step() { printf '\n> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --adhoc) ADHOC=true ;;
      *) fail "unknown argument $arg (only --adhoc)" ;;
    esac
  done
}

pick_identity() {
  if $ADHOC; then
    IDENTITY="-"
    return
  fi
  IDENTITY="${MACJANITOR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
  [ -n "$IDENTITY" ] || fail "no Developer ID Application identity in the keychain (or pass --adhoc)"
}

notary_auth() {
  if [ -n "${MACJANITOR_NOTARY_PROFILE:-}" ]; then
    NOTARY_AUTH=(--keychain-profile "$MACJANITOR_NOTARY_PROFILE")
    if [ -n "${MACJANITOR_NOTARY_KEYCHAIN:-}" ]; then
      NOTARY_AUTH+=(--keychain "$MACJANITOR_NOTARY_KEYCHAIN")
    fi
  elif [ -n "${MACJANITOR_NOTARY_KEY:-}" ]; then
    NOTARY_AUTH=(--key "$MACJANITOR_NOTARY_KEY" --key-id "$MACJANITOR_NOTARY_KEY_ID" --issuer "$MACJANITOR_NOTARY_ISSUER")
  else
    fail "set MACJANITOR_NOTARY_PROFILE or MACJANITOR_NOTARY_KEY, _KEY_ID and _ISSUER (or pass --adhoc)"
  fi
}

build_app() {
  step "Building $APP $VERSION (arm64 + x86_64)"
  MACJANITOR_ARCHS="arm64 x86_64" MACJANITOR_SIGN_IDENTITY="-" ./install/build-app.sh
  [ "$(lipo -archs "$APP/Contents/MacOS/MacJanitor")" = "x86_64 arm64" ] || fail "the executable is not universal"
}

sign() {
  if $ADHOC; then
    codesign --force --options runtime --sign - "$@"
  else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"
  fi
}

sign_app() {
  step "Signing with $IDENTITY (hardened runtime)"
  sign "$APP/Contents/MacOS/MacJanitor"
  sign "$APP"
  codesign --verify --deep --strict -vv "$APP"
}

notarize() {
  step "Notarizing $1"
  xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait --timeout 1h | tee "$WORK/notary.log"
  grep -q "status: Accepted" "$WORK/notary.log" || fail "notarization of $1 was not accepted"
}

notarize_app() {
  ditto -c -k --keepParent "$APP" "$WORK/MacJanitor.zip"
  notarize "$WORK/MacJanitor.zip"
  xcrun stapler staple "$APP"
}

make_dmg() {
  step "Making $VERSIONED_DMG"
  ./scripts/make-dmg.sh "$APP" "$VERSIONED_DMG"
  if ! $ADHOC; then
    sign "$VERSIONED_DMG"
  fi
}

notarize_dmg() {
  notarize "$VERSIONED_DMG"
  xcrun stapler staple "$VERSIONED_DMG"
}

check_gatekeeper() {
  step "Checking with stapler and spctl"
  xcrun stapler validate "$APP"
  xcrun stapler validate "$VERSIONED_DMG"
  spctl -a -vv -t exec "$APP"
  spctl -a -vv -t open --context context:primary-signature "$VERSIONED_DMG"
}

finish() {
  cp "$VERSIONED_DMG" "$STABLE_DMG"
  step "Done"
  shasum -a 256 "$VERSIONED_DMG" "$STABLE_DMG"
  if $ADHOC; then
    echo "Ad-hoc signed, not notarized: other Macs need right-click > Open or Open Anyway."
  fi
}

parse_args "$@"
pick_identity
$ADHOC || notary_auth
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

build_app
sign_app
$ADHOC || notarize_app
make_dmg
$ADHOC || notarize_dmg
$ADHOC || check_gatekeeper
finish
