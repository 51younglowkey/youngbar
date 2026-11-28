// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// Icons macOS takes off the bar with the hidden ones, whatever their mode.
///
/// The hide assertion lists the apps that stay, but macOS only honours the
/// list for apps installed in /Applications (subfolders too). It knows any
/// other app's item by the path of its executable rather than by its bundle,
/// and such an item leaves the bar while anything is hidden, signed or not:
/// a Developer ID app run from a temporary folder or ~/Applications went,
/// and a self-signed one in /Applications stayed (2026-11-27, issue #11;
/// what macOS records is in the control center's `trackedApplications`).
/// The agent's tree no longer lists it then: no walk sees it. Its own app
/// still lists the item, which is how it is told apart from an app that
/// simply has no icon, and how the strip presses it.
///
/// Found out while the icon is set to Show, and true until a walk lists it
/// again or its app quits: the mode doesn't change it. Dropped when the
/// mode changed, a shut-out icon set to Hide was in no list at all, with
/// no row left to set it back (user report, 2026-11-10).
///
/// Known ahead from where the app is (`fixed`): an app outside
/// /Applications is treated as shut out from the start, not only once it
/// was set to Show and went missing (user request, 2026-11-10).
public enum ShutOut {
    /// Whether macOS shows the icon of the app at `path` (its bundle, with
    /// symbolic links resolved) while it hides others: whether it is in
    /// /Applications. Not in ~/Applications, on a mounted disk image or
    /// translocated: those were all hidden (2026-11-27).
    public static func isInApplications(path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count >= 2 && parts[0] == "Applications"
    }

    /// Keys with no mode of their own to choose: listed in the strip and
    /// in their own section of Settings.
    /// - Parameters:
    ///   - shutOut: keys found to be shut out.
    ///   - outside: keys of apps outside /Applications.
    ///   - listed: every key Settings lists now.
    ///   - walked: keys the walk lists, on the bar as far as it can tell.
    ///   - concealed: keys the engine conceals right now.
    ///   - hidden: keys set to Hide, by their mode or by "Hide all".
    ///
    /// An outside app's icon is one while an icon macOS does hide on
    /// request (an /Applications app's, the system's) is concealed: its own
    /// mode changes nothing then, and the walk isn't asked, which still
    /// lists the icon for some seconds after hiding took effect (at launch
    /// it was a bar row for four seconds). Otherwise it is one when the walk
    /// doesn't list it, unless it is set to Hide and nothing else is: with
    /// only outside ones hidden, their modes are what keeps icons off the
    /// bar, and no row to set to Show would leave no way back. On the bar
    /// ("Show all", or nothing hidden) it is a row like any other.
    public static func fixed(shutOut: Set<String>, outside: Set<String>, listed: Set<String>,
                             walked: Set<String>, concealed: Set<String>, hidden: Set<String>) -> Set<String> {
        let othersConcealed = !concealed.subtracting(outside).isEmpty
        let othersHidden = !hidden.intersection(listed).subtracting(outside).isEmpty
        let known = outside.intersection(listed).filter {
            othersConcealed || (!walked.contains($0) && (!hidden.contains($0) || othersHidden))
        }
        return shutOut.subtracting(outside).union(known)
    }

    /// Keys the last refresh listed and this one doesn't, although their
    /// app still runs. They stay listed while the app is asked whether it
    /// still has an icon: an icon just set from Hide to Show that macOS
    /// won't show left the concealed set and every walk at once.
    /// - Parameters:
    ///   - previous: the keys listed after the last refresh.
    ///   - listed: keys the walk, the concealed set, the parked set or the
    ///     shut-out set has now.
    ///   - bundles: known single-icon keys and the app each belongs to.
    public static func lost(previous: Set<String>, listed: Set<String>, bundles: [String: String],
                            running: Set<String>) -> Set<String> {
        previous.subtracting(listed).filter { key in bundles[key].map(running.contains) ?? false }
    }

    /// Keys set to Show whose app runs although no walk lists an icon of it.
    /// - Parameters:
    ///   - bundles: known single-icon keys and the app each belongs to.
    ///   - hidden: keys hidden on top of the saved modes ("Hide all").
    ///   - listed: keys the walk, the concealed set or the parked set has.
    ///   - listedBundles: apps with any icon in the walk or the concealed
    ///     set: an app listed under another key is not missing.
    public static func suspects(bundles: [String: String], modes: [String: Int], hidden: Set<String>,
                                listed: Set<String>, listedBundles: Set<String>,
                                running: Set<String>) -> Set<String> {
        Set(bundles.filter { key, bundle in
            (modes[key] ?? 0) == 0 && !hidden.contains(key) && !listed.contains(key)
                && !listedBundles.contains(bundle) && running.contains(bundle)
        }.keys)
    }

    /// Of the icons found off the bar with an item of their own, those to
    /// land in an adoption window rather than shut out: their app is in
    /// /Applications, so macOS would show the icon, and only parked it, as
    /// it does an item registered while icons are hidden (an app that
    /// rebuilds its item, or one whose launch window was missed). An app
    /// whose place isn't known yet is left as it was.
    /// - Parameters:
    ///   - found: keys of Show icons missing from every walk whose app
    ///     lists an item.
    ///   - bundles: known single-icon keys and the app each belongs to.
    ///   - inApplications: per running app, whether it is in /Applications.
    public static func parked(found: Set<String>, bundles: [String: String],
                              inApplications: [String: Bool]) -> Set<String> {
        found.filter { key in bundles[key].flatMap { inApplications[$0] } == true }
    }

    /// How often a missing icon of one app is landed in an adoption window:
    /// every window shows the hidden icons for a moment, so an app that
    /// keeps losing its item is shut out after a few, like an outside one.
    public struct Adoptions: Sendable {
        /// Windows allowed per app within `span` seconds.
        public static let limit = 3
        public static let span: Double = 600

        var tries: [String: [Double]] = [:]

        public init() {}

        /// Whether another window may open for `bundle` now; it counts if so.
        public mutating func allow(_ bundle: String, now: Double) -> Bool {
            let recent = (tries[bundle] ?? []).filter { now - $0 < Self.span }
            guard recent.count < Self.limit else {
                tries[bundle] = recent
                return false
            }
            tries[bundle] = recent + [now]
            return true
        }
    }

    /// When to ask an app whether it has an icon. Not at once: a starting
    /// app is missing for a few seconds before its icon lands. And not on
    /// every walk: an app that runs without an icon stays a suspect.
    public struct Watch: Sendable {
        /// Seconds a suspect must have been missing before its app is asked.
        public static let patience: Double = 8
        /// The same for an icon that was listed a moment ago (`lost`): its
        /// app isn't starting, the walk only has to settle.
        public static let eagerPatience: Double = 3
        /// Seconds before an app that had no icon is asked again.
        public static let retry: Double = 60

        var since: [String: Double] = [:]
        var asked: [String: Double] = [:]

        public init() {}

        /// Starts over for `key`: its mode changed, so the answer may too.
        public mutating func forget(_ key: String) {
            since[key] = nil
            asked[key] = nil
        }

        /// The suspects to ask now; they count as asked.
        public mutating func due(_ suspects: Set<String>, eager: Set<String> = [], now: Double) -> Set<String> {
            since = since.filter { suspects.contains($0.key) }
            asked = asked.filter { suspects.contains($0.key) }
            var due = Set<String>()
            for key in suspects {
                guard let first = since[key] else {
                    since[key] = now
                    continue
                }
                guard now - first >= (eager.contains(key) ? Self.eagerPatience : Self.patience) else { continue }
                if let last = asked[key], now - last < Self.retry { continue }
                asked[key] = now
                due.insert(key)
            }
            return due
        }
    }
}
