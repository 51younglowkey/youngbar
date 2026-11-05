// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import YoungBarCore

@Suite struct EventLogTests {
    @Test func keepsOnlyTheNewestLines() {
        var log = EventLog(capacity: 3)
        for index in 1...5 { log.append("event \(index)", stamp: "t\(index)") }
        #expect(log.lines == ["t3 event 3", "t4 event 4", "t5 event 5"])
    }

    @Test func recentReturnsTheNewestOldestFirst() {
        var log = EventLog(capacity: 10)
        for index in 1...4 { log.append("e\(index)", stamp: "t") }
        #expect(log.recent(2) == ["t e3", "t e4"])
        #expect(log.recent(0).isEmpty)
        #expect(log.recent(99).count == 4)
    }

    @Test func sameKeyInARowBecomesOneLineWithTheLatestTextAndTime() {
        var log = EventLog()
        log.append("small x1→x2", stamp: "10:00", mergeKey: "small")
        log.append("small x2→x3", stamp: "10:01", mergeKey: "small")
        log.append("small x3→x4", stamp: "10:02", mergeKey: "small")
        #expect(log.lines == ["10:02 small x3→x4 ×3"])
    }

    @Test func anotherEventBreaksAMerge() {
        var log = EventLog()
        log.append("small", stamp: "1", mergeKey: "small")
        log.append("wake", stamp: "2")
        log.append("small", stamp: "3", mergeKey: "small")
        #expect(log.lines == ["1 small", "2 wake", "3 small"])
    }

    @Test func identicalTextMergesWithoutAKey() {
        var log = EventLog()
        log.append("wake", stamp: "1")
        log.append("wake", stamp: "2")
        #expect(log.lines == ["2 wake ×2"])
    }

    @Test func aLineIsAlwaysOneLineAndBounded() {
        var log = EventLog()
        log.append("first\nsecond\r\nthird", stamp: "t")
        #expect(log.lines == ["t first second third"])
        log.append(String(repeating: "x", count: 5000), stamp: "t")
        #expect(log.lines[1].count == EventLog.maxLineLength + 2)
    }

    @Test func restoresThePreviousRunAndDoesNotMergeIntoIt() {
        var first = EventLog()
        first.append("launch", stamp: "09:00")
        first.append("wake", stamp: "09:30")
        var second = EventLog(restoring: first.fileText)
        #expect(second.lines == first.lines)
        second.append("09:30 wake", stamp: "10:00")
        #expect(second.lines == ["09:00 launch", "09:30 wake", "10:00 09:30 wake"])
    }

    @Test func restoringMoreThanCapacityKeepsTheNewest() {
        var first = EventLog(capacity: 10)
        for index in 1...6 { first.append("e\(index)", stamp: "t") }
        #expect(EventLog(capacity: 2, restoring: first.fileText).lines == ["t e5", "t e6"])
    }

    @Test func anEmptyLogHasAnEmptyFile() {
        #expect(EventLog().fileText.isEmpty)
        #expect(EventLog(restoring: "").lines.isEmpty)
    }
}

@Suite struct ControlMoveTests {
    @Test func anIconsWidthIsNotAJump() {
        #expect(!ControlMove.isJump(from: CGPoint(x: 1400, y: 1140), to: CGPoint(x: 1370, y: 1140)))
        #expect(!ControlMove.isJump(from: CGPoint(x: 1400, y: 1140), to: CGPoint(x: 1341, y: 1143)))
    }

    @Test func farOrOffTheLineIsAJump() {
        #expect(ControlMove.isJump(from: CGPoint(x: 1400, y: 1140), to: CGPoint(x: 1340, y: 1140)))
        #expect(ControlMove.isJump(from: CGPoint(x: 1400, y: 1140), to: CGPoint(x: 1600, y: 1140)))
        #expect(ControlMove.isJump(from: CGPoint(x: 1400, y: 1140), to: CGPoint(x: 1400, y: 1134)))
    }
}

@Suite struct ControlCheckTests {
    let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

    func check(_ control: CGRect, icon: Double? = 1440) -> ControlCheck {
        ControlCheck.evaluate(control: control, screens: [screen], barMinY: 1132, barMaxY: 1169, leadingIconX: icon)
    }

    @Test func inPlacePasses() {
        let result = check(CGRect(x: 1400, y: 1138, width: 34, height: 24))
        #expect(result.onScreen && result.inBar)
        #expect(result.gapToIcon == 6)
        #expect(result.besideIcons == true)
        #expect(result.allPassed)
    }

    @Test func belowTheBarFails() {
        let result = check(CGRect(x: 1400, y: 900, width: 34, height: 24))
        #expect(result.onScreen && !result.inBar && !result.allPassed)
    }

    @Test func offEveryScreenFails() {
        let result = check(CGRect(x: -400, y: 1138, width: 34, height: 24))
        #expect(!result.onScreen && !result.allPassed)
    }

    @Test func farFromTheIconsFails() {
        #expect(check(CGRect(x: 900, y: 1138, width: 34, height: 24)).besideIcons == false)
    }

    @Test func coveringAnIconFails() {
        #expect(check(CGRect(x: 1420, y: 1138, width: 34, height: 24)).besideIcons == false)
    }

    @Test func nothingToCompareStillPasses() {
        let result = check(CGRect(x: 1400, y: 1138, width: 34, height: 24), icon: nil)
        #expect(result.besideIcons == nil)
        #expect(result.allPassed)
    }
}
