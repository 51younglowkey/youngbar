// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Keys of the `barOptions` dictionary in user defaults. The dictionary stays
/// `[String: Int]` on disk (older versions wrote it that way); code reads
/// and writes it only through these cases, so a typo is a compile error.
enum Option: String, CaseIterable {
    case language
    case appearanceMode, themeColor, themeScope, stripOpacity
    /// Pre-0.1 three-way strip material; read once to derive `stripOpacity`.
    case stripStyle
    case controlIcon
    case nativeExpand, keepShelfOpen, hoverExpand, blankClick, leftClickMenu
    case revealSeconds
    case iconSpacing
    /// Shown items macOS moved into its « (or under the notch) for lack
    /// of room are listed in the strip too.
    case notchOverflow
    /// Global shortcut: virtual key code and Carbon modifier mask.
    case hotKeyCode, hotKeyModifiers
    /// Set once the first-run guide has been closed.
    case onboarded
}

extension Dictionary where Key == String, Value == Int {
    subscript(option: Option) -> Int? {
        get { self[option.rawValue] }
        set { self[option.rawValue] = newValue }
    }
}
