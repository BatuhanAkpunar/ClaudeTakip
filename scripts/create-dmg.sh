#!/bin/bash
set -euo pipefail

# Create DMG script for ClaudeTakip
# Produces a DMG with a standard layout: app on the left, Applications symlink
# on the right, positioned over the background image.

APP_NAME="ClaudeTakip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build/dmg"
BACKGROUND_FILE="${PROJECT_DIR}/dmg-background.png"
APP_SOURCE="${1:-.}"
VOLUME_NAME="$APP_NAME"
MOUNT_POINT="/Volumes/$VOLUME_NAME"
DMG_PATH="$PROJECT_DIR/$APP_NAME.dmg"

if [ ! -d "$APP_SOURCE/$APP_NAME.app" ]; then
    echo "Error: $APP_NAME.app not found at $APP_SOURCE/$APP_NAME.app"
    echo "Usage: $0 [path-to-built-app-directory]"
    exit 1
fi

echo "==> Creating DMG for $APP_NAME"

# Clean any previous run
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
if [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
fi
rm -f "$DMG_PATH"

# Create a writable sparse image we can arrange, then convert to compressed read-only
SPARSE_BASE="$BUILD_DIR/${APP_NAME}-temp"
SPARSE_IMAGE="${SPARSE_BASE}.sparseimage"
echo "==> Creating sparse image..."
hdiutil create -size 50m -fs HFS+ -volname "$VOLUME_NAME" -type SPARSE -ov "$SPARSE_BASE" >/dev/null

echo "==> Mounting sparse image..."
hdiutil attach "$SPARSE_IMAGE" -noautoopen -noverify -nobrowse >/dev/null

echo "==> Copying $APP_NAME.app..."
cp -R "$APP_SOURCE/$APP_NAME.app" "$MOUNT_POINT/$APP_NAME.app"

echo "==> Creating Applications symlink..."
ln -s /Applications "$MOUNT_POINT/Applications"

echo "==> Copying background image..."
mkdir -p "$MOUNT_POINT/.background"
cp "$BACKGROUND_FILE" "$MOUNT_POINT/.background/background.png"

echo "==> Arranging window via Finder..."
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 532}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync

echo "==> Unmounting sparse image..."
hdiutil detach "$MOUNT_POINT" -quiet

echo "==> Converting to compressed read-only DMG..."
hdiutil convert "$SPARSE_IMAGE" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

echo "==> Cleaning up..."
rm -f "$SPARSE_IMAGE"

DMG_SIZE=$(stat -f%z "$DMG_PATH")
echo ""
echo "==> DMG created successfully!"
echo "File: $DMG_PATH"
echo "Size: $DMG_SIZE bytes"
