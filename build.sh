#!/bin/bash
# Build "HEIC to Resolve.app" from source — no Xcode required, just the Swift
# toolchain that ships with macOS (and the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/HEIC to Resolve.app"

echo "==> Compiling Swift app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -O HEICToResolve.swift -o "$APP/Contents/MacOS/HEICToResolve"

echo "==> Generating app icon"
swift make-icon.swift                # writes /tmp/heic-icon-1024.png
ICONSET="$(mktemp -d)/heic.iconset"
mkdir -p "$ICONSET"
SRC=/tmp/heic-icon-1024.png
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
            512:icon_256x256@2x 512:icon_512x512; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$SRC" --out "$ICONSET/${name}.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -f "$SRC"

echo "==> Writing Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> Code signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Run it:        open \"$APP\""
echo "    Install it:    cp -R \"$APP\" /Applications/"
