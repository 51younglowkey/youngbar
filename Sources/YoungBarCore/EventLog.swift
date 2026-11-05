// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The flight recorder's memory: the last few hundred things that happened,
/// one line each. A report like "the ••• jumps around" happens over time, on a
/// Mac nobody here can touch; a snapshot taken afterwards shows the ••• already
/// back in place.
public struct EventLog: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        /// Empty for a line restored from the file, which already has its time.
        var stamp: String
        var text: String
        var count = 1
        var mergeKey: String?

        var line: String {
            let body = count > 1 ? "\(text) ×\(count)" : text
            return stamp.isEmpty ? body : "\(stamp) \(body)"
        }
    }

    public static let maxLineLength = 700

    public let capacity: Int
    private(set) var entries: [Entry] = []

    /// `saved` is an earlier `fileText`: the lines of the previous run, so a
    /// crash doesn't take the events leading up to it along.
    public init(capacity: Int = 500, restoring saved: String = "") {
        self.capacity = max(capacity, 1)
        let lines = saved.split(whereSeparator: \.isNewline).suffix(self.capacity)
        entries = lines.map { Entry(stamp: "", text: String($0)) }
    }

    /// Adds a line. Lines with the same `mergeKey` in a row, or the same text
    /// without a key, become one with a count and the latest time: an icon
    /// that keeps changing width mustn't push everything else out.
    public mutating func append(_ text: String, stamp: String, mergeKey: String? = nil) {
        let oneLine = String(text.map { $0.isNewline ? " " : $0 }.prefix(Self.maxLineLength))
        if let last = entries.last,
           mergeKey != nil ? last.mergeKey == mergeKey : (last.mergeKey == nil && last.text == oneLine && !last.stamp.isEmpty) {
            entries[entries.count - 1].text = oneLine
            entries[entries.count - 1].stamp = stamp
            entries[entries.count - 1].count += 1
            return
        }
        entries.append(Entry(stamp: stamp, text: oneLine, mergeKey: mergeKey))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public var lines: [String] { entries.map(\.line) }

    /// The newest `limit` lines, oldest first.
    public func recent(_ limit: Int) -> [String] {
        entries.suffix(max(limit, 0)).map(\.line)
    }

    public var fileText: String {
        entries.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}

/// How far the ••• went. An icon coming or going shifts it by an icon's width
/// or so, which is normal; further than that, or off the bar's line, is worth
/// a line of its own and counts as a jump.
public enum ControlMove {
    public static let jumpX: Double = 60
    public static let jumpY: Double = 6

    public static func isJump(from: CGPoint, to: CGPoint) -> Bool {
        abs(Double(to.x - from.x)) >= jumpX || abs(Double(to.y - from.y)) >= jumpY
    }
}

/// What can be checked about the ••• on any Mac without touching anything: the
/// user's report then says by itself whether it is where it should be.
public struct ControlCheck: Equatable, Sendable {
    public let onScreen: Bool
    public let inBar: Bool
    /// From the •••'s right edge to the first icon; nil with no icon to go by,
    /// or when the bar is full and the ••• sits in the « pile instead.
    public let gapToIcon: Double?

    /// The ••• keeps 6 pt from the icon. Up to 20 allows for an icon that went
    /// away since the last walk; overlapping it by more than a point doesn't pass.
    public var besideIcons: Bool? {
        gapToIcon.map { $0 >= -1 && $0 <= 20 }
    }

    public var allPassed: Bool {
        onScreen && inBar && besideIcons != false
    }

    public static func evaluate(control: CGRect, screens: [CGRect], barMinY: Double, barMaxY: Double,
                                leadingIconX: Double?) -> ControlCheck {
        let midY = Double(control.midY)
        return ControlCheck(onScreen: screens.contains { $0.intersects(control) },
                            inBar: midY >= barMinY && midY <= barMaxY,
                            gapToIcon: leadingIconX.map { $0 - Double(control.maxX) })
    }
}
