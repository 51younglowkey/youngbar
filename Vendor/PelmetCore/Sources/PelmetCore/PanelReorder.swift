// PanelReorder.swift
// Where in a section a dragged tile would sit, and what that does to the order
// (docs/PANEL-PLAN.md §9 D1: reorder in the panel is in, Gab 2026-10-12). Pure,
// so the panel's live "make space" and the drop it ends in read the same
// rules: the tile under the pointer is the one the dragged tile takes the place
// of, and the tiles in between give way (the iOS home screen's rule, which
// settles after one move: the pointer ends up over the dragged tile itself).

import CoreGraphics
import Foundation

/// A place among a section's icons.
public struct PanelSlot: Equatable, Sendable {
    public var kind: PanelSection.Kind
    /// Before the tile at this index of the section's icons and breaks, less
    /// the dragged tile; the count is after the last one. Launchers and the
    /// fold keep their places after the icons.
    public var index: Int

    public init(kind: PanelSection.Kind, index: Int) {
        self.kind = kind
        self.index = index
    }
}

/// What stands right of a tile that moved.
public struct PanelNeighbour: Equatable, Sendable {
    /// The next icon to its right; nil when it is the last.
    public var item: ItemID?
    /// A break (a separator that starts a new row) stands between them.
    public var afterBreak: Bool

    public init(item: ItemID?, afterBreak: Bool) {
        self.item = item
        self.afterBreak = afterBreak
    }
}

public enum PanelReorder {
    /// A tile the bar has an icon (or a separator) for: the ones that reorder.
    /// Launchers and the fold sit after them.
    private static func isPlaced(_ tile: PanelTile) -> Bool {
        switch tile {
        case .item, .rowBreak: true
        case .launcher, .fold: false
        }
    }

    /// `tiles` with `tile` taken out and put at `index` among the icons and
    /// breaks (clamped); launchers and the fold stay after them.
    public static func placing(_ tile: PanelTile, in tiles: [PanelTile], at index: Int) -> [PanelTile] {
        var head = tiles.filter { $0 != tile && isPlaced($0) }
        let tail = tiles.filter { $0 != tile && !isPlaced($0) }
        head.insert(tile, at: min(max(index, 0), head.count))
        return head + tail
    }

    /// The slot index for a pointer at `point`, given the section's `tiles`
    /// as drawn now (the dragged tile among them when it is the section's own)
    /// and their `frames` in the pointer's space. Nil when there is no icon to
    /// aim at.
    ///
    /// The nearest icon is the one aimed at, a row of its own outweighing a
    /// nearer tile in another row. The dragged tile takes its place; past the
    /// last icon of a row, in the room after it, it goes after that icon.
    public static func index(
        at point: CGPoint, tiles: [PanelTile], frames: [PanelTile: CGRect], dragged: PanelTile
    ) -> Int? {
        let head = tiles.filter(isPlaced)
        let aimed: [(index: Int, frame: CGRect)] = head.enumerated().compactMap { index, tile in
            guard case .item = tile, let frame = frames[tile] else { return nil }
            return (index, frame)
        }
        guard let nearest = aimed.min(by: { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) })
        else { return nil }

        let own = head.firstIndex(of: dragged)
        let most = head.count - (own == nil ? 0 : 1)
        // Over its own place, or in the room after it: nothing moves.
        if nearest.index == own { return min(nearest.index, most) }

        // Right of an icon with nothing after it in its row, or a break: the
        // room after it is the end of its group (the row layout's divider
        // shares its line with the next group's first icon).
        let frame = nearest.frame
        let next = head.dropFirst(nearest.index + 1).first
        let lastInRow = point.x > frame.maxX && (next == nil || next == .rowBreak || !aimed.contains {
            $0.frame.minX > frame.maxX && abs($0.frame.midY - frame.midY) < frame.height / 2
        })
        // Less the dragged tile, an icon after it has one index less.
        let there = own.map { $0 < nearest.index ? nearest.index - 1 : nearest.index } ?? nearest.index
        return min(lastInRow ? there + 1 : nearest.index, most)
    }

    /// What `tile` stands next to on its right in `tiles`. No icon after it
    /// but a break: it ends its run, before the separators closing the section.
    public static func neighbour(of tile: PanelTile, in tiles: [PanelTile]) -> PanelNeighbour {
        let head = tiles.filter(isPlaced)
        guard let at = head.firstIndex(of: tile) else { return PanelNeighbour(item: nil, afterBreak: false) }
        var broke = false
        for next in head[(at + 1)...] {
            switch next {
            case .rowBreak: broke = true
            case .item(let key): return PanelNeighbour(item: key, afterBreak: broke)
            case .launcher, .fold: break
            }
        }
        return PanelNeighbour(item: nil, afterBreak: broke)
    }

    /// The distance the nearest-icon rule compares: a tile in another row
    /// costs more than one further along the same row.
    private static func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + 4 * dy * dy
    }
}

extension PanelModel {
    /// The model as it would stand with `tile` dropped on `slot`.
    ///
    /// - Parameter keepingOrigin: the tile stays in the section it came from
    ///   as well, so that section does not reflow under the pointer (the
    ///   panel layout, where each section is a grid of its own). The row is
    ///   one grid, where the tile is only moved.
    public func moving(_ tile: PanelTile, to slot: PanelSlot, keepingOrigin: Bool = false) -> PanelModel {
        guard let target = sections.firstIndex(where: { $0.kind == slot.kind }) else { return self }
        var out = self
        if !keepingOrigin {
            for index in out.sections.indices where index != target {
                out.sections[index].tiles.removeAll { $0 == tile }
            }
        }
        out.sections[target].tiles = PanelReorder.placing(tile, in: out.sections[target].tiles, at: slot.index)
        return out
    }

    /// Dropping `tile` on `slot` would change something: another section, or
    /// another place in its own.
    public func changes(_ tile: PanelTile, at slot: PanelSlot) -> Bool {
        guard let target = section(slot.kind) else { return false }
        guard target.tiles.contains(tile) else { return true }
        return PanelReorder.placing(tile, in: target.tiles, at: slot.index) != target.tiles
    }
}
