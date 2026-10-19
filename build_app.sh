#!/bin/bash
# Builds "build/Wake Up Time.app" from the Swift package.
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary (Apple Silicon + Intel)
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/WakeUpTime"
APP="build/Wake Up Time.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WakeUpTime"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swift Scripts/make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built: $APP"

# Zip for distribution (GitHub Releases)
rm -f "build/Wake Up Time.zip"
ditto -c -k --keepParent "$APP" "build/Wake Up Time.zip"
echo "Packaged: build/Wake Up Time.zip"
