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

/// The ••• control: a small panel floating over YoungBar's own (blank)
/// status item, the right-click menu, and the menu-bar button's picture.
extension BarApp {
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showConfigurationMenu()
            return
        }
        toggleShelf()
    }

    func showConfigurationMenu() {
        let menu = configurationMenu()
        if let event = NSApp.currentEvent, let button = controlButton ?? statusItem.button {
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

    func installControlPanelWhenReady() async {
        for _ in 0..<15 {
            if installControlPanel() { return }
            try? await Task.sleep(for: .milliseconds(60))
        }
        // Keep the control reachable if the system never exposes the status
        // item's final frame before the hide assertion starts.
        guard let screen = NSScreen.screens.first else { return }
        let fallback = NSRect(x: screen.frame.maxX - 88, y: screen.frame.maxY - 27,
                              width: 22, height: 22)
        makeControlPanel(at: fallback)
    }

    func installControlPanel() -> Bool {
        guard let button = statusItem.button,
              let host = button.window,
              let screen = host.screen ?? NSScreen.screens.first else { return false }
        let frame = host.convertToScreen(button.convert(button.bounds, to: nil))
        // The assessment interface can hand back a status-item window that
        // sits below the menu bar. Only accept a frame that is actually in it.
        guard frame.width > 0, frame.height > 0, frame.height <= 40,
              frame.minY >= screen.frame.maxY - 45,
              frame.midX >= screen.frame.minX + 30 else { return false }
        makeControlPanel(at: frame)
        return true
    }

    func makeControlPanel(at frame: NSRect) {
        let size = NSSize(width: max(34, frame.width), height: max(24, frame.height))
        controlWidth = size.width
        // Centred in the menu bar, not on the status item's window: macOS
        // can report that window lower, and the control then hung half
        // below the bar (user report, 0.1.4).
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
            ?? NSScreen.screens.first
        let midY = screen.map { $0.frame.maxY - menuBarHeight(of: $0) / 2 } ?? frame.midY
        let hitFrame = NSRect(x: frame.midX - size.width / 2,
                              y: midY - size.height / 2,
                              width: size.width, height: size.height)
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
        control.hover = { [weak self] entered in
            guard let self else { return }
            isHovered = entered
            if entered && options[.hoverExpand] == 1 {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if isHovered && !expanded && !busy {
                        toggleShelfFrom(keyboard: false, byHover: true)
                        hoverOpenedAt = Date()
                    }
                }
            }
        }
        control.rightClick = { [weak self] in self?.showConfigurationMenu() }
        panel.contentView = control
        controlPanel = panel
        controlButton = control
        syncControlAppearance()
        panel.orderFrontRegardless()
        applyUpdateNotice()
        if let controlMoveObserver { NotificationCenter.default.removeObserver(controlMoveObserver) }
        controlMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.controlDidMove() }
        }
        flight.controlFrame = panel.frame
        flight.note("••• installed x\(Int(panel.frame.minX)) y\(Int(panel.frame.minY)) w\(Int(panel.frame.width)) · screens \(screenLayoutText)")
    }

    /// What the menu bar itself looks like. It isn't YoungBar's appearance:
    /// the user can force Light or Dark for YoungBar's windows, and the bar
    /// follows the wallpaper of the desktop on screen, which the window
    /// server knows (`MenuBarLook`). YoungBar's own (blank) status item is
    /// the fallback: its button carries the bar's look whatever YoungBar
    /// forces, but never changes after launch, so it stays on the desktop
    /// YoungBar started on. The system setting is no substitute: with system
    /// Light on a dark wallpaper it drew a dark ••• on a dark bar.
    var menuBarAppearance: NSAppearance? {
        if menuBarThemeTrusted, let dark = MenuBarLook.isDark(on: controlPanel?.screen) {
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
    func checkMenuBarTheme() {
        guard let button = statusItem?.button, button.window != nil,
              let dark = MenuBarLook.isDark(on: controlPanel?.screen) else { return }
        guard dark != (button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) else { return }
        NSLog("YoungBar: the window server's menu-bar look differs from the status item's; using the status item's")
        flight.note("menu bar look: window server differs from the status item; using the status item")
        menuBarThemeTrusted = false
        syncControlAppearance()
    }

    /// The ••• is drawn in YoungBar's own panel, which would otherwise take
    /// YoungBar's appearance and could end up white on a light bar (or black
    /// on a dark one). Cheap: runs on every refresh and appearance change.
    func syncControlAppearance() {
        guard let panel = controlPanel, let target = menuBarAppearance else { return }
        guard panel.appearance?.name != target.name else { return }
        panel.appearance = target
        controlButton?.needsDisplay = true
    }

    /// The menu bar's height on `screen` (taller on a notched built-in).
    /// When the bar hides itself the visible frame reaches the top: the
    /// notch's height then, or the status bar's thickness.
    func menuBarHeight(of screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        if height >= 20 && height <= 50 { return height }
        return max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
    }

    /// The leftmost icon the ••• sits beside on `screen`. Icons held by macOS's
    /// « (or under the notch) are not on the bar; following them would take
    /// the control out of sight too.
    func leadingIcon(in snapshot: EngineSnapshot, on screen: NSScreen) -> (key: String, frame: CGRect)? {
        let outOfSight = outOfSightKeys(snapshot)
        return snapshot.items.compactMap { item -> (key: String, frame: CGRect)? in
            let key = item.id.sectionKey.rawValue
            guard let frame = item.frame,
                  item.id.bundleID != Bundle.main.bundleIdentifier,
                  !outOfSight.contains(key),
                  frame.minX > screen.frame.midX,
                  frame.minX < screen.frame.maxX else { return nil }
            return (key, frame)
        }.min { $0.frame.minX < $1.frame.minX }
    }

    func positionControlBesideMenuIcons(in snapshot: EngineSnapshot) {
        guard let panel = controlPanel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        let outOfSight = outOfSightKeys(snapshot)
        // Item frames are in the global top-left space: this screen's bar
        // runs from `barTop` down.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let barTop = primaryTop - screen.frame.maxY
        guard let leading = leadingIcon(in: snapshot, on: screen) else {
            if flight.hadIconToFollow {
                flight.hadIconToFollow = false
                flight.note("••• no icon to follow on this bar; stays at x\(Int(panel.frame.minX))")
            }
            return
        }
        flight.hadIconToFollow = true
        let leadingFrame = leading.frame
        let leadingIcon = leadingFrame.minX
        // Level with the icons beside it.
        var y = panel.frame.minY
        if leadingFrame.minY - barTop > -5, leadingFrame.maxY - barTop < 50 {
            y = (primaryTop - leadingFrame.midY - panel.frame.height / 2).rounded()
        }
        let floor = notchVisibleMinX ?? (screen.frame.minX + 12)
        var width = controlWidth
        var x = max(floor, leadingIcon - width - 6)
        var inPile = false
        // A full bar: YoungBar's own item is in macOS's « with the others,
        // and the « sits at the right of their pile. The control takes the
        // free left part of that slot, narrowed so it doesn't cover the «.
        let ownKey = snapshot.items.first { $0.id.bundleID == Bundle.main.bundleIdentifier }?.id.sectionKey.rawValue
        if let ownKey, outOfSight.contains(ownKey),
           let pile = snapshot.items.compactMap({ item -> CGFloat? in
               guard let frame = item.frame, outOfSight.contains(item.id.sectionKey.rawValue),
                     frame.minX > screen.frame.midX - 400, frame.minX < leadingIcon else { return nil }
               return frame.minX
           }).min() {
            width = 22
            x = max(floor, pile)
            inPile = true
        }
        if abs(panel.frame.minX - x) > 1 || abs(panel.frame.width - width) > 0.5 || abs(panel.frame.minY - y) > 0.5 {
            // Slide with the bar's own shift instead of jumping a beat later.
            let origin = NSPoint(x: x, y: y)
            // (`animator()` on this panel never applied the move, leaving
            // the control wherever it was installed.)
            let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && abs(panel.frame.minX - x) < 200
            let target = NSRect(origin: origin, size: NSSize(width: width, height: panel.frame.height))
            let reason = "follows \(name(for: leading.key)) x\(Int(leadingIcon))"
                + (inPile ? " · in « pile" : "") + (x == floor ? " · at left limit" : "")
            recordControlMove(from: panel.frame, to: target, reason: reason, snapshot: snapshot)
            flight.controlFrame = target
            flight.ownMoveUntil = Date().addingTimeInterval(1)
            panel.setFrame(target, display: true, animate: animate)
            flight.ownMoveUntil = Date().addingTimeInterval(0.5)
        }
        if expanded && !shelfAnchored { positionShelf() }
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
        controlButton?.image = image
        controlButton?.contentTintColor = tint
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
