#!/bin/bash
set -euo pipefail

# ClaudeTakip Release Script
# Usage: ./scripts/release.sh 1.1.0
#
# What it does:
#   1. Updates version in project.yml
#   2. Builds Release configuration
#   3. Creates signed .zip for Sparkle
#   4. Updates appcast.xml with new entry
#   5. Outputs what to do next (git tag, GitHub release)

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.1.0"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="ClaudeTakip"
SCHEME="ClaudeTakip"
BUILD_DIR="$PROJECT_DIR/build/release"
GITHUB_REPO="BatuhanAkpunar/ClaudeTakip"
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$APP_NAME.zip"

# Sparkle tools (from DerivedData)
SPARKLE_TOOLS=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/sparkle/Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)
if [ -z "$SPARKLE_TOOLS" ]; then
    echo "Error: Sparkle sign_update tool not found. Build the project first."
    exit 1
fi
SIGN_UPDATE="$SPARKLE_TOOLS"

echo "==> Releasing $APP_NAME v$VERSION"

# 1. Update version in project.yml
echo "==> Updating version to $VERSION"
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml

# Increment build number
CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION:" project.yml | sed 's/.*: //')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: $NEW_BUILD/" project.yml

echo "    Version: $VERSION (build $NEW_BUILD)"

# 2. Regenerate Xcode project
echo "==> Generating Xcode project"
xcodegen generate

# 3. Build Release
echo "==> Building Release configuration"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    clean build \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    2>&1 | tail -5

if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
    echo "Error: Build failed — $APP_NAME.app not found"
    exit 1
fi

echo "==> Build succeeded"

# 4. Create zip
echo "==> Creating zip"
cd "$BUILD_DIR"
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
cd "$PROJECT_DIR"

# 5. Sign the zip with Sparkle EdDSA
echo "==> Signing with Sparkle EdDSA"
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1 | grep 'sparkle:edSignature=' | sed 's/.*sparkle:edSignature="//' | sed 's/".*//')

if [ -z "$SIGNATURE" ]; then
    # Fallback: try getting full output
    SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1)
    echo "    sign_update output: $SIGN_OUTPUT"
    SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'edSignature="[^"]*"' | sed 's/edSignature="//' | sed 's/"//')
fi

if [ -z "$SIGNATURE" ]; then
    echo "Warning: Could not extract EdDSA signature. You may need to add it manually."
    SIGNATURE="SIGNATURE_PLACEHOLDER"
fi

echo "    Signature: ${SIGNATURE:0:20}..."

# 6. Update appcast.xml
echo "==> Updating appcast.xml"
PUBDATE=$(date -R)

# Build new item XML
NEW_ITEM="        <item>
            <title>v$VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$NEW_BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure
                url=\"$DOWNLOAD_URL\"
                length=\"$ZIP_SIZE\"
                type=\"application/octet-stream\"
                sparkle:edSignature=\"$SIGNATURE\"
            />
        </item>"

# Insert new item into appcast.xml (after <language>en</language>)
sed -i '' "/<\/language>/a\\
$NEW_ITEM
" appcast.xml

echo "==> Done!"
echo ""
echo "===== NEXT STEPS ====="
echo ""
echo "1. Test the app:"
echo "   open $BUILD_DIR/$APP_NAME.app"
echo ""
echo "2. Commit and tag:"
echo "   git add -A"
echo "   git commit -m \"Release v$VERSION\""
echo "   git tag v$VERSION"
echo "   git push origin main --tags"
echo ""
echo "3. Create GitHub Release:"
echo "   gh release create v$VERSION $ZIP_PATH --title \"v$VERSION\" --notes \"ClaudeTakip v$VERSION\""
echo ""
echo "4. Deploy appcast.xml to Vercel (push to main triggers this)"
echo ""
echo "Zip: $ZIP_PATH"
echo "Size: $ZIP_SIZE bytes"
