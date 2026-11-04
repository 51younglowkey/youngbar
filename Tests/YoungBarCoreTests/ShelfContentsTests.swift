// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Testing
@testable import YoungBarCore

@Suite struct ShelfContentsTests {
    let order = ["a", "b", "c", "d", "e"]
    let modes = ["a": 1, "b": 0, "c": 2, "e": 1]

    @Test func hiddenIconsInSavedOrder() {
        #expect(ShelfContents.keys(order: order, modes: modes, covered: [], includeAlwaysHidden: false) == ["a", "e"])
    }

    @Test func alwaysHiddenOnlyWhenAskedFor() {
        #expect(ShelfContents.keys(order: order, modes: modes, covered: [], includeAlwaysHidden: true) == ["a", "c", "e"])
    }

    @Test func coveredShowIconsJoinInBarOrder() {
        // "d" has no saved mode: it is a Show icon, and the bar has no room for it.
        #expect(ShelfContents.keys(order: order, modes: modes, covered: ["d"], includeAlwaysHidden: false) == ["a", "d", "e"])
    }

    @Test func coveredDoesNotBringBackAlwaysHidden() {
        #expect(ShelfContents.keys(order: order, modes: modes, covered: ["c"], includeAlwaysHidden: false) == ["a", "e"])
    }

    @Test func candidatesAreShowIconsOnTheBar() {
        #expect(ShelfContents.tuckInCandidates(order: order, modes: modes, covered: [], excluded: []) == ["b", "d"])
        #expect(ShelfContents.tuckInCandidates(order: order, modes: modes, covered: ["d"], excluded: []) == ["b"])
        #expect(ShelfContents.tuckInCandidates(order: order, modes: modes, covered: [], excluded: ["b"]) == ["d"])
    }

    @Test func nothingToOfferWhenEverythingIsHidden() {
        let all = ["a": 1, "b": 2]
        #expect(ShelfContents.tuckInCandidates(order: ["a", "b"], modes: all, covered: [], excluded: []).isEmpty)
    }
}
