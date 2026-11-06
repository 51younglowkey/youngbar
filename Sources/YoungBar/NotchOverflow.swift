// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import PelmetCore
import PelmetEngine
import YoungBarCore

/// When the bar is full, macOS 27 moves the icons that don't fit into the
/// menu of a « at the bar's left end (on a notched display, right of the
/// notch). Those icons join the strip, without changing their saved mode,
/// so they leave it by themselves once there is room again.
extension BarApp {
    /// The left edge of the bar right of the notch, in global coordinates,
    /// for the display the strip hangs from; nil without a notch.
    var notchVisibleMinX: CGFloat? {
        anchorScreen.flatMap { barDisplay(for: $0).visibleMinX }
    }

    /// Every item that is out of sight on `screen`'s bar (the strip's display
    /// by default), YoungBar's own status item included. Each bar has its own
    /// room: what didn't fit on a notched built-in can be plain to see on a
    /// wide external display.
    func outOfSightKeys(_ snapshot: EngineSnapshot, on screen: NSScreen? = nil) -> Set<String> {
        guard let screen = screen ?? anchorScreen else { return [] }
        let display = barDisplay(for: screen)
        return ControlLayout.outOfSight(barIcons(snapshot, on: display), on: display)
    }

    /// The strip's share: items set to Show that the user can't reach.
    func computeOverflow(_ hidden: Set<String>) -> Set<String> {
        return hidden.filter { key in
            guard let item = catalog[key], (modes[key] ?? 0) == 0 else { return false }
            return item.id.bundleID != Bundle.main.bundleIdentifier
                && MenuBarPolicy.isSectionManageable(item.id)
                && !MenuBarPolicy.isPinnedSystemItem(item.id)
        }
    }

    /// Displays were added, removed or rearranged. Don't wait for the next
    /// walk: every ••• goes to its own bar now, and the walks that follow line
    /// them up with the icons.
    func displaysChanged() {
        guard !controlSlots.isEmpty else { return }
        syncControlPanels()
    }
}
