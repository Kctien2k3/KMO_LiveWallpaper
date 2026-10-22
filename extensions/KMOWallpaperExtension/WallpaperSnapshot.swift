import CoreGraphics
import Foundation
import IOSurface
import ObjectiveC

/// Answers macOS when it asks what this wallpaper looks like as a picture.
///
/// **What this fixes.** After a restart the lock screen showed the desktop
/// wallpaper instead of the lock one, and this is the half of that which
/// happens before any of Muro's code is running at all. macOS exports a still
/// of the current wallpaper to the Preboot volume, and that exported picture
/// is what the login screen draws while the Mac is still asking for a
/// password. To make it, `WallpaperAgent` asks the provider for a snapshot.
/// This extension used to answer with nothing, so the export failed:
///
///     export-controller: Exporting wallpaper '<... provider=
///       com.kmo.KMO_LiveWallpaper.wallpaper-extension>' - snapshotting
///     extension-proxy: ERROR - snapshot: WallpaperExtensionError (2)
///     export-controller: ERROR - due to 'Failed to create snapshot to export'
///
/// and the login screen went on showing whatever had been exported last, which
/// was a desktop picture Muro had set months of wallpapers ago. macOS also
/// retries the export immediately, dozens of times, so refusing was not free.
///
/// **The shape.** `WallpaperSnapshotXPC` is one Objective-C object holding one
/// Swift value, and `WallpaperSnapshot` is one `IOSurfaceRef`. Both are read
/// out of the runtime rather than assumed: the instance size and the ivar
/// offset are checked, and anything unexpected declines exactly as before
/// rather than writing into a stranger's memory. Same technique, and the same
/// care, as `createRemoteContextXPC`.
enum WallpaperSnapshot {
    /// A snapshot object for `choiceID` at `size` in pixels, or nil when there
    /// is no frame to send or the runtime is not the shape this expects.
    static func make(choiceID: String?, size: CGSize) -> AnyObject? {
        guard let image = WallpaperFrame.image(for: choiceID) else {
            extensionLog("snapshot: no frame for \(choiceID ?? "none")")
            return nil
        }
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let surface = drawSurface(image: image, width: width, height: height) else {
            extensionLog("snapshot: could not draw \(width)x\(height)")
            return nil
        }
        return box(surface)
    }

    private static func drawSurface(image: CGImage, width: Int, height: Int) -> IOSurface? {
        let bytesPerElement = 4
        let bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * bytesPerElement)
        let properties: [IOSurfacePropertyKey: any Sendable] = [
            .width: width,
            .height: height,
            .bytesPerElement: bytesPerElement,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: 0x4247_5241, // 'BGRA'
            .allocSize: IOSurfaceAlignProperty(kIOSurfaceAllocSize, bytesPerRow * height),
        ]
        guard let surface = IOSurface(properties: properties) else { return nil }
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        guard let context = CGContext(
            data: surface.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: surface.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Framed and zoomed to match what the wallpaper layers do
        let prefs = ExtensionPreferences.shared
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let baseScale: CGFloat
        switch prefs.gravityMode {
        case 1:
            baseScale = min(CGFloat(width) / imageWidth, CGFloat(height) / imageHeight)
        case 2:
            baseScale = 1.0
        default:
            baseScale = max(CGFloat(width) / imageWidth, CGFloat(height) / imageHeight)
        }
        let finalScale = (prefs.gravityMode == 2) ? 1.0 : (baseScale * prefs.zoomScale)
        let drawnWidth = (prefs.gravityMode == 2) ? CGFloat(width) : (imageWidth * finalScale)
        let drawnHeight = (prefs.gravityMode == 2) ? CGFloat(height) : (imageHeight * finalScale)
        let x = (CGFloat(width) - drawnWidth) / 2 + prefs.offsetX
        let y = (CGFloat(height) - drawnHeight) / 2 + prefs.offsetY
        context.draw(image, in: CGRect(
            x: x,
            y: y,
            width: drawnWidth,
            height: drawnHeight
        ))
        return surface
    }

    private static func box(_ surface: IOSurface) -> AnyObject? {
        guard let runtimeClass = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
              let ivar = class_getInstanceVariable(runtimeClass, "rawValue")
        else {
            extensionLog("snapshot: no WallpaperSnapshotXPC")
            return nil
        }
        let offset = ivar_getOffset(ivar)
        guard offset >= 0,
              offset + MemoryLayout<UnsafeMutableRawPointer>.size
                  <= class_getInstanceSize(runtimeClass)
        else {
            extensionLog("snapshot: unexpected WallpaperSnapshotXPC layout")
            return nil
        }
        guard let instance = class_createInstance(runtimeClass, 0) else { return nil }
        let object = instance as AnyObject
        // The ivar is a managed reference, so the surface goes in owned and
        // the object's own destructor is what releases it.
        Unmanaged.passUnretained(object).toOpaque()
            .advanced(by: offset)
            .storeBytes(
                of: Unmanaged.passRetained(surface).toOpaque(),
                as: UnsafeMutableRawPointer.self
            )
        return object
    }
}
