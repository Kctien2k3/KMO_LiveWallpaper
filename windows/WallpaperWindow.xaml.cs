using System;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Interop;
using System.Windows.Media;

namespace KMO_LiveWallpaper
{
    public partial class WallpaperWindow : Window
    {
        private readonly Screen _screen;
        private IntPtr _hWnd = IntPtr.Zero;
        private bool _isPlaying = false;
        private double _zoom = 1.0;
        private double _offsetX = 0;
        private double _offsetY = 0;

        public bool IsPlaying => _isPlaying;

        public WallpaperWindow(Screen screen)
        {
            InitializeComponent();
            _screen = screen;

            // Đặt kích thước và toạ độ khớp chính xác với màn hình (MacBook, TV hoặc Màn hình ngoài)
            Left = _screen.Bounds.Left;
            Top = _screen.Bounds.Top;
            Width = _screen.Bounds.Width;
            Height = _screen.Bounds.Height;

            SourceInitialized += OnSourceInitialized;
        }

        private void OnSourceInitialized(object? sender, EventArgs e)
        {
            var helper = new WindowInteropHelper(this);
            _hWnd = helper.Handle;

            // Ghim cửa sổ này xuống tầng WorkerW (nằm sau toàn bộ biểu tượng Desktop)
            IntPtr workerW = Win32.GetDesktopWorkerW();
            if (workerW != IntPtr.Zero)
            {
                Win32.SetParent(_hWnd, workerW);
            }
        }

        public void LoadVideo(string filePath)
        {
            if (string.IsNullOrEmpty(filePath) || !System.IO.File.Exists(filePath)) return;

            Player.Source = new Uri(filePath);
            Player.Play();
            _isPlaying = true;
        }

        public void PlayVideo()
        {
            if (!_isPlaying)
            {
                Player.Play();
                _isPlaying = true;
            }
        }

        public void PauseVideo()
        {
            if (_isPlaying)
            {
                Player.Pause();
                _isPlaying = false;
            }
        }

        public void SetMuted(bool isMuted)
        {
            Player.IsMuted = isMuted;
        }

        public void SetStretchMode(int mode)
        {
            // 0: Lấp đầy (UniformToFill), 1: Vừa khít (Uniform), 2: Kéo giãn (Fill)
            Player.Stretch = mode switch
            {
                1 => Stretch.Uniform,
                2 => Stretch.Fill,
                _ => Stretch.UniformToFill
            };
        }

        public void ApplyTransform(double zoom, double offsetX, double offsetY)
        {
            _zoom = Math.Max(0.5, Math.Min(2.0, zoom));
            _offsetX = offsetX;
            _offsetY = offsetY;

            var transformGroup = new TransformGroup();
            transformGroup.Children.Add(new ScaleTransform(_zoom, _zoom, Width / 2.0, Height / 2.0));
            transformGroup.Children.Add(new TranslateTransform(_offsetX, _offsetY));
            Player.RenderTransform = transformGroup;
        }

        public void AutoFitScreen(Screen screen)
        {
            Left = screen.Bounds.Left;
            Top = screen.Bounds.Top;
            Width = screen.Bounds.Width;
            Height = screen.Bounds.Height;
            ApplyTransform(_zoom, _offsetX, _offsetY);
        }

        private void Player_MediaEnded(object sender, RoutedEventArgs e)
        {
            // Lặp vô tận mượt mà: tua về 0 và tiếp tục phát
            Player.Position = TimeSpan.Zero;
            Player.Play();
            _isPlaying = true;
        }

        private void Player_MediaFailed(object? sender, ExceptionRoutedEventArgs e)
        {
            _isPlaying = false;
        }
    }
}
