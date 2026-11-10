// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation // CGFloat / CGRect on Linux, where only the core is built and tested
#endif

/// One display's menu bar, in the global top-left space AX frames use
/// (`CGDisplayBounds`): the primary display's top-left corner is (0, 0).
public struct BarDisplay: Equatable, Sendable {
    public let frame: CGRect
    public let barHeight: CGFloat
    /// The left edge of the bar right of the notch; nil without a notch.
    public let visibleMinX: CGFloat?

    public init(frame: CGRect, barHeight: CGFloat, visibleMinX: CGFloat? = nil) {
        self.frame = frame
        self.barHeight = barHeight
        self.visibleMinX = visibleMinX
    }

    /// The vertical middle of this display's bar.
    public var barMidY: CGFloat { frame.minY + barHeight / 2 }
    /// How far left the control may go.
    public var leftLimit: CGFloat { visibleMinX ?? (frame.minX + ControlLayout.edgeInset) }
}

/// An item as one display's bar sees it. macOS draws a status item once per
/// display, so the same item has a different frame (or none) on each bar.
public struct BarIcon: Equatable, Sendable {
    public let key: String
    /// Its frame on this bar; nil when this bar doesn't draw it.
    public let frame: CGRect?
    /// Drawn on another display's bar, just not this one.
    public let drawnElsewhere: Bool
    public let isOwn: Bool

    public init(key: String, frame: CGRect?, drawnElsewhere: Bool = false, isOwn: Bool = false) {
        self.key = key
        self.frame = frame
        self.drawnElsewhere = drawnElsewhere
        self.isOwn = isOwn
    }
}

/// Where the control goes on a bar. The answer depends only on that display
/// and the icons on it, and it is always on that bar: no input can leave the
/// control lower down (a user's control sat at the bottom right of the screen).
public struct ControlSpot: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case beside(key: String, iconMinX: CGFloat)
        /// A full bar: in the free left part of macOS's « pile.
        case inPile(key: String, iconMinX: CGFloat)
        /// On YoungBar's own slot, which macOS drew right of `key`.
        case onOwnSlot(key: String, iconMinX: CGFloat)
        /// A full bar: macOS's « sits right before `key`, so left of the «.
        case leftOfChevron(key: String, iconMinX: CGFloat, chevronMinX: CGFloat)
        /// No icon on this bar to go by.
        case noIcon
    }

    public let minX: CGFloat
    public let width: CGFloat
    public let midY: CGFloat
    public let reason: Reason
    public let atLeftLimit: Bool
}

public enum ControlLayout {
    public static let gapToIcon: CGFloat = 6
    public static let narrowWidth: CGFloat = 22
    public static let edgeInset: CGFloat = 12
    /// Neighbours on a bar are a few points apart. A wider gap ends the run of
    /// icons the control sits left of. It is wider than the control itself, so
    /// a control placed in such a gap never covers an icon.
    public static let runGap: CGFloat = 60
    /// With no icon to go by, this far from the right edge of the bar.
    public static let fallbackRightInset: CGFloat = 88
    /// A frame this far above a bar still counts as on it (AX padding).
    static let barSlack: CGFloat = 5

    /// In this display's bar: on the display, level with its bar. A display
    /// above or below can share every x, so x alone can't tell.
    public static func isOnBar(_ frame: CGRect, of display: BarDisplay) -> Bool {
        let y = frame.minY - display.frame.minY
        return y > -barSlack && y < max(display.barHeight, 1)
            && frame.midX >= display.frame.minX && frame.midX < display.frame.maxX
    }

    /// The frames among `frames` that are not `first` or a repeat, more
    /// than a point apart (the walk can list one icon several times).
    public static func distinctFrames(_ frames: [CGRect], besides first: CGRect) -> [CGRect] {
        func same(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 1 && abs(a.width - b.width) <= 1 && abs(a.minY - b.minY) <= 1
        }
        var seen = [first]
        for frame in frames where !seen.contains(where: { same($0, frame) }) { seen.append(frame) }
        return Array(seen.dropFirst())
    }

    /// The control's own frame is in the bar's height range on this display.
    public static func controlIsInBar(_ control: CGRect, of display: BarDisplay) -> Bool {
        let y = control.midY - display.frame.minY
        return y >= 0 && y <= display.barHeight
            && control.midX >= display.frame.minX && control.midX < display.frame.maxX
    }

    /// Keys out of sight on this bar. When nothing at all is drawn on it (the
    /// bar is hidden: full screen, auto-hide; or the display draws none) only
    /// the items drawn nowhere count: everything else may well come back.
    public static func outOfSight(_ icons: [BarIcon], on display: BarDisplay) -> Set<String> {
        let barIsListed = icons.contains { $0.frame.map { isOnBar($0, of: display) } ?? false }
        // YoungBar has one status item, but the walk can list it twice (its
        // AX title flaps to "Item-0"), and the two entries on one spot read
        // as the « pile. Judge it once, by an entry on this bar if any.
        let own = icons.filter(\.isOwn)
        let ownKeys = Set(own.map(\.key))
        let ownJudged = (own.first { $0.frame.map { isOnBar($0, of: display) } ?? false } ?? own.first)?.key
        var frames: [String: CGRect?] = [:]
        for icon in icons {
            if icon.isOwn, icon.key != ownJudged { continue }
            let frame = icon.frame.flatMap { isOnBar($0, of: display) ? $0 : nil }
            if frame == nil, !barIsListed, icon.drawnElsewhere || icon.frame != nil { continue }
            if let frame {
                frames[icon.key] = .some(frame)
            } else if frames[icon.key] == nil {
                frames[icon.key] = .some(nil)
            }
        }
        var result = Overflow.keys(frames: frames, visibleMinX: display.visibleMinX)
        if let ownJudged, result.contains(ownJudged) { result.formUnion(ownKeys) }
        return result
    }

    /// The leftmost icon of the run that starts at the right end of the bar.
    /// A hidden item's slot can sit far left on the bar; a gap keeps it out,
    /// however many real icons the run holds on a narrow display.
    public static func leadingIcon(_ icons: [BarIcon], on display: BarDisplay,
                                   outOfSight hidden: Set<String>) -> (key: String, frame: CGRect)? {
        run(icons, on: display, outOfSight: hidden).last
    }

    /// The icons in sight from the right end of the bar up to the first wide
    /// gap, right to left. YoungBar's own item is not one of them.
    static func run(_ icons: [BarIcon], on display: BarDisplay,
                    outOfSight hidden: Set<String>) -> [(key: String, frame: CGRect)] {
        let visible = icons.compactMap { icon -> (key: String, frame: CGRect)? in
            guard !icon.isOwn, !hidden.contains(icon.key), let frame = icon.frame,
                  isOnBar(frame, of: display) else { return nil }
            return (icon.key, frame)
        }.sorted { $0.frame.minX > $1.frame.minX }
        guard let first = visible.first else { return [] }
        var result = [first]
        for next in visible.dropFirst() {
            if result[result.count - 1].frame.minX - next.frame.maxX > runGap { break }
            result.append(next)
        }
        return result
    }

    /// YoungBar's own slot when macOS drew it inside the run of icons:
    /// another icon starts left of it and none covers it. The ••• floats over
    /// that slot, a blank that opens the strip too. Following the first icon
    /// instead split the two: the ••• on one side of an icon, a blank that
    /// opens the strip on the other (user report, 0.1.7 on macOS 27.0.1).
    /// Left of every icon, the slot is where the ••• goes anyway.
    static func ownSlotInRun(_ icons: [BarIcon], on display: BarDisplay, outOfSight hidden: Set<String>,
                             run: [(key: String, frame: CGRect)]) -> CGRect? {
        guard let leading = run.last, let rightEnd = run.first?.frame.maxX else { return nil }
        let slot = icons.first { icon in
            guard icon.isOwn, !hidden.contains(icon.key), let frame = icon.frame else { return false }
            return isOnBar(frame, of: display)
        }?.frame
        guard let slot, slot.width >= 4, leading.frame.minX < slot.minX - 1, slot.maxX <= rightEnd + 1 else { return nil }
        // A slot macOS really gave out doesn't sit under another icon; a
        // stale frame might.
        let covered = run.contains { $0.frame.minX < slot.maxX - 2 && $0.frame.maxX > slot.minX + 2 }
        return covered ? nil : slot
    }

    /// - Parameters:
    ///   - current: the control's frame now, in the same global space.
    ///   - width: its width beside a free bar.
    public static func spot(icons: [BarIcon], on display: BarDisplay, current: CGRect, width: CGFloat) -> ControlSpot {
        let hidden = outOfSight(icons, on: display)
        let limit = display.leftLimit
        guard let leading = leadingIcon(icons, on: display, outOfSight: hidden) else {
            // Stay where it is along the bar if that is on this display, and
            // on the bar's line in any case.
            let onDisplay = current.midX >= display.frame.minX && current.midX < display.frame.maxX
            let x = onDisplay ? current.minX : display.frame.maxX - width - fallbackRightInset
            let clamped = min(max(x, limit), display.frame.maxX - width)
            return ControlSpot(minX: clamped, width: width, midY: display.barMidY, reason: .noIcon,
                               atLeftLimit: clamped == limit)
        }
        let midY = leading.frame.midY
        let iconX = leading.frame.minX
        // A full bar: YoungBar's own item is in macOS's « with the others, and
        // the « sits at the right of their pile. The control takes the free
        // left part of that slot, narrowed so it doesn't cover the «.
        let ownKeys = Set(icons.filter(\.isOwn).map(\.key))
        if !ownKeys.isDisjoint(with: hidden), let pile = pileMinX(icons, on: display, outOfSight: hidden, leftOf: iconX) {
            let x = max(limit, pile)
            return ControlSpot(minX: x, width: narrowWidth, midY: midY,
                               reason: .inPile(key: leading.key, iconMinX: iconX), atLeftLimit: x == limit)
        }
        // A full bar, YoungBar's own item not listed (macOS keeps it off the
        // walk while anything is hidden): the « sits at the right end of the
        // pile right before the first icon. Beside that icon the ••• covered
        // it (2026-11-10, Stats with more modules turned on). Left of the «
        // instead, narrowed if the notch leaves less room.
        if let chevron = chevronMinX(icons, on: display, outOfSight: hidden, leftOf: iconX) {
            let right = chevron - gapToIcon
            let fitted = min(width, right - limit)
            if fitted >= narrowWidth {
                let x = right - fitted
                return ControlSpot(minX: x, width: fitted, midY: midY,
                                   reason: .leftOfChevron(key: leading.key, iconMinX: iconX, chevronMinX: chevron),
                                   atLeftLimit: x == limit)
            }
        }
        if let slot = ownSlotInRun(icons, on: display, outOfSight: hidden,
                                   run: run(icons, on: display, outOfSight: hidden)) {
            let x = max(limit, (slot.midX - width / 2).rounded())
            return ControlSpot(minX: x, width: width, midY: midY,
                               reason: .onOwnSlot(key: leading.key, iconMinX: iconX), atLeftLimit: x == limit)
        }
        let x = max(limit, iconX - width - gapToIcon)
        return ControlSpot(minX: x, width: width, midY: midY,
                           reason: .beside(key: leading.key, iconMinX: iconX), atLeftLimit: x == limit)
    }

    /// Where macOS's « starts: the right end of the pile of out-of-sight
    /// items just left of `iconX`. The pile's frames all end at the «'s right
    /// edge (staggered, or on one spot); the one starting furthest right is
    /// the «'s own slot.
    static func chevronMinX(_ icons: [BarIcon], on display: BarDisplay, outOfSight hidden: Set<String>,
                            leftOf iconX: CGFloat) -> CGFloat? {
        icons.compactMap { icon -> CGRect? in
            guard hidden.contains(icon.key), let frame = icon.frame, isOnBar(frame, of: display),
                  frame.minX < iconX, iconX - frame.maxX <= runGap else { return nil }
            return frame
        }.map(\.minX).max()
    }

    /// The left end of the pile of out-of-sight items just left of `iconX`.
    static func pileMinX(_ icons: [BarIcon], on display: BarDisplay, outOfSight hidden: Set<String>,
                         leftOf iconX: CGFloat) -> CGFloat? {
        let frames = icons.compactMap { icon -> CGRect? in
            guard hidden.contains(icon.key), let frame = icon.frame, isOnBar(frame, of: display),
                  frame.minX < iconX else { return nil }
            return frame
        }.sorted { $0.minX > $1.minX }
        var edge = iconX
        var result: CGFloat?
        for frame in frames {
            if edge - frame.maxX > runGap { break }
            result = frame.minX
            edge = min(edge, frame.minX)
        }
        return result
    }

    /// Whether AXPress can open an item's menu near the strip: macOS opens it
    /// under the item's own (hidden) slot, which has to be on the strip's
    /// display and near the control. A slot parked at the far left of a bar
    /// doesn't count, wherever the control is.
    public static func slotIsNearControl(_ slot: CGPoint, control: CGRect, on display: BarDisplay) -> Bool {
        guard display.frame.contains(CGPoint(x: slot.x, y: display.frame.minY)) else { return false }
        let y = slot.y - display.frame.minY
        guard y > -barSlack, y < max(display.barHeight, 1) else { return false }
        return slot.x - display.frame.minX > parkedSlotMargin && abs(slot.x - control.midX) < nearSlotDistance
    }

    public static let parkedSlotMargin: CGFloat = 100
    static let nearSlotDistance: CGFloat = 400
}
