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

    /// The window server's type for the desktop `screen` shows: 4 for an app
    /// in full screen, 0 for an ordinary desktop (measured on macOS 27,
    /// 2026-11-11). Nil when it can't say.
    static func spaceType(on screen: NSScreen?) -> Int32? {
        #if YOUNGBAR_TESTHOOKS
        if ProcessInfo.processInfo.environment["YOUNGBAR_PRETEND_FULLSCREEN"] == "1" { return 4 }
        #endif
        guard let calls, let spaceTypeCall, let space = space(on: screen) else { return nil }
        return spaceTypeCall(calls.mainConnection(), space)
    }

    /// Whether the front window on `screen` says it is in full screen
    /// (`AXFullScreen`), asked of the app that owns it. Window bounds can't
    /// tell: on a notched display a full-screen window starts below the
    /// notch, exactly where a window filling an ordinary desktop starts.
    ///
    /// With the desktop type, this says an app is in full screen (macOS keeps
    /// the menu bar away until the pointer reaches the top edge). The type
    /// alone was measured on one Mac only, and a wrong 4 leaves the •••
    /// invisible until the pointer reaches the bar (a user's ••• was gone
    /// with 0.2.1-beta.1, issue #10).
    static func hasFullScreenWindow(on screen: NSScreen) -> Bool {
        #if YOUNGBAR_TESTHOOKS
        if ProcessInfo.processInfo.environment["YOUNGBAR_PRETEND_FULLSCREEN_WINDOW"] == "1" { return true }
        #endif
        guard let number = screen.displayID,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let display = CGDisplayBounds(number)
        let own = ProcessInfo.processInfo.processIdentifier
        // Front to back: the first ordinary window on this display.
        let front = list.first { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != own,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return display.contains(CGPoint(x: bounds.midX, y: bounds.midY))
        }
        guard let pid = front?[kCGWindowOwnerPID as String] as? Int32 else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        return windows.contains { window in
            var full: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full) == .success,
                  (full as? Bool) == true else { return false }
            var position: CFTypeRef?, size: CFTypeRef?
            var origin = CGPoint.zero, extent = CGSize.zero
            if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
               AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
               let position, let size {
                AXValueGetValue(position as! AXValue, .cgPoint, &origin)
                AXValueGetValue(size as! AXValue, .cgSize, &extent)
                return display.contains(CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2))
            }
            return true
        }
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
