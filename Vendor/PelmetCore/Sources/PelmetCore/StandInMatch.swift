// StandInMatch.swift
// MenuBarAgent draws real buttons only on the active display's bar (the one
// the frontmost app is on). Every other bar shows a stand-in group per icon,
// and each group nests the owning app's whole extras bar, so a group's own
// subtree cannot say which of the app's icons it is. Its place can: an app's
// groups on one bar, left to right, are its icons in the order the extras
// bar's items sit on the active bar. Named by the first title instead, every
// Pelmet stand-in on the main bar read as the chevron, the walk kept one,
// and Shortcuts, Media and Camera & mic were "not moved" for good (live
// test, 2026-10-13). Pure: the enumerator reads the frames.

import CoreGraphics

public enum StandInMatch {
    /// How far an app's group-minus-item width gaps may spread and still
    /// read as one padding: a group is wider than its item by the same
    /// amount for every icon of an app (Pelmet 38 vs 24, live probe
    /// 2026-10-13), so a gap that differs is a pairing gone wrong.
    public static let widthGapTolerance: CGFloat = 3

    /// Which of the app's items each stand-in group is: for each entry of
    /// `groups` (the frames of one app's groups on one bar), the index into
    /// `items` (the frames of the items on the app's extras bar, nil
    /// without a frame), or nil where position cannot tell. Counts that
    /// differ, an item with no frame, or width gaps that disagree leave
    /// every group unnamed; groups or items that share an x leave only
    /// those unnamed. A wrong name is worse than none: the walk prefers the
    /// main display's copy, so it would win over the real button.
    public static func items(forGroups groups: [CGRect], items: [CGRect?]) -> [Int?] {
        var result = [Int?](repeating: nil, count: groups.count)
        let itemFrames = items.compactMap { $0 }
        guard groups.count == items.count, itemFrames.count == items.count else { return result }
        let groupXs = groups.map(\.minX), itemXs = itemFrames.map(\.minX)
        let groupOrder = groups.indices.sorted { groupXs[$0] < groupXs[$1] }
        let itemOrder = itemFrames.indices.sorted { itemXs[$0] < itemXs[$1] }
        for rank in groupOrder.indices {
            let group = groupOrder[rank], item = itemOrder[rank]
            guard !sharesX(groupXs, at: group), !sharesX(itemXs, at: item) else { continue }
            result[group] = item
        }
        let gaps = zip(groups, result).compactMap { group, item in item.map { group.width - itemFrames[$0].width } }
        guard let low = gaps.min(), let high = gaps.max(), high - low <= widthGapTolerance else {
            return [Int?](repeating: nil, count: groups.count)
        }
        return result
    }

    /// Half a point apart or less: one spot, as far as order goes.
    private static func sharesX(_ xs: [CGFloat], at index: Int) -> Bool {
        xs.indices.contains { $0 != index && abs(xs[$0] - xs[index]) <= 0.5 }
    }
}
