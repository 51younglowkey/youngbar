// StrayBudget.swift
// The bound on "keep sections grouped" (docs/CORE-SETS.md, #80): the
// automatic pass tries an item at most `limit` times while its roster
// section stays what it is, then leaves it to the editor's "not in place"
// badge and Apply. Pure bookkeeping, no timing: the app asks before each
// pass and tells it which items a pass tried.
//
// Keyed by (item, roster section). Only a change of the item's section
// clears its budget (the user's drop in the editor is a new question),
// whenever it happens (`observe`).
// A bar with no strays, a pass that moved the item, the item vanishing or
// re-registering never reset it: an app that relaunches and re-registers on
// the wrong side again and again is not dragged forever.

import Foundation

public struct StrayBudget: Equatable, Sendable {
    public struct Verdict: Equatable, Sendable {
        /// Strays with attempts left, in the order given.
        public var ready: [ItemID]
        /// Strays that used them all.
        public var exhausted: [ItemID]
        /// The subset of `exhausted` reported for the first time (once per
        /// item and section), for the "giving up" log line.
        public var newlyExhausted: [ItemID]
    }

    private struct Entry: Equatable, Sendable {
        var section: Section
        var used: Int
        var announced: Bool
    }

    public let limit: Int
    private var entries: [ItemID: Entry] = [:]

    public init(limit: Int = 2) {
        self.limit = limit
    }

    /// The entry in force for `id` under `roster`; a stale one (the section
    /// changed since) is replaced by a fresh one.
    private mutating func entry(_ id: ItemID, _ roster: Roster) -> Entry {
        let section = roster.section(of: id)
        if let existing = entries[id], existing.section == section { return existing }
        let fresh = Entry(section: section, used: 0, announced: false)
        entries[id] = fresh
        return fresh
    }

    public mutating func check(_ strays: [ItemID], roster: Roster) -> Verdict {
        var verdict = Verdict(ready: [], exhausted: [], newlyExhausted: [])
        for id in strays {
            var entry = entry(id, roster)
            if entry.used < limit {
                verdict.ready.append(id)
            } else {
                verdict.exhausted.append(id)
                if !entry.announced {
                    entry.announced = true
                    entries[id] = entry
                    verdict.newlyExhausted.append(id)
                }
            }
        }
        return verdict
    }

    /// The roster as it is now, stray or not: an item whose section changed
    /// since its budget opened starts fresh. Read only at a check, a change
    /// made while the item sat on its side was never seen: Vorssaint moved
    /// to Visible, placed, moved to Hidden and back by hand, and placed
    /// again read "attempt 2/2", and the next round "giving up … after 2
    /// attempts" (live test, 2026-10-13 20:17:52).
    public mutating func observe(_ roster: Roster) {
        entries = entries.filter { roster.section(of: $0.key) == $0.value.section }
    }

    /// Attempts used for `id` under its current section.
    public mutating func used(_ id: ItemID, roster: Roster) -> Int {
        entry(id, roster).used
    }

    /// A pass that started tried these items.
    public mutating func spend(_ ids: [ItemID], roster: Roster) {
        for id in ids {
            var entry = entry(id, roster)
            entry.used += 1
            entries[id] = entry
        }
    }
}
