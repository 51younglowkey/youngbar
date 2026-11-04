// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ApplicationServices
import PelmetCore
import PelmetEngine
import YoungBarCore

/// Keeping the engine in step with what happens outside YoungBar. The
/// engine only converges when asked; without these, apps opened after
/// YoungBar started could vanish and a dropped assertion stayed dropped.
///
/// - The running apps: the engine reads them once unless told. An app it
///   doesn't know is never allowed, so its icon was hidden by omission, and
///   one that quit while hidden stayed in the strip as a dead tile.
/// - Parked items: while any hide assertion holds, macOS parks a newly
///   registered menu-bar item off screen, out of every walk. The engine
///   adopts it in a short window without the assertion (the hidden icons
///   show for a moment); only an app that really has an item gets one.
/// - Events: a torn-down assertion or failed activation is only fixed by the
///   next converge, so the layout is re-applied (at most every 10 s).
extension BarApp {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// An app just started.
    func appLaunched(pid: pid_t, bundle: String?) {
        guard started, !quitting, pid > 0, let bundle, bundle != Bundle.main.bundleIdentifier else { return }
        Task {
            await engine.setRunningBundles(runningBundleIDs())
            // Most apps put up their item while launching; give them a few seconds.
            var hasItem = false
            for _ in 0..<12 where !hasItem {
                try? await Task.sleep(for: .milliseconds(500))
                hasItem = await Task.detached { BarApp.hasStatusItem(pid: pid) }.value
            }
            guard hasItem, !quitting else { return }
            let onBar = await engine.freshSnapshot().items.contains { $0.id.bundleID == bundle }
            guard !onBar, await engine.holdsAssertion else {
                // On the bar already (nothing was hidden yet): apply the
                // layout, so a Hidden app's icon goes again.
                await reapplyModel()
                await refresh()
                return
            }
            for _ in 0..<50 where busy { try? await Task.sleep(for: .milliseconds(100)) }
            guard !busy, !quitting else { return }
            busy = true
            let adopted = await engine.openAdoptionWindow(for: bundle)
            busy = false
            NSLog("YoungBar: \(bundle) \(adopted ? "adopted" : "not seen") after launch")
            await refresh()
        }
    }

    /// An app quit: its concealed items stop counting (no dead tiles).
    func appTerminated() {
        guard started, !quitting else { return }
        Task {
            await engine.setRunningBundles(runningBundleIDs())
            await reapplyModel()
            await refresh()
        }
    }

    /// Whether the app has a menu-bar item in its own accessibility tree,
    /// where it shows even while macOS keeps it off the bar. Off the main
    /// actor: a just-launched app can be slow to answer.
    nonisolated static func hasStatusItem(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let extras, CFGetTypeID(extras) == AXUIElementGetTypeID() else { return false }
        let bar = extras as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, 0.3)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success else { return false }
        return ((children as? [AXUIElement])?.count ?? 0) > 0
    }

    /// Reads the engine's events for the life of the app (reading them also
    /// keeps the stream's buffer from growing).
    func watchEngineEvents() {
        let events = engine.events
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .assertionTornDown, .convergeFailed:
                    self.scheduleReapply(after: 1)
                case .itemsChanged:
                    // An app's item came or went: its mode applies to it.
                    self.scheduleReapply(after: 2)
                default:
                    break
                }
            }
        }
    }

    func scheduleReapply(after delay: TimeInterval) {
        guard started, !quitting, !reapplyScheduled else { return }
        // Not more often than every 10 s: an item whose identity changes
        // with its title could otherwise ask on every walk.
        let wait = max(delay, 10 - Date().timeIntervalSince(lastReapplyAt))
        reapplyScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(wait))
            reapplyScheduled = false
            lastReapplyAt = Date()
            await reapplyModel()
        }
    }

    /// Whether this user's session is on screen and unlocked. Walks of a bar
    /// nobody can see are skipped (a locked night was thousands of them).
    var sessionIsOnScreen: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        let onConsole = info["kCGSSessionOnConsoleKey"] as? Bool ?? true
        let locked = info["CGSSessionScreenIsLocked"] as? Bool ?? false
        return onConsole && !locked
    }
}
