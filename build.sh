#!/usr/bin/env bash
# Builds ./Trisplit.app (native Swift engine + panel) and signs it.
#
# Signing identity, first match wins:
#   1. TRISPLIT_SIGN_ID (+ optional TRISPLIT_KEYCHAIN)
#   2. "trisplit dev" from the dedicated keychain created by scripts/dev-cert.sh
#   3. ad-hoc (Accessibility permission resets on every rebuild)
set -euo pipefail
cd "$(dirname "$0")"

APP=Trisplit.app
BIN=Trisplit
DEV_DIR="$HOME/Library/Application Support/trisplit-dev"
DEV_KC="$DEV_DIR/trisplit-dev.keychain-db"
DEV_PW="$DEV_DIR/keychain-password"

shopt -s nullglob
SRCS=(app/main.swift app/Core/*.swift app/Engine/*.swift app/Shell/*.swift)
shopt -u nullglob

for f in panel.html icon.png; do
    [ -f "$f" ] || { echo "error: missing $f" >&2; exit 1; }
done

# Compile outside the bundle so a failed build keeps the previous app intact.
mkdir -p build
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 \
    -framework AppKit -framework WebKit -framework Carbon \
    -framework ApplicationServices -framework ServiceManagement \
    "${SRCS[@]}" -o "build/$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "build/$BIN" "$APP/Contents/MacOS/$BIN"
cp -X panel.html icon.png "$APP/Contents/Resources/"

cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.dibanez.trisplit</string>
  <key>CFBundleName</key><string>Trisplit</string>
  <key>CFBundleDisplayName</key><string>Trisplit</string>
  <key>CFBundleExecutable</key><string>Trisplit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.dibanez.trisplit.url</string>
      <key>CFBundleURLSchemes</key><array><string>trisplit</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

SIGN=()
if [ -n "${TRISPLIT_SIGN_ID:-}" ]; then
    SIGN=(-s "$TRISPLIT_SIGN_ID")
    if [ -n "${TRISPLIT_KEYCHAIN:-}" ]; then SIGN+=(--keychain "$TRISPLIT_KEYCHAIN"); fi
elif [ -f "$DEV_KC" ] && [ -f "$DEV_PW" ]; then
    security unlock-keychain -p "$(cat "$DEV_PW")" "$DEV_KC"
    SHA="$(security find-identity -p codesigning "$DEV_KC" \
        | awk 'index($0, "\"trisplit dev\"") { print $2; exit }')"
    if [ -n "$SHA" ]; then SIGN=(--keychain "$DEV_KC" -s "$SHA"); fi
fi
if [ ${#SIGN[@]} -eq 0 ]; then
    echo "WARNING: no signing identity; signing ad-hoc." >&2
    echo "WARNING: macOS will RESET the Accessibility permission on every rebuild." >&2
    echo "WARNING: run 'make cert' (scripts/dev-cert.sh) once to get a stable identity." >&2
    SIGN=(-s -)
fi

# ~/Documents may be File Provider managed and tags files with xattrs, which
# `codesign --verify --strict` rejects as "detritus".
xattr -cr "$APP"
codesign --force --options runtime --timestamp=none "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature)=' || true
echo "built: $PWD/$APP"
