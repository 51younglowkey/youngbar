// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

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

    /// `key` moved to just before `before`; an empty or unknown `before`
    /// moves it to the end.
    public static func moving(_ key: String, before: String, in order: [String]) -> [String] {
        var result = order.filter { $0 != key }
        let index = result.firstIndex(of: before) ?? result.endIndex
        result.insert(key, at: index)
        return result
    }
}
