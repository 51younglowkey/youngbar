// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// Icons set to Show that macOS takes off the bar with the hidden ones.
///
/// The hide assertion lists the apps that stay, but macOS only honours the
/// list for apps with an Apple-issued signature. The icon of a self-signed
/// or ad hoc signed app (one built on this Mac, say) leaves the bar while
/// anything is hidden, and the agent's tree no longer lists it: no walk
/// sees it, so it was neither on the bar nor in the strip (2026-11-10;
/// a Developer ID app in the same spot, treated the same, stayed). Its own
/// app still lists the item, which is how it is told apart from an app that
/// simply has no icon, and how the strip presses it.
public enum ShutOut {
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
        /// Seconds before an app that had no icon is asked again.
        public static let retry: Double = 60

        var since: [String: Double] = [:]
        var asked: [String: Double] = [:]

        public init() {}

        /// The suspects to ask now; they count as asked.
        public mutating func due(_ suspects: Set<String>, now: Double) -> Set<String> {
            since = since.filter { suspects.contains($0.key) }
            asked = asked.filter { suspects.contains($0.key) }
            var due = Set<String>()
            for key in suspects {
                guard let first = since[key] else {
                    since[key] = now
                    continue
                }
                guard now - first >= Self.patience else { continue }
                if let last = asked[key], now - last < Self.retry { continue }
                asked[key] = now
                due.insert(key)
            }
            return due
        }
    }
}
