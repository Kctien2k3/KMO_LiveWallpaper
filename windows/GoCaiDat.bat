@echo off
chcp 65001 >nul
setlocal

echo ==================================================
echo   GO CAI DAT UNG DUNG KMO_LiveWallpaper (WINDOWS)
echo ==================================================

echo [1/4] Dang dung tien trinh KMO_LiveWallpaper...
taskkill /F /IM KMO_LiveWallpaper.exe >nul 2>nul

echo [2/4] Dang xoa dang ky tu khoi dong (Registry Run)...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "KMO_LiveWallpaper" /f >nul 2>nul

echo [3/4] Dang xoa bieu tuong loi tat (Desktop, Start Menu, Startup)...
powershell -NoProfile -Command "Remove-Item -Path \"$([Environment]::GetFolderPath('Desktop'))\KMO Live Wallpaper.lnk\" -Force -ErrorAction SilentlyContinue; Remove-Item -Path \"$([Environment]::GetFolderPath('Programs'))\KMO Live Wallpaper.lnk\" -Force -ErrorAction SilentlyContinue; Remove-Item -Path \"$([Environment]::GetFolderPath('Startup'))\KMO Live Wallpaper.lnk\" -Force -ErrorAction SilentlyContinue"

echo [4/4] Dang xoa du lieu va tep ung dung...
powershell -NoProfile -Command "Remove-Item -Path \"$env:LOCALAPPDATA\KMO_LiveWallpaper\" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path \"$env:APPDATA\KMO_LiveWallpaper\" -Recurse -Force -ErrorAction SilentlyContinue"

echo ==================================================
echo   GO CAI DAT HOAN TAT! HE THONG DA DUOC DON SACH.
echo ==================================================
ping 127.0.0.1 -n 3 >nul
