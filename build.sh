#!/bin/bash
# Builds MacDirStat with SwiftPM and assembles dist/MacDirStat.app (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/MacDirStat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacDirStat "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Icon: Support/new-icon.png is the source of truth when present (scaled 1:1 to
# every required size). Falls back to the procedural generator otherwise.
if [ ! -f Support/AppIcon.icns ]; then
  ICONSET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$ICONSET"
  if [ -f Support/new-icon.png ]; then
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" \
                "512:icon_512x512" "1024:icon_512x512@2x"; do
      px="${spec%%:*}"; name="${spec##*:}"
      sips -s format png -z "$px" "$px" Support/new-icon.png --out "$ICONSET/$name.png" > /dev/null
    done
  else
    swift Support/genicon.swift "$ICONSET"
  fi
  iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/"

# Sign with a stable self-signed identity so Full Disk Access grants persist
# (ad-hoc signatures are not honored by TCC at runtime — see signing-identity.sh).
# Falls back to ad-hoc if the identity can't be created, so builds never break.
if IDENTITY=$(Support/signing-identity.sh 2>/dev/null) && [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier com.tyler.MacDirStat "$APP"
  echo "Built $APP (signed: $IDENTITY)"
else
  echo "warning: no signing identity; falling back to ad-hoc (FDA won't persist)" >&2
  codesign --force --sign - --identifier com.tyler.MacDirStat "$APP"
  echo "Built $APP (ad-hoc)"
fi
