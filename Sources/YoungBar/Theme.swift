import AppKit

/// User-selectable appearance, persisted in `barOptions`.
enum AppearanceMode: Int, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Accent + strip palette. The strip colour is deliberately deeper than the
/// accent so menu-bar symbols stay legible; white uses dark symbols instead.
enum ThemeColor: Int, CaseIterable {
    case blue, pink, yellow, black, clear, white

    var title: String {
        switch self {
        case .blue: return "蓝"
        case .pink: return "粉"
        case .yellow: return "黄"
        case .black: return "黑"
        case .clear: return "透明"
        case .white: return "白"
        }
    }

    var accent: NSColor {
        switch self {
        case .blue: return NSColor(calibratedRed: 0.50, green: 0.72, blue: 0.85, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.60, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.36, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.56, alpha: 1)
        case .clear: return NSColor.controlAccentColor
        case .white: return NSColor(calibratedWhite: 0.78, alpha: 1)
        }
    }

    var strip: NSColor {
        switch self {
        case .blue: return NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.35, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.29, green: 0.12, blue: 0.17, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 0.33, green: 0.23, blue: 0.06, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.04, alpha: 1)
        case .clear: return .clear
        case .white: return NSColor(calibratedWhite: 0.94, alpha: 1)
        }
    }

    var isLightStrip: Bool { self == .white }
    var isTransparent: Bool { self == .clear }

    var iconResource: String? {
        switch self {
        case .blue: return "Theme-blue"
        case .pink: return "Theme-pink"
        case .yellow: return "Theme-yellow"
        case .black, .clear, .white: return nil
        }
    }
}

/// How far the theme reaches.
enum ThemeScope: Int, CaseIterable {
    case both, interfaceOnly, stripOnly

    var title: String {
        switch self {
        case .both: return "界面 + 收纳条"
        case .interfaceOnly: return "仅界面"
        case .stripOnly: return "仅收纳条"
        }
    }
}

enum StripStyle: Int, CaseIterable {
    case solid, translucent, vibrant

    var title: String {
        switch self {
        case .solid: return "纯色"
        case .translucent: return "半透明"
        case .vibrant: return "毛玻璃"
        }
    }
}

/// Tints a transparent menu-bar crop (white symbols) to black for light strips.
func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

func themeIcon(_ color: ThemeColor) -> NSImage? {
    if let name = color.iconResource,
       let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
        return NSImage(contentsOf: url)
    }
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
        return NSImage(contentsOf: url)
    }
    return NSApp.applicationIconImage
}

/// Small sample of the strip for the settings window.
final class ThemePreviewView: NSView {
    var color: ThemeColor = .blue { didSet { needsDisplay = true } }
    var style: StripStyle = .solid { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if color.isTransparent {
            NSColor(white: 0.24, alpha: 0.55).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.14).setStroke(); path.lineWidth = 1; path.stroke()
        } else {
            switch style {
            case .solid:
                color.strip.setFill(); path.fill()
            case .translucent:
                color.strip.withAlphaComponent(0.72).setFill(); path.fill()
            case .vibrant:
                color.strip.withAlphaComponent(0.55).setFill(); path.fill()
                NSColor.white.withAlphaComponent(0.14).setStroke(); path.lineWidth = 1; path.stroke()
            }
        }

        (color.isLightStrip ? NSColor.black : NSColor.white).withAlphaComponent(0.9).setFill()
        for index in 0..<3 {
            let x = 14 + CGFloat(index) * 34
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - 7, width: 14, height: 14)).fill()
        }

        NSColor.white.withAlphaComponent(0.18).setFill()
        NSRect(x: rect.maxX - 42, y: 9, width: 1, height: rect.height - 18).fill()

        (color.isLightStrip ? NSColor.black : NSColor.white).withAlphaComponent(0.85).setStroke()
        let gear = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 30, y: rect.midY - 7, width: 14, height: 14))
        gear.lineWidth = 1.5
        gear.stroke()
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 25, y: rect.midY - 2, width: 4, height: 4)).fill()
    }
}
