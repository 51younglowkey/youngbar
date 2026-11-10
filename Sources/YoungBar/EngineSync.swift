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
///   one that quit while hidden stayed in the strip as a dead tile. Watched
///   through `runningApplications` (KVO), which also lists menu-bar-only
///   apps — the launch notification isn't posted for every one of them.
/// - Parked items: while any hide assertion holds, macOS parks a newly
///   registered menu-bar item off screen, out of every walk. The engine
///   adopts it in a short window without the assertion (hidden icons show
///   for a moment). Only for an app that really has an item and is set to
///   Show (or is new); a Hidden one stays listed through `parkedKeys` and is
///   adopted when it is first pressed.
/// - Events: a torn-down assertion or failed activation is only fixed by the
///   next converge, so the layout is re-applied — at most every 10 s, and
///   not again once the same layout failed three times in two minutes (an
///   icon macOS won't hide would otherwise re-swap the bar for good).
///
/// All of it is background work: it holds `syncing`, never `busy`.
extension BarApp {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func watchRunningApplications() {
        knownRunningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.runningApplicationsChanged() }
        }
    }

    func runningApplicationsChanged() {
        let apps = NSWorkspace.shared.runningApplications
        let current = Set(apps.map(\.processIdentifier))
        let launched = apps.filter { !knownRunningPIDs.contains($0.processIdentifier) }
        let quit = !knownRunningPIDs.subtracting(current).isEmpty
        knownRunningPIDs = current
        for app in launched { appLaunched(pid: app.processIdentifier, bundle: app.bundleIdentifier) }
        if quit { appTerminated() }
    }

    /// An app just started.
    func appLaunched(pid: pid_t, bundle: String?) {
        guard started, !quitting, pid > 0, let bundle, bundle != Bundle.main.bundleIdentifier else { return }
        Task {
            await engine.setRunningBundles(runningBundleIDs())
            // Apple's own items belong to the system agent, and an app whose
            // item never showed last time won't now: no window for them.
            guard !bundle.hasPrefix("com.apple."), !adoptionMissed.contains(bundle) else { return }
            // Most apps put up their item while launching; give them a few seconds.
            var hasItem = false
            for _ in 0..<12 where !hasItem {
                try? await Task.sleep(for: .milliseconds(500))
                hasItem = await Task.detached { BarApp.hasStatusItem(pid: pid) }.value
            }
            guard hasItem, !quitting else { return }
            // Set to Hidden (or hidden by "Hide all"): it is out of sight
            // anyway. It is adopted when the user first presses it in the
            // strip, so a relaunch doesn't flash every hidden icon.
            let keys = catalog.filter { $0.value.id.bundleID == bundle }.map(\.key)
            if !keys.isEmpty, keys.allSatisfy({ (modes[$0] ?? 0) > 0 || bulkHiddenKeys.contains($0) }) {
                // Parked, the item is in no engine snapshot: without this it
                // would be neither on the bar nor in the strip or Settings,
                // and nothing could press it.
                parkedKeys.formUnion(keys)
                await reapplyModel()
                await refresh()
                return
            }
            for _ in 0..<50 where busy || syncing { try? await Task.sleep(for: .milliseconds(100)) }
            guard !busy, !syncing, !quitting else { return }
            syncing = true
            defer { syncing = false }
            // Looked at only now, holding the flag: another app's window may
            // have landed this one already.
            let onBar = await engine.freshSnapshot().items.contains { $0.id.bundleID == bundle }
            guard !onBar, await engine.holdsAssertion else {
                // On the bar (nothing was hidden yet, or it landed): apply the
                // layout, so a Hidden app's icon goes again.
                await engine.setModel(currentModel())
                return
            }
            let adopted = await engine.openAdoptionWindow(for: bundle)
            if !adopted { adoptionMissed.insert(bundle) }
            NSLog("YoungBar: \(bundle) \(adopted ? "adopted" : "not seen") after launch")
            flight.note("\(bundle) \(adopted ? "adopted" : "not seen") after launch")
            // Adopted, and gone again once the icons are hidden: macOS shut
            // it out (`ShutOut`). A new app needs a key to be found.
            guard adopted else { return }
            try? await Task.sleep(for: .seconds(1))
            if !(await engine.freshSnapshot()).items.contains(where: { $0.id.bundleID == bundle }) {
                rememberUnlistedApp(bundle)
            }
        }
    }

    /// An app quit: its concealed items stop counting (no dead tiles).
    func appTerminated() {
        guard started, !quitting else { return }
        let running = runningBundleIDs()
        parkedKeys = parkedKeys.filter { key in
            catalog[key]?.id.bundleID.map(running.contains) ?? false
        }
        shutOutKeys = shutOutKeys.filter { key in
            catalog[key]?.id.bundleID.map(running.contains) ?? false
        }
        unlistedKeys = unlistedKeys.filter { key in
            catalog[key]?.id.bundleID.map(running.contains) ?? false
        }
        fixedKeys = fixedKeys.filter { key in
            catalog[key]?.id.bundleID.map(running.contains) ?? false
        }
        signatures = signatures.filter { running.contains($0.key) }
        signatureChecked.formIntersection(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
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
                case .assertionTornDown:
                    self.flight.note("engine: hide assertion torn down")
                    self.scheduleReapply(after: 1)
                case .convergeFailed(let reason):
                    self.flight.note("engine: converge failed: \(reason)")
                    self.scheduleReapply(after: 1)
                case .itemsChanged:
                    self.flight.note("engine: items changed", mergeKey: "items-changed")
                    // An app's item came or went: its mode applies to it.
                    self.scheduleReapply(after: 2)
                case .availabilityChanged(let available):
                    self.flight.note("engine: native hiding \(available ? "available" : "unavailable")")
                default:
                    break
                }
            }
        }
    }

    /// The layout the engine is asked to keep, as text: when it changes, an
    /// engine that couldn't settle gets another chance.
    var layoutSignature: String {
        modes.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + "|" + bulkHiddenKeys.sorted().joined(separator: ",")
    }

    func scheduleReapply(after delay: TimeInterval) {
        guard started, !quitting, !reapplyScheduled else { return }
        let signature = layoutSignature
        if let paused = reapplyPausedFor {
            guard paused != signature else { return }
            reapplyPausedFor = nil
            eventReapplies = []
        }
        let now = Date()
        eventReapplies = eventReapplies.filter { now.timeIntervalSince($0) < 120 }
        guard eventReapplies.count < 3 else {
            // Three in two minutes and the engine still reports trouble: an
            // icon it can't hide, most likely. Wait for the layout to change.
            reapplyPausedFor = signature
            NSLog("YoungBar: the engine doesn't settle on this layout; pausing re-applies until it changes")
            flight.note("engine: doesn't settle on this layout; re-applies paused")
            return
        }
        // Not more often than every 10 s: an item whose identity changes
        // with its title could otherwise ask on every walk.
        let wait = max(delay, 10 - now.timeIntervalSince(lastReapplyAt))
        reapplyScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(wait))
            reapplyScheduled = false
            lastReapplyAt = Date()
            eventReapplies.append(lastReapplyAt)
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
