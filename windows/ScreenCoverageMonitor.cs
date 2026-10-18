using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows.Forms;

namespace KMO_LiveWallpaper
{
    public class ScreenCoverageMonitor
    {
        private static readonly string[] ProEditorKeywords =
        {
            "photoshop", "premiere", "afterfx", "illustrator", "audition", "mediaencoder", "lightroom",
            "davinci", "resolve", "blackmagic", "capcut", "blender", "cinema4d", "maya", "houdini",
            "unreal", "unity", "figma", "canva", "handbrake", "obs64"
        };

        private static readonly HashSet<string> IgnoredProcesses = new(StringComparer.OrdinalIgnoreCase)
        {
            "kmo_livewallpaper",
            "explorer",
            "nvidia share",
            "nvcontainer",
            "geforceexperience",
            "nvspcaps64",
            "gamebar",
            "xboxgamebar",
            "gamebarpresencewriter",
            "gamebarftserver",
            "rtss",
            "overwolf",
            "discordhookhelper",
            "discordhookhelper64"
        };

        private static readonly HashSet<string> IgnoredWindowClasses = new(StringComparer.OrdinalIgnoreCase)
        {
            "Progman",
            "WorkerW",
            "Shell_TrayWnd",
            "Shell_SecondaryTrayWnd",
            "Windows.UI.Core.CoreWindow",
            "ImmersiveLauncher",
            "XamlExplorerHostIslandWindow",
            "EdgeUiInputTopWndClass",
            "Dwm",
            "ApplicationFrameWindow",
            "TopLevelWindowForOverflowXamlIsland",
            "CEF-OSC-WIDGET",
            "DirectX",
            "NvWrapperWndClass"
        };

        public static bool IsProEditorOrHeavyAppActive()
        {
            try
            {
                IntPtr fg = Win32.GetForegroundWindow();
                if (fg == IntPtr.Zero) return false;

                string procName = Win32.GetProcessNameByWindow(fg);
                if (string.IsNullOrEmpty(procName)) return false;
                if (procName == "explorer" || procName == "kmo_livewallpaper") return false;

                foreach (var kw in ProEditorKeywords)
                {
                    if (procName.Contains(kw, StringComparison.OrdinalIgnoreCase))
                        return true;
                }
            }
            catch { }
            return false;
        }

        /// <summary>
        /// Tính chính xác % diện tích vùng làm việc (WorkingArea) bị các cửa sổ ứng dụng khác che phủ.
        /// Bỏ qua hoàn toàn Desktop, Taskbar, WorkerW, lớp phủ trong suốt (Overlay), cửa sổ cloaked và cửa sổ của chính ứng dụng.
        /// </summary>
        public static double CalculateScreenCoveragePercent(Screen screen)
        {
            try
            {
                var bounds = screen.WorkingArea;
                if (bounds.Width <= 0 || bounds.Height <= 0)
                {
                    bounds = screen.Bounds;
                }

                double totalArea = (double)bounds.Width * bounds.Height;
                if (totalArea <= 0) return 0.0;

                int myPid = Process.GetCurrentProcess().Id;

                List<Win32.RECT> visibleRects = new();
                double maxSingleRatio = 0.0;

                Win32.EnumWindows((hWnd, lParam) =>
                {
                    if (!Win32.IsWindowVisible(hWnd) || Win32.IsIconic(hWnd)) return true;

                    // Bỏ qua cửa sổ ẩn/cloaked (ví dụ ở Virtual Desktop khác hoặc Windows Store app đang treo)
                    if (Win32.IsWindowCloaked(hWnd)) return true;

                    Win32.GetWindowThreadProcessId(hWnd, out uint pid);
                    if (pid == myPid) return true;

                    // Lọc bỏ overlay trong suốt (WS_EX_TRANSPARENT) và ToolWindow không phải AppWindow
                    int exStyle = Win32.GetWindowLong(hWnd, Win32.GWL_EXSTYLE);
                    if ((exStyle & Win32.WS_EX_TRANSPARENT) != 0) return true;
                    if ((exStyle & Win32.WS_EX_TOOLWINDOW) != 0 && (exStyle & Win32.WS_EX_APPWINDOW) == 0) return true;

                    string cls = Win32.GetWindowClassName(hWnd);
                    if (IgnoredWindowClasses.Contains(cls)) return true;

                    string procName = Win32.GetProcessNameByWindow(hWnd);
                    if (IgnoredProcesses.Contains(procName)) return true;

                    if (Win32.GetWindowRect(hWnd, out Win32.RECT r))
                    {
                        // Lọc bỏ cửa sổ thu nhỏ ngoài màn hình hoặc quá nhỏ (< 80px)
                        if (r.Left <= -10000 || r.Top <= -10000) return true;
                        if (r.Width < 80 || r.Height < 80) return true;

                        // Tính phần giao nhau giữa cửa sổ và vùng làm việc hiện tại
                        int ix1 = Math.Max(bounds.Left, r.Left);
                        int iy1 = Math.Max(bounds.Top, r.Top);
                        int ix2 = Math.Min(bounds.Right, r.Right);
                        int iy2 = Math.Min(bounds.Bottom, r.Bottom);

                        if (ix2 > ix1 && iy2 > iy1)
                        {
                            double interArea = (double)(ix2 - ix1) * (iy2 - iy1);
                            double ratio = (interArea / totalArea) * 100.0;

                            if (ratio > maxSingleRatio)
                                maxSingleRatio = ratio;

                            visibleRects.Add(new Win32.RECT { Left = ix1, Top = iy1, Right = ix2, Bottom = iy2 });
                        }
                    }
                    return true;
                }, IntPtr.Zero);

                if (visibleRects.Count == 0) return 0.0;
                if (visibleRects.Count == 1) return Math.Min(100.0, maxSingleRatio);

                // Đo chính xác bằng lưới mẫu 20x15 tránh tính trùng lặp khi nhiều cửa sổ đè lên nhau
                int cols = 20;
                int rows = 15;
                double stepX = (double)bounds.Width / cols;
                double stepY = (double)bounds.Height / rows;
                int coveredCells = 0;

                for (int r = 0; r < rows; r++)
                {
                    double py = bounds.Top + (r + 0.5) * stepY;
                    for (int c = 0; c < cols; c++)
                    {
                        double px = bounds.Left + (c + 0.5) * stepX;
                        foreach (var rect in visibleRects)
                        {
                            if (px >= rect.Left && px <= rect.Right && py >= rect.Top && py <= rect.Bottom)
                            {
                                coveredCells++;
                                break;
                            }
                        }
                    }
                }

                double unionRatio = ((double)coveredCells / (cols * rows)) * 100.0;
                return Math.Min(100.0, Math.Max(maxSingleRatio, unionRatio));
            }
            catch
            {
                return 0.0;
            }
        }
    }
}
