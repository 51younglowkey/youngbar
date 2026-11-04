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
extension BarApp {
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
}
