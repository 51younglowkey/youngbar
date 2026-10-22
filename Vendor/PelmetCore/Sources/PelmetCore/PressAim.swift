// PressAim.swift
// Where a press made from one display clicks an item (#26). A click opens
// the item's menu on the display whose bar it lands on, real button or
// stand-in, so a press made from a panel on another display clicks that
// bar's copy. The walk keeps the main display's copy of each item and
// records the others (`barCopies`), paired by full id. Locked by
// PressAimTests.

import CoreGraphics

public struct PressAim: Equatable, Sendable {
    public let frame: CGRect
    /// The copy on the press display's bar, not the main display's.
    public let onPressDisplay: Bool

    public init(frame: CGRect, onPressDisplay: Bool) {
        self.frame = frame
        self.onPressDisplay = onPressDisplay
    }

    /// The aim for the walk's item `id`, whose main copy is `main`: its own
    /// copy on `display`'s bar when the walk named one there, else `main`.
    /// By full id: an app's icons share one section key, and picking among
    /// them by key clicked Stats' or iStat's icons at random (review of
    /// cd1be1d). A copy the native « holds on that bar (it overlaps a
    /// neighbour there) is a phantom, never aimed at.
    public static func aim(id: ItemID, main: CGRect, display: CGRect?, copies: [ItemID: [CGRect]]) -> PressAim {
        guard let display,
              let own = copies[id].flatMap({ MenuBarGeometry.copy(onDisplay: display, among: $0) })
        else { return PressAim(frame: main, onPressDisplay: false) }
        let bar = copies.flatMap(\.value).filter { MenuBarGeometry.isInBand($0, ofDisplay: display) }
        let held = PlacementGeometry.overflowTrapped(bar)
        guard let index = bar.firstIndex(of: own), !held.contains(index) else {
            return PressAim(frame: main, onPressDisplay: false)
        }
        return PressAim(frame: own, onPressDisplay: true)
    }

    /// The press display's bar lists icons in this walk: only then is its
    /// copy worth waiting for. A display that draws no bar (Displays have
    /// separate Spaces off) never gets one.
    public static func barListed(on display: CGRect, copies: [ItemID: [CGRect]]) -> Bool {
        copies.values.contains { $0.contains { MenuBarGeometry.isInBand($0, ofDisplay: display) } }
    }

    /// Two reads in a row settle the aim when they agree within
    /// `tolerance` and came from the same bar: a stand-in mid-swap reads as
    /// missing for a walk, and a read of the main copy beside one of the
    /// display's is no agreement. With `awaitingDisplay` (the press
    /// display's bar is listed) a read of the main copy never settles: the
    /// caller waits for the display's copy until its cap, then the last
    /// read stands.
    public static func settles(_ previous: PressAim?, _ current: PressAim, tolerance: CGFloat, awaitingDisplay: Bool) -> Bool {
        guard let previous, previous.onPressDisplay == current.onPressDisplay else { return false }
        if awaitingDisplay, !current.onPressDisplay { return false }
        return abs(previous.frame.midX - current.frame.midX) <= tolerance
            && abs(previous.frame.midY - current.frame.midY) <= tolerance
    }
}
