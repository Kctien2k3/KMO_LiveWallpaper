#!/bin/zsh
SCRIPT_DIR="${0:A:h}"
SRC_APP="$SCRIPT_DIR/KMO_LiveWallpaper.app"
DEST_APP="/Applications/KMO_LiveWallpaper.app"

echo "=================================================="
echo "  CÀI ĐẶT ỨNG DỤNG KMO_LiveWallpaper (macOS)      "
echo "=================================================="

if [ ! -d "$SRC_APP" ]; then
    echo "⚙️ Đang biên dịch ứng dụng từ mã nguồn..."
    "$SCRIPT_DIR/build.sh"
fi

echo "📦 Đang sao chép KMO_LiveWallpaper.app vào /Applications..."
killall KMO_LiveWallpaper 2>/dev/null || true
killall HinhNenDong 2>/dev/null || true
rm -rf "$DEST_APP" "/Applications/HinhNenDong.app"
cp -R "$SRC_APP" "$DEST_APP"

# Gỡ cờ kiểm dịch (Quarantine) của macOS khi tải từ GitHub về máy mới
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
codesign --force --deep --sign - "$DEST_APP" 2>/dev/null || true

echo "🚀 Đang khởi động ứng dụng KMO_LiveWallpaper..."
open "$DEST_APP"

echo "✅ Cài đặt hoàn tất! Bạn có thể đóng cửa sổ này."
