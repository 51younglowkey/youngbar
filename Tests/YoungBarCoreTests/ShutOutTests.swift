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

    @Test func anAppOutsideApplicationsIsFixedWhileAnotherIconIsConcealed() {
        let outside: Set = ["bundle:mine", "bundle:downloaded", "bundle:gone"]
        let listed: Set = ["bundle:mine", "bundle:downloaded", "bundle:installed", "bundle:found", "wifi"]
        // Concealed like any other, or set to Show and still in the walk
        // (hiding just took effect): fixed from the start, with the one
        // found out the slow way.
        #expect(ShutOut.fixed(shutOut: ["bundle:found"], outside: outside, listed: listed,
                              walked: ["wifi", "bundle:downloaded"], concealed: ["bundle:mine", "bundle:installed"],
                              hidden: ["bundle:mine", "bundle:installed"])
                == ["bundle:found", "bundle:mine", "bundle:downloaded"])
        // A concealed system icon counts too; an app that isn't running doesn't.
        #expect(ShutOut.fixed(shutOut: [], outside: outside, listed: listed, walked: ["bundle:installed"],
                              concealed: ["wifi"], hidden: ["wifi"]) == ["bundle:mine", "bundle:downloaded"])
        // The only other hidden icon is out for a moment (a press): still fixed.
        #expect(ShutOut.fixed(shutOut: [], outside: outside, listed: listed, walked: ["bundle:installed", "wifi"],
                              concealed: ["bundle:mine"], hidden: ["bundle:mine", "wifi"])
                == ["bundle:mine", "bundle:downloaded"])
    }

    @Test func anAppOutsideApplicationsOnTheBarIsARowLikeAnyOther() {
        let outside: Set = ["bundle:mine", "bundle:downloaded"]
        let listed: Set = ["bundle:mine", "bundle:downloaded", "bundle:installed", "wifi"]
        // Nothing hidden.
        #expect(ShutOut.fixed(shutOut: [], outside: outside, listed: listed, walked: listed, concealed: [],
                              hidden: ["bundle:quit"]).isEmpty)
        // "Show all": set to Hide, nothing concealed, everything walked.
        #expect(ShutOut.fixed(shutOut: [], outside: outside, listed: listed, walked: listed, concealed: [],
                              hidden: ["bundle:mine", "bundle:installed"]).isEmpty)
    }

    @Test func onlyAppsOutsideApplicationsHiddenKeepTheirModes() {
        let outside: Set = ["bundle:mine", "bundle:downloaded"]
        let listed: Set = ["bundle:mine", "bundle:downloaded", "bundle:installed"]
        // The hidden one is the only reason anything is off the bar: it
        // needs its row to be set back. The other is shut out by it.
        #expect(ShutOut.fixed(shutOut: [], outside: outside, listed: listed, walked: ["bundle:installed"],
                              concealed: ["bundle:mine"], hidden: ["bundle:mine"]) == ["bundle:downloaded"])
        // Found out before its location was read, then set to Hide: the same.
        #expect(ShutOut.fixed(shutOut: ["bundle:mine"], outside: outside, listed: listed,
                              walked: ["bundle:installed", "bundle:downloaded"], concealed: [],
                              hidden: ["bundle:mine"]).isEmpty)
        // Both hidden: both keep a mode.
        #expect(ShutOut.fixed(shutOut: [], outside: outside, listed: listed, walked: ["bundle:installed"],
                              concealed: ["bundle:mine", "bundle:downloaded"],
                              hidden: ["bundle:mine", "bundle:downloaded"]).isEmpty)
    }

    @Test func anInstalledAppMissingFromTheBarIsParkedNotShutOut() {
        let found: Set<String> = ["bundle:timer", "bundle:chat", "bundle:old"]
        let parked = ShutOut.parked(found: found, bundles: bundles,
                                    inApplications: ["timer": true, "chat": false])
        // In /Applications: landed. Elsewhere, or not looked at yet: shut out as before.
        #expect(parked == ["bundle:timer"])
    }

    @Test func onlyAppsInApplicationsAreShownWhileOthersHide() {
        #expect(ShutOut.isInApplications(path: "/Applications/Tendedero.app"))
        #expect(ShutOut.isInApplications(path: "/Applications/Utilities/Tool.app"))
        #expect(ShutOut.isInApplications(path: "/Applications/Tendedero.app/"))
        #expect(!ShutOut.isInApplications(path: "/Users/me/Applications/Mustop.app"))
        #expect(!ShutOut.isInApplications(path: "/Users/me/Downloads/Tendedero.app"))
        #expect(!ShutOut.isInApplications(path: "/Volumes/Tendedero/Tendedero.app"))
        #expect(!ShutOut.isInApplications(path: "/private/var/folders/x/AppTranslocation/y/d/Tendedero.app"))
        #expect(!ShutOut.isInApplications(path: "/ApplicationsOld/Tendedero.app"))
        #expect(!ShutOut.isInApplications(path: "/Applications"))
    }

    @Test func adoptionWindowsPerAppAreLimited() {
        var adoptions = ShutOut.Adoptions()
        let answers = [(0.0, "timer"), (60, "timer"), (120, "timer"), (180, "timer"), (180, "chat"),
                       (601, "timer"), (602, "timer")].map { adoptions.allow($0.1, now: $0.0) }
        // Three per app in ten minutes; another app has its own count; ten
        // minutes after the first, one more.
        #expect(answers == [true, true, true, false, true, true, false])
    }
}
