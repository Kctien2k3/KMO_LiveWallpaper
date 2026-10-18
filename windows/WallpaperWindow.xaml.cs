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

        private int _resolutionMode = 2; // 0: 1080p, 1: 2K, 2: 4K
        private int _nativeVideoWidth = 0;
        private int _nativeVideoHeight = 0;

        public event Action<int, int, TimeSpan>? VideoOpened;

        public bool IsPlaying => _isPlaying;
        public int NativeVideoWidth => _nativeVideoWidth;
        public int NativeVideoHeight => _nativeVideoHeight;
        public TimeSpan VideoDuration => Player.NaturalDuration.HasTimeSpan ? Player.NaturalDuration.TimeSpan : TimeSpan.Zero;

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

        public void PauseVideo()
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

        public void SetResolutionMode(int mode)
        {
            _resolutionMode = Math.Max(0, Math.Min(2, mode));
            ApplyResolutionLayout();

            // Hiệu ứng chuyển cảnh mượt mà xác nhận chế độ phân giải mới đã kích hoạt
            try
            {
                var anim = new System.Windows.Media.Animation.DoubleAnimation(0.75, 1.0, TimeSpan.FromMilliseconds(200));
                Player.BeginAnimation(UIElement.OpacityProperty, anim);
            }
            catch { }
        }

        private void ApplyResolutionLayout()
        {
            int targetW, targetH;
            switch (_resolutionMode)
            {
                case 0:
                    targetW = 1920;
                    targetH = 1080;
                    RenderOptions.SetBitmapScalingMode(Player, BitmapScalingMode.LowQuality);
                    RenderOptions.SetBitmapScalingMode(PlayerViewbox, BitmapScalingMode.LowQuality);
                    break;
                case 1:
                    targetW = 2560;
                    targetH = 1440;
                    RenderOptions.SetBitmapScalingMode(Player, BitmapScalingMode.Linear);
                    RenderOptions.SetBitmapScalingMode(PlayerViewbox, BitmapScalingMode.Linear);
                    break;
                default:
                    targetW = _nativeVideoWidth > 0 ? _nativeVideoWidth : 3840;
                    targetH = _nativeVideoHeight > 0 ? _nativeVideoHeight : 2160;
                    RenderOptions.SetBitmapScalingMode(Player, BitmapScalingMode.HighQuality);
                    RenderOptions.SetBitmapScalingMode(PlayerViewbox, BitmapScalingMode.HighQuality);
                    break;
            }

            if (PlayerContainer != null)
            {
                PlayerContainer.Width = targetW;
                PlayerContainer.Height = targetH;
                App.Log($"[WallpaperWindow] SetResolutionMode: {_resolutionMode} -> Container={targetW}x{targetH}, ScalingMode={RenderOptions.GetBitmapScalingMode(Player)}");
            }

            ApplyTransform(_zoom, _offsetX, _offsetY);
        }

        public void ApplyTransform(double zoom, double offsetX, double offsetY)
        {
            _zoom = Math.Max(0.5, Math.Min(2.0, zoom));
            _offsetX = offsetX;
            _offsetY = offsetY;

            double w = (PlayerContainer != null && PlayerContainer.Width > 0) ? PlayerContainer.Width : Width;
            double h = (PlayerContainer != null && PlayerContainer.Height > 0) ? PlayerContainer.Height : Height;

            var transformGroup = new TransformGroup();
            transformGroup.Children.Add(new ScaleTransform(_zoom, _zoom, w / 2.0, h / 2.0));
            transformGroup.Children.Add(new TranslateTransform(_offsetX, _offsetY));
            Player.RenderTransform = transformGroup;
        }

        public void AutoFitScreen(Screen screen)
        {
            Left = screen.Bounds.Left;
            Top = screen.Bounds.Top;
            Width = screen.Bounds.Width;
            Height = screen.Bounds.Height;
            ApplyResolutionLayout();

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
            _nativeVideoWidth = Player.NaturalVideoWidth;
            _nativeVideoHeight = Player.NaturalVideoHeight;
            var duration = Player.NaturalDuration.HasTimeSpan ? Player.NaturalDuration.TimeSpan : TimeSpan.Zero;
            App.Log($"[WallpaperWindow] MediaOpened successfully: Duration={duration}, Video={_nativeVideoWidth}x{_nativeVideoHeight}");
            _isPlaying = true;
            ApplyResolutionLayout();
            VideoOpened?.Invoke(_nativeVideoWidth, _nativeVideoHeight, duration);
        }

        private void Player_MediaEnded(object sender, RoutedEventArgs e)
        {
            // Lặp vô tận mượt mà: tua về 0 và tiếp tục phát ngay lập tức theo độ dài của video
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
