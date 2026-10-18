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

        public MainWindow()
        {
            App.Log("[MainWindow] Constructor start");
            InitializeComponent();
            LoadAppAssets();
            SyncUIFromConfig();
            _isInitializing = false;

            WallpaperManager.Instance.StateChanged += OnWallpaperStateChanged;
            Closing += OnWindowClosing;
            Loaded += (s, e) => App.Log("[MainWindow] Event: Loaded");
            App.Log("[MainWindow] Constructor complete");
        }

        private void LoadAppAssets()
        {
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string icoPath = Path.Combine(baseDir, "app.ico");
                if (File.Exists(icoPath))
                {
                    Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri(icoPath));
                }

                string pngPath = Path.Combine(baseDir, "app.png");
                if (File.Exists(pngPath))
                {
                    ImgLogo.Source = new System.Windows.Media.Imaging.BitmapImage(new Uri(pngPath));
                }
            }
            catch (Exception ex)
            {
                App.Log($"[MainWindow] LoadAppAssets notice: {ex.Message}");
            }
        }

        private void SyncUIFromConfig()
        {
            var cfg = WallpaperManager.Instance.Config;
            TxtVideoName.Text = string.IsNullOrEmpty(cfg.VideoPath) ? "Chưa chọn video" : Path.GetFileName(cfg.VideoPath);

            // Stretch mode
            RbFill.IsChecked = (cfg.StretchMode == 0);
            RbUniform.IsChecked = (cfg.StretchMode == 1);
            RbStretch.IsChecked = (cfg.StretchMode == 2);

            // Sliders
            SliderZoom.Value = cfg.ZoomScale * 100.0;
            TxtZoomVal.Text = $"{(int)Math.Round(SliderZoom.Value)}%";

            SliderOffsetX.Value = cfg.OffsetX;
            TxtOffsetXVal.Text = $"{(int)Math.Round(SliderOffsetX.Value)}";

            SliderOffsetY.Value = cfg.OffsetY;
            TxtOffsetYVal.Text = $"{(int)Math.Round(SliderOffsetY.Value)}";

            // Toggles
            CbAutoPause90.IsChecked = cfg.AutoPause90Enabled;
            CbCeiling.IsChecked = cfg.CeilingEnabled;
            CbAutoLaunchStartup.IsChecked = WallpaperManager.Instance.IsAutoLaunchStartupEnabled();
            CbMute.IsChecked = cfg.IsMuted;

            // Resolution
            Rb1080p.IsChecked = (cfg.ResolutionMode == 0);
            Rb2k.IsChecked = (cfg.ResolutionMode == 1);
            Rb4k.IsChecked = (cfg.ResolutionMode == 2);
        }

        private void OnWallpaperStateChanged()
        {
            Dispatcher.Invoke(() =>
            {
                double cov = WallpaperManager.Instance.LastCoverage;
                bool paused = WallpaperManager.Instance.IsUserPaused;

                double ramMB = 0;
                try
                {
                    using var p = Process.GetCurrentProcess();
                    ramMB = p.WorkingSet64 / (1024.0 * 1024.0);
                }
                catch { }

                if (paused)
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(255, 149, 0));
                    TxtStatus.Text = $"Tạm dừng thủ công • RAM {ramMB:F0} MB";
                    BtnPlayPause.Content = "Phát tiếp";
                }
                else if (cov >= 90.0)
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(150, 150, 150));
                    TxtStatus.Text = $"Đã dừng (Che {(int)Math.Round(cov)}% > 90%) • RAM {ramMB:F0} MB";
                    BtnPlayPause.Content = "Tạm dừng";
                }
                else
                {
                    DotStatus.Fill = new SolidColorBrush(Color.FromRgb(76, 194, 255));
                    TxtStatus.Text = $"Đang phát (Che {(int)Math.Round(cov)}%) • RAM {ramMB:F0} MB";
                    BtnPlayPause.Content = "Tạm dừng";
                }
            });
        }

        private void BtnChooseVideo_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog
            {
                Title = "Chọn Video Hình Nền",
                Filter = "Video Files (*.mp4;*.mov;*.wmv;*.mkv)|*.mp4;*.mov;*.wmv;*.mkv|All Files (*.*)|*.*"
            };

            if (dlg.ShowDialog() == true)
            {
                WallpaperManager.Instance.LoadVideo(dlg.FileName);
                TxtVideoName.Text = Path.GetFileName(dlg.FileName);
            }
        }

        private void Resolution_Checked(object sender, RoutedEventArgs e)
        {
            if (_isInitializing) return;
            int mode = 2;
            if (Rb1080p.IsChecked == true) mode = 0;
            else if (Rb2k.IsChecked == true) mode = 1;

            WallpaperManager.Instance.Config.ResolutionMode = mode;
            WallpaperManager.Instance.SaveConfig();
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

        private void ApplyCurrentTransform(int stretchMode)
        {
            double zoom = SliderZoom.Value / 100.0;
            double ox = SliderOffsetX.Value;
            double oy = SliderOffsetY.Value;
            WallpaperManager.Instance.SetDisplayTransform(stretchMode, zoom, ox, oy);
        }

        private void BtnReset_Click(object sender, RoutedEventArgs e)
        {
            _isInitializing = true;
            RbFill.IsChecked = true;
            SliderZoom.Value = 100;
            SliderOffsetX.Value = 0;
            SliderOffsetY.Value = 0;
            TxtZoomVal.Text = "100%";
            TxtOffsetXVal.Text = "0";
            TxtOffsetYVal.Text = "0";
            _isInitializing = false;

            ApplyCurrentTransform(0);
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

        public void UpdateStartupCheckbox(bool isChecked)
        {
            _isInitializing = true;
            CbAutoLaunchStartup.IsChecked = isChecked;
            _isInitializing = false;
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
