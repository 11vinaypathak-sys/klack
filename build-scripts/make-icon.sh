#!/bin/bash
# Regenerates the app icon from source and installs it into Klack.app.
#
# The icon is drawn in code (Sources/IconGen), not stored as a hand-made
# image, so it can be re-rendered at any size without a design tool and
# without the original file drifting away from what ships.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ICONSET="$ROOT/AppIcon/Klack.iconset"

echo "==> Rendering 1024px master"
swift build -c release --product IconGen >/dev/null
./.build/release/IconGen "$ROOT/AppIcon/icon_1024.png"

echo "==> Generating iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# macOS expects both @1x and @2x for each logical size; a missing entry makes
# the Dock fall back to a blurry upscale of whatever is closest.
for spec in "16 icon_16x16" "32 icon_16x16@2x" \
            "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" \
            "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$ROOT/AppIcon/icon_1024.png" --out "$ICONSET/$2.png" >/dev/null
done

echo "==> Building .icns"
iconutil -c icns "$ICONSET" -o "$ROOT/AppIcon/Klack.icns"
cp "$ROOT/AppIcon/Klack.icns" "$ROOT/Klack.app/Contents/Resources/Klack.icns"

echo "==> Refreshing icon cache"
# macOS aggressively caches bundle icons; without bumping the bundle's mtime
# the Dock and Finder keep showing the previous artwork indefinitely.
touch "$ROOT/Klack.app"

echo "Done. Icon installed."
