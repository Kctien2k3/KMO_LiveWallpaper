@echo off
chcp 65001 >nul
echo ==================================================
echo   BIÊN DỊCH KMO_LiveWallpaper CHO WINDOWS (x64)
echo ==================================================

where dotnet >nul 2>nul
if %errorlevel% neq 0 (
    echo [LỖI] Chưa cài đặt .NET SDK trên máy tính này.
    echo Vui lòng tải .NET 8.0 SDK tại: https://dotnet.microsoft.com/download/dotnet/8.0
    if "%~1" neq "--no-pause" pause
    exit /b 1
)

echo [1/2] Đang biên dịch bản Release Single-File Standalone (x64)...
dotnet publish "%~dp0KMO_LiveWallpaper.csproj" -c Release -r win-x64 -o "%~dp0publish"

if %errorlevel% neq 0 (
    echo [LỖI] Quá trình biên dịch thất bại!
    if "%~1" neq "--no-pause" pause
    exit /b 1
)

echo [2/2] Đóng gói hoàn tất tại thư mục: %~dp0publish\KMO_LiveWallpaper.exe
echo ==================================================
echo   THÀNH CÔNG! Bạn có thể chạy %~dp0publish\KMO_LiveWallpaper.exe
echo ==================================================
if "%~1" neq "--no-pause" pause
