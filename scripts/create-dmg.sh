#!/bin/bash
set -euo pipefail

# Create DMG script for ClaudeTakip
# This script creates a distributable DMG file with proper background and layout

APP_NAME="ClaudeTakip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/dmg"
BACKGROUND_FILE="${PROJECT_DIR}/dmg-background.png"
APP_SOURCE="${1:-.}"

# Check if app exists
if [ ! -d "$APP_SOURCE/$APP_NAME.app" ]; then
    echo "Error: $APP_NAME.app not found at $APP_SOURCE/$APP_NAME.app"
    echo "Usage: $0 [path-to-built-app-directory]"
    exit 1
fi

echo "==> Creating DMG for $APP_NAME"

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/staging"

# Copy app to staging
echo "==> Copying $APP_NAME.app..."
cp -R "$APP_SOURCE/$APP_NAME.app" "$BUILD_DIR/staging/$APP_NAME.app"

# Create symlink to Applications
echo "==> Creating Applications symlink..."
ln -s /Applications "$BUILD_DIR/staging/Applications"

# Copy background image
echo "==> Copying background image..."
cp "$BACKGROUND_FILE" "$BUILD_DIR/staging/.background.png"

# Create DMG using hdiutil
echo "==> Creating disk image..."
DMG_PATH="$PROJECT_DIR/$APP_NAME.dmg"

# Remove existing DMG if present
rm -f "$DMG_PATH"

# Create the DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUILD_DIR/staging" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: Failed to create DMG"
    exit 1
fi

# Get DMG size
DMG_SIZE=$(stat -f%z "$DMG_PATH")
echo "==> DMG created successfully!"
echo ""
echo "File: $DMG_PATH"
echo "Size: $DMG_SIZE bytes"
echo ""
echo "Next steps:"
echo "1. Open and verify the DMG appearance"
echo "2. If satisfied, commit the DMG or upload to releases"
