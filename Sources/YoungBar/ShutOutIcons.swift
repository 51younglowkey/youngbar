// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import PelmetCore
import PelmetEngine
import YoungBarCore

/// Icons macOS takes off the bar while anything is hidden: apps outside
/// /Applications (see `ShutOut`). They can't be put back, so they join the
/// strip like icons the bar has no room for (`overflowKeys`), keep their
/// saved mode, have a section of their own in Settings with no mode to
/// choose, and return by themselves when nothing is hidden.
///
/// Where the app is tells ahead (`checkLocations`): such an app's icon is
/// in that section from the start (`fixedKeys`), also while it is set to
/// Hide and concealed like any other.
extension BarApp {
    /// Keys of running apps outside /Applications.
    func outsideKeys() -> Set<String> {
        Set(singleIconBundles().filter { inApplications[$0.value] == false }.keys)
    }

    /// Looks where each running app is installed, once per process, and
    /// refreshes when one turns out to be outside /Applications.
    ///
    /// Not only the apps with a known icon: one that was running before
    /// YoungBar started is off the bar by the first walk, so no walk ever
    /// lists its icon (after a restart an app built on this Mac was neither
    /// in the strip nor in Settings, 2026-11-10). Such an app is asked for
    /// its icon here and listed as shut out.
    func checkLocations() {
        guard started, !quitting else { return }
        let first = locationChecked.isEmpty
        var asking: [(bundle: String, pid: pid_t, settled: Bool, inside: Bool?)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                  !bundle.hasPrefix("com.apple."), !locationChecked.contains(app.processIdentifier) else { continue }
            locationChecked.insert(app.processIdentifier)
            // A starting app's icon is still on its way: the adoption
            // window and the walks after it deal with that one.
            let settled = app.launchDate.map { Date().timeIntervalSince($0) > 10 } ?? true
            asking.append((bundle, app.processIdentifier, settled, Self.isInApplications(app)))
        }
        guard !asking.isEmpty else { return }
        locationsPending = first
        Task {
            // Whatever comes of it, the ••• is placed once it is known.
            defer {
                if locationsPending {
                    locationsPending = false
                    if let lastSnapshot { positionControlBesideMenuIcons(in: lastSnapshot) }
                }
            }
            var outside = Set<String>()
            var withIcon = Set<String>()
            let hiding = await engine.holdsAssertion
            for (bundle, pid, settled, inside) in asking {
                // Can't be told: counted as inside, so only what macOS
                // does (`lookForShutOutIcons`) moves it.
                let inside = inside ?? true
                inApplications[bundle] = (inApplications[bundle] ?? true) && inside
                guard !inside else { continue }
                outside.insert(bundle)
                if hiding, settled, !lists(bundle),
                   await Task.detached(operation: { BarApp.hasStatusItem(pid: pid) }).value {
                    withIcon.insert(bundle)
                }
            }
            guard !outside.isEmpty, !quitting else { return }
            flight.note("outside /Applications: \(outside.sorted().joined(separator: ", "))")
            var found: [String] = []
            for bundle in withIcon where !lists(bundle) {
                rememberUnlistedApp(bundle)
                guard let key = singleIconBundles().first(where: { $0.value == bundle })?.key else { continue }
                shutOutKeys.insert(key)
                found.append(name(for: key))
            }
            if !found.isEmpty {
                flight.note("off the bar since before the first walk: \(found.sorted().joined(separator: ", "))")
            }
            await refresh()
        }
    }

    /// Whether any icon of the app is listed now.
    func lists(_ bundle: String) -> Bool {
        presentKeys.contains { catalog[$0]?.id.bundleID == bundle }
    }

    /// Whether the running app is installed in /Applications, the only
    /// place from which macOS keeps its icon on the bar while it hides
    /// others (`ShutOut.isInApplications`). Nil when it has no bundle path.
    nonisolated static func isInApplications(_ app: NSRunningApplication) -> Bool? {
        guard let url = app.bundleURL else { return nil }
        return ShutOut.isInApplications(path: url.resolvingSymlinksInPath().path)
    }

    /// Known single-icon keys and the app each belongs to: those are the
    /// ones the strip can press.
    func singleIconBundles() -> [String: String] {
        var bundles: [String: String] = [:]
        for (key, item) in catalog where key.hasPrefix("bundle:") {
            guard let bundle = item.id.bundleID, bundle != Bundle.main.bundleIdentifier,
                  !bundle.hasPrefix("com.apple.") else { continue }
            bundles[key] = bundle
        }
        return bundles
    }

    /// After a walk: asks the apps of Show icons that stay missing, and of
    /// icons that just left every list (`unlistedKeys`), whether they have
    /// an icon, off the main actor. Show icons that do are shut out; an
    /// unlisted one that doesn't is dropped.
    func lookForShutOutIcons(_ snapshot: EngineSnapshot) {
        guard started, !quitting else { return }
        var listed = parkedKeys.union(shutOutKeys)
        var listedBundles = Set<String>()
        for id in snapshot.items.map(\.id) + Array(snapshot.concealed) {
            listed.insert(id.sectionKey.rawValue)
            if let bundle = id.bundleID { listedBundles.insert(bundle) }
        }
        let bundles = singleIconBundles()
        let suspects = ShutOut.suspects(bundles: bundles, modes: modes, hidden: bulkHiddenKeys, listed: listed,
                                        listedBundles: listedBundles, running: runningBundleIDs())
        let due = shutOutWatch.due(suspects.union(unlistedKeys), eager: unlistedKeys,
                                   now: Date().timeIntervalSinceReferenceDate)
        guard !due.isEmpty else { return }
        let asking = due.compactMap { key -> (String, pid_t)? in
            guard let bundle = bundles[key],
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle })
            else { return nil }
            return (key, app.processIdentifier)
        }
        Task {
            var found = Set<String>()
            // With nothing hidden macOS shows every icon: missing then means
            // the app has none.
            if await engine.holdsAssertion {
                for (key, pid) in asking where await Task.detached(operation: { BarApp.hasStatusItem(pid: pid) }).value {
                    found.insert(key)
                }
            }
            guard !quitting else { return }
            // No icon any more: nothing to keep a row for.
            let dropped = unlistedKeys.intersection(due).subtracting(found)
            unlistedKeys.subtract(dropped)
            // Shut out only when it was meant to show; a hidden one that left
            // the lists stays listed as it is.
            var shutOut = found.filter { (modes[$0] ?? 0) == 0 && !bulkHiddenKeys.contains($0) }
            // A walk since may have listed it after all.
            shutOut.subtract(presentKeys.subtracting(shutOutKeys).subtracting(unlistedKeys))
            shutOut.subtract(shutOutKeys)
            // An /Applications app's icon is only parked: landed, it shows.
            var landedAny = false
            for key in ShutOut.parked(found: shutOut, bundles: bundles, inApplications: inApplications).sorted() {
                guard let bundle = bundles[key], let landed = await landMissing(bundle) else {
                    // Not tried now: asked again later (`Watch.retry`).
                    shutOut.remove(key)
                    continue
                }
                if landed {
                    shutOut.remove(key)
                    unlistedKeys.remove(key)
                    landedAny = true
                }
            }
            guard !shutOut.isEmpty || !dropped.isEmpty || landedAny else { return }
            if !shutOut.isEmpty {
                shutOutKeys.formUnion(shutOut)
                unlistedKeys.subtract(shutOut)
                let names = shutOut.sorted().map { name(for: $0) }.joined(separator: ", ")
                NSLog("YoungBar: macOS keeps these Show icons off the bar while icons are hidden: \(names)")
                flight.note("shut out by macOS while icons are hidden: \(names)")
            }
            if !dropped.isEmpty {
                flight.note("no icon any more: \(dropped.sorted().map { name(for: $0) }.joined(separator: ", "))")
            }
            await refresh()
        }
    }

    /// Brings back the icon of an /Applications app missing from the bar although
    /// the app has one: hidden by omission (the engine wasn't told the app
    /// runs), or parked by macOS (an item registered while icons were
    /// hidden), which an adoption window lands. Whether the icon landed; false
    /// once the app had its windows (`ShutOut.Adoptions`), so it is shut
    /// out like an outside one; nil when it can't be tried now.
    func landMissing(_ bundle: String) async -> Bool? {
        for _ in 0..<50 where busy || syncing { try? await Task.sleep(for: .milliseconds(100)) }
        guard !busy, !syncing, !quitting else { return nil }
        syncing = true
        defer { syncing = false }
        // An app the engine doesn't know of is hidden by omission: a launch
        // it wasn't told about. Told now, it may show without a window.
        await engine.setRunningBundles(runningBundleIDs())
        try? await Task.sleep(for: .milliseconds(500))
        if await engine.freshSnapshot().items.contains(where: { $0.id.bundleID == bundle }) {
            flight.note("\(bundle) back on the bar once the engine knew it runs")
            return true
        }
        guard await engine.holdsAssertion else { return nil }
        guard missingAdoptions.allow(bundle, now: Date().timeIntervalSinceReferenceDate) else {
            flight.note("\(bundle) missing again, too often: kept in the strip")
            return false
        }
        let adopted = await engine.openAdoptionWindow(for: bundle)
        NSLog("YoungBar: \(bundle) \(adopted ? "landed" : "not seen") after going missing")
        flight.note("\(bundle) \(adopted ? "landed" : "not seen") after going missing")
        return adopted
    }

    /// An app whose icon was adopted and left the bar again as the window
    /// closed, and that no walk has ever listed: without a key it could not
    /// become a suspect.
    func rememberUnlistedApp(_ bundle: String) {
        let key = "bundle:\(bundle)"
        guard !catalog.contains(where: { $0.value.id.bundleID == bundle }) else { return }
        catalog[key] = ObservedItem(id: ItemID(rawValue: key), frame: nil, appName: nil)
        if !savedOrder.contains(key) {
            savedOrder.append(key)
            UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        }
    }
}
