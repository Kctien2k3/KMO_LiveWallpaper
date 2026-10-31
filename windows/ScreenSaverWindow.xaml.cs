using System;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using KMO_LiveWallpaper.Effects;
using Point = System.Windows.Point;

namespace KMO_LiveWallpaper
{
    public partial class ScreenSaverWindow : Window
    {
        private Point? _initialMousePos;
        private bool _isClosing = false;
        private readonly Screen _screen;
        private double _zoom = 1.0;
        private double _offsetX = 0;
        private double _offsetY = 0;

        public event Action? Dismissed;

        public ScreenSaverWindow(Screen screen)
        {
            InitializeComponent();
            _screen = screen;

            Left = _screen.Bounds.Left;
            Top = _screen.Bounds.Top;
            Width = _screen.Bounds.Width;
            Height = _screen.Bounds.Height;

            Loaded += (s, e) =>
            {
                Activate();
                Focus();
            };

            KeyDown += (s, e) => Dismiss();
            MouseDown += (s, e) => Dismiss();
            MouseMove += OnMouseMove;
        }

        private void OnMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
        {
            var curPos = e.GetPosition(this);
            if (!_initialMousePos.HasValue)
            {
                _initialMousePos = curPos;
                return;
            }

            double dx = Math.Abs(curPos.X - _initialMousePos.Value.X);
            double dy = Math.Abs(curPos.Y - _initialMousePos.Value.Y);
            if (dx > 12 || dy > 12)
            {
                Dismiss();
            }
        }

        public void Dismiss()
        {
            if (_isClosing) return;
            _isClosing = true;

            try
            {
                Player.Stop();
                Player.Close();
            }
            catch { }

            Dismissed?.Invoke();
            Close();
        }

        public void ApplySettings(
            string videoPath,
            int stretchMode,
            double zoom,
            double offsetX,
            double offsetY,
            double contrast,
            double saturation,
            int fpsMode)
        {
            _zoom = zoom;
            _offsetX = offsetX;
            _offsetY = offsetY;

            // Stretch mode: 0: Lấp đầy (UniformToFill), 1: Vừa khít (Uniform), 2: Kéo giãn (Fill)
            Player.Stretch = stretchMode switch
            {
                1 => Stretch.Uniform,
                2 => Stretch.Fill,
                _ => Stretch.UniformToFill
            };

            // FPS Mode
            int targetFps = fpsMode switch
            {
                0 => 30,
                2 => 120,
                _ => 60
            };
            Timeline.SetDesiredFrameRate(this, targetFps);

            // Tối ưu Zero-Copy: Chỉ áp dụng GPU PixelShader khi người dùng thực sự tinh chỉnh màu
            bool needsFilter = Math.Abs(contrast - 1.0) > 0.01 || Math.Abs(saturation - 1.0) > 0.01;
            if (needsFilter && ColorAdjustEffect.IsSupported)
            {
                Player.Effect = new ColorAdjustEffect
                {
                    Contrast = contrast,
                    Saturation = saturation
                };
            }
            else
            {
                Player.Effect = null;
            }

            ApplyTransform();

            if (!string.IsNullOrEmpty(videoPath) && System.IO.File.Exists(videoPath))
            {
                try
                {
                    Player.Source = new Uri(videoPath);
                    Player.Play();
                }
                catch (Exception ex)
                {
                    App.Log($"[ScreenSaverWindow] Play error: {ex.Message}");
                }
            }
        }

        private void ApplyTransform()
        {
            double w = (PlayerContainer != null && PlayerContainer.Width > 0) ? PlayerContainer.Width : Width;
            double h = (PlayerContainer != null && PlayerContainer.Height > 0) ? PlayerContainer.Height : Height;

            var transformGroup = new TransformGroup();
            transformGroup.Children.Add(new ScaleTransform(_zoom, _zoom, w / 2.0, h / 2.0));
            transformGroup.Children.Add(new TranslateTransform(_offsetX, _offsetY));
            Player.RenderTransform = transformGroup;
        }

        private void Player_MediaOpened(object sender, RoutedEventArgs e)
        {
            ApplyTransform();
            Player.Play();
        }

        private void Player_MediaEnded(object sender, RoutedEventArgs e)
        {
            try
            {
                Player.Position = TimeSpan.Zero;
                Player.Play();
            }
            catch { }
        }
    }
}
