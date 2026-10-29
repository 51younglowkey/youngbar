// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// Items the user set to Show that nobody can see. When the bar is full,
/// macOS 27 puts a « at its left end and moves the items that don't fit
/// into the «'s menu; on a notched display anything left of the notch is
/// out of sight as well.
public enum Overflow {
    /// Keys whose frames overlap another frame by more than a few points.
    /// Items held by the « all report frames piled on its slot (one shared
    /// minX, or staggered 5–6pt apart); real neighbours overlap by at most
    /// ~2pt of AX padding. Same rule as Pelmet's
    /// `PlacementGeometry.overflowTrapped`.
    public static func trapped(_ frames: [String: CGRect]) -> Set<String> {
        let tolerance: CGFloat = 4
        let list = Array(frames)
        var result = Set<String>()
        for (i, a) in list.enumerated() {
            for (j, b) in list.enumerated() where j != i
                && min(a.value.maxX, b.value.maxX) - max(a.value.minX, b.value.minX) > tolerance {
                result.insert(a.key)
                break
            }
        }
        return result
    }

    /// - Parameters:
    ///   - frames: every item on this bar (CG global coordinates), nil when
    ///     the walk lists an item macOS draws nowhere.
    ///   - visibleMinX: the left edge of the bar right of the notch, or nil
    ///     when the display has no notch.
    /// - Returns: the keys that are out of sight; callers keep the ones
    ///   they care about.
    public static func keys(frames: [String: CGRect?], visibleMinX: CGFloat?) -> Set<String> {
        var result = Set(frames.filter { $0.value == nil }.keys)
        let drawn = frames.compactMapValues { $0 }
        result.formUnion(trapped(drawn))
        if let visibleMinX {
            // Partly under the notch is enough: part of its click target is gone.
            result.formUnion(drawn.filter { $0.value.minX < visibleMinX - 0.5 }.keys)
        }
        return result
    }
}
