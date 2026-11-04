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

@MainActor
final class BarControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
            menu.addItem(withTitle: L10n.t("开启辅助功能权限…", "Open Accessibility…"), action: #selector(requestAccessibility), keyEquivalent: "")
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
                        toggleShelf()
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
        panel.makeKeyAndOrderFront(nil)
        applyUpdateNotice()
    }

    /// What the menu bar itself looks like. It isn't YoungBar's appearance:
    /// the user can force Light or Dark for YoungBar's windows, and the bar
    /// follows the wallpaper. YoungBar's own (blank) status item sits in the
    /// bar, so its button carries the bar's look — when macOS set that look
    /// on the status bar window. If the button only inherited YoungBar's
    /// forced choice, the system setting is the better answer.
    var menuBarAppearance: NSAppearance? {
        let systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let system = NSAppearance(named: systemDark ? .darkAqua : .aqua)
        guard let button = statusItem?.button, let window = button.window else { return system }
        var view: NSView? = button
        while let current = view {
            if current.appearance != nil { return button.effectiveAppearance }
            view = current.superview
        }
        if window.appearance != nil || NSApp.appearance == nil { return button.effectiveAppearance }
        return system
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

    func positionControlBesideMenuIcons(in snapshot: EngineSnapshot) {
        guard let panel = controlPanel,
              let screen = panel.screen ?? NSScreen.screens.first else { return }
        // Icons held by macOS's « (or under the notch) are not on the bar;
        // following them would take the control out of sight too.
        let outOfSight = outOfSightKeys(snapshot)
        let leadingIcon = snapshot.items.compactMap { item -> CGFloat? in
            guard let frame = item.frame,
                  item.id.bundleID != Bundle.main.bundleIdentifier,
                  !outOfSight.contains(item.id.sectionKey.rawValue),
                  frame.minX > screen.frame.midX,
                  frame.minX < screen.frame.maxX else { return nil }
            return frame.minX
        }.min()
        guard let leadingIcon else { return }
        let floor = notchVisibleMinX ?? (screen.frame.minX + 12)
        var width = controlWidth
        var x = max(floor, leadingIcon - width - 6)
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
        }
        if abs(panel.frame.minX - x) > 1 || abs(panel.frame.width - width) > 0.5 {
            // Slide with the bar's own shift instead of jumping a beat later.
            let origin = NSPoint(x: x, y: panel.frame.minY)
            // (`animator()` on this panel never applied the move, leaving
            // the control wherever it was installed.)
            let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && abs(panel.frame.minX - x) < 200
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: panel.frame.height)),
                           display: true, animate: animate)
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
        options[.controlIcon] = 0
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
