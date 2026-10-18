using System;
using System.Diagnostics;
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
        private static EventWaitHandle? _showEvent;
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

            // Kiểm tra Single Instance
            _mutex = new Mutex(true, "KMO_LiveWallpaper_SingleInstance_Mutex", out bool createdNew);
            _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, "KMO_LiveWallpaper_ShowEvent");

            if (!createdNew)
            {
                Log("Another instance already running. Signaling window to show.");
                _showEvent.Set();
                Shutdown();
                return;
            }

            // Lắng nghe sự kiện để kích hoạt cửa sổ khi người dùng bấm lại icon app ngoài Desktop
            var showListener = new Thread(() =>
            {
                while (true)
                {
                    if (_showEvent.WaitOne())
                    {
                        Dispatcher.Invoke(() =>
                        {
                            ShowMainWindow();
                        });
                    }
                }
            })
            {
                IsBackground = true
            };
            showListener.Start();

            Log("Mutex acquired. Setting up Tray Icon...");
            SetupTrayIcon();

            Log("Creating MainWindow...");
            _mainWindow = new MainWindow();

            Log("Initializing displays...");
            WallpaperManager.Instance.InitializeDisplays();

            Log("Showing MainWindow...");
            ShowMainWindow();
            Log("Startup complete.");
        }

        private void SetupTrayIcon()
        {
            Icon icon = SystemIcons.Application;
            try
            {
                string icoPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
                if (System.IO.File.Exists(icoPath))
                {
                    icon = new Icon(icoPath);
                }
                else
                {
                    string exePath = Process.GetCurrentProcess().MainModule?.FileName ?? "";
                    var extracted = Icon.ExtractAssociatedIcon(exePath);
                    if (extracted != null) icon = extracted;
                }
            }
            catch {}

            _trayIcon = new NotifyIcon
            {
                Icon = icon,
                Text = "KMO Live Wallpaper",
                Visible = true
            };

            var contextMenu = new ContextMenuStrip();

            var openItem = new ToolStripMenuItem("Mở KMO Live Wallpaper");
            openItem.Font = new System.Drawing.Font(openItem.Font, System.Drawing.FontStyle.Bold);
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

            var exitItem = new ToolStripMenuItem("Thoát ứng dụng");
            exitItem.Click += (s, e) => ExitApplication();
            contextMenu.Items.Add(exitItem);

            _trayIcon.ContextMenuStrip = contextMenu;
            _trayIcon.DoubleClick += (s, e) => ShowMainWindow();
        }

        public void ShowMainWindow()
        {
            if (_mainWindow == null)
            {
                _mainWindow = new MainWindow();
            }
            if (!_mainWindow.IsVisible)
            {
                _mainWindow.Show();
            }
            _mainWindow.WindowState = WindowState.Normal;
            _mainWindow.Activate();
            _mainWindow.Topmost = true;
            _mainWindow.Topmost = false;
            _mainWindow.Focus();
        }

        public void ExitApplication()
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
            try { _showEvent?.Dispose(); } catch {}
            base.OnExit(e);
        }
    }
}
