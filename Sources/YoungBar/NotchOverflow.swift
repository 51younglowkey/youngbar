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
    /// for the display that holds YoungBar's control; nil without a notch.
    var notchVisibleMinX: CGFloat? {
        guard let screen = controlPanel?.screen ?? NSScreen.screens.first,
              screen.safeAreaInsets.top > 0,
              let right = screen.auxiliaryTopRightArea else { return nil }
        return right.minX
    }

    /// Every item on the control's bar that is out of sight, YoungBar's
    /// own status item included (the control must not follow it).
    func outOfSightKeys(_ snapshot: EngineSnapshot) -> Set<String> {
        guard let screen = controlPanel?.screen ?? NSScreen.screens.first else { return [] }
        var frames: [String: CGRect?] = [:]
        for item in snapshot.items {
            // Only this display's bar: a copy on a side display is visible.
            if let frame = item.frame, frame.midX < screen.frame.minX || frame.midX > screen.frame.maxX { continue }
            frames[item.id.sectionKey.rawValue] = item.frame
        }
        return Overflow.keys(frames: frames, visibleMinX: notchVisibleMinX)
    }

    /// The strip's share: items set to Show that the user can't reach.
    func computeOverflow(_ hidden: Set<String>) -> Set<String> {
        guard options[.notchOverflow] != 0 else { return [] }
        return hidden.filter { key in
            guard let item = catalog[key], (modes[key] ?? 0) == 0 else { return false }
            return item.id.bundleID != Bundle.main.bundleIdentifier
                && MenuBarPolicy.isSectionManageable(item.id)
                && !MenuBarPolicy.isPinnedSystemItem(item.id)
        }
    }

    /// After a display is added, removed or rearranged, the control may be
    /// left on a screen that no longer exists or off the bar: put it back
    /// beside the status item.
    func reinstallControlIfNeeded() {
        guard let panel = controlPanel else { return }
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(panel.frame) }
        guard !onScreen || panel.screen == nil else { return }
        closeShelf()
        panel.orderOut(nil)
        controlPanel = nil
        controlButton = nil
        Task {
            await installControlPanelWhenReady()
            await refresh()
        }
    }
}
