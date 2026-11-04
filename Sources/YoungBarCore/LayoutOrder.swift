// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation // CGFloat / CGRect on Linux, where only the core is built and tested
#endif

/// The saved left-to-right order of menu-bar items, as section keys.
public enum LayoutOrder {
    /// `keys` without repeats, first occurrence wins.
    public static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// Where a newly seen item belongs: before the first saved item that
    /// sits to its right on the bar, or at the end.
    public static func insertionIndex(forMinX minX: CGFloat, in order: [String],
                                      minX known: [String: CGFloat]) -> Int {
        order.firstIndex { (known[$0] ?? -.greatestFiniteMagnitude) > minX } ?? order.endIndex
    }

    /// Rewrites only the slots of the items that are on the bar so they
    /// follow `actual` (left to right). Others keep their places. Returns
    /// nil when nothing changes.
    public static func reconciled(_ saved: [String], actual: [String]) -> [String]? {
        let present = actual.filter(saved.contains)
        guard present.count > 1 else { return nil }
        let presentSet = Set(present)
        guard saved.filter(presentSet.contains) != present else { return nil }
        var iterator = present.makeIterator()
        return saved.map { presentSet.contains($0) ? (iterator.next() ?? $0) : $0 }
    }

    /// Whether `key` sits right before `neighbour` in `order`, or right after
    /// it when `after`. A drag that macOS refused leaves the item where it
    /// was, which for a move to the right is still somewhere left of the
    /// target — so "left of it" alone can't tell success from failure.
    public static func isAdjacent(_ key: String, to neighbour: String, after: Bool, in order: [String]) -> Bool {
        guard let a = order.firstIndex(of: key), let b = order.firstIndex(of: neighbour) else { return false }
        return after ? a == b + 1 : a + 1 == b
    }

    /// Whether the dragged icon `moved` now sits right next to `target`, on
    /// the side asked for (right of it when `after`), with no other drawn
    /// icon in between. Judged by frames: an app with several icons has one
    /// key for all of them, so its order position says nothing about which
    /// icon moved.
    public static func landedBeside(_ moved: CGRect, target: CGRect, after: Bool, others: [CGRect]) -> Bool {
        if after {
            guard moved.midX > target.midX else { return false }
            return !others.contains { $0.midX > target.midX && $0.midX < moved.midX }
        }
        guard moved.midX < target.midX else { return false }
        return !others.contains { $0.midX > moved.midX && $0.midX < target.midX }
    }

    /// `key` moved to just before `before`; an empty or unknown `before`
    /// moves it to the end.
    public static func moving(_ key: String, before: String, in order: [String]) -> [String] {
        var result = order.filter { $0 != key }
        let index = result.firstIndex(of: before) ?? result.endIndex
        result.insert(key, at: index)
        return result
    }
}
