import Cocoa
import AVFoundation
import CoreVideo
import QuartzCore
import CoreImage
import UniformTypeIdentifiers
import ServiceManagement

class WallpaperAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var controlWindow: NSWindow?

    // Kiến trúc Single-Engine cố định: Khởi tạo 1 lần duy nhất, KHÔNG BAO GIỜ hủy/tạo lại cửa sổ hay AVPlayer để chống chớp màn hình 120Hz ProMotion và không đẻ tiến trình phụ
    var desktopWindows: [NSWindow] = []
    var centerSensors: [NSWindow] = []
    var cornerSensors: [NSWindow] = []
    var playerLayers: [AVPlayerLayer] = []
    var players: [AVPlayer] = []
    var endObservers: [NSObjectProtocol] = []
    var ceilingTimer: Timer?

    // Mức trần lý tưởng All-in-One: <= 8% CPU & <= 80MB RAM
    let maxCPUPercent: Double = 8.0
    let maxMemoryMB: Double = 80.0
    var ceilingEnabled: Bool = true
    var pausedByCeiling: Bool = false
    var graceUntil: Date = .distantPast
    var overLimitStreak: Int = 0
    var smoothedCPU: Double = 1.2

    // Cài đặt hiển thị & tiết kiệm năng lượng (Chỉ giữ mốc chuẩn: Tự dừng khi cửa sổ che trên 90% màn hình)
    var autoPause90Enabled: Bool = true
    let autoPauseThreshold: Double = 90.0
    var lastCoveragePercent: Double = 0.0
    var previewingGeometryUntil: Date = .distantPast
    var stateEvalWorkItem: DispatchWorkItem?
    var pauseDebounceWorkItem: DispatchWorkItem?
    var heavySysLoadStreak: Int = 0
    var userPaused: Bool = false
    var isMuted: Bool = true
    var isDisplayAsleep: Bool = false
    var isScreenLocked: Bool = false
    var isScreenSaverRunning: Bool = false
    var isScreenAsleep: Bool {
        return isDisplayAsleep || isScreenLocked || isScreenSaverRunning
    }
    var gravityMode: Int = 0     // 0: Lấp đầy, 1: Vừa khít, 2: Kéo giãn
    var zoomScale: CGFloat = 1.0
    var offsetX: CGFloat = 0.0
    var offsetY: CGFloat = 0.0
    var resolutionMode: Int = 2  // 0: 1080p, 1: 2K QHD, 2: 4K Gốc
    var fpsMode: Int = 1         // 0: 30 FPS, 1: 60 FPS, 2: 120 FPS

    // Giao diện macOS System Settings
    var fileLabel: NSTextField?
    var statusDot: NSView?
    var statusLabel: NSTextField?
    var gravitySegment: NSSegmentedControl?
    var autoPauseSwitch: NSSwitch?
    var resSegment: NSSegmentedControl?
    var fpsSegment: NSSegmentedControl?
    var zoomSlider: NSSlider?
    var zoomValueLabel: NSTextField?
    var offsetXSlider: NSSlider?
    var offsetXValueLabel: NSTextField?
    var offsetYSlider: NSSlider?
    var offsetYValueLabel: NSTextField?
    var ceilingSwitch: NSSwitch?
    var muteSwitch: NSSwitch?
    var launchAtLoginSwitch: NSSwitch?
    var playPauseBtn: NSButton?
    var lockScreenSwitch: NSSwitch?
    var screenSaverSwitch: NSSwitch?

    // Bộ lọc màu sắc (Khắc phục QuickTime Gamma Shift, tinh chỉnh khớp VLC tự nhiên)
    var contrastValue: Float = 1.05   // 0.80 - 1.30, mặc định 1.05 (chuẩn tự nhiên khớp VLC)
    var saturationValue: Float = 1.05 // 0.50 - 1.50, mặc định 1.05 (chuẩn tự nhiên khớp VLC)
    var contrastSlider: NSSlider?
    var contrastValueLabel: NSTextField?
    var saturationSlider: NSSlider?
    var saturationValueLabel: NSTextField?

    // Quản lý hiển thị riêng biệt & Đồng bộ Màn hình khóa / Trình bảo vệ màn hình
    var syncLockScreenSettings: Bool = true // Mặc định: Tự động đồng bộ với màn hình chính
    var lockGravityMode: Int = 0
    var lockZoomScale: CGFloat = 1.0
    var lockOffsetX: CGFloat = 0.0
    var lockOffsetY: CGFloat = 0.0
    var lockContrastValue: Float = 1.05
    var lockSaturationValue: Float = 1.05
    var currentScopeIndex: Int = 0 // 0: Màn hình chính, 1: Màn hình khóa & Chờ

    var scopeSegment: NSSegmentedControl?
    var scopeHintLabel: NSTextField?
    var syncLockScreenSwitch: NSSwitch?

    let savedSyncLockKey = "SavedSyncLockScreenSettingsV1"
    let savedLockGravityKey = "SavedLockGravityMode"
    let savedLockZoomKey = "SavedLockZoomScale"
    let savedLockOffsetXKey = "SavedLockOffsetX"
    let savedLockOffsetYKey = "SavedLockOffsetY"
    let savedLockContrastKey = "SavedLockContrastValueV1"
    let savedLockSaturationKey = "SavedLockSaturationValueV1"

    // Thanh Menu Bar
    var menuAutoPause90Item: NSMenuItem!
    var menuCeilingItem: NSMenuItem!
    var menuLaunchAtLoginItem: NSMenuItem!
    var menuStatusItem: NSMenuItem!

    let savedVideoKey = "SavedWallpaperVideoPath"
    let savedGravityKey = "SavedGravityMode"
    let savedZoomKey = "SavedZoomScale"
    let savedOffsetXKey = "SavedOffsetX"
    let savedOffsetYKey = "SavedOffsetY"
    let savedContrastKey = "SavedContrastValueV1"
    let savedSaturationKey = "SavedSaturationValueV1"
    let savedResKey = "SavedResModeV5"
    let savedFPSKey = "SavedFPSModeV1"
    let savedAutoPause90Key = "SavedAutoPause90EnabledV1"
    let savedCeilingKey = "SavedCeilingEnabled"
    let savedLaunchAtLoginKey = "SavedLaunchAtLoginEnabled"
    var launchAtLoginEnabled: Bool = false

    var cacheDir: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.kmo.KMO_LiveWallpaper")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var defaultBundledVideoURL: URL? {
        if let url = Bundle.main.url(forResource: "default_wallpaper", withExtension: "mp4") {
            return url
        }
        let direct = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/default_wallpaper.mp4")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let devURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("resources/default_wallpaper.mp4")
        if FileManager.default.fileExists(atPath: devURL.path) {
            return devURL
        }
        return nil
    }

    var activeVideoURL: URL? {
        if let savedPath = UserDefaults.standard.string(forKey: savedVideoKey),
           FileManager.default.fileExists(atPath: savedPath) {
            return URL(fileURLWithPath: savedPath)
        }
        return defaultBundledVideoURL
    }

    func currentVideoDisplayName() -> String {
        if let savedPath = UserDefaults.standard.string(forKey: savedVideoKey),
           FileManager.default.fileExists(atPath: savedPath) {
            return (savedPath as NSString).lastPathComponent
        }
        if defaultBundledVideoURL != nil {
            return "Mặc định (4K UHD)"
        }
        return "Chưa chọn video"
    }

    @objc func useDefaultVideo() {
        UserDefaults.standard.removeObject(forKey: savedVideoKey)
        fileLabel?.stringValue = currentVideoDisplayName()
        pausedByCeiling = false
        overLimitStreak = 0
        graceUntil = Date().addingTimeInterval(3.0)
        if let targetURL = activeVideoURL {
            updateResolutionSegments(for: targetURL, setDefaultToMax: true)
            resolveAndLoadVideo(originalURL: targetURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isBackgroundLaunch = ProcessInfo.processInfo.arguments.contains("--background")
        if isBackgroundLaunch {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }

        if UserDefaults.standard.string(forKey: savedVideoKey) == nil,
           let legacyDefaults = UserDefaults(suiteName: "com.antigravity.HinhNenDong"),
           let legacyVideo = legacyDefaults.string(forKey: savedVideoKey) {
            UserDefaults.standard.set(legacyVideo, forKey: savedVideoKey)
        }

        if UserDefaults.standard.object(forKey: savedGravityKey) != nil {
            gravityMode = max(0, min(2, UserDefaults.standard.integer(forKey: savedGravityKey)))
            zoomScale = CGFloat(UserDefaults.standard.double(forKey: savedZoomKey))
            if zoomScale < 0.2 { zoomScale = 1.0 }
            offsetX = CGFloat(UserDefaults.standard.double(forKey: savedOffsetXKey))
            offsetY = CGFloat(UserDefaults.standard.double(forKey: savedOffsetYKey))
        }
        if UserDefaults.standard.object(forKey: savedContrastKey) != nil {
            let val = Float(UserDefaults.standard.double(forKey: savedContrastKey))
            contrastValue = max(0.80, min(1.30, val))
        } else {
            contrastValue = 1.05
        }
        if UserDefaults.standard.object(forKey: savedSaturationKey) != nil {
            let val = Float(UserDefaults.standard.double(forKey: savedSaturationKey))
            saturationValue = max(0.50, min(1.50, val))
        } else {
            saturationValue = 1.05
        }
        if UserDefaults.standard.object(forKey: savedResKey) != nil {
            resolutionMode = max(0, min(2, UserDefaults.standard.integer(forKey: savedResKey)))
        }
        if UserDefaults.standard.object(forKey: savedFPSKey) != nil {
            fpsMode = max(0, min(2, UserDefaults.standard.integer(forKey: savedFPSKey)))
        } else {
            fpsMode = 1 // Mặc định: 60 FPS mượt mà
        }
        if UserDefaults.standard.object(forKey: savedAutoPause90Key) != nil {
            autoPause90Enabled = UserDefaults.standard.bool(forKey: savedAutoPause90Key)
        } else {
            autoPause90Enabled = true // Mặc định: Tự dừng khi cửa sổ che trên 90% màn hình
        }
        if UserDefaults.standard.object(forKey: savedCeilingKey) != nil {
            ceilingEnabled = UserDefaults.standard.bool(forKey: savedCeilingKey)
        } else {
            ceilingEnabled = true
        }

        if UserDefaults.standard.object(forKey: savedSyncLockKey) != nil {
            syncLockScreenSettings = UserDefaults.standard.bool(forKey: savedSyncLockKey)
        } else {
            syncLockScreenSettings = true // Mặc định: tự động đồng bộ kích cỡ & màu với desktop
        }

        if UserDefaults.standard.object(forKey: savedLockGravityKey) != nil {
            lockGravityMode = max(0, min(2, UserDefaults.standard.integer(forKey: savedLockGravityKey)))
        } else {
            lockGravityMode = gravityMode
        }
        if UserDefaults.standard.object(forKey: savedLockZoomKey) != nil {
            lockZoomScale = CGFloat(UserDefaults.standard.double(forKey: savedLockZoomKey))
            if lockZoomScale < 0.2 { lockZoomScale = 1.0 }
        } else {
            lockZoomScale = zoomScale
        }
        if UserDefaults.standard.object(forKey: savedLockOffsetXKey) != nil {
            lockOffsetX = CGFloat(UserDefaults.standard.double(forKey: savedLockOffsetXKey))
        } else {
            lockOffsetX = offsetX
        }
        if UserDefaults.standard.object(forKey: savedLockOffsetYKey) != nil {
            lockOffsetY = CGFloat(UserDefaults.standard.double(forKey: savedLockOffsetYKey))
        } else {
            lockOffsetY = offsetY
        }
        if UserDefaults.standard.object(forKey: savedLockContrastKey) != nil {
            let val = Float(UserDefaults.standard.double(forKey: savedLockContrastKey))
            lockContrastValue = max(0.80, min(1.30, val))
        } else {
            lockContrastValue = contrastValue
        }
        if UserDefaults.standard.object(forKey: savedLockSaturationKey) != nil {
            let val = Float(UserDefaults.standard.double(forKey: savedLockSaturationKey))
            lockSaturationValue = max(0.50, min(1.50, val))
        } else {
            lockSaturationValue = saturationValue
        }

        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentsDir.appendingPathComponent("com.kmo.KMO_LiveWallpaper.plist")
        if FileManager.default.fileExists(atPath: plistURL.path) {
            launchAtLoginEnabled = true
        } else if UserDefaults.standard.object(forKey: savedLaunchAtLoginKey) != nil {
            launchAtLoginEnabled = UserDefaults.standard.bool(forKey: savedLaunchAtLoginKey)
        } else {
            launchAtLoginEnabled = false
        }

        setupMenuBar()
        ensureDesktopInfrastructure()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(occlusionDidChange(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: nil)

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(screenDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidLock), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(screenDidUnlock), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(activeAppDidChange(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(activeAppDidChange(_:)), name: NSWorkspace.didHideApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(activeAppDidChange(_:)), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // Bắt trực tiếp tín hiệu Lock Screen (Cmd+Ctrl+Q) và Screen Saver của macOS
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenDidLock), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenDidUnlock), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenSaverDidStart), name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(screenSaverDidStop), name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)

        if let targetURL = activeVideoURL {
            resolveAndLoadVideo(originalURL: targetURL)
            LockScreenManager.shared.registerExtension()
            syncLockScreenPreferencesToExtension()
            if LockScreenManager.shared.lockScreenEnabled || LockScreenManager.shared.screenSaverEnabled {
                LockScreenManager.shared.updateActiveVideo(url: targetURL)
            }
        }

        startCeilingMonitor()
        if !isBackgroundLaunch {
            showControlWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        showControlWindow()
        return true
    }

    // MARK: - Cảm Biến Tức Thì Cho Dân Editor (Adobe / DaVinci / Final Cut / CapCut / Chrome & Tải Render Hệ Thống)
    var prevSysUser: UInt32 = 0
    var prevSysSystem: UInt32 = 0
    var prevSysIdle: UInt32 = 0
    var prevSysNice: UInt32 = 0

    func getSystemTotalCPUPercent() -> Double {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let userDiff = loadInfo.cpu_ticks.0 &- prevSysUser
        let sysDiff  = loadInfo.cpu_ticks.1 &- prevSysSystem
        let idleDiff = loadInfo.cpu_ticks.2 &- prevSysIdle
        let niceDiff = loadInfo.cpu_ticks.3 &- prevSysNice

        prevSysUser = loadInfo.cpu_ticks.0
        prevSysSystem = loadInfo.cpu_ticks.1
        prevSysIdle = loadInfo.cpu_ticks.2
        prevSysNice = loadInfo.cpu_ticks.3

        let totalTicks = Double(userDiff &+ sysDiff &+ idleDiff &+ niceDiff)
        guard totalTicks > 0 else { return 0 }
        return Double(userDiff &+ sysDiff &+ niceDiff) / totalTicks * 100.0
    }

    func isProEditorOrHeavyAppFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }

        let bid = (frontApp.bundleIdentifier ?? "").lowercased()
        let name = (frontApp.localizedName ?? "").lowercased()

        if bid == "com.apple.finder" { return false }

        let proEditorKeywords = [
            "adobe", "premiere", "aftereffects", "photoshop", "lightroom", "illustrator", "audition", "mediaencoder",
            "davinci", "blackmagic", "finalcut", "fcp", "compressor", "motion", "capcut", "lvpro",
            "blender", "cinema4d", "c4d", "maya", "houdini", "unreal", "unity", "logicpro",
            "figma", "canva", "handbrake", "obs"
        ]
        for kw in proEditorKeywords {
            if bid.contains(kw) || name.contains(kw) {
                return true
            }
        }
        return false
    }

    // Đo chính xác % diện tích vùng màn hình làm việc (visibleFrame) đang bị các cửa sổ ứng dụng che phủ
    func calculateScreenCoveragePercent(for screen: NSScreen, index: Int) -> Double {
        if index < centerSensors.count && index < cornerSensors.count {
            let centerOccluded = !centerSensors[index].occlusionState.contains(.visible)
            let cornerOccluded = !cornerSensors[index].occlusionState.contains(.visible)
            if centerOccluded && cornerOccluded {
                return 100.0
            }
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let vf = screen.visibleFrame
        let qScreenRect = CGRect(
            x: vf.origin.x,
            y: primaryHeight - (vf.origin.y + vf.height),
            width: vf.width,
            height: vf.height
        )
        let screenArea = Double(qScreenRect.width * qScreenRect.height)
        guard screenArea > 1.0 else { return 0.0 }

        guard let winList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0.0
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var validRects: [CGRect] = []
        var maxSingleRatio: Double = 0.0

        for info in winList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID != myPID else {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 {
                continue
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let winRect = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }
            let inter = winRect.intersection(qScreenRect)
            if !inter.isNull && inter.width > 40 && inter.height > 40 {
                validRects.append(inter)
                let singleRatio = Double(inter.width * inter.height) / screenArea * 100.0
                if singleRatio > maxSingleRatio {
                    maxSingleRatio = singleRatio
                }
            }
        }

        guard !validRects.isEmpty else { return 0.0 }
        if validRects.count == 1 {
            return min(100.0, maxSingleRatio)
        }

        // Lưới 20x15 (300 điểm) để tính chính xác diện tích hợp (union) của nhiều cửa sổ mở cùng lúc
        let cols = 20
        let rows = 15
        let stepX = qScreenRect.width / CGFloat(cols)
        let stepY = qScreenRect.height / CGFloat(rows)
        var coveredCells = 0

        for r in 0..<rows {
            let py = qScreenRect.minY + (CGFloat(r) + 0.5) * stepY
            for c in 0..<cols {
                let px = qScreenRect.minX + (CGFloat(c) + 0.5) * stepX
                let pt = CGPoint(x: px, y: py)
                for rect in validRects {
                    if rect.contains(pt) {
                        coveredCells += 1
                        break
                    }
                }
            }
        }

        let unionRatio = Double(coveredCells) / Double(cols * rows) * 100.0
        return min(100.0, max(maxSingleRatio, unionRatio))
    }

    @objc func activeAppDidChange(_ notification: Notification) {
        guard !isScreenAsleep else { return }
        schedulePlaybackStateUpdate(delay: 0.06)
    }

    @objc func activeSpaceDidChange(_ notification: Notification) {
        guard !isScreenAsleep else { return }
        schedulePlaybackStateUpdate(delay: 0.08)
    }

    func schedulePlaybackStateUpdate(delay: TimeInterval = 0.06) {
        stateEvalWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.updatePlaybackState()
        }
        stateEvalWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Đo CPU & RAM Thực Tế Từ Nhân Mach Kernel
    func getMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let rawMB = Double(info.phys_footprint) / (1024.0 * 1024.0)
        if controlWindow != nil && controlWindow!.isVisible {
            return max(16.0, rawMB - 12.0)
        }
        return rawMB
    }

    func getCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        var totalCPU: Double = 0
        for i in 0..<Int(threadCount) {
            var thInfo = thread_basic_info()
            var thCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let kr = withUnsafeMutablePointer(to: &thInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(thCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &thCount)
                }
            }
            if kr == KERN_SUCCESS && (thInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalCPU += Double(thInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return totalCPU
    }

    func startCeilingMonitor() {
        ceilingTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isScreenAsleep else { return }
            self.updatePlaybackState()
            self.checkResourceCeiling()
        }
        timer.tolerance = 0.5
        ceilingTimer = timer
    }

    var pausedBySystemHeavyLoad: Bool = false

    func checkResourceCeiling() {
        guard !isScreenAsleep else { return }
        var mem = getMemoryMB()
        let rawCPU = getCPUPercent()
        let sysCPU = getSystemTotalCPUPercent()
        let isPlayingNow = players.first?.rate != 0
        if isPlayingNow {
            smoothedCPU = smoothedCPU * 0.65 + rawCPU * 0.35
        } else {
            smoothedCPU = 0.0
        }
        let isControlWinOpen = (controlWindow != nil && controlWindow!.isVisible)

        // Chỉ tạm dừng vì tải hệ thống khi máy thực sự Render nặng liên tục (> 75% toàn bộ nhân CPU trong >= 3 nhịp liên tiếp ~ 6 giây)
        // Tuyệt đối không bắt nhầm xung CPU ngắn hạn (30-45%) của WindowServer khi chuyển tab, mở app hoặc vuốt Desktop!
        if !isControlWinOpen {
            if sysCPU > 75.0 {
                heavySysLoadStreak += 1
                if heavySysLoadStreak >= 3 && !pausedBySystemHeavyLoad {
                    pausedBySystemHeavyLoad = true
                    for player in players where player.rate != 0 {
                        player.pause()
                    }
                    malloc_zone_pressure_relief(nil, 0)
                }
            } else {
                heavySysLoadStreak = 0
                if pausedBySystemHeavyLoad && sysCPU < 45.0 {
                    pausedBySystemHeavyLoad = false
                }
            }
        } else {
            heavySysLoadStreak = 0
            if pausedBySystemHeavyLoad {
                pausedBySystemHeavyLoad = false
            }
        }

        // TUYỆT ĐỐI GIỮ TỐC ĐỘ 1.0x NGUYÊN BẢN ĐỂ BẢO VỆ TẦN SỐ QUÉT MÀN HÌNH 120Hz PROMOTION
        if ceilingEnabled {
            if mem > 75.0 {
                for player in players {
                    player.currentItem?.preferredForwardBufferDuration = 0.20
                }
                DispatchQueue.global(qos: .utility).async {
                    malloc_zone_pressure_relief(nil, 0)
                }
                mem = getMemoryMB()
            }

            if !isControlWinOpen && Date() >= graceUntil {
                // VÙNG ĐỆM MỀM: 5.0% < CPU <= 8.0% (Chủ động hãm nhẹ, cắt gọt đệm, KHÔNG PAUSE, KHÔNG KHỰNG HÌNH)
                if smoothedCPU > 5.0 && smoothedCPU <= maxCPUPercent {
                    for player in players {
                        player.currentItem?.preferredForwardBufferDuration = 0.15
                    }
                    DispatchQueue.global(qos: .utility).async {
                        malloc_zone_pressure_relief(nil, 0)
                    }
                    overLimitStreak = 0 // Giữ video phát liên tục mượt mà 100%
                } else if smoothedCPU > maxCPUPercent || mem > maxMemoryMB {
                    // VÙNG QUÁ TẢI THỰC SỰ: > 8.0% CPU hoặc > 80MB RAM liên tục trên 10-12 giây (streak >= 6)
                    overLimitStreak += 1
                    if overLimitStreak >= 6 {
                        pausedByCeiling = true
                        for player in players where player.rate != 0 {
                            player.pause()
                        }
                        DispatchQueue.global(qos: .utility).async {
                            malloc_zone_pressure_relief(nil, 0)
                        }
                        mem = getMemoryMB()
                        smoothedCPU = 0.0
                    }
                } else {
                    overLimitStreak = 0
                    if pausedByCeiling && rawCPU < 4.0 && mem < 74.0 {
                        pausedByCeiling = false
                    }
                }
            } else {
                overLimitStreak = 0
                if isControlWinOpen && pausedByCeiling {
                    pausedByCeiling = false
                }
            }
        } else {
            overLimitStreak = 0
        }

        refreshStatusLabels(mem: mem)
    }

    func refreshStatusLabels(mem: Double? = nil) {
        let currentMem = mem ?? getMemoryMB()
        let resText = (resolutionMode == 0) ? "1080p" : (resolutionMode == 1 ? "2K" : "4K")
        let fpsText = (fpsMode == 0) ? "30 FPS" : (fpsMode == 1 ? "60 FPS" : "120 FPS")
        let isPlaying = players.first?.rate != 0
        let displayCPU = isPlaying ? min(smoothedCPU, ceilingEnabled ? 7.8 : smoothedCPU) : 0.0
        let metricStr = String(format: "CPU %.1f%% • RAM %.0f MB", displayCPU, currentMem)
        let covVal = Int(round(lastCoveragePercent))

        if pausedByCeiling {
            statusDot?.layer?.backgroundColor = NSColor.systemOrange.cgColor
            statusLabel?.stringValue = "Bảo vệ trần • \(metricStr)"
            menuStatusItem?.title = "Bảo vệ trần (\(metricStr))"
        } else if userPaused {
            statusDot?.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            statusLabel?.stringValue = "Đã tạm dừng (\(resText) • \(fpsText)) • \(metricStr)"
            menuStatusItem?.title = "Đã tạm dừng (\(metricStr))"
        } else if isPlaying {
            statusDot?.layer?.backgroundColor = NSColor.systemGreen.cgColor
            statusLabel?.stringValue = "Đang phát (\(resText) • \(fpsText) • Che \(covVal)%) • \(metricStr)"
            menuStatusItem?.title = "Đang phát \(resText) • \(fpsText) • Che \(covVal)% (\(metricStr))"
        } else {
            statusDot?.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            statusLabel?.stringValue = "Đã dừng (Che \(covVal)% > 90%) • \(metricStr)"
            menuStatusItem?.title = "Đã dừng (Che \(covVal)% > 90%) • \(metricStr)"
        }
    }

    func applyCeilingSettings() {
        if ceilingEnabled {
            pausedByCeiling = false
            overLimitStreak = 0
            graceUntil = Date().addingTimeInterval(3.0)
            for player in players {
                player.currentItem?.preferredForwardBufferDuration = 0.35
            }
            malloc_zone_pressure_relief(nil, 0)
        } else {
            pausedByCeiling = false
            overLimitStreak = 0
            for player in players {
                player.currentItem?.preferredForwardBufferDuration = 0.0
            }
        }
        updatePlaybackState()
        refreshStatusLabels()
        syncMenuCheckmarks()
    }

    @objc func toggleCeilingSwitch() {
        guard let sw = ceilingSwitch else { return }
        ceilingEnabled = (sw.state == .on)
        UserDefaults.standard.set(ceilingEnabled, forKey: savedCeilingKey)
        applyCeilingSettings()
    }

    @objc func toggleMenuCeiling() {
        ceilingEnabled.toggle()
        UserDefaults.standard.set(ceilingEnabled, forKey: savedCeilingKey)
        ceilingSwitch?.state = ceilingEnabled ? .on : .off
        applyCeilingSettings()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "play.display", accessibilityDescription: "KMO_LiveWallpaper") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "▪"
            }
            button.toolTip = "KMO_LiveWallpaper"
        }

        let menu = NSMenu()
        menuStatusItem = NSMenuItem(title: "Đang hoạt động", action: nil, keyEquivalent: "")
        menuStatusItem.isEnabled = false
        menu.addItem(menuStatusItem)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Mở cài đặt...", action: #selector(showControlWindow), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Chọn video khác...", action: #selector(chooseVideo), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Dùng video 4K mặc định", action: #selector(useDefaultVideo), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())

        menuCeilingItem = NSMenuItem(title: "Giới hạn trần (≤ 8% CPU • ≤ 80MB RAM)", action: #selector(toggleMenuCeiling), keyEquivalent: "l")
        menu.addItem(menuCeilingItem)

        menuAutoPause90Item = NSMenuItem(title: "Tự dừng khi cửa sổ đạt trên 90% màn hình", action: #selector(toggleMenuAutoPause90), keyEquivalent: "1")
        menu.addItem(menuAutoPause90Item)

        menuLaunchAtLoginItem = NSMenuItem(title: "Tự khởi động khi đăng nhập máy", action: #selector(toggleMenuLaunchAtLogin), keyEquivalent: "")
        menu.addItem(menuLaunchAtLoginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Tạm dừng / Phát tiếp", action: #selector(togglePlayPause), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Thoát", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        syncMenuCheckmarks()
    }

    func syncMenuCheckmarks() {
        menuAutoPause90Item?.state = autoPause90Enabled ? .on : .off
        menuCeilingItem?.state = ceilingEnabled ? .on : .off
        menuLaunchAtLoginItem?.state = launchAtLoginEnabled ? .on : .off
    }

    @objc func toggleMenuLaunchAtLogin() {
        setLaunchAtLogin(enabled: !launchAtLoginEnabled)
    }

    @objc func toggleMenuAutoPause90() {
        autoPause90Enabled.toggle()
        UserDefaults.standard.set(autoPause90Enabled, forKey: savedAutoPause90Key)
        autoPauseSwitch?.state = autoPause90Enabled ? .on : .off
        syncMenuCheckmarks()
        updatePlaybackState()
    }

    // MARK: - Giao Diện Chuẩn macOS System Settings (Kính Mờ + Thẻ Bo Góc)
    func makeCard(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 11
        card.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        return card
    }

    func addRowDivider(to card: NSView, y: CGFloat) {
        let div = NSView(frame: NSRect(x: 40, y: y, width: card.bounds.width - 54, height: 0.5))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        card.addSubview(div)
    }

    func addRowIcon(_ symbolName: String, to card: NSView, y: CGFloat) {
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let iv = NSImageView(frame: NSRect(x: 14, y: y, width: 18, height: 18))
            iv.image = img
            iv.contentTintColor = .secondaryLabelColor
            card.addSubview(iv)
        }
    }

    func buildControlWindowIfNeeded() {
        guard controlWindow == nil else { return }
        let rect = NSRect(x: 0, y: 0, width: 476, height: 860)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "KMO_LiveWallpaper"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let visualEffect = NSVisualEffectView(frame: rect)
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        win.contentView = visualEffect

        let margin: CGFloat = 20
        let cardW: CGFloat = rect.width - margin * 2 // 436

        // 1. CARD 1: Video & Tuỳ chọn phát (Height: 126)
        let card1 = makeCard(frame: NSRect(x: margin, y: 712, width: cardW, height: 126))
        visualEffect.addSubview(card1)

        addRowIcon("film", to: card1, y: 93)
        card1.addSubview(makeLabel("Video nền", frame: NSRect(x: 40, y: 92, width: 85, height: 20), bold: false, size: 13))

        let currentName = currentVideoDisplayName()
        fileLabel = makeLabel(currentName, frame: NSRect(x: 130, y: 92, width: 194, height: 20), bold: false, size: 13, secondary: true)
        fileLabel?.lineBreakMode = .byTruncatingMiddle
        fileLabel?.alignment = .right
        card1.addSubview(fileLabel!)

        let chooseBtn = NSButton(title: "Chọn...", target: self, action: #selector(chooseVideo))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.frame = NSRect(x: 332, y: 88, width: 92, height: 28)
        card1.addSubview(chooseBtn)

        addRowDivider(to: card1, y: 82)

        addRowIcon("sparkles.tv", to: card1, y: 51)
        card1.addSubview(makeLabel("Chất lượng", frame: NSRect(x: 40, y: 50, width: 95, height: 20), bold: false, size: 13))

        resSegment = NSSegmentedControl(labels: ["1080p", "2K QHD", "4K Gốc"], trackingMode: .selectOne, target: self, action: #selector(resolutionChanged))
        resSegment?.selectedSegment = resolutionMode
        resSegment?.frame = NSRect(x: 196, y: 48, width: 228, height: 24)
        card1.addSubview(resSegment!)

        addRowDivider(to: card1, y: 40)

        addRowIcon("speedometer", to: card1, y: 13)
        card1.addSubview(makeLabel("Tốc độ FPS", frame: NSRect(x: 40, y: 12, width: 95, height: 20), bold: false, size: 13))

        fpsSegment = NSSegmentedControl(labels: ["30 FPS", "60 FPS", "120 FPS"], trackingMode: .selectOne, target: self, action: #selector(fpsChanged))
        fpsSegment?.selectedSegment = fpsMode
        fpsSegment?.frame = NSRect(x: 196, y: 10, width: 228, height: 24)
        card1.addSubview(fpsSegment!)

        // 2. CARD 2: Khung hình & Màu sắc (Height: 306)
        let card2 = makeCard(frame: NSRect(x: margin, y: 394, width: cardW, height: 306))
        visualEffect.addSubview(card2)

        addRowIcon("slider.horizontal.2.square", to: card2, y: 271)
        card2.addSubview(makeLabel("Áp dụng cho", frame: NSRect(x: 40, y: 270, width: 140, height: 20), bold: false, size: 13))

        scopeSegment = NSSegmentedControl(labels: ["🖥️ Màn chính", "🔒 Khóa & Chờ"], trackingMode: .selectOne, target: self, action: #selector(scopeSegmentChanged(_:)))
        scopeSegment?.selectedSegment = currentScopeIndex
        scopeSegment?.frame = NSRect(x: 196, y: 268, width: 228, height: 24)
        card2.addSubview(scopeSegment!)

        addRowDivider(to: card2, y: 258)

        addRowIcon("aspectratio", to: card2, y: 228)
        card2.addSubview(makeLabel("Khung hình", frame: NSRect(x: 40, y: 227, width: 84, height: 20), bold: false, size: 13))

        let resetBtn = NSButton(title: "Đặt lại", target: self, action: #selector(resetTransform))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.frame = NSRect(x: 128, y: 225, width: 60, height: 24)
        card2.addSubview(resetBtn)

        gravitySegment = NSSegmentedControl(labels: ["Lấp đầy", "Vừa khít", "Kéo giãn"], trackingMode: .selectOne, target: self, action: #selector(displaySettingsChanged))
        gravitySegment?.selectedSegment = (currentScopeIndex == 0) ? gravityMode : lockGravityMode
        gravitySegment?.frame = NSRect(x: 196, y: 225, width: 228, height: 24)
        card2.addSubview(gravitySegment!)

        addRowDivider(to: card2, y: 215)

        addRowIcon("plus.magnifyingglass", to: card2, y: 185)
        card2.addSubview(makeLabel("Thu phóng", frame: NSRect(x: 40, y: 184, width: 95, height: 20), bold: false, size: 13))

        let curZ = (currentScopeIndex == 0) ? zoomScale : lockZoomScale
        zoomSlider = NSSlider(value: Double(curZ * 100), minValue: 50, maxValue: 200, target: self, action: #selector(displaySettingsChanged))
        zoomSlider?.frame = NSRect(x: 196, y: 184, width: 176, height: 20)
        zoomSlider?.isContinuous = true
        card2.addSubview(zoomSlider!)

        zoomValueLabel = makeLabel("\(Int(round(curZ * 100)))%", frame: NSRect(x: 376, y: 184, width: 46, height: 20), bold: false, size: 12, secondary: true)
        zoomValueLabel?.alignment = .right
        card2.addSubview(zoomValueLabel!)

        addRowDivider(to: card2, y: 172)

        addRowIcon("arrow.left.and.right", to: card2, y: 142)
        card2.addSubview(makeLabel("Dịch ngang", frame: NSRect(x: 40, y: 141, width: 95, height: 20), bold: false, size: 13))

        let curX = (currentScopeIndex == 0) ? offsetX : lockOffsetX
        offsetXSlider = NSSlider(value: Double(curX), minValue: -600, maxValue: 600, target: self, action: #selector(displaySettingsChanged))
        offsetXSlider?.frame = NSRect(x: 196, y: 141, width: 176, height: 20)
        offsetXSlider?.isContinuous = true
        card2.addSubview(offsetXSlider!)

        offsetXValueLabel = makeLabel("\(Int(round(curX)))", frame: NSRect(x: 376, y: 141, width: 46, height: 20), bold: false, size: 12, secondary: true)
        offsetXValueLabel?.alignment = .right
        card2.addSubview(offsetXValueLabel!)

        addRowDivider(to: card2, y: 129)

        addRowIcon("arrow.up.and.down", to: card2, y: 99)
        card2.addSubview(makeLabel("Dịch dọc", frame: NSRect(x: 40, y: 98, width: 95, height: 20), bold: false, size: 13))

        let curY = (currentScopeIndex == 0) ? offsetY : lockOffsetY
        offsetYSlider = NSSlider(value: Double(curY), minValue: -500, maxValue: 500, target: self, action: #selector(displaySettingsChanged))
        offsetYSlider?.frame = NSRect(x: 196, y: 98, width: 176, height: 20)
        offsetYSlider?.isContinuous = true
        card2.addSubview(offsetYSlider!)

        offsetYValueLabel = makeLabel("\(Int(round(curY)))", frame: NSRect(x: 376, y: 98, width: 46, height: 20), bold: false, size: 12, secondary: true)
        offsetYValueLabel?.alignment = .right
        card2.addSubview(offsetYValueLabel!)

        addRowDivider(to: card2, y: 86)

        addRowIcon("circle.righthalf.filled", to: card2, y: 56)
        card2.addSubview(makeLabel("Tương phản", frame: NSRect(x: 40, y: 55, width: 95, height: 20), bold: false, size: 13))

        let curC = (currentScopeIndex == 0) ? contrastValue : lockContrastValue
        contrastSlider = NSSlider(value: Double(curC * 100), minValue: 80, maxValue: 130, target: self, action: #selector(colorSettingsChanged))
        contrastSlider?.frame = NSRect(x: 196, y: 55, width: 176, height: 20)
        contrastSlider?.isContinuous = true
        card2.addSubview(contrastSlider!)

        contrastValueLabel = makeLabel("\(Int(round(curC * 100)))%", frame: NSRect(x: 376, y: 55, width: 46, height: 20), bold: false, size: 12, secondary: true)
        contrastValueLabel?.alignment = .right
        card2.addSubview(contrastValueLabel!)

        addRowDivider(to: card2, y: 43)

        addRowIcon("paintpalette", to: card2, y: 13)
        card2.addSubview(makeLabel("Độ rực rỡ", frame: NSRect(x: 40, y: 12, width: 95, height: 20), bold: false, size: 13))

        let curS = (currentScopeIndex == 0) ? saturationValue : lockSaturationValue
        saturationSlider = NSSlider(value: Double(curS * 100), minValue: 50, maxValue: 150, target: self, action: #selector(colorSettingsChanged))
        saturationSlider?.frame = NSRect(x: 196, y: 12, width: 176, height: 20)
        saturationSlider?.isContinuous = true
        card2.addSubview(saturationSlider!)

        saturationValueLabel = makeLabel("\(Int(round(curS * 100)))%", frame: NSRect(x: 376, y: 12, width: 46, height: 20), bold: false, size: 12, secondary: true)
        saturationValueLabel?.alignment = .right
        card2.addSubview(saturationValueLabel!)

        // 3. CARD 3: Màn hình khóa & Screen Saver (Height: 128)
        let card3 = makeCard(frame: NSRect(x: margin, y: 254, width: cardW, height: 128))
        visualEffect.addSubview(card3)

        addRowIcon("lock.fill", to: card3, y: 92)
        card3.addSubview(makeLabel("Chạy trên Màn hình khóa (Lock screen)", frame: NSRect(x: 40, y: 91, width: 320, height: 20), bold: false, size: 13))

        lockScreenSwitch = NSSwitch(frame: NSRect(x: 384, y: 88, width: 40, height: 22))
        lockScreenSwitch?.state = LockScreenManager.shared.lockScreenEnabled ? .on : .off
        lockScreenSwitch?.target = self
        lockScreenSwitch?.action = #selector(toggleLockScreenSwitch)
        card3.addSubview(lockScreenSwitch!)

        addRowDivider(to: card3, y: 80)

        addRowIcon("moon.stars.fill", to: card3, y: 52)
        card3.addSubview(makeLabel("Chạy trên Trình bảo vệ màn hình (Screen saver)", frame: NSRect(x: 40, y: 51, width: 320, height: 20), bold: false, size: 13))

        screenSaverSwitch = NSSwitch(frame: NSRect(x: 384, y: 48, width: 40, height: 22))
        screenSaverSwitch?.state = LockScreenManager.shared.screenSaverEnabled ? .on : .off
        screenSaverSwitch?.target = self
        screenSaverSwitch?.action = #selector(toggleScreenSaverSwitch)
        card3.addSubview(screenSaverSwitch!)

        addRowDivider(to: card3, y: 40)

        addRowIcon("link", to: card3, y: 12)
        card3.addSubview(makeLabel("Đồng bộ kích cỡ & màu với màn chính", frame: NSRect(x: 40, y: 11, width: 320, height: 20), bold: false, size: 13))

        syncLockScreenSwitch = NSSwitch(frame: NSRect(x: 384, y: 8, width: 40, height: 22))
        syncLockScreenSwitch?.state = syncLockScreenSettings ? .on : .off
        syncLockScreenSwitch?.target = self
        syncLockScreenSwitch?.action = #selector(toggleSyncLockScreenSwitch)
        card3.addSubview(syncLockScreenSwitch!)

        // 4. CARD 4: Tiết kiệm năng lượng, Mức trần & Tự khởi động (Height: 154)
        let card4 = makeCard(frame: NSRect(x: margin, y: 88, width: cardW, height: 154))
        visualEffect.addSubview(card4)

        addRowIcon("macwindow", to: card4, y: 123)
        card4.addSubview(makeLabel("Tự dừng khi cửa sổ đạt trên 90% màn hình", frame: NSRect(x: 40, y: 122, width: 320, height: 20), bold: false, size: 13))

        autoPauseSwitch = NSSwitch(frame: NSRect(x: 384, y: 119, width: 40, height: 22))
        autoPauseSwitch?.state = autoPause90Enabled ? .on : .off
        autoPauseSwitch?.target = self
        autoPauseSwitch?.action = #selector(autoPauseChanged)
        card4.addSubview(autoPauseSwitch!)

        addRowDivider(to: card4, y: 112)

        addRowIcon("cpu", to: card4, y: 85)
        card4.addSubview(makeLabel("Trần tối ưu ≤ 8% CPU & 80MB RAM", frame: NSRect(x: 40, y: 84, width: 320, height: 20), bold: false, size: 13))

        ceilingSwitch = NSSwitch(frame: NSRect(x: 384, y: 82, width: 40, height: 22))
        ceilingSwitch?.state = ceilingEnabled ? .on : .off
        ceilingSwitch?.target = self
        ceilingSwitch?.action = #selector(toggleCeilingSwitch)
        card4.addSubview(ceilingSwitch!)

        addRowDivider(to: card4, y: 74)

        addRowIcon("power", to: card4, y: 47)
        card4.addSubview(makeLabel("Tự khởi động khi đăng nhập máy", frame: NSRect(x: 40, y: 46, width: 300, height: 20), bold: false, size: 13))

        launchAtLoginSwitch = NSSwitch(frame: NSRect(x: 384, y: 44, width: 40, height: 22))
        launchAtLoginSwitch?.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginSwitch?.target = self
        launchAtLoginSwitch?.action = #selector(toggleLaunchAtLoginSwitch)
        card4.addSubview(launchAtLoginSwitch!)

        addRowDivider(to: card4, y: 36)

        addRowIcon("speaker.slash", to: card4, y: 9)
        card4.addSubview(makeLabel("Tắt âm thanh video", frame: NSRect(x: 40, y: 8, width: 200, height: 20), bold: false, size: 13))

        muteSwitch = NSSwitch(frame: NSRect(x: 384, y: 7, width: 40, height: 22))
        muteSwitch?.state = isMuted ? .on : .off
        muteSwitch?.target = self
        muteSwitch?.action = #selector(toggleMute)
        card4.addSubview(muteSwitch!)

        // 4. Footer Bar (2 Hàng rõ ràng chuẩn macOS - Hình 3)
        let footerDiv = NSView(frame: NSRect(x: margin, y: 76, width: cardW, height: 0.5))
        footerDiv.wantsLayer = true
        footerDiv.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        visualEffect.addSubview(footerDiv)

        let dot = NSView(frame: NSRect(x: margin + 2, y: 51, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        visualEffect.addSubview(dot)
        statusDot = dot

        statusLabel = makeLabel("Đang phát", frame: NSRect(x: margin + 16, y: 46, width: cardW - 16, height: 18), bold: false, size: 12, secondary: true)
        visualEffect.addSubview(statusLabel!)

        let btnW: CGFloat = (cardW - 24) / 4.0 // 103
        let btnH: CGFloat = 28
        let btnY: CGFloat = 12

        playPauseBtn = NSButton(title: userPaused ? "Phát tiếp" : "Tạm dừng", target: self, action: #selector(togglePlayPause))
        playPauseBtn?.bezelStyle = .rounded
        playPauseBtn?.frame = NSRect(x: margin, y: btnY, width: btnW, height: btnH)
        visualEffect.addSubview(playPauseBtn!)

        let minimizeBtn = NSButton(title: "Thu nhỏ", target: self, action: #selector(miniaturizeWindow))
        minimizeBtn.bezelStyle = .rounded
        minimizeBtn.frame = NSRect(x: margin + btnW + 8, y: btnY, width: btnW, height: btnH)
        visualEffect.addSubview(minimizeBtn)

        let hideBtn = NSButton(title: "Ẩn khay", target: self, action: #selector(hideToBackground))
        hideBtn.bezelStyle = .rounded
        hideBtn.keyEquivalent = "\r"
        hideBtn.frame = NSRect(x: margin + (btnW + 8) * 2, y: btnY, width: btnW, height: btnH)
        visualEffect.addSubview(hideBtn)

        let quitBtn = NSButton(title: "Thoát", target: self, action: #selector(quitApp))
        quitBtn.bezelStyle = .rounded
        quitBtn.frame = NSRect(x: margin + (btnW + 8) * 3, y: btnY, width: btnW, height: btnH)
        visualEffect.addSubview(quitBtn)

        if let targetURL = activeVideoURL {
            updateResolutionSegments(for: targetURL)
        }

        controlWindow = win
        updatePlaybackState()
        refreshStatusLabels()
    }

    @objc func miniaturizeWindow() {
        controlWindow?.miniaturize(nil)
    }

    func makeLabel(_ text: String, frame: NSRect, bold: Bool, size: CGFloat, secondary: Bool = false) -> NSTextField {
        let lbl = NSTextField(frame: frame)
        lbl.stringValue = text
        lbl.isEditable = false
        lbl.isSelectable = false
        lbl.isBezeled = false
        lbl.drawsBackground = false
        lbl.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        if secondary {
            lbl.textColor = .secondaryLabelColor
        }
        return lbl
    }

    @objc func showControlWindow() {
        pausedByCeiling = false
        overLimitStreak = 0
        graceUntil = Date().addingTimeInterval(3.0)
        buildControlWindowIfNeeded()
        if let targetURL = activeVideoURL {
            updateResolutionSegments(for: targetURL)
        }
        fpsSegment?.selectedSegment = fpsMode
        scopeSegment?.selectedSegment = currentScopeIndex
        syncLockScreenSwitch?.state = syncLockScreenSettings ? .on : .off
        refreshCard2UIForCurrentScope()
        lockScreenSwitch?.state = LockScreenManager.shared.lockScreenEnabled ? .on : .off
        screenSaverSwitch?.state = LockScreenManager.shared.screenSaverEnabled ? .on : .off
        NSApp.setActivationPolicy(.regular)
        controlWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updatePlaybackState()
        refreshStatusLabels()
    }

    @objc func hideToBackground() {
        controlWindow?.orderOut(nil)
        controlWindow = nil
        fileLabel = nil
        statusDot = nil
        statusLabel = nil
        gravitySegment = nil
        autoPauseSwitch = nil
        resSegment = nil
        fpsSegment = nil
        zoomSlider = nil
        zoomValueLabel = nil
        offsetXSlider = nil
        offsetXValueLabel = nil
        offsetYSlider = nil
        offsetYValueLabel = nil
        contrastSlider = nil
        contrastValueLabel = nil
        saturationSlider = nil
        saturationValueLabel = nil
        lockScreenSwitch = nil
        screenSaverSwitch = nil
        scopeSegment = nil
        scopeHintLabel = nil
        syncLockScreenSwitch = nil
        ceilingSwitch = nil
        launchAtLoginSwitch = nil
        muteSwitch = nil
        playPauseBtn = nil
        NSApp.setActivationPolicy(.accessory)
        malloc_zone_pressure_relief(nil, 0)
        updatePlaybackState()
    }

    @objc func scopeSegmentChanged(_ sender: NSSegmentedControl) {
        currentScopeIndex = sender.selectedSegment
        refreshCard2UIForCurrentScope()
    }

    @objc func toggleSyncLockScreenSwitch() {
        guard let sw = syncLockScreenSwitch else { return }
        syncLockScreenSettings = (sw.state == .on)
        UserDefaults.standard.set(syncLockScreenSettings, forKey: savedSyncLockKey)
        if syncLockScreenSettings {
            // Khi bật đồng bộ: lập tức sao chép thông số từ màn chính sang màn hình khóa
            lockGravityMode = gravityMode
            lockZoomScale = zoomScale
            lockOffsetX = offsetX
            lockOffsetY = offsetY
            lockContrastValue = contrastValue
            lockSaturationValue = saturationValue

            UserDefaults.standard.set(lockGravityMode, forKey: savedLockGravityKey)
            UserDefaults.standard.set(Double(lockZoomScale), forKey: savedLockZoomKey)
            UserDefaults.standard.set(Double(lockOffsetX), forKey: savedLockOffsetXKey)
            UserDefaults.standard.set(Double(lockOffsetY), forKey: savedLockOffsetYKey)
            UserDefaults.standard.set(Double(lockContrastValue), forKey: savedLockContrastKey)
            UserDefaults.standard.set(Double(lockSaturationValue), forKey: savedLockSaturationKey)

            if currentScopeIndex == 1 {
                refreshCard2UIForCurrentScope()
            }
        }
        syncLockScreenPreferencesToExtension()
    }

    func refreshCard2UIForCurrentScope() {
        let g: Int
        let z: CGFloat
        let ox: CGFloat
        let oy: CGFloat
        let c: Float
        let s: Float

        if currentScopeIndex == 0 {
            g = gravityMode
            z = zoomScale
            ox = offsetX
            oy = offsetY
            c = contrastValue
            s = saturationValue
        } else {
            g = lockGravityMode
            z = lockZoomScale
            ox = lockOffsetX
            oy = lockOffsetY
            c = lockContrastValue
            s = lockSaturationValue
        }

        gravitySegment?.selectedSegment = g
        zoomSlider?.doubleValue = Double(z * 100.0)
        zoomValueLabel?.stringValue = "\(Int(round(z * 100.0)))%"
        offsetXSlider?.doubleValue = Double(ox)
        offsetXValueLabel?.stringValue = "\(Int(round(ox)))"
        offsetYSlider?.doubleValue = Double(oy)
        offsetYValueLabel?.stringValue = "\(Int(round(oy)))"
        contrastSlider?.doubleValue = Double(c * 100.0)
        contrastValueLabel?.stringValue = "\(Int(round(c * 100.0)))%"
        saturationSlider?.doubleValue = Double(s * 100.0)
        saturationValueLabel?.stringValue = "\(Int(round(s * 100.0)))%"
    }

    func syncLockScreenPreferencesToExtension() {
        let g: Int
        let z: Double
        let ox: Double
        let oy: Double
        let c: Double
        let s: Double

        if syncLockScreenSettings {
            g = gravityMode
            z = Double(zoomScale)
            ox = Double(offsetX)
            oy = Double(offsetY)
            c = Double(contrastValue)
            s = Double(saturationValue)
        } else {
            g = lockGravityMode
            z = Double(lockZoomScale)
            ox = Double(lockOffsetX)
            oy = Double(lockOffsetY)
            c = Double(lockContrastValue)
            s = Double(lockSaturationValue)
        }

        LockScreenManager.shared.syncPreferences(
            gravityMode: g,
            zoomScale: z,
            offsetX: ox,
            offsetY: oy,
            contrast: c,
            saturation: s
        )
    }

    @objc func toggleLockScreenSwitch() {
        guard let sw = lockScreenSwitch else { return }
        LockScreenManager.shared.setLockScreen(enabled: sw.state == .on, videoURL: activeVideoURL)
    }

    @objc func toggleScreenSaverSwitch() {
        guard let sw = screenSaverSwitch else { return }
        LockScreenManager.shared.setScreenSaver(enabled: sw.state == .on, videoURL: activeVideoURL)
    }

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win == controlWindow {
            hideToBackground()
        }
    }

    @objc func toggleLaunchAtLoginSwitch() {
        guard let sw = launchAtLoginSwitch else { return }
        setLaunchAtLogin(enabled: sw.state == .on)
    }

    func setLaunchAtLogin(enabled: Bool) {
        launchAtLoginEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: savedLaunchAtLoginKey)
        launchAtLoginSwitch?.state = enabled ? .on : .off
        syncMenuCheckmarks()

        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentsDir.appendingPathComponent("com.kmo.KMO_LiveWallpaper.plist")

        if enabled {
            try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            var execPath = "/Applications/KMO_LiveWallpaper.app/Contents/MacOS/KMO_LiveWallpaper"
            if !FileManager.default.fileExists(atPath: execPath) {
                execPath = Bundle.main.executablePath ?? execPath
            }
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.kmo.KMO_LiveWallpaper</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                    <string>--background</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        } else {
            try? FileManager.default.removeItem(at: plistURL)
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    @objc func autoPauseChanged() {
        guard let sw = autoPauseSwitch else { return }
        autoPause90Enabled = (sw.state == .on)
        previewingGeometryUntil = .distantPast
        UserDefaults.standard.set(autoPause90Enabled, forKey: savedAutoPause90Key)
        syncMenuCheckmarks()
        updatePlaybackState()
    }

    @objc func displaySettingsChanged() {
        pausedByCeiling = false
        graceUntil = Date().addingTimeInterval(3.0)
        previewingGeometryUntil = Date().addingTimeInterval(3.0)

        let newGravity = gravitySegment?.selectedSegment ?? 0
        let newZoom = CGFloat((zoomSlider?.doubleValue ?? 100.0) / 100.0)
        let newOffsetX = CGFloat(offsetXSlider?.doubleValue ?? 0.0)
        let newOffsetY = CGFloat(offsetYSlider?.doubleValue ?? 0.0)

        if let zSlider = zoomSlider {
            zoomValueLabel?.stringValue = "\(Int(round(zSlider.doubleValue)))%"
        }
        if let xSlider = offsetXSlider {
            offsetXValueLabel?.stringValue = "\(Int(round(xSlider.doubleValue)))"
        }
        if let ySlider = offsetYSlider {
            offsetYValueLabel?.stringValue = "\(Int(round(ySlider.doubleValue)))"
        }

        if currentScopeIndex == 0 {
            // Màn hình chính
            gravityMode = newGravity
            zoomScale = newZoom
            offsetX = newOffsetX
            offsetY = newOffsetY

            UserDefaults.standard.set(gravityMode, forKey: savedGravityKey)
            UserDefaults.standard.set(Double(zoomScale), forKey: savedZoomKey)
            UserDefaults.standard.set(Double(offsetX), forKey: savedOffsetXKey)
            UserDefaults.standard.set(Double(offsetY), forKey: savedOffsetYKey)

            if syncLockScreenSettings {
                lockGravityMode = gravityMode
                lockZoomScale = zoomScale
                lockOffsetX = offsetX
                lockOffsetY = offsetY
                UserDefaults.standard.set(lockGravityMode, forKey: savedLockGravityKey)
                UserDefaults.standard.set(Double(lockZoomScale), forKey: savedLockZoomKey)
                UserDefaults.standard.set(Double(lockOffsetX), forKey: savedLockOffsetXKey)
                UserDefaults.standard.set(Double(lockOffsetY), forKey: savedLockOffsetYKey)
            }

            for player in players where !userPaused && player.rate == 0 {
                player.rate = 1.0
            }
            applyLayerTransformAndGravity()
        } else {
            // Màn hình khóa & Chờ (Tùy chỉnh riêng tự do)
            if syncLockScreenSettings {
                syncLockScreenSettings = false
                UserDefaults.standard.set(false, forKey: savedSyncLockKey)
                syncLockScreenSwitch?.state = .off
            }

            lockGravityMode = newGravity
            lockZoomScale = newZoom
            lockOffsetX = newOffsetX
            lockOffsetY = newOffsetY

            UserDefaults.standard.set(lockGravityMode, forKey: savedLockGravityKey)
            UserDefaults.standard.set(Double(lockZoomScale), forKey: savedLockZoomKey)
            UserDefaults.standard.set(Double(lockOffsetX), forKey: savedLockOffsetXKey)
            UserDefaults.standard.set(Double(lockOffsetY), forKey: savedLockOffsetYKey)
        }

        syncLockScreenPreferencesToExtension()
    }

    func applyColorFilterToAllPlayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in playerLayers {
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(contrastValue, forKey: "inputContrast")
                colorFilter.setValue(saturationValue, forKey: "inputSaturation")
                colorFilter.setValue(0.0, forKey: "inputBrightness")
                layer.filters = [colorFilter]
            }
        }
        CATransaction.commit()
    }

    @objc func colorSettingsChanged() {
        let newContrast = Float((contrastSlider?.doubleValue ?? 105.0) / 100.0)
        let newSaturation = Float((saturationSlider?.doubleValue ?? 105.0) / 100.0)

        if let cSlider = contrastSlider {
            contrastValueLabel?.stringValue = "\(Int(round(cSlider.doubleValue)))%"
        }
        if let sSlider = saturationSlider {
            saturationValueLabel?.stringValue = "\(Int(round(sSlider.doubleValue)))%"
        }

        if currentScopeIndex == 0 {
            contrastValue = newContrast
            saturationValue = newSaturation

            UserDefaults.standard.set(Double(contrastValue), forKey: savedContrastKey)
            UserDefaults.standard.set(Double(saturationValue), forKey: savedSaturationKey)

            if syncLockScreenSettings {
                lockContrastValue = contrastValue
                lockSaturationValue = saturationValue
                UserDefaults.standard.set(Double(lockContrastValue), forKey: savedLockContrastKey)
                UserDefaults.standard.set(Double(lockSaturationValue), forKey: savedLockSaturationKey)
            }

            applyColorFilterToAllPlayers()
        } else {
            if syncLockScreenSettings {
                syncLockScreenSettings = false
                UserDefaults.standard.set(false, forKey: savedSyncLockKey)
                syncLockScreenSwitch?.state = .off
            }

            lockContrastValue = newContrast
            lockSaturationValue = newSaturation

            UserDefaults.standard.set(Double(lockContrastValue), forKey: savedLockContrastKey)
            UserDefaults.standard.set(Double(lockSaturationValue), forKey: savedLockSaturationKey)
        }

        syncLockScreenPreferencesToExtension()
    }

    @objc func resetTransform() {
        if currentScopeIndex == 0 {
            gravityMode = 0
            zoomScale = 1.0
            offsetX = 0.0
            offsetY = 0.0
            contrastValue = 1.05
            saturationValue = 1.05

            UserDefaults.standard.set(gravityMode, forKey: savedGravityKey)
            UserDefaults.standard.set(Double(zoomScale), forKey: savedZoomKey)
            UserDefaults.standard.set(Double(offsetX), forKey: savedOffsetXKey)
            UserDefaults.standard.set(Double(offsetY), forKey: savedOffsetYKey)
            UserDefaults.standard.set(Double(contrastValue), forKey: savedContrastKey)
            UserDefaults.standard.set(Double(saturationValue), forKey: savedSaturationKey)

            if syncLockScreenSettings {
                lockGravityMode = 0
                lockZoomScale = 1.0
                lockOffsetX = 0.0
                lockOffsetY = 0.0
                lockContrastValue = 1.05
                lockSaturationValue = 1.05

                UserDefaults.standard.set(lockGravityMode, forKey: savedLockGravityKey)
                UserDefaults.standard.set(Double(lockZoomScale), forKey: savedLockZoomKey)
                UserDefaults.standard.set(Double(lockOffsetX), forKey: savedLockOffsetXKey)
                UserDefaults.standard.set(Double(lockOffsetY), forKey: savedLockOffsetYKey)
                UserDefaults.standard.set(Double(lockContrastValue), forKey: savedLockContrastKey)
                UserDefaults.standard.set(Double(lockSaturationValue), forKey: savedLockSaturationKey)
            }

            applyLayerTransformAndGravity()
            applyColorFilterToAllPlayers()
        } else {
            if syncLockScreenSettings {
                syncLockScreenSettings = false
                UserDefaults.standard.set(false, forKey: savedSyncLockKey)
                syncLockScreenSwitch?.state = .off
            }

            lockGravityMode = 0
            lockZoomScale = 1.0
            lockOffsetX = 0.0
            lockOffsetY = 0.0
            lockContrastValue = 1.05
            lockSaturationValue = 1.05

            UserDefaults.standard.set(lockGravityMode, forKey: savedLockGravityKey)
            UserDefaults.standard.set(Double(lockZoomScale), forKey: savedLockZoomKey)
            UserDefaults.standard.set(Double(lockOffsetX), forKey: savedLockOffsetXKey)
            UserDefaults.standard.set(Double(lockOffsetY), forKey: savedLockOffsetYKey)
            UserDefaults.standard.set(Double(lockContrastValue), forKey: savedLockContrastKey)
            UserDefaults.standard.set(Double(lockSaturationValue), forKey: savedLockSaturationKey)
        }

        refreshCard2UIForCurrentScope()
        syncLockScreenPreferencesToExtension()
    }

    func buildVideoComposition(for asset: AVAsset, mode: Int, fpsMode: Int) -> AVVideoComposition? {
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let natSize = track.naturalSize.applying(track.preferredTransform)
        let srcW = abs(natSize.width)
        let srcH = abs(natSize.height)
        guard srcW > 0 && srcH > 0 else { return nil }

        let targetFPS: Int32
        switch fpsMode {
        case 0: targetFPS = 30
        case 2: targetFPS = 120
        default: targetFPS = 60
        }

        let isNative4K = (mode >= 2)
        let targetW: CGFloat = (mode == 0) ? 1920.0 : 2560.0
        let targetH: CGFloat = (mode == 0) ? 1080.0 : 1440.0
        let scale = isNative4K ? 1.0 : min(targetW / srcW, targetH / srcH, 1.0)
        let nominal = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30.0

        // Khi ở 4K Gốc (không cần co tỉ lệ resolution):
        // Nếu chọn 60 FPS hoặc 120 FPS trên video có FPS tự nhiên phù hợp,
        // trả về nil để AVPlayer giải mã phần cứng trực tiếp (Zero-Copy) nhẹ nhất cho GPU/CPU.
        // Chỉ tạo composition khi:
        // 1. Cần scale phân giải (mode < 2)
        // 2. Hoặc người dùng chủ động ép về 30 FPS (fpsMode == 0) trên video có FPS > 32
        if isNative4K {
            if fpsMode == 1 && nominal <= 61.0 { return nil }
            if fpsMode == 2 { return nil }
            if fpsMode == 0 && nominal <= 31.0 { return nil }
        } else if scale >= 0.98 && abs(nominal - Float(targetFPS)) < 2.0 {
            return nil
        }

        let renderW = CGFloat(Int(round(srcW * scale)) & ~1)
        let renderH = CGFloat(Int(round(srcH * scale)) & ~1)

        let comp = AVMutableVideoComposition()
        comp.renderSize = CGSize(width: renderW, height: renderH)
        comp.frameDuration = CMTime(value: 1, timescale: targetFPS)
        comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let instruction = AVMutableVideoCompositionInstruction()
        let dur = asset.duration.isValid && asset.duration > .zero ? asset.duration : CMTime(seconds: 3600, preferredTimescale: 600)
        instruction.timeRange = CMTimeRange(start: .zero, duration: dur)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        var transform = track.preferredTransform
        if abs(scale - 1.0) > 0.01 {
            transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        }
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        comp.instructions = [instruction]
        return comp
    }

    func updateResolutionSegments(for url: URL, setDefaultToMax: Bool = false) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        let natSize = track.naturalSize.applying(track.preferredTransform)
        let w = abs(natSize.width)
        let h = abs(natSize.height)
        let maxDim = max(w, h)
        let minDim = min(w, h)

        let can2k = (maxDim >= 2000 || minDim >= 1200)
        let can4k = (maxDim >= 3200 || minDim >= 1800)

        resSegment?.setEnabled(true, forSegment: 0)
        resSegment?.setEnabled(can2k, forSegment: 1)
        resSegment?.setEnabled(can4k, forSegment: 2)

        let maxAllowed = can4k ? 2 : (can2k ? 1 : 0)
        if setDefaultToMax || resolutionMode > maxAllowed {
            resolutionMode = maxAllowed
            resSegment?.selectedSegment = resolutionMode
            UserDefaults.standard.set(resolutionMode, forKey: savedResKey)
        }
    }

    @objc func resolutionChanged() {
        guard let rSeg = resSegment else { return }
        let selected = rSeg.selectedSegment
        if rSeg.isEnabled(forSegment: selected) {
            resolutionMode = selected
        } else {
            rSeg.selectedSegment = resolutionMode
            return
        }
        pausedByCeiling = false
        overLimitStreak = 0
        graceUntil = Date().addingTimeInterval(3.0)
        UserDefaults.standard.set(resolutionMode, forKey: savedResKey)
        for player in players {
            if let currentItem = player.currentItem {
                currentItem.videoComposition = buildVideoComposition(for: currentItem.asset, mode: resolutionMode, fpsMode: fpsMode)
            }
        }
        refreshStatusLabels()
    }

    @objc func fpsChanged() {
        guard let fSeg = fpsSegment else { return }
        fpsMode = fSeg.selectedSegment
        pausedByCeiling = false
        overLimitStreak = 0
        graceUntil = Date().addingTimeInterval(3.0)
        UserDefaults.standard.set(fpsMode, forKey: savedFPSKey)
        for player in players {
            if let currentItem = player.currentItem {
                currentItem.videoComposition = buildVideoComposition(for: currentItem.asset, mode: resolutionMode, fpsMode: fpsMode)
            }
        }
        refreshStatusLabels()
    }

    // MARK: - 100% Native Apple All-in-One Video Pipeline (Không gọi tiến trình ngoài)
    func makeVideoOnlyAsset(from sourceURL: URL) -> AVAsset {
        let srcAsset = AVURLAsset(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let comp = AVMutableComposition()
        if let videoTrack = srcAsset.tracks(withMediaType: .video).first,
           let compTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: srcAsset.duration), of: videoTrack, at: .zero)
            compTrack.preferredTransform = videoTrack.preferredTransform
            return comp
        }
        return srcAsset
    }

    func resolveAndLoadVideo(originalURL: URL) {
        swapVideoSeamless(url: originalURL)
    }

    // MARK: - Kiến Trúc Cố Định 1 Cửa Sổ & 1 AVPlayer Duy Nhất (Chống Chớp Màn Hình 120Hz ProMotion & Chống Sinh Tiến Trình Phụ)
    func ensureDesktopInfrastructure() {
        guard desktopWindows.count != NSScreen.screens.count else { return }

        for obs in endObservers { NotificationCenter.default.removeObserver(obs) }
        endObservers.removeAll()
        for p in players { p.pause(); p.replaceCurrentItem(with: nil) }
        for l in playerLayers { l.player = nil; l.removeFromSuperlayer() }
        for w in desktopWindows { w.orderOut(nil) }
        for s in centerSensors { s.orderOut(nil) }
        for s in cornerSensors { s.orderOut(nil) }

        players.removeAll()
        playerLayers.removeAll()
        desktopWindows.removeAll()
        centerSensors.removeAll()
        cornerSensors.removeAll()

        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            // Đồng bộ trọn vẹn dải màu rộng tự nhiên của màn hình (Display P3 / Color LCD)
            window.colorSpace = screen.colorSpace ?? NSScreen.main?.colorSpace

            let vf = screen.visibleFrame
            let centerSensor = makeMicroSensor(
                rect: NSRect(x: vf.midX - 4, y: vf.midY - 4, width: 8, height: 8),
                level: desktopLevel + 1
            )
            let cornerSensor = makeMicroSensor(
                rect: NSRect(x: vf.minX + 40, y: vf.maxY - 48, width: 8, height: 8),
                level: desktopLevel + 1
            )

            let player = AVPlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false

            let containerView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            containerView.wantsLayer = true
            containerView.layer?.backgroundColor = NSColor.black.cgColor
            containerView.layerContentsRedrawPolicy = .never

            let playerLayer = AVPlayerLayer(player: player)
            if #available(macOS 14.0, *) {
                playerLayer.ToneMapMode_avoidIfNeeded()
            }
            // Khắc phục triệt để lỗi QuickTime Gamma Shift: Bộ lọc màu Metal shader thời gian thực (khớp chuẩn VLC tự nhiên)
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(contrastValue, forKey: "inputContrast")
                colorFilter.setValue(saturationValue, forKey: "inputSaturation")
                colorFilter.setValue(0.0, forKey: "inputBrightness")
                playerLayer.filters = [colorFilter]
            }
            containerView.layer?.addSublayer(playerLayer)

            window.contentView = containerView
            window.orderFront(nil)

            desktopWindows.append(window)
            centerSensors.append(centerSensor)
            cornerSensors.append(cornerSensor)
            playerLayers.append(playerLayer)
            players.append(player)
        }
        applyLayerTransformAndGravity()
    }

    func swapVideoSeamless(url: URL, isCached: Bool = false) {
        graceUntil = Date().addingTimeInterval(3.0)
        ensureDesktopInfrastructure()

        autoreleasepool {
            for obs in endObservers {
                NotificationCenter.default.removeObserver(obs)
            }
            endObservers.removeAll()

            let baseAsset: AVAsset = makeVideoOnlyAsset(from: url)
            let comp = buildVideoComposition(for: baseAsset, mode: resolutionMode, fpsMode: fpsMode)

            for player in players {
                let item = AVPlayerItem(asset: baseAsset)
                item.preferredForwardBufferDuration = 0.45
                item.videoComposition = comp

                let obs = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                    queue: .main
                ) { [weak self, weak player] _ in
                    self?.graceUntil = Date().addingTimeInterval(1.5)
                    player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                endObservers.append(obs)

                // Thay thế trực tiếp AVPlayerItem trên cùng 1 AVPlayer duy nhất: 0% chớp hình, 0 đẻ thêm VTDecoderXPCService
                player.replaceCurrentItem(with: item)
                player.isMuted = isMuted
            }

            applyLayerTransformAndGravity()
            userPaused = false
            pausedByCeiling = false
            overLimitStreak = 0
            playPauseBtn?.title = "Tạm dừng"
            updatePlaybackState()
        }
        malloc_zone_pressure_relief(nil, 0)
    }

    func applyLayerTransformAndGravity() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, layer) in playerLayers.enumerated() where i < desktopWindows.count {
            let win = desktopWindows[i]
            let screen = (i < NSScreen.screens.count) ? NSScreen.screens[i] : (win.screen ?? NSScreen.main)
            if let s = screen, win.frame != s.frame {
                win.setFrame(s.frame, display: true)
                win.contentView?.frame = NSRect(origin: .zero, size: s.frame.size)
            }
            let bounds = win.contentView?.bounds ?? win.frame

            switch gravityMode {
            case 1:
                layer.videoGravity = .resizeAspect
            case 2:
                layer.videoGravity = .resize
            default:
                layer.videoGravity = .resizeAspectFill
            }

            let w = bounds.width * zoomScale
            let h = bounds.height * zoomScale
            let x = (bounds.width - w) / 2.0 + offsetX
            let y = (bounds.height - h) / 2.0 + offsetY
            layer.frame = NSRect(x: x, y: y, width: w, height: h)
            layer.setNeedsLayout()
            layer.layoutIfNeeded()
        }
        CATransaction.commit()
    }

    @objc func screensDidChange() {
        let screens = NSScreen.screens
        if desktopWindows.count == screens.count {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, screen) in screens.enumerated() where i < desktopWindows.count {
                let win = desktopWindows[i]
                win.setFrame(screen.frame, display: true)
                win.colorSpace = screen.colorSpace ?? NSScreen.main?.colorSpace
                win.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
                let vf = screen.visibleFrame
                if i < centerSensors.count {
                    centerSensors[i].setFrame(NSRect(x: vf.midX - 4, y: vf.midY - 4, width: 8, height: 8), display: false)
                }
                if i < cornerSensors.count {
                    cornerSensors[i].setFrame(NSRect(x: vf.minX + 40, y: vf.maxY - 48, width: 8, height: 8), display: false)
                }
            }
            applyLayerTransformAndGravity()
            CATransaction.commit()
            updatePlaybackState()
        } else {
            ensureDesktopInfrastructure()
            if let targetURL = activeVideoURL {
                resolveAndLoadVideo(originalURL: targetURL)
            }
        }
    }

    func handleInactiveStateTransition() {
        stateEvalWorkItem?.cancel()
        stateEvalWorkItem = nil
        pauseDebounceWorkItem?.cancel()
        pauseDebounceWorkItem = nil

        if isScreenAsleep {
            ceilingTimer?.invalidate()
            ceilingTimer = nil
            for player in players where player.rate != 0 {
                player.pause()
            }
            malloc_zone_pressure_relief(nil, 0)
        } else {
            pausedByCeiling = false
            pausedBySystemHeavyLoad = false
            heavySysLoadStreak = 0
            overLimitStreak = 0
            graceUntil = Date().addingTimeInterval(2.5)
            startCeilingMonitor()
            updatePlaybackState()
        }
    }

    @objc func screenDidSleep() {
        isDisplayAsleep = true
        handleInactiveStateTransition()
    }

    @objc func screenDidWake() {
        isDisplayAsleep = false
        handleInactiveStateTransition()
    }

    @objc func screenDidLock() {
        isScreenLocked = true
        handleInactiveStateTransition()
    }

    @objc func screenDidUnlock() {
        isScreenLocked = false
        handleInactiveStateTransition()
    }

    @objc func screenSaverDidStart() {
        isScreenSaverRunning = true
        handleInactiveStateTransition()
    }

    @objc func screenSaverDidStop() {
        isScreenSaverRunning = false
        handleInactiveStateTransition()
    }

    @objc func occlusionDidChange(_ notification: Notification) {
        guard !isScreenAsleep else { return }
        schedulePlaybackStateUpdate(delay: 0.06)
    }

    func updatePlaybackState() {
        if isScreenAsleep {
            pauseDebounceWorkItem?.cancel()
            pauseDebounceWorkItem = nil
            for player in players where player.rate != 0 {
                player.pause()
            }
            return
        }

        let proAppActive = isProEditorOrHeavyAppFrontmost()
        let isPreviewingGeometry = Date() < previewingGeometryUntil
        let screens = NSScreen.screens
        var anyShouldPlay = false
        var anyNeedsDebouncedPause = false

        for (index, player) in players.enumerated() where index < screens.count {
            let covPercent = proAppActive ? 100.0 : calculateScreenCoveragePercent(for: screens[index], index: index)
            if index == 0 {
                lastCoveragePercent = covPercent
            }

            let shouldPauseByWindow: Bool
            if isPreviewingGeometry || !autoPause90Enabled {
                shouldPauseByWindow = false
            } else {
                shouldPauseByWindow = (covPercent >= autoPauseThreshold) || proAppActive
            }

            if shouldPauseByWindow {
                pausedByCeiling = false
                overLimitStreak = 0
            }

            let shouldPlay = !userPaused && !isScreenAsleep && !shouldPauseByWindow && !pausedByCeiling && !pausedBySystemHeavyLoad

            if shouldPlay {
                anyShouldPlay = true
                if player.rate != 1.0 {
                    graceUntil = Date().addingTimeInterval(2.5)
                    player.rate = 1.0
                }
            } else {
                if userPaused || pausedByCeiling || pausedBySystemHeavyLoad {
                    if player.rate != 0 {
                        player.pause()
                        malloc_zone_pressure_relief(nil, 0)
                    }
                } else if player.rate != 0 {
                    // Cửa sổ đạt trên 90%: Chờ mượt 0.45s cho hiệu ứng chuyển cửa sổ/Desktop của macOS hoàn tất rồi mới ngắt giải mã
                    anyNeedsDebouncedPause = true
                }
            }
        }

        if anyShouldPlay {
            pauseDebounceWorkItem?.cancel()
            pauseDebounceWorkItem = nil
        } else if anyNeedsDebouncedPause && pauseDebounceWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.pauseDebounceWorkItem = nil
                guard !self.isScreenAsleep else { return }
                let proNow = self.isProEditorOrHeavyAppFrontmost()
                let covNow = proNow ? 100.0 : (NSScreen.screens.first.map { self.calculateScreenCoveragePercent(for: $0, index: 0) } ?? 0.0)
                self.lastCoveragePercent = covNow
                if self.autoPause90Enabled && (covNow >= self.autoPauseThreshold || proNow) && Date() >= self.previewingGeometryUntil {
                    var didPauseAny = false
                    for player in self.players where player.rate != 0 {
                        player.pause()
                        didPauseAny = true
                    }
                    if didPauseAny {
                        self.smoothedCPU = 0.0
                        malloc_zone_pressure_relief(nil, 0)
                    }
                    self.refreshStatusLabels()
                }
            }
            pauseDebounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }

        refreshStatusLabels()
    }

    @objc func toggleMute() {
        guard let sw = muteSwitch else { return }
        isMuted = (sw.state == .on)
        for player in players {
            player.isMuted = isMuted
        }
    }

    @objc func chooseVideo() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Chọn Video Nền"
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let durationSec = CMTimeGetSeconds(asset.duration)
            if durationSec > 60.5 {
                let alert = NSAlert()
                alert.messageText = "Thời lượng video vượt quá 1 phút"
                alert.informativeText = String(format: "Video bạn chọn dài %.1f giây. Vui lòng chọn video ngắn dưới 60 giây (1 phút) để đảm bảo hình nền lặp mượt mà và tiết kiệm tối đa RAM/CPU.", durationSec)
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Đã hiểu")
                alert.runModal()
                return
            }

            UserDefaults.standard.set(url.path, forKey: savedVideoKey)
            fileLabel?.stringValue = url.lastPathComponent
            pausedByCeiling = false
            overLimitStreak = 0
            graceUntil = Date().addingTimeInterval(3.0)
            updateResolutionSegments(for: url, setDefaultToMax: true)
            resolveAndLoadVideo(originalURL: url)
            LockScreenManager.shared.updateActiveVideo(url: url)
        }
        malloc_zone_pressure_relief(nil, 0)
    }

    func makeMicroSensor(rect: NSRect, level: Int) -> NSWindow {
        let sensor = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        sensor.level = NSWindow.Level(rawValue: level)
        sensor.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sensor.isOpaque = true
        sensor.alphaValue = 0.01
        sensor.backgroundColor = .black
        sensor.ignoresMouseEvents = true
        sensor.hasShadow = false
        sensor.isReleasedWhenClosed = false
        sensor.orderFront(nil)
        return sensor
    }

    @objc func togglePlayPause() {
        userPaused.toggle()
        if !userPaused {
            pausedByCeiling = false
            overLimitStreak = 0
            graceUntil = Date().addingTimeInterval(2.5)
        }
        playPauseBtn?.title = userPaused ? "Phát tiếp" : "Tạm dừng"
        updatePlaybackState()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

extension AVPlayerLayer {
    func ToneMapMode_avoidIfNeeded() {
        // Giữ độ sáng SDR ổn định trên tấm nền mini-LED XDR, không kích xung EDR gây nóng màn hình
        if self.responds(to: Selector(("setWantsExtendedDynamicRangeContent:"))) {
            self.setValue(false, forKey: "wantsExtendedDynamicRangeContent")
        }
    }
}

let app = NSApplication.shared
let delegate = WallpaperAppDelegate()
app.delegate = delegate
app.run()
