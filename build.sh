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

# Dọn dẹp metadata & Ký mã (Ad-hoc codesign)
dot_clean "$APP_DIR" 2>/dev/null || true
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

echo "📦 1/3: Đang đóng gói file ZIP Universal..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$SCRIPT_DIR/KMO_LiveWallpaper-macOS-Universal.zip"

echo "💿 2/3: Đang đóng gói file DMG (macOS Disk Image kéo thả)..."
DMG_STAGING="/tmp/kmo_dmg_stage"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$SCRIPT_DIR/KMO_LiveWallpaper.dmg"
hdiutil create -volname "KMO_LiveWallpaper" -srcfolder "$DMG_STAGING" -ov -format UDZO "$SCRIPT_DIR/KMO_LiveWallpaper.dmg" >/dev/null
rm -rf "$DMG_STAGING"

echo "⚙️ 3/3: Đang đóng gói file PKG Cài đặt tự động 1-Click (Apple Installer Package)..."
SCRIPTS_DIR="/tmp/kmo_pkg_scripts"
rm -rf "$SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"
cat << 'EOF' > "$SCRIPTS_DIR/postinstall"
#!/bin/sh
DEST="/Applications/KMO_LiveWallpaper.app"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
chmod -R 755 "$DEST" 2>/dev/null || true
CONSOLE_USER=$(stat -f "%Su" /dev/console)
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
    sudo -u "$CONSOLE_USER" open "$DEST" 2>/dev/null || true
fi
exit 0
EOF
chmod +x "$SCRIPTS_DIR/postinstall"

rm -f "/tmp/KMO_Component.pkg" "$SCRIPT_DIR/KMO_LiveWallpaper-macOS-Installer.pkg"
pkgbuild --component "$APP_DIR" \
         --install-location "/Applications" \
         --scripts "$SCRIPTS_DIR" \
         --identifier "com.kmo.KMO_LiveWallpaper" \
         --version "2.0" \
         "/tmp/KMO_Component.pkg" >/dev/null 2>&1 || true

productbuild --package "/tmp/KMO_Component.pkg" "$SCRIPT_DIR/KMO_LiveWallpaper-macOS-Installer.pkg" >/dev/null
rm -f "/tmp/KMO_Component.pkg"
rm -rf "$SCRIPTS_DIR"

echo "✅ Hoàn tất đóng gói toàn diện!"
echo "   1. File PKG Cài tự động: $SCRIPT_DIR/KMO_LiveWallpaper-macOS-Installer.pkg"
echo "   2. File DMG Kéo thả:     $SCRIPT_DIR/KMO_LiveWallpaper.dmg"
echo "   3. File ZIP Truyền thống: $SCRIPT_DIR/KMO_LiveWallpaper-macOS-Universal.zip"
