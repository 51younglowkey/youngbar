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

@MainActor
final class BarApp: NSObject, NSApplicationDelegate {
    let engine = AgentBarEngine()
    var statusItem: NSStatusItem!
    var knownBundles: [String: String] = [:]
    var modes: [String: Int] = {
        if let saved = UserDefaults.standard.dictionary(forKey: "itemModes") as? [String: Int] { return saved }
        return Dictionary(uniqueKeysWithValues: (UserDefaults.standard.stringArray(forKey: "hiddenBundles") ?? []).map { ("bundle:\($0)", 1) })
    }()
    var hiddenBundles: Set<String> {
        Set(modes.filter { $0.value > 0 }.keys.compactMap { ItemID(rawValue: $0).bundleID })
    }
    var savedOrder = UserDefaults.standard.stringArray(forKey: "itemOrder") ?? []
    var catalog: [String: ObservedItem] = [:]
    var presentKeys: Set<String> = []
    var shownUntil: [ItemID: Date] = [:]
    var settings: BarSettings?
    var busy = false
    var refreshing = false
    var includeAlwaysHidden = false
    var feedback = ""
    var options = UserDefaults.standard.dictionary(forKey: "barOptions") as? [String: Int] ?? [:]
    var isHovered = false
    var mouseMonitor: Any?
    var currentFrames: [CGRect] = []
    var revealSeconds: TimeInterval { TimeInterval(options[.revealSeconds] ?? 20) }
    var expanded = false
    var started = false
    var previousSessionCrashed = UserDefaults.standard.bool(forKey: "sessionActive")
    var rescueRequested = CommandLine.arguments.contains("--reveal-all")
    var timer: Timer?
    /// When the last menu-bar walk ran; the tick skips walks at rest.
    var lastRefreshAt = Date.distantPast
    var workspaceObservers: [NSObjectProtocol] = []
    var iconCache: [String: NSImage] = [:]
    var nameCache: [String: String] = [:]
    var controlPanel: NSPanel?
    var controlButton: BarControlButton?
    var shelfPanel: NSPanel?
    var gearButton: BarControlButton?
    var hotKeyRef: EventHotKeyRef?
    /// Presses delivered by Carbon; read by the self-tests.
    var hotKeyPressCount = 0
    var hotKeyHandler: EventHandlerRef?
    var shelfState: String?
    /// Typed into the open strip: filters it to matching items.
    var shelfQuery = ""
    /// Keyboard selection in the strip, an index into `shelfButtons`.
    var shelfSelection: Int?
    var shelfButtons: [BarControlButton] = []
    var shelfIconColor: NSColor = .white
    /// Items set to Show that sit under the notch, so nobody sees them.
    var overflowKeys: Set<String> = []
    /// The control's width beside a free bar; it narrows when crowded.
    var controlWidth: CGFloat = 34
    var guideWindow: NSWindow?
    var guideModel: GuideModel?
    var guideTimer: Timer?
    var guideCloseObserver: NSObjectProtocol?
    /// After an item is opened from the strip, the strip stays where it was
    /// (no re-centring on the control as the revealed item shifts it) until
    /// the strip closes.
    var shelfAnchored = false
    /// The strip's own synthetic click on the revealed item is not a click
    /// outside the strip.
    var ignoreOutsideUntil: Date?
    /// Set by `YOUNGBAR_SETTINGS_PREVIEW`: only the settings window runs.
    var previewOnly = false
    lazy var customIconImage: NSImage? = NSImage(contentsOf: customControlIconURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if YOUNGBAR_TESTHOOKS
        if let preview = ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGS_PREVIEW"] {
            // Must return before the session marker below: a preview runs
            // beside the live instance and shares its defaults.
            previewOnly = true
            if preview == "en" { options[.language] = 1 } else if preview == "zh" { options[.language] = 0 }
            // In memory only: the live instance shares these defaults.
            if let name = ProcessInfo.processInfo.environment["YOUNGBAR_SETTINGS_PREVIEW_THEME"],
               let theme = ["blue", "pink", "yellow", "clear"].firstIndex(of: name) {
                options[.themeColor] = theme
                options[.themeScope] = 0
            }
            L10n.current = Language(rawValue: options[.language] ?? 0) ?? .chinese
            NSApp.setActivationPolicy(.accessory)
            Task { await runSettingsPreview() }
            return
        }
        #endif
        L10n.current = Language(rawValue: options[.language] ?? 0) ?? .chinese
        UserDefaults.standard.set(true, forKey: "sessionActive")
        if Diagnostics.isEnabled {
            writeJSON(["args": CommandLine.arguments, "rescue": rescueRequested,
                       "crashed": previousSessionCrashed], name: "launch.json")
        }
        NSApp.setActivationPolicy(.accessory)
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
        startRefreshTriggers()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.outsideClick() }
        }
        registerHotKey()
        refreshLoginItemIfMoved()
        if needsGuide {
            showGuide()
        } else {
            markGuided()
            if !AXIsProcessTrusted() { showWindow() }
        }
        Task {
            await installControlPanelWhenReady()
            await refresh()
            Diagnostics.write(app: self, snapshot: nil)
            #if YOUNGBAR_TESTHOOKS
            await runLaunchHooks()
            #endif
            if options[.keepShelfOpen] == 1 { showShelf() }
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
        unregisterHotKey()
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        timer?.invalidate()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        Task { await engine.stop() }
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || options[.leftClickMenu] == 1 {
            showConfigurationMenu()
            return
        }
        toggleShelf()
    }

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
            closeShelf()
        } else {
            let event = NSApp.currentEvent
            includeAlwaysHidden = !fromKeyboard && event?.type == .leftMouseUp && event?.modifierFlags.contains(.option) == true
            Task {
                // The shortcut always opens the strip: that is where typing
                // and the arrow keys work.
                if options[.nativeExpand] == 1 && !includeAlwaysHidden && !fromKeyboard {
                    await refresh()
                    await revealHiddenSection()
                } else {
                    // The strip shows app icons; never reveal items to open it.
                    showShelf(selectFirst: fromKeyboard)
                    await refresh()
                }
            }
        }
    }

    var themeColor: ThemeColor {
        ThemeColor(rawValue: options[.themeColor] ?? 0) ?? .blue
    }

    var stripOpacity: CGFloat {
        CGFloat(stripOpacityPercent(options)) / 100
    }

    var themeScope: ThemeScope {
        ThemeScope(rawValue: options[.themeScope] ?? 0) ?? .both
    }

    func applyAppearance() {
        let mode = AppearanceMode(rawValue: options[.appearanceMode] ?? 0) ?? .system
        NSApp.appearance = mode.appearance
        NSApp.applicationIconImage = themeIcon(themeColor)
    }

    /// Every AX walk of the menu bar costs CPU, so walks follow what the
    /// user can see: once a second while the strip or settings are open or
    /// an item is revealed on a timer, every few seconds at rest. App
    /// launches and quits, wake and display changes walk right away.
    var refreshInterval: TimeInterval {
        let watching = expanded || settings?.isVisible == true || !shownUntil.isEmpty
        return watching ? 1 : 4
    }

    func startRefreshTriggers() {
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastRefreshAt) >= self.refreshInterval - 0.05 else { return }
                await self.refresh()
            }
        }
        tick.tolerance = 0.4
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        let center = NSWorkspace.shared.notificationCenter
        // A launching app adds its item a moment after the launch notice.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshSoon() }
            })
        }
        workspaceObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reinstallControlIfNeeded()
                self?.refreshSoon()
            }
        })
    }

    func refreshSoon() {
        Task {
            for delay in [400, 1600] {
                try? await Task.sleep(for: .milliseconds(delay))
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !busy, !refreshing, AXIsProcessTrusted(), AssessmentMode.isAvailable else { return }
        refreshing = true
        lastRefreshAt = Date()
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
        overflowKeys = computeOverflow(outOfSightKeys(snapshot))
        currentFrames = snapshot.items.compactMap(\.frame)
        positionControlBesideMenuIcons(in: snapshot)
        if expanded { populateShelf() }
        // The settings model only matters while its window is on screen;
        // `showWindow` renders in full when it opens.
        if settings?.isVisible == true { renderWindow() }
        Diagnostics.write(app: self, snapshot: snapshot)
    }

    func writeJSON(_ value: [String: Any], name: String) {
        let url = Diagnostics.url.deletingLastPathComponent().appendingPathComponent(name)
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func remember(_ snapshot: EngineSnapshot) {
        // A saved mode can outlive the menu-bar item (app quit or updated while
        // concealed). Only keys in the live snapshot are presentable.
        var present: Set<String> = []
        for item in snapshot.items { present.insert(item.id.sectionKey.rawValue) }
        for id in snapshot.concealed { present.insert(id.sectionKey.rawValue) }
        presentKeys = present

        var orderChanged = false
        let deduped = LayoutOrder.unique(savedOrder)
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
                let known = catalog.compactMapValues { $0.frame?.minX }
                savedOrder.insert(key, at: LayoutOrder.insertionIndex(forMinX: frame.minX, in: savedOrder, minX: known))
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
        let finalOrder = LayoutOrder.unique(savedOrder)
        if finalOrder != savedOrder { savedOrder = finalOrder; orderChanged = true }
        if orderChanged { UserDefaults.standard.set(savedOrder, forKey: "itemOrder") }
    }

    /// The table is the user's ordering model, but it must not drift from the
    /// real bar. Whenever the visible items disagree with their saved order,
    /// rewrite just those slots to the actual left-to-right order and persist.
    func reconcileVisibleOrder(_ snapshot: EngineSnapshot) {
        guard !busy else { return }
        let actual = LayoutOrder.unique(snapshot.items
            .filter { $0.frame != nil }
            .sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
            .map { $0.id.sectionKey.rawValue })
        guard let reconciled = LayoutOrder.reconciled(savedOrder, actual: actual) else { return }
        savedOrder = reconciled
        UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        Task { await engine.setModel(currentModel()) }
    }

    func name(for key: String) -> String {
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

    func orderedKeys() -> [String] {
        savedOrder.filter { catalog[$0] != nil && presentKeys.contains($0) }
            + catalog.keys.filter { !savedOrder.contains($0) && presentKeys.contains($0) }.sorted()
    }

    func appName(for bundle: String) -> String {
        if let cached = nameCache[bundle] { return cached }
        let name = lookUpAppName(for: bundle)
        // An unresolved id may resolve once the app is installed or running.
        if name != bundle { nameCache[bundle] = name }
        return name
    }

    func lookUpAppName(for bundle: String) -> String {
        if let name = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle })?.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundle
    }

    func showConfigurationMenu() {
        let menu = NSMenu(title: "YoungBar")
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
            let leftClick = NSMenuItem(title: L10n.t("左键点击显示菜单", "Show menu on left click"), action: #selector(toggleLeftClickMenu), keyEquivalent: "")
            leftClick.state = options[.leftClickMenu] == 1 ? .on : .off
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
        menu.addItem(withTitle: L10n.t("检查更新…", "Check for Updates…"), action: #selector(openReleases), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("退出 YoungBar", "Quit YoungBar"), action: #selector(quit), keyEquivalent: "")
        for item in menu.items where item.action != nil && item.target == nil { item.target = self }
        if let event = NSApp.currentEvent, let button = controlButton ?? statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
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
        shelfQuery = ""
        shelfSelection = selectFirst ? 0 : nil
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
        shelfAnchored = false
        shelfQuery = ""
        shelfSelection = nil
        shelfPanel?.orderOut(nil)
    }

    func shelfKeys() -> [String] {
        if !shelfQuery.isEmpty { return searchShelf(shelfQuery) }
        return orderedKeys().filter {
            (modes[$0] ?? 0) == 1 || (includeAlwaysHidden && modes[$0] == 2) || overflowKeys.contains($0)
        }
    }

    func populateShelf() {
        guard let shelfPanel else { return }
        let keys = shelfKeys()
        let state = shelfQuery + "#" + keys.joined(separator: "|")
        guard state != shelfState || shelfPanel.contentView == nil else { return }
        shelfState = state
        // Each item shows its app's own icon (or the system symbol): sharp at
        // any size, unlike a menu-bar crop.
        let widths = keys.map { _ in CGFloat(40) }
        let itemContentWidth = widths.reduce(16, +)
        let screenWidth = (controlPanel?.screen ?? NSScreen.screens.first)?.frame.width ?? 800
        let gearWidth: CGFloat = 38
        let queryText = NSMutableAttributedString()
        if let glass = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = glass.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            queryText.append(NSAttributedString(attachment: attachment))
            queryText.append(NSAttributedString(string: " "))
        }
        queryText.append(NSAttributedString(string: shelfQuery))
        queryText.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .medium),
                               range: NSRange(location: 0, length: queryText.length))
        let queryLabel = NSTextField(labelWithAttributedString: queryText)
        queryLabel.lineBreakMode = .byTruncatingHead
        let queryWidth: CGFloat = shelfQuery.isEmpty ? 0 : min(140, queryLabel.intrinsicContentSize.width + 16)
        let width = min(max(keys.isEmpty ? 150 : 100, queryWidth + itemContentWidth + gearWidth), screenWidth - 24)
        let height: CGFloat = 40
        shelfPanel.setContentSize(NSSize(width: width, height: height))
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let themed = themeScope != .interfaceOnly
        let themeForStrip: ThemeColor? = themed ? themeColor : nil
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
        let itemArea = width - gearWidth - queryWidth
        shelfButtons = []
        if queryWidth > 0 {
            queryText.addAttribute(.foregroundColor, value: iconColor, range: NSRange(location: 0, length: queryText.length))
            queryLabel.attributedStringValue = queryText
            queryLabel.frame = NSRect(x: 10, y: 11, width: queryWidth - 12, height: 18)
            queryLabel.setAccessibilityLabel(L10n.t("搜索：\(shelfQuery)", "Search: \(shelfQuery)"))
            background.addSubview(queryLabel)
        }
        if keys.isEmpty {
            let label = NSTextField(labelWithString: shelfQuery.isEmpty
                                    ? L10n.t("没有收纳项目", "No concealed items")
                                    : L10n.t("没有匹配的项目", "No matches"))
            label.textColor = iconColor.withAlphaComponent(shelfQuery.isEmpty ? 1 : 0.7); label.alignment = .center
            label.frame = NSRect(x: queryWidth + 8, y: 11, width: itemArea - 16, height: 18)
            background.addSubview(label)
        } else {
            let scroll = NSScrollView(frame: NSRect(x: queryWidth, y: 0, width: itemArea, height: height))
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
                // A copy: the cached icon is shared with the settings rows.
                let image = fallbackImage(for: key)?.copy() as? NSImage
                image?.size = NSSize(width: 22, height: 22)
                button.image = image
                let outOfSight = overflowKeys.contains(key) && (modes[key] ?? 0) == 0
                button.toolTip = outOfSight ? L10n.t("\(name(for: key))（菜单栏放不下）", "\(name(for: key)) (no room in the menu bar)") : name(for: key)
                button.contentTintColor = iconColor
                button.setAccessibilityLabel(name(for: key))
                document.addSubview(button); x += widths[index]
                shelfButtons.append(button)
            }
            scroll.documentView = document; background.addSubview(scroll)
        }

        let divider = NSView(frame: NSRect(x: queryWidth + itemArea, y: 8, width: 1, height: 24))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = iconColor.withAlphaComponent(0.18).cgColor
        background.addSubview(divider)

        let gear = BarControlButton(frame: NSRect(x: queryWidth + itemArea + 5, y: 6, width: 28, height: 28))
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

    func fallbackImage(for key: String) -> NSImage? {
        let id = catalog[key]?.id ?? ItemID(rawValue: key)
        if let system = MenuBarPolicy.systemItem(for: id) {
            let symbols: [SystemItem: String] = [.battery: "battery.100percent", .bluetooth: "network", .clock: "clock", .displays: "display", .keyboard: "keyboard", .volume: "speaker.wave.2", .wifi: "wifi", .screenMirroring: "airplayvideo", .primaryBentoBox: "switch.2"]
            return NSImage(systemSymbolName: symbols[system] ?? "circle", accessibilityDescription: name(for: key))
        }
        return id.bundleID.flatMap { icon(for: $0) }
    }

    func settledSnapshot(for ids: Set<ItemID>) async -> EngineSnapshot {
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

    func icon(for bundle: String) -> NSImage? {
        if let cached = iconCache[bundle] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        guard let url else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil) }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 28, height: 28)
        iconCache[bundle] = image
        return image
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

    func revealHiddenSection() async {
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

    func outsideClick() {
        guard !busy, (ignoreOutsideUntil ?? .distantPast) < Date() else { return }
        let location = NSEvent.mouseLocation
        if expanded && options[.keepShelfOpen] != 1,
           shelfPanel?.frame.contains(location) != true,
           controlPanel?.frame.contains(location) != true { closeShelf() }
        // The walk's frames are those of the control's bar.
        guard options[.blankClick] == 1, let screen = controlPanel?.screen ?? NSScreen.screens.first,
              location.y >= screen.frame.maxY - 40, location.x > screen.frame.midX,
              controlPanel?.frame.contains(location) != true else { return }
        let cgPoint = CGPoint(x: location.x, y: screen.frame.maxY - location.y)
        guard !currentFrames.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(cgPoint) }) else { return }
        statusClicked()
    }

    @objc func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        renderWindow()
    }

    @objc func showWindow() {
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
                if key == .language {
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
                if key == .controlIcon {
                    applyControlIcon()
                    renderWindow(force: true)
                    return
                }
                if [.appearanceMode, .themeColor, .stripOpacity, .themeScope].contains(key) {
                    applyAppearance()
                    shelfState = nil
                    if expanded { populateShelf() }
                    renderWindow(force: true)
                    return
                }
                if key == .keepShelfOpen {
                    if value == 1 { showShelf() }
                    else { closeShelf() }
                }
                if key == .notchOverflow {
                    shelfState = nil
                    Task { await refresh() }
                }
                renderWindow()
            }
            controller.onRefresh = { [weak self] in self?.refreshClicked() }
            controller.onHotKeyRecording = { [weak self] recording in
                if recording { self?.unregisterHotKey() } else { self?.registerHotKey() }
            }
            controller.onHotKey = { [weak self] combo in self?.setHotKey(combo) }
            controller.onExport = { [weak self] in self?.exportConfiguration() }
            controller.onImport = { [weak self] in self?.importConfiguration() }
            controller.onGuide = { [weak self] in self?.showGuide() }
            settings = controller
        }
        renderWindow(force: true)
        settings?.show()
    }

    func renderWindow(force: Bool = false) {
        let keys = previewOnly ? LayoutOrder.unique(savedOrder) : orderedKeys()
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
                         customIcon: customIconImage, options: options,
                         hotKey: hotKeyDisplay, hasHotKey: hotKey != nil, hasNotch: notchVisibleMinX != nil)
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
            options[.controlIcon] = ControlIcon.symbols.count
            UserDefaults.standard.set(options, forKey: "barOptions")
            applyControlIcon()
            renderWindow(force: true)
        } catch {
            NSLog("YoungBar custom icon save failed: \(error)")
        }
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
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
    func refreshLoginItemIfMoved() {
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
    func setSpacing(_ level: Int) {
        guard level != (options[.iconSpacing] ?? 0) else { return }
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
            options[.iconSpacing] = level
            UserDefaults.standard.set(options, forKey: "barOptions")
            feedback = L10n.t("菜单栏间距已修改，重启电脑后生效", "Spacing updated; takes effect after a reboot")
        } catch {
            feedback = L10n.t("菜单栏间距写入失败：\(error.localizedDescription)", "Spacing write failed: \(error.localizedDescription)")
        }
        renderWindow(force: true)
    }

    func runDefaults(_ arguments: [String]) throws {
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

    func setMode(key: String, mode: Int) {
        guard !busy else { return }
        modes[key] = mode
        UserDefaults.standard.set(modes, forKey: "itemModes")
        UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        closeShelf(); shownUntil.removeAll(); shelfState = nil
        // Busy before the task starts, so no refresh walks in between.
        busy = true
        Task {
            await engine.conceal()
            await engine.setModel(currentModel())
            busy = false
            await refresh()
        }
        renderWindow()
    }

    func moveItem(key: String, before: String) {
        guard !busy, let item = catalog[key],
              !MenuBarPolicy.isPinnedSystemItem(item.id), !MenuBarPolicy.isPinnedAppleHost(item.id.bundleID) else { return }
        let originalOrder = savedOrder
        savedOrder = LayoutOrder.moving(key, before: before, in: savedOrder)
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

    @objc func toggleLeftClickMenu() {
        options[.leftClickMenu] = options[.leftClickMenu] == 1 ? 0 : 1
        UserDefaults.standard.set(options, forKey: "barOptions")
        feedback = options[.leftClickMenu] == 1 ? L10n.t("左键点击改为显示菜单", "Left click now shows the menu") : L10n.t("左键点击改为展开收纳", "Left click now opens the strip")
        renderWindow(force: true)
    }

    /// Bulk visibility is transient: it builds a throw-away model instead of
    /// overwriting the per-item Hidden / Always Hidden choices.
    @objc func hideAllApps() {
        guard !busy else { return }
        closeShelf()
        busy = true
        Task {
            await bulkHideAll()
            busy = false
            feedback = L10n.t("已隐藏全部应用图标", "Hid all app icons")
            renderWindow(force: true)
        }
    }

    @objc func showAllApps() {
        guard !busy else { return }
        busy = true
        Task {
            await engine.reveal(Set(Section.allCases))
            busy = false
            feedback = L10n.t("已显示全部菜单栏项目", "Showed all menu-bar items")
            renderWindow(force: true)
        }
    }

    @objc func restoreAppModes() {
        guard !busy else { return }
        busy = true
        Task {
            await engine.conceal()
            await engine.setModel(currentModel())
            busy = false
            feedback = L10n.t("已恢复你的收纳配置", "Restored your layout")
            renderWindow(force: true)
        }
    }

    func bulkHideAll() async {
        var model = SectionModel(newItemsDestination: .visible)
        for item in catalog.values where item.id.bundleID != nil && !MenuBarPolicy.isPinnedSystemItem(item.id) {
            model.assignments[item.id] = .hidden
        }
        for section in Section.allCases {
            model.order[section] = savedOrder.map { ItemID(rawValue: $0) }.filter { model.section(of: $0) == section }
        }
        await engine.setModel(model)
    }

    @objc func toggleBundle(_ item: NSMenuItem) {
        guard let bundle = item.representedObject as? String else { return }
        setHidden(bundle: bundle)
    }

    func setHidden(bundle: String) {
        let key = "bundle:\(bundle)"
        setMode(key: key, mode: (modes[key] ?? 0) > 0 ? 0 : 1)
    }

    /// Show every item, ignoring the saved hide rules. Used by the crash
    /// guard and on clean termination so the menu bar is never left hidden.
    func revealEverything() async {
        var model = SectionModel(newItemsDestination: .visible)
        model.order = currentModel().order
        await engine.setModel(model)
        await engine.conceal()
    }

    func currentModel() -> SectionModel {
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

    /// Updates are GitHub releases; YoungBar itself never goes online.
    @objc func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/51younglowkey/youngbar/releases/latest")!)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

/// Carry the user's layout across bundle-id/name changes.
/// `dev.leorea.bar` → `dev.leorea.youngbar` → `studio.wuyiyang.youngbar`.
enum YoungBarDefaults {
    static func migrateIfNeeded() {
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
