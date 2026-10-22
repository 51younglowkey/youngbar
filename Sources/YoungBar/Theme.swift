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
/// accent so white menu-bar symbols stay legible.
enum ThemeColor: Int, CaseIterable {
    case forest, sakura, amber, graphite

    var title: String {
        switch self {
        case .forest: return "墨绿"
        case .sakura: return "樱粉"
        case .amber: return "琥珀"
        case .graphite: return "石墨"
        }
    }

    var accent: NSColor {
        switch self {
        case .forest: return NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.45, alpha: 1)
        case .sakura: return NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.60, alpha: 1)
        case .amber: return NSColor(calibratedRed: 0.79, green: 0.54, blue: 0.24, alpha: 1)
        case .graphite: return NSColor(calibratedRed: 0.54, green: 0.56, blue: 0.60, alpha: 1)
        }
    }

    var strip: NSColor {
        switch self {
        case .forest: return NSColor(calibratedRed: 0.05, green: 0.23, blue: 0.19, alpha: 1)
        case .sakura: return NSColor(calibratedRed: 0.29, green: 0.12, blue: 0.17, alpha: 1)
        case .amber: return NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.07, alpha: 1)
        case .graphite: return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.16, alpha: 1)
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

/// Small sample of the strip for the settings window.
final class ThemePreviewView: NSView {
    var color: ThemeColor = .forest { didSet { needsDisplay = true } }
    var style: StripStyle = .solid { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        switch style {
        case .solid:
            color.strip.setFill(); path.fill()
        case .translucent:
            color.strip.withAlphaComponent(0.72).setFill(); path.fill()
        case .vibrant:
            NSColor(white: 0.24, alpha: 0.62).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.14).setStroke(); path.lineWidth = 1; path.stroke()
        }

        NSColor.white.withAlphaComponent(0.9).setFill()
        for index in 0..<3 {
            let x = 14 + CGFloat(index) * 34
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - 7, width: 14, height: 14)).fill()
        }

        NSColor.white.withAlphaComponent(0.18).setFill()
        NSRect(x: rect.maxX - 42, y: 9, width: 1, height: rect.height - 18).fill()

        NSColor.white.withAlphaComponent(0.85).setStroke()
        let gear = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 30, y: rect.midY - 7, width: 14, height: 14))
        gear.lineWidth = 1.5
        gear.stroke()
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 25, y: rect.midY - 2, width: 4, height: 4)).fill()
    }
}
