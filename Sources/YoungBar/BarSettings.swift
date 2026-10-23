// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

struct BarEntry {
    let key: String
    let name: String
    let image: NSImage?
    let mode: Int
    let pinned: Bool
}

/// The settings window. Sidebar and detail are SwiftUI (`SettingsView.swift`); this
/// class owns the AppKit window and translates `SettingsAction`s into the
/// callbacks `BarApp` already handles.
@MainActor
final class BarSettings: NSObject {
    var onMode: ((String, Int) -> Void)?
    var onMove: ((String, String) -> Void)?
    var onRefresh: (() -> Void)?
    var onOption: ((String, Int) -> Void)?
    var onLogin: ((Bool) -> Void)?
    var onPermission: ((String) -> Void)?
    var onSpacing: ((Int) -> Void)?
    var onCustomIcon: (() -> Void)?
    var onRemoveCustomIcon: (() -> Void)?

    private let window: NSWindow
    private let model = SettingsModel()
    private let glass = NSGlassEffectView()
    private(set) var refreshClickCount = 0

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = SettingsPage.general.title
        window.isReleasedWhenClosed = false
        // No toolbar: the traffic lights float on the glass and each page
        // draws its own title. `title` still names the window in Mission
        // Control and the Window menu.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // The whole window is tinted glass, as before the SwiftUI move. The
        // sidebar adds the translucent behind-window sidebar material on top;
        // the detail column is transparent and only lays a light scrim.
        window.isOpaque = false
        window.backgroundColor = .clear
        let split = NSSplitViewController()
        split.splitView = SeamlessSplitView()
        split.splitView.isVertical = true
        let sidebarHost = NSHostingController(rootView: SettingsSidebar(model: model))
        sidebarHost.sizingOptions = []
        let sidebarMaterial = NSVisualEffectView()
        sidebarMaterial.material = .sidebar
        sidebarMaterial.blendingMode = .behindWindow
        sidebarMaterial.state = .followsWindowActiveState
        let sidebarController = NSViewController()
        sidebarController.view = sidebarMaterial
        sidebarController.addChild(sidebarHost)
        sidebarHost.view.frame = sidebarMaterial.bounds
        sidebarHost.view.autoresizingMask = [.width, .height]
        sidebarMaterial.addSubview(sidebarHost.view)
        let sidebar = NSSplitViewItem(viewController: sidebarController)
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 220
        sidebar.canCollapse = false
        let detailHost = NSHostingController(rootView: SettingsDetailView(model: model))
        detailHost.sizingOptions = []
        let detail = NSSplitViewItem(viewController: detailHost)
        detail.minimumThickness = 500
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(detail)

        glass.style = .regular
        glass.cornerRadius = 0
        let root = NSViewController()
        root.view = glass
        root.addChild(split)
        glass.contentView = split.view
        window.contentViewController = root

        window.minSize = NSSize(width: 740, height: 480)
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        window.setFrameAutosaveName("YoungBarSettings")
        model.onPageChange = { [weak self] page in self?.window.title = page.title }
        model.send = { [weak self] action in self?.handle(action) }
    }

    private func handle(_ action: SettingsAction) {
        switch action {
        case .option(let key, let value): onOption?(key, value)
        case .mode(let key, let mode): onMode?(key, mode)
        case .move(let key, let before): onMove?(key, before)
        case .login(let enabled): onLogin?(enabled)
        case .permission(let kind): onPermission?(kind)
        case .spacing(let level): onSpacing?(level)
        case .chooseCustomIcon: onCustomIcon?()
        case .removeCustomIcon: onRemoveCustomIcon?()
        case .refresh:
            refreshClickCount += 1
            onRefresh?()
        }
    }

    // MARK: - State

    var isVisible: Bool { window.isVisible }
    var windowForCapture: NSWindow { window }

    func close() { window.close() }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func select(_ page: SettingsPage) { model.page = page }

    /// Re-reads localized strings that live outside SwiftUI.
    func languageChanged() { window.title = (model.page ?? .general).title }

    func update(entries: [BarEntry], message: String, axTrusted: Bool,
                launchAtLogin: Bool, customIcon: NSImage?, options: [String: Int]) {
        // `update` runs on every refresh tick; only touch what changed so an
        // open picker or a drag in progress is not rebuilt underneath the user.
        let signature: (BarEntry) -> String = { "\($0.key)|\($0.name)|\($0.mode)|\($0.pinned)" }
        if model.entries.map(signature) != entries.map(signature) { model.entries = entries }
        if model.options != options { model.options = options }
        if model.message != message { model.message = message }
        if model.axTrusted != axTrusted { model.axTrusted = axTrusted }
        if model.launchAtLogin != launchAtLogin { model.launchAtLogin = launchAtLogin }
        if model.customIcon !== customIcon { model.customIcon = customIcon }
        let theme = ThemeColor(rawValue: options["themeColor"] ?? 0) ?? .blue
        let tinted = (ThemeScope(rawValue: options["themeScope"] ?? 0) ?? .both) != .stripOnly
        glass.tintColor = tinted && theme != .clear ? theme.accent.withAlphaComponent(0.10) : nil
    }

    // MARK: - Self-test support

    var currentEntries: [BarEntry] { model.entries }
    var currentPage: SettingsPage { model.page ?? .general }
    var windowFrame: NSRect { window.frame }
    var windowTitle: String { window.title }

    /// Converts a frame recorded in SwiftUI's global space (the window's
    /// content, sidebar included) to screen space.
    func screenRect(for key: String) -> NSRect? {
        guard window.isVisible, let view = window.contentView, let rect = model.frames[key] else { return nil }
        let local = view.isFlipped
            ? rect
            : NSRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        return window.convertToScreen(view.convert(local, to: nil))
    }

    func refreshButtonScreenRect() -> NSRect? {
        guard model.page == .general else { return nil }
        return screenRect(for: "refresh")
    }

    /// Diagnostic: what would receive a click on the login switch?
    func loginHitTest() -> [String: Any] {
        var chain: [String] = []
        var point = NSPoint.zero
        if let screen = screenRect(for: "login"), let content = window.contentView {
            let windowRect = window.convertFromScreen(screen)
            point = NSPoint(x: windowRect.midX, y: windowRect.midY)
            var view = content.hitTest(content.convert(point, from: nil))
            while let current = view {
                chain.append(String(describing: type(of: current)))
                view = current.superview
            }
        }
        return [
            "point": NSStringFromPoint(point),
            "chain": chain,
            "isKey": window.isKeyWindow,
            "ignoresMouse": window.ignoresMouseEvents,
            "isVisible": window.isVisible,
            "contentFrame": NSStringFromRect(window.contentView?.frame ?? .zero),
        ]
    }

    /// Renders each page to PNG without Screen Recording permission.
    /// Used by the agent's `YOUNGBAR_SNAPSHOT_DIR` live check.
    func writeSnapshots(to directory: String) async {
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let original = model.page
        for page in SettingsPage.allCases {
            model.page = page
            try? await Task.sleep(for: .milliseconds(400))
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: base.appendingPathComponent("\(page.rawValue).png"))
        }
        model.page = original
    }
}

/// No divider between sidebar and content: the sidebar's material is the
/// boundary, as in the original design. The sidebar width is fixed, so
/// there is nothing to drag.
final class SeamlessSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 0 }
    override var dividerColor: NSColor { .clear }
    override func drawDivider(in rect: NSRect) {}
}
