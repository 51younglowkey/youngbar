// Synonyms.swift
// The words people type for the menu bar items macOS ships: "bt" for
// Bluetooth, "dnd" for Focus, "cc" for Control Center. English only for now;
// localized titles still find their entry through the Apple bundle id.

import Foundation

public enum Synonyms {
    private struct Entry {
        /// Folded title with separators removed ("Wi-Fi" → "wifi"). Matches
        /// the whole title, or one word of it for single-word names.
        let names: [String]
        /// Pieces of an Apple bundle id (`com.apple.menuextra.wifi`), for
        /// titles a language or a state has changed.
        let bundles: [String]
        let keywords: [String]
    }

    private static let table: [Entry] = [
        Entry(names: ["wifi", "airport"], bundles: ["menuextra.wifi", "menuextra.airport"],
              keywords: ["wifi", "wlan", "wireless", "network"]),
        Entry(names: ["bluetooth"], bundles: ["menuextra.bluetooth"],
              keywords: ["bt"]),
        Entry(names: ["sound", "volume"], bundles: ["menuextra.sound", "menuextra.volume"],
              keywords: ["vol", "volume", "audio", "output"]),
        Entry(names: ["battery"], bundles: ["menuextra.battery"],
              keywords: ["batt", "power"]),
        Entry(names: ["focus", "donotdisturb"], bundles: ["donotdisturb", "focus"],
              keywords: ["dnd", "do not disturb"]),
        Entry(names: ["vpn"], bundles: ["menuextra.vpn"],
              keywords: ["vpn", "tunnel"]),
        Entry(names: ["textinput", "keyboard", "inputmenu", "inputsource"],
              bundles: ["textinputmenuagent", "menuextra.textinput"],
              keywords: ["kb", "keyboard", "input", "language"]),
        Entry(names: ["controlcenter"], bundles: ["menuextra.controlcenter"],
              keywords: ["cc"]),
        Entry(names: ["display", "displays"], bundles: ["menuextra.display"],
              keywords: ["brightness", "screen"]),
        Entry(names: ["airdrop"], bundles: ["menuextra.airdrop"],
              keywords: ["air drop", "share"]),
        Entry(names: ["nowplaying"], bundles: ["menuextra.nowplaying"],
              keywords: ["music", "media", "play"]),
        Entry(names: ["clock"], bundles: ["menuextra.clock"],
              keywords: ["time", "date"]),
        Entry(names: ["spotlight"], bundles: ["menuextra.spotlight"],
              keywords: ["search"]),
        Entry(names: ["siri"], bundles: ["com.apple.siri", "menuextra.siri"],
              keywords: ["assistant"]),
        Entry(names: ["screenmirroring", "airplay"],
              bundles: ["menuextra.airplay", "menuextra.screenmirroring", "airplayuiagent"],
              keywords: ["airplay", "mirror"]),
        Entry(names: ["fastuserswitching", "userswitcher", "users"],
              bundles: ["menuextra.user"],
              keywords: ["user", "account"]),
        Entry(names: ["timemachine"], bundles: ["timemachine"],
              keywords: ["backup"]),
        Entry(names: ["notificationcenter", "notifications"], bundles: ["notificationcenter"],
              keywords: ["notifications", "nc"]),
    ]

    /// Extra search words for an item, empty when it isn't one we know.
    /// Matching is loose on purpose: a third-party "Bluetooth Explorer" gets
    /// "bt" too, which is what someone typing it wants.
    public static func keywords(title: String, bundleID: String? = nil) -> [String] {
        let normalized = FoldedText.normalized(title)
        let words = normalized.split(separator: " ").map(String.init)
        let compact = words.joined()
        let bundle = bundleID?.lowercased()
        let isApple = bundle?.hasPrefix("com.apple.") == true

        var out: [String] = []
        for entry in table where matches(entry, compact: compact, words: words, bundle: isApple ? bundle : nil) {
            for keyword in entry.keywords where !out.contains(keyword) {
                out.append(keyword)
            }
        }
        return out
    }

    private static func matches(_ entry: Entry, compact: String, words: [String], bundle: String?) -> Bool {
        for name in entry.names {
            if compact == name || words.contains(name) { return true }
            // Longer names are distinctive enough to match inside a title.
            if name.count >= 8, compact.contains(name) { return true }
        }
        if let bundle {
            return entry.bundles.contains { bundle.contains($0) }
        }
        return false
    }
}
