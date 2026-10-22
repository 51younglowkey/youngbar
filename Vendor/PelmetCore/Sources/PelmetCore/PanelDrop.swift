// PanelDrop.swift
// Where a tile dragged out of the panel would land. Reorder in the panel is in
// (Gab, 2026-10-12, reversing docs/PANEL-PLAN.md D1's "between sections
// only"): this file says which section the pointer is over and which gap of the
// bar, `PanelReorder` which place among a section's tiles. Pure geometry on
// screen points, y up (Cocoa), so the drag follows the same rules as the
// tests: the menu bar above is Visible, the panel's sections are Hidden and
// Always Hidden, the Always Hidden fold counts as Always Hidden, and Didn't
// fit takes no drop.

import CoreGraphics
import Foundation

public struct PanelDropZones: Equatable, Sendable {
    /// What the pointer would drop on.
    public enum Hit: Equatable, Sendable {
        case none
        case section(Section)
        /// The Always Hidden fold: a drop there is Always Hidden, and holding
        /// over it springs it open.
        case fold

        /// The section a drop here moves the tile to.
        public var section: Section? {
            switch self {
            case .none: nil
            case .section(let section): section
            case .fold: .alwaysHidden
            }
        }
    }

    /// The row layout's tiles, by the group they belong to.
    public struct Group: Equatable, Sendable {
        public var kind: PanelSection.Kind
        public var tiles: [CGRect]

        public init(kind: PanelSection.Kind, tiles: [CGRect]) {
            self.kind = kind
            self.tiles = tiles
        }
    }

    /// The mock's generous zone around the panel: this far past each side,
    /// and further below, where the pointer overshoots.
    public static let reach: CGFloat = 16
    public static let reachBelow: CGFloat = 28
    /// Past the fold control's own edge.
    public static let foldSlack: CGFloat = 4

    /// The menu bar's band on the panel's display.
    public var bar: CGRect
    /// The glass.
    public var panel: CGRect
    /// The Didn't fit section, header included.
    public var didntFit: CGRect?
    /// The fold control: the tile, the count chip or the handle.
    public var fold: CGRect?
    /// Always Hidden's grid, only while it is open.
    public var alwaysHidden: CGRect?
    /// The row layout: every tile's frame by group. Non-empty means the row.
    public var groups: [Group]

    public init(
        bar: CGRect, panel: CGRect, didntFit: CGRect? = nil, fold: CGRect? = nil,
        alwaysHidden: CGRect? = nil, groups: [Group] = []
    ) {
        self.bar = bar
        self.panel = panel
        self.didntFit = didntFit
        self.fold = fold
        self.alwaysHidden = alwaysHidden
        self.groups = groups
    }

    /// The glass and the zone around it.
    public var zone: CGRect {
        CGRect(
            x: panel.minX - Self.reach, y: panel.minY - Self.reachBelow,
            width: panel.width + 2 * Self.reach, height: panel.height + Self.reach + Self.reachBelow)
    }

    public func hit(at point: CGPoint) -> Hit {
        if Self.covers(bar, point) { return .section(.visible) }
        guard Self.covers(zone, point) else { return .none }
        if let fold, Self.covers(fold.insetBy(dx: -Self.foldSlack, dy: -Self.foldSlack), point) { return .fold }
        if !groups.isEmpty { return nearestGroup(to: point) }
        // Didn't fit sits at the top: the padding above it and half the gap
        // below it are its own.
        if let didntFit, point.y >= didntFit.minY - 5 { return .none }
        if let alwaysHidden, point.y <= alwaysHidden.maxY { return .section(.alwaysHidden) }
        return .section(.hidden)
    }

    /// The row has no sections stacked: whichever group has the tile nearest
    /// the pointer, a divider or the zone's margin included.
    private func nearestGroup(to point: CGPoint) -> Hit {
        var best: (kind: PanelSection.Kind, distance: CGFloat)?
        for group in groups {
            for tile in group.tiles {
                let dx = max(tile.minX - point.x, 0, point.x - tile.maxX)
                let dy = max(tile.minY - point.y, 0, point.y - tile.maxY)
                // A row of its own outweighs a nearer tile in another row.
                let distance = dx * dx + 4 * dy * dy
                if best == nil || distance < best!.distance { best = (group.kind, distance) }
            }
        }
        switch best?.kind {
        case .hidden: return .section(.hidden)
        case .alwaysHidden: return .section(.alwaysHidden)
        case .didntFit, nil: return .none
        }
    }

    /// Edges count: a pointer pushed to the display's top row sits at maxY.
    private static func covers(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}

/// Where on the bar a tile dropped on it would land: between two Visible
/// icons, or at the chevron's edge. macOS can't open a gap in the real bar, so
/// the panel draws a line at `x` instead.
public struct PanelBarGap: Equatable, Sendable {
    /// A Visible icon on the panel's display, in the pointer's x.
    public struct Icon: Equatable, Sendable {
        public var id: ItemID
        public var minX: CGFloat
        public var maxX: CGFloat
        /// The clock and Control Center end the bar and stay there: nothing
        /// is dropped after them.
        public var movable: Bool

        public init(id: ItemID, minX: CGFloat, maxX: CGFloat, movable: Bool) {
            self.id = id
            self.minX = minX
            self.maxX = maxX
            self.movable = movable
        }
    }

    /// Where the line goes.
    public var x: CGFloat
    /// The Visible icon right of the gap, which the tile goes in front of;
    /// nil past the last one.
    public var before: ItemID?

    public init(x: CGFloat, before: ItemID?) {
        self.x = x
        self.before = before
    }

    /// The gap nearest `x`. The chevron's edge (`edge`, its right side) is
    /// one, left of the first icon; none past an icon that can't move.
    public static func nearest(to x: CGFloat, icons: [Icon], edge: CGFloat?) -> PanelBarGap? {
        let row = icons.sorted { $0.minX < $1.minX }
        guard let first = row.first, let last = row.last else { return nil }
        var gaps = [PanelBarGap(x: edge.map { (min($0, first.minX) + first.minX) / 2 } ?? first.minX, before: first.id)]
        for (left, right) in zip(row, row.dropFirst()) where left.movable {
            gaps.append(PanelBarGap(x: (left.maxX + right.minX) / 2, before: right.id))
        }
        if last.movable { gaps.append(PanelBarGap(x: last.maxX, before: nil)) }
        return gaps.min { abs($0.x - x) < abs($1.x - x) }
    }
}
