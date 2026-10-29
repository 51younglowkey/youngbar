// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import UniformTypeIdentifiers
import YoungBarCore

/// Export and import of the whole layout as one JSON file, for a new Mac,
/// a reinstall, or trying something out with a way back.
extension BarApp {
    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "YoungBar-\(day).json"
        panel.message = L10n.t("导出每个图标的显示方式、顺序和所有选项", "Export each icon's state, the order and all options")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeConfiguration(to: url)
            feedback = L10n.t("配置已导出到 \(url.lastPathComponent)", "Exported to \(url.lastPathComponent)")
        } catch {
            feedback = L10n.t("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
        }
        renderWindow(force: true)
    }

    func writeConfiguration(to url: URL) throws {
        var exported = options
        exported[.onboarded] = nil
        try ConfigFile(itemModes: modes, itemOrder: savedOrder, options: exported).encoded()
            .write(to: url, options: .atomic)
    }

    func importConfiguration() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("选择一个 YoungBar 配置文件", "Choose a YoungBar layout file")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file: ConfigFile
        do {
            let data = try Data(contentsOf: url)
            file = try ConfigFile.decode(data, knownOptions: Set(Option.allCases.map(\.rawValue)))
        } catch ConfigFile.ImportError.newerFormat {
            feedback = L10n.t("这个文件来自更新版本的 YoungBar，请先升级", "This file comes from a newer YoungBar; update first")
            renderWindow(force: true)
            return
        } catch {
            feedback = L10n.t("不是有效的 YoungBar 配置文件", "Not a valid YoungBar layout file")
            renderWindow(force: true)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.t("导入这份配置？", "Import this layout?")
        alert.informativeText = L10n.t(
            "会替换当前每个图标的显示方式和所有选项（\(file.itemModes.count) 个图标）。菜单栏里可见图标的左右顺序以实际位置为准。",
            "This replaces every icon's state and all options (\(file.itemModes.count) icons). Icons on the bar keep their actual left-to-right order.")
        alert.addButton(withTitle: L10n.t("导入", "Import"))
        alert.addButton(withTitle: L10n.t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        applyConfiguration(file) {
            self.feedback = L10n.t("已导入 \(url.lastPathComponent)", "Imported \(url.lastPathComponent)")
        }
    }

    /// Replaces modes and options with `file`'s and re-applies the model.
    func applyConfiguration(_ file: ConfigFile, completion: @escaping @MainActor () -> Void = {}) {
        modes = file.itemModes
        savedOrder = LayoutOrder.unique(file.itemOrder + savedOrder)
        let onboarded = options[.onboarded]
        options = file.options
        options[.onboarded] = onboarded
        let defaults = UserDefaults.standard
        defaults.set(modes, forKey: "itemModes")
        defaults.set(hiddenBundles.sorted(), forKey: "hiddenBundles")
        defaults.set(savedOrder, forKey: "itemOrder")
        defaults.set(options, forKey: "barOptions")
        L10n.current = Language(rawValue: options[.language] ?? 0) ?? .chinese
        settings?.languageChanged()
        applyAppearance()
        applyControlIcon()
        registerHotKey()
        closeShelf(); shownUntil.removeAll(); shelfState = nil
        busy = true
        Task {
            await engine.conceal()
            await engine.setModel(currentModel())
            busy = false
            completion()
            await refresh()
            renderWindow(force: true)
        }
    }
}
