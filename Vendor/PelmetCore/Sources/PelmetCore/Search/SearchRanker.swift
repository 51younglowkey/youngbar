// SearchRanker.swift
// Turns a typed query into an ordered result list: the best field score,
// scaled by the caller's weight, where the item lives, and how often it has
// been picked lately. Pure and synchronous; the 2ms-per-keystroke budget is
// held by folding candidates once (see `SearchCandidate`) and by one
// pass over the history per call.

import Foundation

public enum SearchRanker {
    // A field's score is scaled by how trustworthy that field is. An alias
    // is the user's own word for the row, so it edges out the title; a
    // synonym ranks just under the title it stands for; the app name under
    // a title always loses to a title hit.
    static let titleFactor = 1.0
    static let aliasFactor = 1.1
    static let keywordFactor = 0.9
    static let subtitleFactor = 0.6

    /// Hidden and always-hidden rows rank above visible ones on an equal
    /// match: you search for what you can't see.
    static let concealedSectionFactor = 1.2

    /// Frecency lifts a row by up to 40%, saturating: one fresh pick is
    /// +13%, three are +24%. Enough to settle ties and nudge across a tier
    /// boundary, never enough to bury an exact hit under a habit.
    static let frecencyMaxBoost = 0.4
    static let frecencyHalfSaturation = 2.0

    public static func rank(
        query: String,
        candidates: [SearchCandidate],
        history: SearchHistory = SearchHistory(),
        now: Date,
        limit: Int = 10
    ) -> [SearchMatch] {
        let folded = FoldedText(query)
        guard !folded.isEmpty, limit > 0 else { return [] }

        let frecencies = history.frecencies(at: now)
        let latched = history.latchedID(for: query)

        var scored: [(index: Int, match: SearchMatch)] = []
        for (index, candidate) in candidates.enumerated() {
            guard let hit = bestField(of: candidate, for: folded) else { continue }
            let frecency = frecencies[candidate.id] ?? 0
            let boost = 1 + frecencyMaxBoost * frecency / (frecency + frecencyHalfSaturation)
            let score = hit.score * candidate.weight * sectionFactor(candidate.section) * boost
            scored.append((index, SearchMatch(
                candidate: candidate,
                score: score,
                field: hit.field,
                matchedText: hit.text,
                titleRanges: hit.field == .title ? hit.ranges : []
            )))
        }

        // The latch beats any score; ties keep the caller's candidate order.
        scored.sort { lhs, rhs in
            let lhsLatched = lhs.match.candidate.id == latched
            let rhsLatched = rhs.match.candidate.id == latched
            if lhsLatched != rhsLatched { return lhsLatched }
            if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
            return lhs.index < rhs.index
        }
        return scored.prefix(limit).map(\.match)
    }

    /// What to show before anything is typed: the rows you can't see in the
    /// bar, most-picked recently first. Scores carry the frecency.
    public static func restState(
        candidates: [SearchCandidate],
        history: SearchHistory = SearchHistory(),
        now: Date,
        limit: Int = 5
    ) -> [SearchMatch] {
        let frecencies = history.frecencies(at: now)
        let concealed = candidates.enumerated().filter { _, candidate in
            candidate.kind == .item && (candidate.section == .hidden || candidate.section == .alwaysHidden)
        }
        let ordered = concealed.sorted { lhs, rhs in
            let l = frecencies[lhs.element.id] ?? 0
            let r = frecencies[rhs.element.id] ?? 0
            return l != r ? l > r : lhs.offset < rhs.offset
        }
        return ordered.prefix(max(0, limit)).map { _, candidate in
            SearchMatch(
                candidate: candidate,
                score: frecencies[candidate.id] ?? 0,
                field: .title,
                matchedText: nil,
                titleRanges: []
            )
        }
    }

    /// The rest of the title, in its own casing, to ghost after what's typed
    /// ("dr" → "opbox"). Only a literal title prefix completes: an acronym,
    /// synonym or app-name hit has nothing in the title to extend.
    public static func completion(query: String, for match: SearchMatch) -> String? {
        let typed = Array(query)
        let title = Array(match.candidate.title)
        guard !typed.isEmpty, title.count > typed.count else { return nil }
        for (a, b) in zip(typed, title) where comparable(a) != comparable(b) {
            return nil
        }
        return String(title[typed.count...])
    }

    // MARK: - Internals

    private struct FieldHit {
        var field: SearchMatch.Field
        var score: Double
        var text: String?
        var ranges: [Range<Int>]
    }

    /// Best weighted score over title, alias, keywords and subtitle. On a
    /// tie the earlier field wins, so a title hit is never reported as a
    /// keyword hit of the same strength.
    private static func bestField(of candidate: SearchCandidate, for query: FoldedText) -> FieldHit? {
        var best: FieldHit?
        func consider(_ field: SearchMatch.Field, _ text: FoldedText?, _ factor: Double, _ label: String?) {
            guard let text, let match = FuzzyMatcher.match(query, in: text) else { return }
            let score = match.score * factor
            if score > (best?.score ?? 0) {
                best = FieldHit(field: field, score: score, text: label, ranges: match.ranges)
            }
        }
        consider(.title, candidate.foldedTitle, titleFactor, nil)
        consider(.alias, candidate.foldedAlias, aliasFactor, candidate.alias)
        for (keyword, folded) in zip(candidate.keywords, candidate.foldedKeywords) {
            consider(.keyword, folded, keywordFactor, keyword)
        }
        consider(.subtitle, candidate.foldedSubtitle, subtitleFactor, nil)
        return best
    }

    private static func sectionFactor(_ section: Section?) -> Double {
        switch section {
        case .hidden, .alwaysHidden: concealedSectionFactor
        case .visible, nil: 1
        }
    }

    /// Case and diacritics folded, separators kept as themselves: a typed
    /// "wi-" must line up with the title's "Wi-" character for character.
    private static func comparable(_ char: Character) -> String {
        if let folded = FoldedText.fold(char), let scalar = Unicode.Scalar(folded) {
            return String(scalar)
        }
        return String(char)
    }
}
