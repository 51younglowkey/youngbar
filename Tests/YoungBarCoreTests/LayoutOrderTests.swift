// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation
import Testing
@testable import YoungBarCore

@Suite struct LayoutOrderTests {
    @Test func uniqueKeepsFirstOccurrence() {
        #expect(LayoutOrder.unique(["a", "b", "a", "c", "b"]) == ["a", "b", "c"])
    }

    @Test func newItemGoesWhereItSits() {
        let order = ["wechat", "codexbar", "wifi"]
        let x: [String: CGFloat] = ["wechat": 1300, "codexbar": 1350, "wifi": 1530]
        #expect(LayoutOrder.insertionIndex(forMinX: 1400, in: order, minX: x) == 2)
        #expect(LayoutOrder.insertionIndex(forMinX: 1000, in: order, minX: x) == 0)
        #expect(LayoutOrder.insertionIndex(forMinX: 1700, in: order, minX: x) == 3)
    }

    @Test func reconcileRewritesOnlyVisibleSlots() {
        // "h" is concealed and keeps its slot; the three on the bar swap.
        let saved = ["a", "h", "b", "c"]
        #expect(LayoutOrder.reconciled(saved, actual: ["c", "a", "b"]) == ["c", "h", "a", "b"])
    }

    @Test func reconcileIgnoresUnknownAndAgreeingOrders() {
        #expect(LayoutOrder.reconciled(["a", "b"], actual: ["a", "b", "new"]) == nil)
        #expect(LayoutOrder.reconciled(["a", "b"], actual: ["a"]) == nil)
    }

    @Test func movingBeforeAnotherOrToTheEnd() {
        #expect(LayoutOrder.moving("c", before: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
        #expect(LayoutOrder.moving("a", before: "", in: ["a", "b", "c"]) == ["b", "c", "a"])
        #expect(LayoutOrder.moving("a", before: "missing", in: ["a", "b"]) == ["b", "a"])
    }
}

@Suite struct OverflowTests {
    let notchRight: CGFloat = 1010

    @Test func itemsUnderTheNotchOverflow() {
        let frames: [String: CGRect?] = [
            "clear": CGRect(x: 1100, y: 0, width: 30, height: 38),
            "edge": CGRect(x: 1000, y: 0, width: 30, height: 38),
            "under": CGRect(x: 850, y: 0, width: 30, height: 38),
        ]
        #expect(Overflow.keys(frames: frames, visibleMinX: notchRight) == ["edge", "under"])
    }

    @Test func undrawnItemsOverflow() {
        #expect(Overflow.keys(frames: ["gone": nil], visibleMinX: notchRight) == ["gone"])
    }

    /// The crowded bar measured on this MacBook (2026-10-29): YoungBar's
    /// own item and Youdao piled on the « slot, Codex the first real icon.
    @Test func itemsPiledOnTheChevronAreTrapped() {
        let frames: [String: CGRect?] = [
            "youngbar": CGRect(x: 1008.5, y: 0, width: 38, height: 38),
            "youdao": CGRect(x: 1014.5, y: 0, width: 38, height: 38),
            "codex": CGRect(x: 1054.5, y: 0, width: 38, height: 38),
            "claude": CGRect(x: 1092.5, y: 0, width: 38, height: 38),
        ]
        #expect(Overflow.keys(frames: frames, visibleMinX: notchRight) == ["youngbar", "youdao"])
    }

    /// Pelmet's measured case: staggered trapped frames, then real icons
    /// whose AX padding overlaps by 2pt.
    @Test func paddingOverlapIsNotTrapped() {
        let frames: [String: CGRect] = [
            "velja": CGRect(x: 1044, y: 0, width: 37, height: 24),
            "dbngin": CGRect(x: 1049, y: 0, width: 24, height: 24),
            "separator": CGRect(x: 1055, y: 0, width: 26, height: 24),
            "openclip": CGRect(x: 1087, y: 0, width: 36, height: 24),
            "herd": CGRect(x: 1121, y: 0, width: 30, height: 24),
        ]
        #expect(Overflow.trapped(frames) == ["velja", "dbngin", "separator"])
    }

    @Test func noNotchStillFindsTrapped() {
        let frames: [String: CGRect?] = [
            "a": CGRect(x: 400, y: 0, width: 30, height: 24),
            "b": CGRect(x: 405, y: 0, width: 30, height: 24),
            "c": CGRect(x: 500, y: 0, width: 30, height: 24),
        ]
        #expect(Overflow.keys(frames: frames, visibleMinX: nil) == ["a", "b"])
    }
}

@Suite struct HotKeyComboTests {
    @Test func standardIsDoubleCommand() {
        #expect(HotKeyCombo.standard.isDoubleTap)
        #expect(HotKeyCombo.standard.modifiers == HotKeyCombo.command)
        #expect(HotKeyCombo.standard.isUsable)
        #expect(HotKeyCombo.legacy.display(keyName: "B") == "⌃⌥B")
    }

    @Test func doubleTapNeedsOneModifier() {
        #expect(!HotKeyCombo.doubleTap(HotKeyCombo.shift).isUsable)
        #expect(!HotKeyCombo.doubleTap(HotKeyCombo.command | HotKeyCombo.option).isUsable)
        #expect(HotKeyCombo.doubleTap(HotKeyCombo.control).isUsable)
    }

    @Test func symbolsFollowMenuOrder() {
        let all = HotKeyCombo(keyCode: 0, modifiers: HotKeyCombo.command | HotKeyCombo.shift | HotKeyCombo.option | HotKeyCombo.control)
        #expect(all.modifierSymbols == "⌃⌥⇧⌘")
    }

    @Test func shiftAloneIsNotUsable() {
        #expect(!HotKeyCombo(keyCode: 0, modifiers: HotKeyCombo.shift).isUsable)
        #expect(!HotKeyCombo(keyCode: 0, modifiers: 0).isUsable)
        #expect(HotKeyCombo(keyCode: 0, modifiers: HotKeyCombo.command | HotKeyCombo.shift).isUsable)
    }

    @Test func strayBitsAreDropped() {
        #expect(HotKeyCombo(keyCode: 1, modifiers: HotKeyCombo.option | 0x1).modifiers == HotKeyCombo.option)
    }
}

@Suite struct DoubleTapDetectorTests {
    let command = HotKeyCombo.command

    @Test func twoQuickTapsFire() {
        var detector = DoubleTapDetector(target: command)
        #expect(detector.flagsChanged(command, at: 0.00) == nil)
        #expect(detector.flagsChanged(0, at: 0.08) == nil)
        #expect(detector.flagsChanged(command, at: 0.20) == nil)
        #expect(detector.flagsChanged(0, at: 0.28) == command)
        // A third tap starts over.
        #expect(detector.flagsChanged(command, at: 0.40) == nil)
        #expect(detector.flagsChanged(0, at: 0.45) == nil)
    }

    @Test func aKeyInBetweenCancels() {
        var detector = DoubleTapDetector(target: command)
        _ = detector.flagsChanged(command, at: 0)
        _ = detector.flagsChanged(0, at: 0.1)
        _ = detector.flagsChanged(command, at: 0.2)
        detector.otherKey() // ⌘C
        #expect(detector.flagsChanged(0, at: 0.3) == nil)
        _ = detector.flagsChanged(command, at: 0.4)
        detector.otherKey() // ⌘V
        #expect(detector.flagsChanged(0, at: 0.5) == nil)
    }

    @Test func slowTapsOrHeldKeyDoNotFire() {
        var detector = DoubleTapDetector(target: command)
        _ = detector.flagsChanged(command, at: 0)
        _ = detector.flagsChanged(0, at: 0.1)
        _ = detector.flagsChanged(command, at: 1.0)
        #expect(detector.flagsChanged(0, at: 1.1) == nil)
        _ = detector.flagsChanged(command, at: 1.2)
        #expect(detector.flagsChanged(0, at: 2.0) == nil) // held
    }

    @Test func otherModifierJoiningCancels() {
        var detector = DoubleTapDetector(target: command)
        _ = detector.flagsChanged(command, at: 0)
        _ = detector.flagsChanged(0, at: 0.1)
        _ = detector.flagsChanged(command, at: 0.2)
        _ = detector.flagsChanged(command | HotKeyCombo.shift, at: 0.25)
        #expect(detector.flagsChanged(0, at: 0.3) == nil)
    }

    @Test func recordingTakesAnyModifierButNotMixed() {
        var detector = DoubleTapDetector(target: nil)
        let option = HotKeyCombo.option
        _ = detector.flagsChanged(option, at: 0)
        _ = detector.flagsChanged(0, at: 0.1)
        _ = detector.flagsChanged(command, at: 0.2)
        #expect(detector.flagsChanged(0, at: 0.3) == nil)
        _ = detector.flagsChanged(command, at: 0.4)
        #expect(detector.flagsChanged(0, at: 0.5) == command)
    }
}

@Suite struct ConfigFileTests {
    @Test func roundTrip() throws {
        let file = ConfigFile(itemModes: ["bundle:a": 1, "bundle:b": 2], itemOrder: ["bundle:a", "bundle:b"],
                              options: ["language": 1], exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try ConfigFile.decode(file.encoded(), knownOptions: ["language"])
        #expect(decoded == file)
    }

    @Test func importCleansInput() throws {
        let file = ConfigFile(itemModes: ["ok": 1, "bad": 7], itemOrder: ["a", "a", "b"],
                              options: ["language": 1, "fromTheFuture": 3])
        let decoded = try ConfigFile.decode(file.encoded(), knownOptions: ["language"])
        #expect(decoded.itemModes == ["ok": 1])
        #expect(decoded.itemOrder == ["a", "b"])
        #expect(decoded.options == ["language": 1])
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: ConfigFile.ImportError.unreadable) {
            try ConfigFile.decode(Data("{\"hello\":1}".utf8), knownOptions: [])
        }
        var newer = ConfigFile(itemModes: [:], itemOrder: [], options: [:])
        newer.format = ConfigFile.currentFormat + 1
        #expect(throws: ConfigFile.ImportError.newerFormat(ConfigFile.currentFormat + 1)) {
            try ConfigFile.decode(newer.encoded(), knownOptions: [])
        }
        var other = ConfigFile(itemModes: [:], itemOrder: [], options: [:])
        other.app = "Elsewhere"
        #expect(throws: ConfigFile.ImportError.notYoungBar) {
            try ConfigFile.decode(other.encoded(), knownOptions: [])
        }
    }
}
