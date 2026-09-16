#!/bin/bash
# Build the menu bar app. No Xcode project, no dependencies — just swiftc and
# a hand-written bundle. Produces tools/menubar/BrickdupBridge.app
set -euo pipefail
cd "$(dirname "$0")"

APP="BrickdupBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/BrickdupBridge" BrickdupBridge.swift

# App icon: AppIcon.png (square, ideally 1024+) -> .icns with every size macOS
# asks for. Only shows in Finder / Login Items / Activity Monitor; the menu bar
# itself uses the SF Symbol, since a detailed icon is illegible at 16 px.
mkdir -p "$APP/Contents/Resources"
if [ -f AppIcon.png ]; then
  SET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$SET"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz          AppIcon.png --out "$SET/icon_${sz}x${sz}.png"    >/dev/null
    sips -z $((sz*2)) $((sz*2)) AppIcon.png --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

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
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
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
