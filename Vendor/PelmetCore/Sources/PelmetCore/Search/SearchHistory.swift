// SearchHistory.swift
// What the user picked, for ranking: a recency-weighted pick count (frecency)
// and the query latch. Stored apart from the settings blob under its own key
// (`app.fif7y.Pelmet.search.v1`) so "Reset search history" is one delete.

import Foundation

public struct SearchHistory: Codable, Equatable, Sendable {
    public struct Pick: Codable, Equatable, Sendable {
        public let id: String
        /// Normalized query typed when it was picked; empty when picked
        /// from the rest state.
        public let query: String
        public let at: Date
    }

    /// A pick's weight halves every two weeks, so about a month of memory.
    public static let halfLife: TimeInterval = 14 * 24 * 3600
    /// Oldest picks drop first. By then they weigh almost nothing anyway.
    public static let maxPicks = 300

    /// Oldest first.
    public private(set) var picks: [Pick] = []

    public init() {}

    public mutating func record(id: String, query: String, at date: Date) {
        picks.append(Pick(id: id, query: FoldedText.normalized(query), at: date))
        if picks.count > Self.maxPicks {
            picks.removeFirst(picks.count - Self.maxPicks)
        }
    }

    public mutating func reset() {
        picks.removeAll()
    }

    /// Drops every pick of one row, and with them the queries that latched
    /// onto it: the row goes back to where a never-picked one ranks.
    public mutating func forget(id: String) {
        picks.removeAll { $0.id == id }
    }

    public func hasPicks(for id: String) -> Bool {
        picks.contains { $0.id == id }
    }

    /// Recency-weighted pick count: a pick today is 1, two weeks ago 0.5.
    public func frecency(of id: String, at now: Date) -> Double {
        var total = 0.0
        for pick in picks where pick.id == id {
            total += Self.weight(of: pick, at: now)
        }
        return total
    }

    /// Frecency of every picked id in one pass; the ranker looks rows up in
    /// this instead of scanning the picks once per candidate.
    public func frecencies(at now: Date) -> [String: Double] {
        var table: [String: Double] = [:]
        for pick in picks {
            table[pick.id, default: 0] += Self.weight(of: pick, at: now)
        }
        return table
    }

    /// The id the user keeps choosing for this query: the last two picks for
    /// it were the same row. A later pick of a different row ends it, and two
    /// more picks of that one hand the latch over.
    public func latchedID(for query: String) -> String? {
        let key = FoldedText.normalized(query)
        guard !key.isEmpty else { return nil }
        var last: String?
        for pick in picks.reversed() where pick.query == key {
            guard let previous = last else {
                last = pick.id
                continue
            }
            return previous == pick.id ? previous : nil
        }
        return nil
    }

    private static func weight(of pick: Pick, at now: Date) -> Double {
        // A pick stamped in the future (clock change) counts as just made.
        let age = max(0, now.timeIntervalSince(pick.at))
        return exp2(-age / halfLife)
    }
}
