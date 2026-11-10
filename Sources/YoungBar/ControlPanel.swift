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

@MainActor
final class BarControlButton: NSButton {
    /// The display whose bar this ••• sits on.
    var displayID: CGDirectDisplayID?
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

/// The control never needs the keyboard: as a key window it took typing
/// away from the frontmost app at launch and after every display change.
@MainActor
final class BarControlPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// One display's •••. macOS draws a menu bar per display, so each has its own.
@MainActor
final class ControlSlot {
    let displayID: CGDirectDisplayID
    let panel: BarControlPanel
    let button: BarControlButton
    let createdAt = Date()
    var moveObserver: NSObjectProtocol?
    /// Where it was last seen, and until when a move is YoungBar's own. A move
    /// outside that came from macOS (or something else).
    var knownFrame: NSRect?
    var ownMoveUntil = Date.distantPast
    var hadIconToFollow = true

    init(displayID: CGDirectDisplayID, panel: BarControlPanel, button: BarControlButton) {
        self.displayID = displayID
        self.panel = panel
        self.button = button
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel.orderOut(nil)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// The ••• control: small panels floating on each display's bar over YoungBar's
/// own (blank) status item, the right-click menu, and the menu-bar button's picture.
extension BarApp {
    /// How strong a ••• is on a bar macOS has dimmed (the display that isn't
    /// active). Measured against the clock there: 0.45 on a 0.12 background,
    /// where the active bar's is 0.92 on 0.01.
    static let inactiveBarAlpha: CGFloat = 0.4

    /// The ••• the strip hangs from: where it was opened, else the primary display's.
    var anchorSlot: ControlSlot? {
        anchorDisplayID.flatMap { controlSlots[$0] }
            ?? NSScreen.screens.first?.displayID.flatMap { controlSlots[$0] }
            ?? controlSlots.values.first
    }

    var controlPanel: NSPanel? { anchorSlot?.panel }
    var controlButton: BarControlButton? { anchorSlot?.button }
    var anchorScreen: NSScreen? {
        anchorSlot.flatMap { screen(for: $0.displayID) } ?? NSScreen.screens.first
    }

    func setControlsIgnoreMouse(_ ignore: Bool) {
        for slot in controlSlots.values { slot.panel.ignoresMouseEvents = ignore }
    }

    @objc func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showConfigurationMenu()
            return
        }
        toggleShelfFrom(keyboard: false, on: (sender as? BarControlButton)?.displayID)
    }

    func showConfigurationMenu(for clicked: NSButton? = nil) {
        let menu = configurationMenu()
        if let event = NSApp.currentEvent, let button = clicked ?? controlButton ?? statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    func configurationMenu() -> NSMenu {
        let menu = NSMenu(title: "YoungBar")
        if let release = availableUpdate {
            let item = NSMenuItem(title: L10n.t("有新版本 \(release.version)，点此更新…", "YoungBar \(release.version) is available; update…"),
                                  action: #selector(checkForUpdates), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: L10n.t("允许「设备控制与数据访问」…", "Allow Device Control and Data Access…"), action: #selector(requestAccessibility), keyEquivalent: "")
        } else if !AssessmentMode.isAvailable {
            menu.addItem(withTitle: L10n.t("此系统上无法使用原生隐藏功能", "Native hiding is unavailable on this system"), action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: expanded ? L10n.t("收起收纳条", "Close strip") : L10n.t("打开收纳条", "Open strip"), action: #selector(toggleShelf), keyEquivalent: "")
            let shortcut = NSMenuItem(title: L10n.t("快捷键：\(hotKeyDisplay)", "Shortcut: \(hotKeyDisplay)"), action: nil, keyEquivalent: "")
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
        if bundledReleaseNotes != nil {
            menu.addItem(withTitle: L10n.t("本次更新内容…", "What's New…"), action: #selector(showWhatsNew), keyEquivalent: "")
        }
        menu.addItem(withTitle: L10n.t("复制诊断信息", "Copy Diagnostics"), action: #selector(copyDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("检查更新…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("退出 YoungBar", "Quit YoungBar"), action: #selector(quit), keyEquivalent: "")
        for item in menu.items where item.action != nil && item.target == nil { item.target = self }
        return menu
    }

    /// Waits for macOS to give YoungBar's status item its place, then puts a
    /// ••• on every display's bar.
    func installControlPanelWhenReady() async {
        for _ in 0..<15 {
            if let seed = statusItemFrameInBar() {
                installControlPanels(seed: seed)
                return
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        // Keep the control reachable if the system never exposes the status
        // item's final frame before the hide assertion starts.
        installControlPanels(seed: nil)
    }

    /// The status item's frame, if it is actually in a menu bar: the assessment
    /// interface can hand back a window that sits below it.
    func statusItemFrameInBar() -> NSRect? {
        guard let button = statusItem.button,
              let host = button.window,
              let screen = host.screen ?? NSScreen.screens.first else { return nil }
        let frame = host.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.width > 0, frame.height > 0, frame.height <= menuBarHeight(of: screen) + 5,
              frame.minY >= screen.frame.maxY - menuBarHeight(of: screen) - 5,
              frame.midX >= screen.frame.minX + ControlLayout.parkedSlotMargin else { return nil }
        return frame
    }

    func installControlPanels(seed: NSRect?) {
        if let seed { controlWidth = max(34, seed.width) }
        syncControlPanels(seed: seed)
        // Something is on screen from the start, even with no walk to place the
        // others (no permission yet).
        anchorSlot?.panel.orderFrontRegardless()
    }

    /// One ••• per display's bar. Called at launch and whenever displays are
    /// added, removed or rearranged. A display that keeps its ID keeps its •••;
    /// `placeControl` puts it back if macOS moved it.
    func syncControlPanels(seed: NSRect? = nil) {
        let screens = barScreens
        let wanted = Set(screens.compactMap(\.displayID))
        for (id, slot) in controlSlots where !wanted.contains(id) {
            if anchorDisplayID == id {
                closeShelf()
                anchorDisplayID = nil
            }
            flight.note("••• removed with display \(id)")
            slot.close()
            controlSlots[id] = nil
        }
        for screen in screens {
            guard let id = screen.displayID, controlSlots[id] == nil else { continue }
            let onSeed = seed.map { screen.frame.contains(NSPoint(x: $0.midX, y: $0.midY)) } ?? false
            let slot = makeControl(on: screen, id: id, minX: onSeed ? seed.map { $0.midX - controlWidth / 2 } : nil)
            controlSlots[id] = slot
            flight.note("••• \(displayLabel(slot))installed x\(Int(slot.panel.frame.minX)) y\(Int(slot.panel.frame.minY)) w\(Int(slot.panel.frame.width)) · screens \(screenLayoutText)")
        }
        applyUpdateNotice()
        if let lastSnapshot { positionControlBesideMenuIcons(in: lastSnapshot) }
        syncControlAppearance()
    }

    func makeControl(on screen: NSScreen, id: CGDirectDisplayID, minX: CGFloat?) -> ControlSlot {
        let size = NSSize(width: controlWidth, height: 24)
        // Centred in the menu bar, not on the status item's window: macOS
        // can report that window lower, and the control then hung half
        // below the bar (user report, 0.1.4).
        let midY = screen.frame.maxY - menuBarHeight(of: screen) / 2
        let x = minX ?? (screen.frame.maxX - size.width - ControlLayout.fallbackRightInset)
        let hitFrame = NSRect(x: x, y: midY - size.height / 2, width: size.width, height: size.height)
        let panel = BarControlPanel(contentRect: hitFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // `.fullScreenAuxiliary` stays: without it a full-screen space had
        // nothing to click at all (while anything is hidden macOS doesn't
        // draw YoungBar's own item). The cost, still open: the control
        // floats over the app when the full-screen menu bar is hidden.
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
        control.isBordered = false
        // A custom picture keeps its own colours; the symbols follow the bar.
        control.contentTintColor = (options[.controlIcon] ?? 0) == ControlIcon.symbols.count ? nil : .labelColor
        control.setAccessibilityLabel("YoungBar")
        control.target = self
        control.action = #selector(statusClicked)
        control.sendAction(on: [.leftMouseUp])
        control.displayID = id
        control.hover = { [weak self] entered in
            guard let self else { return }
            isHovered = entered
            if entered && options[.hoverExpand] == 1 {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if isHovered && !expanded && !busy {
                        toggleShelfFrom(keyboard: false, byHover: true, on: id)
                        hoverOpenedAt = Date()
                    }
                }
            }
        }
        control.rightClick = { [weak self, weak control] in self?.showConfigurationMenu(for: control) }
        panel.contentView = control
        let slot = ControlSlot(displayID: id, panel: panel, button: control)
        slot.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self, weak slot] _ in
            Task { @MainActor in
                if let self, let slot { self.controlDidMove(slot) }
            }
        }
        slot.knownFrame = panel.frame
        return slot
    }

    /// What the menu bar looks like on the ••• the strip goes by.
    var menuBarAppearance: NSAppearance? { menuBarAppearance(on: anchorScreen) }

    /// What the menu bar itself looks like on `screen`. It isn't YoungBar's
    /// appearance: the user can force Light or Dark for YoungBar's windows, and
    /// the bar follows the wallpaper of the desktop on screen, which the window
    /// server knows (`MenuBarLook`). YoungBar's own (blank) status item is
    /// the fallback: its button carries the bar's look whatever YoungBar
    /// forces, but never changes after launch, so it stays on the desktop
    /// YoungBar started on. The system setting is no substitute: with system
    /// Light on a dark wallpaper it drew a dark ••• on a dark bar.
    func menuBarAppearance(on screen: NSScreen?) -> NSAppearance? {
        if menuBarThemeTrusted, let dark = MenuBarLook.isDark(on: screen) {
            // The pair that draws the ••• as strong as the icons beside it:
            // `.darkAqua` is dimmer on a dark bar, `.vibrantLight` paler on a
            // light one.
            return NSAppearance(named: dark ? .vibrantDark : .aqua)
        }
        if let button = statusItem?.button, button.window != nil { return button.effectiveAppearance }
        let systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return NSAppearance(named: systemDark ? .darkAqua : .aqua)
    }

    /// Soon after launch the button still shows the bar's real look. If the
    /// window server's answer differs then, a macOS update changed what that
    /// private call means (a failed call reads as Light): a dark ••• on every
    /// dark bar would be worse than one that doesn't follow the desktop.
    /// Asked about the display the button itself is on: another display can
    /// rightly show another desktop.
    func checkMenuBarTheme() {
        guard let button = statusItem?.button, let host = button.window,
              let dark = MenuBarLook.isDark(on: host.screen ?? NSScreen.screens.first) else { return }
        guard dark != (button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) else { return }
        NSLog("YoungBar: the window server's menu-bar look differs from the status item's; using the status item's")
        flight.note("menu bar look: window server differs from the status item; using the status item")
        menuBarThemeTrusted = false
        syncControlAppearance()
    }

    /// The ••• is drawn in YoungBar's own panels, which would otherwise take
    /// YoungBar's appearance and could end up white on a light bar (or black
    /// on a dark one). Each panel goes by its own display: another display can
    /// show another desktop. Cheap: runs on every refresh and appearance change.
    func syncControlAppearance() {
        for slot in controlSlots.values {
            guard let screen = screen(for: slot.displayID),
                  let target = menuBarAppearance(on: screen),
                  slot.panel.appearance?.name != target.name else { continue }
            slot.panel.appearance = target
            slot.button.needsDisplay = true
        }
        syncBarActivity()
    }

    /// macOS dims the bar of the display that isn't active, icons included.
    /// A ••• at full strength there would be the one bright thing on that bar.
    func syncBarActivity() {
        guard controlSlots.count > 1 else {
            controlSlots.values.first?.panel.alphaValue = 1
            return
        }
        for slot in controlSlots.values {
            let active = screen(for: slot.displayID).flatMap { MenuBarLook.isActiveBar(on: $0) } ?? true
            let alpha: CGFloat = active ? 1 : Self.inactiveBarAlpha
            if slot.panel.alphaValue != alpha { slot.panel.alphaValue = alpha }
        }
    }

    /// The menu bar's height on `screen` (taller on a notched built-in).
    /// When the bar hides itself the visible frame reaches the top: the
    /// notch's height then, or the status bar's thickness.
    func menuBarHeight(of screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        if height >= 20 && height <= 50 { return height }
        return max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
    }

    /// Displays that draw a menu bar: all of them, unless they share one set
    /// of desktops ("Displays have separate Spaces" off), when only the primary does.
    var barScreens: [NSScreen] {
        NSScreen.screensHaveSeparateSpaces ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
    }

    func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }

    /// The display the pointer is on, if it draws a bar; else the primary's.
    var pointerDisplayID: CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        let under = barScreens.first { NSMouseInRect(location, $0.frame, false) }
        return (under ?? NSScreen.screens.first)?.displayID
    }

    /// `screen` in the global top-left space AX frames use.
    func barDisplay(for screen: NSScreen) -> BarDisplay {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let frame = CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY,
                           width: screen.frame.width, height: screen.frame.height)
        let notched = screen.safeAreaInsets.top > 0
        return BarDisplay(frame: frame, barHeight: menuBarHeight(of: screen),
                          visibleMinX: notched ? screen.auxiliaryTopRightArea?.minX : nil)
    }

    /// `frame` (AppKit, bottom-left) in the global top-left space.
    func globalRect(_ frame: NSRect) -> CGRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Every item as `display`'s bar sees it. The snapshot keeps one copy of
    /// each item (the main display's); the rest come from the same walk.
    ///
    /// An app with several untitled icons (Stats, one per module) walks as
    /// one id, so the snapshot keeps one of its icons and which one changes
    /// from walk to walk. Every other place it has on this bar is an icon of
    /// its own here (`key#1`, …): the ••• went left of the narrow one and sat
    /// on the other (2026-11-10, Stats with its GPU module turned on).
    func barIcons(_ snapshot: EngineSnapshot, on display: BarDisplay) -> [BarIcon] {
        let own = Bundle.main.bundleIdentifier
        return snapshot.items.flatMap { item -> [BarIcon] in
            let key = item.id.sectionKey.rawValue
            let isOwn = item.id.bundleID == own
            let copies = barCopies[item.id] ?? []
            let here = copies.first { ControlLayout.isOnBar($0, of: display) }
                ?? item.frame.flatMap { ControlLayout.isOnBar($0, of: display) ? $0 : nil }
            let first = BarIcon(key: key, frame: here,
                                drawnElsewhere: here == nil && (!copies.isEmpty || item.frame != nil),
                                isOwn: isOwn)
            guard let here, !isOwn else { return [first] }
            let others = ControlLayout.distinctFrames(copies.filter { ControlLayout.isOnBar($0, of: display) },
                                                      besides: here)
            return [first] + others.enumerated().map { BarIcon(key: "\(key)#\($0.offset + 1)", frame: $0.element) }
        }
    }

    /// Reads the copies the engine's last walk found; call right after a walk.
    func refreshBarCopies() async {
        barCopies = await engine.barCopies()
    }

    func positionControlBesideMenuIcons(in snapshot: EngineSnapshot) {
        lastSnapshot = snapshot
        for slot in controlSlots.values { placeControl(slot, in: snapshot) }
        if expanded && !shelfAnchored { positionShelf() }
    }

    /// Puts this display's ••• on this display's bar, beside this display's
    /// icons. Nothing is kept from where it happened to be but its place along
    /// the bar, and only when there's no icon to go by.
    func placeControl(_ slot: ControlSlot, in snapshot: EngineSnapshot) {
        guard let screen = screen(for: slot.displayID) else { return }
        let panel = slot.panel
        let display = barDisplay(for: screen)
        let spot = ControlLayout.spot(icons: barIcons(snapshot, on: display), on: display,
                                      current: globalRect(panel.frame), width: controlWidth)
        let label = displayLabel(slot)
        var reason = "\(label)no icon to follow on this bar"
        var hasIcon = true
        switch spot.reason {
        case .beside(let key, let iconX):
            reason = "\(label)follows \(name(for: key)) x\(Int(iconX))"
        case .inPile(let key, let iconX):
            reason = "\(label)follows \(name(for: key)) x\(Int(iconX)) · in « pile"
        case .onOwnSlot(let key, let iconX):
            reason = "\(label)follows \(name(for: key)) x\(Int(iconX)) · on own slot"
        case .leftOfChevron(let key, let iconX, let chevron):
            reason = "\(label)follows \(name(for: key)) x\(Int(iconX)) · left of « x\(Int(chevron))"
        case .noIcon:
            hasIcon = false
            if slot.hadIconToFollow {
                slot.hadIconToFollow = false
                flight.note("••• \(label)no icon to follow on this bar; stays at x\(Int(panel.frame.minX))")
            }
        }
        if hasIcon { slot.hadIconToFollow = true }
        if spot.atLeftLimit { reason += " · at left limit" }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let y = (primaryTop - spot.midY - panel.frame.height / 2).rounded()
        if abs(panel.frame.minX - spot.minX) > 1 || abs(panel.frame.width - spot.width) > 0.5 || abs(panel.frame.minY - y) > 0.5 {
            // Slide with the bar's own shift instead of jumping a beat later.
            // (`animator()` on this panel never applied the move, leaving
            // the control wherever it was installed.)
            let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && panel.isVisible
                && abs(panel.frame.minX - spot.minX) < 200 && abs(panel.frame.minY - y) < 1
            let target = NSRect(x: spot.minX, y: y, width: spot.width, height: panel.frame.height)
            recordControlMove(from: panel.frame, to: target, reason: reason, snapshot: snapshot)
            slot.knownFrame = target
            slot.ownMoveUntil = Date().addingTimeInterval(1)
            panel.setFrame(target, display: true, animate: animate)
            slot.ownMoveUntil = Date().addingTimeInterval(0.5)
        }
        // A new display's ••• appears once it knows where to be, or after a
        // moment if this bar lists no icons at all (hidden, or still coming up).
        if !panel.isVisible, hasIcon || Date().timeIntervalSince(slot.createdAt) > 3 {
            panel.orderFrontRegardless()
        }
    }

    /// How a log line tells the •••s apart; nothing with one display.
    func displayLabel(_ slot: ControlSlot) -> String {
        guard controlSlots.count > 1,
              let index = NSScreen.screens.firstIndex(where: { $0.displayID == slot.displayID }) else { return "" }
        return "display \(index + 1) · "
    }

    var customControlIconURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YoungBar", isDirectory: true)
            .appendingPathComponent("control-icon.png")
    }

    func currentControlIcon() -> NSImage? {
        let index = options[.controlIcon] ?? 0
        let custom = index == ControlIcon.symbols.count ? customIconImage : nil
        return ControlIcon.image(index, custom: custom)
    }

    func applyControlIcon() {
        let index = options[.controlIcon] ?? 0
        let image = currentControlIcon()
        let tint: NSColor? = index == ControlIcon.symbols.count ? nil : .labelColor
        for slot in controlSlots.values {
            slot.button.image = image
            slot.button.contentTintColor = tint
        }
    }

    func removeCustomIcon() {
        try? FileManager.default.removeItem(at: customControlIconURL)
        customIconImage = nil
        // Back to the ellipsis only if the picture was the one in use.
        if options[.controlIcon] == ControlIcon.symbols.count { options[.controlIcon] = 0 }
        UserDefaults.standard.set(options, forKey: "barOptions")
        applyControlIcon()
        renderWindow(force: true)
    }

    func chooseControlIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.t("选择一张图片作为菜单栏图标", "Choose an image for the menu-bar button")
        guard panel.runModal() == .OK, let url = panel.url,
              let source = NSImage(contentsOf: url) else { return }
        let target = NSImage(size: NSSize(width: 36, height: 36))
        let box = NSRect(x: 0, y: 0, width: 36, height: 36)
        target.lockFocus()
        NSColor.clear.setFill()
        box.fill()
        // Scaled to fit, not stretched: a wide or tall picture keeps its shape.
        source.draw(in: ImageFit.aspectFit(source.size, in: box),
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
            options[.controlIcon] = ControlIcon.symbols.count
            UserDefaults.standard.set(options, forKey: "barOptions")
            applyControlIcon()
            renderWindow(force: true)
        } catch {
            NSLog("YoungBar custom icon save failed: \(error)")
        }
    }

    @objc func showAbout() {
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
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            .credits: credits,
        ])
    }

    @objc func refreshClicked() {
        Task { await refresh(); renderWindow(force: true) }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
