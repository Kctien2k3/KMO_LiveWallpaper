using System;
using System.Drawing;
using System.Threading;
using System.Windows;
using System.Windows.Forms;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;

namespace KMO_LiveWallpaper
{
    public partial class App : Application
    {
        private static Mutex? _mutex;
        private NotifyIcon? _trayIcon;
        private MainWindow? _mainWindow;

        private static readonly string LogPath = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "KMO_LiveWallpaper", "app.log");

        public static void Log(string msg)
        {
            try { System.IO.File.AppendAllText(LogPath, $"[{DateTime.Now:HH:mm:ss.fff}] {msg}\r\n"); } catch {}
        }

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            AppDomain.CurrentDomain.UnhandledException += (s, args) =>
            {
                Log($"[CRASH AppDomain] {args.ExceptionObject}");
            };

            DispatcherUnhandledException += (s, args) =>
            {
                Log($"[CRASH Dispatcher] {args.Exception}");
                args.Handled = true;
            };

            Log("Application starting...");

            // Kiểm tra Single Instance (chỉ cho phép 1 app chạy duy nhất)
            _mutex = new Mutex(true, "KMO_LiveWallpaper_SingleInstance_Mutex", out bool createdNew);
            if (!createdNew)
            {
                Log("Another instance already running. Exiting.");
                MessageBox.Show("Ứng dụng KMO_LiveWallpaper đang chạy trong khay hệ thống!", "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
                Shutdown();
                return;
            }

            Log("Mutex acquired. Setting up Tray Icon...");
            // Khởi tạo khay hệ thống (System Tray Icon)
            SetupTrayIcon();

            Log("Creating MainWindow...");
            // Khởi tạo cửa sổ cài đặt
            _mainWindow = new MainWindow();

            Log("Initializing displays...");
            // Khởi động các màn hình hiển thị video
            WallpaperManager.Instance.InitializeDisplays();

            Log("Showing MainWindow...");
            // Hiển thị cửa sổ cài đặt lần đầu
            _mainWindow.Show();
            Log("Startup complete.");
        }

        private void SetupTrayIcon()
        {
            _trayIcon = new NotifyIcon
            {
                Icon = SystemIcons.Application,
                Text = "KMO_LiveWallpaper",
                Visible = true
            };

            var contextMenu = new ContextMenuStrip();

            var openItem = new ToolStripMenuItem("Mở cài đặt...");
            openItem.Click += (s, e) => ShowMainWindow();
            contextMenu.Items.Add(openItem);

            var chooseItem = new ToolStripMenuItem("Chọn video...");
            chooseItem.Click += (s, e) =>
            {
                var dlg = new Microsoft.Win32.OpenFileDialog
                {
                    Title = "Chọn Video Hình Nền",
                    Filter = "Video Files (*.mp4;*.mov;*.wmv;*.mkv)|*.mp4;*.mov;*.wmv;*.mkv|All Files (*.*)|*.*"
                };
                if (dlg.ShowDialog() == true)
                {
                    WallpaperManager.Instance.LoadVideo(dlg.FileName);
                }
            };
            contextMenu.Items.Add(chooseItem);

            contextMenu.Items.Add(new ToolStripSeparator());

            var autoPauseItem = new ToolStripMenuItem("Tự dừng khi cửa sổ đạt trên 90% màn hình")
            {
                Checked = WallpaperManager.Instance.Config.AutoPause90Enabled,
                CheckOnClick = true
            };
            autoPauseItem.Click += (s, e) =>
            {
                WallpaperManager.Instance.SetAutoPause90(autoPauseItem.Checked);
            };
            contextMenu.Items.Add(autoPauseItem);

            var ceilingItem = new ToolStripMenuItem("Giới hạn trần (≤ 5% CPU • ≤ 80MB RAM)")
            {
                Checked = WallpaperManager.Instance.Config.CeilingEnabled,
                CheckOnClick = true
            };
            ceilingItem.Click += (s, e) =>
            {
                WallpaperManager.Instance.SetCeilingEnabled(ceilingItem.Checked);
            };
            contextMenu.Items.Add(ceilingItem);

            contextMenu.Items.Add(new ToolStripSeparator());

            var playPauseItem = new ToolStripMenuItem("Tạm dừng / Phát tiếp");
            playPauseItem.Click += (s, e) => WallpaperManager.Instance.TogglePlayPause();
            contextMenu.Items.Add(playPauseItem);

            var exitItem = new ToolStripMenuItem("Thoát");
            exitItem.Click += (s, e) => ExitApplication();
            contextMenu.Items.Add(exitItem);

            _trayIcon.ContextMenuStrip = contextMenu;
            _trayIcon.DoubleClick += (s, e) => ShowMainWindow();
        }

        private void ShowMainWindow()
        {
            if (_mainWindow == null)
            {
                _mainWindow = new MainWindow();
            }
            _mainWindow.Show();
            _mainWindow.WindowState = WindowState.Normal;
            _mainWindow.Activate();
        }

        private void ExitApplication()
        {
            if (_trayIcon != null)
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
                _trayIcon = null;
            }

            WallpaperManager.Instance.Shutdown();
            Shutdown();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            Log($"Application exiting with code {e.ApplicationExitCode}");
            try { _mutex?.ReleaseMutex(); } catch {}
            try { _mutex?.Dispose(); } catch {}
            base.OnExit(e);
        }
    }
}
