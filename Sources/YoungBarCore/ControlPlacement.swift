// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Where the ••• goes on the bar. It floats over YoungBar's own status item,
/// which is a blank placeholder that still opens the strip when clicked.
///
/// While a hide assertion holds, macOS usually gives that item no visible
/// slot, and the ••• goes left of the first icon instead. But when macOS does
/// draw the slot and another app's icon sits left of it (an app that started
/// after YoungBar, a ⌘-drag), following the first icon split the two: the •••
/// on one side of that icon, a blank slot that opens the strip on the other
/// (user report, 0.1.7 on macOS 27.0.1). Then the ••• sits on the slot.
public enum ControlPlacement {
    /// Space kept between the ••• and the first icon.
    public static let gap: Double = 6

    /// A horizontal stretch of the bar, in global points.
    public struct Span: Equatable, Sendable {
        public var minX: Double
        public var maxX: Double
        public init(minX: Double, maxX: Double) {
            self.minX = minX
            self.maxX = maxX
        }
        public var midX: Double { (minX + maxX) / 2 }
    }

    /// YoungBar's own slot when it is part of the row of icons: another icon
    /// starts left of it and none covers it. Left of every icon, the slot is
    /// either not drawn or already where the ••• goes beside the first icon.
    public static func slotInRow(own: Span?, icons: [Span]) -> Span? {
        guard let own, own.maxX - own.minX >= 4,
              let first = icons.map(\.minX).min(), first < own.minX - 1 else { return nil }
        // A slot macOS really gave out doesn't sit under another icon; a
        // stale frame might.
        let covered = icons.contains { $0.minX < own.maxX - 2 && $0.maxX > own.minX + 2 }
        return covered ? nil : own
    }

    /// The •••'s left edge, and whether it sits on YoungBar's own slot.
    /// `floor` is the leftmost it may go (right of the notch).
    public static func x(width: Double, own: Span?, icons: [Span], floor: Double) -> (x: Double, onOwnSlot: Bool)? {
        if let slot = slotInRow(own: own, icons: icons) {
            return (max(floor, (slot.midX - width / 2).rounded()), true)
        }
        guard let first = icons.map(\.minX).min() else { return nil }
        return (max(floor, first - width - gap), false)
    }
}
