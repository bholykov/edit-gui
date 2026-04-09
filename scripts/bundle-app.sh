#!/bin/bash
# Assembles EditApp.app from the SPM release build.
# Run from the repo root: bash scripts/bundle-app.sh
#
# Prerequisites:
#   swift build -c release                   (builds EditApp)
#   bash scripts/build-binary.sh             (builds and copies the edit binary)
#   — OR — copy edit binary to EditApp/Resources/edit manually.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPTS_DIR")"
EDITAPP="$REPO_ROOT/EditApp"

APP="$REPO_ROOT/EditApp.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building release..."
cd "$EDITAPP"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$EDITAPP/.build/release/EditApp" "$MACOS/EditApp"
cp "$EDITAPP/Sources/Info.plist"     "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Copy the MS Edit binary into the bundle's Resources directory.
# editBinaryPath() in Swift checks Bundle.main.path(forResource:"edit") first,
# which resolves to Contents/Resources/edit inside a proper .app bundle.
if [ -f "$EDITAPP/Resources/edit" ]; then
    cp "$EDITAPP/Resources/edit" "$RESOURCES/edit"
    chmod +x "$RESOURCES/edit"
elif [ -f "$EDITAPP/.build/release/edit" ]; then
    cp "$EDITAPP/.build/release/edit" "$RESOURCES/edit"
    chmod +x "$RESOURCES/edit"
else
    echo "Warning: edit binary not found."
    echo "Run: bash scripts/build-binary.sh"
    echo "Then re-run this script."
    exit 1
fi

# Ad-hoc code sign — required on Apple Silicon, free (no Developer ID needed).
codesign --force --deep --sign - "$APP"

echo ""
echo "Done: $APP"
echo "Launch with: open $APP"
