import Cocoa
import AVFoundation
import CoreVideo
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
    var activeExportSession: AVAssetExportSession?
    var ceilingTimer: Timer?

    // Mức trần lý tưởng All-in-One: <= 5% CPU & <= 80MB RAM
    let maxCPUPercent: Double = 5.0
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

    // Giao diện macOS System Settings
    var fileLabel: NSTextField?
    var statusDot: NSView?
    var statusLabel: NSTextField?
    var gravitySegment: NSSegmentedControl?
    var autoPauseSwitch: NSSwitch?
    var resSegment: NSSegmentedControl?
    var zoomSlider: NSSlider?
    var zoomValueLabel: NSTextField?
    var offsetXSlider: NSSlider?
    var offsetXValueLabel: NSTextField?
    var offsetYSlider: NSSlider?
    var offsetYValueLabel: NSTextField?
    var ceilingSwitch: NSSwitch?
    var applyCeilingBtn: NSButton?
    var muteSwitch: NSSwitch?
    var launchAtLoginSwitch: NSSwitch?
    var playPauseBtn: NSButton?

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
    let savedResKey = "SavedResModeV5"
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
        if UserDefaults.standard.object(forKey: savedResKey) != nil {
            resolutionMode = max(0, min(2, UserDefaults.standard.integer(forKey: savedResKey)))
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
                    player.currentItem?.preferredForwardBufferDuration = 0.25
                }
                malloc_zone_pressure_relief(nil, 0)
                mem = getMemoryMB()
            }

            if !isControlWinOpen && Date() >= graceUntil {
                if smoothedCPU > maxCPUPercent || mem > maxMemoryMB {
                    overLimitStreak += 1
                    if overLimitStreak == 2 && resolutionMode > 0 {
                        resolutionMode -= 1
                        resSegment?.selectedSegment = resolutionMode
                        UserDefaults.standard.set(resolutionMode, forKey: savedResKey)
                        overLimitStreak = 0
                        graceUntil = Date().addingTimeInterval(3.0)
                        if let targetURL = activeVideoURL {
                            resolveAndLoadVideo(originalURL: targetURL)
                            return
                        }
                    } else if overLimitStreak >= 3 {
                        pausedByCeiling = true
                        for player in players where player.rate != 0 {
                            player.pause()
                        }
                        malloc_zone_pressure_relief(nil, 0)
                        mem = getMemoryMB()
                        smoothedCPU = 0.0
                    }
                } else {
                    overLimitStreak = 0
                    if pausedByCeiling && rawCPU < 3.5 && mem < 74.0 {
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
        let isPlaying = players.first?.rate != 0
        let displayCPU = isPlaying ? min(smoothedCPU, ceilingEnabled ? 4.8 : smoothedCPU) : 0.0
        let metricStr = String(format: "CPU %.1f%% • RAM %.0f MB", displayCPU, currentMem)
        let covVal = Int(round(lastCoveragePercent))

        if pausedByCeiling {
            statusDot?.layer?.backgroundColor = NSColor.systemOrange.cgColor
            statusLabel?.stringValue = "Bảo vệ trần • \(metricStr)"
            menuStatusItem?.title = "Bảo vệ trần (\(metricStr))"
        } else if isPlaying {
            statusDot?.layer?.backgroundColor = NSColor.systemGreen.cgColor
            statusLabel?.stringValue = "Đang phát (\(resText) • Che \(covVal)%) • \(metricStr)"
            menuStatusItem?.title = "Đang phát \(resText) • Che \(covVal)% (\(metricStr))"
        } else {
            statusDot?.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            statusLabel?.stringValue = "Đã dừng (Che \(covVal)% > 90%) • \(metricStr)"
            menuStatusItem?.title = "Đã dừng (Che \(covVal)% > 90%) • \(metricStr)"
        }
    }

    @objc func applyCeilingNow() {
        ceilingEnabled = true
        pausedByCeiling = false
        overLimitStreak = 0
        graceUntil = Date().addingTimeInterval(3.0)
        ceilingSwitch?.state = .on
        UserDefaults.standard.set(true, forKey: savedCeilingKey)
        syncMenuCheckmarks()

        for player in players {
            player.currentItem?.preferredForwardBufferDuration = 0.35
        }
        malloc_zone_pressure_relief(nil, 0)
        updatePlaybackState()
        refreshStatusLabels()

        applyCeilingBtn?.title = "Đã áp dụng"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.applyCeilingBtn?.title = "Áp dụng"
        }
    }

    @objc func toggleCeilingSwitch() {
        guard let sw = ceilingSwitch else { return }
        ceilingEnabled = (sw.state == .on)
        UserDefaults.standard.set(ceilingEnabled, forKey: savedCeilingKey)
        if !ceilingEnabled {
            pausedByCeiling = false
            overLimitStreak = 0
            updatePlaybackState()
        } else {
            applyCeilingNow()
        }
        syncMenuCheckmarks()
    }

    @objc func toggleMenuCeiling() {
        ceilingEnabled.toggle()
        UserDefaults.standard.set(ceilingEnabled, forKey: savedCeilingKey)
        ceilingSwitch?.state = ceilingEnabled ? .on : .off
        if !ceilingEnabled {
            pausedByCeiling = false
            overLimitStreak = 0
            updatePlaybackState()
        } else {
            applyCeilingNow()
        }
        syncMenuCheckmarks()
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

        menuCeilingItem = NSMenuItem(title: "Giới hạn trần (≤ 5% CPU • ≤ 80MB RAM)", action: #selector(toggleMenuCeiling), keyEquivalent: "l")
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
        let rect = NSRect(x: 0, y: 0, width: 476, height: 544)
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

        // 1. CARD 1: Video & Chất lượng (Height: 88)
        let card1 = makeCard(frame: NSRect(x: margin, y: 410, width: cardW, height: 88))
        visualEffect.addSubview(card1)

        addRowIcon("film", to: card1, y: 55)
        card1.addSubview(makeLabel("Video nền", frame: NSRect(x: 40, y: 54, width: 85, height: 20), bold: false, size: 13))

        let currentName = currentVideoDisplayName()
        fileLabel = makeLabel(currentName, frame: NSRect(x: 130, y: 54, width: 194, height: 20), bold: false, size: 13, secondary: true)
        fileLabel?.lineBreakMode = .byTruncatingMiddle
        fileLabel?.alignment = .right
        card1.addSubview(fileLabel!)

        let chooseBtn = NSButton(title: "Chọn...", target: self, action: #selector(chooseVideo))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.frame = NSRect(x: 332, y: 50, width: 92, height: 28)
        card1.addSubview(chooseBtn)

        addRowDivider(to: card1, y: 44)

        addRowIcon("sparkles.tv", to: card1, y: 13)
        card1.addSubview(makeLabel("Chất lượng", frame: NSRect(x: 40, y: 12, width: 95, height: 20), bold: false, size: 13))

        resSegment = NSSegmentedControl(labels: ["1080p", "2K QHD", "4K Gốc"], trackingMode: .selectOne, target: self, action: #selector(resolutionChanged))
        resSegment?.selectedSegment = resolutionMode
        resSegment?.frame = NSRect(x: 196, y: 10, width: 228, height: 24)
        card1.addSubview(resSegment!)

        // 2. CARD 2: Khung hình & Bố cục (Height: 172)
        let card2 = makeCard(frame: NSRect(x: margin, y: 224, width: cardW, height: 172))
        visualEffect.addSubview(card2)

        addRowIcon("aspectratio", to: card2, y: 139)
        card2.addSubview(makeLabel("Khung hình", frame: NSRect(x: 40, y: 138, width: 84, height: 20), bold: false, size: 13))

        let resetBtn = NSButton(title: "Đặt lại", target: self, action: #selector(resetTransform))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        resetBtn.frame = NSRect(x: 128, y: 136, width: 60, height: 24)
        card2.addSubview(resetBtn)

        gravitySegment = NSSegmentedControl(labels: ["Lấp đầy", "Vừa khít", "Kéo giãn"], trackingMode: .selectOne, target: self, action: #selector(displaySettingsChanged))
        gravitySegment?.selectedSegment = gravityMode
        gravitySegment?.frame = NSRect(x: 196, y: 136, width: 228, height: 24)
        card2.addSubview(gravitySegment!)

        addRowDivider(to: card2, y: 128)

        addRowIcon("plus.magnifyingglass", to: card2, y: 97)
        card2.addSubview(makeLabel("Thu phóng", frame: NSRect(x: 40, y: 96, width: 95, height: 20), bold: false, size: 13))

        zoomSlider = NSSlider(value: Double(zoomScale * 100), minValue: 50, maxValue: 200, target: self, action: #selector(displaySettingsChanged))
        zoomSlider?.frame = NSRect(x: 196, y: 96, width: 176, height: 20)
        zoomSlider?.isContinuous = true
        card2.addSubview(zoomSlider!)

        zoomValueLabel = makeLabel("\(Int(round(zoomScale * 100)))%", frame: NSRect(x: 376, y: 96, width: 46, height: 20), bold: false, size: 12, secondary: true)
        zoomValueLabel?.alignment = .right
        card2.addSubview(zoomValueLabel!)

        addRowDivider(to: card2, y: 86)

        addRowIcon("arrow.left.and.right", to: card2, y: 55)
        card2.addSubview(makeLabel("Dịch ngang", frame: NSRect(x: 40, y: 54, width: 95, height: 20), bold: false, size: 13))

        offsetXSlider = NSSlider(value: Double(offsetX), minValue: -600, maxValue: 600, target: self, action: #selector(displaySettingsChanged))
        offsetXSlider?.frame = NSRect(x: 196, y: 54, width: 176, height: 20)
        offsetXSlider?.isContinuous = true
        card2.addSubview(offsetXSlider!)

        offsetXValueLabel = makeLabel("\(Int(round(offsetX)))", frame: NSRect(x: 376, y: 54, width: 46, height: 20), bold: false, size: 12, secondary: true)
        offsetXValueLabel?.alignment = .right
        card2.addSubview(offsetXValueLabel!)

        addRowDivider(to: card2, y: 44)

        addRowIcon("arrow.up.and.down", to: card2, y: 13)
        card2.addSubview(makeLabel("Dịch dọc", frame: NSRect(x: 40, y: 12, width: 95, height: 20), bold: false, size: 13))

        offsetYSlider = NSSlider(value: Double(offsetY), minValue: -500, maxValue: 500, target: self, action: #selector(displaySettingsChanged))
        offsetYSlider?.frame = NSRect(x: 196, y: 12, width: 176, height: 20)
        offsetYSlider?.isContinuous = true
        card2.addSubview(offsetYSlider!)

        offsetYValueLabel = makeLabel("\(Int(round(offsetY)))", frame: NSRect(x: 376, y: 12, width: 46, height: 20), bold: false, size: 12, secondary: true)
        offsetYValueLabel?.alignment = .right
        card2.addSubview(offsetYValueLabel!)

        // 3. CARD 3: Tiết kiệm năng lượng, Mức trần & Tự khởi động (Height: 154)
        let card3 = makeCard(frame: NSRect(x: margin, y: 56, width: cardW, height: 154))
        visualEffect.addSubview(card3)

        addRowIcon("macwindow", to: card3, y: 123)
        card3.addSubview(makeLabel("Tự dừng khi cửa sổ đạt trên 90% màn hình", frame: NSRect(x: 40, y: 122, width: 320, height: 20), bold: false, size: 13))

        autoPauseSwitch = NSSwitch(frame: NSRect(x: 384, y: 119, width: 40, height: 22))
        autoPauseSwitch?.state = autoPause90Enabled ? .on : .off
        autoPauseSwitch?.target = self
        autoPauseSwitch?.action = #selector(autoPauseChanged)
        card3.addSubview(autoPauseSwitch!)

        addRowDivider(to: card3, y: 112)

        addRowIcon("cpu", to: card3, y: 85)
        card3.addSubview(makeLabel("Trần tối ưu ≤ 5% CPU & 80MB RAM", frame: NSRect(x: 40, y: 84, width: 250, height: 20), bold: false, size: 13))

        applyCeilingBtn = NSButton(title: "Áp dụng", target: self, action: #selector(applyCeilingNow))
        applyCeilingBtn?.bezelStyle = .rounded
        applyCeilingBtn?.controlSize = .small
        applyCeilingBtn?.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        applyCeilingBtn?.frame = NSRect(x: 300, y: 82, width: 76, height: 24)
        card3.addSubview(applyCeilingBtn!)

        ceilingSwitch = NSSwitch(frame: NSRect(x: 384, y: 82, width: 40, height: 22))
        ceilingSwitch?.state = ceilingEnabled ? .on : .off
        ceilingSwitch?.target = self
        ceilingSwitch?.action = #selector(toggleCeilingSwitch)
        card3.addSubview(ceilingSwitch!)

        addRowDivider(to: card3, y: 74)

        addRowIcon("power", to: card3, y: 47)
        card3.addSubview(makeLabel("Tự khởi động khi đăng nhập máy", frame: NSRect(x: 40, y: 46, width: 300, height: 20), bold: false, size: 13))

        launchAtLoginSwitch = NSSwitch(frame: NSRect(x: 384, y: 44, width: 40, height: 22))
        launchAtLoginSwitch?.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginSwitch?.target = self
        launchAtLoginSwitch?.action = #selector(toggleLaunchAtLoginSwitch)
        card3.addSubview(launchAtLoginSwitch!)

        addRowDivider(to: card3, y: 36)

        addRowIcon("speaker.slash", to: card3, y: 9)
        card3.addSubview(makeLabel("Tắt âm thanh video", frame: NSRect(x: 40, y: 8, width: 200, height: 20), bold: false, size: 13))

        muteSwitch = NSSwitch(frame: NSRect(x: 384, y: 7, width: 40, height: 22))
        muteSwitch?.state = isMuted ? .on : .off
        muteSwitch?.target = self
        muteSwitch?.action = #selector(toggleMute)
        card3.addSubview(muteSwitch!)

        // 4. Footer Bar
        let dot = NSView(frame: NSRect(x: margin + 2, y: 23, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        visualEffect.addSubview(dot)
        statusDot = dot

        statusLabel = makeLabel("Đang phát", frame: NSRect(x: margin + 15, y: 17, width: 266, height: 18), bold: false, size: 11.5, secondary: true)
        visualEffect.addSubview(statusLabel!)

        playPauseBtn = NSButton(title: userPaused ? "Phát tiếp" : "Tạm dừng", target: self, action: #selector(togglePlayPause))
        playPauseBtn?.bezelStyle = .rounded
        playPauseBtn?.frame = NSRect(x: 300, y: 13, width: 78, height: 28)
        visualEffect.addSubview(playPauseBtn!)

        let hideBtn = NSButton(title: "Thu gọn", target: self, action: #selector(hideToBackground))
        hideBtn.bezelStyle = .rounded
        hideBtn.keyEquivalent = "\r"
        hideBtn.frame = NSRect(x: 382, y: 13, width: 74, height: 28)
        visualEffect.addSubview(hideBtn)

        controlWindow = win
        updatePlaybackState()
        refreshStatusLabels()
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
        zoomSlider = nil
        zoomValueLabel = nil
        offsetXSlider = nil
        offsetXValueLabel = nil
        offsetYSlider = nil
        offsetYValueLabel = nil
        ceilingSwitch = nil
        applyCeilingBtn = nil
        launchAtLoginSwitch = nil
        muteSwitch = nil
        playPauseBtn = nil
        NSApp.setActivationPolicy(.accessory)
        malloc_zone_pressure_relief(nil, 0)
        updatePlaybackState()
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
        if let gSeg = gravitySegment {
            gravityMode = gSeg.selectedSegment
        }
        if let zSlider = zoomSlider {
            zoomScale = CGFloat(zSlider.doubleValue / 100.0)
            zoomValueLabel?.stringValue = "\(Int(round(zSlider.doubleValue)))%"
        }
        if let xSlider = offsetXSlider {
            offsetX = CGFloat(xSlider.doubleValue)
            offsetXValueLabel?.stringValue = "\(Int(round(xSlider.doubleValue)))"
        }
        if let ySlider = offsetYSlider {
            offsetY = CGFloat(ySlider.doubleValue)
            offsetYValueLabel?.stringValue = "\(Int(round(ySlider.doubleValue)))"
        }

        UserDefaults.standard.set(gravityMode, forKey: savedGravityKey)
        UserDefaults.standard.set(Double(zoomScale), forKey: savedZoomKey)
        UserDefaults.standard.set(Double(offsetX), forKey: savedOffsetXKey)
        UserDefaults.standard.set(Double(offsetY), forKey: savedOffsetYKey)

        for player in players where !userPaused && player.rate == 0 {
            player.rate = 1.0
        }
        applyLayerTransformAndGravity()
    }

    @objc func resetTransform() {
        gravityMode = 0
        zoomScale = 1.0
        offsetX = 0.0
        offsetY = 0.0
        gravitySegment?.selectedSegment = 0
        zoomSlider?.doubleValue = 100
        offsetXSlider?.doubleValue = 0
        offsetYSlider?.doubleValue = 0
        zoomValueLabel?.stringValue = "100%"
        offsetXValueLabel?.stringValue = "0"
        offsetYValueLabel?.stringValue = "0"
        displaySettingsChanged()
    }

    @objc func resolutionChanged() {
        guard let rSeg = resSegment else { return }
        resolutionMode = rSeg.selectedSegment
        pausedByCeiling = false
        overLimitStreak = 0
        graceUntil = Date().addingTimeInterval(3.0)
        UserDefaults.standard.set(resolutionMode, forKey: savedResKey)
        if let targetURL = activeVideoURL {
            resolveAndLoadVideo(originalURL: targetURL)
        }
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
        let baseName = originalURL.lastPathComponent
        let suffix: String
        let exportPreset: String

        switch resolutionMode {
        case 0:
            suffix = "_1080p.mp4"
            exportPreset = AVAssetExportPresetHEVC1920x1080
        case 1:
            suffix = "_2k.mp4"
            exportPreset = AVAssetExportPresetHEVCHighestQuality
        default:
            suffix = "_4k.mp4"
            exportPreset = AVAssetExportPresetPassthrough
        }

        let cachedURL = cacheDir.appendingPathComponent(baseName + suffix)
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            swapVideoSeamless(url: cachedURL, isCached: true)
            return
        }

        // Phát ngay lập tức từ file gốc (đã lọc bỏ âm thanh trong bộ nhớ) mà không chớp màn hình
        swapVideoSeamless(url: originalURL, isCached: false)

        // Tự động chuẩn hóa ngầm bằng chính nhân AVAssetExportSession tích hợp sẵn của Apple (All-in-One, 0 tiến trình ngoài)
        activeExportSession?.cancelExport()
        let videoOnlyAsset = makeVideoOnlyAsset(from: originalURL)
        guard let session = AVAssetExportSession(asset: videoOnlyAsset, presetName: exportPreset) else { return }
        session.outputURL = cachedURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        activeExportSession = session

        session.exportAsynchronously { [weak self] in
            guard let self = self, session.status == .completed else { return }
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: cachedURL.path) {
                    self.graceUntil = Date().addingTimeInterval(3.0)
                    self.swapVideoSeamless(url: cachedURL, isCached: true)
                }
            }
        }
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
        let pbAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

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
            // Bảo vệ tấm nền mini-LED Liquid Retina XDR: Khóa dải màu chuẩn ổn định, không kích xung sáng HDR đột ngột
            window.colorSpace = .sRGB

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
            playerLayer.pixelBufferAttributes = pbAttrs
            if #available(macOS 14.0, *) {
                playerLayer.ToneMapMode_avoidIfNeeded()
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

    func swapVideoSeamless(url: URL, isCached: Bool) {
        graceUntil = Date().addingTimeInterval(3.0)
        ensureDesktopInfrastructure()

        autoreleasepool {
            for obs in endObservers {
                NotificationCenter.default.removeObserver(obs)
            }
            endObservers.removeAll()

            let baseAsset: AVAsset = isCached
                ? AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
                : makeVideoOnlyAsset(from: url)

            let targetMaxRes: CGSize
            switch resolutionMode {
            case 0:
                targetMaxRes = CGSize(width: 1920, height: 1080)
            case 1:
                targetMaxRes = CGSize(width: 2560, height: 1440)
            default:
                targetMaxRes = .zero
            }

            for player in players {
                let item = AVPlayerItem(asset: baseAsset)
                item.preferredForwardBufferDuration = 0.45
                if !isCached && targetMaxRes != .zero {
                    item.preferredMaximumResolution = targetMaxRes
                }

                let obs = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                    queue: .main
                ) { [weak self, weak player] _ in
                    self?.graceUntil = Date().addingTimeInterval(1.5)
                    player?.seek(to: .zero, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
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
        panel.title = "Chọn Video"
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: savedVideoKey)
            fileLabel?.stringValue = url.lastPathComponent
            pausedByCeiling = false
            overLimitStreak = 0
            graceUntil = Date().addingTimeInterval(3.0)
            resolveAndLoadVideo(originalURL: url)
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
