// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Testing
@testable import YoungBarCore

@Suite struct ShutOutTests {
    let bundles = ["bundle:timer": "timer", "bundle:stats": "stats", "bundle:chat": "chat", "bundle:old": "old"]

    func suspects(modes: [String: Int] = [:], hidden: Set<String> = [], listed: Set<String> = ["bundle:stats"],
                  listedBundles: Set<String> = ["stats"], running: Set<String> = ["timer", "stats", "chat"]) -> Set<String> {
        ShutOut.suspects(bundles: bundles, modes: modes, hidden: hidden, listed: listed,
                         listedBundles: listedBundles, running: running)
    }

    @Test func showIconsOfRunningAppsThatNoWalkLists() {
        // "old" isn't running; "stats" is on the bar.
        #expect(suspects() == ["bundle:timer", "bundle:chat"])
    }

    @Test func hiddenIconsAreNotMissing() {
        #expect(suspects(modes: ["bundle:timer": 1, "bundle:chat": 2]) == [])
        #expect(suspects(hidden: ["bundle:timer"]) == ["bundle:chat"])
    }

    @Test func parkedOrConcealedCountsAsListed() {
        #expect(suspects(listed: ["bundle:stats", "bundle:chat"]) == ["bundle:timer"])
    }

    @Test func anAppListedUnderAnotherKeyIsNotMissing() {
        // Its icon is in the walk as "status:chat::…"; "bundle:chat" is an old key.
        #expect(suspects(listedBundles: ["stats", "chat"]) == ["bundle:timer"])
    }

    @Test func askedOnlyAfterStayingMissing() {
        var watch = ShutOut.Watch()
        #expect(watch.due(["a"], now: 0) == [])
        #expect(watch.due(["a"], now: 4) == [])
        #expect(watch.due(["a"], now: 8) == ["a"])
    }

    @Test func backOnTheBarStartsOver() {
        var watch = ShutOut.Watch()
        _ = watch.due(["a"], now: 0)
        _ = watch.due([], now: 4)
        #expect(watch.due(["a"], now: 8) == [])
        #expect(watch.due(["a"], now: 16) == ["a"])
    }

    @Test func anAppWithoutAnIconIsNotAskedOnEveryWalk() {
        var watch = ShutOut.Watch()
        _ = watch.due(["a"], now: 0)
        #expect(watch.due(["a"], now: 8) == ["a"])
        #expect(watch.due(["a"], now: 12) == [])
        #expect(watch.due(["a"], now: 67) == [])
        #expect(watch.due(["a"], now: 68) == ["a"])
    }

    @Test func anIconThatLeftEveryListStaysWhileItsAppRuns() {
        // "timer" was listed and no longer is; "old" quit; "stats" is still there.
        let lost = ShutOut.lost(previous: ["bundle:timer", "bundle:stats", "bundle:old", "status:x::y"],
                                listed: ["bundle:stats"], bundles: bundles, running: ["timer", "stats", "chat"])
        #expect(lost == ["bundle:timer"])
    }

    @Test func anIconListedAMomentAgoIsAskedSooner() {
        var watch = ShutOut.Watch()
        #expect(watch.due(["a", "b"], eager: ["a"], now: 0) == [])
        #expect(watch.due(["a", "b"], eager: ["a"], now: 2) == [])
        #expect(watch.due(["a", "b"], eager: ["a"], now: 3) == ["a"])
        #expect(watch.due(["a", "b"], eager: ["a"], now: 8) == ["b"])
    }
}
