#!/bin/zsh
set -e

SCRIPT_DIR="${0:A:h}"
APP_DIR="$SCRIPT_DIR/KMO_LiveWallpaper.app"

echo "🚀 Đang biên dịch KMO_LiveWallpaper (Universal Binary: Apple Silicon M1/M2/M3/M4 + Intel)..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

if [ -f "$SCRIPT_DIR/resources/default_wallpaper.mp4" ]; then
    echo "📦 Đang nhúng video 4K mặc định vào ứng dụng..."
    cp -f "$SCRIPT_DIR/resources/default_wallpaper.mp4" "$APP_DIR/Contents/Resources/default_wallpaper.mp4"
fi

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KMO_LiveWallpaper</string>
    <key>CFBundleIdentifier</key>
    <string>com.kmo.KMO_LiveWallpaper</string>
    <key>CFBundleName</key>
    <string>KMO_LiveWallpaper</string>
    <key>CFBundleDisplayName</key>
    <string>KMO_LiveWallpaper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

swiftc -O -target arm64-apple-macos13.0 "$SCRIPT_DIR/main.swift" -o "/tmp/KMO_LiveWallpaper_arm64"
swiftc -O -target x86_64-apple-macos13.0 "$SCRIPT_DIR/main.swift" -o "/tmp/KMO_LiveWallpaper_x86_64"
lipo -create "/tmp/KMO_LiveWallpaper_arm64" "/tmp/KMO_LiveWallpaper_x86_64" -output "$APP_DIR/Contents/MacOS/KMO_LiveWallpaper"
rm -f "/tmp/KMO_LiveWallpaper_arm64" "/tmp/KMO_LiveWallpaper_x86_64"

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$SCRIPT_DIR/KMO_LiveWallpaper-macOS-Universal.zip"
echo "✅ Đã đóng gói thành công tại: $APP_DIR"
