#!/bin/bash
# Builds "AI Notch.app" with the command-line Swift toolchain — no Xcode needed.
# Xcode users can just open SideNotch.xcodeproj and hit Run instead.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/AI Notch.app"
EXEC="AI Notch"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
  -parse-as-library \
  -O -whole-module-optimization \
  -target "${ARCH}-apple-macos14.0" \
  -sdk "$SDK" \
  -module-name SideNotch \
  SideNotch/*.swift \
  -o "$APP/Contents/MacOS/$EXEC"

cp SideNotch/Info.plist "$APP/Contents/Info.plist"
cp SideNotch/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Run it with: open '$APP'   (quit by right-clicking the tab)"
