// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import YoungBarCore

/// An icon in the strip. A click opens it; dragged sideways, a hidden icon
/// changes places with its neighbours; a right-click changes its state.
@MainActor
final class ShelfItemButton: NSButton {
    var dragMoved: ((ShelfItemButton, CGFloat) -> Void)?
    var dragEnded: ((ShelfItemButton) -> Void)?
    var rightClick: ((ShelfItemButton, NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        if let rightClick { rightClick(self, event) } else { super.rightMouseDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard dragMoved != nil, let window else { super.mouseDown(with: event); return }
        let start = event.locationInWindow
        var dragging = false
        highlight(true)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let dx = next.locationInWindow.x - start.x
            if next.type == .leftMouseUp {
                highlight(false)
                if dragging { dragEnded?(self) } else { sendAction(action, to: target) }
                return
            }
            if !dragging {
                // A small wobble is still a click.
                guard abs(dx) > 4 || abs(next.locationInWindow.y - start.y) > 4 else { continue }
                dragging = true
                highlight(false)
            }
            dragMoved?(self, dx)
        }
    }
}

/// An image that never takes a click: the ＋ on an icon an empty strip
/// offers, so the click reaches the icon underneath.
final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Reordering in the strip changes the saved order only: hidden icons are
/// not in the bar, so nothing is revealed or dragged there, and the strip
/// keeps that order. (It is not pushed to the bar: an icon set back to Show
/// returns where macOS keeps it, and the saved order follows the bar again.
/// One shown only for a moment — opened from the strip, Show all — keeps
/// its strip place; see `reconcileVisibleOrder`.)
extension BarApp {
    static let shelfSlot: CGFloat = 40
    static let shelfInset: CGFloat = 8

    func shelfSlot(atX x: CGFloat) -> Int {
        let slot = Int(((x - Self.shelfInset) / Self.shelfSlot).rounded())
        return min(max(slot, 0), shelfButtons.count - 1)
    }

    func shelfDragMoved(_ button: ShelfItemButton, by dx: CGFloat) {
        guard !busy, let from = shelfButtons.firstIndex(of: button) else { return }
        let last = Self.shelfInset + CGFloat(shelfButtons.count - 1) * Self.shelfSlot
        let x = min(max(Self.shelfInset + CGFloat(from) * Self.shelfSlot + dx, Self.shelfInset), last)
        button.superview?.addSubview(button, positioned: .above, relativeTo: nil)
        button.setFrameOrigin(NSPoint(x: x, y: button.frame.minY))
        let to = shelfSlot(atX: x)
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, other) in shelfButtons.enumerated() where other !== button {
            var slot = index
            if from < to, index > from, index <= to { slot -= 1 }
            if from > to, index >= to, index < from { slot += 1 }
            let origin = NSPoint(x: Self.shelfInset + CGFloat(slot) * Self.shelfSlot, y: other.frame.minY)
            guard other.frame.origin != origin else { continue }
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    other.animator().setFrameOrigin(origin)
                }
            } else {
                other.setFrameOrigin(origin)
            }
        }
    }

    func shelfDragEnded(_ button: ShelfItemButton) {
        guard let from = shelfButtons.firstIndex(of: button), let key = button.identifier?.rawValue else { return }
        let to = shelfSlot(atX: button.frame.minX)
        defer {
            shelfState = nil
            populateShelf()
        }
        guard !busy, to != from else { return }
        var keys = shelfButtons.compactMap { $0.identifier?.rawValue }
        keys.remove(at: from)
        keys.insert(key, at: to)
        // Before the icon that now follows it; the last one goes to the end.
        let following = to + 1 < keys.count ? keys[to + 1] : ""
        savedOrder = LayoutOrder.moving(key, before: following, in: savedOrder)
        UserDefaults.standard.set(savedOrder, forKey: "itemOrder")
        if shelfSelection != nil { shelfSelection = to }
        Task { await engine.setModel(currentModel()) }
        renderWindow()
    }
}

/// Right-click on a strip icon: put it back in the bar or move it between
/// Hidden and Always Hidden, without opening Settings.
extension BarApp {
    func shelfItemMenu(for key: String) -> NSMenu {
        let menu = NSMenu()
        let mode = modes[key] ?? 0
        func add(_ title: String, _ newMode: Int) {
            let item = NSMenuItem(title: title, action: #selector(shelfItemModeChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, String(newMode)]
            menu.addItem(item)
        }
        let title = NSMenuItem(title: name(for: key), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if fixedKeys.contains(key) {
            // Nothing to choose: macOS keeps it off the bar either way.
            let note = NSMenuItem(title: L10n.t("有图标隐藏时，macOS 不显示它：固定在收纳条里",
                                                "macOS keeps it off the bar while icons are hidden: it stays in the strip"),
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        } else {
            if mode != 0 { add(L10n.t("放回菜单栏", "Show in menu bar"), 0) }
            if mode != 1 { add(L10n.t("隐藏（收进收纳条）", "Hide (in the strip)"), 1) }
            if mode != 2 { add(L10n.t("始终隐藏", "Always hide"), 2) }
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.t("在设置中调整…", "Adjust in Settings…"), action: #selector(openLayoutSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    func showShelfItemMenu(_ button: ShelfItemButton, event: NSEvent) {
        guard !busy, let key = button.identifier?.rawValue else { return }
        // The menu is a click outside the strip as far as the strip knows.
        ignoreOutsideUntil = Date().addingTimeInterval(2)
        NSMenu.popUpContextMenu(shelfItemMenu(for: key), with: event, for: button)
    }

    @objc func shelfItemModeChosen(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2, let mode = Int(pair[1]) else { return }
        setMode(key: pair[0], mode: mode)
        feedback = L10n.t("已更新「\(name(for: pair[0]))」", "Updated \(name(for: pair[0]))")
    }

    @objc func openLayoutSettings() {
        closeShelf()
        showWindow()
        settings?.select(.layout)
    }
}
