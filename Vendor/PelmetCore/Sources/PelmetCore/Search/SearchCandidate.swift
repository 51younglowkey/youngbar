// SearchCandidate.swift
// One row the command bar can offer, and one scored hit on it. The caller
// builds candidates from whatever it knows (items, launchers, settings,
// commands); the search core never learns where they came from.

import Foundation

public struct SearchCandidate: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case item, launcher, setting, command
    }

    /// Stable key across keystrokes and launches: an `ItemID` raw value,
    /// "setting:hoverReveal", "command:quit", "launcher:<bundle>". History
    /// is keyed on it, so it must not change when a title does.
    public let id: String
    public let kind: Kind
    public let title: String
    /// App name for items, tab name for settings. Matches rank below titles.
    public let subtitle: String?
    /// Synonyms and setting keywords ("bt" for Bluetooth).
    public let keywords: [String]
    /// The user's own name for it; outranks everything else it matches.
    public let alias: String?
    /// Where an item lives. Nil for rows that are not menu bar items.
    public let section: Section?
    /// Base weight the caller sets (e.g. settings below items); 1 is neutral.
    public let weight: Double

    // Folded once at construction: building the corpus happens when the bar
    // opens, ranking happens on every keystroke.
    let foldedTitle: FoldedText
    let foldedSubtitle: FoldedText?
    let foldedKeywords: [FoldedText]
    let foldedAlias: FoldedText?

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = [],
        alias: String? = nil,
        section: Section? = nil,
        weight: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.alias = alias
        self.section = section
        self.weight = weight
        self.foldedTitle = FoldedText(title)
        self.foldedSubtitle = subtitle.map(FoldedText.init)
        self.foldedKeywords = keywords.map(FoldedText.init)
        self.foldedAlias = alias.map(FoldedText.init)
    }

    /// The same row with another alias (the user just set or cleared it),
    /// so the corpus need not be rebuilt for one name.
    public func withAlias(_ alias: String?) -> SearchCandidate {
        SearchCandidate(
            id: id, kind: kind, title: title, subtitle: subtitle, keywords: keywords,
            alias: alias, section: section, weight: weight
        )
    }
}

public struct SearchMatch: Equatable, Sendable {
    /// Which of the candidate's texts produced the winning score.
    public enum Field: String, Sendable {
        case title, subtitle, keyword, alias
    }

    public let candidate: SearchCandidate
    public let score: Double
    public let field: Field
    /// The keyword or alias that matched, so the row can say "bt → Bluetooth".
    /// Nil for title and subtitle hits.
    public let matchedText: String?
    /// Matched runs in the title as Character offsets, for bolding. Empty
    /// unless the title itself matched.
    public let titleRanges: [Range<Int>]
}
