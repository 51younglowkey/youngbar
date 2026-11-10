// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import YoungBarCore

/// The •••'s place on every kind of Mac the author doesn't have: these cases
/// are made up from display sizes and icon counts, not read from real machines.
@Suite struct ControlLayoutTests {
    /// The author's built-in display, and the external one beside it.
    static let builtIn = BarDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), barHeight: 40, visibleMinX: 1010)
    static let side = BarDisplay(frame: CGRect(x: 1800, y: -424, width: 1920, height: 1080), barHeight: 31)
    static let above = BarDisplay(frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), barHeight: 31)
    static let below = BarDisplay(frame: CGRect(x: 0, y: 1169, width: 1920, height: 1080), barHeight: 31)
    static let left = BarDisplay(frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440), barHeight: 31)

    /// `count` icons laid out from the right end of `display`'s bar.
    static func row(_ count: Int, on display: BarDisplay, width: CGFloat = 32, gap: CGFloat = 6) -> [BarIcon] {
        (0..<count).map { index in
            let right = display.frame.maxX - 20 - CGFloat(index) * (width + gap)
            return BarIcon(key: "icon\(index)",
                           frame: CGRect(x: right - width, y: display.frame.minY, width: width, height: display.barHeight))
        }
    }

    static func control(at x: CGFloat, y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 34, height: 24) }

    // MARK: - Left beside the icons

    @Test func sitsBesideTheFirstIcon() {
        let icons = Self.row(9, on: Self.builtIn)
        let spot = ControlLayout.spot(icons: icons, on: Self.builtIn, current: Self.control(at: 100, y: 0), width: 34)
        let first = icons.last?.frame?.minX ?? 0
        #expect(spot.minX == first - 34 - ControlLayout.gapToIcon)
        #expect(spot.reason == .beside(key: "icon8", iconMinX: first))
    }

    /// The bug behind "••• overlaps the icons": icons past the middle of a
    /// narrow display were ignored, so the ••• landed among them.
    @Test func manyIconsOnANarrowDisplayDontOverlapIt() {
        let display = BarDisplay(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), barHeight: 24)
        let icons = Self.row(22, on: display)
        let spot = ControlLayout.spot(icons: icons, on: display, current: Self.control(at: 900, y: 0), width: 34)
        let frames = icons.compactMap(\.frame)
        let control = CGRect(x: spot.minX, y: 0, width: spot.width, height: 24)
        #expect(frames.allSatisfy { !$0.intersects(control) })
        #expect(spot.minX < display.frame.midX)
    }

    @Test func aParkedSlotFarLeftIsNotFollowed() {
        let parked = BarIcon(key: "parked", frame: CGRect(x: 7, y: 0, width: 32, height: 40))
        let display = BarDisplay(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), barHeight: 31)
        let row = Self.row(5, on: display)
        let spot = ControlLayout.spot(icons: row + [parked], on: display, current: Self.control(at: 1500, y: 0), width: 34)
        #expect(spot.reason == .beside(key: "icon4", iconMinX: row.last?.frame?.minX ?? 0))
    }

    @Test func staysRightOfTheNotch() {
        // More icons than fit right of the notch: the ones under it are out of sight.
        let icons = Self.row(30, on: Self.builtIn)
        let spot = ControlLayout.spot(icons: icons, on: Self.builtIn, current: Self.control(at: 1200, y: 0), width: 34)
        #expect(spot.minX >= 1010)
    }

    @Test func aFullBarPutsItInThePile() {
        // Own item and two others held by the « at x≈1100; the bar's icons right of it.
        let held = [
            BarIcon(key: "own", frame: CGRect(x: 1100, y: 0, width: 32, height: 40), isOwn: true),
            BarIcon(key: "a", frame: CGRect(x: 1106, y: 0, width: 32, height: 40)),
            BarIcon(key: "b", frame: CGRect(x: 1112, y: 0, width: 32, height: 40)),
        ]
        let rest = (0..<10).map { index in
            BarIcon(key: "icon\(index)", frame: CGRect(x: 1160 + CGFloat(index) * 38, y: 0, width: 32, height: 40))
        }
        let spot = ControlLayout.spot(icons: held + rest, on: Self.builtIn, current: Self.control(at: 1200, y: 0), width: 34)
        #expect(spot.width == ControlLayout.narrowWidth)
        #expect(spot.minX == 1100)
        #expect(spot.reason == .inPile(key: "icon0", iconMinX: 1160))
    }

    // MARK: - Always on its own bar

    /// The report: the ••• at the bottom right of the screen. x kept following
    /// the icons while y stayed wherever macOS had moved it.
    @Test func comesBackToTheBarFromAnywhere() {
        let icons = Self.row(9, on: Self.builtIn)
        for y in [306, 1138, 0, -500, 3000] as [CGFloat] {
            let spot = ControlLayout.spot(icons: icons, on: Self.builtIn, current: Self.control(at: 173, y: y), width: 34)
            #expect(abs(spot.midY - Self.builtIn.barMidY) <= 1, "from y \(y)")
        }
    }

    @Test func withNoIconItStillGoesToTheBar() {
        let spot = ControlLayout.spot(icons: [], on: Self.builtIn, current: Self.control(at: 1300, y: 900), width: 34)
        #expect(spot.midY == Self.builtIn.barMidY)
        #expect(spot.minX == 1300)
        #expect(spot.reason == .noIcon)
    }

    @Test func withNoIconAndOffTheDisplayItGoesToTheRightSide() {
        let spot = ControlLayout.spot(icons: [], on: Self.side, current: Self.control(at: 100, y: 900), width: 34)
        #expect(spot.minX == Self.side.frame.maxX - 34 - ControlLayout.fallbackRightInset)
        #expect(spot.midY == Self.side.barMidY)
    }

    /// Every arrangement, every icon count: the spot is in that display's bar
    /// and clear of its icons.
    @Test(arguments: [Self.builtIn, Self.side, Self.above, Self.below, Self.left,
                      BarDisplay(frame: CGRect(x: 0, y: 0, width: 1080, height: 1920), barHeight: 31),
                      BarDisplay(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), barHeight: 37, visibleMinX: 850),
                      BarDisplay(frame: CGRect(x: 0, y: 0, width: 3840, height: 2160), barHeight: 24)])
    func alwaysInTheBarAndClearOfTheIcons(display: BarDisplay) {
        for count in [0, 1, 3, 8, 15, 25, 40] {
            let icons = Self.row(count, on: display)
            let hidden = ControlLayout.outOfSight(icons, on: display)
            let spot = ControlLayout.spot(icons: icons, on: display, current: Self.control(at: -9000, y: 9000), width: 34)
            let control = CGRect(x: spot.minX, y: spot.midY - 12, width: spot.width, height: 24)
            #expect(ControlLayout.controlIsInBar(control, of: display), "\(count) icons")
            #expect(spot.minX >= display.leftLimit, "\(count) icons")
            #expect(control.maxX <= display.frame.maxX, "\(count) icons")
            let seen = icons.filter { !hidden.contains($0.key) }.compactMap(\.frame)
            if spot.atLeftLimit == false {
                #expect(seen.allSatisfy { !$0.intersects(control) }, "\(count) icons on \(display.frame)")
            }
        }
    }

    // MARK: - Displays above, below and beside

    /// A display above shares every x with the built-in: x alone took its
    /// copies for the built-in's icons.
    @Test func aDisplayAboveDoesntLendItsIcons() {
        let own = Self.row(4, on: Self.above)
        #expect(ControlLayout.leadingIcon(own, on: Self.builtIn, outOfSight: []) == nil)
        let spot = ControlLayout.spot(icons: own, on: Self.builtIn, current: Self.control(at: 1300, y: 0), width: 34)
        #expect(spot.reason == .noIcon)
        #expect(spot.midY == Self.builtIn.barMidY)
    }

    @Test func eachBarGoesByItsOwnCopies() {
        let main = Self.row(5, on: Self.builtIn)
        let other = Self.row(5, on: Self.side)
        let onMain = ControlLayout.spot(icons: main, on: Self.builtIn, current: Self.control(at: 0, y: 0), width: 34)
        let onSide = ControlLayout.spot(icons: other, on: Self.side, current: Self.control(at: 0, y: 0), width: 34)
        #expect(onMain.minX < Self.builtIn.frame.maxX)
        #expect(onSide.minX >= Self.side.frame.minX)
        #expect(onSide.midY == other[0].frame?.midY)
        #expect(onMain.midY == main[0].frame?.midY)
    }

    @Test func anIconOnlyOnAnotherBarIsOutOfSightHere() {
        let here = Self.row(3, on: Self.builtIn)
        let elsewhere = BarIcon(key: "only-there", frame: nil, drawnElsewhere: true)
        #expect(ControlLayout.outOfSight(here + [elsewhere], on: Self.builtIn) == ["only-there"])
    }

    /// Full screen or auto-hide: nothing is on the bar for now. Calling every
    /// icon out of sight would fill the strip with all of them.
    @Test func aHiddenBarDoesntMakeEverythingOutOfSight() {
        let hiddenBar = Self.row(6, on: Self.builtIn).map { icon in
            BarIcon(key: icon.key, frame: icon.frame?.offsetBy(dx: 0, dy: -30))
        }
        #expect(ControlLayout.outOfSight(hiddenBar, on: Self.builtIn).isEmpty)
        let elsewhere = Self.row(6, on: Self.builtIn).map { BarIcon(key: $0.key, frame: nil, drawnElsewhere: true) }
        #expect(ControlLayout.outOfSight(elsewhere, on: Self.builtIn).isEmpty)
    }

    @Test func anItemDrawnNowhereIsStillOutOfSight() {
        let nowhere = BarIcon(key: "nowhere", frame: nil)
        #expect(ControlLayout.outOfSight([nowhere], on: Self.builtIn) == ["nowhere"])
    }

    @Test func twoIconsOfOneAppCountOnce() {
        let frame = CGRect(x: 1400, y: 0, width: 32, height: 40)
        let icons = [BarIcon(key: "app", frame: frame), BarIcon(key: "app", frame: nil, drawnElsewhere: true)]
        #expect(ControlLayout.outOfSight(icons, on: Self.builtIn).isEmpty)
    }

    // MARK: - Pressing in place

    @Test func aSlotOnTheStripsDisplayNearTheControlCanBePressed() {
        let control = Self.control(at: 1300, y: 8)
        #expect(ControlLayout.slotIsNearControl(CGPoint(x: 1250, y: 0), control: control, on: Self.builtIn))
    }

    @Test func aSlotParkedFarAwayIsNot() {
        let control = Self.control(at: 1300, y: 8)
        #expect(!ControlLayout.slotIsNearControl(CGPoint(x: 7, y: 0), control: control, on: Self.builtIn))
        #expect(!ControlLayout.slotIsNearControl(CGPoint(x: 700, y: 0), control: control, on: Self.builtIn))
    }

    /// Used to need the slot in the right half of the display: a narrow bar's
    /// icons there got a flash of revealed icons for nothing.
    @Test func aSlotLeftOfTheMiddleOfANarrowDisplayCanBePressed() {
        let display = BarDisplay(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), barHeight: 24)
        let control = Self.control(at: 500, y: 0)
        #expect(ControlLayout.slotIsNearControl(CGPoint(x: 480, y: 0), control: control, on: display))
    }

    @Test func aSlotOnAnotherDisplayIsNot() {
        let control = Self.control(at: 3000, y: -424)
        #expect(!ControlLayout.slotIsNearControl(CGPoint(x: 1300, y: 0), control: control, on: Self.side))
        #expect(ControlLayout.slotIsNearControl(CGPoint(x: 2900, y: -424), control: control, on: Self.side))
    }
}

/// YoungBar's own slot drawn inside the row of icons (user report, 0.1.7 on
/// macOS 27.0.1: ♥ on one side of an icon, a blank slot on the other).
@Suite struct OwnSlotTests {
    static let display = BarDisplay(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), barHeight: 37, visibleMinX: 820)
    // A planet icon at 1300, then Wi-Fi.
    static let planet = BarIcon(key: "planet", frame: CGRect(x: 1300, y: 0, width: 38, height: 37))
    static let wifi = BarIcon(key: "wifi", frame: CGRect(x: 1390, y: 0, width: 22, height: 37))

    static func own(_ minX: CGFloat, width: CGFloat = 38, key: String = "own") -> BarIcon {
        BarIcon(key: key, frame: CGRect(x: minX, y: 0, width: width, height: 37), isOwn: true)
    }

    static func spot(_ icons: [BarIcon]) -> ControlSpot {
        ControlLayout.spot(icons: icons, on: display, current: CGRect(x: 1000, y: 6, width: 34, height: 24), width: 34)
    }

    @Test func noSlotFollowsTheFirstIcon() {
        let spot = Self.spot([Self.planet, Self.wifi])
        #expect(spot.minX == 1260)
        #expect(spot.reason == .beside(key: "planet", iconMinX: 1300))
    }

    /// The usual case, and the one while hiding: the slot is left of the icons.
    @Test func slotLeftOfEveryIconFollowsTheFirstIcon() {
        let spot = Self.spot([Self.own(1220), Self.planet, Self.wifi])
        #expect(spot.minX == 1260)
        #expect(spot.reason == .beside(key: "planet", iconMinX: 1300))
    }

    @Test func slotAfterAnotherIconTakesTheSlot() {
        let spot = Self.spot([Self.planet, Self.own(1345), Self.wifi])
        #expect(spot.minX == 1347)
        #expect(spot.reason == .onOwnSlot(key: "planet", iconMinX: 1300))
    }

    /// The walk lists the own item twice; a frameless copy changes nothing.
    @Test func slotListedTwiceStillTakesTheSlot() {
        let spot = Self.spot([Self.planet, Self.own(1345), BarIcon(key: "own2", frame: nil, isOwn: true), Self.wifi])
        #expect(spot.reason == .onOwnSlot(key: "planet", iconMinX: 1300))
    }

    /// Under another icon it reads as the « pile, never as a slot to sit on.
    @Test func slotUnderAnIconIsIgnored() {
        if case .onOwnSlot = Self.spot([Self.planet, Self.own(1305), Self.wifi]).reason { Issue.record("sat on a covered slot") }
    }

    @Test func zeroWidthSlotIsIgnored() {
        #expect(Self.spot([Self.planet, Self.own(1350, width: 0), Self.wifi]).reason == .beside(key: "planet", iconMinX: 1300))
    }

    @Test func slotRightOfEveryIconIsIgnored() {
        #expect(Self.spot([Self.planet, Self.wifi, Self.own(1440)]).reason == .beside(key: "planet", iconMinX: 1300))
    }

    /// Two entries for the own item on one spot are not the « pile.
    @Test func ownItemListedTwiceIsNotAPile() {
        let icons = [Self.planet, Self.own(1345), Self.own(1345, key: "own2"), Self.wifi]
        #expect(ControlLayout.outOfSight(icons, on: Self.display).isEmpty)
        #expect(Self.spot(icons).reason == .onOwnSlot(key: "planet", iconMinX: 1300))
    }
}

/// An app with several untitled icons walks as one id (Stats with a module
/// per icon): every place it has counts, or the ••• lands on one of them.
@Suite struct SameIDIconTests {
    static let display = OwnSlotTests.display
    static let wechat = BarIcon(key: "wechat", frame: CGRect(x: 1316, y: 0, width: 40, height: 37))

    @Test func repeatsCollapse() {
        let gpu = CGRect(x: 1151, y: 0, width: 33, height: 37)
        let disk = CGRect(x: 1198, y: 0, width: 112, height: 37)
        #expect(ControlLayout.distinctFrames([gpu, disk, gpu, disk.offsetBy(dx: 0.5, dy: 0)], besides: gpu) == [disk])
        #expect(ControlLayout.distinctFrames([gpu], besides: gpu).isEmpty)
    }

    /// The report: the snapshot kept the GPU icon, so the disk icon was
    /// missing and the ••• went beside WeChat, on top of it.
    @Test func everyIconOfTheAppIsFollowed() {
        let gpu = BarIcon(key: "stats", frame: CGRect(x: 1151, y: 0, width: 33, height: 37))
        let disk = BarIcon(key: "stats#1", frame: CGRect(x: 1198, y: 0, width: 112, height: 37))
        let spot = ControlLayout.spot(icons: [gpu, disk, Self.wechat], on: Self.display,
                                      current: CGRect(x: 1000, y: 6, width: 34, height: 24), width: 34)
        #expect(spot.reason == .beside(key: "stats", iconMinX: 1151))
        let control = CGRect(x: spot.minX, y: 0, width: spot.width, height: 37)
        #expect(![gpu, disk, Self.wechat].contains { $0.frame?.intersects(control) ?? false })
    }
}
