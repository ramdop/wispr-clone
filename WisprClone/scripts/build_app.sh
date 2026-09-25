#!/bin/bash
set -e

# Cleanup extended attributes (exclude .build to avoid permission errors)
xattr -cr Sources || true

APP_NAME="WisprClone"
# Install outside iCloud-synced folders (Desktop/Documents), where macOS can evict files
INSTALLED_APP="/Applications/$APP_NAME.app"
APP_BUNDLE="$PWD/$APP_NAME.app"

echo "🧹 Cleaning up old processes..."
pkill "$APP_NAME" || true
sleep 1

echo "🚀 Building Release Configuration..."
swift build -c release

echo "📦 Creating App Bundle Structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "📋 Copying Binary..."
cp .build/release/WisprClone "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "📝 Copying Info.plist..."
# Use the concrete plist with hardcoded values
cp Sources/Info_Release.plist "$APP_BUNDLE/Contents/Info.plist"

# Verify PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "🎨 Copying App Icon..."
cp Sources/Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "🔏 Signing App Store (Ad-Hoc)..."
# Copy to /tmp to avoid cloud-synced folder xattr issues
TMP_APP="/tmp/$APP_NAME.app"
rm -rf "$TMP_APP"
cp -R "$APP_BUNDLE" "$TMP_APP"
xattr -cr "$TMP_APP"
codesign --force --deep --sign - "$TMP_APP"
# Copy back
rm -rf "$APP_BUNDLE"
cp -R "$TMP_APP" "$APP_BUNDLE"

echo "✅ App Bundle Created at: $APP_BUNDLE"

# Install into /Applications
echo "🔄 Installing to $INSTALLED_APP..."
rm -rf "$INSTALLED_APP"
cp -R "$APP_BUNDLE" "$INSTALLED_APP"

echo "👉 Launching app..."
open "$INSTALLED_APP"
