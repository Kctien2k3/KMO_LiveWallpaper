import Foundation
import AppKit
import AVFoundation

final class LockScreenManager {
    static let shared = LockScreenManager()

    let extensionBundleID = "com.kmo.KMO_LiveWallpaper.wallpaper-extension"

    var containerDocsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Documents", isDirectory: true)
    }

    var storeURLs: [URL] {
        let storeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        return [
            storeDir.appendingPathComponent("Index.plist"),
            storeDir.appendingPathComponent("Index2.plist")
        ]
    }

    var backupDirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/KMO_Backup", isDirectory: true)
    }

    let savedLockScreenKey = "SavedLockScreenEnabledV1"
    let savedScreenSaverKey = "SavedScreenSaverEnabledV1"

    var lockScreenEnabled: Bool = false
    var screenSaverEnabled: Bool = false

    private init() {
        lockScreenEnabled = UserDefaults.standard.bool(forKey: savedLockScreenKey)
        screenSaverEnabled = UserDefaults.standard.bool(forKey: savedScreenSaverKey)
    }

    func ensureBackupsExist() {
        let manager = FileManager.default
        try? manager.createDirectory(at: backupDirURL, withIntermediateDirectories: true)
        for url in storeURLs where manager.fileExists(atPath: url.path) {
            let bak = backupDirURL.appendingPathComponent("\(url.lastPathComponent).bak")
            if !manager.fileExists(atPath: bak.path) {
                try? manager.copyItem(at: url, to: bak)
            }
        }
    }

    func registerExtension() {
        let appPaths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Extensions/KMOWallpaperExtension.appex").path,
            "/Applications/KMO_LiveWallpaper.app/Contents/Extensions/KMOWallpaperExtension.appex"
        ]
        for extPath in appPaths where FileManager.default.fileExists(atPath: extPath) {
            _ = run("/usr/bin/xattr", ["-cr", extPath])
            _ = run("/usr/bin/pluginkit", ["-a", extPath])
            _ = run("/usr/bin/pluginkit", ["-e", "use", "-i", extensionBundleID])
            break
        }
    }

    func stageVideo(url: URL) -> URL? {
        let manager = FileManager.default
        let videos = containerDocsURL.appendingPathComponent("videos", isDirectory: true)
        try? manager.createDirectory(at: videos, withIntermediateDirectories: true)

        let wallpaperID = "kmo-active-wallpaper"
        let destDir = videos.appendingPathComponent(wallpaperID, isDirectory: true)
        try? manager.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destVideo = destDir.appendingPathComponent("wallpaper.mov")

        // Hard link or copy video
        if manager.fileExists(atPath: destVideo.path) {
            try? manager.removeItem(at: destVideo)
        }
        if (try? manager.linkItem(at: url, to: destVideo)) == nil {
            try? manager.copyItem(at: url, to: destVideo)
        }

        // Generate thumbnail
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        if let cgImg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            if let data = rep.representation(using: .jpeg, properties: [:]) {
                try? data.write(to: destDir.appendingPathComponent("thumbnail.jpg"))
            }
        }

        // Write library.json
        let libData = """
        {"wallpapers":[{"id":"\(wallpaperID)","title":"\(url.deletingPathExtension().lastPathComponent)","videoFilename":"wallpaper.mov","thumbnailFilename":"thumbnail.jpg"}]}
        """.data(using: .utf8)!
        try? libData.write(to: containerDocsURL.appendingPathComponent("library.json"))

        // Write kmo-prefs.json
        writePrefs()

        return destVideo
    }

    private var lastPrefsDict: [String: Any] = [
        "alwaysPauseDesktop": true,
        "gravityMode": 0,
        "zoomScale": 1.0,
        "offsetX": 0.0,
        "offsetY": 0.0,
        "contrast": 1.05,
        "saturation": 1.05
    ]

    func syncPreferences(
        gravityMode: Int,
        zoomScale: Double,
        offsetX: Double,
        offsetY: Double,
        contrast: Double,
        saturation: Double
    ) {
        lastPrefsDict = [
            "alwaysPauseDesktop": true,
            "gravityMode": gravityMode,
            "zoomScale": zoomScale,
            "offsetX": offsetX,
            "offsetY": offsetY,
            "contrast": contrast,
            "saturation": saturation
        ]
        writePrefs()
        notifyExtension()
    }

    private func writePrefs() {
        let manager = FileManager.default
        try? manager.createDirectory(at: containerDocsURL, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: lastPrefsDict, options: [.prettyPrinted]) {
            try? data.write(to: containerDocsURL.appendingPathComponent("kmo-prefs.json"), options: .atomic)
        }
    }

    func notifyExtension() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            .init("com.kmo.KMO_LiveWallpaper.wallpaper.preferences-changed" as CFString),
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            center,
            .init("com.kmo.KMO_LiveWallpaper.wallpaper.library-changed" as CFString),
            nil,
            nil,
            true
        )
    }

    func setLockScreen(enabled: Bool, videoURL: URL?) {
        lockScreenEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: savedLockScreenKey)
        applyChanges(videoURL: videoURL)
    }

    func setScreenSaver(enabled: Bool, videoURL: URL?) {
        screenSaverEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: savedScreenSaverKey)
        applyChanges(videoURL: videoURL)
    }

    func updateActiveVideo(url: URL) {
        if lockScreenEnabled || screenSaverEnabled {
            applyChanges(videoURL: url)
        }
    }

    func applyChanges(videoURL: URL?) {
        ensureBackupsExist()
        registerExtension()

        var staged: URL?
        if (lockScreenEnabled || screenSaverEnabled), let videoURL = videoURL {
            staged = stageVideo(url: videoURL)
        }

        for _ in 1...3 {
            if lockScreenEnabled, let staged = staged {
                applyChoiceToStores(surface: .desktop, stagedVideoURL: staged)
            } else if !lockScreenEnabled {
                restoreSurfaceInStores(surface: .desktop)
            }

            if screenSaverEnabled, let staged = staged {
                applyChoiceToStores(surface: .screenSaver, stagedVideoURL: staged)
            } else if !screenSaverEnabled {
                restoreSurfaceInStores(surface: .screenSaver)
            }

            notifyExtension()
            restartWallpaperAgent()

            Thread.sleep(forTimeInterval: 0.8)
            if verifyStoresHoldConfig() {
                break
            }
        }
    }

    private func verifyStoresHoldConfig() -> Bool {
        let role = lockScreenEnabled ? "Desktop" : (screenSaverEnabled ? "Idle" : nil)
        guard let role = role else { return true }
        for url in storeURLs where FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let store = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            var holds = false
            AppleWallpaperStore.forEachNode(in: store) { _, node in
                if let surface = node[role] as? [String: Any],
                   let content = surface["Content"] as? [String: Any],
                   let choices = content["Choices"] as? [[String: Any]],
                   choices.contains(where: { ($0["Provider"] as? String) == extensionBundleID }) {
                    holds = true
                }
            }
            if !holds { return false }
        }
        return true
    }

    private func defaultSurface() -> [String: Any] {
        [
            "Content": [
                "Choices": [[
                    "Provider": "default",
                    "Files": [] as [[String: Any]],
                    "Configuration": Data(),
                ]],
                "Shuffle": "$null",
            ],
            "LastSet": Date(),
            "LastUse": Date(),
        ]
    }

    private func firstNonKMOSurface(named name: String, in store: Any) -> [String: Any]? {
        guard let dict = store as? [String: Any] else { return nil }
        var found: [String: Any]?
        AppleWallpaperStore.forEachNode(in: dict) { _, node in
            if found == nil,
               let surface = node[name] as? [String: Any],
               let content = surface["Content"] as? [String: Any],
               let choices = content["Choices"] as? [[String: Any]],
               let provider = choices.first?["Provider"] as? String,
               provider != extensionBundleID {
                found = surface
            }
        }
        return found
    }

    private func applyChoiceToStores(surface: AppleWallpaperStore.Surface, stagedVideoURL: URL) {
        let choice: [String: Any] = [
            "Provider": extensionBundleID,
            "Files": [["relative": stagedVideoURL.absoluteString]],
            "Configuration": Data("kmo-active-wallpaper".utf8)
        ]

        let manager = FileManager.default
        for url in storeURLs where manager.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let loaded = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else { continue }

            var store: Any = loaded
            AppleWallpaperStore.unlinkNodes(in: &store)
            AppleWallpaperStore.applyChoiceCreatingNode(
                choice,
                to: &store,
                targetKey: "all",
                surface: surface,
                desktopFallback: firstNonKMOSurface(named: "Desktop", in: store) ?? defaultSurface(),
                idleFallback: firstNonKMOSurface(named: "Idle", in: store) ?? defaultSurface()
            )

            if let outData = try? PropertyListSerialization.data(fromPropertyList: store, format: .xml, options: 0) {
                try? outData.write(to: url, options: .atomic)
                Thread.sleep(forTimeInterval: 0.2)
                try? outData.write(to: url, options: .atomic)
            }
        }
    }

    private func restoreSurfaceInStores(surface: AppleWallpaperStore.Surface) {
        let manager = FileManager.default
        let roleKey = (surface == .screenSaver) ? "Idle" : "Desktop"

        for url in storeURLs where manager.fileExists(atPath: url.path) {
            let bakURL = backupDirURL.appendingPathComponent("\(url.lastPathComponent).bak")
            guard let currentData = try? Data(contentsOf: url),
                  var current = try? PropertyListSerialization.propertyList(from: currentData, format: nil) as? [String: Any]
            else { continue }

            let bakStore = (try? Data(contentsOf: bakURL)).flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            }

            // Restore roleKey from backup if present
            if let bakStore = bakStore {
                if var sysDef = current["SystemDefault"] as? [String: Any],
                   let bakSysDef = bakStore["SystemDefault"] as? [String: Any],
                   let bakSurface = bakSysDef[roleKey] as? [String: Any] {
                    sysDef[roleKey] = bakSurface
                    current["SystemDefault"] = sysDef
                }
                if var allSpaces = current["AllSpacesAndDisplays"] as? [String: Any],
                   let bakAll = bakStore["AllSpacesAndDisplays"] as? [String: Any],
                   let bakSurface = bakAll[roleKey] as? [String: Any] {
                    allSpaces[roleKey] = bakSurface
                    current["AllSpacesAndDisplays"] = allSpaces
                }
            }

            if let outData = try? PropertyListSerialization.data(fromPropertyList: current, format: .xml, options: 0) {
                try? outData.write(to: url, options: .atomic)
            }
        }
    }

    func restartWallpaperAgent() {
        _ = run("/usr/bin/killall", ["WallpaperAgent"])
    }

    @discardableResult
    private func run(_ exec: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
