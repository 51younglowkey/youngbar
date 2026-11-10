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

    /// `byHover`: opened by resting the pointer on •••. Such a strip takes no
    /// keyboard focus — the user may be typing elsewhere, and a digit would
    /// open an item.
    func toggleShelfFrom(keyboard fromKeyboard: Bool, byHover: Bool = false) {
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
            includeAlwaysHidden = !fromKeyboard && !byHover && event?.type == .leftMouseUp && event?.modifierFlags.contains(.option) == true
            // Always the strip: it shows app icons, so nothing on the bar is
            // revealed to open it. (Showing the hidden icons in the bar
            // itself, the old "Show in bar" mode, flashed and doubled the
            // bar while it reflowed; it is gone.)
            showShelf(selectFirst: fromKeyboard, takeKeyboard: !byHover)
            if fromKeyboard, whatsNewWindow?.isVisible == true { updateIntro?.triedShortcut = true }
            Task { await refresh() }
        }
    }

    func showShelf(selectFirst: Bool = false, takeKeyboard: Bool = true) {
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
        let wasOpen = expanded && shelfPanel?.isVisible == true
        // A fresh open starts scrolled to the left (icons 1–9 in view); the
        // old content would carry its scroll position into the rebuild.
        if !wasOpen {
            shelfPanel?.contentView = nil
            flight.note("strip opened")
        }
        expanded = true
        shelfAnchored = false
        shelfSelection = selectFirst ? 0 : nil
        shelfNumbered = options[.shelfNumbers] != 0
        // Nothing in it: show the bar's icons, ready to be tucked in.
        shelfAdding = shelfKeys().isEmpty
        shelfState = nil
        // Above the menu bar while browsing; lowered while an item's own menu
        // or panel is open so that opens on top of the strip.
        shelfPanel?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        populateShelf()
        guard let shelfPanel else { return }
        positionShelf()
        // A short fade in, stepped by hand: `animator()` on these panels
        // has not always applied (see positionControlBesideMenuIcons), and a
        // strip stuck at alpha 0 would be far worse than no fade.
        let fade = !wasOpen && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        shelfPanel.alphaValue = fade ? 0.2 : 1
        shelfPanel.orderFrontRegardless()
        if takeKeyboard { shelfPanel.makeKeyAndOrderFront(nil) }
        if fade {
            Task {
                for step in 1...4 {
                    try? await Task.sleep(for: .milliseconds(25))
                    shelfPanel.alphaValue = 0.2 + 0.8 * CGFloat(step) / 4
                }
                shelfPanel.alphaValue = 1
            }
        }
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
        if expanded { flight.note("strip closed") }
        expanded = false
        hoverOpenedAt = nil
        shelfAnchored = false
        shelfSelection = nil
        shelfNumbered = false
        shelfAdding = false
        shelfPanel?.orderOut(nil)
    }

    func shelfKeys() -> [String] {
        // Out of sight on top of the saved modes: no room in the bar, or "Hide all".
        ShelfContents.keys(order: orderedKeys(), modes: modes, covered: overflowKeys.union(bulkHiddenKeys),
                           includeAlwaysHidden: includeAlwaysHidden)
    }

    /// What a strip that opened empty offers to tuck in: icons on the bar set
    /// to Show, in bar order — not YoungBar itself, not the clock and Control
    /// Center that macOS pins, not icons the bar has no room for.
    func tuckInCandidates() -> [String] {
        let order = orderedKeys()
        let excluded = Set(order.filter { key in
            guard let item = catalog[key] else { return true }
            // A helper with no bundle of its own can't be hidden.
            return item.id.bundleID == Bundle.main.bundleIdentifier
                || item.hostIsBundleless
                || !MenuBarPolicy.isSectionManageable(item.id)
                || MenuBarPolicy.isPinnedSystemItem(item.id)
                || MenuBarPolicy.isPinnedAppleHost(item.id.bundleID)
        })
        return ShelfContents.tuckInCandidates(order: order, modes: modes, covered: overflowKeys.union(bulkHiddenKeys),
                                              excluded: excluded)
    }

    func populateShelf() {
        guard let shelfPanel else { return }
        let keys = shelfKeys()
        // Opened empty: the bar's own icons are offered, dimmed, until the
        // strip closes, so several can be tucked in one after another.
        let candidates = shelfAdding ? tuckInCandidates() : []
        let adding = !candidates.isEmpty
        let state = (shelfNumbered ? "#" : "") + keys.joined(separator: "|")
            + (adding ? "+" + candidates.joined(separator: "|") : "")
        guard state != shelfState || shelfPanel.contentView == nil else { return }
        shelfState = state
        let previousFrame = shelfPanel.frame
        let previousScroll = (shelfPanel.contentView?.subviews.first { $0 is NSScrollView } as? NSScrollView)?
            .contentView.bounds.origin.x ?? 0
        // Each item shows its app's own icon (or the system symbol): sharp at
        // any size, unlike a menu-bar crop.
        let slot = Self.shelfSlot
        let inset = Self.shelfInset
        // A little air between what is in the strip and what could join it.
        let gap: CGFloat = adding && !keys.isEmpty ? 10 : 0
        let itemContentWidth = inset * 2 + slot * CGFloat(keys.count + candidates.count) + gap
        let screenWidth = (controlPanel?.screen ?? NSScreen.screens.first)?.frame.width ?? 800
        let gearWidth: CGFloat = 38
        let rowHeight: CGFloat = 40
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // The clear theme is the system blur only, so its icons follow light
        // and dark; every colour theme is dark enough for white icons.
        let systemStrip = themeColor == .clear
        let iconColor: NSColor = systemStrip && !isDark ? .black : .white
        shelfIconColor = iconColor

        // Text above the icons while offering them; the only content when
        // there is nothing in the strip and nothing to offer.
        var header: NSTextField?
        var emptyLink: NSButton?
        if adding {
            let text = keys.isEmpty
                ? L10n.t("还没有收纳的图标，点一下就收进来", "Nothing here yet. Click an icon to tuck it in")
                : L10n.t("已收进 \(keys.count) 个，可以接着点；按 Esc 完成",
                         "\(keys.count) tucked in. Keep clicking, or press Esc when done")
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = iconColor.withAlphaComponent(0.85)
            label.lineBreakMode = .byTruncatingTail
            header = label
        } else if keys.isEmpty {
            // Nothing to show and nothing to offer (every icon is hidden
            // already, or the bar hasn't been read yet): Settings decides.
            let link = NSButton(title: "", target: self, action: #selector(openLayoutSettings))
            link.isBordered = false
            link.attributedTitle = NSAttributedString(
                string: L10n.t("还没有收纳的图标 · 去设置里选择", "Nothing tucked away yet · choose in Settings"),
                attributes: [.foregroundColor: iconColor, .font: NSFont.systemFont(ofSize: 12)])
            link.toolTip = L10n.t("在设置的「菜单栏」页把图标设为「隐藏」", "Set icons to Hide on the Menu Bar page in Settings")
            link.setAccessibilityLabel(L10n.t("去设置里选择要收纳的图标", "Choose icons to tuck away in Settings"))
            emptyLink = link
        }
        let headerHeight: CGFloat = header == nil ? 0 : 22
        let height = rowHeight + headerHeight
        let textWidth = (header?.fittingSize.width ?? emptyLink?.fittingSize.width ?? 0) + 24
        let contentWidth = keys.isEmpty && !adding ? textWidth : max(itemContentWidth, textWidth)
        let width = min(max(keys.isEmpty && !adding ? 150 : 100, contentWidth + gearWidth), screenWidth - 24)
        shelfPanel.setContentSize(NSSize(width: width, height: height))

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
        tint.layer?.backgroundColor = (systemStrip ? NSColor.clear : themeColor.strip.withAlphaComponent(stripOpacity)).cgColor
        effect.addSubview(tint)
        let background: NSView = effect
        let itemArea = width - gearWidth
        shelfButtons = []
        if let emptyLink {
            emptyLink.frame = NSRect(x: 8, y: 10, width: itemArea - 16, height: 20)
            background.addSubview(emptyLink)
        } else {
            if let header {
                header.frame = NSRect(x: 12, y: rowHeight + 2, width: itemArea - 20, height: 16)
                background.addSubview(header)
            }
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: itemArea, height: rowHeight))
            scroll.drawsBackground = false; scroll.borderType = .noBorder
            scroll.hasHorizontalScroller = itemContentWidth > itemArea
            scroll.scrollerStyle = .overlay
            let document = NSView(frame: NSRect(x: 0, y: 0, width: max(itemContentWidth, itemArea), height: rowHeight))
            var x = inset
            for (index, key) in keys.enumerated() {
                let button = ShelfItemButton(frame: NSRect(x: x, y: 2, width: slot, height: 36))
                button.title = ""; button.isBordered = false
                button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
                button.identifier = .init(key); button.target = self; button.action = #selector(pressShelfItem(_:))
                // A copy: the cached icon is shared with the settings rows.
                let image = fallbackImage(for: key)?.copy() as? NSImage
                image?.size = NSSize(width: 22, height: 22)
                button.image = image
                let outOfSight = overflowKeys.contains(key) && (modes[key] ?? 0) == 0
                var tip = name(for: key)
                if outOfSight {
                    tip = shutOutKeys.contains(key)
                        ? L10n.t("\(tip)（有图标隐藏时，macOS 不显示它）", "\(tip) (macOS keeps it off the bar while icons are hidden)")
                        : L10n.t("\(tip)（菜单栏放不下）", "\(tip) (no room in the menu bar)")
                }
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
                    number.frame = NSRect(x: slot - 13, y: button.isFlipped ? 24 : 0, width: 10, height: 12)
                    number.setAccessibilityElement(false)
                    button.addSubview(number)
                }
                document.addSubview(button)
                x += slot
                shelfButtons.append(button)
            }
            x += gap
            for key in candidates {
                let button = ShelfItemButton(frame: NSRect(x: x, y: 2, width: slot, height: 36))
                button.title = ""; button.isBordered = false
                button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
                button.identifier = .init(key); button.target = self; button.action = #selector(tuckInFromShelf(_:))
                let image = fallbackImage(for: key)?.copy() as? NSImage
                image?.size = NSSize(width: 22, height: 22)
                button.image = image
                button.contentTintColor = iconColor
                // Dimmed: not in the strip yet. The ＋ beside it stays bright.
                button.alphaValue = 0.45
                let tip = L10n.t("收进收纳条：\(name(for: key))", "Tuck into the strip: \(name(for: key))")
                button.toolTip = tip
                button.setAccessibilityLabel(tip)
                document.addSubview(button)
                let badge = PassThroughImageView(frame: NSRect(x: x + slot - 15, y: 4, width: 12, height: 12))
                badge.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
                badge.contentTintColor = iconColor
                badge.setAccessibilityElement(false)
                document.addSubview(badge)
                x += slot
            }
            scroll.documentView = document; background.addSubview(scroll)
            // A rebuild (an icon dropped, one more tucked in) keeps the view where it was.
            let offset = min(previousScroll, max(0, document.frame.width - itemArea))
            if offset > 0 {
                scroll.contentView.scroll(to: NSPoint(x: offset, y: 0))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        let divider = NSView(frame: NSRect(x: itemArea, y: 8, width: 1, height: height - 16))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = iconColor.withAlphaComponent(0.18).cgColor
        background.addSubview(divider)

        let gear = BarControlButton(frame: NSRect(x: itemArea + 5, y: (height - 28) / 2, width: 28, height: 28))
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
        if shelfAnchored && previousFrame.width > 0 {
            // An item's own menu is open beside the strip: grow or shrink
            // about the same centre and top edge instead of jumping.
            shelfPanel.setFrameOrigin(NSPoint(x: previousFrame.midX - width / 2, y: previousFrame.maxY - height))
        } else {
            positionShelf()
        }
    }

    /// An icon offered by an empty strip, clicked: it goes into the strip
    /// (Hidden) at once and leaves the bar a moment later. The strip stays
    /// open for the next one.
    @objc func tuckInFromShelf(_ button: NSButton) {
        guard let key = button.identifier?.rawValue, catalog[key] != nil, (modes[key] ?? 0) == 0 else { return }
        bulkHiddenKeys = []
        modes[key] = 1
        UserDefaults.standard.set(modes, forKey: "itemModes")
        UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        feedback = L10n.t("已收进收纳条：\(name(for: key))", "Tucked into the strip: \(name(for: key))")
        // The bar reflows as the icon leaves it; that is not a click outside.
        ignoreOutsideUntil = Date().addingTimeInterval(1.5)
        shelfState = nil
        populateShelf()
        applyTuckIns()
    }

    /// Clicks can come faster than the engine applies them: one apply runs
    /// at a time and takes whatever was tucked in meanwhile with it.
    func applyTuckIns() {
        guard !tuckInApplying else { tuckInPending = true; return }
        tuckInApplying = true
        Task {
            repeat {
                tuckInPending = false
                for _ in 0..<100 where busy { try? await Task.sleep(for: .milliseconds(100)) }
                // Still busy after 10 s: apply anyway, but leave the flag to its owner.
                let owned = !busy
                if owned { busy = true }
                await engine.setModel(currentModel())
                if owned { busy = false }
            } while tuckInPending
            tuckInApplying = false
            await refresh()
            renderWindow()
        }
    }

    /// The on-screen windows of `pid` right now.
    func windowNumbers(of pid: pid_t) -> Set<Int> {
        guard pid > 0 else { return [] }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid ? info[kCGWindowNumber as String] as? Int : nil
        })
    }

    /// Orders the strip just below the frontmost window of `pid` that overlaps
    /// it, if there is one — among the windows the press opened, not those
    /// on screen before it: under the app's own main window the strip would
    /// vanish while still open.
    func tuckShelf(below pid: pid_t, excluding existing: Set<Int> = []) {
        guard pid > 0, let shelfPanel, expanded else { return }
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let shelf = shelfPanel.frame
        let shelfCG = CGRect(x: shelf.minX, y: screenTop - shelf.maxY, width: shelf.width, height: shelf.height)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let panel = windows.first(where: { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let number = info[kCGWindowNumber as String] as? Int, !existing.contains(number),
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
        shelfPanel?.level = .floating
        let owner = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == item.id.bundleID }?.processIdentifier ?? 0
        let ownerWindows = windowNumbers(of: owner)
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
                    tuckShelf(below: owner, excluding: ownerWindows)
                }
            }
            return
        }
        // Our own click below is not a click outside the strip. (A press in
        // place clicks nothing, so a quick pick from its menu still closes it.)
        ignoreOutsideUntil = Date().addingTimeInterval(2)
        // System items (Wi-Fi, battery…) have no press action: reveal and
        // click, as iBar did, with the pointer hidden so it doesn't jump.
        busy = true
        Task {
            defer { busy = false }
            await engine.reveal(items: [item.id])
            shownUntil[item.id] = Date().addingTimeInterval(revealSeconds)
            var snapshot = await settledSnapshot(for: [item.id])
            // An app started while YoungBar hid it: macOS parked its item
            // off screen, and a reveal doesn't bring it back. Let it land now,
            // once (hidden icons show for a moment) — not at every launch.
            if snapshot.items.first(where: { $0.id.sectionKey == item.id.sectionKey })?.frame == nil,
               MenuBarPolicy.systemItem(for: item.id) == nil, let bundle = item.id.bundleID,
               await engine.holdsAssertion {
                _ = await engine.openAdoptionWindow(for: bundle)
                snapshot = await settledSnapshot(for: [item.id])
            }
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
            // Out but still out of sight (in macOS's « or under the notch): a
            // click there would open « or hit nothing. Say so instead.
            guard !outOfSightKeys(snapshot).contains(key) else {
                shownUntil[item.id] = nil
                await engine.conceal(items: [item.id])
                NSSound.beep()
                feedback = L10n.t("菜单栏放不下「\(name(for: key))」：隐藏几个别的图标再试",
                                  "No room in the menu bar for \(name(for: key)): hide a few other icons and try again")
                renderWindow(force: true)
                return
            }
            let pid = snapshot.items.first { $0.id.sectionKey == item.id.sectionKey }?.pid ?? 0
            let pidWindows = windowNumbers(of: pid)
            NSCursor.hide()
            await ItemMover.shieldedClick(at: CGPoint(x: frame.midX, y: frame.midY))
            NSCursor.unhide()
            // Menus open above everything, but many items open an ordinary
            // window-level panel. Tuck the strip directly under it so the
            // panel is on top while the strip still covers other windows.
            for delay in [350, 600] {
                try? await Task.sleep(for: .milliseconds(delay))
                tuckShelf(below: pid, excluding: pidWindows)
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
        let bar = extras as! AXUIElement
        // Without its own timeout this read waited the system default
        // (seconds) on a busy app, freezing the strip.
        AXUIElementSetMessagingTimeout(bar, timeout)
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children)
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
        if !near {
            NSLog("YoungBar: \(key) slot at x=\(point.x) is away from the control; revealing instead")
            flight.note("\(name(for: key)): slot at x\(Int(point.x)) is away from the ••• at x\(Int(control.minX)); revealing instead")
        }
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
