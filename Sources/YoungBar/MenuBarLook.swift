// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import YoungBarCore

/// The menu bar's look on the desktop a screen is showing, from the window
/// server. The status item's button can't tell: it keeps the look of the
/// desktop YoungBar started on. Asking takes no status item (nothing on the
/// bar moves, the engine sees nothing) and no screen recording.
///
/// Private SkyLight calls, resolved at runtime like the engine's shim: a
/// macOS without them gets `nil`, and the ••• goes by the button as before.
@MainActor
enum MenuBarLook {
    private struct Calls {
        let mainConnection: @convention(c) () -> Int32
        let activeSpace: @convention(c) (Int32) -> UInt64
        let currentSpace: @convention(c) (Int32, CFString) -> UInt64
        let theme: @convention(c) (UInt64) -> Int32
    }

    private static let calls: Calls? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnection = dlsym(handle, "SLSMainConnectionID"),
              let activeSpace = dlsym(handle, "SLSGetActiveSpace"),
              let currentSpace = dlsym(handle, "SLSManagedDisplayGetCurrentSpace"),
              let theme = dlsym(handle, "SLSGetMenuAppearanceThemeOnSpace") else { return nil }
        return Calls(mainConnection: unsafeBitCast(mainConnection, to: (@convention(c) () -> Int32).self),
                     activeSpace: unsafeBitCast(activeSpace, to: (@convention(c) (Int32) -> UInt64).self),
                     currentSpace: unsafeBitCast(currentSpace, to: (@convention(c) (Int32, CFString) -> UInt64).self),
                     theme: unsafeBitCast(theme, to: (@convention(c) (UInt64) -> Int32).self))
    }()

    /// The desktop `screen` is showing; the active one when it has none.
    static func space(on screen: NSScreen?) -> UInt64? {
        guard let calls else { return nil }
        let connection = calls.mainConnection()
        var space: UInt64 = 0
        if let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
           let name = CFUUIDCreateString(nil, uuid) {
            space = calls.currentSpace(connection, name)
        }
        // Displays sharing one set of desktops don't go by their own ID.
        if space == 0 { space = calls.activeSpace(connection) }
        return space == 0 ? nil : space
    }

    /// The window server's value for that desktop, as it comes.
    static func rawTheme(space: UInt64) -> Int32? {
        calls?.theme(space)
    }

    static func isDark(on screen: NSScreen?) -> Bool? {
        guard let space = space(on: screen), let raw = rawTheme(space: space) else { return nil }
        return MenuBarTheme.isDark(rawValue: raw)
    }

    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    private static let spaceTypeCall: SpaceType? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let call = dlsym(handle, "SLSSpaceGetType") else { return nil }
        return unsafeBitCast(call, to: SpaceType.self)
    }()

    /// Whether `screen` is showing an app in full screen, where macOS keeps
    /// the menu bar away until the pointer reaches the top edge. The window
    /// server's type for such a desktop is 4 (0 for an ordinary one; measured
    /// on macOS 27, 2026-11-11). False when it can't say.
    static func isFullScreen(on screen: NSScreen?) -> Bool {
        guard let calls, let spaceTypeCall, let space = space(on: screen) else { return false }
        return spaceTypeCall(calls.mainConnection(), space) == 4
    }

    private typealias CopyActiveBar = @convention(c) (Int32) -> Unmanaged<CFString>?

    private static let activeBarCall: CopyActiveBar? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let call = dlsym(handle, "SLSCopyActiveMenuBarDisplayIdentifier") else { return nil }
        return unsafeBitCast(call, to: CopyActiveBar.self)
    }()

    /// Whether `screen` has the active menu bar, the one macOS doesn't dim; nil
    /// when the window server can't say, and the ••• then stays at full strength.
    static func isActiveBar(on screen: NSScreen) -> Bool? {
        guard let calls, let activeBarCall,
              let number = screen.displayID,
              let active = activeBarCall(calls.mainConnection())?.takeRetainedValue() as String?,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let name = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return active.caseInsensitiveCompare(name) == .orderedSame
    }
}
