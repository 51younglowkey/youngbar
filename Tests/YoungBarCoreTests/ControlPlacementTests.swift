// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import YoungBarCore

@Suite struct ControlPlacementTests {
    typealias Span = ControlPlacement.Span

    // A planet icon at 1300, YoungBar's slot right of it, then Wi-Fi.
    let planet = Span(minX: 1300, maxX: 1338)
    let wifi = Span(minX: 1390, maxX: 1412)

    @Test func noSlotFollowsTheFirstIcon() {
        let place = ControlPlacement.x(width: 34, own: nil, icons: [planet, wifi], floor: 820)
        #expect(place?.x == 1260)
        #expect(place?.onOwnSlot == false)
    }

    @Test func slotLeftOfEveryIconFollowsTheFirstIcon() {
        // The usual case, and the one while hiding: the slot is leftmost or
        // not drawn, and its frame lies left of the icons.
        let own = Span(minX: 1070, maxX: 1108)
        let place = ControlPlacement.x(width: 34, own: own, icons: [planet, wifi], floor: 820)
        #expect(place?.x == 1260)
        #expect(place?.onOwnSlot == false)
    }

    @Test func slotAfterAnotherIconTakesTheSlot() {
        // The report: ♥ left of the planet, a blank slot right of it.
        let own = Span(minX: 1345, maxX: 1383)
        let place = ControlPlacement.x(width: 34, own: own, icons: [planet, wifi], floor: 820)
        #expect(place?.x == 1347)
        #expect(place?.onOwnSlot == true)
    }

    @Test func slotUnderAnIconIsIgnored() {
        let own = Span(minX: 1305, maxX: 1343)
        #expect(ControlPlacement.slotInRow(own: own, icons: [planet, wifi]) == nil)
        #expect(ControlPlacement.x(width: 34, own: own, icons: [planet, wifi], floor: 820)?.onOwnSlot == false)
    }

    @Test func zeroWidthSlotIsIgnored() {
        #expect(ControlPlacement.slotInRow(own: Span(minX: 1350, maxX: 1350), icons: [planet]) == nil)
    }

    @Test func floorStillHolds() {
        let place = ControlPlacement.x(width: 34, own: nil, icons: [Span(minX: 830, maxX: 860)], floor: 820)
        #expect(place?.x == 820)
    }

    @Test func nothingToGoBy() {
        #expect(ControlPlacement.x(width: 34, own: Span(minX: 1345, maxX: 1383), icons: [], floor: 820) == nil)
    }
}
