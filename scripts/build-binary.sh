#!/bin/bash
# Builds the MS Edit Rust binary and copies it into the app bundle's Resources.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPTS_DIR")"
RESOURCES_DIR="$SCRIPTS_DIR/../EditApp/Resources"

echo "Building MS Edit binary..."
cd "$REPO_ROOT"
cargo build --release

cp target/release/edit "$RESOURCES_DIR/edit"
chmod +x "$RESOURCES_DIR/edit"
echo "Binary copied to EditApp/Resources/edit"
