#!/bin/bash
# Build the menu bar app. No Xcode project, no dependencies — just swiftc and
# a hand-written bundle. Produces tools/menubar/BrickdupBridge.app
set -euo pipefail
cd "$(dirname "$0")"

APP="BrickdupBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/BrickdupBridge" BrickdupBridge.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Brickdup Bridge</string>
  <key>CFBundleDisplayName</key>       <string>Brickdup Bridge</string>
  <key>CFBundleIdentifier</key>        <string>com.brickdup.bridge</string>
  <key>CFBundleExecutable</key>        <string>BrickdupBridge</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.6.2</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <!-- menu bar only: no Dock icon, no app switcher entry -->
  <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST

echo "built $(pwd)/$APP"
echo "run it:   open $APP"
echo "or:       $APP/Contents/MacOS/BrickdupBridge"
