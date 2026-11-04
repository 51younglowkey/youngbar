// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// Which icons the strip shows, from the saved modes (0 Show, 1 Hide,
/// 2 Always Hide) and the icons the bar has no room for.
public enum ShelfContents {
    /// The strip's icons, in `order`: Hidden ones, Always Hidden ones when
    /// asked for (⌥-click on •••), and Show ones that are `covered` (in
    /// macOS's « or under the notch), which nobody could reach otherwise.
    public static func keys(order: [String], modes: [String: Int], covered: Set<String>,
                            includeAlwaysHidden: Bool) -> [String] {
        order.filter { key in
            let mode = modes[key] ?? 0
            return mode == 1 || (includeAlwaysHidden && mode == 2) || (mode == 0 && covered.contains(key))
        }
    }

    /// What an empty strip offers to tuck in: Show icons that are on the bar
    /// (not `covered`), in `order`, without the `excluded` ones (YoungBar
    /// itself, items macOS pins).
    public static func tuckInCandidates(order: [String], modes: [String: Int], covered: Set<String>,
                                        excluded: Set<String>) -> [String] {
        order.filter { (modes[$0] ?? 0) == 0 && !covered.contains($0) && !excluded.contains($0) }
    }
}
