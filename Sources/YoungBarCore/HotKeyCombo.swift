// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// A global shortcut as Carbon registers it: a virtual key code and a
/// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
public struct HotKeyCombo: Equatable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// ⌃⌥B, the shortcut of every earlier version.
    public static let standard = HotKeyCombo(keyCode: 11, modifiers: control | option)

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    /// A shortcut needs ⌘, ⌃ or ⌥; Shift alone would steal ordinary typing.
    public var isUsable: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0
    }

    /// Modifier symbols in the order macOS menus use: ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text
    }

    public func display(keyName: String) -> String { modifierSymbols + keyName }
}
