#!/bin/bash
set -e

SOURCE="icon_source_v2.png"
ICONSET="WisprClone.iconset"
ICNS="Sources/Resources/AppIcon.icns"

if [ ! -f "$SOURCE" ]; then
    echo "❌ Error: Source icon $SOURCE not found."
    exit 1
fi

echo "🎨 Creating iconset directory..."
mkdir -p "$ICONSET"
mkdir -p "Sources/Resources"

echo "📐 Resizing icons..."
sips -z 16 16     "$SOURCE" --out "$ICONSET/icon_16x16.png" -s format png > /dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_16x16@2x.png" -s format png > /dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_32x32.png" -s format png > /dev/null
sips -z 64 64     "$SOURCE" --out "$ICONSET/icon_32x32@2x.png" -s format png > /dev/null
sips -z 128 128   "$SOURCE" --out "$ICONSET/icon_128x128.png" -s format png > /dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_128x128@2x.png" -s format png > /dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_256x256.png" -s format png > /dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_256x256@2x.png" -s format png > /dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_512x512.png" -s format png > /dev/null
sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png" -s format png > /dev/null

echo "🔨 Converting to .icns..."
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "🧹 Cleaning up..."
rm -rf "$ICONSET"
rm "$SOURCE"

echo "✅ AppIcon.icns created at $ICNS"
