// DisplayCrossing.swift
// What the pointer arriving on a display asks of the bar, by that display's
// behavior (Settings › Displays). Pure: `MenuBarBandMonitor` reads the
// pointer, the settings and the rehide machine, and performs the action.

import Foundation

public enum DisplayCrossing {
    public enum Action: Equatable, Sendable {
        case none
        /// An "always show all" display: reveal Hidden for it.
        case reveal
        /// A collapsing display with the bar out: arm the countdown, never an
        /// instant conceal (one here flashed the bar open-shut when the
        /// pointer crossed displays right after a hover reveal).
        case leaveBand
    }

    /// `previous` is the display the pointer was last seen on (nil before the
    /// first sighting), `current` the one it is on now; `behavior` is
    /// `current`'s. `launched`: the launch applied its own baseline for the
    /// display under the pointer (`AppState.launchBaselineApplied`).
    ///
    /// The first sighting on an "always show all" display reveals, as a
    /// crossing would, once the launch is done: as a baseline it revealed
    /// nothing until the pointer crossed back (live test, 2026-10-13, after
    /// the 20:09 launch). Not before: the monitor starts ahead of the launch,
    /// whose conceal the reveal must follow, and the launch's baseline reads
    /// the pointer where it is by then. On a collapsing display the first
    /// sighting stays a baseline: the launch concealed already, and arming
    /// the countdown there concealed the bar on the first move after a
    /// reveal.
    public static func action(
        from previous: String?, to current: String?, behavior: DisplayBehavior, launched: Bool, revealed: Bool
    ) -> Action {
        guard current != previous else { return .none }
        let crossed = previous != nil
        switch behavior {
        case .alwaysShowAll:
            return crossed || launched ? .reveal : .none
        case .collapse:
            return crossed && revealed ? .leaveBand : .none
        }
    }
}
