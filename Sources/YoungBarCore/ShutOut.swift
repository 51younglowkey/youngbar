// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// Icons macOS takes off the bar with the hidden ones, whatever their mode.
///
/// The hide assertion lists the apps that stay, but macOS only honours the
/// list for apps with an Apple-issued signature. The icon of a self-signed
/// or ad hoc signed app (one built on this Mac, say) leaves the bar while
/// anything is hidden, and the agent's tree no longer lists it: no walk
/// sees it, so it was neither on the bar nor in the strip (2026-11-10;
/// a Developer ID app in the same spot, treated the same, stayed). Its own
/// app still lists the item, which is how it is told apart from an app that
/// simply has no icon, and how the strip presses it.
///
/// Found out while the icon is set to Show, and true until a walk lists it
/// again or its app quits: the mode doesn't change it. Dropped when the
/// mode changed, a shut-out icon set to Hide was in no list at all, with
/// no row left to set it back (user report, 2026-11-10).
///
/// Known ahead from the signature too (`fixed`): an app without an
/// Apple-issued one is treated as shut out from the start, not only once
/// it was set to Show and went missing (user request, 2026-11-10; an ad
/// hoc signed app is shut out like a self-signed one, tried the same day).
public enum ShutOut {
    /// Keys with no mode of their own to choose: listed in the strip and
    /// in their own section of Settings.
    /// - Parameters:
    ///   - shutOut: keys found to be shut out.
    ///   - unsigned: keys of apps without an Apple-issued signature.
    ///   - listed: every key Settings lists now.
    ///   - walked: keys the walk lists, on the bar as far as it can tell.
    ///   - concealed: keys the engine conceals right now.
    ///   - hidden: keys set to Hide, by their mode or by "Hide all".
    ///
    /// An unsigned app's icon is one while an icon macOS does hide on
    /// request (a signed app's, the system's) is concealed: its own mode
    /// changes nothing then, and the walk isn't asked, which still lists
    /// the icon for some seconds after hiding took effect (at launch it
    /// was a bar row for four seconds). Otherwise it is one when the walk
    /// doesn't list it, unless it is set to Hide and nothing else is:
    /// with only unsigned ones hidden, their modes are what keeps icons
    /// off the bar, and no row to set to Show would leave no way back. On
    /// the bar ("Show all", or nothing hidden) it is a row like any other.
    public static func fixed(shutOut: Set<String>, unsigned: Set<String>, listed: Set<String>,
                             walked: Set<String>, concealed: Set<String>, hidden: Set<String>) -> Set<String> {
        let othersConcealed = !concealed.subtracting(unsigned).isEmpty
        let othersHidden = !hidden.intersection(listed).subtracting(unsigned).isEmpty
        let known = unsigned.intersection(listed).filter {
            othersConcealed || (!walked.contains($0) && (!hidden.contains($0) || othersHidden))
        }
        return shutOut.subtracting(unsigned).union(known)
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
