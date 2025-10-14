#!/bin/bash
# Build script for EditMac
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building EditMac...${NC}"

# Clean previous build
rm -f EditMacBin
rm -rf EditMac.app

# Step 1: Build Rust static library
echo -e "${BLUE}[1/3] Building Rust library...${NC}"
cd ..
cargo build --lib
cd macos

# Step 2: Compile Swift files
echo -e "${BLUE}[2/3] Compiling Swift files...${NC}"
MACOS_DIR="$(pwd)"
swiftc \
    -o EditMacBin \
    -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
    -target arm64-apple-macos12.0 \
    -framework Cocoa \
    -I ../target/debug \
    -L ../target/debug \
    -ledit \
    "${MACOS_DIR}/EditMac/main.swift" \
    "${MACOS_DIR}/EditMac/AppDelegate.swift" \
    "${MACOS_DIR}/EditMac/EditorViewController.swift" \
    "${MACOS_DIR}/EditMac/EditView.swift"

# Step 3: Create app bundle
echo -e "${BLUE}[3/3] Creating app bundle...${NC}"
mkdir -p EditMac.app/Contents/MacOS
mkdir -p EditMac.app/Contents/Resources

cp EditMacBin EditMac.app/Contents/MacOS/EditMac
cp EditMac/Info.plist EditMac.app/Contents/

echo -e "${GREEN}✓ Build complete!${NC}"
echo -e "${GREEN}App bundle: $(pwd)/EditMac.app${NC}"
echo ""
echo "To run: open EditMac.app"
