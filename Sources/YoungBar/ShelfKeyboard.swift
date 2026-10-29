// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Carbon.HIToolbox
import PelmetCore
import YoungBarCore

/// The strip's window. It can take key focus without activating YoungBar
/// (a non-activating panel), so the shortcut opens it ready for typing
/// while the frontmost app stays frontmost.
@MainActor
final class ShelfPanel: NSPanel {
    /// Returns true when it handled the key.
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // Ahead of the buttons: they would take Space and Return themselves.
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Keyboard use of the open strip:
/// ← → (or Tab / ⇧Tab) choose an item, Return opens it, typing filters by
/// name, ⌫ deletes, Esc clears the search and then closes, ⌘, opens
/// Settings.
extension BarApp {
    func handleShelfKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "," { openSettingsFromShelf(); return true }
            return false
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            if shelfQuery.isEmpty { closeShelf() } else { setShelfQuery("") }
        case kVK_LeftArrow:
            moveShelfSelection(by: -1)
        case kVK_RightArrow:
            moveShelfSelection(by: 1)
        case kVK_Tab:
            moveShelfSelection(by: flags.contains(.shift) ? -1 : 1)
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_DownArrow:
            pressShelfSelection()
        case kVK_Delete:
            if !shelfQuery.isEmpty { setShelfQuery(String(shelfQuery.dropLast())) }
        case kVK_Space where shelfQuery.isEmpty:
            pressShelfSelection()
        default:
            guard !flags.contains(.control), let text = event.characters,
                  !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                return false
            }
            setShelfQuery(shelfQuery + text)
        }
        return true
    }

    func setShelfQuery(_ query: String) {
        shelfQuery = query
        // The best match is chosen as soon as there is a query.
        shelfSelection = query.isEmpty ? nil : 0
        populateShelf()
    }

    func moveShelfSelection(by step: Int) {
        guard !shelfButtons.isEmpty else { return }
        let count = shelfButtons.count
        if let current = shelfSelection {
            shelfSelection = ((current + step) % count + count) % count
        } else {
            shelfSelection = step > 0 ? 0 : count - 1
        }
        applyShelfSelection()
    }

    func pressShelfSelection() {
        guard let index = shelfSelection ?? (shelfButtons.count == 1 ? 0 : nil),
              shelfButtons.indices.contains(index) else { NSSound.beep(); return }
        pressShelfItem(shelfButtons[index])
    }

    /// The chosen item gets a soft rounded highlight, like a pressed one.
    func applyShelfSelection() {
        for (index, button) in shelfButtons.enumerated() {
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            let selected = index == shelfSelection
            button.layer?.backgroundColor = selected
                ? shelfIconColor.withAlphaComponent(shelfIconColor == .black ? 0.12 : 0.22).cgColor
                : NSColor.clear.cgColor
            button.setAccessibilitySelected(selected)
            if selected { button.scrollToVisible(button.bounds) }
        }
    }

    /// Hidden, Always Hidden and covered items matching `query`, best first.
    /// English names and the app's bundle id count too, so "wifi" or
    /// "wechat" find an item whatever language the names are in.
    func searchShelf(_ query: String) -> [String] {
        let candidates = orderedKeys().compactMap { key -> SearchCandidate? in
            let mode = modes[key] ?? 0
            let covered = overflowKeys.contains(key)
            guard mode > 0 || covered else { return nil }
            let id = catalog[key]?.id ?? ItemID(rawValue: key)
            var keywords = searchKeywords(for: id)
            if let bundle = id.bundleID {
                keywords.append(bundle)
                if let last = bundle.split(separator: ".").last { keywords.append(String(last)) }
            }
            let section: Section = mode == 2 ? .alwaysHidden : (mode == 1 ? .hidden : .visible)
            return SearchCandidate(id: key, kind: .item, title: name(for: key), keywords: keywords, section: section)
        }
        return SearchRanker.rank(query: query, candidates: candidates, now: Date(), limit: 20).map(\.candidate.id)
    }

    private func searchKeywords(for id: ItemID) -> [String] {
        guard let system = MenuBarPolicy.systemItem(for: id) else { return [] }
        switch system {
        case .battery: return ["Battery", "电池"]
        case .bluetooth: return ["Bluetooth", "蓝牙"]
        case .clock: return ["Clock", "Date", "Time", "时间", "日期"]
        case .displays: return ["Displays", "显示器"]
        case .keyboard: return ["Input", "Keyboard", "输入法"]
        case .volume: return ["Sound", "Volume", "声音"]
        case .wifi: return ["Wi-Fi", "WLAN", "无线"]
        case .screenMirroring: return ["Screen Mirroring", "AirPlay", "屏幕镜像"]
        case .primaryBentoBox: return ["Control Center", "控制中心"]
        }
    }
}
