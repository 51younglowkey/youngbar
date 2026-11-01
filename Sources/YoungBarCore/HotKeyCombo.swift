// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// A global shortcut as Carbon registers it: a virtual key code and a
/// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
public struct HotKeyCombo: Equatable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// Not a key: the combination is its one modifier pressed twice.
    public static let doubleTapKeyCode: UInt32 = 0xFFFF

    /// ⌘ pressed twice on its own: one hand, and nothing in macOS or the
    /// common apps claims it (Claude takes ⌥⌥, ChatGPT ⌥Space).
    public static let standard = doubleTap(command)
    /// ⌃⌥B, the shortcut of 0.1.1–0.1.3.
    public static let legacy = HotKeyCombo(keyCode: 11, modifiers: control | option)

    public static func doubleTap(_ modifier: UInt32) -> HotKeyCombo {
        HotKeyCombo(keyCode: doubleTapKeyCode, modifiers: modifier)
    }

    public var isDoubleTap: Bool { keyCode == Self.doubleTapKeyCode }

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    /// A shortcut needs ⌘, ⌃ or ⌥; Shift alone would steal ordinary typing.
    /// A double tap is of exactly one of them.
    public var isUsable: Bool {
        if isDoubleTap { return [Self.command, Self.option, Self.control].contains(modifiers) }
        return modifiers & (Self.command | Self.option | Self.control) != 0
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

/// Spots a modifier pressed twice on its own: down and up quickly, twice,
/// with no other key or modifier in between (so ⌘C ⌘V never count).
/// Fed with every modifier change and every other key press.
public struct DoubleTapDetector: Sendable {
    /// Only this modifier counts; nil takes whichever of ⌘ ⌥ ⌃ is tapped
    /// (for recording a new shortcut).
    public var target: UInt32?
    public var maxPress: Double = 0.35
    public var maxGap: Double = 0.45

    private var down: (modifier: UInt32, at: Double)?
    private var lastTap: (modifier: UInt32, at: Double)?

    public init(target: UInt32?) { self.target = target }

    /// `modifiers` is the Carbon mask held after the change. Returns the
    /// modifier on its second tap.
    public mutating func flagsChanged(_ modifiers: UInt32, at time: Double) -> UInt32? {
        let candidates = target.map { [$0] } ?? [HotKeyCombo.command, HotKeyCombo.option, HotKeyCombo.control]
        if candidates.contains(modifiers) {
            if let lastTap, lastTap.modifier != modifiers { self.lastTap = nil }
            down = (modifiers, time)
            return nil
        }
        if modifiers == 0, let pressed = down {
            down = nil
            guard time - pressed.at <= maxPress else { lastTap = nil; return nil }
            if let last = lastTap, last.modifier == pressed.modifier, pressed.at - last.at <= maxGap {
                lastTap = nil
                return pressed.modifier
            }
            lastTap = (pressed.modifier, time)
            return nil
        }
        reset()
        return nil
    }

    /// Any other key: whatever was pressed was part of a combination.
    public mutating func otherKey() { reset() }

    public mutating func reset() {
        down = nil
        lastTap = nil
    }
}
