// StrayLedger.swift
// Which strays "keep sections grouped" (docs/CORE-SETS.md, #80) may move.
// Pelmet only moves a stray it can explain: the bar's physical order is the
// truth, and an icon the user put on a side by hand (a ⌘-drag BarAdoption
// could not read, a drop from another display, a drag during a pass) must
// stay where it is. The ledger remembers, per item, the last physical side
// of the chevron, the last roster section and the process behind it, and
// from the change between two looks decides:
//
//   actionable  a stray that is newly seen, relaunched (new pid), or whose
//               section changed while its side did not (an editor drop:
//               membership moved, nothing else did; a flip of Pelmet's
//               own between the two looks is no change). Lasts while it
//               stays a stray; an icon that is in place is settled.
//   byHand      its side flipped without being one of Pelmet's own planned
//               moves. Exempt until its section changes again.
//   settled     everything else (nothing to explain, nothing to do).
//
// Pure: the caller supplies sightings and its own moves.

import Foundation

public struct StrayLedger: Equatable, Sendable {
    public enum Side: Equatable, Sendable { case left, right }

    public struct Sighting: Equatable, Sendable {
        public let id: ItemID
        /// Side of the chevron on the primary bar; nil when the item has no
        /// place there right now (another display, parked, never framed).
        public let side: Side?
        public let section: Section
        public let pid: Int32?
        /// Hidden with its section right now: off the bar, and out of reach
        /// of a hand, however long it stays so.
        public let concealed: Bool

        public init(id: ItemID, side: Side?, section: Section, pid: Int32? = nil, concealed: Bool = false) {
            self.id = id
            self.side = side
            self.section = section
            self.pid = pid
            self.concealed = concealed
        }
    }

    public enum Standing: Equatable, Sendable { case actionable, settled, byHand }

    private struct Record: Equatable, Sendable {
        var side: Side?
        var section: Section
        var pid: Int32?
        var standing: Standing
        /// An actionable icon's first look off the primary bar since it was
        /// explained (or since a look last placed it).
        var unplacedSince: Date?
        var concealed = false
    }

    private var records: [ItemID: Record] = [:]

    /// How long an explanation outlives looks that can't place the icon (a
    /// relaunch not framed yet, another display). Framed after that, the
    /// wrong side may be a hand drag: it is left alone.
    public static let unplacedWindow: TimeInterval = 30

    public init() {}

    /// Left or right of `chevron` in an observed bar order (nil when either
    /// is not on it).
    public static func side(of id: ItemID, in bar: [ItemID], chevron: ItemID?) -> Side? {
        guard let chevron, let split = bar.firstIndex(of: chevron),
              let index = bar.firstIndex(of: id), index != split else { return nil }
        return index < split ? .left : .right
    }

    public func standing(of id: ItemID) -> Standing? { records[id]?.standing }

    /// The strays Pelmet may move.
    public func actionable(_ strays: [ItemID]) -> [ItemID] {
        strays.filter { records[$0]?.standing == .actionable }
    }

    /// Why a stray is not moved, for the grouper's "none to move" line:
    /// `exhausted` are the strays `StrayBudget` gave up on. The line said
    /// "by hand, or out of attempts" for a stray that was neither (settled
    /// by the look after the grouper's own drag, live test, 2026-10-13
    /// 21:14:08).
    public func whyNotMoved(_ id: ItemID, exhausted: Set<ItemID>) -> String {
        if exhausted.contains(id) { return "out of attempts" }
        switch records[id]?.standing {
        case .byHand: return "by hand"
        case .settled: return "other (nothing explains it)"
        case .actionable: return "other (actionable)"
        case nil: return "other (never seen)"
        }
    }

    /// Takes one look at the bar: every item in the snapshot, concealed or
    /// not. Items missing from it are forgotten (back later = newly seen).
    /// `strays` are the items whose side disagrees with their section right
    /// now. `ownMoves` are the items a pass of ours just tried to move: their
    /// side flips are ours. `now` is the look's time. Returns the items that
    /// flipped by hand this look.
    @discardableResult
    public mutating func observe(
        _ sightings: [Sighting], strays: Set<ItemID> = [], ownMoves: Set<ItemID> = [], now: Date = Date()
    ) -> [ItemID] {
        var next: [ItemID: Record] = [:]
        var byHand: [ItemID] = []
        for s in sightings {
            guard let prev = records[s.id] else {
                next[s.id] = Record(
                    side: s.side, section: s.section, pid: s.pid, standing: strays.contains(s.id) ? .actionable : .settled,
                    concealed: s.concealed
                )
                continue
            }
            var standing = prev.standing
            let relaunched = prev.pid != nil && s.pid != nil && prev.pid != s.pid
            let sectionChanged = prev.section != s.section
            let sideChanged = prev.side != s.side
            // A flip of our own is no side change of the person's, beside a
            // section change too. A look that comes after both the grouper's
            // drag and the next editor drop sees section and side change
            // together, the shape of an adopted ⌘-drag, and settled it:
            // Vorssaint placed in Hidden and dropped back to Visible 2.9s
            // later, inside the grouper's debounce, read "none to move" with
            // a fresh budget and no hand move (live test, 2026-10-13 21:14:08).
            let ownFlip = sideChanged && ownMoves.contains(s.id)
            // Off the bar since the last look is no flip either: an editor
            // drop into a concealed section leaves the look with the drop,
            // and read as an adoption it was left on the wrong side for Apply
            // ("nothing explains it", live test, 2026-10-13 21:43:30).
            // Nor is coming back on it from concealed: a drop out of a
            // concealed section draws it there, no hand does.
            let leftTheLook = prev.side != nil && s.side == nil
            let backFromConcealed = prev.side == nil && prev.concealed
            let flipped = sideChanged && !leftTheLook && !backFromConcealed && !ownFlip
            if relaunched {
                standing = .actionable
            } else if sectionChanged {
                standing = flipped ? .settled : .actionable
            } else if sideChanged, prev.side != nil, s.side != nil {
                if ownMoves.contains(s.id) {
                    standing = .settled
                } else {
                    standing = .byHand
                    byHand.append(s.id)
                }
            }
            // An explanation is only good while the icon is out of place: one
            // in place is settled, so a later arrival from another display
            // (a drop BarAdoption could not read) is not mistaken for one.
            // Only a look that places it can say so: a relaunched icon not
            // framed yet kept no explanation, and framed on the wrong side a
            // look later (nil → side is no flip) it stayed there. Unplaced,
            // the explanation lasts `unplacedWindow`: held for good, a hand
            // drag hours later read as explained and was moved back. A
            // concealed icon can't be dragged: its window starts over, and
            // again at the first look after it (a reveal 30s on).
            let explained = relaunched || (sectionChanged && !flipped)
            var unplacedSince: Date?
            if standing == .actionable {
                let since = (explained || s.concealed || prev.concealed ? nil : prev.unplacedSince) ?? now
                if now.timeIntervalSince(since) > Self.unplacedWindow {
                    standing = .settled
                } else if s.side == nil {
                    unplacedSince = since
                } else if !strays.contains(s.id) {
                    standing = .settled
                }
            }
            next[s.id] = Record(
                side: s.side, section: s.section, pid: s.pid ?? prev.pid, standing: standing, unplacedSince: unplacedSince,
                concealed: s.concealed
            )
        }
        records = next
        return byHand
    }
}
