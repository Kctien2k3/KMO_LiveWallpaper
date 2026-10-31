using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Windows.Threading;
using Microsoft.Win32;

namespace KMO_LiveWallpaper
{
    /// <summary>
    /// Quản lý Màn hình khóa (Lock Screen) và Trình bảo vệ màn hình (Screen Saver) cho Windows.
    /// Tối ưu 0% CPU khi màn hình chính đang làm việc và kích hoạt mượt mà khi người dùng không hoạt động.
    /// </summary>
    public class LockScreenManager
    {
        private static LockScreenManager? _instance;
        public static LockScreenManager Instance => _instance ??= new LockScreenManager();

        private readonly DispatcherTimer _idleTimer;
        private readonly List<ScreenSaverWindow> _activeSaverWindows = new();
        private bool _isSaverActive = false;
        private bool _isScreenLocked = false;

        public bool IsScreenSaverActive => _isSaverActive;
        public bool IsScreenLocked => _isScreenLocked;

        public event Action? ScreenSaverStarted;
        public event Action? ScreenSaverStopped;

        public LockScreenManager()
        {
            // Kiểm tra trạng thái rảnh rỗi (idle) mỗi 2 giây
            _idleTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(2.0)
            };
            _idleTimer.Tick += OnIdleCheckTick;
            _idleTimer.Start();

            SystemEvents.SessionSwitch += OnSessionSwitch;
        }

        private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
        {
            if (e.Reason == SessionSwitchReason.SessionLock)
            {
                _isScreenLocked = true;
                App.Log("[LockScreenManager] Windows Session Locked (Win+L)");
                if (WallpaperManager.Instance.Config.LockScreenEnabled)
                {
                    ApplyLockScreenWallpaper();
                }
            }
            else if (e.Reason == SessionSwitchReason.SessionUnlock)
            {
                _isScreenLocked = false;
                App.Log("[LockScreenManager] Windows Session Unlocked");
                StopScreenSaver();
            }
        }

        private void OnIdleCheckTick(object? sender, EventArgs e)
        {
            var config = WallpaperManager.Instance.Config;
            if (!config.ScreenSaverEnabled || _isSaverActive || _isScreenLocked)
            {
                return;
            }

            // Lấy thời gian chờ Screen Saver của Windows (hoặc mặc định 5 phút)
            uint timeoutSec = Win32.GetWindowsScreenSaverTimeoutSeconds();
            uint idleMs = Win32.GetIdleTimeMs();

            if (idleMs >= (timeoutSec * 1000))
            {
                App.Log($"[LockScreenManager] User idle detected ({idleMs / 1000}s >= {timeoutSec}s). Triggering Screen Saver...");
                StartScreenSaver();
            }
        }

        public void StartScreenSaver()
        {
            if (_isSaverActive) return;
            _isSaverActive = true;

            var config = WallpaperManager.Instance.Config;
            string videoPath = config.VideoPath;
            if (string.IsNullOrEmpty(videoPath) || !File.Exists(videoPath))
            {
                videoPath = WallpaperManager.EnsureDefaultVideoAvailable();
            }

            int stretch = config.SyncLockScreenSettings ? config.StretchMode : config.LockGravityMode;
            double zoom = config.SyncLockScreenSettings ? config.ZoomScale : config.LockZoomScale;
            double ox = config.SyncLockScreenSettings ? config.OffsetX : config.LockOffsetX;
            double oy = config.SyncLockScreenSettings ? config.OffsetY : config.LockOffsetY;
            double contrast = config.SyncLockScreenSettings ? config.ContrastValue : config.LockContrastValue;
            double saturation = config.SyncLockScreenSettings ? config.SaturationValue : config.LockSaturationValue;

            _activeSaverWindows.Clear();
            foreach (var screen in Screen.AllScreens)
            {
                var saverWin = new ScreenSaverWindow(screen);
                saverWin.Dismissed += OnSaverWindowDismissed;
                saverWin.Show();
                saverWin.ApplySettings(videoPath, stretch, zoom, ox, oy, contrast, saturation, config.FpsMode);
                _activeSaverWindows.Add(saverWin);
            }

            ScreenSaverStarted?.Invoke();
        }

        private void OnSaverWindowDismissed()
        {
            StopScreenSaver();
        }

        public void StopScreenSaver()
        {
            if (!_isSaverActive) return;
            _isSaverActive = false;

            foreach (var win in _activeSaverWindows.ToArray())
            {
                try { win.Close(); } catch { }
            }
            _activeSaverWindows.Clear();

            ScreenSaverStopped?.Invoke();
            WallpaperManager.Instance.UpdatePlaybackState();
        }

        /// <summary>
        /// Đồng bộ khung hình và áp dụng cho Màn hình khóa Windows
        /// </summary>
        public void ApplyLockScreenWallpaper()
        {
            try
            {
                var config = WallpaperManager.Instance.Config;
                string videoPath = config.VideoPath;
                if (string.IsNullOrEmpty(videoPath) || !File.Exists(videoPath)) return;

                WallpaperManager.Instance.CaptureLockScreenSnapshot();

                string lockscreenDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "KMO_LiveWallpaper");
                if (!Directory.Exists(lockscreenDir)) Directory.CreateDirectory(lockscreenDir);

                string imagePath = Path.Combine(lockscreenDir, "lockscreen_wallpaper.jpg");

                // Ghi nhận đường dẫn hình nền khóa
                App.Log($"[LockScreenManager] ApplyLockScreenWallpaper: target={imagePath}");

                // Cập nhật Registry Windows Personalization cho LockScreenImage nếu được phân quyền
                try
                {
                    using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Lock Screen", true);
                    if (key != null && File.Exists(imagePath))
                    {
                        key.SetValue("LockScreenImage", imagePath, RegistryValueKind.String);
                    }
                }
                catch { }
            }
            catch (Exception ex)
            {
                App.Log($"[LockScreenManager] ApplyLockScreenWallpaper ERROR: {ex.Message}");
            }
        }

        /// <summary>
        /// Đăng ký tệp .scr để người dùng chọn KMO trong hộp thoại Cài đặt Screen Saver của Windows
        /// </summary>
        public static void RegisterScreenSaverExecutable()
        {
            try
            {
                string exePath = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName ?? "";
                if (string.IsNullOrEmpty(exePath) || !File.Exists(exePath)) return;

                string appDataDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "KMO_LiveWallpaper");
                if (!Directory.Exists(appDataDir)) Directory.CreateDirectory(appDataDir);

                string scrPath = Path.Combine(appDataDir, "KMO_LiveWallpaper.scr");
                if (!File.Exists(scrPath) || new FileInfo(scrPath).Length != new FileInfo(exePath).Length)
                {
                    File.Copy(exePath, scrPath, true);
                    App.Log($"[LockScreenManager] Created screen saver binary: {scrPath}");
                }
            }
            catch (Exception ex)
            {
                App.Log($"[LockScreenManager] RegisterScreenSaverExecutable error: {ex.Message}");
            }
        }
    }
}
