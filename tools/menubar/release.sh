#!/bin/bash
# Build, sign, notarize and zip the menu bar app for a GitHub release.
#
#   tools/menubar/release.sh [output-dir]
#
# Needs, once per machine:
#   - a "Developer ID Application" certificate in the keychain
#   - a notarytool keychain profile (credentials never touch this script):
#       xcrun notarytool store-credentials "brickdup-notary" \
#           --apple-id "<apple id>" --team-id "<team id>"
#
# Override with SIGN_ID="Developer ID Application: …" / NOTARY_PROFILE=name.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_ID="${SIGN_ID:-Developer ID Application: Ryan Kunkleman (77F3B9355E)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-brickdup-notary}"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"

./build.sh >/dev/null

# Sign a CLEAN COPY outside the repo. If ~/Documents is synced by iCloud
# Drive, the file provider keeps re-adding com.apple.FinderInfo to the bundle,
# and codesign rejects any bundle carrying it ("detritus not allowed").
APP="$OUT/BrickdupBridge.app"
rm -rf "$APP"
ditto --norsrc --noextattr --noacl BrickdupBridge.app "$APP"
xattr -cr "$APP"

# Hardened runtime + secure timestamp are both required for notarization.
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"

# Notarize: Apple scans the zip, then the ticket is stapled to the app so it
# opens cleanly even offline.
ZIP="$OUT/BrickdupBridge-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip so the download carries the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute -vv "$APP"
echo "release zip: $ZIP"
