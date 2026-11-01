// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Carbon.HIToolbox

/// The strip's window. It can take key focus without activating YoungBar
/// (a non-activating panel), so the shortcut opens it ready for the arrow
/// keys while the frontmost app stays frontmost.
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
/// ← → (or Tab / ⇧Tab) choose an item, Return or Space opens it, 1–9
/// open the first nine directly, Esc closes, ⌘, opens Settings. There is
/// no search: the strip holds a handful of icons.
extension BarApp {
    func handleShelfKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "," { openSettingsFromShelf(); return true }
            return false
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            closeShelf()
        case kVK_LeftArrow:
            moveShelfSelection(by: -1)
        case kVK_RightArrow:
            moveShelfSelection(by: 1)
        case kVK_Tab:
            moveShelfSelection(by: flags.contains(.shift) ? -1 : 1)
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_DownArrow, kVK_Space:
            pressShelfSelection()
        default:
            guard let number = Self.numberKeys[Int(event.keyCode)] else { return false }
            guard shelfButtons.indices.contains(number - 1) else { NSSound.beep(); return true }
            shelfSelection = number - 1
            applyShelfSelection()
            pressShelfItem(shelfButtons[number - 1])
        }
        return true
    }

    /// The digit row and the keypad by key position, so a layout that
    /// needs ⇧ for digits (AZERTY) works too.
    static let numberKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5,
        kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
    ]

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
}
