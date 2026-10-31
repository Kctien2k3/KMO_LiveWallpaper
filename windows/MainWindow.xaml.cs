using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using Color = System.Windows.Media.Color;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using Application = System.Windows.Application;

namespace KMO_LiveWallpaper
{
    public partial class MainWindow : Window
    {
        private bool _isInitializing = true;
        private int _currentScopeIndex = 0; // 0: Màn hình chính, 1: Màn hình khóa & Chờ

        public MainWindow()
        {
            App.Log("[MainWindow] Constructor start");
            InitializeComponent();
            LoadAppAssets();
            SyncUIFromConfig();
            _isInitializing = false;

            WallpaperManager.Instance.StateChanged += OnWallpaperStateChanged;
            WallpaperManager.Instance.VideoInfoUpdated += OnVideoInfoUpdated;
            Closing += OnWindowClosing;
            Loaded += (s, e) =>
            {
                App.Log("[MainWindow] Event: Loaded");
                OnWallpaperStateChanged();
            };
            App.Log("[MainWindow] Constructor complete");
        }

        private void OnVideoInfoUpdated(int width, int height, TimeSpan duration)
        {
            UpdateResolutionCapabilities(width, height, duration);
        }

        private void UpdateResolutionCapabilities(int width, int height, TimeSpan duration)
        {
            Dispatcher.Invoke(() =>
            {
                string videoPath = WallpaperManager.Instance.Config.VideoPath;
                string fileName = string.IsNullOrEmpty(videoPath) ? "Chưa chọn video" : Path.GetFileName(videoPath);

                TxtVideoName.Text = fileName;
                TxtVideoName.ToolTip = $"Tệp: {fileName}\nĐộ phân giải gốc: {width}x{height}\nThời lượng: {duration:mm\\:ss}";

                int maxDim = Math.Max(width, height);
                int minDim = Math.Min(width, height);
                bool supports4k = (maxDim >= 3200 || minDim >= 1800);
                bool supports2k = (maxDim >= 2000 || minDim >= 1200);
                bool supports1080p = true; // 1080p luôn khả dụng

                // Cập nhật trạng thái và nhãn của 3 nút lựa chọn chất lượng
                Rb1080p.IsEnabled = supports1080p;
                Rb2k.IsEnabled = supports2k;
                Rb4k.IsEnabled = supports4k;

                Rb1080p.Content = "1080p";
                Rb2k.Content = supports2k ? "2K QHD" : "2K 🔒";
                Rb4k.Content = supports4k ? "4K Gốc" : "4K 🔒";

                Rb1080p.ToolTip = "Phát ở độ phân giải 1080p Full HD (Tiết kiệm GPU & RAM)";
                Rb2k.ToolTip = supports2k ? "Phát ở độ phân giải 2K QHD sắc nét" : "Video gốc không đủ độ phân giải 2K (bị khóa)";
                Rb4k.ToolTip = supports4k ? "Phát ở độ phân giải 4K gốc (Direct Hardware Scanout)" : "Video gốc không đủ độ phân giải 4K (bị khóa)";

                // Tự động điều chỉnh chế độ nếu chế độ hiện tại vượt quá chất lượng video gốc
                int currentMode = WallpaperManager.Instance.Config.ResolutionMode;
                int maxAllowed = supports4k ? 2 : (supports2k ? 1 : 0);
                if (currentMode > maxAllowed)
                {
                    currentMode = maxAllowed;
                }

                _isInitializing = true;
                Rb1080p.IsChecked = (currentMode == 0);
                Rb2k.IsChecked = (currentMode == 1);
                Rb4k.IsChecked = (currentMode == 2);
                _isInitializing = false;

                UpdateQualityNotice(currentMode);
                WallpaperManager.Instance.SetResolutionMode(currentMode);
                OnWallpaperStateChanged();
            });
        }

        private void UpdateQualityNotice(int mode)
        {
            switch (mode)
            {
                case 0:
                    TxtQualityNotice.Text = "Đang phát 1080p Full HD • Tiết kiệm GPU & RAM tối đa";
                    TxtQualityNotice.Foreground = new SolidColorBrush(Color.FromRgb(50, 215, 75)); // Green
                    break;
                case 1:
                    TxtQualityNotice.Text = "Đang phát 2K QHD sắc nét • Cân bằng hoàn hảo giữa độ mịn và hiệu năng";
                    TxtQualityNotice.Foreground = new SolidColorBrush(Color.FromRgb(255, 159, 10)); // Orange
                    break;
                default:
                    TxtQualityNotice.Text = "Đang giải mã 4K gốc (Direct Hardware Scanout) • Sắc nét đỉnh cao";
                    TxtQualityNotice.Foreground = new SolidColorBrush(Color.FromRgb(76, 194, 255)); // Blue
                    break;
            }
        }

        private void LoadAppAssets()
        {
            try
            {
                string pngPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.png");
                if (File.Exists(pngPath))
                {
                    ImgLogo.Source = new System.Windows.Media.Imaging.BitmapImage(new Uri(pngPath));
                }
            }
            catch {}
        }

        private void SyncUIFromConfig()
        {
            var config = WallpaperManager.Instance.Config;
            string fileName = string.IsNullOrEmpty(config.VideoPath) ? "Chưa chọn video" : Path.GetFileName(config.VideoPath);
            TxtVideoName.Text = fileName;
            TxtVideoName.ToolTip = config.VideoPath;

            // Chất lượng phân giải
            Rb1080p.IsChecked = (config.ResolutionMode == 0);
            Rb2k.IsChecked = (config.ResolutionMode == 1);
            Rb4k.IsChecked = (config.ResolutionMode == 2);
            UpdateQualityNotice(config.ResolutionMode);

            // FPS Mode
            RbFps30.IsChecked = (config.FpsMode == 0);
            RbFps60.IsChecked = (config.FpsMode == 1);
            RbFps120.IsChecked = (config.FpsMode == 2);

            // Màn hình khóa & Screen Saver
            CbLockScreen.IsChecked = config.LockScreenEnabled;
            CbScreenSaver.IsChecked = config.ScreenSaverEnabled;
            CbSyncLockScreen.IsChecked = config.SyncLockScreenSettings;

            // Tiết kiệm năng lượng & Mức trần
            CbAutoPause90.IsChecked = config.AutoPause90Enabled;
            CbCeiling.IsChecked = config.CeilingEnabled;
            CbAutoLaunchStartup.IsChecked = WallpaperManager.Instance.IsAutoLaunchStartupEnabled();
            CbMute.IsChecked = config.IsMuted;

            // Phạm vi tác động & Khung hình
            RbScopeDesktop.IsChecked = true;
            _currentScopeIndex = 0;
            RefreshCard2UIForCurrentScope();

            // Nhận diện metadata nếu video đã có sẵn
            if (!string.IsNullOrEmpty(config.VideoPath) && File.Exists(config.VideoPath))
            {
                var (dur, w, h) = WallpaperManager.GetVideoMetadata(config.VideoPath);
                if (w > 0 && h > 0)
                {
                    UpdateResolutionCapabilities(w, h, dur);
                }
            }
        }

        private void RefreshCard2UIForCurrentScope()
        {
            _isInitializing = true;
            var config = WallpaperManager.Instance.Config;

            if (RbFill == null || SliderZoom == null || SliderContrast == null || SliderSaturation == null)
            {
                _isInitializing = false;
                return;
            }

            int stretch;
            double zoom, ox, oy, contrast, saturation;

            if (_currentScopeIndex == 0)
            {
                stretch = config.StretchMode;
                zoom = config.ZoomScale;
                ox = config.OffsetX;
                oy = config.OffsetY;
                contrast = config.ContrastValue;
                saturation = config.SaturationValue;
            }
            else
            {
                stretch = config.LockGravityMode;
                zoom = config.LockZoomScale;
                ox = config.LockOffsetX;
                oy = config.LockOffsetY;
                contrast = config.LockContrastValue;
                saturation = config.LockSaturationValue;
            }

            RbFill.IsChecked = (stretch == 0);
            RbUniform.IsChecked = (stretch == 1);
            RbStretch.IsChecked = (stretch == 2);

            SliderZoom.Value = zoom * 100.0;
            TxtZoomVal.Text = $"{(int)Math.Round(zoom * 100.0)}%";

            SliderOffsetX.Value = ox;
            TxtOffsetXVal.Text = $"{(int)Math.Round(ox)}";

            SliderOffsetY.Value = oy;
            TxtOffsetYVal.Text = $"{(int)Math.Round(oy)}";

            SliderContrast.Value = contrast * 100.0;
            TxtContrastVal.Text = $"{(int)Math.Round(contrast * 100.0)}%";

            SliderSaturation.Value = saturation * 100.0;
            TxtSaturationVal.Text = $"{(int)Math.Round(saturation * 100.0)}%";

            _isInitializing = false;
        }

        private void OnWallpaperStateChanged()
        {
            Dispatcher.Invoke(() =>
            {
                var config = WallpaperManager.Instance.Config;
                string resText = config.ResolutionMode switch
                {
                    0 => "1080p",
                    1 => "2K",
                    _ => "4K"
                };
                string fpsText = config.FpsMode switch
                {
                    0 => "30 FPS",
                    1 => "60 FPS",
                    _ => "120 FPS"
                };

                bool isPlaying = !WallpaperManager.Instance.IsUserPaused;
                BtnPlayPause.Content = isPlaying ? "Tạm dừng" : "Phát tiếp";

                double cov = WallpaperManager.Instance.LastCoverage;
                double cpu = WallpaperManager.Instance.SmoothedCPU;
                long memMB = 0;
                try
                {
                    using var proc = Process.GetCurrentProcess();
                    memMB = proc.WorkingSet64 / (1024 * 1024);
                }
                catch { }

                string metricStr = $"CPU {cpu:F1}% • RAM {memMB} MB";
                int covVal = (int)Math.Round(cov);

                if (WallpaperManager.Instance.IsUserPaused)
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(142, 142, 147)); // Gray
                    TxtStatus.Text = $"Đã tạm dừng ({resText} • {fpsText}) • {metricStr}";
                }
                else if (cov >= 90.0 && config.AutoPause90Enabled)
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(142, 142, 147)); // Gray
                    TxtStatus.Text = $"Đã dừng (Che {covVal}% > 90%) • {metricStr}";
                }
                else
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(50, 215, 75)); // Green
                    TxtStatus.Text = $"Đang phát ({resText} • {fpsText} • Che {covVal}%) • {metricStr}";
                }
            });
        }

        private void BtnChooseVideo_Click(object sender, RoutedEventArgs e)
        {
            var openFileDialog = new OpenFileDialog
            {
                Title = "Chọn Video Hình Nền",
                Filter = "Tệp Video (*.mp4;*.mov;*.wmv;*.mkv)|*.mp4;*.mov;*.wmv;*.mkv|Tất cả tệp (*.*)|*.*",
                CheckFileExists = true
            };

            if (openFileDialog.ShowDialog() == true)
            {
                string selectedFile = openFileDialog.FileName;

                // Kiểm tra giới hạn thời lượng video <= 60s để đảm bảo tài nguyên nhẹ mượt
                var (duration, width, height) = WallpaperManager.GetVideoMetadata(selectedFile);
                if (duration > TimeSpan.FromSeconds(60.5))
                {
                    System.Windows.MessageBox.Show(
                        $"Video đã chọn có thời lượng: {duration:mm\\:ss} (vượt quá giới hạn tối đa 60 giây).\n\n" +
                        "Vui lòng chọn video ngắn dưới 1 phút (≤ 60s) để làm hình nền động nhằm tối ưu độ mượt, tiết kiệm tài nguyên và vòng lặp liên tục!",
                        "Thời lượng video vượt quá 60s",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning
                    );
                    return;
                }

                WallpaperManager.Instance.LoadVideo(selectedFile);
                if (width > 0)
                {
                    UpdateResolutionCapabilities(width, height, duration);
                }
            }
        }

        private void Resolution_Checked(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            int mode = 2;
            if (Rb1080p.IsChecked == true) mode = 0;
            else if (Rb2k.IsChecked == true) mode = 1;

            bool allowed = (mode == 0) || (mode == 1 && Rb2k.IsEnabled) || (mode == 2 && Rb4k.IsEnabled);
            if (!allowed)
            {
                _isInitializing = true;
                int fallback = WallpaperManager.Instance.Config.ResolutionMode;
                Rb1080p.IsChecked = (fallback == 0);
                Rb2k.IsChecked = (fallback == 1);
                Rb4k.IsChecked = (fallback == 2);
                _isInitializing = false;
                return;
            }

            UpdateQualityNotice(mode);
            WallpaperManager.Instance.SetResolutionMode(mode);
            OnWallpaperStateChanged();
        }

        private void Fps_Checked(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            int mode = 1;
            if (RbFps30.IsChecked == true) mode = 0;
            else if (RbFps120.IsChecked == true) mode = 2;

            WallpaperManager.Instance.SetFpsMode(mode);
            OnWallpaperStateChanged();
        }

        private void Scope_Checked(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            _currentScopeIndex = (RbScopeDesktop.IsChecked == true) ? 0 : 1;
            RefreshCard2UIForCurrentScope();
        }

        private void Stretch_Checked(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            int mode = 0;
            if (RbUniform.IsChecked == true) mode = 1;
            else if (RbStretch.IsChecked == true) mode = 2;

            ApplyCurrentTransform(mode);
        }

        private void Transform_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (_isInitializing) return;
            TxtZoomVal.Text = $"{(int)Math.Round(SliderZoom.Value)}%";
            TxtOffsetXVal.Text = $"{(int)Math.Round(SliderOffsetX.Value)}";
            TxtOffsetYVal.Text = $"{(int)Math.Round(SliderOffsetY.Value)}";

            int mode = 0;
            if (RbUniform.IsChecked == true) mode = 1;
            else if (RbStretch.IsChecked == true) mode = 2;

            ApplyCurrentTransform(mode);
        }

        private void ColorSlider_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (_isInitializing) return;
            TxtContrastVal.Text = $"{(int)Math.Round(SliderContrast.Value)}%";
            TxtSaturationVal.Text = $"{(int)Math.Round(SliderSaturation.Value)}%";

            double c = SliderContrast.Value / 100.0;
            double s = SliderSaturation.Value / 100.0;

            if (_currentScopeIndex == 0)
            {
                WallpaperManager.Instance.SetColorControls(c, s);
            }
            else
            {
                if (WallpaperManager.Instance.Config.SyncLockScreenSettings)
                {
                    _isInitializing = true;
                    CbSyncLockScreen.IsChecked = false;
                    _isInitializing = false;
                    WallpaperManager.Instance.SetSyncLockScreenSettings(false);
                }
                WallpaperManager.Instance.SetLockScreenColorControls(c, s);
            }
        }

        private void ApplyCurrentTransform(int stretchMode)
        {
            double zoom = SliderZoom.Value / 100.0;
            double ox = SliderOffsetX.Value;
            double oy = SliderOffsetY.Value;

            if (_currentScopeIndex == 0)
            {
                WallpaperManager.Instance.SetDisplayTransform(stretchMode, zoom, ox, oy);
            }
            else
            {
                if (WallpaperManager.Instance.Config.SyncLockScreenSettings)
                {
                    _isInitializing = true;
                    CbSyncLockScreen.IsChecked = false;
                    _isInitializing = false;
                    WallpaperManager.Instance.SetSyncLockScreenSettings(false);
                }
                WallpaperManager.Instance.SetLockScreenTransform(stretchMode, zoom, ox, oy);
            }
        }

        private void BtnReset_Click(object sender, RoutedEventArgs e)
        {
            _isInitializing = true;
            RbFill.IsChecked = true;
            SliderZoom.Value = 100;
            SliderOffsetX.Value = 0;
            SliderOffsetY.Value = 0;
            SliderContrast.Value = 100;
            SliderSaturation.Value = 100;
            TxtZoomVal.Text = "100%";
            TxtOffsetXVal.Text = "0";
            TxtOffsetYVal.Text = "0";
            TxtContrastVal.Text = "100%";
            TxtSaturationVal.Text = "100%";
            _isInitializing = false;

            if (_currentScopeIndex == 0)
            {
                WallpaperManager.Instance.SetDisplayTransform(0, 1.0, 0, 0);
                WallpaperManager.Instance.SetColorControls(1.0, 1.0);
            }
            else
            {
                if (WallpaperManager.Instance.Config.SyncLockScreenSettings)
                {
                    _isInitializing = true;
                    CbSyncLockScreen.IsChecked = false;
                    _isInitializing = false;
                    WallpaperManager.Instance.SetSyncLockScreenSettings(false);
                }
                WallpaperManager.Instance.SetLockScreenTransform(0, 1.0, 0, 0);
                WallpaperManager.Instance.SetLockScreenColorControls(1.0, 1.0);
            }
        }

        private void CbLockScreen_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            WallpaperManager.Instance.SetLockScreenEnabled(CbLockScreen.IsChecked == true);
        }

        private void CbScreenSaver_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            WallpaperManager.Instance.SetScreenSaverEnabled(CbScreenSaver.IsChecked == true);
        }

        private void CbSyncLockScreen_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            bool isSync = (CbSyncLockScreen.IsChecked == true);
            WallpaperManager.Instance.SetSyncLockScreenSettings(isSync);
            if (isSync && _currentScopeIndex == 1)
            {
                RefreshCard2UIForCurrentScope();
            }
        }

        private void CbAutoPause90_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            WallpaperManager.Instance.SetAutoPause90(CbAutoPause90.IsChecked == true);
        }

        private void CbCeiling_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            WallpaperManager.Instance.SetCeilingEnabled(CbCeiling.IsChecked == true);
        }

        private void CbAutoLaunchStartup_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            WallpaperManager.Instance.SetAutoLaunchStartup(CbAutoLaunchStartup.IsChecked == true);
        }

        private void CbMute_Changed(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            WallpaperManager.Instance.SetMuted(CbMute.IsChecked == true);
        }

        private void BtnPlayPause_Click(object sender, RoutedEventArgs e)
        {
            WallpaperManager.Instance.TogglePlayPause();
            OnWallpaperStateChanged();
        }

        private void BtnMinimize_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void BtnHide_Click(object sender, RoutedEventArgs e)
        {
            Hide();
        }

        private void BtnExit_Click(object sender, RoutedEventArgs e)
        {
            (Application.Current as App)?.ExitApplication();
        }

        private void OnWindowClosing(object? sender, CancelEventArgs e)
        {
            // Khi nhấn nút X trên thanh tiêu đề: thu nhỏ xuống Taskbar như ứng dụng bình thường
            e.Cancel = true;
            WindowState = WindowState.Minimized;
        }
    }
}
