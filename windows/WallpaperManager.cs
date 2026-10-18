using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Forms;
using System.Windows.Threading;
using Microsoft.Win32;

namespace KMO_LiveWallpaper
{
    public class WallpaperConfig
    {
        public string VideoPath { get; set; } = string.Empty;
        public int StretchMode { get; set; } = 0; // 0: Lấp đầy, 1: Vừa khít, 2: Kéo giãn
        public double ZoomScale { get; set; } = 1.0;
        public double OffsetX { get; set; } = 0.0;
        public double OffsetY { get; set; } = 0.0;
        public bool AutoPause90Enabled { get; set; } = true;
        public bool CeilingEnabled { get; set; } = true;
        public bool IsMuted { get; set; } = true;
        public int ResolutionMode { get; set; } = 2; // 0: 1080p, 1: 2K, 2: 4K
    }

    public class WallpaperManager
    {
        private static WallpaperManager? _instance;
        public static WallpaperManager Instance => _instance ??= new WallpaperManager();

        private readonly List<WallpaperWindow> _wallpaperWindows = new();
        private readonly DispatcherTimer _monitorTimer;
        private DispatcherTimer? _pauseDebounceTimer;
        private DispatcherTimer? _eventDebounceTimer;
        private IntPtr _hWinEventHook = IntPtr.Zero;
        private Win32.WinEventDelegate? _winEventProc;

        private WallpaperConfig _config = new();
        private bool _isScreenLocked = false;
        private bool _isSuspended = false;
        private bool _userPaused = false;
        private double _lastCoverage = 0.0;
        private double _smoothedCPU = 0.0;

        public WallpaperConfig Config => _config;
        public double LastCoverage => _lastCoverage;
        public double SmoothedCPU => _smoothedCPU;
        public bool IsUserPaused => _userPaused;

        public event Action? StateChanged;

        private string ConfigFilePath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "KMO_LiveWallpaper",
            "config.json"
        );

        public WallpaperManager()
        {
            LoadConfig();

            // Đăng ký sự kiện nguồn và hiển thị của Windows
            SystemEvents.SessionSwitch += OnSessionSwitch;
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;

            // Lắng nghe sự kiện cửa sổ tức thì (60ms) như macOS: chuyển app, di chuyển, phóng to, thu nhỏ
            _winEventProc = new Win32.WinEventDelegate(OnWinEvent);
            _hWinEventHook = Win32.SetWinEventHook(
                Win32.EVENT_SYSTEM_FOREGROUND,
                Win32.EVENT_SYSTEM_MINIMIZEEND,
                IntPtr.Zero,
                _winEventProc,
                0,
                0,
                Win32.WINEVENT_OUTOFCONTEXT | Win32.WINEVENT_SKIPOWNPROCESS
            );

            // Timer kiểm tra tài nguyên và che phủ định kỳ (1.5 giây) làm dự phòng
            _monitorTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(1.5)
            };
            _monitorTimer.Tick += OnMonitorTick;
            _monitorTimer.Start();
        }

        private void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
        {
            if (idObject != 0) return; // Chỉ xử lý OBJID_WINDOW (0)

            // Debounce 60ms mượt mà giống hệt schedulePlaybackStateUpdate(delay: 0.06) trên macOS
            _eventDebounceTimer?.Stop();
            _eventDebounceTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(60) };
            _eventDebounceTimer.Tick += (s, e) =>
            {
                _eventDebounceTimer?.Stop();
                _eventDebounceTimer = null;
                UpdatePlaybackState();
            };
            _eventDebounceTimer.Start();
        }

        public static string EnsureDefaultVideoAvailable()
        {
            try
            {
                string appDataDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "KMO_LiveWallpaper");
                if (!Directory.Exists(appDataDir))
                {
                    Directory.CreateDirectory(appDataDir);
                }

                string targetPath = Path.Combine(appDataDir, "default.mp4");

                // 1. Đã có sẵn trong AppData và có dung lượng hợp lệ (> 1MB)
                if (File.Exists(targetPath) && new FileInfo(targetPath).Length > 1024 * 1024)
                {
                    return targetPath;
                }

                // 2. Kiểm tra tệp default.mp4 nằm cùng thư mục với tệp exe
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string localDefault = Path.Combine(baseDir, "default.mp4");
                if (File.Exists(localDefault) && new FileInfo(localDefault).Length > 1024 * 1024)
                {
                    try
                    {
                        File.Copy(localDefault, targetPath, true);
                        return targetPath;
                    }
                    catch
                    {
                        return localDefault;
                    }
                }

                // 3. Trích xuất từ Embedded Resource tích hợp sẵn trong file exe
                var assembly = System.Reflection.Assembly.GetExecutingAssembly();
                using var stream = assembly.GetManifestResourceStream("KMO_LiveWallpaper.default.mp4");
                if (stream != null)
                {
                    using var fs = new FileStream(targetPath, FileMode.Create, FileAccess.Write);
                    stream.CopyTo(fs);
                    App.Log($"[WallpaperManager] Extracted embedded default.mp4 to {targetPath} ({fs.Length} bytes)");
                    return targetPath;
                }

                if (File.Exists(targetPath)) return targetPath;
                if (File.Exists(localDefault)) return localDefault;
            }
            catch (Exception ex)
            {
                App.Log($"[WallpaperManager] EnsureDefaultVideoAvailable error: {ex.Message}");
            }

            return string.Empty;
        }

        public void InitializeDisplays()
        {
            CloseAllDisplays();

            if (string.IsNullOrEmpty(_config.VideoPath) || !File.Exists(_config.VideoPath))
            {
                string defaultVid = EnsureDefaultVideoAvailable();
                if (!string.IsNullOrEmpty(defaultVid))
                {
                    _config.VideoPath = defaultVid;
                    SaveConfig();
                }
                else
                {
                    App.Log("[WallpaperManager] No video configured and no default video found. Skipping wallpaper window creation.");
                    return;
                }
            }

            foreach (var screen in Screen.AllScreens)
            {
                var win = new WallpaperWindow(screen);
                win.SetMuted(_config.IsMuted);
                win.SetStretchMode(_config.StretchMode);
                win.ApplyTransform(_config.ZoomScale, _config.OffsetX, _config.OffsetY);
                win.Show();
                win.LoadVideo(_config.VideoPath);
                _wallpaperWindows.Add(win);
            }

            UpdatePlaybackState();
        }

        public void LoadVideo(string filePath)
        {
            _config.VideoPath = filePath;
            SaveConfig();
            InitializeDisplays();
        }

        public void TogglePlayPause()
        {
            _userPaused = !_userPaused;
            UpdatePlaybackState();
        }

        public void SetAutoPause90(bool enabled)
        {
            _config.AutoPause90Enabled = enabled;
            SaveConfig();
            UpdatePlaybackState();
        }

        public void SetCeilingEnabled(bool enabled)
        {
            _config.CeilingEnabled = enabled;
            SaveConfig();
            UpdatePlaybackState();
        }

        public void SetMuted(bool muted)
        {
            _config.IsMuted = muted;
            SaveConfig();
            foreach (var win in _wallpaperWindows)
            {
                win.SetMuted(muted);
            }
        }

        public void SetDisplayTransform(int stretchMode, double zoom, double offsetX, double offsetY)
        {
            _config.StretchMode = stretchMode;
            _config.ZoomScale = zoom;
            _config.OffsetX = offsetX;
            _config.OffsetY = offsetY;
            SaveConfig();

            foreach (var win in _wallpaperWindows)
            {
                win.SetStretchMode(stretchMode);
                win.ApplyTransform(zoom, offsetX, offsetY);
            }
        }

        public void UpdatePlaybackState()
        {
            if (_isScreenLocked || _isSuspended || _userPaused)
            {
                _pauseDebounceTimer?.Stop();
                PauseAll();
                StateChanged?.Invoke();
                return;
            }

            bool proApp = ScreenCoverageMonitor.IsProEditorOrHeavyAppActive();
            double cov = proApp ? 100.0 : ScreenCoverageMonitor.CalculateScreenCoveragePercent(Screen.PrimaryScreen ?? Screen.AllScreens[0]);
            _lastCoverage = cov;

            bool shouldPause = proApp || (_config.AutoPause90Enabled && cov >= 90.0);
            App.Log($"[PlaybackState] Cov={cov:F1}%, ProApp={proApp}, ShouldPause={shouldPause}, AnyPlaying={IsAnyPlaying()}");

            if (!shouldPause)
            {
                // Khi về Desktop: Phát lại tức thì (0ms)
                _pauseDebounceTimer?.Stop();
                _pauseDebounceTimer = null;
                PlayAll();
            }
            else
            {
                // Khi che > 90%: Chờ mượt 0.45s cho cửa sổ Windows trượt xong rồi mới ngắt
                if (_pauseDebounceTimer == null && IsAnyPlaying())
                {
                    _pauseDebounceTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(450) };
                    _pauseDebounceTimer.Tick += (s, e) =>
                    {
                        _pauseDebounceTimer.Stop();
                        _pauseDebounceTimer = null;
                        PauseAll();
                        CompactMemoryIfNeeded();
                        StateChanged?.Invoke();
                    };
                    _pauseDebounceTimer.Start();
                }
            }

            StateChanged?.Invoke();
        }

        private void OnMonitorTick(object? sender, EventArgs e)
        {
            try
            {
                App.Log("[Tick] OnMonitorTick starting...");
                UpdatePlaybackState();
                CheckResourceCeiling();
                App.Log("[Tick] OnMonitorTick completed.");
            }
            catch (Exception ex)
            {
                App.Log($"[Tick ERROR] {ex}");
            }
        }

        private void CheckResourceCeiling()
        {
            try
            {
                using var proc = Process.GetCurrentProcess();
                proc.Refresh();

                double ramMB = proc.WorkingSet64 / (1024.0 * 1024.0);

                // Nếu RAM vượt ngưỡng an toàn 75MB, tự động thu gọn bộ nhớ đệm để giữ vững trần 80MB
                if (_config.CeilingEnabled && ramMB > 75.0)
                {
                    CompactMemoryIfNeeded();
                }
            }
            catch { }
        }

        public void CompactMemoryIfNeeded()
        {
            GC.Collect(2, GCCollectionMode.Forced, true);
            GC.WaitForPendingFinalizers();
            try
            {
                Win32.EmptyWorkingSet(Process.GetCurrentProcess().Handle);
            }
            catch { }
        }

        private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
        {
            if (e.Reason == SessionSwitchReason.SessionLock)
            {
                _isScreenLocked = true;
                PauseAll();
                CompactMemoryIfNeeded();
            }
            else if (e.Reason == SessionSwitchReason.SessionUnlock)
            {
                _isScreenLocked = false;
                UpdatePlaybackState();
            }
        }

        private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
        {
            if (e.Mode == PowerModes.Suspend)
            {
                _isSuspended = true;
                PauseAll();
                CompactMemoryIfNeeded();
            }
            else if (e.Mode == PowerModes.Resume)
            {
                _isSuspended = false;
                UpdatePlaybackState();
            }
        }

        private void OnDisplaySettingsChanged(object? sender, EventArgs e)
        {
            // Tự động nhận diện thay đổi khi cắm/rút HDMI hoặc chiếu TV (Mirroring/Extended)
            var screens = Screen.AllScreens;
            if (_wallpaperWindows.Count == screens.Length)
            {
                for (int i = 0; i < screens.Length; i++)
                {
                    _wallpaperWindows[i].AutoFitScreen(screens[i]);
                }
            }
            else
            {
                InitializeDisplays();
            }
        }

        private void PlayAll()
        {
            foreach (var win in _wallpaperWindows)
            {
                win.PlayVideo();
            }
        }

        private void PauseAll()
        {
            foreach (var win in _wallpaperWindows)
            {
                win.PauseVideo();
            }
        }

        private bool IsAnyPlaying()
        {
            foreach (var win in _wallpaperWindows)
            {
                if (win.IsPlaying) return true;
            }
            return false;
        }

        private void CloseAllDisplays()
        {
            foreach (var win in _wallpaperWindows)
            {
                win.Close();
            }
            _wallpaperWindows.Clear();
        }

        private void LoadConfig()
        {
            try
            {
                if (File.Exists(ConfigFilePath))
                {
                    string json = File.ReadAllText(ConfigFilePath);
                    _config = JsonSerializer.Deserialize<WallpaperConfig>(json) ?? new WallpaperConfig();
                }
            }
            catch { }

            // Nếu người dùng mới cài đặt lần đầu hoặc chưa có video (hoặc video cũ bị xóa)
            // Tự động gắn video hình nền mặc định để tuyệt đối không bị màn hình đen/trống!
            if (string.IsNullOrEmpty(_config.VideoPath) || !File.Exists(_config.VideoPath))
            {
                string defaultVid = EnsureDefaultVideoAvailable();
                if (!string.IsNullOrEmpty(defaultVid))
                {
                    _config.VideoPath = defaultVid;
                    SaveConfig();
                    App.Log($"[WallpaperManager] Loaded default fallback wallpaper: {defaultVid}");
                }
            }
        }

        public void SaveConfig()
        {
            try
            {
                string dir = Path.GetDirectoryName(ConfigFilePath)!;
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

                string json = JsonSerializer.Serialize(_config, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(ConfigFilePath, json);
            }
            catch { }
        }

        public void Shutdown()
        {
            if (_hWinEventHook != IntPtr.Zero)
            {
                Win32.UnhookWinEvent(_hWinEventHook);
                _hWinEventHook = IntPtr.Zero;
            }
            _eventDebounceTimer?.Stop();
            _monitorTimer.Stop();
            _pauseDebounceTimer?.Stop();
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            CloseAllDisplays();
        }
    }
}
