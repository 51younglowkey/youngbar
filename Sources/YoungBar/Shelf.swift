// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers
import PelmetCore
import PelmetEngine
import YoungBarCore

/// The strip (收纳条): opening and closing it, drawing its icons, and
/// opening an item from it in place.
extension BarApp {
    @objc func toggleShelf() {
        toggleShelfFrom(keyboard: false)
    }

    func toggleShelfFrom(keyboard fromKeyboard: Bool) {
        guard AXIsProcessTrusted(), AssessmentMode.isAvailable else {
            showConfigurationMenu()
            return
        }
        guard !busy else { return }
        if expanded {
            if !fromKeyboard, let opened = hoverOpenedAt, Date().timeIntervalSince(opened) < 1.5 { return }
            closeShelf()
        } else {
            let event = NSApp.currentEvent
            includeAlwaysHidden = !fromKeyboard && event?.type == .leftMouseUp && event?.modifierFlags.contains(.option) == true
            // Always the strip: it shows app icons, so nothing on the bar is
            // revealed to open it. (Showing the hidden icons in the bar
            // itself, the old "Show in bar" mode, flashed and doubled the
            // bar while it reflowed; it is gone.)
            showShelf(selectFirst: fromKeyboard)
            if fromKeyboard, whatsNewWindow?.isVisible == true { updateIntro?.triedShortcut = true }
            Task { await refresh() }
        }
    }

    func showShelf(selectFirst: Bool = false) {
        guard controlPanel != nil else { return }
        if shelfPanel == nil {
            let panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            panel.keyHandler = { [weak self] event in self?.handleShelfKey(event) ?? false }
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            shelfPanel = panel
        }
        expanded = true
        shelfAnchored = false
        shelfSelection = selectFirst ? 0 : nil
        shelfNumbered = options[.shelfNumbers] != 0
        shelfState = nil
        // Above the menu bar while browsing; lowered while an item's own menu
        // or panel is open so that opens on top of the strip.
        shelfPanel?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        populateShelf()
        guard let shelfPanel else { return }
        positionShelf()
        shelfPanel.orderFrontRegardless()
        shelfPanel.makeKeyAndOrderFront(nil)
    }

    func positionShelf() {
        guard let anchor = controlPanel, let shelfPanel,
              let screen = anchor.screen ?? NSScreen.screens.first else { return }
        let width = shelfPanel.frame.width
        // Centred under the control.
        let x = min(max(anchor.frame.midX - width / 2, screen.frame.minX + 8), screen.frame.maxX - width - 8)
        shelfPanel.setFrameOrigin(NSPoint(x: x, y: anchor.frame.minY - shelfPanel.frame.height - 7))
    }

    func closeShelf() {
        expanded = false
        hoverOpenedAt = nil
        shelfAnchored = false
        shelfSelection = nil
        shelfNumbered = false
        shelfPanel?.orderOut(nil)
    }

    func shelfKeys() -> [String] {
        return orderedKeys().filter {
            (modes[$0] ?? 0) == 1 || (includeAlwaysHidden && modes[$0] == 2) || overflowKeys.contains($0)
        }
    }

    func populateShelf() {
        guard let shelfPanel else { return }
        let keys = shelfKeys()
        let state = (shelfNumbered ? "#" : "") + keys.joined(separator: "|")
        guard state != shelfState || shelfPanel.contentView == nil else { return }
        shelfState = state
        // Each item shows its app's own icon (or the system symbol): sharp at
        // any size, unlike a menu-bar crop.
        let widths = keys.map { _ in CGFloat(40) }
        let itemContentWidth = widths.reduce(16, +)
        let screenWidth = (controlPanel?.screen ?? NSScreen.screens.first)?.frame.width ?? 800
        let gearWidth: CGFloat = 38
        let width = min(max(keys.isEmpty ? 150 : 100, itemContentWidth + gearWidth), screenWidth - 24)
        let height: CGFloat = 40
        shelfPanel.setContentSize(NSSize(width: width, height: height))
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let themeForStrip: ThemeColor? = themeColor
        let systemStrip = themeForStrip == nil || themeForStrip == .clear
        let lightStrip = systemStrip ? !isDark : false
        let iconColor: NSColor = lightStrip ? .black : .white
        shelfIconColor = iconColor

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
        shelfButtons = []
        if keys.isEmpty {
            let label = NSTextField(labelWithString: L10n.t("没有收纳项目", "No concealed items"))
            label.textColor = iconColor; label.alignment = .center
            label.frame = NSRect(x: 8, y: 11, width: itemArea - 16, height: 18)
            background.addSubview(label)
        } else {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: itemArea, height: height))
            scroll.drawsBackground = false; scroll.borderType = .noBorder
            scroll.hasHorizontalScroller = itemContentWidth > itemArea
            scroll.scrollerStyle = .overlay
            let document = NSView(frame: NSRect(x: 0, y: 0, width: max(itemContentWidth, itemArea), height: height))
            var x: CGFloat = 8
            for (index, key) in keys.enumerated() {
                let button = ShelfItemButton(frame: NSRect(x: x, y: 2, width: widths[index], height: 36))
                button.title = ""; button.isBordered = false
                button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
                button.identifier = .init(key); button.target = self; button.action = #selector(pressShelfItem(_:))
                // A copy: the cached icon is shared with the settings rows.
                let image = fallbackImage(for: key)?.copy() as? NSImage
                image?.size = NSSize(width: 22, height: 22)
                button.image = image
                let outOfSight = overflowKeys.contains(key) && (modes[key] ?? 0) == 0
                var tip = outOfSight ? L10n.t("\(name(for: key))（菜单栏放不下）", "\(name(for: key)) (no room in the menu bar)") : name(for: key)
                if index < 9 { tip += L10n.t("　键盘：\(index + 1)", "  Key: \(index + 1)") }
                button.toolTip = tip
                button.contentTintColor = iconColor
                button.setAccessibilityLabel(name(for: key))
                button.rightClick = { [weak self] button, event in self?.showShelfItemMenu(button, event: event) }
                // Only hidden icons reorder: a covered one keeps the bar's order.
                if (modes[key] ?? 0) > 0 {
                    button.dragMoved = { [weak self] button, dx in self?.shelfDragMoved(button, by: dx) }
                    button.dragEnded = { [weak self] button in self?.shelfDragEnded(button) }
                }
                if shelfNumbered && index < 9 {
                    let number = NSTextField(labelWithString: "\(index + 1)")
                    number.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
                    number.textColor = iconColor.withAlphaComponent(0.75)
                    number.alignment = .right
                    number.frame = NSRect(x: widths[index] - 13, y: button.isFlipped ? 24 : 0, width: 10, height: 12)
                    number.setAccessibilityElement(false)
                    button.addSubview(number)
                }
                document.addSubview(button)
                x += widths[index]
                shelfButtons.append(button)
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
        if let selection = shelfSelection { shelfSelection = shelfButtons.isEmpty ? nil : min(selection, shelfButtons.count - 1) }
        applyShelfSelection()
        positionShelf()
    }

    /// Orders the strip just below the frontmost window of `pid` that overlaps
    /// it, if there is one.
    func tuckShelf(below pid: pid_t) {
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

    @objc func openSettingsFromShelf() {
        closeShelf()
        showWindow()
    }

    @objc func pressShelfItem(_ button: NSButton) {
        guard !busy, let key = button.identifier?.rawValue, let item = catalog[key] else { return }
        // The strip stays where it is and the item's own menu or panel opens
        // next to it.
        flashPressed(button)
        shelfAnchored = true
        ignoreOutsideUntil = Date().addingTimeInterval(2)
        shelfPanel?.level = .floating
        let owner = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == item.id.bundleID }?.processIdentifier ?? 0
        // A covered item's menu opens under its slot, just below the notch:
        // still on screen, so it is pressed in place too.
        if let element = pressableElement(for: key, item: item, pid: owner),
           pressOpensNearStrip(key) || overflowKeys.contains(key) {
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
    func pressableElement(for key: String, item: ObservedItem, pid: pid_t) -> AXUIElement? {
        guard let element = statusElement(for: key, item: item, pid: pid) else { return nil }
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        guard ((actions as? [String]) ?? []).contains(kAXPressAction) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    /// The owning app's own status-item element (third-party apps with a
    /// single item). It stays in the app's AX tree while concealed.
    func statusElement(for key: String, item: ObservedItem, pid: pid_t, timeout: Float = 0.5) -> AXUIElement? {
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
    func pressOpensNearStrip(_ key: String) -> Bool {
        guard let point = axPosition(for: key), let control = controlPanel?.frame,
              let screen = controlPanel?.screen ?? NSScreen.screens.first else { return false }
        let near = point.x > screen.frame.midX && abs(point.x - control.midX) < 400
        if !near { NSLog("YoungBar: \(key) slot at x=\(point.x) is away from the control; revealing instead") }
        return near
    }

    func axPosition(for key: String) -> CGPoint? {
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
    func flashPressed(_ button: NSButton) {
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

    func outsideClick() {
        guard !busy, (ignoreOutsideUntil ?? .distantPast) < Date() else { return }
        let location = NSEvent.mouseLocation
        if expanded,
           shelfPanel?.frame.contains(location) != true,
           controlPanel?.frame.contains(location) != true { closeShelf() }
    }
}
