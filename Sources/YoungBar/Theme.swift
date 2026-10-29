// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

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

/// Accent + strip palette. The three colours share one lightness and
/// chroma in OKLCH and differ only in hue, so none of them reads brighter or
/// greyer than the others:
///   accent  L 0.70  C 0.13      strip  L 0.55  C 0.12
///   hue     blue 255°, pink 355°, yellow 75°
/// The strip tone is the darker one so white menu-bar symbols stay legible.
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
        case .blue: return NSColor(srgbRed: 0.392, green: 0.630, blue: 0.907, alpha: 1)
        case .pink: return NSColor(srgbRed: 0.865, green: 0.479, blue: 0.636, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.804, green: 0.570, blue: 0.282, alpha: 1)
        case .clear: return NSColor(calibratedWhite: 0.55, alpha: 1)
        }
    }

    var strip: NSColor {
        switch self {
        case .blue: return NSColor(srgbRed: 0.239, green: 0.450, blue: 0.692, alpha: 1)
        case .pink: return NSColor(srgbRed: 0.652, green: 0.316, blue: 0.457, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.603, green: 0.397, blue: 0.126, alpha: 1)
        case .clear: return .clear
        }
    }

    var isTransparent: Bool { self == .clear }

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
        case .both: return L10n.t("界面与收纳条", "Both")
        case .interfaceOnly: return L10n.t("仅界面", "Interface")
        case .stripOnly: return L10n.t("仅收纳条", "Strip")
        }
    }
}

/// How opaque the theme colour is over the strip's blur, in percent;
/// 100 is a solid strip. Older settings stored a three-way `stripStyle`
/// (solid / translucent / glass), which maps onto the same scale.
let stripOpacityRange = 30...100

func stripOpacityPercent(_ options: [String: Int]) -> Int {
    if let percent = options[.stripOpacity] {
        return min(max(percent, stripOpacityRange.lowerBound), stripOpacityRange.upperBound)
    }
    return [100, 72, 55][min(max(options[.stripStyle] ?? 0, 0), 2)]
}

/// Recolours a symbol image (drawn white) for the strip preview.
func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

@MainActor private var themeIconCache: [ThemeColor: NSImage] = [:]

@MainActor
func themeIcon(_ color: ThemeColor) -> NSImage? {
    if let cached = themeIconCache[color] { return cached }
    let image = loadThemeIcon(color)
    themeIconCache[color] = image
    return image
}

@MainActor
private func loadThemeIcon(_ color: ThemeColor) -> NSImage? {
    if let name = color.iconResource,
       let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
        return NSImage(contentsOf: url)
    }
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
        return NSImage(contentsOf: url)
    }
    return NSApp.applicationIconImage
}

/// Small sample of the strip for the settings window. Draws the same layers
/// as the real strip: a blur stand-in, then the theme colour at `opacity`.
final class ThemePreviewView: NSView {
    var color: ThemeColor = .blue { didSet { needsDisplay = true } }
    var opacity: CGFloat = 1 { didSet { needsDisplay = true } }
    var isDark: Bool = true { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(white: isDark ? 0.24 : 0.86, alpha: isDark ? 0.55 : 0.72).setFill()
        path.fill()
        if !color.isTransparent {
            color.strip.withAlphaComponent(opacity).setFill()
            path.fill()
        }
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()

        let symbolColor: NSColor = color == .clear && !isDark ? .black : .white

        func drawSymbol(_ name: String, x: CGFloat, height: CGFloat = 14) -> CGFloat {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { return 0 }
            let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
            let width = height * ratio
            let tinted = tintedImage(image, color: symbolColor)
            tinted.draw(in: NSRect(x: x, y: rect.midY - height / 2, width: width, height: height),
                        from: .zero, operation: .sourceOver, fraction: 0.95,
                        respectFlipped: true, hints: nil)
            return width
        }

        var cursor: CGFloat = 14
        for name in ["wifi", "battery.75percent", "clock"] {
            cursor += drawSymbol(name, x: cursor) + 10
        }

        symbolColor.withAlphaComponent(0.18).setFill()
        NSRect(x: rect.maxX - 42, y: 9, width: 1, height: rect.height - 18).fill()
        _ = drawSymbol("gearshape", x: rect.maxX - 31, height: 15)
    }
}


enum ControlIcon {
    static let symbols = ["ellipsis", "heart.fill", "star.fill", "sparkles",
                          "circle.grid.2x2.fill"]

    static func title(_ index: Int) -> String {
        switch index {
        case 0: return L10n.t("省略号", "Ellipsis")
        case 1: return L10n.t("爱心", "Heart")
        case 2: return L10n.t("星形", "Star")
        case 3: return L10n.t("闪光", "Sparkles")
        case 4: return L10n.t("网格", "Grid")
        default: return L10n.t("自定义", "Custom")
        }
    }

    static func image(_ index: Int, custom: NSImage?) -> NSImage? {
        if index == symbols.count {
            if let custom { return custom }
            return NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        }
        guard symbols.indices.contains(index),
              let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: title(index)) else {
            return NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        }
        image.isTemplate = true
        return image
    }
}
