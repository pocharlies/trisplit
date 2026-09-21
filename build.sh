#!/bin/sh
# Compila TrisplitPanel.app (AppKit nativo) en ./TrisplitPanel.app
set -e
cd "$(dirname "$0")"
APP=TrisplitPanel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TrisplitPanel</string>
  <key>CFBundleIdentifier</key><string>com.dibanez.trisplitpanel</string>
  <key>CFBundleName</key><string>TrisplitPanel</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
swiftc -O app/main.swift -o "$APP/Contents/MacOS/TrisplitPanel" -framework Cocoa -framework WebKit
echo "built: $PWD/$APP"
