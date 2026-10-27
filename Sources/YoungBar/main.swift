// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ScreenCaptureKit
import ServiceManagement
import UniformTypeIdentifiers
import PelmetCore
import PelmetEngine

@MainActor
final class BarControlButton: NSButton {
    var rightClick: (() -> Void)?
    var hover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func rightMouseDown(with event: NSEvent) {
        rightClick?()
    }
}

@MainActor
final class BarControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class BarApp: NSObject, NSApplicationDelegate {
    private let engine = AgentBarEngine()
    private let usageTelemetry = UsageTelemetry()
    private var statusItem: NSStatusItem!
    private var knownBundles: [String: String] = [:]
    private var modes: [String: Int] = {
        if let saved = UserDefaults.standard.dictionary(forKey: "itemModes") as? [String: Int] { return saved }
        return Dictionary(uniqueKeysWithValues: (UserDefaults.standard.stringArray(forKey: "hiddenBundles") ?? []).map { ("bundle:\($0)", 1) })
    }()
    private var hiddenBundles: Set<String> {
        Set(modes.filter { $0.value > 0 }.keys.compactMap { ItemID(rawValue: $0).bundleID })
    }
    private var savedOrder = UserDefaults.standard.stringArray(forKey: "itemOrder") ?? []
    private var catalog: [String: ObservedItem] = [:]
    private var presentKeys: Set<String> = []
    private var shownUntil: [ItemID: Date] = [:]
    private var settings: BarSettings?
    private var busy = false
    private var refreshing = false
    private var includeAlwaysHidden = false
    private var feedback = ""
    private var options = UserDefaults.standard.dictionary(forKey: "barOptions") as? [String: Int] ?? [:]
    private var isHovered = false
    private var mouseMonitor: Any?
    private var currentFrames: [CGRect] = []
    private var revealSeconds: TimeInterval { TimeInterval(options["revealSeconds"] ?? 20) }
    private var expanded = false
    private var started = false
    private var previousSessionCrashed = UserDefaults.standard.bool(forKey: "sessionActive")
    private var rescueRequested = CommandLine.arguments.contains("--reveal-all")
    private var timer: Timer?
    private var controlPanel: NSPanel?
    private var controlButton: BarControlButton?
    private var shelfPanel: NSPanel?
    private var gearButton: BarControlButton?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var shelfState: String?
    /// After an item is opened from the strip, the strip stays where it was
    /// (no re-centring on the control as the revealed item shifts it) until
    /// the strip closes.
    private var shelfAnchored = false
    /// The strip's own synthetic click on the revealed item is not a click
    /// outside the strip.
    private var ignoreOutsideUntil: Date?
    /// Set by `YOUNGBAR_SETTINGS_PREVIEW`: only the settings window runs.
    private var previewOnly = false
    private lazy var customIconImage: NSImage? = NSImage(contentsOf: customControlIconURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let preview = ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGS_PREVIEW"] {
            // Must return before the session marker below: a preview runs
            // beside the live instance and shares its defaults.
            previewOnly = true
            if preview == "en" { options["language"] = 1 } else if preview == "zh" { options["language"] = 0 }
            // In memory only: the live instance shares these defaults.
            if let name = ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGS_PREVIEW_THEME"],
               let theme = ["blue", "pink", "yellow", "clear"].firstIndex(of: name) {
                options["themeColor"] = theme
                options["themeScope"] = 0
            }
            L10n.current = Language(rawValue: options["language"] ?? 0) ?? .chinese
            NSApp.setActivationPolicy(.accessory)
            Task { await runSettingsPreview() }
            return
        }
        L10n.current = Language(rawValue: options["language"] ?? 0) ?? .chinese
        UserDefaults.standard.set(true, forKey: "sessionActive")
        writeJSON(["args": CommandLine.arguments, "rescue": rescueRequested,
                   "crashed": previousSessionCrashed], name: "launch.json")
        NSApp.setActivationPolicy(.accessory)
        if !rescueRequested { usageTelemetry.start() }
        // A previous synthetic drag can leave the global mouse association
        // off; reset it before any UI is shown.
        CGAssociateMouseAndMouseCursorPosition(1)
        CGDisplayShowCursor(CGMainDisplayID())
        applyAppearance()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "•••"
        statusItem.button?.toolTip = L10n.t(
            "YoungBar：点击查看收纳的图标；右键选择要收纳的应用",
            "YoungBar: click to show concealed icons; right-click to choose apps")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.outsideClick() }
        }
        registerHotKey()
        refreshLoginItemIfMoved()
        if !AXIsProcessTrusted() { showWindow() }
        Task {
            await installControlPanelWhenReady()
            await refresh()
            Diagnostics.write(app: self, snapshot: nil)
            if ProcessInfo.processInfo.environment["YOUNGBAR_TOPSHOT"] == "1" {
                try? await Task.sleep(for: .milliseconds(1800))
                await captureScreen(to: "top-full.png")
            }
            if let directory = ProcessInfo.processInfo.environment["YOUNGBAR_SNAPSHOT_DIR"] {
                showWindow()
                try? await Task.sleep(for: .milliseconds(500))
                await settings?.writeSnapshots(to: directory)
                writeShelfSnapshot(to: directory)
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_SELFTEST"] == "1" {
                await runSelfTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_INTERACTIONTEST"] == "1" {
                await runInteractionTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_BULKTEST"] == "1" {
                await runBulkTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_SPACINGTEST"] == "1" {
                runSpacingTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_MENUTEST"] == "1" {
                await runMenuTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_ORDERTEST"] == "1" {
                await runOrderTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_SHELFOPENTEST"] == "1" {
                await runShelfOpenTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_EXPANDEDSHOT"] == "1" {
                showShelf()
                try? await Task.sleep(for: .milliseconds(500))
                await captureScreen(to: "expanded-full.png")
                closeShelf()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_GEARTEST"] == "1" {
                await runGearTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_PINNEDTEST"] == "1" {
                await runPinnedHideTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_HOTKEYTEST"] == "1" {
                await runHotKeyTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_ABOUTTEST"] == "1" {
                await runAboutTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_CONCEALTEST"] == "1" {
                await runConcealTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGSUITEST"] == "1" {
                await runSettingsUITest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGSCLICKTEST"] == "1" {
                await runSettingsClickTest()
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_HITTEST"] == "1" {
                showWindow()
                try? await Task.sleep(for: .milliseconds(500))
                if let info = settings?.loginHitTest() {
                    writeJSON(info, name: "hittest.json")
                }
            }
            if ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGSSHOT"] == "1" {
                showWindow()
                try? await Task.sleep(for: .milliseconds(700))
                if let window = settings?.windowForCapture {
                    await captureWindow(window, to: "settings-window.png")
                }
            }
            if let raw = ProcessInfo.processInfo.environment["YOUNGBAR_CLOSEWINDOW_PID"], let pid = pid_t(raw) {
                await runWindowCleanup(pid: pid)
            }
            if options["keepShelfOpen"] == 1 { showShelf() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if previewOnly { return .terminateNow }
        if rescueRequested {
            UserDefaults.standard.set(false, forKey: "sessionActive")
            return .terminateNow
        }
        guard started, AXIsProcessTrusted() else {
            UserDefaults.standard.set(false, forKey: "sessionActive")
            return .terminateNow
        }
        Task { @MainActor in
            await revealEverything()
            UserDefaults.standard.set(false, forKey: "sessionActive")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !previewOnly else { return }
        UserDefaults.standard.set(false, forKey: "sessionActive")
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        timer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        Task { await engine.stop() }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || options["leftClickMenu"] == 1 {
            showConfigurationMenu()
            return
        }
        toggleShelf()
    }

    @objc private func toggleShelf() {
        guard AXIsProcessTrusted(), AssessmentMode.isAvailable else {
            showConfigurationMenu()
            return
        }
        guard !busy else { return }
        if expanded {
            closeShelf()
        } else {
            let event = NSApp.currentEvent
            includeAlwaysHidden = event?.type == .leftMouseUp && event?.modifierFlags.contains(.option) == true
            Task {
                if options["nativeExpand"] == 1 && !includeAlwaysHidden {
                    await refresh()
                    await revealHiddenSection()
                } else {
                    // The strip shows app icons; never reveal items to open it.
                    showShelf()
                    await refresh()
                }
            }
        }
    }

    private var themeColor: ThemeColor {
        ThemeColor(rawValue: options["themeColor"] ?? 0) ?? .blue
    }

    private var stripOpacity: CGFloat {
        CGFloat(stripOpacityPercent(options)) / 100
    }

    private var themeScope: ThemeScope {
        ThemeScope(rawValue: options["themeScope"] ?? 0) ?? .both
    }

    private func applyAppearance() {
        let mode = AppearanceMode(rawValue: options["appearanceMode"] ?? 0) ?? .system
        NSApp.appearance = mode.appearance
        NSApp.applicationIconImage = themeIcon(themeColor)
    }

    /// Carbon global hotkey: Ctrl-Option-B toggles the strip without AX
    /// focus or the mouse. The handler runs on the main event loop.
    private func registerHotKey() {
        var hotKeyID = EventHotKeyID(signature: OSType(0x5942_4152), id: 1) // "YBAR"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_B),
                                        UInt32(controlKey | optionKey),
                                        hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            NSLog("YoungBar hotkey registration failed: \(status)")
            return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let app = Unmanaged<BarApp>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { app.toggleShelf() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
    }

    private func refresh() async {
        guard !busy, !refreshing, AXIsProcessTrusted(), AssessmentMode.isAvailable else { return }
        refreshing = true
        defer { refreshing = false }
        if !started {
            await engine.start()
            await engine.setSteadyExtras(false)
            if previousSessionCrashed || rescueRequested {
                await revealEverything()
                let wasCrashed = previousSessionCrashed
                previousSessionCrashed = false
                UserDefaults.standard.set(false, forKey: "sessionActive")
                let recovered = await engine.freshSnapshot()
                writeJSON(["at": ISO8601DateFormatter().string(from: Date()),
                           "crashed": wasCrashed,
                           "rescue": rescueRequested,
                           "concealedAfterReveal": recovered.concealed.count],
                          name: "recovery.json")
                if rescueRequested {
                    started = true
                    NSApp.terminate(nil)
                    return
                }
                feedback = L10n.t("上次未正常退出，已先恢复所有菜单栏图标",
                                  "Previous session ended unexpectedly; restored all menu-bar icons first")
            }
            await engine.setModel(currentModel())
            started = true
        }
        let expired = Set(shownUntil.filter { $0.value <= Date() }.keys)
        if !expired.isEmpty {
            for id in expired { shownUntil[id] = nil }
            await engine.conceal(items: expired)
        }
        let snapshot = await engine.freshSnapshot()
        remember(snapshot)
        currentFrames = snapshot.items.compactMap(\.frame)
        positionControlBesideMenuIcons(in: snapshot)
        if expanded { populateShelf() }
        renderWindow()
        Diagnostics.write(app: self, snapshot: snapshot)
    }

    /// Opt-in live check (`YOUNGBAR_SELFTEST=1`): reveal one concealed item,
    /// wait for a frame, conceal it again, and record both observations.
    /// It restores the item to its original concealed state.
    private func runSelfTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        let before = await engine.freshSnapshot()
        result["concealedBefore"] = before.concealed.count
        result["visibleBefore"] = before.items.count
        guard let target = before.concealed.first(where: {
            $0.bundleID != nil && MenuBarPolicy.isSectionManageable($0)
        }) else {
            result["error"] = "no concealed app item to test"
            writeSelfTest(result)
            return
        }
        result["target"] = target.sectionKey.rawValue
        await engine.reveal(items: [target])
        try? await Task.sleep(for: .milliseconds(700))
        let shown = await engine.freshSnapshot()
        let frame = shown.items.first { $0.id == target }?.frame
        result["appeared"] = frame != nil
        result["frameAfterReveal"] = frame.map { "\($0.origin.x),\($0.origin.y) \($0.width)x\($0.height)" } ?? ""
        // Exercise the real timed-reveal path. Tests use 2 s by default;
        // YOUNGBAR_SELFTEST_SECONDS=20 waits the production default out.
        let expiry = Double(ProcessInfo.processInfo.environment["YOUNGBAR_SELFTEST_SECONDS"] ?? "") ?? 2
        result["expirySeconds"] = expiry
        shownUntil[target] = Date().addingTimeInterval(expiry)
        try? await Task.sleep(for: .seconds(expiry + 1.5))
        var after = await engine.freshSnapshot()
        let autoHidden = after.concealed.contains(target)
        result["autoHidden"] = autoHidden
        if !autoHidden { await engine.conceal(items: [target]) }
        try? await Task.sleep(for: .milliseconds(500))
        after = await engine.freshSnapshot()
        result["concealedAfter"] = after.concealed.count
        result["stillVisible"] = after.items.filter { $0.id.sectionKey == target.sectionKey }.map(\.id.rawValue)
        result["goneAgain"] = !after.items.contains { $0.id == target }
        result["passed"] = (frame != nil) && autoHidden && (result["goneAgain"] as? Bool ?? false)
        writeSelfTest(result)
    }

    /// Opt-in (`YOUNGBAR_INTERACTIONTEST=1`): drives the real shelf click path
    /// for one concealed item, counts menu-level windows, then presses Escape
    /// and reconceals the item. It records the production reveal window too.
    private func runInteractionTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        guard AXIsProcessTrusted(), AssessmentMode.isAvailable else {
            result["error"] = "accessibility or assessment unavailable"
            writeInteractionTest(result)
            return
        }
        closeShelf()
        if let panel = controlPanel, let screen = panel.screen ?? NSScreen.main {
            let point = CGPoint(x: panel.frame.midX, y: screen.frame.maxY - panel.frame.midY)
            await ItemMover.shieldedClick(at: point)
            try? await Task.sleep(for: .milliseconds(700))
            result["controlClickOpenedShelf"] = expanded
            if expanded { closeShelf() }
            for _ in 0..<40 where busy {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        showShelf()
        // Some saved entries no longer own a menu-bar item. Pick one that
        // actually materialises before driving the click path.
        var chosen: String?
        for candidate in shelfKeys() {
            guard let candidateItem = catalog[candidate] else { continue }
            await engine.reveal(items: [candidateItem.id])
            let probe = await settledSnapshot(for: [candidateItem.id])
            if probe.items.contains(where: { $0.id == candidateItem.id }) {
                chosen = candidate
                break
            }
            await engine.conceal(items: [candidateItem.id])
        }
        guard let key = chosen, let item = catalog[key] else {
            result["error"] = "no revealable shelf item to click"
            closeShelf()
            writeInteractionTest(result)
            return
        }
        result["target"] = key
        let targetPID = item.id.bundleID.flatMap { bundle in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundle }?.processIdentifier
        }
        result["targetAppPID"] = targetPID
        result["targetWindowsBefore"] = targetPID.map { self.targetWindows(pid: $0) } ?? []
        try? await Task.sleep(for: .milliseconds(300))
        let before = menuWindowCount()
        let button = BarControlButton(frame: .zero)
        button.identifier = .init(key)
        for _ in 0..<40 where busy {
            try? await Task.sleep(for: .milliseconds(150))
        }
        result["busyBeforePress"] = busy
        pressShelfItem(button)
        result["busyAfterPressCall"] = busy
        for _ in 0..<40 where busy {
            try? await Task.sleep(for: .milliseconds(150))
        }
        try? await Task.sleep(for: .milliseconds(600))
        let after = menuWindowCount()
        result["menuWindowsBefore"] = before
        result["menuWindowsAfter"] = after
        let focus = focusedMenuOwner()
        result["focusedRole"] = focus.role
        result["focusedMenuOwnerPID"] = focus.pid
        result["focusedMenuOwnerName"] = focus.pid.flatMap {
            NSRunningApplication(processIdentifier: $0)?.localizedName
        } ?? ""
        // CGWindowList does not expose status-item menus as ordinary windows;
        // an open menu takes AX focus in the owning app instead.
        let windowsAfterClick = targetPID.map { self.targetWindows(pid: $0) } ?? []
        result["targetWindowsAfter"] = windowsAfterClick
        result["menuOpened"] = focus.pid != nil && focus.pid == targetPID
        result["clickOpenedTargetUI"] = (focus.pid == targetPID) || (windowsAfterClick.count > 0)
        result["revealWindowSeconds"] = shownUntil[item.id].map { Int($0.timeIntervalSinceNow.rounded()) } ?? 0
        result["feedback"] = feedback
        let probeKeys = await engine.freshSnapshot().items.compactMap { $0.id.bundleID }
        result["visibleMatchesTargetBundle"] = probeKeys.filter { $0 == item.id.bundleID }.count
        postEscape()
        try? await Task.sleep(for: .milliseconds(700))
        result["menuWindowsAfterEscape"] = menuWindowCount()
        result["menuClosedAfterEscape"] = focusedMenuOwner().pid != targetPID
        result["targetWindowsAfterEscape"] = targetPID.map { self.targetWindows(pid: $0) } ?? []
        if (result["targetWindowsBefore"] as? [[String: Any]])?.isEmpty == true {
            NSRunningApplication(processIdentifier: targetPID ?? 0)?.activate(options: [.activateAllWindows])
            try? await Task.sleep(for: .milliseconds(350))
            postCommandW()
            try? await Task.sleep(for: .milliseconds(500))
            var remaining = targetPID.map { self.targetWindows(pid: $0) } ?? []
            if !remaining.isEmpty {
                closeWindows(pid: targetPID)
                try? await Task.sleep(for: .milliseconds(500))
                remaining = targetPID.map { self.targetWindows(pid: $0) } ?? []
            }
            result["windowsAfterCleanup"] = remaining
        }
        shownUntil[item.id] = nil
        await engine.conceal(items: [item.id])
        try? await Task.sleep(for: .milliseconds(500))
        result["concealedAfterTest"] = !(await engine.freshSnapshot()).items.contains { $0.id == item.id }
        closeShelf()
        writeInteractionTest(result)
    }

    /// Opt-in (`YOUNGBAR_SPACINGTEST=1`): writes the 3/3 spacing used by
    /// iBar's 小间隙, reads it back, then removes both keys again.
    private func runSpacingTest() {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        do {
            try runDefaults(["-currentHost", "write", "-g", "NSStatusItemSelectionPadding", "3"])
            try runDefaults(["-currentHost", "write", "-g", "NSStatusItemSpacing", "3"])
            result["paddingReadBack"] = try readDefaults(["-currentHost", "read", "-g", "NSStatusItemSelectionPadding"])
            result["spacingReadBack"] = try readDefaults(["-currentHost", "read", "-g", "NSStatusItemSpacing"])
            try runDefaults(["-currentHost", "remove", "-g", "NSStatusItemSelectionPadding"])
            try runDefaults(["-currentHost", "remove", "-g", "NSStatusItemSpacing"])
            result["restored"] = true
            result["passed"] = (result["paddingReadBack"] as? String) == "3"
                && (result["spacingReadBack"] as? String) == "3"
        } catch {
            result["error"] = error.localizedDescription
            result["passed"] = false
        }
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("spacingtest.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func readDefaults(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "YoungBar", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }

    /// One-off cleanup for a window a test opened (YOUNGBAR_CLOSEWINDOW_PID).
    private func runWindowCleanup(pid: pid_t) async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "pid": pid]
        result["before"] = targetWindows(pid: pid)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        try? await Task.sleep(for: .milliseconds(500))
        postCommandW()
        try? await Task.sleep(for: .milliseconds(700))
        closeWindows(pid: pid)
        try? await Task.sleep(for: .milliseconds(500))
        let remaining = targetWindows(pid: pid)
        result["after"] = remaining
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("cleanup.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func postCommandW() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: down) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    private func closeWindows(pid: pid_t?) {
        guard let pid else { return }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
               let button {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            } else {
                var minimized = true as CFBoolean
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized)
            }
        }
    }

    private func targetWindows(pid: pid_t) -> [[String: Any]] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid else { return nil }
            return [
                "name": window[kCGWindowName as String] as? String ?? "",
                "layer": window[kCGWindowLayer as String] as? Int ?? -1,
                "bounds": window[kCGWindowBounds as String] as? String ?? "",
            ]
        }
    }

    private func focusedMenuOwner() -> (role: String, pid: pid_t?) {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return ("", nil)
        }
        let ax = element as! AXUIElement
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(ax, kAXRoleAttribute as CFString, &roleValue)
        var pid: pid_t = 0
        AXUIElementGetPid(ax, &pid)
        return ((roleValue as? String) ?? "", pid == 0 ? nil : pid)
    }

    private func menuWindowCount() -> Int {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter { (($0[kCGWindowLayer as String] as? Int) ?? 0) >= 100 }.count
    }

    private func postEscape() {
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    private func writeInteractionTest(_ result: [String: Any]) {
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("interactiontest.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("YoungBar interaction test write failed: \(error)")
        }
    }

    /// Opt-in (`YOUNGBAR_MENUTEST=1`): temporarily hides the input-source item,
    /// clicks it from the strip, and checks that a real menu opened and Escape
    /// closed it. The item's original visibility is restored afterwards.
    private func runMenuTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        guard let key = catalog.first(where: { $0.value.id.bundleID == "com.apple.TextInputMenuAgent" })?.key,
              let item = catalog[key] else {
            result["error"] = "input-source item not present"
            writeJSON(result, name: "menutest.json")
            return
        }
        let original = modes[key] ?? 0
        result["target"] = key
        result["originalMode"] = original
        modes[key] = 1
        UserDefaults.standard.set(modes, forKey: "itemModes")
        await engine.conceal()
        await engine.setModel(currentModel())
        try? await Task.sleep(for: .milliseconds(700))
        result["concealedBeforeClick"] = (await engine.freshSnapshot()).concealed.contains(item.id)

        showShelf()
        let button = BarControlButton(frame: .zero)
        button.identifier = .init(key)
        for _ in 0..<40 where busy { try? await Task.sleep(for: .milliseconds(150)) }
        pressShelfItem(button)
        for _ in 0..<40 where busy { try? await Task.sleep(for: .milliseconds(150)) }
        try? await Task.sleep(for: .milliseconds(700))

        let targetPID = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.TextInputMenuAgent" }?.processIdentifier
        let focus = focusedMenuOwner()
        result["focusRole"] = focus.role
        result["focusOwner"] = focus.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? ""

        // The input-source menu is not exposed as AXFocusedUIElement; probe
        // the point just below the item instead.
        var probePoint: CGPoint?
        if let frame = (await engine.freshSnapshot()).items.first(where: { $0.id == item.id })?.frame {
            probePoint = CGPoint(x: frame.midX, y: frame.maxY + 40)
        }
        if let probePoint {
            let probe = elementInfo(at: probePoint)
            result["menuElementRole"] = probe.role
            result["menuElementOwner"] = probe.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? ""
            result["menuOpened"] = probe.role.hasPrefix("AXMenu")
        }
        await captureScreen(to: "menutest-open.png")

        postEscape()
        try? await Task.sleep(for: .milliseconds(700))
        if let probePoint {
            let probe = elementInfo(at: probePoint)
            result["menuElementRoleAfterEscape"] = probe.role
            result["menuClosed"] = !probe.role.hasPrefix("AXMenu")
        }
        await captureScreen(to: "menutest-closed.png")
        result["targetPID"] = targetPID

        shownUntil[item.id] = nil
        modes[key] = original
        UserDefaults.standard.set(modes, forKey: "itemModes")
        await engine.conceal()
        await engine.setModel(currentModel())
        try? await Task.sleep(for: .milliseconds(700))
        result["restoredMode"] = modes[key] == original
        result["passed"] = (result["menuOpened"] as? Bool == true)
            && (result["menuClosed"] as? Bool == true)
            && (result["restoredMode"] as? Bool == true)
        closeShelf()
        writeJSON(result, name: "menutest.json")
    }

    /// Opt-in (`YOUNGBAR_ORDERTEST=1`): swaps two adjacent app items with the
    /// same shielded ⌘-drag the UI uses, verifies the new order, then drags
    /// them back and verifies the original order.
    private func runOrderTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        guard let leftKey = catalog.first(where: { $0.value.id.bundleID == "com.tencent.xinWeChat" })?.key,
              let rightKey = catalog.first(where: { $0.value.id.bundleID == "com.steipete.codexbar" })?.key else {
            result["error"] = "test pair not present"
            writeJSON(result, name: "ordertest.json")
            return
        }
        let before = await engine.freshSnapshot()
        guard let left = before.items.first(where: { $0.id.sectionKey.rawValue == leftKey })?.frame,
              let right = before.items.first(where: { $0.id.sectionKey.rawValue == rightKey })?.frame,
              right.midX > left.midX else {
            result["error"] = "test pair has no usable frames"
            writeJSON(result, name: "ordertest.json")
            return
        }
        result["leftKey"] = leftKey
        result["rightKey"] = rightKey
        result["before"] = "\(left.midX) < \(right.midX)"
        controlPanel?.ignoresMouseEvents = true
        await ItemMover.cmdDrag(from: CGPoint(x: right.midX, y: right.midY),
                                to: CGPoint(x: left.minX - 3, y: left.midY))
        try? await Task.sleep(for: .milliseconds(900))
        let moved = await engine.freshSnapshot()
        guard let leftAfter = moved.items.first(where: { $0.id.sectionKey.rawValue == leftKey })?.frame,
              let rightAfter = moved.items.first(where: { $0.id.sectionKey.rawValue == rightKey })?.frame else {
            controlPanel?.ignoresMouseEvents = false
            result["error"] = "frames missing after drag"
            writeJSON(result, name: "ordertest.json")
            return
        }
        result["moved"] = rightAfter.midX < leftAfter.midX
        result["afterMove"] = "\(leftAfter.midX) ? \(rightAfter.midX)"
        await ItemMover.cmdDrag(from: CGPoint(x: rightAfter.midX, y: rightAfter.midY),
                                to: CGPoint(x: leftAfter.maxX + 3, y: leftAfter.midY))
        try? await Task.sleep(for: .milliseconds(900))
        let restored = await engine.freshSnapshot()
        let leftRestored = restored.items.first(where: { $0.id.sectionKey.rawValue == leftKey })?.frame
        let rightRestored = restored.items.first(where: { $0.id.sectionKey.rawValue == rightKey })?.frame
        result["restored"] = (leftRestored.map { left in rightRestored.map { $0.midX > left.midX } ?? false }) ?? false
        controlPanel?.ignoresMouseEvents = false
        result["passed"] = (result["moved"] as? Bool == true) && (result["restored"] as? Bool == true)
        writeJSON(result, name: "ordertest.json")
    }

    private func elementInfo(at point: CGPoint) -> (role: String, pid: pid_t?) {
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
              let element else { return ("", nil) }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return ((role as? String) ?? "", pid == 0 ? nil : pid)
    }

    private func captureWindow(_ window: NSWindow, to name: String) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let scale = window.backingScaleFactor
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try data.write(to: Diagnostics.url.deletingLastPathComponent().appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("YoungBar window capture failed: \(error)")
        }
    }

    private func captureScreen(to name: String) async {
        guard CGPreflightScreenCaptureAccess(), let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { return }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("YoungBar screenshot failed: \(error)")
        }
    }

    private func writeJSON(_ value: [String: Any], name: String) {
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent(name)
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func writeShelfSnapshot(to directory: String) {
        showShelf()
        defer { closeShelf() }
        guard let view = shelfPanel?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? data.write(to: base.appendingPathComponent("shelf.png"))
    }

    private func writeSelfTest(_ result: [String: Any]) {
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("selftest.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("YoungBar selftest write failed: \(error)")
        }
    }

    private func remember(_ snapshot: EngineSnapshot) {
        // A saved mode can outlive the menu-bar item (app quit or updated while
        // concealed). Only keys in the live snapshot are presentable.
        var present: Set<String> = []
        for item in snapshot.items { present.insert(item.id.sectionKey.rawValue) }
        for id in snapshot.concealed { present.insert(id.sectionKey.rawValue) }
        presentKeys = present

        var orderChanged = false
        let deduped = uniqueKeys(savedOrder)
        if deduped.count != savedOrder.count {
            savedOrder = deduped
            orderChanged = true
        }
        for item in snapshot.items.sorted(by: { ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude) })
        where item.id.bundleID != Bundle.main.bundleIdentifier && MenuBarPolicy.isSectionManageable(item.id) {
            let key = item.id.sectionKey.rawValue
            catalog[key] = item
            if !savedOrder.contains(key), let frame = item.frame {
                // New items belong where they actually sit, not at the end.
                let index = savedOrder.firstIndex { existing in
                    guard let existingFrame = catalog[existing]?.frame else { return false }
                    return existingFrame.minX > frame.minX
                } ?? savedOrder.endIndex
                savedOrder.insert(key, at: index)
                orderChanged = true
            }
            if let bundle = item.id.bundleID, bundle != PelmetBundle.agentID {
                knownBundles[bundle] = item.appName ?? appName(for: bundle)
            }
        }
        for id in snapshot.concealed where catalog[id.sectionKey.rawValue] == nil {
            catalog[id.sectionKey.rawValue] = ObservedItem(id: id, frame: nil, appName: nil)
            if !savedOrder.contains(id.sectionKey.rawValue) {
                savedOrder.append(id.sectionKey.rawValue)
                orderChanged = true
            }
        }
        for key in modes.keys where catalog[key] == nil {
            catalog[key] = ObservedItem(id: ItemID(rawValue: key), frame: nil, appName: nil)
            if !savedOrder.contains(key) {
                savedOrder.append(key)
                orderChanged = true
            }
        }
        reconcileVisibleOrder(snapshot)
        let finalOrder = uniqueKeys(savedOrder)
        if finalOrder != savedOrder { savedOrder = finalOrder; orderChanged = true }
        if orderChanged { UserDefaults.standard.set(savedOrder, forKey: "itemOrder") }
    }

    /// The table is the user's ordering model, but it must not drift from the
    /// real bar. Whenever the visible items disagree with their saved order,
    /// rewrite just those slots to the actual left-to-right order and persist.
    private func reconcileVisibleOrder(_ snapshot: EngineSnapshot) {
        guard !busy else { return }
        let actual = uniqueKeys(snapshot.items
            .filter { $0.frame != nil }
            .sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
            .map { $0.id.sectionKey.rawValue })
            .filter { savedOrder.contains($0) }
        guard actual.count > 1 else { return }
        let savedVisible = savedOrder.filter { actual.contains($0) }
        guard savedVisible != actual else { return }
        var iterator = actual.makeIterator()
        savedOrder = savedOrder.map { actual.contains($0) ? (iterator.next() ?? $0) : $0 }
        UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        Task { await engine.setModel(currentModel()) }
    }

    private func name(for key: String) -> String {
        let id = catalog[key]?.id ?? ItemID(rawValue: key)
        if let system = MenuBarPolicy.systemItem(for: id) {
            switch system {
            case .battery: return L10n.t("电池", "Battery")
            case .bluetooth: return L10n.t("蓝牙", "Bluetooth")
            case .clock: return L10n.t("日期与时间", "Date & Time")
            case .displays: return L10n.t("显示器", "Displays")
            case .keyboard: return L10n.t("输入法", "Input")
            case .volume: return L10n.t("声音", "Sound")
            case .wifi: return "Wi-Fi"
            case .screenMirroring: return L10n.t("屏幕镜像", "Screen Mirroring")
            case .primaryBentoBox: return L10n.t("控制中心", "Control Center")
            }
        }
        if let bundle = id.bundleID { return knownBundles[bundle] ?? appName(for: bundle) }
        return key
    }

    private func uniqueKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func orderedKeys() -> [String] {
        savedOrder.filter { catalog[$0] != nil && presentKeys.contains($0) }
            + catalog.keys.filter { !savedOrder.contains($0) && presentKeys.contains($0) }.sorted()
    }

    private func appName(for bundle: String) -> String {
        if let name = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle })?.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundle
    }

    private func showConfigurationMenu() {
        let menu = NSMenu(title: "YoungBar")
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: L10n.t("开启辅助功能权限…", "Open Accessibility…"), action: #selector(requestAccessibility), keyEquivalent: "")
        } else if !AssessmentMode.isAvailable {
            menu.addItem(withTitle: L10n.t("此系统上无法使用原生隐藏功能", "Native hiding is unavailable on this system"), action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: expanded ? L10n.t("收起收纳条", "Close strip") : L10n.t("打开收纳条", "Open strip"), action: #selector(toggleShelf), keyEquivalent: "")
            let shortcut = NSMenuItem(title: L10n.t("快捷键：⌃⌥B", "Shortcut: ⌃⌥B"), action: nil, keyEquivalent: "")
            shortcut.isEnabled = false
            menu.addItem(shortcut)
            menu.addItem(.separator())
            menu.addItem(withTitle: L10n.t("选择要隐藏的应用：", "Choose apps to conceal:"), action: nil, keyEquivalent: "")
            for bundle in knownBundles.keys.sorted(by: { (knownBundles[$0] ?? $0).localizedCompare(knownBundles[$1] ?? $1) == .orderedAscending }) {
                let item = NSMenuItem(title: knownBundles[bundle] ?? bundle, action: #selector(toggleBundle(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = bundle
                item.state = hiddenBundles.contains(bundle) ? .on : .off
                menu.addItem(item)
            }
            if knownBundles.isEmpty {
                menu.addItem(withTitle: L10n.t("正在读取菜单栏图标…", "Reading menu-bar items…"), action: nil, keyEquivalent: "")
            }
            let leftClick = NSMenuItem(title: L10n.t("左键点击显示菜单", "Show menu on left click"), action: #selector(toggleLeftClickMenu), keyEquivalent: "")
            leftClick.state = options["leftClickMenu"] == 1 ? .on : .off
            menu.addItem(leftClick)
            menu.addItem(.separator())
            menu.addItem(withTitle: L10n.t("全部隐藏（应用图标）", "Hide all (app icons)"), action: #selector(hideAllApps), keyEquivalent: "")
            menu.addItem(withTitle: L10n.t("全部显示", "Show all"), action: #selector(showAllApps), keyEquivalent: "")
            menu.addItem(withTitle: L10n.t("恢复我的收纳配置", "Restore my layout"), action: #selector(restoreAppModes), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: L10n.t("刷新图标列表", "Refresh item list"), action: #selector(refreshClicked), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("打开设置窗口", "Open Settings"), action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("关于 YoungBar", "About YoungBar"), action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("退出 YoungBar", "Quit YoungBar"), action: #selector(quit), keyEquivalent: "")
        for item in menu.items where item.action != nil && item.target == nil { item.target = self }
        if let event = NSApp.currentEvent, let button = controlButton ?? statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    private func installControlPanelWhenReady() async {
        for _ in 0..<15 {
            if installControlPanel() { return }
            try? await Task.sleep(for: .milliseconds(60))
        }
        // Keep the control reachable if the system never exposes the status
        // item's final frame before the hide assertion starts.
        guard let screen = NSScreen.main else { return }
        let fallback = NSRect(x: screen.frame.maxX - 88, y: screen.frame.maxY - 27,
                              width: 22, height: 22)
        makeControlPanel(at: fallback)
    }

    private func installControlPanel() -> Bool {
        guard let button = statusItem.button,
              let host = button.window,
              let screen = host.screen ?? NSScreen.main else { return false }
        let frame = host.convertToScreen(button.convert(button.bounds, to: nil))
        // The assessment interface can hand back a status-item window that
        // sits below the menu bar. Only accept a frame that is actually in it.
        guard frame.width > 0, frame.height > 0, frame.height <= 40,
              frame.minY >= screen.frame.maxY - 45,
              frame.midX >= screen.frame.minX + 30 else { return false }
        makeControlPanel(at: frame)
        return true
    }

    private func makeControlPanel(at frame: NSRect) {
        let size = NSSize(width: max(34, frame.width), height: max(24, frame.height))
        let hitFrame = NSRect(x: frame.midX - size.width / 2,
                              y: frame.midY - size.height / 2,
                              width: size.width, height: size.height)
        let panel = BarControlPanel(contentRect: hitFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        let control = BarControlButton(frame: NSRect(origin: .zero, size: size))
        control.title = ""
        control.image = currentControlIcon()
        control.imagePosition = .imageOnly
        control.imageScaling = .scaleProportionallyDown
        control.contentTintColor = (options["controlIcon"] ?? 0) == ControlIcon.symbols.count ? nil : .labelColor
        control.isBordered = false
        control.contentTintColor = .labelColor
        control.setAccessibilityLabel("YoungBar")
        control.target = self
        control.action = #selector(statusClicked)
        control.sendAction(on: [.leftMouseUp])
        control.hover = { [weak self] entered in
            guard let self else { return }
            isHovered = entered
            if entered && options["hoverExpand"] == 1 {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if isHovered && !expanded && !busy { toggleShelf() }
                }
            }
        }
        control.rightClick = { [weak self] in self?.showConfigurationMenu() }
        panel.contentView = control
        panel.makeKeyAndOrderFront(nil)
        controlPanel = panel
        controlButton = control
    }

    private func positionControlBesideMenuIcons(in snapshot: EngineSnapshot) {
        guard let panel = controlPanel,
              let screen = panel.screen ?? NSScreen.main else { return }
        let leadingIcon = snapshot.items.compactMap { item -> CGFloat? in
            guard let frame = item.frame,
                  item.id.bundleID != Bundle.main.bundleIdentifier,
                  frame.minX > screen.frame.midX,
                  frame.minX < screen.frame.maxX else { return nil }
            return frame.minX
        }.min()
        guard let leadingIcon else { return }
        let x = max(screen.frame.minX + 12, leadingIcon - panel.frame.width - 6)
        if abs(panel.frame.minX - x) > 1 {
            // Slide with the bar's own shift instead of jumping a beat later.
            let origin = NSPoint(x: x, y: panel.frame.minY)
            // (`animator()` on this panel never applied the move, leaving
            // the control wherever it was installed.)
            let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && abs(panel.frame.minX - x) < 200
            panel.setFrame(NSRect(origin: origin, size: panel.frame.size), display: true, animate: animate)
        }
        if expanded && !shelfAnchored { positionShelf() }
    }

    private func showShelf() {
        guard controlPanel != nil else { return }
        if shelfPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            shelfPanel = panel
        }
        expanded = true
        shelfAnchored = false
        // Above the menu bar while browsing; lowered while an item's own menu
        // or panel is open so that opens on top of the strip.
        shelfPanel?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        populateShelf()
        guard let shelfPanel else { return }
        positionShelf()
        shelfPanel.orderFrontRegardless()
        shelfPanel.makeKeyAndOrderFront(nil)
    }

    private func positionShelf() {
        guard let anchor = controlPanel, let shelfPanel,
              let screen = anchor.screen ?? NSScreen.main else { return }
        let width = shelfPanel.frame.width
        // Centred under the control.
        let x = min(max(anchor.frame.midX - width / 2, screen.frame.minX + 8), screen.frame.maxX - width - 8)
        shelfPanel.setFrameOrigin(NSPoint(x: x, y: anchor.frame.minY - shelfPanel.frame.height - 7))
    }

    private func closeShelf() {
        expanded = false
        shelfAnchored = false
        shelfPanel?.orderOut(nil)
    }

    private func shelfKeys() -> [String] {
        orderedKeys().filter { (modes[$0] ?? 0) == 1 || (includeAlwaysHidden && modes[$0] == 2) }
    }

    private func populateShelf() {
        guard let shelfPanel else { return }
        let keys = shelfKeys()
        let state = keys.joined(separator: "|")
        guard state != shelfState || shelfPanel.contentView == nil else { return }
        shelfState = state
        // Each item shows its app's own icon (or the system symbol): sharp at
        // any size, unlike a menu-bar crop.
        let widths = keys.map { _ in CGFloat(40) }
        let itemContentWidth = widths.reduce(16, +)
        let screenWidth = (controlPanel?.screen ?? NSScreen.main)?.frame.width ?? 800
        let gearWidth: CGFloat = 38
        let width = min(max(keys.isEmpty ? 150 : 100, itemContentWidth + gearWidth), screenWidth - 24)
        let height: CGFloat = 40
        shelfPanel.setContentSize(NSSize(width: width, height: height))
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let themed = themeScope != .interfaceOnly
        let themeForStrip: ThemeColor? = themed ? themeColor : nil
        let systemStrip = themeForStrip == nil || themeForStrip == .clear
        let lightStrip = systemStrip ? !isDark : false
        let iconColor: NSColor = lightStrip ? .black : .white

        // Every theme uses the same two layers: blur, then the theme colour at
        // the chosen opacity (100% is a solid strip). Clear keeps the blur only.
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = systemStrip ? (isDark ? .hudWindow : .menu) : .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        let tint = NSView(frame: effect.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = (systemStrip ? NSColor.clear
            : (themeForStrip?.strip ?? .clear).withAlphaComponent(stripOpacity)).cgColor
        effect.addSubview(tint)
        let background: NSView = effect
        let itemArea = width - gearWidth
        if keys.isEmpty {
            let label = NSTextField(labelWithString: L10n.t("没有收纳项目", "No concealed items"))
            label.textColor = iconColor; label.alignment = .center
            label.frame = NSRect(x: 8, y: 9, width: itemArea - 16, height: 22)
            background.addSubview(label)
        } else {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: itemArea, height: height))
            scroll.drawsBackground = false; scroll.borderType = .noBorder
            scroll.hasHorizontalScroller = itemContentWidth > itemArea
            scroll.scrollerStyle = .overlay
            let document = NSView(frame: NSRect(x: 0, y: 0, width: max(itemContentWidth, itemArea), height: height))
            var x: CGFloat = 8
            for (index, key) in keys.enumerated() {
                let button = BarControlButton(frame: NSRect(x: x, y: 2, width: widths[index], height: 36))
                button.title = ""; button.isBordered = false
                button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
                button.identifier = .init(key); button.target = self; button.action = #selector(pressShelfItem(_:))
                let image = fallbackImage(for: key)
                image?.size = NSSize(width: 22, height: 22)
                button.image = image
                button.toolTip = name(for: key)
                button.contentTintColor = iconColor
                button.setAccessibilityLabel(name(for: key))
                document.addSubview(button); x += widths[index]
            }
            scroll.documentView = document; background.addSubview(scroll)
        }

        let divider = NSView(frame: NSRect(x: itemArea, y: 8, width: 1, height: 24))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = iconColor.withAlphaComponent(0.18).cgColor
        background.addSubview(divider)

        let gear = BarControlButton(frame: NSRect(x: itemArea + 5, y: 6, width: 28, height: 28))
        gear.title = ""
        gear.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L10n.t("设置", "Settings"))
        gear.imagePosition = .imageOnly
        gear.imageScaling = .scaleProportionallyDown
        gear.isBordered = false
        gear.contentTintColor = iconColor
        gear.target = self
        gear.action = #selector(openSettingsFromShelf)
        gear.toolTip = L10n.t("打开设置", "Open Settings")
        gear.setAccessibilityLabel(L10n.t("设置", "Settings"))
        background.addSubview(gear)
        gearButton = gear
        shelfPanel.contentView = background
        positionShelf()
    }

    /// Clock and battery change continuously; a cached crop would show a
    /// stale time or percentage. They always use the symbol fallback.
    /// Orders the strip just below the frontmost window of `pid` that overlaps
    /// it, if there is one.
    private func tuckShelf(below pid: pid_t) {
        guard pid > 0, let shelfPanel, expanded else { return }
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let shelf = shelfPanel.frame
        let shelfCG = CGRect(x: shelf.minX, y: screenTop - shelf.maxY, width: shelf.width, height: shelf.height)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let panel = windows.first(where: { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  ((info[kCGWindowLayer as String] as? Int) ?? 0) < shelfPanel.level.rawValue,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            return rect.intersects(shelfCG)
        }), let number = panel[kCGWindowNumber as String] as? Int else { return }
        shelfPanel.level = NSWindow.Level(rawValue: (panel[kCGWindowLayer as String] as? Int) ?? 0)
        shelfPanel.order(.below, relativeTo: number)
    }

    private func fallbackImage(for key: String) -> NSImage? {
        let id = catalog[key]?.id ?? ItemID(rawValue: key)
        if let system = MenuBarPolicy.systemItem(for: id) {
            let symbols: [SystemItem: String] = [.battery: "battery.100percent", .bluetooth: "network", .clock: "clock", .displays: "display", .keyboard: "keyboard", .volume: "speaker.wave.2", .wifi: "wifi", .screenMirroring: "airplayvideo", .primaryBentoBox: "switch.2"]
            return NSImage(systemSymbolName: symbols[system] ?? "circle", accessibilityDescription: name(for: key))
        }
        return id.bundleID.flatMap { icon(for: $0) }
    }

    private func settledSnapshot(for ids: Set<ItemID>) async -> EngineSnapshot {
        var last = await engine.freshSnapshot()
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(100))
            let next = await engine.freshSnapshot()
            let a = last.items.filter { ids.contains($0.id) }.compactMap(\.frame)
            let b = next.items.filter { ids.contains($0.id) }.compactMap(\.frame)
            if a.count == ids.count, a == b { return next }
            last = next
        }
        return last
    }

    private func icon(for bundle: String) -> NSImage? {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        guard let url else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil) }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 28, height: 28)
        return image
    }

    @objc private func openSettingsFromShelf() {
        closeShelf()
        showWindow()
    }

    @objc private func pressShelfItem(_ button: NSButton) {
        guard !busy, let key = button.identifier?.rawValue, let item = catalog[key] else { return }
        // The strip stays where it is and the item's own menu or panel opens
        // next to it.
        flashPressed(button)
        shelfAnchored = true
        ignoreOutsideUntil = Date().addingTimeInterval(2)
        shelfPanel?.level = .floating
        let owner = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == item.id.bundleID }?.processIdentifier ?? 0
        if let element = pressableElement(for: key, item: item, pid: owner), pressOpensNearStrip(key) {
            // Third-party items take AXPress while still concealed: no
            // reveal (so nothing on the bar shifts), no pointer movement.
            // The press can block until a menu closes, so it runs off the
            // main actor with a short timeout.
            nonisolated(unsafe) let target = element
            Task.detached { _ = AXUIElementPerformAction(target, kAXPressAction as CFString) }
            Task {
                for delay in [350, 600] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    tuckShelf(below: owner)
                }
            }
            return
        }
        // System items (Wi-Fi, battery…) have no press action: reveal and
        // click, as iBar did, with the pointer hidden so it doesn't jump.
        busy = true
        Task {
            defer { busy = false }
            await engine.reveal(items: [item.id])
            shownUntil[item.id] = Date().addingTimeInterval(revealSeconds)
            let snapshot = await settledSnapshot(for: [item.id])
            positionControlBesideMenuIcons(in: snapshot)
            guard let frame = snapshot.items.first(where: { $0.id.sectionKey == item.id.sectionKey })?.frame else {
                // The saved entry can outlive its menu-bar item (app updated or
                // quit while concealed). Put it back instead of leaving it shown.
                shownUntil[item.id] = nil
                await engine.conceal(items: [item.id])
                feedback = L10n.t("没有读取到该项目的位置（已恢复收纳）", "Could not read the item position (concealed again)")
                renderWindow(force: true)
                return
            }
            NSCursor.hide()
            await ItemMover.shieldedClick(at: CGPoint(x: frame.midX, y: frame.midY))
            NSCursor.unhide()
            // Menus open above everything, but many items open an ordinary
            // window-level panel. Tuck the strip directly under it so the
            // panel is on top while the strip still covers other windows.
            for delay in [350, 600] {
                try? await Task.sleep(for: .milliseconds(delay))
                tuckShelf(below: snapshot.items.first { $0.id.sectionKey == item.id.sectionKey }?.pid ?? 0)
            }
            renderWindow()
        }
    }

    /// The owning app's own status-item element when it can be pressed in
    /// place: a third-party app with exactly one item exposing AXPress.
    private func pressableElement(for key: String, item: ObservedItem, pid: pid_t) -> AXUIElement? {
        guard let element = statusElement(for: key, item: item, pid: pid) else { return nil }
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        guard ((actions as? [String]) ?? []).contains(kAXPressAction) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    /// The owning app's own status-item element (third-party apps with a
    /// single item). It stays in the app's AX tree while concealed.
    private func statusElement(for key: String, item: ObservedItem, pid: pid_t, timeout: Float = 0.5) -> AXUIElement? {
        guard pid > 0, key.hasPrefix("bundle:"), MenuBarPolicy.systemItem(for: item.id) == nil else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let extras, CFGetTypeID(extras) == AXUIElementGetTypeID() else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        guard let items = children as? [AXUIElement], items.count == 1, let element = items.first else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    /// A press opens the menu under the item's own (hidden) slot. macOS can
    /// park that slot far from the bar's icons — the menu then opened at the
    /// left edge of the screen. Only press in place when the slot is near the
    /// control; otherwise reveal and click like a system item.
    private func pressOpensNearStrip(_ key: String) -> Bool {
        guard let point = axPosition(for: key), let control = controlPanel?.frame,
              let screen = controlPanel?.screen ?? NSScreen.main else { return false }
        let near = point.x > screen.frame.midX && abs(point.x - control.midX) < 400
        if !near { NSLog("YoungBar: \(key) slot at x=\(point.x) is away from the control; revealing instead") }
        return near
    }

    private func axPosition(for key: String) -> CGPoint? {
        guard let item = catalog[key],
              let pid = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == item.id.bundleID })?.processIdentifier,
              let element = statusElement(for: key, item: item, pid: pid, timeout: 0.3) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    /// Immediate feedback on the strip: the pressed icon lights up briefly.
    private func flashPressed(_ button: NSButton) {
        guard button.superview != nil else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = button.layer?.backgroundColor
            fade.toValue = NSColor.clear.cgColor
            fade.duration = 0.25
            button.layer?.add(fade, forKey: "fade")
            button.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func revealHiddenSection() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if !shownUntil.isEmpty {
            let ids = Set(shownUntil.keys); shownUntil.removeAll()
            await engine.conceal(items: ids)
        } else {
            let ids = Set(catalog.filter { modes[$0.key] == 1 }.map { $0.value.id })
            await engine.reveal(items: ids)
            for id in ids { shownUntil[id] = Date().addingTimeInterval(revealSeconds) }
            _ = await settledSnapshot(for: ids)
        }
        positionControlBesideMenuIcons(in: await engine.freshSnapshot())
    }

    private func outsideClick() {
        guard !busy, (ignoreOutsideUntil ?? .distantPast) < Date() else { return }
        let location = NSEvent.mouseLocation
        if expanded && options["keepShelfOpen"] != 1,
           shelfPanel?.frame.contains(location) != true,
           controlPanel?.frame.contains(location) != true { closeShelf() }
        guard options["blankClick"] == 1, let screen = NSScreen.main,
              location.y >= screen.frame.maxY - 40, location.x > screen.frame.midX,
              controlPanel?.frame.contains(location) != true else { return }
        let cgPoint = CGPoint(x: location.x, y: screen.frame.maxY - location.y)
        guard !currentFrames.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(cgPoint) }) else { return }
        statusClicked()
    }

    @objc private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        renderWindow()
    }

    @objc private func showWindow() {
        if settings == nil {
            let controller = BarSettings()
            controller.onMode = { [weak self] key, mode in self?.setMode(key: key, mode: mode) }
            controller.onMove = { [weak self] key, before in self?.moveItem(key: key, before: before) }
            controller.onPermission = { [weak self] kind in
                guard let self else { return }
                if kind == "accessibility" { self.requestAccessibility() }
                self.renderWindow()
            }
            controller.onLogin = { [weak self] enabled in self?.setLaunchAtLogin(enabled) }
            controller.onSpacing = { [weak self] level in self?.setSpacing(level) }
            controller.onCustomIcon = { [weak self] in self?.chooseControlIcon() }
            controller.onRemoveCustomIcon = { [weak self] in self?.removeCustomIcon() }
            controller.onOption = { [weak self] key, value in
                guard let self else { return }
                options[key] = value
                UserDefaults.standard.set(options, forKey: "barOptions")
                if key == "shareAnonymousUsage" {
                    usageTelemetry.setEnabled(value == 1)
                    renderWindow()
                    return
                }
                if key == "language" {
                    // The SwiftUI tree rebuilds in place; the window keeps
                    // its position and page.
                    L10n.current = Language(rawValue: value) ?? .chinese
                    statusItem?.button?.toolTip = L10n.t(
                        "YoungBar：点击查看收纳的图标；右键选择要收纳的应用",
                        "YoungBar: click to show concealed icons; right-click to choose apps")
                    renderWindow(force: true)
                    settings?.languageChanged()
                    return
                }
                if key == "controlIcon" {
                    applyControlIcon()
                    renderWindow(force: true)
                    return
                }
                if ["appearanceMode", "themeColor", "stripOpacity", "themeScope"].contains(key) {
                    applyAppearance()
                    shelfState = nil
                    if expanded { populateShelf() }
                    renderWindow(force: true)
                    return
                }
                if key == "keepShelfOpen" {
                    if value == 1 { showShelf() }
                    else { closeShelf() }
                }
                renderWindow()
            }
            controller.onRefresh = { [weak self] in self?.refreshClicked() }
            settings = controller
        }
        renderWindow(force: true)
        settings?.show()
    }

    private func renderWindow(force: Bool = false) {
        let keys = previewOnly ? uniqueKeys(savedOrder) : orderedKeys()
        let entries = keys.map { key in
            let id = catalog[key]?.id ?? ItemID(rawValue: key)
            return BarEntry(key: key, name: name(for: key), image: fallbackImage(for: key),
                            mode: modes[key] ?? 0,
                            pinned: MenuBarPolicy.isPinnedSystemItem(id) || MenuBarPolicy.isPinnedAppleHost(id.bundleID))
        }
        let message: String
        if !AXIsProcessTrusted() { message = L10n.t("需要辅助功能权限", "Accessibility permission required") }
        else if !feedback.isEmpty { message = feedback }
        else { message = "" }
        settings?.update(entries: entries, message: message,
                         axTrusted: AXIsProcessTrusted(), launchAtLogin: launchAtLoginEnabled,
                         customIcon: customIconImage, options: options)
    }

    private var customControlIconURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YoungBar", isDirectory: true)
            .appendingPathComponent("control-icon.png")
    }

    private func currentControlIcon() -> NSImage? {
        let index = options["controlIcon"] ?? 0
        let custom = index == ControlIcon.symbols.count ? customIconImage : nil
        return ControlIcon.image(index, custom: custom)
    }

    private func applyControlIcon() {
        let index = options["controlIcon"] ?? 0
        let image = currentControlIcon()
        let tint: NSColor? = index == ControlIcon.symbols.count ? nil : .labelColor
        controlButton?.image = image
        controlButton?.contentTintColor = tint
    }

    private func removeCustomIcon() {
        try? FileManager.default.removeItem(at: customControlIconURL)
        customIconImage = nil
        options["controlIcon"] = 0
        UserDefaults.standard.set(options, forKey: "barOptions")
        applyControlIcon()
        renderWindow(force: true)
    }

    private func chooseControlIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.t("选择一张图片作为菜单栏图标", "Choose an image for the menu-bar button")
        guard panel.runModal() == .OK, let url = panel.url,
              let source = NSImage(contentsOf: url) else { return }
        let target = NSImage(size: NSSize(width: 36, height: 36))
        target.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 36, height: 36).fill()
        source.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36),
                    from: .zero, operation: .sourceOver, fraction: 1)
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try FileManager.default.createDirectory(at: customControlIconURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: customControlIconURL, options: .atomic)
            customIconImage = NSImage(data: png)
            options["controlIcon"] = ControlIcon.symbols.count
            UserDefaults.standard.set(options, forKey: "barOptions")
            applyControlIcon()
            renderWindow(force: true)
        } catch {
            NSLog("YoungBar custom icon save failed: \(error)")
        }
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                feedback = L10n.t("已加入登录项，下次登录时自动启动", "Added to login items; launches at next login")
            } else {
                try SMAppService.mainApp.unregister()
                feedback = L10n.t("已从登录项移除", "Removed from login items")
            }
        } catch {
            feedback = L10n.t("开机自启动设置失败：\(error.localizedDescription)", "Launch-at-login failed: \(error.localizedDescription)")
        }
        renderWindow(force: true)
    }

    /// The login item records the app's path. After the bundle moves it would
    /// launch nothing, so re-register once from the new location.
    private func refreshLoginItemIfMoved() {
        let path = Bundle.main.bundlePath
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let token = "\(path)|\(version)"
        let previous = UserDefaults.standard.string(forKey: "loginItemToken")
        UserDefaults.standard.set(token, forKey: "loginItemToken")
        guard SMAppService.mainApp.status == .enabled, previous != token else { return }
        try? SMAppService.mainApp.unregister()
        try? SMAppService.mainApp.register()
    }

    /// Values recovered from iBar Pro 1.4.6's own spacing commands:
    /// default removes both keys; the other levels write equal padding/spacing.
    private func setSpacing(_ level: Int) {
        guard level != (options["iconSpacing"] ?? 0) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("修改菜单栏图标间隙？", "Change menu-bar icon spacing?")
        alert.informativeText = L10n.t("这会写入系统全局菜单栏间距偏好，重启电脑后生效。可以随时改回默认。", "This writes a global menu-bar spacing preference and takes effect after a reboot. You can restore the default anytime.")
        alert.addButton(withTitle: L10n.t("写入", "Write"))
        alert.addButton(withTitle: L10n.t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            renderWindow(force: true)
            return
        }
        do {
            if level == 0 {
                try runDefaults(["-currentHost", "remove", "-g", "NSStatusItemSelectionPadding"])
                try runDefaults(["-currentHost", "remove", "-g", "NSStatusItemSpacing"])
            } else {
                let value = level == 1 ? 5 : level == 2 ? 3 : 0
                try runDefaults(["-currentHost", "write", "-g", "NSStatusItemSelectionPadding", String(value)])
                try runDefaults(["-currentHost", "write", "-g", "NSStatusItemSpacing", String(value)])
            }
            options["iconSpacing"] = level
            UserDefaults.standard.set(options, forKey: "barOptions")
            feedback = L10n.t("菜单栏间距已修改，重启电脑后生效", "Spacing updated; takes effect after a reboot")
        } catch {
            feedback = L10n.t("菜单栏间距写入失败：\(error.localizedDescription)", "Spacing write failed: \(error.localizedDescription)")
        }
        renderWindow(force: true)
    }

    private func runDefaults(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "YoungBar", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "defaults 退出码 \(process.terminationStatus)" : text])
        }
    }

    private func setMode(key: String, mode: Int) {
        guard !busy else { return }
        modes[key] = mode
        UserDefaults.standard.set(modes, forKey: "itemModes")
        UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        closeShelf(); shownUntil.removeAll(); shelfState = nil
        Task {
            busy = true
            await engine.conceal()
            await engine.setModel(currentModel())
            busy = false
            await refresh()
        }
        renderWindow()
    }

    private func moveItem(key: String, before: String) {
        guard !busy, let item = catalog[key],
              !MenuBarPolicy.isPinnedSystemItem(item.id), !MenuBarPolicy.isPinnedAppleHost(item.id.bundleID) else { return }
        let originalOrder = savedOrder
        savedOrder.removeAll { $0 == key }
        let index = savedOrder.firstIndex(of: before) ?? savedOrder.count
        savedOrder.insert(key, at: index)
        closeShelf(); shelfState = nil
        busy = true
        Task {
            defer { busy = false; renderWindow() }
            let targetKey = before.isEmpty ? savedOrder.dropLast().last : before
            guard let targetKey, let target = catalog[targetKey], presentKeys.contains(targetKey) else {
                savedOrder = originalOrder; feedback = L10n.t("目标位置旁边的项目当前不在菜单栏中", "The neighbouring item is not in the menu bar right now"); return
            }
            guard !(before.isEmpty && MenuBarPolicy.isPinnedSystemItem(target.id)) else {
                savedOrder = originalOrder; feedback = L10n.t("日期和控制中心的位置由 macOS 固定", "Date and Control Center are pinned by macOS"); return
            }
            let ids: Set<ItemID> = [item.id, target.id]
            let temporary = ids.filter { (modes[$0.sectionKey.rawValue] ?? 0) > 0 && shownUntil[$0] == nil }
            await engine.reveal(items: ids)
            let snapshot = await settledSnapshot(for: ids)
            if let from = snapshot.items.first(where: { $0.id.sectionKey == item.id.sectionKey })?.frame,
               let to = snapshot.items.first(where: { $0.id.sectionKey == target.id.sectionKey })?.frame {
                let destination = CGPoint(x: before.isEmpty ? to.maxX + 3 : to.minX - 3, y: to.midY)
                controlPanel?.ignoresMouseEvents = true
                await ItemMover.cmdDrag(from: CGPoint(x: from.midX, y: from.midY), to: destination)
                controlPanel?.ignoresMouseEvents = false
                let result = await settledSnapshot(for: ids)
                let a = result.items.first { $0.id.sectionKey == item.id.sectionKey }?.frame
                let b = result.items.first { $0.id.sectionKey == target.id.sectionKey }?.frame
                let landed = a != nil && b != nil && (before.isEmpty ? a!.midX > b!.midX : a!.midX < b!.midX)
                if landed {
                    UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
                    await engine.setModel(currentModel())
                    feedback = L10n.t("顺序已应用到菜单栏", "Order applied to the menu bar")
                } else {
                    savedOrder = originalOrder; feedback = L10n.t("macOS 没有接受这次排序，已保留原顺序", "macOS did not accept the order; kept the previous one")
                }
            } else { savedOrder = originalOrder; feedback = L10n.t("项目当前没有可移动的位置", "This item has no movable position right now") }
            await engine.conceal(items: Set(temporary))
            positionControlBesideMenuIcons(in: await engine.freshSnapshot())
        }
    }

    @objc private func toggleLeftClickMenu() {
        options["leftClickMenu"] = options["leftClickMenu"] == 1 ? 0 : 1
        UserDefaults.standard.set(options, forKey: "barOptions")
        feedback = options["leftClickMenu"] == 1 ? L10n.t("左键点击改为显示菜单", "Left click now shows the menu") : L10n.t("左键点击改为展开收纳", "Left click now opens the strip")
        renderWindow(force: true)
    }

    /// Bulk visibility is transient: it builds a throw-away model instead of
    /// overwriting the per-item Hidden / Always Hidden choices.
    @objc private func hideAllApps() {
        guard !busy else { return }
        closeShelf()
        Task {
            busy = true
            await bulkHideAll()
            busy = false
            feedback = L10n.t("已隐藏全部应用图标", "Hid all app icons")
            renderWindow(force: true)
        }
    }

    @objc private func showAllApps() {
        guard !busy else { return }
        Task {
            busy = true
            await engine.reveal(Set(Section.allCases))
            busy = false
            feedback = L10n.t("已显示全部菜单栏项目", "Showed all menu-bar items")
            renderWindow(force: true)
        }
    }

    @objc private func restoreAppModes() {
        guard !busy else { return }
        Task {
            busy = true
            await engine.conceal()
            await engine.setModel(currentModel())
            busy = false
            feedback = L10n.t("已恢复你的收纳配置", "Restored your layout")
            renderWindow(force: true)
        }
    }

    private func bulkHideAll() async {
        var model = SectionModel(newItemsDestination: .visible)
        for item in catalog.values where item.id.bundleID != nil && !MenuBarPolicy.isPinnedSystemItem(item.id) {
            model.assignments[item.id] = .hidden
        }
        for section in Section.allCases {
            model.order[section] = savedOrder.map { ItemID(rawValue: $0) }.filter { model.section(of: $0) == section }
        }
        await engine.setModel(model)
    }

    /// Opt-in (`YOUNGBAR_BULKTEST=1`): hide all app items, reveal everything,
    /// then restore the user's model, and prove the modes were not rewritten.
    private func runBulkTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        let modesBefore = modes
        let before = await engine.freshSnapshot()
        let visibleBefore = before.items.filter { $0.frame != nil }.count
        result["concealedBefore"] = before.concealed.count
        result["visibleBefore"] = visibleBefore
        await bulkHideAll()
        let hidden = await engine.freshSnapshot()
        let visibleAfterHide = hidden.items.filter { $0.frame != nil }.count
        result["concealedAfterHideAll"] = hidden.concealed.count
        result["visibleAfterHideAll"] = visibleAfterHide
        await engine.reveal(Set(Section.allCases))
        let shown = await engine.freshSnapshot()
        result["concealedAfterShowAll"] = shown.concealed.count
        result["visibleAfterShowAll"] = shown.items.filter { $0.frame != nil }.count
        await engine.conceal()
        await engine.setModel(currentModel())
        try? await Task.sleep(for: .milliseconds(400))
        let restored = await engine.freshSnapshot()
        result["concealedAfterRestore"] = restored.concealed.count
        result["modesUnchanged"] = modes == modesBefore
        result["passed"] = (hidden.concealed.count > before.concealed.count)
            && (shown.concealed.count == 0)
            && (restored.concealed.count == before.concealed.count)
            && (modes == modesBefore)
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("bulktest.json")
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @objc private func toggleBundle(_ item: NSMenuItem) {
        guard let bundle = item.representedObject as? String else { return }
        setHidden(bundle: bundle)
    }

    private func setHidden(bundle: String) {
        let key = "bundle:\(bundle)"
        setMode(key: key, mode: (modes[key] ?? 0) > 0 ? 0 : 1)
    }

    /// Show every item, ignoring the saved hide rules. Used by the crash
    /// guard and on clean termination so the menu bar is never left hidden.
    private func revealEverything() async {
        var model = SectionModel(newItemsDestination: .visible)
        model.order = currentModel().order
        await engine.setModel(model)
        await engine.conceal()
    }

    private func currentModel() -> SectionModel {
        var model = SectionModel(newItemsDestination: .visible)
        for (key, mode) in modes where mode > 0 {
            model.assignments[ItemID(rawValue: key)] = mode == 2 ? .alwaysHidden : .hidden
        }
        for section in Section.allCases {
            model.order[section] = savedOrder.map { ItemID(rawValue: $0) }.filter { model.section(of: $0) == section }
        }
        return model
    }

    // Read-only accessors for the opt-in diagnostics snapshot.
    var diagnosticsStarted: Bool { started }
    var diagnosticsExpanded: Bool { expanded }
    var diagnosticsFeedback: String { feedback }

    func diagnosticsItems(snapshot: EngineSnapshot?) -> [Diagnostics.Item] {
        orderedKeys().map { key in
            // Only the live snapshot has a trustworthy frame: catalog entries
            // keep the last seen frame even after an item is concealed.
            let frame = snapshot?.items.first { $0.id.sectionKey.rawValue == key }?.frame
            return Diagnostics.Item(
                key: key,
                name: name(for: key),
                x: frame.map { Double($0.minX) },
                y: frame.map { Double($0.minY) },
                width: frame.map { Double($0.width) },
                height: frame.map { Double($0.height) },
                axX: axPosition(for: key).map { Double($0.x) },
                mode: modes[key] ?? 0
            )
        }
    }

    /// Opt-in (`YOUNGBAR_SHELFOPENTEST=1`): opening the strip must be instant
    /// and must not reveal any menu-bar item.
    /// Opt-in (`YOUNGBAR_PINNEDTEST=1`): checks whether the clock and Control
    /// Center can be hidden through the allowlist even though their position
    /// cannot be dragged. Restores the original modes afterwards.
    private func runPinnedHideTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        let keys = ["status:com.apple.MenuBarAgent::com.apple.menuextra.clock",
                    "status:com.apple.MenuBarAgent::com.apple.menuextra.controlcenter"]
        let originals = keys.map { modes[$0] ?? 0 }
        result["originals"] = originals
        for key in keys { modes[key] = 1 }
        UserDefaults.standard.set(modes, forKey: "itemModes")
        await engine.conceal()
        await engine.setModel(currentModel())
        try? await Task.sleep(for: .milliseconds(900))
        let hidden = await engine.freshSnapshot()
        let concealedKeys = hidden.concealed.map { $0.sectionKey.rawValue }
        result["clockConcealed"] = concealedKeys.contains(keys[0])
        result["controlCenterConcealed"] = concealedKeys.contains(keys[1])
        result["revealedCount"] = await engine.itemsRevealedOnTheirOwn().count
        for (index, key) in keys.enumerated() {
            modes[key] = originals[index]
        }
        UserDefaults.standard.set(modes, forKey: "itemModes")
        await engine.conceal()
        await engine.setModel(currentModel())
        try? await Task.sleep(for: .milliseconds(700))
        result["restored"] = keys.allSatisfy { (modes[$0] ?? 0) == originals[keys.firstIndex(of: $0)!] }
        result["passed"] = (result["clockConcealed"] as? Bool == true)
            && (result["controlCenterConcealed"] as? Bool == true)
            && (result["restored"] as? Bool == true)
        writeJSON(result, name: "pinnedtest.json")
    }

    /// Opt-in (`YOUNGBAR_HOTKEYTEST=1`): posts the real ⌃⌥B chord and checks
    /// that the strip opens and closes without the mouse.
    private func runHotKeyTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        closeShelf()
        postHotKey()
        try? await Task.sleep(for: .milliseconds(700))
        result["opened"] = expanded
        postHotKey()
        try? await Task.sleep(for: .milliseconds(700))
        result["closed"] = !expanded
        result["passed"] = (result["opened"] as? Bool == true) && (result["closed"] as? Bool == true)
        closeShelf()
        writeJSON(result, name: "hotkeytest.json")
    }

    private func postHotKey() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 11, keyDown: down) else { continue }
            event.flags = [.maskControl, .maskAlternate]
            event.post(tap: .cghidEventTap)
        }
    }

    /// Opt-in (`YOUNGBAR_GEARTEST=1`): opens the strip and clicks its pinned
    /// gear with a real HID click, then checks that the settings window opened.
    /// Opt-in (`YOUNGBAR_SETTINGSCLICKTEST=1`): real HID click on the settings
    /// "refresh" button, then checks the button's own action counter.
    private func postPlainClick(at point: CGPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
    }

    /// Opt-in (`YOUNGBAR_SETTINGSUITEST=1`): drives the SwiftUI settings window
    /// with real HID events — per-item mode menu, drag and right-click reorder,
    /// language menu — then restores modes, order and language. Every event is
    /// aimed only after checking the settings window is the topmost window at
    /// that point, so a stray click never lands in another app.
    /// `YOUNGBAR_EXPECT_ORDER` (comma-separated keys) is the order to restore;
    /// it defaults to the order at the start of the test.
    private func runSettingsUITest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        var debug: [String] = []
        defer {
            result["debug"] = debug
            writeJSON(result, name: "settingsuitest.json")
        }
        for _ in 0..<40 where catalog.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        func settle(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func waitIdle() async { for _ in 0..<80 where busy { await settle(250) } }
        let originalModes = modes
        let expected = ProcessInfo.processInfo.environment["YOUNGBAR_EXPECT_ORDER"]?
            .split(separator: ",").map(String.init) ?? savedOrder
        let originalLanguage = options["language"] ?? 0
        let originalOptions = options
        result["restoredAtStart"] = await restoreOrder(to: expected)

        showWindow()
        await settle(1200)
        guard let settings, NSApp.isActive, settings.windowForCapture.isKeyWindow else {
            result["error"] = "settings window is not key; refusing to post events"
            return
        }
        let controller = settings
        let ourWindow = settings.windowForCapture.windowNumber
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        /// Converts an AppKit screen point to CG space, or nil if another
        /// window would receive the event.
        func aim(_ point: NSPoint, _ label: String) -> CGPoint? {
            let topmost = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
            guard topmost == ourWindow else {
                debug.append("\(label): \(NSStringFromPoint(point)) is covered by window \(topmost), ours \(ourWindow)")
                return nil
            }
            return CGPoint(x: point.x, y: screenTop - point.y)
        }
        func rect(_ key: String) -> NSRect? {
            let found = settings.screenRect(for: key)
            if found == nil { debug.append("no frame for \(key)") }
            return found
        }
        /// The value of a right-aligned pop-up in a form row.
        func popUp(_ key: String) -> CGPoint? {
            guard let row = rect(key) else { return nil }
            debug.append("\(key) row \(NSStringFromRect(row)), window \(NSStringFromRect(settings.windowFrame))")
            return aim(NSPoint(x: row.maxX - 30, y: row.midY), key)
        }
        func order(_ key: String) -> Int { savedOrder.firstIndex(of: key) ?? -1 }
        /// Opens a menu with a click and picks an item with the keyboard.
        /// Keys are only sent once a menu window is on screen; otherwise they
        /// would reach whatever control has focus.
        func pick(at point: CGPoint, keys: [CGKeyCode], button: CGMouseButton = .left, _ label: String) async -> Bool {
            let before = menuWindowCount()
            await Self.postClick(at: point, button: button)
            for _ in 0..<10 where menuWindowCount() <= before { await settle(100) }
            guard menuWindowCount() > before else {
                debug.append("\(label): no menu opened; keys not sent")
                return false
            }
            // A key sent while the menu is still appearing can be dropped.
            await settle(700)
            await Self.postKeys(keys + [36])
            return true
        }

        // 1. Per-item mode buttons: Shown → Hidden → Always Hidden → Hidden → Shown.
        settings.select(.layout)
        await settle(1000)
        var modeSteps: [[String: Any]] = []
        if let target = settings.currentEntries.first(where: { !$0.pinned && $0.mode == 0 && $0.key.hasPrefix("bundle:") }) {
            result["modeTarget"] = target.key
            for expected in [1, 2, 1, 0] {
                guard let control = rect("mode:\(target.key)"),
                      let point = aim(NSPoint(x: control.minX + control.width * CGFloat(2 * expected + 1) / 6,
                                              y: control.midY), "mode") else {
                    modeSteps.append(["error": "segment not reachable"]); break
                }
                await Self.postClick(at: point, button: .left)
                await settle(1200); await waitIdle(); await settle(600)
                modeSteps.append(["expected": expected, "stored": modes[target.key] ?? 0,
                                  "row": settings.currentEntries.first { $0.key == target.key }?.mode ?? -1])
            }
        }
        result["modeSteps"] = modeSteps
        result["modePassed"] = modeSteps.count == 4 && modeSteps.allSatisfy { ($0["expected"] as? Int) == ($0["stored"] as? Int) && ($0["expected"] as? Int) == ($0["row"] as? Int) }

        // 2. Drag a row below its right-hand neighbour; 3. move it back with
        //    the context menu ("左移一位" is the second item).
        await settle(800)
        let entries = settings.currentEntries
        let pairs = entries.indices.dropLast().filter { index in
            let a = entries[index], b = entries[index + 1]
            return !a.pinned && !b.pinned && a.key.hasPrefix("bundle:") && b.key.hasPrefix("bundle:")
        }
        let shownPair = pairs.first { entries[$0].mode == 0 && entries[$0 + 1].mode == 0 }
        if let index = shownPair ?? pairs.first,
           let rowA = rect("row:\(entries[index].key)"),
           let rowB = rect("row:\(entries[index + 1].key)"),
           let from = aim(NSPoint(x: rowA.minX + 90, y: rowA.midY), "drag start"),
           let to = aim(NSPoint(x: rowB.minX + 90, y: rowB.midY), "drag end") {
            let a = entries[index].key, b = entries[index + 1].key
            result["dragPair"] = [a, b]
            result["orderBefore"] = [order(a), order(b)]
            await Self.postDrag(from: from, to: to)
            await settle(1500); await waitIdle(); await settle(800)
            let dragged = order(a) > order(b)
            result["orderAfterDrag"] = [order(a), order(b)]
            result["dragFeedback"] = feedback
            result["dragPassed"] = dragged

            var contextSteps: [[String: Any]] = []
            // Without a successful drag, move right first so there is something to undo.
            let plan: [(Int, Bool)] = dragged ? [(2, false)] : [(3, true), (2, false)]
            for (downs, expectRight) in plan {
                await settle(1000)
                if !settings.windowForCapture.isKeyWindow { showWindow(); await settle(800) }
                guard let row = rect("row:\(a)"), let point = aim(NSPoint(x: row.minX + 90, y: row.midY), "context") else {
                    contextSteps.append(["error": "row not reachable"]); break
                }
                guard await pick(at: point, keys: Array(repeating: CGKeyCode(125), count: downs), button: .right, "context") else {
                    contextSteps.append(["error": "menu did not open"]); break
                }
                await settle(1500); await waitIdle(); await settle(800)
                contextSteps.append(["downs": downs, "aRightOfB": order(a) > order(b), "expectedRight": expectRight, "feedback": feedback])
            }
            result["contextSteps"] = contextSteps
            result["contextPassed"] = contextSteps.count == plan.count && contextSteps.allSatisfy { ($0["aRightOfB"] as? Bool) == ($0["expectedRight"] as? Bool) }
        } else {
            result["dragError"] = "no movable adjacent pair reachable"
        }

        // 4. Language menu: there and back, in place.
        if !settings.windowForCapture.isKeyWindow { showWindow(); await settle(800) }
        settings.select(.general)
        await settle(1000)
        let frameBefore = settings.windowFrame
        var languageSteps: [[String: Any]] = []
        let toOther: CGKeyCode = originalLanguage == 0 ? 125 : 126
        let back: CGKeyCode = originalLanguage == 0 ? 126 : 125
        for (key, expected) in [(toOther, 1 - originalLanguage), (back, originalLanguage)] {
            // Synthetic keys sometimes miss a freshly opened menu; one retry
            // separates that from a real failure.
            var attempts = 0
            while attempts < 2 && (options["language"] ?? 0) != expected {
                attempts += 1
                guard let point = popUp("language"), await pick(at: point, keys: [key], "language") else { break }
                await settle(1500)
            }
            languageSteps.append(["expected": expected, "stored": options["language"] ?? -1, "attempts": attempts,
                                  "title": self.settings?.windowTitle ?? "",
                                  "sameWindow": self.settings === controller,
                                  "frameUnchanged": self.settings?.windowFrame == frameBefore])
        }
        result["languageSteps"] = languageSteps
        result["languagePassed"] = languageSteps.count == 2 && languageSteps.allSatisfy {
            ($0["expected"] as? Int) == ($0["stored"] as? Int) && ($0["sameWindow"] as? Bool) == true && ($0["frameUnchanged"] as? Bool) == true
        }

        // Restore anything a failed step left behind.
        await waitIdle()
        for (key, mode) in originalModes where modes[key] != mode { setMode(key: key, mode: mode); await settle(800); await waitIdle() }
        for key in modes.keys where originalModes[key] == nil && modes[key] != 0 { setMode(key: key, mode: 0); await settle(800); await waitIdle() }
        if (options["language"] ?? 0) != originalLanguage {
            options["language"] = originalLanguage
            UserDefaults.standard.set(options, forKey: "barOptions")
            L10n.current = Language(rawValue: originalLanguage) ?? .chinese
            renderWindow(force: true)
        }
        result["restoredAtEnd"] = await restoreOrder(to: expected)
        // Items that are not in the menu bar only differ in their saved slot;
        // put that back too once the visible order matches.
        if savedOrder != expected, Set(savedOrder) == Set(expected),
           savedOrder.filter({ presentKeys.contains($0) }) == expected.filter({ presentKeys.contains($0) }) {
            savedOrder = expected
            UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        }
        result["modesRestored"] = modes.filter { $0.value != 0 } == originalModes.filter { $0.value != 0 }
        result["orderRestored"] = savedOrder == expected
        result["languageRestored"] = (options["language"] ?? 0) == originalLanguage
        result["optionsUnchanged"] = options == originalOptions
        settings.close()
    }

    /// Moves items until the ones now in the menu bar follow `target`,
    /// through the same path as a user move: at each step the first item out
    /// of place is moved in front of whatever sits in its slot. Items that are
    /// not present are ignored. Returns the moves made.
    private func restoreOrder(to target: [String]) async -> [String] {
        var moves: [String] = []
        func present(_ keys: [String]) -> [String] { keys.filter { catalog[$0] != nil && presentKeys.contains($0) } }
        for _ in 0..<12 {
            let current = present(savedOrder), wanted = present(target).filter { current.contains($0) }
            guard current != wanted,
                  let slot = current.indices.first(where: { $0 < wanted.count && current[$0] != wanted[$0] }) else { break }
            let key = wanted[slot], before = current[slot]
            moveItem(key: key, before: before)
            moves.append("\(key) before \(before)")
            try? await Task.sleep(for: .milliseconds(500))
            for _ in 0..<80 where busy { try? await Task.sleep(for: .milliseconds(250)) }
            moves.append("→ \(feedback)")
        }
        return moves
    }

    nonisolated private static func postClick(at point: CGPoint, button: CGMouseButton) async {
        await Task.detached {
            let source = CGEventSource(stateID: .hidSystemState)
            let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
            let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
            CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
            usleep(40_000)
            CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        }.value
    }

    nonisolated private static func postKeys(_ keys: [CGKeyCode]) async {
        await Task.detached {
            let source = CGEventSource(stateID: .hidSystemState)
            for key in keys {
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
                usleep(30_000)
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
                usleep(200_000)
            }
        }.value
    }

    nonisolated private static func postDrag(from: CGPoint, to: CGPoint) async {
        await Task.detached {
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(300_000)
            for step in 1...20 {
                let t = CGFloat(step) / 20
                let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(40_000)
            }
            usleep(400_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)?.post(tap: .cghidEventTap)
        }.value
    }

    private func runSettingsClickTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        showWindow()
        try? await Task.sleep(for: .milliseconds(700))
        guard let settings, let rect = settings.refreshButtonScreenRect(),
              let screen = NSScreen.main else {
            result["error"] = "settings button not available"
            writeJSON(result, name: "settingsclick.json")
            return
        }
        result["frame"] = NSStringFromRect(rect)
        let before = settings.refreshClickCount
        let point = CGPoint(x: rect.midX, y: screen.frame.maxY - rect.midY)
        // A plain, untagged HID click behaves like a physical click; if a
        // shield/tap is swallowing real input this one fails.
        postPlainClick(at: point)
        try? await Task.sleep(for: .milliseconds(700))
        let plainAfter = settings.refreshClickCount
        result["plainAfter"] = plainAfter
        await ItemMover.shieldedClick(at: point)
        try? await Task.sleep(for: .milliseconds(900))
        let after = settings.refreshClickCount
        result["before"] = before
        result["after"] = after
        result["passed"] = after > before
        result["plainWorked"] = plainAfter > before
        writeJSON(result, name: "settingsclick.json")
    }

    private func runGearTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        showShelf()
        try? await Task.sleep(for: .milliseconds(500))
        result["shelfOpened"] = expanded
        guard let gear = gearButton, let panel = shelfPanel,
              let screen = panel.screen ?? NSScreen.main else {
            result["error"] = "gear not built"
            writeJSON(result, name: "geartest.json")
            return
        }
        let frame = panel.convertToScreen(gear.convert(gear.bounds, to: nil))
        result["gearFrame"] = "\(frame.origin.x),\(frame.origin.y) \(frame.width)x\(frame.height)"
        let point = CGPoint(x: frame.midX, y: screen.frame.maxY - frame.midY)
        await ItemMover.shieldedClick(at: point)
        try? await Task.sleep(for: .milliseconds(900))
        result["settingsOpened"] = settings?.isVisible ?? false
        result["shelfClosed"] = !expanded
        result["passed"] = (result["shelfOpened"] as? Bool == true)
            && (result["settingsOpened"] as? Bool == true)
        if expanded { closeShelf() }
        writeJSON(result, name: "geartest.json")
    }

    private func runShelfOpenTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        closeShelf()
        let before = await engine.freshSnapshot()
        let visibleBefore = before.items.filter { $0.frame != nil }.count
        let start = Date()
        toggleShelf()
        while !expanded && Date().timeIntervalSince(start) < 1.0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let revealed = await engine.itemsRevealedOnTheirOwn().count
        let after = await engine.freshSnapshot()
        let visibleAfter = after.items.filter { $0.frame != nil }.count
        result["opened"] = expanded
        result["openMs"] = elapsed
        result["revealedOnOpen"] = revealed
        result["visibleBefore"] = visibleBefore
        result["visibleAfter"] = visibleAfter
        result["passed"] = expanded && elapsed < 400 && revealed == 0 && visibleAfter == visibleBefore
        closeShelf()
        writeJSON(result, name: "shelfopen.json")
    }

    /// Dev-only (`YOUNGBAR_SETTINGS_PREVIEW=1`, `=zh` or `=en`): captures every
    /// settings page in dark and light from saved state, then exits. It never
    /// touches the menu bar, so it can run beside a live instance.
    private func runSettingsPreview() async {
        for (suffix, appearance) in [("dark", NSAppearance(named: .darkAqua)), ("light", NSAppearance(named: .aqua))] {
            NSApp.appearance = appearance
            showWindow()
            for page in SettingsPage.allCases {
                settings?.select(page)
                try? await Task.sleep(for: .milliseconds(700))
                if let window = settings?.windowForCapture {
                    let theme = ["blue", "pink", "yellow", "clear"][themeColor.rawValue]
                    await captureWindow(window, to: "preview-\(L10n.current == .english ? "en" : "zh")-\(theme)-\(suffix)-\(page.rawValue).png")
                }
            }
        }
        exit(0)
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(string: """
        Menu bar organizer for macOS 27.
        UI reconstruction inspired by iBar Pro 1.4.6.
        Built on Dimble's PelmetCore / PelmetEngine (GPLv3).
        Licensed under GPL-3.0-only; see LICENSE and THIRD_PARTY_NOTICES.
        """, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "YoungBar",
            .applicationVersion: "0.1.0",
            .version: "1",
            .credits: credits,
        ])
    }

    /// Opt-in (`YOUNGBAR_CONCEALTEST=1`): compares "conceal while a panel is
    /// open" (iFan) with "conceal while a menu is open" (input source).
    private func runConcealTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]

        if let fanKey = catalog.first(where: { $0.value.id.bundleID == "com.better365.iFanOffline" })?.key,
           let fan = catalog[fanKey] {
            let pid = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.better365.iFanOffline" }?.processIdentifier
            result["fanWindowsBefore"] = pid.map { targetWindows(pid: $0).count } ?? 0
            modes[fanKey] = 1
            UserDefaults.standard.set(modes, forKey: "itemModes")
            await engine.conceal()
            await engine.setModel(currentModel())
            try? await Task.sleep(for: .milliseconds(600))
            await engine.reveal(items: [fan.id])
            let shown = await settledSnapshot(for: [fan.id])
            if let frame = shown.items.first(where: { $0.id == fan.id })?.frame {
                await ItemMover.shieldedClick(at: CGPoint(x: frame.midX, y: frame.midY))
                try? await Task.sleep(for: .milliseconds(900))
                result["fanWindowsAfterClick"] = pid.map { targetWindows(pid: $0).count } ?? 0
                shownUntil[fan.id] = nil
                await engine.conceal(items: [fan.id])
                try? await Task.sleep(for: .milliseconds(1500))
                result["fanConcealedWhilePanelOpen"] = (await engine.freshSnapshot()).concealed.contains(fan.id)
                try? await Task.sleep(for: .seconds(2))
                result["fanConcealedAfter2s"] = (await engine.freshSnapshot()).concealed.contains(fan.id)

                NSRunningApplication(processIdentifier: pid ?? 0)?.activate(options: [.activateAllWindows])
                try? await Task.sleep(for: .milliseconds(350))
                postCommandW()
                try? await Task.sleep(for: .milliseconds(500))
                closeWindows(pid: pid)
                try? await Task.sleep(for: .milliseconds(500))
                result["fanWindowsAfterCleanup"] = pid.map { targetWindows(pid: $0).count } ?? 0
            }
            modes[fanKey] = 1
            UserDefaults.standard.set(modes, forKey: "itemModes")
            await engine.conceal()
            await engine.setModel(currentModel())
            try? await Task.sleep(for: .milliseconds(500))
        }

        if let menuKey = catalog.first(where: { $0.value.id.bundleID == "com.apple.TextInputMenuAgent" })?.key,
           let menuItem = catalog[menuKey] {
            let original = modes[menuKey] ?? 0
            modes[menuKey] = 1
            UserDefaults.standard.set(modes, forKey: "itemModes")
            await engine.conceal()
            await engine.setModel(currentModel())
            try? await Task.sleep(for: .milliseconds(600))
            await engine.reveal(items: [menuItem.id])
            let shown = await settledSnapshot(for: [menuItem.id])
            if let frame = shown.items.first(where: { $0.id == menuItem.id })?.frame {
                await ItemMover.shieldedClick(at: CGPoint(x: frame.midX, y: frame.midY))
                try? await Task.sleep(for: .milliseconds(800))
                let probe = elementInfo(at: CGPoint(x: frame.midX, y: frame.maxY + 40))
                result["menuOpenRole"] = probe.role
                shownUntil[menuItem.id] = nil
                await engine.conceal(items: [menuItem.id])
                try? await Task.sleep(for: .milliseconds(1200))
                result["menuConcealedWhileOpen"] = (await engine.freshSnapshot()).concealed.contains(menuItem.id)
                postEscape()
            }
            modes[menuKey] = original
            UserDefaults.standard.set(modes, forKey: "itemModes")
            await engine.conceal()
            await engine.setModel(currentModel())
        }
        writeJSON(result, name: "concealtest.json")
    }

    /// Opt-in (`YOUNGBAR_ABOUTTEST=1`): opens the About panel and records its
    /// title plus a PNG of the panel content.
    private func runAboutTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
        showAbout()
        try? await Task.sleep(for: .milliseconds(700))
        let about = NSApp.windows.first { !before.contains(ObjectIdentifier($0)) }
        result["title"] = about?.title ?? ""
        result["opened"] = about != nil
        result["frame"] = about.map { NSStringFromRect($0.frame) } ?? ""
        await captureScreen(to: "about-full.png")
        if let view = about?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("about.png")
                try? data.write(to: url, options: .atomic)
            }
        }
        result["passed"] = about != nil
        writeJSON(result, name: "abouttest.json")
    }

    @objc private func refreshClicked() {
        Task { await refresh(); renderWindow(force: true) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Carry the user's layout across bundle-id/name changes.
/// `dev.leorea.bar` → `dev.leorea.youngbar` → `studio.wuyiyang.youngbar`.
enum YoungBarDefaults {
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        migrate(from: "dev.leorea.bar", marker: "migratedFromLeoreaBar")
        migrate(from: "dev.leorea.youngbar", marker: "migratedFromLeoreaYoungBar")
    }

    private static func migrate(from suiteName: String, marker: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: marker),
              let legacy = UserDefaults(suiteName: suiteName) else { return }
        for key in ["itemModes", "itemOrder", "barOptions", "hiddenBundles"]
        where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: marker)
    }
}

YoungBarDefaults.migrateIfNeeded()
let app = NSApplication.shared
let delegate = BarApp()
app.delegate = delegate
app.run()
