import AppKit
import ScreenCaptureKit
import PelmetEngine

@MainActor
final class StatusPictures {
    struct Picture {
        let image: NSImage
        let takenAt: Date
    }

    private struct Stored: Codable {
        let png: Data
        let takenAt: Date
    }

    private(set) var pictures: [String: Picture] = [:]
    private(set) var error: String?
    var cacheFileExists: Bool { FileManager.default.fileExists(atPath: Self.cacheURL.path) }
    var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    private static let maxEntries = 120
    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    private static let maxBytes = 8 * 1024 * 1024

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YoungBar", isDirectory: true)
            .appendingPathComponent("pictures.json")
    }

    init() { load() }

    // Only the menu-bar band is acquired. The crops are cached on disk so a
    // click can open the strip instantly instead of revealing every item to
    // take fresh pixels (that reveal is what made the bar flash).
    func capture(_ items: [ObservedItem]) async {
        guard isAllowed, let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { return }
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let cursorPIDs = Set(windows.compactMap { window -> Int32? in
                guard let owner = window[kCGWindowOwnerName as String] as? String,
                      owner.hasSuffix("Software Cursor"),
                      let pid = window[kCGWindowOwnerPID as String] as? Int32 else { return nil }
                return pid
            })
            let own = content.applications.filter {
                $0.processID == ProcessInfo.processInfo.processIdentifier || cursorPIDs.contains($0.processID)
            }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let frames = items.compactMap(\.frame)
            guard let minX = frames.map(\.minX).min(), let maxX = frames.map(\.maxX).max(),
                  let maxY = frames.map(\.maxY).max(), maxX > minX else { return }
            let bounds = CGDisplayBounds(display.displayID)
            let band = CGRect(x: max(bounds.minX, minX), y: bounds.minY,
                              width: min(bounds.maxX, maxX) - max(bounds.minX, minX),
                              height: min(60, maxY - bounds.minY + 2))
            guard band.width > 0, band.height > 0 else { return }
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.sourceRect = band.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            config.width = Int(band.width * scale); config.height = Int(band.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let shot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let sx = CGFloat(shot.width) / band.width, sy = CGFloat(shot.height) / band.height
            for item in items {
                guard let frame = item.frame else { continue }
                let rect = CGRect(x: (frame.minX - band.minX) * sx, y: (frame.minY - band.minY) * sy,
                                  width: frame.width * sx, height: frame.height * sy).integral
                guard let crop = shot.cropping(to: rect) else { continue }
                pictures[item.id.sectionKey.rawValue] = Picture(
                    image: NSImage(cgImage: Self.transparentBackground(crop), size: frame.size), takenAt: Date())
            }
            error = nil
            persist()
        } catch { self.error = error.localizedDescription }
    }

    /// Removes the on-disk crops and the in-memory copies. The next capture
    /// rebuilds them; until then the strip falls back to app icons.
    func clearCache() {
        pictures.removeAll()
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let stored = try? JSONDecoder().decode([String: Stored].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        let fresh = stored
            .filter { $0.value.takenAt >= cutoff }
            .sorted { $0.value.takenAt > $1.value.takenAt }
            .prefix(Self.maxEntries)
        for (key, value) in fresh {
            if let image = NSImage(data: value.png) {
                pictures[key] = Picture(image: image, takenAt: value.takenAt)
            }
        }
        if pictures.count != stored.count { persist() }
    }

    private func persist() {
        let ordered = pictures.sorted { $0.value.takenAt > $1.value.takenAt }
            .prefix(Self.maxEntries)
        var stored: [String: Stored] = [:]
        for (key, picture) in ordered {
            guard let png = Self.png(picture.image) else { continue }
            stored[key] = Stored(png: png, takenAt: picture.takenAt)
        }
        guard var data = try? JSONEncoder().encode(stored) else { return }
        // Keep the newest crops until the encoded cache fits the byte budget.
        var keys = stored.keys.sorted {
            (stored[$0]?.takenAt ?? .distantPast) > (stored[$1]?.takenAt ?? .distantPast)
        }
        while data.count > Self.maxBytes, !keys.isEmpty {
            stored.removeValue(forKey: keys.removeFirst())
            guard let trimmed = try? JSONEncoder().encode(stored) else { break }
            data = trimmed
        }
        do {
            try FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            NSLog("YoungBar picture cache write failed: \(error)")
        }
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Menu-bar crops arrive with the bar's own background baked in. Turn
    /// that background into alpha so the strip's colour/material shows through.
    /// Corners estimate the background luminance; dark bars keep their light
    /// glyphs, light bars are inverted to light glyphs for our dark strip.
    private static func transparentBackground(_ image: CGImage) -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let width = image.width, height = image.height
        let pixels = bytes.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func luminance(_ offset: Int) -> Int {
            (299 * Int(pixels[offset]) + 587 * Int(pixels[offset + 1]) + 114 * Int(pixels[offset + 2])) / 1000
        }
        let corners = [0, (width - 1) * 4, (height - 1) * width * 4, ((height - 1) * width + width - 1) * 4]
        let background = corners.map(luminance).reduce(0, +) / max(1, corners.count)
        let range = max(1, background < 128 ? 255 - background : background)
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let lum = luminance(offset)
            let alpha = min(255, max(0, abs(lum - background) * 255 / range))
            var red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            if background >= 128 {
                red = 255 - red; green = 255 - green; blue = 255 - blue
            }
            pixels[offset] = UInt8(red * alpha / 255)
            pixels[offset + 1] = UInt8(green * alpha / 255)
            pixels[offset + 2] = UInt8(blue * alpha / 255)
            pixels[offset + 3] = UInt8(alpha)
        }
        return context.makeImage() ?? image
    }
}
