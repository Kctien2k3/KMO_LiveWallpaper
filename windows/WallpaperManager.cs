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

            // Timer kiểm tra tài nguyên và che phủ định kỳ (1.5 giây)
            _monitorTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(1.5)
            };
            _monitorTimer.Tick += OnMonitorTick;
            _monitorTimer.Start();
        }

        public void InitializeDisplays()
        {
            CloseAllDisplays();

            if (string.IsNullOrEmpty(_config.VideoPath) || !File.Exists(_config.VideoPath))
            {
                App.Log("[WallpaperManager] No video configured yet. Skipping wallpaper window creation.");
                return;
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
            _monitorTimer.Stop();
            _pauseDebounceTimer?.Stop();
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            CloseAllDisplays();
        }
    }
}
