// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// The look the window server keeps for the menu bar on each desktop
/// (`SLSGetMenuAppearanceThemeOnSpace` on macOS 27). Only the two values seen
/// there count: anything else means the call changed, and the caller goes
/// back to the status item's own look.
public enum MenuBarTheme {
    public static func isDark(rawValue: Int32) -> Bool? {
        switch rawValue {
        case 0: false
        case 1: true
        default: nil
        }
    }
}
