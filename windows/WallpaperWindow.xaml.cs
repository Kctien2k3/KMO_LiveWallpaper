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
            App.Log($"[WallpaperWindow] HWND={_hWnd}, WorkerW={workerW}");

            if (workerW != IntPtr.Zero)
            {
                int style = Win32.GetWindowLong(_hWnd, Win32.GWL_STYLE);
                style &= unchecked((int)~Win32.WS_POPUP);
                style |= (int)Win32.WS_CHILD;
                Win32.SetWindowLong(_hWnd, Win32.GWL_STYLE, style);

                IntPtr prevParent = Win32.SetParent(_hWnd, workerW);
                App.Log($"[WallpaperWindow] SetParent done, prevParent={prevParent}");

                Win32.SetWindowPos(
                    _hWnd,
                    IntPtr.Zero,
                    _screen.Bounds.Left,
                    _screen.Bounds.Top,
                    _screen.Bounds.Width,
                    _screen.Bounds.Height,
                    Win32.SWP_NOZORDER | Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW
                );
            }
        }

        public void LoadVideo(string filePath)
        {
            if (string.IsNullOrEmpty(filePath) || !System.IO.File.Exists(filePath))
            {
                App.Log($"[WallpaperWindow] LoadVideo skipped: file does not exist ({filePath})");
                return;
            }

            App.Log($"[WallpaperWindow] LoadVideo: {filePath}");
            try
            {
                Player.Source = new Uri(filePath);
                Player.Play();
                _isPlaying = true;
            }
            catch (Exception ex)
            {
                App.Log($"[WallpaperWindow] LoadVideo error: {ex.Message}");
            }
        }

        public void PlayVideo()
        {
            if (!_isPlaying)
            {
                try
                {
                    Player.Play();
                    _isPlaying = true;
                }
                catch (Exception ex)
                {
                    App.Log($"[WallpaperWindow] PlayVideo error: {ex.Message}");
                }
            }
        }

        public void PauseVideo()
        {
            if (_isPlaying)
            {
                try
                {
                    Player.Pause();
                    _isPlaying = false;
                }
                catch (Exception ex)
                {
                    App.Log($"[WallpaperWindow] PauseVideo error: {ex.Message}");
                }
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

            if (_hWnd != IntPtr.Zero)
            {
                Win32.SetWindowPos(
                    _hWnd,
                    IntPtr.Zero,
                    screen.Bounds.Left,
                    screen.Bounds.Top,
                    screen.Bounds.Width,
                    screen.Bounds.Height,
                    Win32.SWP_NOZORDER | Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW
                );
            }
        }

        private void Player_MediaOpened(object sender, RoutedEventArgs e)
        {
            App.Log($"[WallpaperWindow] MediaOpened successfully: Duration={Player.NaturalDuration}, Video={Player.NaturalVideoWidth}x{Player.NaturalVideoHeight}");
            _isPlaying = true;
        }

        private void Player_MediaEnded(object sender, RoutedEventArgs e)
        {
            // Lặp vô tận mượt mà: tua về 0 và tiếp tục phát
            try
            {
                Player.Position = TimeSpan.Zero;
                Player.Play();
                _isPlaying = true;
            }
            catch (Exception ex)
            {
                App.Log($"[WallpaperWindow] Loop replay error: {ex.Message}");
            }
        }

        private void Player_MediaFailed(object? sender, ExceptionRoutedEventArgs e)
        {
            App.Log($"[WallpaperWindow] MediaFailed: {e.ErrorException?.Message}");
            _isPlaying = false;
        }
    }
}
