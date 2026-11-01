// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Keys of the `barOptions` dictionary in user defaults. 0.1.4 dropped
/// keepShelfOpen, blankClick, leftClickMenu, revealSeconds, notchOverflow,
/// themeScope and nativeExpand: what they chose is now fixed behaviour, and
/// values older versions saved are ignored. The dictionary stays
/// `[String: Int]` on disk (older versions wrote it that way); code reads
/// and writes it only through these cases, so a typo is a compile error.
enum Option: String, CaseIterable {
    case language
    case appearanceMode, themeColor, stripOpacity
    /// Pre-0.1 three-way strip material; read once to derive `stripOpacity`.
    case stripStyle
    case controlIcon
    case hoverExpand
    case iconSpacing
    /// Global shortcut: virtual key code and Carbon modifier mask.
    case hotKeyCode, hotKeyModifiers
    /// Set once the first-run guide has been closed.
    case onboarded
    /// An app's icon seen for the first time goes straight to the strip.
    case autoHideNew
    /// Numbers 1–9 under the icons when the strip opens from the keyboard
    /// (on unless 0). The number keys work either way.
    case shelfNumbers
}

extension Dictionary where Key == String, Value == Int {
    subscript(option: Option) -> Int? {
        get { self[option.rawValue] }
        set { self[option.rawValue] = newValue }
    }
}
