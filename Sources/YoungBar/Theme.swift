import AppKit

/// User-selectable appearance, persisted in `barOptions`.
enum AppearanceMode: Int, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return L10n.t("跟随系统", "System")
        case .light: return L10n.t("浅色", "Light")
        case .dark: return L10n.t("深色", "Dark")
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
    case blue, pink, yellow, clear

    var title: String {
        switch self {
        case .blue: return L10n.t("怎怎瓦岗蓝", "Hachiware Blue")
        case .pink: return L10n.t("羊霸霸粉", "Chiikawa Pink")
        case .yellow: return L10n.t("乌拉黄", "Usagi Yellow")
        case .clear: return L10n.t("透明", "Clear")
        }
    }

    var accent: NSColor {
        switch self {
        case .blue: return NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.60, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 0.90, green: 0.72, blue: 0.36, alpha: 1)
        case .clear: return NSColor(calibratedWhite: 0.55, alpha: 1)
        }
    }

    var strip: NSColor {
        switch self {
        case .blue: return .clear
        case .pink: return NSColor(calibratedRed: 0.29, green: 0.12, blue: 0.17, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 0.33, green: 0.23, blue: 0.06, alpha: 1)
        case .clear: return .clear
        }
    }

    var isLightStrip: Bool { false }
    var isTransparent: Bool { self == .clear || self == .blue }

    /// Tint applied when the strip is rendered as glass.
    var glassTint: NSColor {
        switch self {
        case .blue: return NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.95, alpha: 0.55)
        case .clear: return .clear
        default: return accent.withAlphaComponent(0.18)
        }
    }

    var iconResource: String? {
        switch self {
        case .blue: return "Theme-blue"
        case .pink: return "Theme-pink"
        case .yellow: return "Theme-yellow"
        case .clear: return "Theme-clear"
        }
    }
}

/// How far the theme reaches.
enum ThemeScope: Int, CaseIterable {
    case both, interfaceOnly, stripOnly

    var title: String {
        switch self {
        case .both: return L10n.t("界面 + 收纳条", "Both")
        case .interfaceOnly: return L10n.t("仅界面", "Interface only")
        case .stripOnly: return L10n.t("仅收纳条", "Strip only")
        }
    }
}

enum StripStyle: Int, CaseIterable {
    case solid, translucent, vibrant

    var title: String {
        switch self {
        case .solid: return L10n.t("纯色", "Solid")
        case .translucent: return L10n.t("半透明", "Translucent")
        case .vibrant: return L10n.t("毛玻璃", "Glass")
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
    var isDark: Bool = true { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if color.isTransparent {
            NSColor(white: isDark ? 0.24 : 0.86, alpha: isDark ? 0.55 : 0.72).setFill()
            path.fill()
            if color == .blue {
                color.glassTint.setFill(); path.fill()
            }
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

        let symbolColor: NSColor = (color == .clear && !isDark) || color.isLightStrip ? .black : .white
        symbolColor.withAlphaComponent(0.9).setFill()
        for index in 0..<3 {
            let x = 14 + CGFloat(index) * 34
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - 7, width: 14, height: 14)).fill()
        }

        NSColor.white.withAlphaComponent(0.18).setFill()
        NSRect(x: rect.maxX - 42, y: 9, width: 1, height: rect.height - 18).fill()

        symbolColor.withAlphaComponent(0.85).setStroke()
        let gear = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 30, y: rect.midY - 7, width: 14, height: 14))
        gear.lineWidth = 1.5
        gear.stroke()
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 25, y: rect.midY - 2, width: 4, height: 4)).fill()
    }
}


/// A miniature strip used as a theme swatch: background + three symbols.
final class ThemeSwatchButton: NSButton {
    var theme: ThemeColor = .blue { didSet { needsDisplay = true } }
    var selected: Bool = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        if theme.isTransparent {
            NSColor(white: 0.26, alpha: 0.62).setFill()
            path.fill()
            if theme == .clear {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                let cell = rect.width / 4
                for row in 0..<2 {
                    for column in 0..<4 {
                        let light = (row + column) % 2 == 0
                        (light ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.18)).setFill()
                        NSRect(x: rect.minX + CGFloat(column) * cell, y: rect.minY + CGFloat(row) * cell,
                               width: cell, height: cell).fill()
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                theme.glassTint.setFill()
                path.fill()
            }
            NSColor.white.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            theme.strip.setFill()
            path.fill()
        }

        (theme.isLightStrip ? NSColor.black : NSColor.white).withAlphaComponent(0.9).setFill()
        for index in 0..<3 {
            let dot = NSRect(x: rect.minX + 8 + CGFloat(index) * 12, y: rect.midY - 3, width: 6, height: 6)
            NSBezierPath(ovalIn: dot).fill()
        }

        if selected {
            NSColor.labelColor.setStroke()
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
