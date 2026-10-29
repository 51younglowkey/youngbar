// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

// Live self-tests and screenshot helpers. They drive the real menu bar with
// synthetic clicks, drags and keys, so they are compiled only into test
// builds: `TESTHOOKS=1 sh Scripts/build.sh`. A release build has none of
// this code and ignores the YOUNGBAR_*TEST environment variables.

#if YOUNGBAR_TESTHOOKS
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ScreenCaptureKit
import PelmetCore
import PelmetEngine
import YoungBarCore

extension BarApp {
    /// Runs the opt-in checks named by environment variables, once, after
    /// launch has finished its first refresh.
    func runLaunchHooks() async {
        if ProcessInfo.processInfo.environment["YOUNGBAR_UPDATETEST"] == "1" {
            await runUpdateTest()
        }
        if let page = ProcessInfo.processInfo.environment["YOUNGBAR_SHOWSETTINGS"] {
            showWindow()
            settings?.select(SettingsPage(rawValue: page) ?? .general)
            try? await Task.sleep(for: .milliseconds(900))
            writeJSON(["window": settings?.windowForCapture.windowNumber ?? 0], name: "settingswindow.json")
            try? await Task.sleep(for: .seconds(4))
            settings?.close()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_SHOWGUIDE"] == "1" {
            showGuide()
            try? await Task.sleep(for: .milliseconds(800))
            writeJSON(["window": guideWindow?.windowNumber ?? 0], name: "guide.json")
            try? await Task.sleep(for: .seconds(4))
            guideWindow?.orderOut(nil)
            guideTimer?.invalidate()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_KEYBOARDTEST"] == "1" {
            await runKeyboardTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_HOTKEYPROBE"] == "1" {
            await runHotKeyProbe()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_OVERFLOWTEST"] == "1" {
            await runOverflowTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_CONFIGTEST"] == "1" {
            await runConfigTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_TOPSHOT"] == "1" {
            try? await Task.sleep(for: .milliseconds(1800))
            await captureScreen(to: "top-full.png")
        }
        if let directory = ProcessInfo.processInfo.environment["YOUNGBAR_SNAPSHOT_DIR"] {
            showWindow()
            try? await Task.sleep(for: .milliseconds(500))
            await settings?.writeSnapshots(to: directory)
            writeShelfSnapshot(to: directory)
            await writeExtraSnapshots(to: directory)
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
    }

    /// Opt-in live check (`YOUNGBAR_SELFTEST=1`): reveal one concealed item,
    /// wait for a frame, conceal it again, and record both observations.
    /// It restores the item to its original concealed state.
    func runSelfTest() async {
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
    func runInteractionTest() async {
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
    func runSpacingTest() {
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

    func readDefaults(_ arguments: [String]) throws -> String {
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
    func runWindowCleanup(pid: pid_t) async {
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

    func postCommandW() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: down) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    func closeWindows(pid: pid_t?) {
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
                let minimized = true as CFBoolean
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized)
            }
        }
    }

    func targetWindows(pid: pid_t) -> [[String: Any]] {
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

    func focusedMenuOwner() -> (role: String, pid: pid_t?) {
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

    func menuWindowCount() -> Int {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter { (($0[kCGWindowLayer as String] as? Int) ?? 0) >= 100 }.count
    }

    func postEscape() {
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    func writeInteractionTest(_ result: [String: Any]) {
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
    func runMenuTest() async {
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
    func runOrderTest() async {
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

    func elementInfo(at point: CGPoint) -> (role: String, pid: pid_t?) {
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

    func captureWindow(_ window: NSWindow, to name: String) async {
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

    func captureScreen(to name: String) async {
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

    func writeShelfSnapshot(to directory: String) {
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

    func writeSelfTest(_ result: [String: Any]) {
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("selftest.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("YoungBar selftest write failed: \(error)")
        }
    }

    /// Opt-in (`YOUNGBAR_BULKTEST=1`): hide all app items, reveal everything,
    /// then restore the user's model, and prove the modes were not rewritten.
    func runBulkTest() async {
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

    /// Opt-in (`YOUNGBAR_SHELFOPENTEST=1`): opening the strip must be instant
    /// and must not reveal any menu-bar item.
    /// Opt-in (`YOUNGBAR_PINNEDTEST=1`): checks whether the clock and Control
    /// Center can be hidden through the allowlist even though their position
    /// cannot be dragged. Restores the original modes afterwards.
    func runPinnedHideTest() async {
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
    func runHotKeyTest() async {
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

    func postHotKey() {
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
    func postPlainClick(at point: CGPoint) {
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
    func runSettingsUITest() async {
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
        let originalLanguage = options[.language] ?? 0
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
            while attempts < 2 && (options[.language] ?? 0) != expected {
                attempts += 1
                guard let point = popUp("language"), await pick(at: point, keys: [key], "language") else { break }
                await settle(1500)
            }
            languageSteps.append(["expected": expected, "stored": options[.language] ?? -1, "attempts": attempts,
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
        if (options[.language] ?? 0) != originalLanguage {
            options[.language] = originalLanguage
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
        result["languageRestored"] = (options[.language] ?? 0) == originalLanguage
        result["optionsUnchanged"] = options == originalOptions
        settings.close()
    }

    /// Moves items until the ones now in the menu bar follow `target`,
    /// through the same path as a user move: at each step the first item out
    /// of place is moved in front of whatever sits in its slot. Items that are
    /// not present are ignored. Returns the moves made.
    func restoreOrder(to target: [String]) async -> [String] {
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

    nonisolated static func postClick(at point: CGPoint, button: CGMouseButton) async {
        await Task.detached {
            let source = CGEventSource(stateID: .hidSystemState)
            let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
            let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
            CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
            usleep(40_000)
            CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        }.value
    }

    nonisolated static func postKeys(_ keys: [CGKeyCode]) async {
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

    nonisolated static func postDrag(from: CGPoint, to: CGPoint) async {
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

    func runSettingsClickTest() async {
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

    func runGearTest() async {
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

    func runShelfOpenTest() async {
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
    func runSettingsPreview() async {
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

    /// Opt-in (`YOUNGBAR_CONCEALTEST=1`): compares "conceal while a panel is
    /// open" (iFan) with "conceal while a menu is open" (input source).
    func runConcealTest() async {
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
    func runAboutTest() async {
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

    // MARK: - 0.1.1 checks

    /// The strip searched, the guide, and a strip with a selection, for
    /// `YOUNGBAR_SNAPSHOT_DIR`. Rendered with cacheDisplay: no Screen
    /// Recording needed.
    func writeExtraSnapshots(to directory: String) async {
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        func save(_ view: NSView?, _ name: String) {
            guard let view else { return }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: base.appendingPathComponent(name))
            }
        }
        showShelf(selectFirst: true)
        moveShelfSelection(by: 1)
        save(shelfPanel?.contentView, "shelf-selected.png")
        if let first = shelfButtons.first?.identifier?.rawValue {
            setShelfQuery(String(name(for: first).prefix(2)).lowercased())
            save(shelfPanel?.contentView, "shelf-search.png")
        }
        setShelfQuery("zzqx")
        save(shelfPanel?.contentView, "shelf-nomatch.png")
        closeShelf()
        showGuide()
        try? await Task.sleep(for: .milliseconds(600))
        save(guideWindow?.contentView, "guide.png")
        guideWindow?.orderOut(nil)
        guideTimer?.invalidate()
    }

    func shelfKey(_ code: Int, _ characters: String = "", flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: shelfPanel?.windowNumber ?? 0, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: UInt16(code)) else { return }
        _ = handleShelfKey(event)
    }

    func postChord(_ code: Int, _ flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Opt-in (`YOUNGBAR_KEYBOARDTEST=1`): the shortcut opens the strip with
    /// key focus and the first item chosen; arrows move; typing filters; Esc
    /// clears then closes; a custom shortcut replaces ⌃⌥B and is restored.
    /// Only the shortcut chords are real key presses; the keys inside the
    /// strip go straight to its handler.
    func runKeyboardTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "keyboardtest.json") }
        closeShelf()
        try? await Task.sleep(for: .milliseconds(300))
        postChord(kVK_ANSI_B, [.maskControl, .maskAlternate])
        try? await Task.sleep(for: .milliseconds(900))
        result["openedByShortcut"] = expanded
        result["stripIsKey"] = shelfPanel?.isKeyWindow ?? false
        result["frontAppStillFront"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        result["selectionAfterOpen"] = shelfSelection ?? -1
        let shown = shelfButtons.compactMap { $0.identifier?.rawValue }
        result["itemsShown"] = shown
        shelfKey(kVK_RightArrow)
        result["selectionAfterRight"] = shelfSelection ?? -1
        shelfKey(kVK_LeftArrow)
        shelfKey(kVK_LeftArrow)
        result["selectionAfterTwoLeft"] = shelfSelection ?? -1
        var searchOK = false
        if let target = shown.last {
            let query = String(name(for: target).prefix(3)).lowercased()
            for character in query { shelfKey(0, String(character)) }
            let matches = shelfButtons.compactMap { $0.identifier?.rawValue }
            result["query"] = query
            result["matches"] = matches
            searchOK = matches.first == target && shelfSelection == 0
            result["searchFoundTarget"] = searchOK
            shelfKey(kVK_Delete)
            result["queryAfterDelete"] = shelfQuery
        }
        shelfKey(kVK_Escape)
        for character in "zzqx" { shelfKey(0, String(character)) }
        result["noMatchCount"] = shelfButtons.count
        shelfKey(kVK_Escape)
        result["queryClearedByEsc"] = shelfQuery.isEmpty && expanded
        shelfKey(kVK_Escape)
        result["closedByEsc"] = !expanded

        let original = (options[.hotKeyCode], options[.hotKeyModifiers])
        setHotKey(HotKeyCombo(keyCode: UInt32(kVK_ANSI_Y),
                              modifiers: HotKeyCombo.control | HotKeyCombo.option | HotKeyCombo.command))
        result["customDisplay"] = hotKeyDisplay
        try? await Task.sleep(for: .milliseconds(300))
        postChord(kVK_ANSI_Y, [.maskControl, .maskAlternate, .maskCommand])
        try? await Task.sleep(for: .milliseconds(900))
        result["openedByCustom"] = expanded
        closeShelf()
        try? await Task.sleep(for: .milliseconds(300))
        postChord(kVK_ANSI_B, [.maskControl, .maskAlternate])
        try? await Task.sleep(for: .milliseconds(900))
        result["oldShortcutIgnored"] = !expanded
        closeShelf()
        options[.hotKeyCode] = original.0
        options[.hotKeyModifiers] = original.1
        UserDefaults.standard.set(options, forKey: "barOptions")
        registerHotKey()
        result["restoredDisplay"] = hotKeyDisplay
        result["passed"] = (result["openedByShortcut"] as? Bool == true)
            && (result["stripIsKey"] as? Bool == true)
            && (shown.isEmpty || (result["selectionAfterOpen"] as? Int) == 0)
            && (shown.isEmpty || searchOK)
            && (result["noMatchCount"] as? Int) == 0
            && (result["queryClearedByEsc"] as? Bool == true)
            && (result["closedByEsc"] as? Bool == true)
            && (result["openedByCustom"] as? Bool == true)
            && (result["oldShortcutIgnored"] as? Bool == true)
            && hotKeyDisplay == "⌃⌥B"
    }

    /// Opt-in (`YOUNGBAR_OVERFLOWTEST=1`): reads the notch geometry and the
    /// shown items' frames, then shows every Hidden item for a moment to
    /// crowd the bar and records which items land under the notch and
    /// whether the strip lists them. Modes are restored afterwards.
    func runOverflowTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "overflowtest.json") }
        result["notchVisibleMinX"] = notchVisibleMinX.map { Double($0) } ?? -1
        func frames(_ snapshot: EngineSnapshot) -> [String: Double] {
            var out: [String: Double] = [:]
            for item in snapshot.items { if let frame = item.frame { out[item.id.sectionKey.rawValue] = Double(frame.minX) } }
            return out
        }
        await refresh()
        result["overflowAtRest"] = overflowKeys.sorted()
        let originalModes = modes
        // Shown items re-sync the saved order to the bar; put it back after.
        let originalOrder = savedOrder
        let hiddenKeys = modes.filter { $0.value == 1 }.map(\.key)
        for key in hiddenKeys { modes[key] = 0 }
        UserDefaults.standard.set(modes, forKey: "itemModes")
        busy = true
        await engine.conceal()
        await engine.setModel(currentModel())
        busy = false
        try? await Task.sleep(for: .milliseconds(1500))
        await refresh()
        let crowded = await engine.freshSnapshot()
        result["framesAllShown"] = frames(crowded)
        result["overflowAllShown"] = overflowKeys.sorted()
        showShelf()
        let stripKeys = shelfButtons.compactMap { $0.identifier?.rawValue }
        result["stripKeysAllShown"] = stripKeys
        result["stripListsOverflow"] = overflowKeys.isSubset(of: Set(stripKeys))
        closeShelf()
        // YOUNGBAR_OVERFLOW_HOLD=<seconds> keeps the crowded bar up for a screenshot.
        if let hold = Double(ProcessInfo.processInfo.environment["YOUNGBAR_OVERFLOW_HOLD"] ?? "") {
            writeJSON(["crowded": true], name: "overflow-hold.json")
            try? await Task.sleep(for: .seconds(hold))
        }
        modes = originalModes
        UserDefaults.standard.set(modes, forKey: "itemModes")
        savedOrder = originalOrder
        UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        busy = true
        await engine.conceal()
        await engine.setModel(currentModel())
        busy = false
        try? await Task.sleep(for: .milliseconds(1200))
        await refresh()
        let after = await engine.freshSnapshot()
        result["restored"] = modes == originalModes
        result["concealedAfter"] = after.concealed.map(\.sectionKey.rawValue).sorted()
        result["overflowAfter"] = overflowKeys.sorted()
    }

    /// Opt-in (`YOUNGBAR_CONFIGTEST=1`): exports the layout, changes one
    /// option, imports the file again and checks everything came back.
    func runConfigTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "configtest.json") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("youngbar-configtest.json")
        let modesBefore = modes, optionsBefore = options, orderBefore = savedOrder
        do {
            try writeConfiguration(to: url)
            let file = try ConfigFile.decode(Data(contentsOf: url), knownOptions: Set(Option.allCases.map(\.rawValue)))
            result["exportedModes"] = file.itemModes.count
            result["exportedOrder"] = file.itemOrder.count
            options[.revealSeconds] = 33
            var done = false
            applyConfiguration(file) { done = true }
            for _ in 0..<40 where !done { try? await Task.sleep(for: .milliseconds(150)) }
            result["applied"] = done
            result["modesEqual"] = modes == modesBefore
            result["optionsEqual"] = options == optionsBefore
            result["orderEqual"] = savedOrder == orderBefore
            result["passed"] = done && modes == modesBefore && options == optionsBefore && savedOrder == orderBefore
        } catch {
            result["error"] = "\(error)"
            result["passed"] = false
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Opt-in (`YOUNGBAR_HOTKEYPROBE=1`): registers several shortcuts in turn
    /// and records which ones open the strip. Restores the saved one.
    func runHotKeyProbe() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        // Let launch settle: the first refresh can still hold `busy`.
        try? await Task.sleep(for: .seconds(2))
        defer { writeJSON(result, name: "hotkeyprobe.json") }
        let original = (options[.hotKeyCode], options[.hotKeyModifiers])
        let c = HotKeyCombo.control, o = HotKeyCombo.option, m = HotKeyCombo.command
        let combos: [(String, Int, UInt32, CGEventFlags)] = [
            ("1 ctrl-opt-cmd-Y", kVK_ANSI_Y, c | o | m, [.maskControl, .maskAlternate, .maskCommand]),
            ("2 ctrl-opt-cmd-Y", kVK_ANSI_Y, c | o | m, [.maskControl, .maskAlternate, .maskCommand]),
            ("3 ctrl-opt-B", kVK_ANSI_B, c | o, [.maskControl, .maskAlternate]),
            ("4 ctrl-opt-B", kVK_ANSI_B, c | o, [.maskControl, .maskAlternate]),
            ("5 opt-cmd-B", kVK_ANSI_B, o | m, [.maskAlternate, .maskCommand]),
            ("6 ctrl-opt-N", kVK_ANSI_N, c | o, [.maskControl, .maskAlternate]),
            ("7 opt-cmd-B", kVK_ANSI_B, o | m, [.maskAlternate, .maskCommand]),
            ("8 ctrl-opt-cmd-K", kVK_ANSI_K, c | o | m, [.maskControl, .maskAlternate, .maskCommand]),
        ]
        for (label, code, mods, flags) in combos {
            closeShelf()
            setHotKey(HotKeyCombo(keyCode: UInt32(code), modifiers: mods))
            let registered = hotKeyDisplay
            try? await Task.sleep(for: .milliseconds(400))
            let pressesBefore = hotKeyPressCount
            postChord(code, flags)
            try? await Task.sleep(for: .milliseconds(150))
            let early = expanded
            try? await Task.sleep(for: .milliseconds(750))
            result[label] = ["registered": registered, "opened": expanded, "openAt150ms": early,
                             "presses": hotKeyPressCount - pressesBefore]
            closeShelf()
        }
        options[.hotKeyCode] = original.0
        options[.hotKeyModifiers] = original.1
        UserDefaults.standard.set(options, forKey: "barOptions")
        registerHotKey()
        feedback = ""
        result["restoredDisplay"] = hotKeyDisplay
    }

    /// Opt-in (`YOUNGBAR_UPDATETEST=1`): checks GitHub, records what the
    /// updater found and the window number (for `screencapture -l`), checks
    /// `YOUNGBAR_SIGCHECK_PATH` against this app's signature if given, and
    /// with `YOUNGBAR_UPDATE_INSTALL=1` installs (YoungBar quits and the
    /// swap script reopens the new version). Pair with
    /// `YOUNGBAR_UPDATE_PRETEND_VERSION=0.1.0` to update to the real release.
    func runUpdateTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "current": currentVersion]
        checkForUpdates()
        for _ in 0..<100 where updateModel?.state == .checking { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .milliseconds(500))
        switch updateModel?.state {
        case .available(let version, _): result["state"] = "available"; result["offered"] = version
        case .upToDate(let version): result["state"] = "upToDate"; result["offered"] = version
        case .failed(let message): result["state"] = "failed"; result["message"] = message
        default: result["state"] = "other"
        }
        result["window"] = updateWindow?.windowNumber ?? 0
        if let path = ProcessInfo.processInfo.environment["YOUNGBAR_SIGCHECK_PATH"] {
            result["sigcheckPath"] = path
            result["sigcheckAccepted"] = Self.signedLikeThisApp(URL(fileURLWithPath: path))
        }
        result["selfAccepted"] = Self.signedLikeThisApp(Bundle.main.bundleURL)
        writeJSON(result, name: "updatetest.json")
        try? await Task.sleep(for: .seconds(3))
        guard ProcessInfo.processInfo.environment["YOUNGBAR_UPDATE_INSTALL"] == "1",
              result["state"] as? String == "available" else { return }
        installUpdate()
        for _ in 0..<150 {
            try? await Task.sleep(for: .milliseconds(200))
            if case .failed(let message) = updateModel?.state {
                writeJSON(["installFailed": message], name: "updateinstall.json")
                return
            }
        }
    }
}
#endif
