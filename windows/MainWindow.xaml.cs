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
            Loaded += (s, e) => App.Log("[MainWindow] Event: Loaded");
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

                bool supports4k = (width >= 3840 || height >= 2160);
                bool supports2k = (width >= 2560 || height >= 1440);
                bool supports1080p = true; // 1080p luôn khả dụng

                // Cập nhật thông tin kỹ thuật gốc
                if (width > 0 && height > 0)
                {
                    string resCategory = supports4k ? "4K UHD" : supports2k ? "2K QHD" : "1080p Full HD";
                    TxtNativeResInfo.Text = $"{width}x{height} ({resCategory}) • {(duration > TimeSpan.Zero ? $"{duration:mm\\:ss}" : "<60s")}";
                    TxtNativeResInfo.Foreground = supports4k ? new SolidColorBrush(Color.FromRgb(76, 194, 255))
                                                : supports2k ? new SolidColorBrush(Color.FromRgb(255, 159, 10))
                                                : new SolidColorBrush(Color.FromRgb(50, 215, 75));

                    if (supports4k)
                    {
                        TxtSupportedModesInfo.Text = "Khả dụng: 1080p, 2K, 4K";
                        TxtSupportedModesInfo.Foreground = new SolidColorBrush(Color.FromRgb(50, 215, 75));
                    }
                    else if (supports2k)
                    {
                        TxtSupportedModesInfo.Text = "Khả dụng: 1080p, 2K (Khóa 4K)";
                        TxtSupportedModesInfo.Foreground = new SolidColorBrush(Color.FromRgb(255, 159, 10));
                    }
                    else
                    {
                        TxtSupportedModesInfo.Text = "Khả dụng: Chỉ 1080p (Khóa 2K, 4K)";
                        TxtSupportedModesInfo.Foreground = new SolidColorBrush(Color.FromRgb(255, 69, 58));
                    }
                }

                // Cập nhật trạng thái và nhãn của 3 nút lựa chọn chất lượng
                Rb1080p.IsEnabled = supports1080p;
                Rb2k.IsEnabled = supports2k;
                Rb4k.IsEnabled = supports4k;

                Rb1080p.Content = "1080p";
                Rb2k.Content = supports2k ? "2K QHD" : "2K (Khóa 🔒)";
                Rb4k.Content = supports4k ? "4K Gốc" : "4K (Khóa 🔒)";

                Rb1080p.ToolTip = "Phát ở độ phân giải 1080p Full HD";
                Rb2k.ToolTip = supports2k ? "Phát ở độ phân giải 2K QHD (2560x1440)" : "Video gốc không đủ độ phân giải 2K (bị khóa)";
                Rb4k.ToolTip = supports4k ? "Phát ở độ phân giải 4K gốc (3840x2160)" : "Video gốc không đủ độ phân giải 4K (bị khóa)";

                // Tự động điều chỉnh chế độ nếu chế độ hiện tại vượt quá chất lượng video gốc
                int currentMode = WallpaperManager.Instance.Config.ResolutionMode;
                if (currentMode == 2 && !supports4k)
                {
                    currentMode = supports2k ? 1 : 0;
                }
                else if (currentMode == 1 && !supports2k)
                {
                    currentMode = 0;
                }

                _isInitializing = true;
                Rb1080p.IsChecked = (currentMode == 0);
                Rb2k.IsChecked = (currentMode == 1);
                Rb4k.IsChecked = (currentMode == 2);
                _isInitializing = false;

                UpdateQualityNotice(currentMode);
                WallpaperManager.Instance.SetResolutionMode(currentMode);
            });
        }

        private void UpdateQualityNotice(int mode)
        {
            switch (mode)
            {
                case 0:
                    TxtQualityNotice.Text = "Đang hạ về 1080p Full HD để tiết kiệm tài nguyên GPU và pin tối đa";
                    TxtQualityNotice.Foreground = new SolidColorBrush(Color.FromRgb(50, 215, 75));
                    break;
                case 1:
                    TxtQualityNotice.Text = "Đang phát ở 2K QHD sắc nét, cân bằng hoàn hảo giữa độ mịn và hiệu năng";
                    TxtQualityNotice.Foreground = new SolidColorBrush(Color.FromRgb(255, 159, 10));
                    break;
                default:
                    TxtQualityNotice.Text = "Đang giải mã gốc (Direct Hardware Scanout) mượt mà nhất cho GPU/CPU";
                    TxtQualityNotice.Foreground = new SolidColorBrush(Color.FromRgb(76, 194, 255));
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

            // Đồng bộ Card 2 theo scope đang chọn (Desktop)
            RefreshCard2UIForCurrentScope();

            OnWallpaperStateChanged();
        }

        private void RefreshCard2UIForCurrentScope()
        {
            _isInitializing = true;
            var config = WallpaperManager.Instance.Config;

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
                bool isPlaying = !WallpaperManager.Instance.IsUserPaused;
                BtnPlayPause.Content = isPlaying ? "Tạm dừng" : "Phát tiếp";

                double cov = WallpaperManager.Instance.LastCoverage;
                double cpu = WallpaperManager.Instance.SmoothedCPU;

                if (WallpaperManager.Instance.IsUserPaused)
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(255, 159, 10)); // Vàng cam
                    TxtStatus.Text = "Đang tạm dừng theo yêu cầu của bạn";
                }
                else if (cov >= 90.0 && WallpaperManager.Instance.Config.AutoPause90Enabled)
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(50, 215, 75)); // Xanh lá
                    TxtStatus.Text = $"Đang dừng tiết kiệm điện (Cửa sổ che {cov:F0}% màn hình • 0% CPU)";
                }
                else
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(76, 194, 255)); // Xanh dương
                    TxtStatus.Text = $"Đang phát mượt mà • Che phủ {cov:F0}% • Tải CPU: {cpu:F1}%";
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
        }

        private void Scope_Checked(object sender, RoutedEventArgs e)
        {
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
