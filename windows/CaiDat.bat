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
if exist "%~dp0app.ico" copy /Y "%~dp0app.ico" "%TARGET_DIR%\app.ico" >nul
if exist "%~dp0app.png" copy /Y "%~dp0app.png" "%TARGET_DIR%\app.png" >nul
if exist "%~dp0default.mp4" copy /Y "%~dp0default.mp4" "%TARGET_DIR%\default.mp4" >nul
if exist "%~dp0publish\default.mp4" copy /Y "%~dp0publish\default.mp4" "%TARGET_DIR%\default.mp4" >nul

echo [🔗] Đang tạo biểu tượng lối tắt ngoài Desktop và Start Menu...
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $d = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'KMO Live Wallpaper.lnk'); $s = $ws.CreateShortcut($d); $s.TargetPath = '%TARGET_DIR%\KMO_LiveWallpaper.exe'; $s.WorkingDirectory = '%TARGET_DIR%'; $s.IconLocation = '%TARGET_DIR%\KMO_LiveWallpaper.exe,0'; $s.Description = 'KMO Live Wallpaper'; $s.Save(); $sm = [System.IO.Path]::Combine([Environment]::GetFolderPath('Programs'), 'KMO Live Wallpaper.lnk'); $s2 = $ws.CreateShortcut($sm); $s2.TargetPath = '%TARGET_DIR%\KMO_LiveWallpaper.exe'; $s2.WorkingDirectory = '%TARGET_DIR%'; $s2.IconLocation = '%TARGET_DIR%\KMO_LiveWallpaper.exe,0'; $s2.Description = 'KMO Live Wallpaper'; $s2.Save()"

echo [🚀] Đang khởi chạy KMO Live Wallpaper...
start "" "%TARGET_DIR%\KMO_LiveWallpaper.exe"

echo ==================================================
echo   ✅ CÀI ĐẶT HOÀN TẤT! ỨNG DỤNG ĐÃ KHỞI CHẠY.
echo ==================================================
timeout /t 3 >nul
