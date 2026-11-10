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

    @Test func anUnsignedAppIsFixedWhileAnotherIconIsConcealed() {
        let unsigned: Set = ["bundle:mine", "bundle:adhoc", "bundle:gone"]
        let listed: Set = ["bundle:mine", "bundle:adhoc", "bundle:signed", "bundle:found", "wifi"]
        // Concealed like any other, or set to Show and still in the walk
        // (hiding just took effect): fixed from the start, with the one
        // found out the slow way.
        #expect(ShutOut.fixed(shutOut: ["bundle:found"], unsigned: unsigned, listed: listed,
                              walked: ["wifi", "bundle:adhoc"], concealed: ["bundle:mine", "bundle:signed"],
                              hidden: ["bundle:mine", "bundle:signed"])
                == ["bundle:found", "bundle:mine", "bundle:adhoc"])
        // A concealed system icon counts too; an app that isn't running doesn't.
        #expect(ShutOut.fixed(shutOut: [], unsigned: unsigned, listed: listed, walked: ["bundle:signed"],
                              concealed: ["wifi"], hidden: ["wifi"]) == ["bundle:mine", "bundle:adhoc"])
        // The only other hidden icon is out for a moment (a press): still fixed.
        #expect(ShutOut.fixed(shutOut: [], unsigned: unsigned, listed: listed, walked: ["bundle:signed", "wifi"],
                              concealed: ["bundle:mine"], hidden: ["bundle:mine", "wifi"])
                == ["bundle:mine", "bundle:adhoc"])
    }

    @Test func anUnsignedAppOnTheBarIsARowLikeAnyOther() {
        let unsigned: Set = ["bundle:mine", "bundle:adhoc"]
        let listed: Set = ["bundle:mine", "bundle:adhoc", "bundle:signed", "wifi"]
        // Nothing hidden.
        #expect(ShutOut.fixed(shutOut: [], unsigned: unsigned, listed: listed, walked: listed, concealed: [],
                              hidden: ["bundle:quit"]).isEmpty)
        // "Show all": set to Hide, nothing concealed, everything walked.
        #expect(ShutOut.fixed(shutOut: [], unsigned: unsigned, listed: listed, walked: listed, concealed: [],
                              hidden: ["bundle:mine", "bundle:signed"]).isEmpty)
    }

    @Test func onlyUnsignedAppsHiddenKeepTheirModes() {
        let unsigned: Set = ["bundle:mine", "bundle:adhoc"]
        let listed: Set = ["bundle:mine", "bundle:adhoc", "bundle:signed"]
        // The hidden one is the only reason anything is off the bar: it
        // needs its row to be set back. The other is shut out by it.
        #expect(ShutOut.fixed(shutOut: [], unsigned: unsigned, listed: listed, walked: ["bundle:signed"],
                              concealed: ["bundle:mine"], hidden: ["bundle:mine"]) == ["bundle:adhoc"])
        // Found out before its signature was read, then set to Hide: the same.
        #expect(ShutOut.fixed(shutOut: ["bundle:mine"], unsigned: unsigned, listed: listed,
                              walked: ["bundle:signed", "bundle:adhoc"], concealed: [],
                              hidden: ["bundle:mine"]).isEmpty)
        // Both hidden: both keep a mode.
        #expect(ShutOut.fixed(shutOut: [], unsigned: unsigned, listed: listed, walked: ["bundle:signed"],
                              concealed: ["bundle:mine", "bundle:adhoc"],
                              hidden: ["bundle:mine", "bundle:adhoc"]).isEmpty)
    }
}
