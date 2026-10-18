using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace KMO_LiveWallpaper
{
    public static class Win32
    {
        public const uint WM_SPAWN_WORKER = 0x052C;
        public const uint SMTO_NORMAL = 0x0000;
        public const uint SPI_GETWORKAREA = 0x0030;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;

            public int Width => Right - Left;
            public int Height => Bottom - Top;
        }

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr FindWindow(string? lpClassName, string? lpWindowName);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string? className, string? windowTitle);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            IntPtr wParam,
            IntPtr lParam,
            uint fuFlags,
            uint uTimeout,
            out IntPtr lpdwResult);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        public const int GWL_STYLE = -16;
        public const int GWL_EXSTYLE = -20;
        public const uint WS_CHILD = 0x40000000;
        public const uint WS_POPUP = 0x80000000;
        public const uint WS_EX_TRANSPARENT = 0x00000020;
        public const uint WS_EX_TOOLWINDOW = 0x00000080;
        public const uint SWP_NOZORDER = 0x0004;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref RECT pvParam, uint fWinIni);

        [DllImport("psapi.dll")]
        public static extern int EmptyWorkingSet(IntPtr hwProc);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize);

        public static string GetWindowClassName(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return string.Empty;
            var sb = new StringBuilder(256);
            GetClassName(hWnd, sb, 256);
            return sb.ToString();
        }

        /// <summary>
        /// Tìm hoặc tạo WorkerW nằm ngay sau biểu tượng Desktop (SHELLDLL_DefView).
        /// </summary>
        public static IntPtr GetDesktopWorkerW()
        {
            IntPtr progman = FindWindow("Progman", null);
            if (progman == IntPtr.Zero)
            {
                progman = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Progman", null);
            }

            if (progman != IntPtr.Zero)
            {
                SendMessageTimeout(progman, WM_SPAWN_WORKER, new IntPtr(0xD), new IntPtr(0x1), SMTO_NORMAL, 1000, out _);
                SendMessageTimeout(progman, WM_SPAWN_WORKER, IntPtr.Zero, IntPtr.Zero, SMTO_NORMAL, 1000, out _);
            }

            IntPtr workerw = IntPtr.Zero;

            // Tìm WorkerW nằm ngay sau cửa sổ chứa SHELLDLL_DefView
            EnumWindows((toplevelHandle, param) =>
            {
                IntPtr shellView = FindWindowEx(toplevelHandle, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (shellView != IntPtr.Zero)
                {
                    workerw = FindWindowEx(IntPtr.Zero, toplevelHandle, "WorkerW", null);
                }
                return true;
            }, IntPtr.Zero);

            // Fallback: Tìm WorkerW độc lập không chứa SHELLDLL_DefView (WorkerW tầng nền)
            if (workerw == IntPtr.Zero)
            {
                EnumWindows((top, param) =>
                {
                    string cls = GetWindowClassName(top);
                    if (cls == "WorkerW")
                    {
                        IntPtr defView = FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
                        if (defView == IntPtr.Zero)
                        {
                            workerw = top;
                            return false;
                        }
                    }
                    return true;
                }, IntPtr.Zero);
            }

            return workerw != IntPtr.Zero ? workerw : progman;
        }

        public static string GetProcessNameByWindow(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return string.Empty;
            GetWindowThreadProcessId(hWnd, out uint pid);
            if (pid == 0) return string.Empty;
            try
            {
                using var p = Process.GetProcessById((int)pid);
                return p.ProcessName.ToLowerInvariant();
            }
            catch
            {
                return string.Empty;
            }
        }
    }
}
