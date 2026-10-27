import Foundation

/// Preferences are written by the main Muro app into the extension container.
/// Lock-screen playback is intentionally the safe default: the existing Muro
/// window engine remains the only component allowed to animate the desktop.
final class ExtensionPreferences: @unchecked Sendable {
    static let shared = ExtensionPreferences()

    private struct FileContents: Codable {
        var alwaysPauseDesktop: Bool
        var gravityMode: Int?
        var zoomScale: Double?
        var offsetX: Double?
        var offsetY: Double?
        var contrast: Double?
        var saturation: Double?
    }

    private let lock = NSLock()
    private var pauseDesktop = true
    private var currentGravityMode: Int = 0
    private var currentZoomScale: CGFloat = 1.0
    private var currentOffsetX: CGFloat = 0.0
    private var currentOffsetY: CGFloat = 0.0
    private var currentContrast: Float = 1.0
    private var currentSaturation: Float = 1.0

    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("kmo-prefs.json")
    }

    private init() {
        reload()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in ExtensionPreferences.shared.reloadAndApply() },
            "com.kmo.KMO_LiveWallpaper.wallpaper.preferences-changed" as CFString,
            nil,
            .deliverImmediately
        )
        // The app posts this whenever it stages or removes a video. The one
        // case that needs an answer is a playlist or automation step on the
        // lock screen or the screen saver; everything else is left alone.
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in RendererState.shared.handleLibraryChanged() },
            "com.kmo.KMO_LiveWallpaper.wallpaper.library-changed" as CFString,
            nil,
            .deliverImmediately
        )
    }

    var alwaysPauseDesktop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pauseDesktop
    }

    var gravityMode: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentGravityMode
    }

    var zoomScale: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return currentZoomScale
    }

    var offsetX: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return currentOffsetX
    }

    var offsetY: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return currentOffsetY
    }

    var contrast: Float {
        lock.lock()
        defer { lock.unlock() }
        return currentContrast
    }

    var saturation: Float {
        lock.lock()
        defer { lock.unlock() }
        return currentSaturation
    }

    /// The app writes preferences and the desktop still through the same
    /// notification, so both are picked up here.
    func reloadAndApply() {
        reload()
        RendererState.shared.applyCurrentStyling()
        RendererState.shared.refreshDesktopStill()
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Self.url),
              let contents = try? JSONDecoder().decode(FileContents.self, from: data)
        else { return }
        lock.lock()
        pauseDesktop = contents.alwaysPauseDesktop
        currentGravityMode = contents.gravityMode ?? 0
        currentZoomScale = CGFloat(contents.zoomScale ?? 1.0)
        currentOffsetX = CGFloat(contents.offsetX ?? 0.0)
        currentOffsetY = CGFloat(contents.offsetY ?? 0.0)
        currentContrast = Float(contents.contrast ?? 1.0)
        currentSaturation = Float(contents.saturation ?? 1.0)
        lock.unlock()
    }
}

final class ExtensionPlaybackCoordinator: @unchecked Sendable {
    static let shared = ExtensionPlaybackCoordinator()
    private var tokens: [NSObjectProtocol] = []

    private init() {
        _ = ExtensionPreferences.shared
        let center = DistributedNotificationCenter.default()
        tokens.append(center.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: nil
        ) { _ in
            RendererState.shared.setPresentation(mode: "locked", activity: "active")
        })
        tokens.append(center.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: nil
        ) { _ in
            RendererState.shared.setPresentation(mode: "default", activity: "active")
        })
        // Logging in at the login window is not an unlock and posts neither of
        // the two above. A surface created there is playing because the screen
        // was covered, and without this it would carry on playing behind the
        // desktop once somebody logged in. It also repaints, because logging
        // in is the moment the desktop is first looked at.
        for name in ["com.apple.sessionDidMoveOnConsole", "com.apple.sessionDidMoveOffConsole"] {
            tokens.append(center.addObserver(
                forName: .init(name),
                object: nil,
                queue: nil
            ) { _ in
                RendererState.shared.refreshDesktopStill()
            })
        }
    }
}
