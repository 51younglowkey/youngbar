// FoldedText.swift
// A string prepared for matching: case and diacritics folded away, separators
// dropped, word starts marked. Built once per candidate field and once per
// query, so a keystroke compares integer arrays instead of re-folding Strings.

import Foundation

public struct FoldedText: Equatable, Sendable {
    /// Folded letters and digits, separators removed ("Wi-Fi" → w i f i).
    let scalars: [UInt32]
    /// Per kept character, its offset (in Characters) in the original string,
    /// which is what the bolding ranges are expressed in.
    let origin: [Int]
    /// Per kept character, whether it opens a word: the first letter, one
    /// after a separator, or a camelCase hump ("AirDrop" → D).
    let wordStart: [Bool]

    public init(_ text: String) {
        let chars = Array(text)
        var scalars: [UInt32] = []
        var origin: [Int] = []
        var wordStart: [Bool] = []
        scalars.reserveCapacity(chars.count)
        origin.reserveCapacity(chars.count)
        wordStart.reserveCapacity(chars.count)

        var previous = CharClass.separator
        for (offset, char) in chars.enumerated() {
            guard let folded = Self.fold(char) else {
                previous = .separator
                continue
            }
            let current = Self.classify(char)
            var opens = previous == .separator
            if previous == .lower, current == .upper { opens = true }
            if previous == .upper, current == .upper,
               offset + 1 < chars.count, Self.classify(chars[offset + 1]) == .lower {
                opens = true // "XMLParser": the P opens "Parser"
            }
            scalars.append(folded)
            origin.append(offset)
            wordStart.append(opens)
            previous = current
        }
        self.scalars = scalars
        self.origin = origin
        self.wordStart = wordStart
    }

    /// Kept characters: letters and digits.
    public var count: Int { scalars.count }
    public var isEmpty: Bool { scalars.isEmpty }

    /// The form a query is stored under in `SearchHistory`: folded, separator
    /// runs collapsed to one space, trimmed. "  Wi-Fi " and "wi fi" are one query.
    public static func normalized(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for char in text {
            if let folded = fold(char), let scalar = Unicode.Scalar(folded) {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return String(out)
    }

    /// Folded form of a character that keeps its letter or digit, nil for
    /// separators. Case, diacritics and width fold; ASCII skips Foundation
    /// because nearly every menu bar title is ASCII.
    static func fold(_ char: Character) -> UInt32? {
        if let ascii = char.asciiValue {
            switch ascii {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): return UInt32(ascii) + 32
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(ascii)
            default: return nil
            }
        }
        guard char.isLetter || char.isNumber else { return nil }
        let folded = String(char).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        // One folded unit per original Character keeps ranges 1:1 ("ß" → s).
        guard let first = folded.unicodeScalars.first,
              first.properties.isAlphabetic || first.properties.numericType != nil
        else { return nil }
        return first.value
    }

    private enum CharClass { case separator, lower, upper, digit }

    private static func classify(_ char: Character) -> CharClass {
        if char.isUppercase { return .upper }
        if char.isLowercase { return .lower }
        if char.isNumber { return .digit }
        return char.isLetter ? .lower : .separator
    }
}
