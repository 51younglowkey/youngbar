// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import PelmetCore
import PelmetEngine
import Security
import YoungBarCore

/// Icons macOS takes off the bar while anything is hidden: apps without an
/// Apple-issued signature (see `ShutOut`). They can't be put back, so they
/// join the strip like icons the bar has no room for (`overflowKeys`), keep
/// their saved mode, have a section of their own in Settings with no mode
/// to choose, and return by themselves when nothing is hidden.
///
/// The signature tells ahead (`checkSignatures`): such an app's icon is in
/// that section from the start (`fixedKeys`), also while it is set to Hide
/// and concealed like any other.
extension BarApp {
    /// Keys of running apps whose signature is not Apple-issued.
    func unsignedKeys() -> Set<String> {
        Set(singleIconBundles().filter { signatures[$0.value] == false }.keys)
    }

    /// Looks at the signature of each running app, once per process and
    /// off the main actor, and refreshes when one turns out not to be
    /// Apple-issued.
    ///
    /// Not only the apps with a known icon: one that was running before
    /// YoungBar started is off the bar by the first walk, so no walk ever
    /// lists its icon (after a restart an ad hoc signed app was neither in
    /// the strip nor in Settings, 2026-11-10). Such an app is asked for its
    /// icon here and listed as shut out.
    func checkSignatures() {
        guard started, !quitting else { return }
        let first = signatureChecked.isEmpty
        var asking: [(bundle: String, pid: pid_t, settled: Bool)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
                  !bundle.hasPrefix("com.apple."), !signatureChecked.contains(app.processIdentifier) else { continue }
            signatureChecked.insert(app.processIdentifier)
            // A starting app's icon is still on its way: the adoption
            // window and the walks after it deal with that one.
            let settled = app.launchDate.map { Date().timeIntervalSince($0) > 10 } ?? true
            asking.append((bundle, app.processIdentifier, settled))
        }
        guard !asking.isEmpty else { return }
        signaturesPending = first
        Task {
            // Whatever comes of it, the ••• is placed once it is known.
            defer {
                if signaturesPending {
                    signaturesPending = false
                    if let lastSnapshot { positionControlBesideMenuIcons(in: lastSnapshot) }
                }
            }
            var unsigned = Set<String>()
            var withIcon = Set<String>()
            let hiding = await engine.holdsAssertion
            for (bundle, pid, settled) in asking {
                // Can't be told: counted as signed, so only what macOS
                // does (`lookForShutOutIcons`) moves it.
                let appleIssued = await Task.detached { BarApp.hasAppleIssuedSignature(pid: pid) }.value ?? true
                signatures[bundle] = (signatures[bundle] ?? true) && appleIssued
                guard !appleIssued else { continue }
                unsigned.insert(bundle)
                if hiding, settled, !lists(bundle),
                   await Task.detached(operation: { BarApp.hasStatusItem(pid: pid) }).value {
                    withIcon.insert(bundle)
                }
            }
            guard !unsigned.isEmpty, !quitting else { return }
            flight.note("no Apple-issued signature: \(unsigned.sorted().joined(separator: ", "))")
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

    /// Whether the running app's signature chains to Apple (Apple's own,
    /// the App Store, Developer ID, Apple Development): not self-signed and
    /// not ad hoc. Nil when the process can't be looked at. Asked of the
    /// running code, which needs no pass over the bundle on disk.
    nonisolated static func hasAppleIssuedSignature(pid: pid_t) -> Bool? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
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
