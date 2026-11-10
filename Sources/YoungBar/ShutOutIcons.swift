// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import PelmetCore
import PelmetEngine
import YoungBarCore

/// Show icons macOS takes off the bar while anything is hidden: apps without
/// an Apple-issued signature (see `ShutOut`). They can't be put back, so
/// they join the strip like icons the bar has no room for (`overflowKeys`),
/// keep their saved mode, and return by themselves when nothing is hidden.
extension BarApp {
    /// After a walk: asks the apps of Show icons that stay missing whether
    /// they have an icon, off the main actor, and lists the ones that do.
    func lookForShutOutIcons(_ snapshot: EngineSnapshot) {
        guard started, !quitting else { return }
        var listed = parkedKeys.union(shutOutKeys)
        var listedBundles = Set<String>()
        for id in snapshot.items.map(\.id) + Array(snapshot.concealed) {
            listed.insert(id.sectionKey.rawValue)
            if let bundle = id.bundleID { listedBundles.insert(bundle) }
        }
        var bundles: [String: String] = [:]
        // Single-icon keys only: those are the ones the strip can press.
        for (key, item) in catalog where key.hasPrefix("bundle:") {
            guard let bundle = item.id.bundleID, bundle != Bundle.main.bundleIdentifier,
                  !bundle.hasPrefix("com.apple.") else { continue }
            bundles[key] = bundle
        }
        let suspects = ShutOut.suspects(bundles: bundles, modes: modes, hidden: bulkHiddenKeys, listed: listed,
                                        listedBundles: listedBundles, running: runningBundleIDs())
        let due = shutOutWatch.due(suspects, now: Date().timeIntervalSinceReferenceDate)
        guard !due.isEmpty else { return }
        let asking = due.compactMap { key -> (String, pid_t)? in
            guard let bundle = bundles[key],
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle })
            else { return nil }
            return (key, app.processIdentifier)
        }
        Task {
            // With nothing hidden macOS shows every icon: missing then means
            // the app has none.
            guard await engine.holdsAssertion else { return }
            var found = Set<String>()
            for (key, pid) in asking where await Task.detached(operation: { BarApp.hasStatusItem(pid: pid) }).value {
                found.insert(key)
            }
            // A walk since may have listed it after all.
            found.subtract(presentKeys.subtracting(shutOutKeys))
            found.subtract(shutOutKeys)
            guard !found.isEmpty, !quitting else { return }
            shutOutKeys.formUnion(found)
            let names = found.sorted().map { name(for: $0) }.joined(separator: ", ")
            NSLog("YoungBar: macOS keeps these Show icons off the bar while icons are hidden: \(names)")
            flight.note("shut out by macOS while icons are hidden: \(names)")
            await refresh()
        }
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
