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
        if ProcessInfo.processInfo.environment["YOUNGBAR_EXTRASTEST"] == "1" {
            await runExtrasTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_SHELFDRAGTEST"] == "1" {
            await runShelfDragTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_AUTOHIDETEST"] == "1" {
            await runAutoHideTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_AUTOUPDATETEST"] == "1" {
            await runAutoUpdateTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_APPEARANCETEST"] == "1" {
            await runAppearanceTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_EMPTYSHELFTEST"] == "1" {
            await runEmptyShelfTest()
        }
        if let seconds = Double(ProcessInfo.processInfo.environment["YOUNGBAR_BARLOOKTEST"] ?? "") {
            await runBarLookTest(seconds: seconds)
        }
        if let bundle = ProcessInfo.processInfo.environment["YOUNGBAR_LAUNCHTEST"], !bundle.isEmpty {
            await runLaunchTest(bundle: bundle)
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_NOASSERTIONTEST"] == "1" {
            await runNoAssertionTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_CONTROLYTEST"] == "1" {
            await runControlLevelTest()
        }
        if ProcessInfo.processInfo.environment["YOUNGBAR_FLIGHTTEST"] == "1" {
            await runFlightRecorderTest()
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
        result["concealedAfterTest"] = (await engine.freshSnapshot()).concealed.contains(item.id)
        closeShelf()
        writeInteractionTest(result)
    }

    /// Opt-in (`YOUNGBAR_SPACINGTEST=1`): writes the 3/3 spacing used by
    /// iBar's 小间隙, reads it back, then removes both keys again.
    func runSpacingTest() {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        let keys = ["NSStatusItemSelectionPadding", "NSStatusItemSpacing"]
        // This Mac's own values (nil: not set), put back however the test ends.
        let originals = keys.map { try? readDefaults(["-currentHost", "read", "-g", $0]) }
        result["originals"] = originals.map { $0 ?? "(unset)" }
        do {
            try runDefaults(["-currentHost", "write", "-g", "NSStatusItemSelectionPadding", "3"])
            try runDefaults(["-currentHost", "write", "-g", "NSStatusItemSpacing", "3"])
            result["paddingReadBack"] = try readDefaults(["-currentHost", "read", "-g", "NSStatusItemSelectionPadding"])
            result["spacingReadBack"] = try readDefaults(["-currentHost", "read", "-g", "NSStatusItemSpacing"])
            result["passed"] = (result["paddingReadBack"] as? String) == "3"
                && (result["spacingReadBack"] as? String) == "3"
        } catch {
            result["error"] = error.localizedDescription
            result["passed"] = false
        }
        for (key, original) in zip(keys, originals) {
            if let original {
                try? runDefaults(["-currentHost", "write", "-g", key, original])
            } else {
                try? runDefaults(["-currentHost", "delete", "-g", key])
            }
        }
        let after = keys.map { try? readDefaults(["-currentHost", "read", "-g", $0]) }
        result["restored"] = after == originals
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
        // In memory only (currentModel reads it): a crash mid-test must not
        // leave the temporary mode saved.
        modes[key] = 1
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
        // The click went through the reveal path: release that item, which
        // a plain conceal() leaves out.
        await engine.conceal(releasing: [item.id])
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
        // As `restoreAppModes` does: "Hide all" lasts until it is undone.
        bulkHiddenKeys = []
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

    /// Opt-in (`YOUNGBAR_HOTKEYTEST=1`): presses the saved shortcut for real
    /// (⌘⌘ by default) and checks that the strip opens and closes without the
    /// mouse.
    func runHotKeyTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        result["shortcut"] = hotKeyDisplay
        closeShelf()
        await postHotKey()
        try? await Task.sleep(for: .milliseconds(700))
        result["opened"] = expanded
        await postHotKey()
        try? await Task.sleep(for: .milliseconds(700))
        result["closed"] = !expanded
        result["passed"] = (result["opened"] as? Bool == true) && (result["closed"] as? Bool == true)
        closeShelf()
        writeJSON(result, name: "hotkeytest.json")
    }

    func postHotKey() async {
        guard let hotKey else { return }
        var flags: CGEventFlags = []
        if hotKey.modifiers & HotKeyCombo.command != 0 { flags.insert(.maskCommand) }
        if hotKey.modifiers & HotKeyCombo.option != 0 { flags.insert(.maskAlternate) }
        if hotKey.modifiers & HotKeyCombo.control != 0 { flags.insert(.maskControl) }
        if hotKey.modifiers & HotKeyCombo.shift != 0 { flags.insert(.maskShift) }
        if hotKey.isDoubleTap {
            let key = flags.contains(.maskCommand) ? kVK_Command : flags.contains(.maskAlternate) ? kVK_Option : kVK_Control
            await postModifiers([(key, flags), (key, flags)])
        } else {
            postChord(Int(hotKey.keyCode), flags)
        }
    }

    /// An untagged HID click, like a physical one.
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

    /// Opt-in (`YOUNGBAR_GEARTEST=1`): opens the strip and clicks its pinned
    /// gear with a real HID click, then checks that the settings window opened.
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
        // Leave the screen as the test found it.
        settings?.close()
        writeJSON(result, name: "geartest.json")
    }

    func runShelfOpenTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        closeShelf()
        let before = await engine.freshSnapshot()
        let visibleBefore = before.items.filter { $0.frame != nil }.count
        // Only what opening reveals: an earlier test's item may still be
        // out for its own 20 s.
        let revealedBefore = await engine.itemsRevealedOnTheirOwn()
        let start = Date()
        toggleShelf()
        while !expanded && Date().timeIntervalSince(start) < 1.0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let revealed = await engine.itemsRevealedOnTheirOwn().subtracting(revealedBefore).count
        let after = await engine.freshSnapshot()
        let visibleAfter = after.items.filter { $0.frame != nil }.count
        result["opened"] = expanded
        result["openMs"] = elapsed
        result["revealedOnOpen"] = revealed
        result["visibleBefore"] = visibleBefore
        result["visibleAfter"] = visibleAfter
        // The fade-in must end fully opaque (a strip stuck half-transparent is a bug).
        try? await Task.sleep(for: .milliseconds(250))
        let alpha = Double(shelfPanel?.alphaValue ?? 0)
        result["alphaAfterFade"] = alpha
        result["passed"] = expanded && elapsed < 400 && revealed == 0 && visibleAfter == visibleBefore && alpha > 0.99
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
            let originalFan = modes[fanKey]
            modes[fanKey] = 1
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
            // Released whether or not the click happened, and back to the
            // user's own mode (not forced to Hidden).
            shownUntil[fan.id] = nil
            await engine.conceal(items: [fan.id])
            modes[fanKey] = originalFan
            UserDefaults.standard.set(modes, forKey: "itemModes")
            await engine.conceal()
            await engine.setModel(currentModel())
            try? await Task.sleep(for: .milliseconds(500))
        }

        if let menuKey = catalog.first(where: { $0.value.id.bundleID == "com.apple.TextInputMenuAgent" })?.key,
           let menuItem = catalog[menuKey] {
            let original = modes[menuKey]
            modes[menuKey] = 1
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
            shownUntil[menuItem.id] = nil
            await engine.conceal(items: [menuItem.id])
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
        about?.close()
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

    /// Real modifier presses: `flags` held for each step, then released.
    func postModifiers(_ steps: [(Int, CGEventFlags)], hold: Int = 40, gap: Int = 90) async {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for (code, flags) in steps {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
                event.type = .flagsChanged
                event.flags = down ? flags : []
                event.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(down ? hold : gap))
            }
        }
    }

    func postCommand(down: Bool) {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                                  virtualKey: CGKeyCode(kVK_Command), keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = down ? .maskCommand : []
        event.post(tap: .cghidEventTap)
    }

    func postDoubleCommand(gap: Int = 90) async {
        await postModifiers([(kVK_Command, .maskCommand), (kVK_Command, .maskCommand)], gap: gap)
    }

    /// Opt-in (`YOUNGBAR_KEYBOARDTEST=1`): double-tapping ⌘ (real key
    /// presses) opens the strip with key focus, the first item chosen and
    /// numbers on the icons; ⌘ then ⌘⇧, or two slow taps, don't; arrows
    /// move; letters change nothing (no search); a digit past the last
    /// icon beeps; Esc closes; a custom shortcut replaces ⌘⌘ and the saved
    /// one is restored. With `YOUNGBAR_KEYBOARD_DIGIT=1` a digit also
    /// opens a third-party item's menu (closed again with Esc).
    func runKeyboardTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "keyboardtest.json") }
        let original = (options[.hotKeyCode], options[.hotKeyModifiers])
        options[.hotKeyCode] = nil
        options[.hotKeyModifiers] = nil
        registerHotKey()
        result["defaultDisplay"] = hotKeyDisplay
        closeShelf()
        try? await Task.sleep(for: .milliseconds(300))
        await postDoubleCommand()
        try? await Task.sleep(for: .milliseconds(700))
        result["openedByDoubleCommand"] = expanded
        result["stripIsKey"] = shelfPanel?.isKeyWindow ?? false
        result["frontAppStillFront"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        result["selectionAfterOpen"] = shelfSelection ?? -1
        result["numbersShown"] = shelfNumbered
        let shown = shelfButtons.compactMap { $0.identifier?.rawValue }
        result["itemsShown"] = shown
        shelfKey(kVK_RightArrow)
        result["selectionAfterRight"] = shelfSelection ?? -1
        shelfKey(kVK_LeftArrow)
        shelfKey(kVK_LeftArrow)
        result["selectionAfterTwoLeft"] = shelfSelection ?? -1
        for character in "zzqx" { shelfKey(0, String(character)) }
        let typingIgnored = shelfButtons.compactMap { $0.identifier?.rawValue } == shown && expanded
        result["typingIgnored"] = typingIgnored
        let selectionBefore = shelfSelection
        if shown.count < 9, let code = Self.numberKeys.first(where: { $0.value == shown.count + 1 && $0.key < 0x40 })?.key {
            shelfKey(code)
            result["digitPastEndIgnored"] = expanded && shelfSelection == selectionBefore
        }
        shelfKey(kVK_Escape)
        result["closedByEsc"] = !expanded

        await postModifiers([(kVK_Command, .maskCommand), (kVK_Shift, [.maskCommand, .maskShift])])
        try? await Task.sleep(for: .milliseconds(600))
        result["commandShiftIgnored"] = !expanded
        closeShelf()
        try? await Task.sleep(for: .milliseconds(600))
        await postDoubleCommand(gap: 700)
        try? await Task.sleep(for: .milliseconds(600))
        result["slowTapsIgnored"] = !expanded
        closeShelf()

        // ⌘-click, then ⌘ alone: the click (handed to the monitor directly,
        // so nothing is clicked for real) makes the first press not a tap.
        try? await Task.sleep(for: .milliseconds(600))
        postCommand(down: true)
        try? await Task.sleep(for: .milliseconds(40))
        if let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .command,
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            handleDoubleTapEvent(click)
        }
        try? await Task.sleep(for: .milliseconds(30))
        postCommand(down: false)
        try? await Task.sleep(for: .milliseconds(90))
        await postModifiers([(kVK_Command, .maskCommand)])
        try? await Task.sleep(for: .milliseconds(600))
        result["commandClickIgnored"] = !expanded
        closeShelf()

        // A real click on the control: numbers too, and the strip takes the
        // keys (a real Esc closes it).
        try? await Task.sleep(for: .milliseconds(600))
        if let control = controlPanel?.frame, let primary = NSScreen.screens.first {
            postPlainClick(at: CGPoint(x: control.midX, y: primary.frame.maxY - control.midY))
            try? await Task.sleep(for: .milliseconds(700))
            result["clickOpened"] = expanded
            result["clickNumbersShown"] = shelfNumbered
            result["clickStripIsKey"] = shelfPanel?.isKeyWindow ?? false
            postChord(kVK_Escape, [])
            try? await Task.sleep(for: .milliseconds(500))
            result["clickClosedByRealEsc"] = !expanded
            closeShelf()
        }

        if ProcessInfo.processInfo.environment["YOUNGBAR_KEYBOARD_DIGIT"] == "1" {
            try? await Task.sleep(for: .milliseconds(600))
            await postDoubleCommand()
            try? await Task.sleep(for: .milliseconds(700))
            let target = shelfButtons.firstIndex { button in
                guard let key = button.identifier?.rawValue, let bundle = catalog[key]?.id.bundleID else { return false }
                return !bundle.hasPrefix("com.apple.")
            }
            if let target, target < 9, let code = Self.numberKeys.first(where: { $0.value == target + 1 && $0.key < 0x40 })?.key {
                result["digitTarget"] = shelfButtons[target].identifier?.rawValue ?? ""
                shelfKey(code)
                result["digitPressed"] = shelfAnchored && shelfSelection == target
                try? await Task.sleep(for: .milliseconds(1200))
                postChord(kVK_Escape, [])
                try? await Task.sleep(for: .milliseconds(400))
            }
            closeShelf()
        }

        try? await Task.sleep(for: .milliseconds(600))
        setHotKey(HotKeyCombo(keyCode: UInt32(kVK_ANSI_Y),
                              modifiers: HotKeyCombo.control | HotKeyCombo.option | HotKeyCombo.command))
        result["customDisplay"] = hotKeyDisplay
        try? await Task.sleep(for: .milliseconds(300))
        postChord(kVK_ANSI_Y, [.maskControl, .maskAlternate, .maskCommand])
        try? await Task.sleep(for: .milliseconds(900))
        result["openedByCustom"] = expanded
        closeShelf()
        try? await Task.sleep(for: .milliseconds(600))
        await postDoubleCommand()
        try? await Task.sleep(for: .milliseconds(700))
        result["doubleCommandIgnoredAfterChange"] = !expanded
        closeShelf()
        options[.hotKeyCode] = original.0
        options[.hotKeyModifiers] = original.1
        UserDefaults.standard.set(options, forKey: "barOptions")
        registerHotKey()
        result["restoredDisplay"] = hotKeyDisplay
        let checks = ["openedByDoubleCommand", "stripIsKey", "numbersShown", "typingIgnored", "closedByEsc",
                      "clickOpened", "clickNumbersShown", "clickStripIsKey", "clickClosedByRealEsc", "commandClickIgnored",
                      "commandShiftIgnored", "slowTapsIgnored", "openedByCustom", "doubleCommandIgnoredAfterChange"]
        result["passed"] = checks.allSatisfy { result[$0] as? Bool == true }
            && (shown.isEmpty || (result["selectionAfterOpen"] as? Int) == 0)
            && (result["digitPastEndIgnored"] as? Bool ?? true)
            && (result["digitPressed"] as? Bool ?? true)
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
        // In memory only: YOUNGBAR_OVERFLOW_HOLD can keep this state a while.
        for key in hiddenKeys { modes[key] = 0 }
        busy = true
        await engine.conceal()
        await engine.setModel(currentModel())
        busy = false
        try? await Task.sleep(for: .milliseconds(1500))
        await refresh()
        let crowded = await engine.freshSnapshot()
        result["framesAllShown"] = frames(crowded)
        result["overflowAllShown"] = overflowKeys.sorted()
        // Nothing went under « or the notch: the bar never filled, and the
        // checks below would hold for an empty set. Say so instead of passing.
        let wasCrowded = !overflowKeys.isEmpty
        result["crowded"] = wasCrowded
        if !wasCrowded {
            result["inconclusive"] = "the bar did not fill up with every icon shown: open more menu-bar apps (or show more items from Control Center) and run again"
        }
        // Settings → Menu Bar marks exactly those rows "No room".
        let covered = barEntries().filter(\.covered).map(\.key)
        result["coveredInSettings"] = covered.sorted()
        result["settingsMarksOverflow"] = Set(covered) == overflowKeys
        showShelf()
        let stripKeys = shelfButtons.compactMap { $0.identifier?.rawValue }
        result["stripKeysAllShown"] = stripKeys
        result["stripListsOverflow"] = overflowKeys.isSubset(of: Set(stripKeys))
        closeShelf()
        // YOUNGBAR_OVERFLOW_HOLD=<seconds> keeps the crowded bar up for a screenshot.
        if let hold = Double(ProcessInfo.processInfo.environment["YOUNGBAR_OVERFLOW_HOLD"] ?? "") {
            writeJSON(["crowded": wasCrowded], name: "overflow-hold.json")
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
        if wasCrowded {
            result["passed"] = (result["settingsMarksOverflow"] as? Bool == true)
                && (result["stripListsOverflow"] as? Bool == true)
                && (result["restored"] as? Bool == true)
        }
    }

    /// Opt-in (`YOUNGBAR_EXTRASTEST=1`): What's New opens with the bundled
    /// notes (no install commands in them); the diagnostics report has its
    /// lines; a strip icon's right-click menu offers the other two states,
    /// and choosing Always Hide takes it out of the strip (put back after).
    /// `YOUNGBAR_EXTRAS_HOLD=<seconds>` keeps What's New up for a screenshot.
    func runExtrasTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "extrastest.json") }
        let notes = bundledReleaseNotes ?? []
        let text = notes.map { "\($0)" }.joined()
        result["notesBlocks"] = notes.count
        result["notesHaveNoInstall"] = !text.contains("curl") && !text.contains("shasum")
        showWhatsNew()
        try? await Task.sleep(for: .milliseconds(600))
        result["whatsNewShown"] = whatsNewWindow?.isVisible == true
        result["whatsNewWindow"] = whatsNewWindow?.windowNumber ?? 0
        result["notesLanguageEnglish"] = updateIntro?.english ?? false
        result["tourSteps"] = updateIntro?.steps.count ?? 0
        // Every page, held for a screenshot when asked: extras-hold.json
        // names the window and the page on screen.
        let hold = Double(ProcessInfo.processInfo.environment["YOUNGBAR_EXTRAS_HOLD"] ?? "")
        func show(_ page: Int, _ label: String) async {
            updateIntro?.page = page
            try? await Task.sleep(for: .milliseconds(300))
            guard let hold else { return }
            writeJSON(["window": whatsNewWindow?.windowNumber ?? 0, "page": label], name: "extras-hold.json")
            try? await Task.sleep(for: .seconds(hold))
        }
        // Chinese first, whatever this Mac's language, so both halves get seen.
        func useLanguage(english: Bool) {
            guard let intro = updateIntro, let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            intro.english = english
            intro.shortcut = shortcutForTour(english: english)
            intro.notes = ReleaseNotes.blocks(ReleaseNotes.localized(text, preferredLanguages: [english ? "en" : "zh-Hans"]))
        }
        useLanguage(english: false)
        let pages = 1 + (updateIntro?.steps.count ?? 0)
        for page in 0..<pages { await show(page, "zh-\(page)") }
        // The try-it step: a real ⌘⌘ while the tour is up.
        updateIntro?.page = 1
        await postDoubleCommand()
        try? await Task.sleep(for: .milliseconds(700))
        result["tourSawShortcut"] = updateIntro?.triedShortcut == true
        closeShelf()
        await show(1, "zh-1-done")
        // The English half, as an English system would get it.
        useLanguage(english: true)
        result["englishNotesFirst"] = updateIntro?.notes.first.map { "\($0)" } ?? ""
        await show(0, "en-0")
        await show(1, "en-1")
        if hold != nil { writeJSON(["done": true], name: "extras-hold.json") }
        whatsNewWindow?.orderOut(nil)

        let report = await diagnosticsReport()
        result["report"] = report
        result["reportLines"] = report.split(separator: "\n").count

        showShelf()
        try? await Task.sleep(for: .milliseconds(400))
        guard let key = shelfKeys().first(where: { modes[$0] == 1 }) else {
            result["menuSkipped"] = "no hidden icon"
            closeShelf()
            return
        }
        let menu = shelfItemMenu(for: key)
        result["menuTitles"] = menu.items.map(\.title)
        guard let always = menu.items.first(where: { ($0.representedObject as? [String])?.last == "2" }) else { return }
        shelfItemModeChosen(always)
        for _ in 0..<40 where busy { try? await Task.sleep(for: .milliseconds(100)) }
        result["modeAfterMenu"] = modes[key] ?? 0
        result["leftStrip"] = !shelfKeys().contains(key)
        setMode(key: key, mode: 1)
        for _ in 0..<40 where busy { try? await Task.sleep(for: .milliseconds(100)) }
        result["restored"] = modes[key] == 1 && shelfKeys().contains(key)
    }

    /// Opt-in (`YOUNGBAR_SHELFDRAGTEST=1`): with the real mouse, drags the
    /// strip's first icon onto the last slot, checks the strip and the saved
    /// order follow and that nothing was revealed on the bar, then puts the
    /// saved order back. Needs two hidden icons.
    func runShelfDragTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "shelfdragtest.json") }
        let originalOrder = savedOrder
        let concealedBefore = await engine.freshSnapshot().concealed
        showShelf()
        try? await Task.sleep(for: .milliseconds(500))
        let before = shelfButtons.compactMap { $0.identifier?.rawValue }
        result["before"] = before
        guard before.count >= 2, let first = shelfButtons.first, let last = shelfButtons.last,
              let window = shelfPanel, let primary = NSScreen.screens.first else {
            result["skipped"] = "fewer than two icons"
            closeShelf()
            return
        }
        func point(_ button: NSButton) -> CGPoint {
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            return CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
        }
        let start = point(first)
        let end = CGPoint(x: point(last).x + 6, y: start.y)
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ at: CGPoint) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start)
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseDown, start)
        try? await Task.sleep(for: .milliseconds(120))
        for step in 1...12 {
            let x = start.x + (end.x - start.x) * CGFloat(step) / 12
            post(.leftMouseDragged, CGPoint(x: x, y: start.y))
            try? await Task.sleep(for: .milliseconds(25))
        }
        post(.leftMouseUp, end)
        try? await Task.sleep(for: .milliseconds(600))
        let after = shelfButtons.compactMap { $0.identifier?.rawValue }
        result["after"] = after
        result["stripReordered"] = after == Array(before.dropFirst()) + [before[0]]
        let savedHidden = savedOrder.filter { before.contains($0) }
        result["savedOrderFollows"] = savedHidden == after
        result["stillOpen"] = expanded
        let concealedAfter = await engine.freshSnapshot().concealed
        result["nothingRevealed"] = concealedAfter == concealedBefore
        closeShelf()
        savedOrder = originalOrder
        UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        await engine.setModel(currentModel())
        result["orderRestored"] = UserDefaults.standard.stringArray(forKey: "itemOrder") == originalOrder
    }

    /// Opt-in (`YOUNGBAR_AUTOHIDETEST=1`): makes one shown app icon look
    /// new (forgets it, with the option on in memory), refreshes, and checks
    /// it went to the strip and is concealed. Its mode, the saved order and
    /// the option are put back and it shows again.
    func runAutoHideTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "autohidetest.json") }
        await refresh()
        let snapshot = await engine.freshSnapshot()
        guard let victim = snapshot.items.last(where: { item in
            guard item.frame != nil, let bundle = item.id.bundleID else { return false }
            return bundle != Bundle.main.bundleIdentifier && !bundle.hasPrefix("com.apple.")
                && (modes[item.id.sectionKey.rawValue] ?? 0) == 0 && MenuBarPolicy.isSectionManageable(item.id)
        }) else {
            result["skipped"] = "no shown app icon"
            return
        }
        let key = victim.id.sectionKey.rawValue
        result["key"] = key
        let original = (mode: modes[key], order: savedOrder, option: options[.autoHideNew])
        options[.autoHideNew] = 1
        modes[key] = nil
        savedOrder.removeAll { $0 == key }
        catalog[key] = nil
        await refresh()
        for _ in 0..<20 where busy { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(800))
        result["modeAfter"] = modes[key] ?? 0
        result["feedback"] = feedback
        let hidden = await engine.freshSnapshot()
        result["concealed"] = hidden.concealed.contains { $0.sectionKey.rawValue == key }
        result["inStrip"] = shelfKeys().contains(key)
        // A key the user already knows is never auto-hidden.
        options[.autoHideNew] = original.option
        modes[key] = original.mode
        UserDefaults.standard.set(modes, forKey: "itemModes")
        UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        savedOrder = original.order
        UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        busy = true
        await engine.setModel(currentModel())
        busy = false
        try? await Task.sleep(for: .milliseconds(1200))
        await refresh()
        let after = await engine.freshSnapshot()
        result["shownAgain"] = after.items.contains { $0.id.sectionKey.rawValue == key && $0.frame != nil }
            && !after.concealed.contains { $0.sectionKey.rawValue == key }
        result["restored"] = modes[key] == original.mode && savedOrder == original.order
    }

    /// Opt-in (`YOUNGBAR_AUTOUPDATETEST=1`, usually with
    /// `YOUNGBAR_UPDATE_PRETEND_VERSION`): runs the daily check now and
    /// records whether the menu got its line, and that no window opened.
    /// `YOUNGBAR_AUTOUPDATE_HOLD=<seconds>` keeps the state up a while.
    func runAutoUpdateTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "current": currentVersion]
        defer { writeJSON(result, name: "autoupdatetest.json") }
        autoUpdateTask?.cancel()
        lastAutoUpdateCheck = nil
        await autoUpdateCheckIfDue()
        result["found"] = availableUpdate?.version.description ?? ""
        result["menuTop"] = configurationMenu().items.first?.title ?? ""
        result["windowOpened"] = updateWindow?.isVisible == true
        result["tooltip"] = controlButton?.toolTip ?? ""
        if let hold = Double(ProcessInfo.processInfo.environment["YOUNGBAR_AUTOUPDATE_HOLD"] ?? "") {
            writeJSON(["found": true], name: "autoupdate-hold.json")
            try? await Task.sleep(for: .seconds(hold))
        }
        startAutoUpdateChecks()
    }

    /// Opt-in (`YOUNGBAR_NOASSERTIONTEST=1`): the bar a user sees with
    /// nothing to hide. Hands the engine an empty model for a moment (the
    /// saved modes are not touched), so it drops the hide assertion and
    /// macOS draws YoungBar's own status item; records where it and the
    /// control sit. `YOUNGBAR_NOASSERTION_HOLD=<seconds>` keeps that state
    /// up for a screenshot. Then the real model goes back.
    func runNoAssertionTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "noassertiontest.json") }
        func own(_ snapshot: EngineSnapshot) -> [String: Double] {
            guard let frame = snapshot.items.first(where: { $0.id.bundleID == Bundle.main.bundleIdentifier })?.frame else { return [:] }
            return ["x": Double(frame.minX), "width": Double(frame.width)]
        }
        await refresh()
        let before = await engine.freshSnapshot()
        result["concealedBefore"] = before.concealed.map(\.sectionKey.rawValue).sorted()
        result["assertionBefore"] = await engine.holdsAssertion
        result["ownItemBefore"] = own(before)
        result["nativeTitle"] = statusItem.button?.title ?? ""
        result["nativeHasImage"] = statusItem.button?.image != nil
        busy = true
        await engine.setModel(SectionModel(newItemsDestination: .visible))
        try? await Task.sleep(for: .milliseconds(1500))
        let bare = await engine.freshSnapshot()
        positionControlBesideMenuIcons(in: bare)
        result["assertionBare"] = await engine.holdsAssertion
        result["ownItemBare"] = own(bare)
        if let panel = controlPanel?.frame {
            result["controlBare"] = ["x": Double(panel.minX), "width": Double(panel.width)]
        }
        if let hold = Double(ProcessInfo.processInfo.environment["YOUNGBAR_NOASSERTION_HOLD"] ?? "") {
            writeJSON(["bare": true], name: "noassertion-hold.json")
            try? await Task.sleep(for: .seconds(hold))
        }
        await engine.setModel(currentModel())
        busy = false
        try? await Task.sleep(for: .milliseconds(1500))
        await refresh()
        let after = await engine.freshSnapshot()
        result["concealedAfter"] = after.concealed.map(\.sectionKey.rawValue).sorted()
        result["assertionAfter"] = await engine.holdsAssertion
        result["restored"] = Set(after.concealed) == Set(before.concealed)
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
            options[.hoverExpand] = options[.hoverExpand] == 1 ? 0 : 1
            var done = false
            applyConfiguration(file) { done = true }
            for _ in 0..<40 where !done { try? await Task.sleep(for: .milliseconds(150)) }
            result["applied"] = done
            result["modesEqual"] = modes == modesBefore
            result["optionsEqual"] = options == optionsBefore
            result["optionsDiffer"] = Set(options.keys).union(optionsBefore.keys)
                .filter { options[$0] != optionsBefore[$0] }
                .sorted().map { "\($0): \(optionsBefore[$0].map(String.init) ?? "nil") → \(options[$0].map(String.init) ?? "nil")" }
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

    // MARK: - 0.1.5 checks

    /// Opt-in (`YOUNGBAR_CONTROLYTEST=1`): the control hung half below the
    /// bar for a user (0.1.4). Drops it by half a bar height, then checks the
    /// next refresh puts it back level with the icons beside it. If it
    /// doesn't, the control still goes back to where it was.
    func runControlLevelTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "controlytest.json") }
        await refresh()
        try? await Task.sleep(for: .milliseconds(800))
        guard let panel = controlPanel, let screen = panel.screen ?? NSScreen.screens.first,
              let primaryTop = NSScreen.screens.first?.frame.maxY else { return }
        let original = panel.frame.origin
        func level() async -> [String: Double] {
            // Read first: a timed refresh during the snapshot may move it.
            var values: [String: Double] = ["controlMidY": Double(primaryTop - panel.frame.midY)]
            let snapshot: EngineSnapshot? = await engine.freshSnapshot()
            let barTop = primaryTop - screen.frame.maxY
            let icon = snapshot?.items.compactMap { item -> CGRect? in
                guard let frame = item.frame, item.id.bundleID != Bundle.main.bundleIdentifier,
                      frame.minX > panel.frame.maxX, frame.minY - barTop < 50 else { return nil }
                return frame
            }.min { $0.minX < $1.minX }
            if let icon { values["iconMidY"] = Double(icon.midY) }
            values["barHeight"] = Double(menuBarHeight(of: screen))
            return values
        }
        result["before"] = await level()
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY - menuBarHeight(of: screen) / 2))
        result["dropped"] = await level()
        await refresh()
        try? await Task.sleep(for: .milliseconds(1200))
        let after = await level()
        result["after"] = after
        var levelAfter = false
        if let control = after["controlMidY"], let icon = after["iconMidY"] {
            levelAfter = abs(control - icon) <= 1.5
        }
        result["levelAfter"] = levelAfter
        if !levelAfter { panel.setFrameOrigin(original) }
    }

    /// Opt-in (`YOUNGBAR_FLIGHTTEST=1`): the flight recorder must tell who moved
    /// the •••. Moves it from outside, far then a little, and checks the log,
    /// the jump count, the report and the file; YoungBar's own animated way
    /// back mustn't read as a move from outside. The ••• ends where it was.
    func runFlightRecorderTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "flighttest.json") }
        // Right after launch the hidden icons are still leaving the bar, and
        // the ••• isn't where it stays. Wait for it to hold still.
        var settled: NSPoint?
        for _ in 0..<15 {
            await refresh()
            try? await Task.sleep(for: .milliseconds(1000))
            if settled == controlPanel?.frame.origin { break }
            settled = controlPanel?.frame.origin
        }
        guard let panel = controlPanel else { return }
        let original = panel.frame.origin
        let before = await engine.freshSnapshot()
        let inPlace = controlCheck(before)
        let jumpsBefore = flight.recentJumps
        func logged(_ text: String, last: Int = 12) -> Bool {
            flight.recent(last).contains { $0.contains(text) }
        }

        // Far: a jump from outside, then YoungBar's own way back.
        panel.setFrameOrigin(NSPoint(x: original.x - 300, y: original.y))
        let misplaced = controlCheck(before)
        try? await Task.sleep(for: .milliseconds(200))
        result["farOutsideLogged"] = logged("moved from outside")
        await refresh()
        try? await Task.sleep(for: .milliseconds(1200))
        result["ownMoveLogged"] = logged("follows")
        result["jumpsCounted"] = flight.recentJumps - jumpsBefore

        // A little: the way back animates, which is when a false "from
        // outside" would show.
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX - 30, y: panel.frame.minY))
        try? await Task.sleep(for: .milliseconds(200))
        result["smallOutsideLogged"] = logged("moved from outside", last: 2)
        let marker = "flight test: own move next"
        flight.note(marker)
        await refresh()
        try? await Task.sleep(for: .milliseconds(1200))
        // The last marker: the log keeps the lines of earlier runs.
        let lines = flight.recent(60)
        let afterMarker = lines.suffix(from: (lines.lastIndex { $0.contains(marker) } ?? lines.count - 1) + 1)
        result["afterMarker"] = Array(afterMarker)
        result["ownMoveNotOutside"] = !afterMarker.isEmpty && !afterMarker.contains { $0.contains("outside") }

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        try? await Task.sleep(for: .milliseconds(300))
        result["screensLogged"] = logged("screens changed")

        let after = await engine.freshSnapshot()
        let backInPlace = controlCheck(after)
        result["checkBefore"] = inPlace?.allPassed ?? false
        result["checkWhileMisplaced"] = misplaced?.allPassed ?? true
        result["gapWhileMisplaced"] = misplaced?.gapToIcon ?? -1
        result["checkAfter"] = backInPlace?.allPassed ?? false
        result["backInPlace"] = abs(panel.frame.minX - original.x) <= 1 && abs(panel.frame.minY - original.y) <= 1
        if result["backInPlace"] as? Bool != true { panel.setFrameOrigin(original) }

        let report = await diagnosticsReport()
        result["report"] = report
        flight.flush()
        let file = (try? String(contentsOf: FlightRecorder.url, encoding: .utf8)) ?? ""
        result["fileHasJump"] = file.contains("JUMP")
        result["passed"] = ["farOutsideLogged", "ownMoveLogged", "smallOutsideLogged", "ownMoveNotOutside",
                            "screensLogged", "checkBefore", "checkAfter", "backInPlace", "fileHasJump"]
            .allSatisfy { result[$0] as? Bool == true }
            && (result["jumpsCounted"] as? Int ?? 0) >= 2
            && misplaced?.allPassed == false
    }

    /// Opt-in (`YOUNGBAR_APPEARANCETEST=1`): the ••• must take the menu bar's
    /// look whatever YoungBar's own appearance setting is. Steps the setting
    /// through System / Light / Dark in memory only, then restores it.
    /// `YOUNGBAR_APPEARANCE_HOLD=<seconds>` holds each step for a screenshot
    /// (`screencapture -x -R <control frame>`).
    func runAppearanceTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "appearancetest.json") }
        func look(_ appearance: NSAppearance?) -> String {
            guard let appearance else { return "none" }
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        }
        // Whether macOS set the bar's look somewhere between the status
        // item's button and its window (else the button inherits YoungBar's).
        var explicit = false
        var view: NSView? = statusItem.button
        while let current = view, !explicit { explicit = current.appearance != nil; view = current.superview }
        result["barLookSetBySystem"] = explicit || statusItem.button?.window?.appearance != nil
        result["systemStyle"] = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
        let original = options[.appearanceMode]
        let hold = Double(ProcessInfo.processInfo.environment["YOUNGBAR_APPEARANCE_HOLD"] ?? "")
        var steps: [[String: Any]] = []
        var passed = controlPanel != nil
        for mode in AppearanceMode.allCases {
            options[.appearanceMode] = mode.rawValue
            applyAppearance()
            try? await Task.sleep(for: .milliseconds(400))
            let bar = look(menuBarAppearance)
            let control = look(controlPanel?.effectiveAppearance)
            steps.append(["mode": mode.rawValue, "app": look(NSApp.effectiveAppearance),
                          "statusButton": look(statusItem.button?.effectiveAppearance),
                          "bar": bar, "control": control,
                          "controlFrame": controlPanel.map { NSStringFromRect($0.frame) } ?? ""])
            if bar == "none" || control != bar { passed = false }
            if let hold { try? await Task.sleep(for: .seconds(hold)) }
        }
        options[.appearanceMode] = original
        applyAppearance()
        result["steps"] = steps
        // The control's look must not change with YoungBar's own setting.
        result["controlIgnoresSetting"] = Set(steps.compactMap { $0["control"] as? String }).count == 1
        result["restored"] = options[.appearanceMode] == original
        result["passed"] = passed && (result["controlIgnoresSetting"] as? Bool == true)
    }

    /// Opt-in (`YOUNGBAR_BARLOOKTEST=<seconds>`): records every change in what
    /// the window server, the status item's button and the ••• report, for
    /// that long, while the desktops are switched from outside (wallpapers
    /// can differ per desktop). Passes when the ••• never stays off the bar's
    /// look for more than 2 s. `YOUNGBAR_BARLOOK_DISTRUST=1` runs it as after
    /// a failed launch check: the ••• must then go by the button instead.
    func runBarLookTest(seconds: Double) async {
        func look(_ appearance: NSAppearance?) -> String {
            guard let appearance else { return "none" }
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        }
        let trustedBefore = menuBarThemeTrusted
        if ProcessInfo.processInfo.environment["YOUNGBAR_BARLOOK_DISTRUST"] == "1" {
            menuBarThemeTrusted = false
            syncControlAppearance()
        }
        var samples: [[String: Any]] = []
        var last = ""
        var themes: Set<Int32> = []
        var spaces: Set<UInt64> = []
        var mismatchSince: Date?
        var longestMismatch = 0.0
        let started = Date()
        func at(_ date: Date) -> Double { (date.timeIntervalSince(started) * 100).rounded() / 100 }
        @MainActor final class Notices { var times: [Date] = [] }
        let notices = Notices()
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            let now = Date()
            Task { @MainActor in notices.times.append(now) }
        }
        while Date().timeIntervalSince(started) < seconds {
            let button = statusItem.button
            let space = MenuBarLook.space(on: controlPanel?.screen)
            let theme = space.flatMap { MenuBarLook.rawTheme(space: $0) }
            if let space { spaces.insert(space) }
            if let theme { themes.insert(theme) }
            let bar = look(menuBarAppearance)
            let control = look(controlPanel?.effectiveAppearance)
            let state: [String: String] = [
                "app": look(NSApp.effectiveAppearance),
                "bar": bar,
                "button": look(button?.effectiveAppearance),
                "control": control,
                "space": space.map(String.init) ?? "none",
                "theme": theme.map(String.init) ?? "none",
                "window": look(button?.window?.effectiveAppearance),
            ]
            let line = state.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            if line != last {
                samples.append(["t": at(Date()), "state": line])
                last = line
            }
            let now = Date()
            if control == bar {
                mismatchSince = nil
            } else {
                let since = mismatchSince ?? now
                mismatchSince = since
                longestMismatch = max(longestMismatch, now.timeIntervalSince(since))
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        let distrusted = !menuBarThemeTrusted
        // The launch check, run here: away from the launch desktop the button
        // can differ from the window server, and then the check must say so.
        menuBarThemeTrusted = true
        syncControlAppearance()
        let endButton = look(statusItem.button?.effectiveAppearance)
        let endBar = look(menuBarAppearance)
        checkMenuBarTheme()
        let checkTrusts = menuBarThemeTrusted
        menuBarThemeTrusted = trustedBefore
        syncControlAppearance()
        writeJSON(["at": ISO8601DateFormatter().string(from: Date()), "samples": samples,
                   "launchCheckAtEnd": ["button": endButton, "theme": endBar, "trusts": checkTrusts],
                   "spaceNotices": notices.times.map(at),
                   "spaces": spaces.sorted().map(String.init),
                   "themes": themes.sorted().map(Int.init),
                   "distrusted": distrusted,
                   "buttonName": statusItem.button?.effectiveAppearance.name.rawValue ?? "none",
                   "longestMismatch": (longestMismatch * 100).rounded() / 100,
                   "passed": longestMismatch < 2 && !samples.isEmpty], name: "barlooktest.json")
    }

    /// Opt-in (`YOUNGBAR_EMPTYSHELFTEST=1`): with nothing hidden, the strip
    /// opens offering the bar's icons; clicking one tucks it in at once and
    /// the strip stays open. Every Hidden icon is shown for the test (Always
    /// Hidden ones stay hidden); saved modes and order are put back after.
    func runEmptyShelfTest() async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date())]
        defer { writeJSON(result, name: "emptyshelftest.json") }
        await refresh()
        let originalModes = modes
        let originalOrder = savedOrder
        func restore() async {
            closeShelf()
            for _ in 0..<50 where busy || tuckInApplying { try? await Task.sleep(for: .milliseconds(100)) }
            modes = originalModes
            UserDefaults.standard.set(modes, forKey: "itemModes")
            UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
            // Shown icons re-sync the saved order to the bar; put it back.
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
            result["orderRestored"] = savedOrder == originalOrder
            result["concealedAfter"] = after.concealed.map(\.sectionKey.rawValue).sorted()
        }
        // In memory only, until the restore below.
        for (key, mode) in modes where mode == 1 { modes[key] = 0 }
        busy = true
        await engine.conceal()
        await engine.setModel(currentModel())
        busy = false
        try? await Task.sleep(for: .milliseconds(1500))
        await refresh()
        closeShelf()
        includeAlwaysHidden = false
        showShelf()
        try? await Task.sleep(for: .milliseconds(300))
        let offered = tuckInCandidates()
        result["stripKeysAtOpen"] = shelfKeys()
        result["adding"] = shelfAdding
        result["offered"] = offered
        result["alphaAfterOpen"] = Double(shelfPanel?.alphaValue ?? 0)
        result["stripHeight"] = Double(shelfPanel?.frame.height ?? 0)
        guard shelfKeys().isEmpty else {
            // Showing every icon crowded the bar: the covered ones fill the strip.
            result["skipped"] = "the strip is not empty with every icon shown"
            await restore()
            return
        }
        // A third-party app's icon, so putting it back is a plain show.
        let target = offered.first { catalog[$0]?.id.bundleID.map { !$0.hasPrefix("com.apple.") } ?? false } ?? offered.first
        guard let target, let content = shelfPanel?.contentView,
              let button = findButton(in: content, key: target, action: #selector(tuckInFromShelf(_:))) else {
            result["skipped"] = offered.isEmpty ? "nothing offered" : "no button for the offered icon"
            await restore()
            return
        }
        result["target"] = target
        tuckInFromShelf(button)
        result["inStripAtOnce"] = shelfKeys().contains(target)
        for _ in 0..<40 where tuckInApplying { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(800))
        await refresh()
        let snapshot = await engine.freshSnapshot()
        result["modeAfter"] = modes[target] ?? 0
        result["concealed"] = snapshot.concealed.contains { $0.sectionKey.rawValue == target }
        result["stillOpen"] = expanded
        result["stillOffering"] = shelfAdding
        result["stripButtons"] = shelfButtons.compactMap { $0.identifier?.rawValue }
        await restore()
        result["passed"] = (result["adding"] as? Bool == true) && !offered.isEmpty
            && (result["inStripAtOnce"] as? Bool == true) && (result["concealed"] as? Bool == true)
            && (result["stillOpen"] as? Bool == true) && (result["restored"] as? Bool == true)
            && (result["alphaAfterOpen"] as? Double ?? 0) > 0.99
    }

    /// Opt-in (`YOUNGBAR_LAUNCHTEST=<bundle id>`): quits that app and opens it
    /// again, then checks its icon is back. Pick a menu-bar utility with no
    /// documents (it really quits). With anything hidden, macOS parks a new
    /// registration off screen; EngineSync has to adopt it. A Show icon must
    /// be back on the bar; a Hidden one must not be.
    func runLaunchTest(bundle: String) async {
        var result: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "bundle": bundle]
        defer { writeJSON(result, name: "launchtest.json") }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle }),
              let url = app.bundleURL else {
            result["skipped"] = "not running"
            return
        }
        let key = catalog.first { $0.value.id.bundleID == bundle }?.key
        let mode = key.flatMap { modes[$0] } ?? 0
        result["key"] = key ?? ""
        result["mode"] = mode
        // Without an assertion nothing parks, and the case isn't tested.
        result["holdsAssertion"] = await engine.holdsAssertion
        _ = app.terminate()
        for _ in 0..<40 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(250)) }
        result["quit"] = app.isTerminated
        try? await Task.sleep(for: .seconds(1))
        let started = Date()
        result["reopened"] = NSWorkspace.shared.open(url)
        // The launch handler waits up to 6 s for the item, then adopts it.
        var onBar = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))
            onBar = await engine.freshSnapshot().items.contains { $0.id.bundleID == bundle && $0.frame != nil }
            if onBar && mode == 0 { break }
        }
        result["secondsUntilBack"] = onBar ? Date().timeIntervalSince(started) : -1
        result["onBarAfterLaunch"] = onBar
        let inStrip = shelfKeys().contains { catalog[$0]?.id.bundleID == bundle }
        let inSettings = barEntries().contains { catalog[$0.key]?.id.bundleID == bundle }
        result["inStripAfterLaunch"] = inStrip
        result["inSettingsAfterLaunch"] = inSettings
        // Off the bar is only right if it can still be reached: a parked icon
        // once dropped out of the strip and Settings as well.
        result["passed"] = (result["quit"] as? Bool == true) && inSettings
            && (mode == 0 ? onBar : !onBar && inStrip)
    }

    /// The button for `key` sending `action`, anywhere under `view`.
    func findButton(in view: NSView, key: String, action: Selector) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == key, button.action == action { return button }
        for subview in view.subviews {
            if let found = findButton(in: subview, key: key, action: action) { return found }
        }
        return nil
    }
}
#endif
