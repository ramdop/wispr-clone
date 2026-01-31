#!/bin/bash
set -e

# Define paths
APP_NAME="WisprClone"
PROJECT_ROOT="$PWD"
BUILD_SCRIPT="$PROJECT_ROOT/scripts/build_app.sh"
RELEASE_DIR="$PROJECT_ROOT/Release"
ZIP_NAME="WisprClone_Release.zip"

# 1. Run the existing build script
echo "🛠️  Running Build Script..."
if [ -f "$BUILD_SCRIPT" ]; then
    bash "$BUILD_SCRIPT"
else
    echo "❌ Build script not found at $BUILD_SCRIPT"
    exit 1
fi

# 2. Prepare Release Directory
echo "📦 Packaging for Release..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 3. Copy App to Release Folder
cp -R "$PROJECT_ROOT/$APP_NAME.app" "$RELEASE_DIR/"

# 4. Create Zip (Best for distribution)
cd "$RELEASE_DIR"
zip -r -y "$ZIP_NAME" "$APP_NAME.app" > /dev/null

echo ""
echo "✅ Release Package Created!"
echo "📂 Location: $RELEASE_DIR/$ZIP_NAME"
echo ""
echo "🚀 HOW TO INSTALL ON ANOTHER MAC:"
echo "1. Copy '$ZIP_NAME' to the other Mac (AirDrop, iCloud, USB)."
echo "2. Unzip it."
echo "3. Drag '$APP_NAME.app' to the 'Applications' folder."
echo "4. Right-click > Open (to bypass Gatekeeper check)."
echo "   OR if that fails, run this in Terminal:"
echo "   xattr -cr /Applications/$APP_NAME.app"
echo ""
