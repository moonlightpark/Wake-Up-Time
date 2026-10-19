#!/bin/bash
# Builds "build/Wake Up Time.app" from the Swift package.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WakeUpTime"
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
