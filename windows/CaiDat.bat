@echo off
chcp 65001 >nul
setlocal

echo ==================================================
echo   CÀI ĐẶT ỨNG DỤNG KMO_LiveWallpaper (WINDOWS)
echo ==================================================

set "TARGET_DIR=%LOCALAPPDATA%\KMO_LiveWallpaper"
set "EXE_SRC=%~dp0publish\KMO_LiveWallpaper.exe"

if not exist "%EXE_SRC%" (
    set "EXE_SRC=%~dp0KMO_LiveWallpaper.exe"
)

if not exist "%EXE_SRC%" (
    echo [⚙️] Đang tự động biên dịch ứng dụng...
    call "%~dp0build.bat"
    set "EXE_SRC=%~dp0publish\KMO_LiveWallpaper.exe"
)

if not exist "%EXE_SRC%" (
    echo [❌] Không tìm thấy tệp KMO_LiveWallpaper.exe để cài đặt!
    pause
    exit /b 1
)

echo [📦] Đang cài đặt vào: %TARGET_DIR% ...
taskkill /F /IM KMO_LiveWallpaper.exe >nul 2>nul
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
copy /Y "%EXE_SRC%" "%TARGET_DIR%\KMO_LiveWallpaper.exe" >nul

echo [🔗] Đang tạo lối tắt ngoài Desktop...
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'KMO_LiveWallpaper.lnk')); $s.TargetPath = '%TARGET_DIR%\KMO_LiveWallpaper.exe'; $s.Save()"

echo [🚀] Đang khởi chạy KMO_LiveWallpaper...
start "" "%TARGET_DIR%\KMO_LiveWallpaper.exe"

echo ==================================================
echo   ✅ CÀI ĐẶT HOÀN TẤT! ỨNG DỤNG ĐÃ KHỞI CHẠY.
echo ==================================================
timeout /t 3 >nul
