// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import YoungBarCore

/// Inputs the app used to trust: hand-edited layout files, release bodies
/// saved from a browser, chords that end in a lone modifier.
@Suite struct SavedShortcutTests {
    let command = Int(HotKeyCombo.command)
    let controlOption = Int(HotKeyCombo.control | HotKeyCombo.option)

    @Test func nothingSavedIsTheDefault() {
        #expect(HotKeyCombo.saved(code: nil, modifiers: nil) == .standard)
    }

    @Test func minusOneIsNoShortcut() {
        #expect(HotKeyCombo.saved(code: -1, modifiers: 0) == nil)
    }

    @Test func realShortcutsComeBack() {
        #expect(HotKeyCombo.saved(code: 11, modifiers: controlOption) == .legacy)
        #expect(HotKeyCombo.saved(code: Int(HotKeyCombo.doubleTapKeyCode), modifiers: command) == .standard)
    }

    @Test func numbersThatWouldTrapFallBackToTheDefault() {
        #expect(HotKeyCombo.saved(code: 11, modifiers: -1) == .standard)
        #expect(HotKeyCombo.saved(code: -7, modifiers: command) == .standard)
        #expect(HotKeyCombo.saved(code: 70_000, modifiers: command) == .standard)
        #expect(HotKeyCombo.saved(code: Int.max, modifiers: command) == .standard)
    }

    @Test func aBareLetterOrStrayBitsAreNotAShortcut() {
        #expect(HotKeyCombo.savedPair(code: 11, modifiers: 0) == nil)
        #expect(HotKeyCombo.savedPair(code: 11, modifiers: Int(HotKeyCombo.shift)) == nil)
        #expect(HotKeyCombo.savedPair(code: 11, modifiers: command | 1) == nil)
        #expect(HotKeyCombo.savedPair(code: 200, modifiers: command) == nil)
        // A double tap is of exactly one of ⌘ ⌥ ⌃.
        #expect(HotKeyCombo.savedPair(code: Int(HotKeyCombo.doubleTapKeyCode), modifiers: controlOption) == nil)
    }

    @Test func importDropsABadShortcutAndKeepsTheRest() throws {
        let known: Set<String> = ["language", "hotKeyCode", "hotKeyModifiers"]
        let bad = ConfigFile(itemModes: [:], itemOrder: [],
                             options: ["language": 1, "hotKeyCode": 11, "hotKeyModifiers": -1])
        let decoded = try ConfigFile.decode(bad.encoded(), knownOptions: known)
        #expect(decoded.options == ["language": 1])
        let none = ConfigFile(itemModes: [:], itemOrder: [], options: ["hotKeyCode": -1, "hotKeyModifiers": 0])
        #expect(try ConfigFile.decode(none.encoded(), knownOptions: known).options == ["hotKeyCode": -1, "hotKeyModifiers": 0])
        let good = ConfigFile(itemModes: [:], itemOrder: [], options: ["hotKeyCode": 11, "hotKeyModifiers": controlOption])
        #expect(try ConfigFile.decode(good.encoded(), knownOptions: known).options == ["hotKeyCode": 11, "hotKeyModifiers": controlOption])
    }
}

@Suite struct ChordTapTests {
    let command = HotKeyCombo.command
    let shift = HotKeyCombo.shift

    @Test func theEndOfAChordIsNotATap() {
        var detector = DoubleTapDetector(target: command)
        // ⌘⇧Z with ⇧ let go first, then one quick ⌘.
        _ = detector.flagsChanged(command, at: 0.00)
        _ = detector.flagsChanged(command | shift, at: 0.05)
        detector.otherKey()
        _ = detector.flagsChanged(command, at: 0.15)
        _ = detector.flagsChanged(0, at: 0.20)
        _ = detector.flagsChanged(command, at: 0.30)
        #expect(detector.flagsChanged(0, at: 0.36) == nil)
    }

    @Test func recordingIgnoresAnAbortedChord() {
        var detector = DoubleTapDetector(target: nil)
        let option = HotKeyCombo.option
        _ = detector.flagsChanged(command | option, at: 0.00)
        _ = detector.flagsChanged(option, at: 0.10)
        _ = detector.flagsChanged(0, at: 0.15)
        _ = detector.flagsChanged(option, at: 0.25)
        #expect(detector.flagsChanged(0, at: 0.30) == nil)
        // Two real taps after that still record.
        _ = detector.flagsChanged(option, at: 0.40)
        #expect(detector.flagsChanged(0, at: 0.45) == option)
    }
}

@Suite struct ReleaseBodyTests {
    let body = "# YoungBar 9.9\n\n## 新增\n\n- 中文一条\n\n# English\n\n## New\n\n- One line\n"

    @Test func crlfBodiesStillSplitIntoLines() {
        let crlf = body.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(ReleaseNotes.blocks(ReleaseNotes.localized(crlf, preferredLanguages: ["zh-Hans"]))
                == [.section("新增"), .bullet("中文一条", level: 0)])
        #expect(ReleaseNotes.blocks(ReleaseNotes.localized(crlf, preferredLanguages: ["en"]))
                == [.section("New"), .bullet("One line", level: 0)])
        #expect(ReleaseNotes.blocks(body.replacingOccurrences(of: "\n", with: "\r")).count == 4)
    }

    @Test func aMarkerWithStraySpacesStillSplits() {
        let spaced = body.replacingOccurrences(of: "\n# English\n", with: "\n# English  \n")
        #expect(ReleaseNotes.blocks(ReleaseNotes.localized(spaced, preferredLanguages: ["en"]))
                == [.section("New"), .bullet("One line", level: 0)])
    }
}

@Suite struct MoveLandingTests {
    @Test func leftOfTheTargetMeansRightBeforeIt() {
        #expect(LayoutOrder.isAdjacent("b", to: "c", after: false, in: ["a", "b", "c"]))
        // Still somewhere left of the target, as a refused move to the right leaves it.
        #expect(!LayoutOrder.isAdjacent("a", to: "c", after: false, in: ["a", "b", "c"]))
    }

    @Test func afterTheTargetMeansRightAfterIt() {
        #expect(LayoutOrder.isAdjacent("c", to: "b", after: true, in: ["a", "b", "c"]))
        #expect(!LayoutOrder.isAdjacent("a", to: "b", after: true, in: ["a", "b", "c"]))
    }

    @Test func missingItemsNeverLand() {
        #expect(!LayoutOrder.isAdjacent("x", to: "b", after: false, in: ["a", "b"]))
        #expect(!LayoutOrder.isAdjacent("a", to: "x", after: true, in: ["a", "b"]))
    }
}

@Suite struct OtherDisplayTests {
    @Test func aCopyOnAnotherBarIsNotTrapped() {
        // Same x, but one bar sits a display above (CG y grows downwards).
        let frames: [String: CGRect] = [
            "builtIn": CGRect(x: 1200, y: 0, width: 24, height: 24),
            "external": CGRect(x: 1205, y: -1440, width: 24, height: 24),
        ]
        #expect(Overflow.trapped(frames).isEmpty)
    }

    @Test func aPileOnOneBarStillIs() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 900, y: 0, width: 24, height: 24),
            "b": CGRect(x: 905, y: 0, width: 24, height: 24),
        ]
        #expect(Overflow.trapped(frames) == ["a", "b"])
    }
}
