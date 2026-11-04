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
    /// Show icons "Hide all" also took off the bar, until Show all, Restore
    /// my layout or a per-item change (`LayoutActions`).
    var bulkHiddenKeys: Set<String> = []
    /// Set once quitting starts: nothing re-applies the layout after that.
    var quitting = false
    /// A re-apply after an engine event is pending; they come 10 s apart at most.
    var reapplyScheduled = false
    var lastReapplyAt = Date.distantPast
    /// Recent event-driven re-applies, and the layout they stopped on after
    /// three in two minutes (the engine couldn't settle on it).
    var eventReapplies: [Date] = []
    var reapplyPausedFor: String?
    /// Background engine work (EngineSync) is running. Refresh walks wait for
    /// it; clicks and the shortcut don't (that is what `busy` is for).
    var syncing = false
    /// Mode choices made while `busy`, applied when it clears; the last one per row wins.
    var pendingModes: [String: Int] = [:]
    /// Running apps as last seen, to tell launches and quits apart (KVO on
    /// `runningApplications`), and bundles whose item never landed in an
    /// adoption window (not tried again this session).
    var runningAppsObservation: NSKeyValueObservation?
    var knownRunningPIDs: Set<pid_t> = []
    var adoptionMissed: Set<String> = []
    /// Items of Hidden apps started while an assertion holds: macOS parks them
    /// off screen, out of every engine snapshot, until an adoption window.
    var parkedKeys: Set<String> = []
    /// Keys no version reads any more (options 0.1.4 turned into fixed
    /// behaviour) are dropped on load, so they don't linger in exports.
    var options: [String: Int] = {
        let saved = UserDefaults.standard.dictionary(forKey: "barOptions") as? [String: Int] ?? [:]
        let known = saved.filter { Option(rawValue: $0.key) != nil }
        if known.count != saved.count { UserDefaults.standard.set(known, forKey: "barOptions") }
        return known
    }()
    var isHovered = false
    /// When hovering last opened the strip: a click landing just after
    /// (the user was reaching for •••) must not close it again.
    var hoverOpenedAt: Date?
    var mouseMonitor: Any?
    /// How long a system item clicked from the strip stays in the bar.
    let revealSeconds: TimeInterval = 20
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
    /// A double-tap shortcut is watched for, not registered: every modifier
    /// change and key press goes through this.
    var doubleTapDetector = DoubleTapDetector(target: nil)
    var doubleTapMonitors: [Any] = []
    var doubleTapNeedsTrust = false
    var shelfState: String?
    /// Keyboard selection in the strip, an index into `shelfButtons`.
    var shelfSelection: Int?
    /// The first nine icons show their number (unless turned off), however
    /// the strip was opened: the number keys work after a click too.
    var shelfNumbered = false
    /// The strip opened with nothing in it, so it offers the bar's own icons
    /// to tuck in until it closes.
    var shelfAdding = false
    /// One apply of tucked-in icons at a time (`applyTuckIns`); a click
    /// during it asks for another round.
    var tuckInApplying = false
    var tuckInPending = false
    var shelfButtons: [NSButton] = []
    var shelfIconColor: NSColor = .white
    /// Items set to Show that sit under the notch, so nobody sees them.
    var overflowKeys: Set<String> = []
    /// The control's width beside a free bar; it narrows when crowded.
    var controlWidth: CGFloat = 34
    var guideWindow: NSWindow?
    var guideModel: GuideModel?
    var guideTimer: Timer?
    var guideCloseObserver: NSObjectProtocol?
    /// Runs once when the guide is finished or closed (after an update:
    /// What's New and the tour).
    var afterGuide: (() -> Void)?
    var updateWindow: NSWindow?
    var whatsNewWindow: NSWindow?
    var updateIntro: UpdateIntroModel?
    var updateModel: UpdateModel?
    var updateTask: Task<Void, Never>?
    var pendingRelease: ReleaseInfo?
    /// A newer release found by the daily check: a line at the top of the
    /// control's right-click menu (and its tooltip) until it is installed.
    var availableUpdate: ReleaseInfo?
    var autoUpdateTask: Task<Void, Never>?
    var lastAutoUpdateCheck: Date?
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
            }
            L10n.current = Language(rawValue: options[.language] ?? 0) ?? .chinese
            NSApp.setActivationPolicy(.accessory)
            Task { await runSettingsPreview() }
            return
        }
        #endif
        if options[.language] == nil {
            // A fresh install starts in the Mac's language. An update from a
            // version that never saved one keeps Chinese, its old default.
            let chinese = !needsGuide || PreferredLanguage.isChinese(Locale.preferredLanguages)
            options[.language] = (chinese ? Language.chinese : Language.english).rawValue
            UserDefaults.standard.set(options, forKey: "barOptions")
        }
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
        // A blank placeholder: the floating control draws over its slot.
        // While a hide assertion holds, macOS doesn't draw this item; with
        // nothing to hide it does, and a title here showed a second •••
        // under the control.
        statusItem.button?.title = ""
        statusItem.button?.setAccessibilityLabel("YoungBar")
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
        let hotKeyRegistered = registerHotKey()
        refreshLoginItemIfMoved()
        startAutoUpdateChecks()
        // After an update: say so once in Settings, walk through the guide
        // again (its permission step just shows it is granted), then show
        // what changed. Decided once, here — the first walk below can change
        // what `needsGuide` reads.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let lastVersion = UserDefaults.standard.string(forKey: "lastLaunchedVersion")
        let firstRun = needsGuide
        // 0.1.0 and 0.1.1 saved no version: a saved layout means an update.
        let updated = lastVersion.map { $0 != version } ?? !firstRun
        if updated { feedback = L10n.t("已更新到 \(version)", "Updated to \(version)") }
        if !hotKeyRegistered {
            feedback = L10n.t("快捷键 \(hotKeyDisplay) 被其他应用占用，可以在设置里换一个",
                              "\(hotKeyDisplay) is taken by another app; choose another in Settings")
        }
        let showNotes: () -> Void = { [weak self] in self?.showWhatsNew() }
        if firstRun {
            if updated { afterGuide = showNotes }
            showGuide()
        } else {
            markGuided()
            if !AXIsProcessTrusted() { showWindow() }
        }
        Task {
            await installControlPanelWhenReady()
            await refresh()
            // The first walk ran before the hidden icons left the bar, so the
            // control was placed left of them. Look again once they are gone
            // instead of leaving it stranded until the idle tick (≈5 s).
            refreshSoon()
            Diagnostics.write(app: self, snapshot: nil)
            #if YOUNGBAR_TESTHOOKS
            await runLaunchHooks()
            #endif
            if updated && !firstRun {
                afterGuide = showNotes
                showGuide()
            }
            // Saved only now: quitting during the first walk shows the
            // update again next time instead of never.
            UserDefaults.standard.set(version, forKey: "lastLaunchedVersion")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if previewOnly { return .terminateNow }
        quitting = true
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

    var themeColor: ThemeColor {
        ThemeColor(rawValue: options[.themeColor] ?? 0) ?? .blue
    }

    var stripOpacity: CGFloat {
        CGFloat(stripOpacityPercent(options)) / 100
    }

    func applyAppearance() {
        let mode = AppearanceMode(rawValue: options[.appearanceMode] ?? 0) ?? .system
        NSApp.appearance = mode.appearance
        // YoungBar's windows take the chosen look; the ••• keeps the bar's.
        syncControlAppearance()
        NSApp.applicationIconImage = themeIcon(themeColor)
        applyUpdateNotice()
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
                guard let self, Date().timeIntervalSince(self.lastRefreshAt) >= self.refreshInterval - 0.05,
                      self.sessionIsOnScreen else { return }
                await self.refresh()
            }
        }
        tick.tolerance = 0.4
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        let center = NSWorkspace.shared.notificationCenter
        // Launches and quits reach the engine through the running-apps list
        // (EngineSync), which menu-bar-only apps are in too; these notices
        // only bring the next walk forward. A launching app adds its item a
        // moment after the launch notice.
        watchRunningApplications()
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
        // Dark Mode switched: the bar changes its look at once, so does the •••
        // (and again on the next walks, once the status item has caught up).
        workspaceObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.syncControlAppearance()
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
        guard !busy, !refreshing, !syncing, AXIsProcessTrusted(), AssessmentMode.isAvailable else { return }
        if doubleTapNeedsTrust { registerHotKey() }
        refreshing = true
        lastRefreshAt = Date()
        defer { refreshing = false }
        if !started {
            await engine.start()
            await engine.setSteadyExtras(false)
            // The engine reads the running apps once unless told; launches
            // and quits keep it current from here (EngineSync).
            await engine.setRunningBundles(runningBundleIDs())
            watchEngineEvents()
            if previousSessionCrashed || rescueRequested {
                await revealEverything()
                let wasCrashed = previousSessionCrashed
                previousSessionCrashed = false
                // The marker stays set for this session (it hides icons
                // again), so a second crash is noticed too; a rescue run
                // clears it as it quits.
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
        positionControlBesideMenuIcons(in: snapshot)
        // The wallpaper or Dark Mode may have changed the bar's look.
        syncControlAppearance()
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
        // Landed since (any adoption window lands them all): the engine has it.
        parkedKeys.subtract(present)
        presentKeys = present.union(parkedKeys)

        var orderChanged = false
        // Nothing is "new" on the very first run: every icon is.
        let knewItems = !savedOrder.isEmpty
        var newlyHidden: [String] = []
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
                if knewItems, shouldAutoHide(item) { newlyHidden.append(key) }
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
        if !newlyHidden.isEmpty { autoHide(newlyHidden) }
    }

    /// An app's icon the user has never had in the bar. Apple's own items
    /// (system extras, the clock, Control Center) never count.
    func shouldAutoHide(_ item: ObservedItem) -> Bool {
        // A helper with no bundle of its own (filed under its app) can never
        // be hidden by the assertion: it would sit in the bar and the strip.
        guard options[.autoHideNew] == 1, modes[item.id.sectionKey.rawValue] == nil, !item.hostIsBundleless,
              let bundle = item.id.bundleID, !bundle.hasPrefix("com.apple."),
              MenuBarPolicy.systemItem(for: item.id) == nil else { return false }
        return true
    }

    func autoHide(_ keys: [String]) {
        // Saved first: these keys are now known, so they are never "new"
        // again even if the bar is busy right now.
        for key in keys { modes[key] = 1 }
        UserDefaults.standard.set(modes, forKey: "itemModes")
        UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        let names = keys.map { name(for: $0) }.joined(separator: L10n.t("、", ", "))
        feedback = L10n.t("新图标已放进收纳条：\(names)", "New icons moved to the strip: \(names)")
        shelfState = nil
        Task {
            for _ in 0..<100 where busy { try? await Task.sleep(for: .milliseconds(100)) }
            // Still busy after 10 s: apply anyway, but leave the flag to its owner.
            let owned = !busy
            if owned { busy = true }
            await engine.setModel(currentModel())
            if owned { busy = false }
            renderWindow()
        }
    }

    /// The table is the user's ordering model, but it must not drift from the
    /// real bar. Whenever the visible items disagree with their saved order,
    /// rewrite just those slots to the actual left-to-right order and persist.
    func reconcileVisibleOrder(_ snapshot: EngineSnapshot) {
        guard !busy, !syncing else { return }
        // Only icons set to Show and in sight: a Hidden one out for a moment
        // (opened from the strip, Show all) keeps its place in the strip's
        // order, and a pile in macOS's « has no order to learn from.
        let outOfSight = outOfSightKeys(snapshot)
        let actual = LayoutOrder.unique(snapshot.items
            .filter { item in
                let key = item.id.sectionKey.rawValue
                return item.frame != nil && (modes[key] ?? 0) == 0 && !outOfSight.contains(key)
            }
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
}

/// Carry the user's layout across bundle-id/name changes.
/// `dev.leorea.bar` → `dev.leorea.youngbar` → `studio.wuyiyang.youngbar`.
enum YoungBarDefaults {
    static func migrateIfNeeded() {
        // Newest first: dev.leorea.youngbar copied dev.leorea.bar's keys and
        // then kept the newer edits, which an older-first pass would skip.
        migrate(from: "dev.leorea.youngbar", marker: "migratedFromLeoreaYoungBar")
        migrate(from: "dev.leorea.bar", marker: "migratedFromLeoreaBar")
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
