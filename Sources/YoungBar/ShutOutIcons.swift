// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import PelmetCore
import PelmetEngine
import YoungBarCore

/// Icons macOS takes off the bar while anything is hidden: apps without an
/// Apple-issued signature (see `ShutOut`). They can't be put back, so they
/// join the strip like icons the bar has no room for (`overflowKeys`), keep
/// their saved mode, have a section of their own in Settings with no mode
/// to choose, and return by themselves when nothing is hidden.
extension BarApp {
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
            guard !shutOut.isEmpty || !dropped.isEmpty else { return }
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
