#!/bin/bash
# Creates AppIcon.icns from a 1024x1024 source PNG.
#
# Usage:
#   bash scripts/create-icon.sh path/to/icon-1024.png
#
# Output: EditApp/Resources/AppIcon.icns
# This file is picked up by bundle-app.sh and referenced via CFBundleIconFile
# in Sources/Info.plist.
#
# Requirements: macOS (uses sips + iconutil, both pre-installed).
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: bash scripts/create-icon.sh <source-1024x1024.png>"
    exit 1
fi

SOURCE="$1"

if [ ! -f "$SOURCE" ]; then
    echo "Error: file not found: $SOURCE"
    exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPTS_DIR")"
RESOURCES="$REPO_ROOT/EditApp/Resources"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

echo "Generating icon sizes from $SOURCE..."

sips -z 16   16   "$SOURCE" --out "$ICONSET/icon_16x16.png"       > /dev/null
sips -z 32   32   "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"    > /dev/null
sips -z 32   32   "$SOURCE" --out "$ICONSET/icon_32x32.png"       > /dev/null
sips -z 64   64   "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"    > /dev/null
sips -z 128  128  "$SOURCE" --out "$ICONSET/icon_128x128.png"     > /dev/null
sips -z 256  256  "$SOURCE" --out "$ICONSET/icon_128x128@2x.png"  > /dev/null
sips -z 256  256  "$SOURCE" --out "$ICONSET/icon_256x256.png"     > /dev/null
sips -z 512  512  "$SOURCE" --out "$ICONSET/icon_256x256@2x.png"  > /dev/null
sips -z 512  512  "$SOURCE" --out "$ICONSET/icon_512x512.png"     > /dev/null
sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png"  > /dev/null

iconutil -c icns "$ICONSET" --output "$RESOURCES/AppIcon.icns"

echo "Done: $RESOURCES/AppIcon.icns"
echo "Run bundle-app.sh to rebuild the .app with the new icon."
