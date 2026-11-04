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

/// Changing what the menu bar shows: per-item modes, reordering, bulk
/// hide/show, and the model handed to the engine.
///
/// The engine keeps two kinds of "out": whole sections (`reveal(_:)`, taken
/// back by `conceal()`) and single items (`reveal(items:)`, taken back only
/// by `conceal(items:)` / `conceal(releasing:)`). An item revealed on its own
/// and never released stays on the bar whatever its mode says, so every
/// item reveal here is paired with a release.
extension BarApp {
    func setMode(key: String, mode: Int) {
        guard !busy else {
            // Another change is still being applied. The row already shows
            // this one, so apply it right after instead of dropping it.
            Task {
                for _ in 0..<50 where busy { try? await Task.sleep(for: .milliseconds(100)) }
                if busy { renderWindow(force: true) } else { setMode(key: key, mode: mode) }
            }
            return
        }
        guard (modes[key] ?? 0) != mode else { renderWindow(); return }
        modes[key] = mode
        UserDefaults.standard.set(modes, forKey: "itemModes")
        UserDefaults.standard.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        bulkHiddenKeys = []
        // Icons opened from the strip are out on their own 20 s: take them
        // back with this change, or nothing ever would.
        let timed = Set(shownUntil.keys)
        closeShelf(); shownUntil.removeAll(); shelfState = nil
        // Busy before the task starts, so no refresh walks in between.
        busy = true
        Task {
            await engine.conceal(releasing: timed)
            await engine.setModel(currentModel())
            busy = false
            await refresh()
        }
        renderWindow()
    }

    func moveItem(key: String, before: String) {
        guard !busy else {
            // Put the row back where it is: a ⌘-drag can't wait in a queue.
            feedback = L10n.t("上一个更改还在进行，请稍后再移动", "Still applying the last change; move it again in a moment")
            renderWindow(force: true)
            return
        }
        guard let item = catalog[key],
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
            // Everything this move brings out is released after it, Show
            // items too (a revealed item could never be hidden again) —
            // except one already out on a strip timer, which ends on its own.
            let temporary = ids.filter { shownUntil[$0] == nil }
            await engine.reveal(items: ids)
            let snapshot = await settledSnapshot(for: ids)
            if let from = snapshot.items.first(where: { $0.id.sectionKey == item.id.sectionKey })?.frame,
               let to = snapshot.items.first(where: { $0.id.sectionKey == target.id.sectionKey })?.frame {
                let destination = CGPoint(x: before.isEmpty ? to.maxX + 3 : to.minX - 3, y: to.midY)
                controlPanel?.ignoresMouseEvents = true
                await ItemMover.cmdDrag(from: CGPoint(x: from.midX, y: from.midY), to: destination)
                controlPanel?.ignoresMouseEvents = false
                let result = await settledSnapshot(for: ids)
                if moveLanded(item.id, beside: target.id, after: before.isEmpty, in: result) {
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

    /// The dragged item sits right next to the target, on the side the move
    /// asked for, among the icons drawn on the bar (YoungBar's own blank
    /// item aside). "Left of the target" alone is also true of a refused
    /// move to the right.
    func moveLanded(_ item: ItemID, beside target: ItemID, after: Bool, in snapshot: EngineSnapshot) -> Bool {
        let drawn = snapshot.items
            .filter { $0.frame != nil && $0.id.bundleID != Bundle.main.bundleIdentifier }
            .sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
            .map { $0.id.sectionKey.rawValue }
        return LayoutOrder.isAdjacent(item.sectionKey.rawValue, to: target.sectionKey.rawValue, after: after, in: drawn)
    }

    /// "Hide all (app icons)": every app icon set to Show joins the Hidden
    /// ones until Show all, Restore my layout or the next per-item change.
    /// The saved modes are untouched, the icons are listed in the strip, and
    /// system icons (Wi-Fi, battery…) stay.
    @objc func hideAllApps() {
        guard !busy else { return }
        closeShelf()
        busy = true
        Task {
            await bulkHideAll()
            busy = false
            feedback = L10n.t("已隐藏全部应用图标，都在收纳条里", "Hid all app icons; they're in the strip")
            renderWindow(force: true)
            await refresh()
        }
    }

    @objc func showAllApps() {
        guard !busy else { return }
        bulkHiddenKeys = []
        busy = true
        Task {
            await engine.reveal(Set(Section.allCases))
            // Under the revealed sections this changes nothing on the bar;
            // it drops a "Hide all" so Restore comes back to the saved modes.
            await engine.setModel(currentModel())
            busy = false
            feedback = L10n.t("已显示全部菜单栏项目", "Showed all menu-bar items")
            renderWindow(force: true)
        }
    }

    @objc func restoreAppModes() {
        guard !busy else { return }
        bulkHiddenKeys = []
        busy = true
        Task {
            await engine.conceal()
            await engine.setModel(currentModel())
            busy = false
            feedback = L10n.t("已恢复你的收纳配置", "Restored your layout")
            renderWindow(force: true)
            await refresh()
        }
    }

    func bulkHideAll() async {
        let timed = Set(shownUntil.keys)
        shownUntil.removeAll()
        bulkHiddenKeys = Set(catalog.values.compactMap { item -> String? in
            let key = item.id.sectionKey.rawValue
            guard (modes[key] ?? 0) == 0, let bundle = item.id.bundleID, bundle != Bundle.main.bundleIdentifier,
                  MenuBarPolicy.isSectionManageable(item.id),
                  MenuBarPolicy.systemItem(for: item.id) == nil,
                  !MenuBarPolicy.isPinnedSystemItem(item.id),
                  !MenuBarPolicy.isPinnedAppleHost(bundle) else { return nil }
            return key
        })
        await engine.setModel(currentModel())
        // After "Show all" every section is still out, and the model alone
        // would hide nothing: take the sections back too.
        await engine.conceal(releasing: timed)
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
        // "Hide all", on top of the saved modes until it is undone.
        for key in bulkHiddenKeys where (modes[key] ?? 0) == 0 {
            model.assignments[ItemID(rawValue: key)] = .hidden
        }
        for section in Section.allCases {
            model.order[section] = savedOrder.map { ItemID(rawValue: $0) }.filter { model.section(of: $0) == section }
        }
        return model
    }

    /// Hands the current layout to the engine again: after an app launched or
    /// quit, or when the engine reports a dropped assertion. Waits for a
    /// change in progress and gives up if it doesn't end.
    func reapplyModel() async {
        for _ in 0..<50 where busy { try? await Task.sleep(for: .milliseconds(100)) }
        guard started, !busy, !quitting else { return }
        busy = true
        await engine.setModel(currentModel())
        busy = false
    }
}
