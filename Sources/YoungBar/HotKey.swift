// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Carbon.HIToolbox
import YoungBarCore

/// The global shortcut that opens the strip. Carbon hot keys need neither
/// AX focus nor an event tap; the handler runs on the main event loop.
extension BarApp {
    var hotKey: HotKeyCombo? {
        // A code of -1 means the user cleared the shortcut.
        guard let code = options[.hotKeyCode] else { return .standard }
        guard code >= 0 else { return nil }
        return HotKeyCombo(keyCode: UInt32(code), modifiers: UInt32(options[.hotKeyModifiers] ?? 0))
    }

    var hotKeyDisplay: String {
        guard let hotKey else { return L10n.t("无", "None") }
        return hotKey.display(keyName: Self.keyName(for: hotKey.keyCode))
    }

    /// (Re)registers the saved shortcut. Returns false when macOS refuses
    /// it, usually because another app already owns the combination.
    @discardableResult
    func registerHotKey() -> Bool {
        if hotKeyHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let app = Unmanaged<BarApp>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    app.hotKeyPressCount += 1
                    app.toggleShelfFrom(keyboard: true)
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        unregisterHotKey()
        guard let hotKey else { return true }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5942_4152), id: 1) // "YBAR"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("YoungBar hotkey registration failed: \(status)") }
        return status == noErr
    }

    func unregisterHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Saves and registers a new shortcut (nil clears it). A combination
    /// macOS refuses is not kept: the previous one comes back.
    func setHotKey(_ combo: HotKeyCombo?) {
        let previous = (options[.hotKeyCode], options[.hotKeyModifiers])
        if let combo {
            options[.hotKeyCode] = Int(combo.keyCode)
            options[.hotKeyModifiers] = Int(combo.modifiers)
        } else {
            options[.hotKeyCode] = -1
            options[.hotKeyModifiers] = 0
        }
        if registerHotKey() {
            feedback = combo == nil
                ? L10n.t("已关闭全局快捷键", "Global shortcut turned off")
                : L10n.t("快捷键已改为 \(hotKeyDisplay)", "Shortcut is now \(hotKeyDisplay)")
        } else {
            let refused = hotKeyDisplay
            options[.hotKeyCode] = previous.0
            options[.hotKeyModifiers] = previous.1
            registerHotKey()
            feedback = L10n.t("\(refused) 已被其他应用占用，保留原来的 \(hotKeyDisplay)",
                              "\(refused) is taken by another app; kept \(hotKeyDisplay)")
        }
        UserDefaults.standard.set(options, forKey: "barOptions")
        renderWindow(force: true)
    }

    /// Carbon modifier mask for AppKit modifier flags.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= HotKeyCombo.command }
        if flags.contains(.shift) { mask |= HotKeyCombo.shift }
        if flags.contains(.option) { mask |= HotKeyCombo.option }
        if flags.contains(.control) { mask |= HotKeyCombo.control }
        return mask
    }

    /// The key's label on the current keyboard layout ("B", "Space", "F5").
    static func keyName(for keyCode: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(keyCode)] { return name }
        // The ASCII-capable layout: with a Chinese input method active the
        // current source has no key layout of its own.
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
