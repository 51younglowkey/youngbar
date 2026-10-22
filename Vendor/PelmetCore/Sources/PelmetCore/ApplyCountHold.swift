// ApplyCountHold.swift
// The number the Apply button shows, from the raw count (`ApplyCount`, read
// off asynchronous snapshots). The raw count dips to 0 for a beat whenever a
// snapshot lands before the walk that explains it: a stale walk at the drop,
// an own extra's show, and a reveal (a concealed Shortcuts drop read "= 1",
// then "= 0" at the LG reveal's settle and "= 1" again 126ms later, live
// test, 2026-10-13 21:13:26). Each was patched on its own path; this holds
// the button instead, once for every path.
//
// A drop to 0 while order edits are pending is held for `hold` and shown
// only if the count still reads 0 then. Everything else shows at once: a
// rise, a drop to another number, and any count once the edits are empty
// (Apply, Discard or a settle cleared them: the button never keeps a stale
// number, and going dark is never delayed). Pure: the caller feeds it every
// raw read and arranges a read at `due`.

import Foundation

public struct ApplyCountHold: Equatable, Sendable {
    public let hold: Duration
    /// The number on the button.
    public private(set) var shown = 0
    /// When a held drop to 0 may show, while one is held.
    public private(set) var due: ContinuousClock.Instant?

    public var isHolding: Bool { due != nil }

    public init(hold: Duration) {
        self.hold = hold
    }

    /// One read of the raw count. `editsPending`: the editor holds order
    /// edits not yet applied. Returns the number to show.
    @discardableResult
    public mutating func feed(_ raw: Int, editsPending: Bool, now: ContinuousClock.Instant) -> Int {
        if editsPending, raw == 0, shown > 0 {
            if let due {
                if now >= due {
                    shown = 0
                    self.due = nil
                }
            } else {
                due = now + hold
            }
        } else {
            shown = raw
            due = nil
        }
        return shown
    }
}
