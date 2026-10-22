// FuzzyMatcher.swift
// Scores a typed query against one string, the way a command palette expects:
// "wifi" is Wi-Fi, "cc" is Control Center, "ctrcen" is still Control Center.
// Letters must appear in order; separators in either string are ignored.
//
// The score lives in tiers so the order is a guarantee, not a tuning outcome:
// exact > prefix > word prefix > acronym > scattered. Inside the scattered
// tier a Sublime-style DP picks the best path (consecutive runs and word
// starts earn bonuses, gaps and a late start cost).

import Foundation

public struct FuzzyMatch: Equatable, Sendable {
    /// Shape of the match, best last so tiers compare with `<`.
    public enum Tier: Int, Comparable, Sendable {
        case scattered, acronym, wordPrefix, prefix, exact

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let tier: Tier
    public let score: Double
    /// Matched runs as Character offsets into the original string, for
    /// bolding. Runs split at separators ("Wi-Fi" for "wf" → 0..<1, 3..<4).
    public let ranges: [Range<Int>]
}

public enum FuzzyMatcher {
    // Tier floors. Each tier's spread stays under the gap to the next one
    // (exact 1000 · prefix 700–800 · word prefix 460–560 · acronym 350–400 ·
    // scattered 10–330), so only weights, sections and frecency in the ranker
    // can reorder across tiers, never the matcher itself.
    static let exactScore = 1000.0
    static let prefixBase = 700.0
    static let wordPrefixBase = 500.0
    static let acronymBase = 350.0
    static let scatteredFloor = 10.0
    static let scatteredCeiling = 330.0

    // Scattered DP, integer units. A consecutive pair outweighs a word start
    // so "ener" beats "e…n…e…r" scattered; a word start outweighs a few gap
    // letters so landing on a word beats drifting inside one.
    static let consecutiveBonus = 30
    static let wordStartBonus = 24
    static let firstLetterBonus = 32
    static let innerGapPenalty = 2
    static let leadingGapPenalty = 1
    /// Raw DP score 0 maps here, so a typical mixed path ("ctrcen") lands
    /// around 200 and a thin one under 100.
    static let scatteredOffset = 100

    /// DP bounds. Menu bar titles are short; anything longer falls back to
    /// the leftmost greedy path instead of an unbounded matrix.
    private static let maxQuery = 48
    private static let maxText = 192

    public static func match(_ query: String, in text: String) -> FuzzyMatch? {
        match(FoldedText(query), in: FoldedText(text))
    }

    /// Nil when the query's letters do not all appear in order.
    public static func match(_ query: FoldedText, in text: FoldedText) -> FuzzyMatch? {
        let m = query.count
        let n = text.count
        guard m > 0, m <= n, isSubsequence(query, of: text) else { return nil }
        let coverage = Double(m) / Double(n)

        if hasPrefix(query, text) {
            let positions = Array(0..<m)
            return FuzzyMatch(
                tier: m == n ? .exact : .prefix,
                score: m == n ? exactScore : prefixBase + 100 * coverage,
                ranges: ranges(of: positions, in: text)
            )
        }

        if let (start, wordIndex) = wordPrefixStart(query, in: text) {
            let positions = Array(start..<(start + m))
            return FuzzyMatch(
                tier: .wordPrefix,
                score: wordPrefixBase + 60 * coverage - 8 * Double(min(wordIndex, 5)),
                ranges: ranges(of: positions, in: text)
            )
        }

        if m >= 2, let positions = acronymPositions(query, in: text) {
            let words = text.wordStart.reduce(0) { $0 + ($1 ? 1 : 0) }
            let leads = positions[0] == 0 ? 10.0 : 0
            return FuzzyMatch(
                tier: .acronym,
                score: acronymBase + 40 * Double(m) / Double(words) + leads,
                ranges: ranges(of: positions, in: text)
            )
        }

        let (raw, positions) = scattered(query, in: text)
        let score = min(scatteredCeiling, max(scatteredFloor, Double(scatteredOffset + raw)))
        return FuzzyMatch(tier: .scattered, score: score, ranges: ranges(of: positions, in: text))
    }

    // MARK: - Tiers

    private static func isSubsequence(_ query: FoldedText, of text: FoldedText) -> Bool {
        var q = 0
        for scalar in text.scalars where scalar == query.scalars[q] {
            q += 1
            if q == query.count { return true }
        }
        return false
    }

    private static func hasPrefix(_ query: FoldedText, _ text: FoldedText) -> Bool {
        for i in 0..<query.count where query.scalars[i] != text.scalars[i] { return false }
        return true
    }

    /// First place the whole query runs contiguously from a word's first
    /// letter ("cen" in "Control Center"), and how many words precede it.
    private static func wordPrefixStart(_ query: FoldedText, in text: FoldedText) -> (start: Int, wordIndex: Int)? {
        let m = query.count
        var wordIndex = 0
        for start in 0...(text.count - m) {
            guard text.wordStart[start] else { continue }
            if start > 0 { wordIndex += 1 }
            var i = 0
            while i < m, text.scalars[start + i] == query.scalars[i] { i += 1 }
            if i == m { return (start, wordIndex) }
        }
        return nil
    }

    /// Query letters landing on successive word starts ("ccd" → Control
    /// Center Display). Words may be skipped; leftmost assignment is enough
    /// because only existence and the ranges matter.
    private static func acronymPositions(_ query: FoldedText, in text: FoldedText) -> [Int]? {
        var positions: [Int] = []
        var q = 0
        for j in 0..<text.count where text.wordStart[j] && text.scalars[j] == query.scalars[q] {
            positions.append(j)
            q += 1
            if q == query.count { return positions }
        }
        return nil
    }

    // MARK: - Scattered

    /// Best subsequence path by DP (fzy-style): `d` = best score with the
    /// query letter matched exactly at this text position, `best` = best score
    /// within the text so far. Backtracking recovers the positions.
    private static func scattered(_ query: FoldedText, in text: FoldedText) -> (raw: Int, positions: [Int]) {
        let m = query.count
        let n = text.count
        guard m <= maxQuery, n <= maxText else {
            return (0, greedyPositions(query, in: text))
        }

        let never = Int.min / 2
        var d = [Int](repeating: never, count: m * n)
        var best = [Int](repeating: never, count: m * n)

        for i in 0..<m {
            let lastRow = i == m - 1
            var carry = never
            for j in 0..<n {
                var here = never
                if query.scalars[i] == text.scalars[j] {
                    let bonus = text.wordStart[j] ? (j == 0 ? firstLetterBonus : wordStartBonus) : 0
                    if i == 0 {
                        here = -leadingGapPenalty * j + bonus
                    } else if j > 0 {
                        var viaGap = never
                        if best[(i - 1) * n + j - 1] > never {
                            viaGap = best[(i - 1) * n + j - 1] + bonus
                        }
                        var viaRun = never
                        if d[(i - 1) * n + j - 1] > never {
                            viaRun = d[(i - 1) * n + j - 1] + consecutiveBonus
                        }
                        here = max(viaGap, viaRun)
                    }
                }
                d[i * n + j] = here
                // Letters left unmatched after the last query letter are free.
                let gap = lastRow ? 0 : innerGapPenalty
                carry = max(here, carry > never ? carry - gap : never)
                best[i * n + j] = carry
            }
        }

        // Backtrack: take the last row's best end, then walk left, staying
        // glued to the previous letter whenever the run bonus produced it.
        var positions = [Int](repeating: 0, count: m)
        var runRequired = false
        var j = n - 1
        for i in stride(from: m - 1, through: 0, by: -1) {
            while j >= 0 {
                let here = d[i * n + j]
                if here > never, runRequired || here == best[i * n + j] {
                    runRequired = i > 0 && j > 0
                        && best[i * n + j] == d[(i - 1) * n + j - 1] + consecutiveBonus
                    positions[i] = j
                    j -= 1
                    break
                }
                j -= 1
            }
        }
        return (best[m * n - 1], positions)
    }

    private static func greedyPositions(_ query: FoldedText, in text: FoldedText) -> [Int] {
        var positions: [Int] = []
        var q = 0
        for j in 0..<text.count where q < query.count && text.scalars[j] == query.scalars[q] {
            positions.append(j)
            q += 1
        }
        return positions
    }

    // MARK: - Ranges

    /// Kept-character positions → Character-offset runs in the original
    /// string, merged where the original characters touch.
    private static func ranges(of positions: [Int], in text: FoldedText) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for position in positions {
            let offset = text.origin[position]
            if let last = out.last, last.upperBound == offset {
                out[out.count - 1] = last.lowerBound..<(offset + 1)
            } else {
                out.append(offset..<(offset + 1))
            }
        }
        return out
    }
}
