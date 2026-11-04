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

/// What the settings window asks for that lives outside it: the window
/// itself, permissions, launch at login and the global icon spacing.
extension BarApp {
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
                    applyUpdateNotice()
                    renderWindow(force: true)
                    settings?.languageChanged()
                    return
                }
                if key == .controlIcon {
                    applyControlIcon()
                    renderWindow(force: true)
                    return
                }
                if [.appearanceMode, .themeColor, .stripOpacity].contains(key) {
                    applyAppearance()
                    shelfState = nil
                    if expanded { populateShelf() }
                    renderWindow(force: true)
                    return
                }
                renderWindow()
            }
            controller.onHotKeyRecording = { [weak self] recording in
                if recording { self?.unregisterHotKey() } else { self?.registerHotKey() }
            }
            controller.onHotKey = { [weak self] combo in self?.setHotKey(combo) }
            controller.onExport = { [weak self] in self?.exportConfiguration() }
            controller.onImport = { [weak self] in self?.importConfiguration() }
            controller.onGuide = { [weak self] in self?.showGuide() }
            controller.onCheckUpdates = { [weak self] in self?.checkForUpdates() }
            settings = controller
        }
        renderWindow(force: true)
        settings?.show()
    }

    /// The Menu Bar page's rows, in bar order.
    func barEntries() -> [BarEntry] {
        let keys = previewOnly ? LayoutOrder.unique(savedOrder) : orderedKeys()
        return keys.map { key in
            let id = catalog[key]?.id ?? ItemID(rawValue: key)
            return BarEntry(key: key, name: name(for: key), image: fallbackImage(for: key),
                            mode: modes[key] ?? 0,
                            pinned: MenuBarPolicy.isPinnedSystemItem(id) || MenuBarPolicy.isPinnedAppleHost(id.bundleID),
                            covered: overflowKeys.contains(key))
        }
    }

    /// Pushes the current state into the settings window. Skipped while the
    /// window is closed — `showWindow` renders in full (`force`) when it
    /// opens — so actions and refresh ticks don't rebuild rows nobody sees.
    func renderWindow(force: Bool = false) {
        guard let settings, force || settings.isVisible else { return }
        let message: String
        if !AXIsProcessTrusted() { message = L10n.t("需要辅助功能权限", "Accessibility permission required") }
        else if !feedback.isEmpty { message = feedback }
        else { message = "" }
        settings.update(entries: barEntries(), message: message,
                        axTrusted: AXIsProcessTrusted(), launchAtLogin: launchAtLoginEnabled,
                        loginNeedsApproval: launchAtLoginNeedsApproval,
                        customIcon: customIconImage, options: options,
                        hotKey: hotKeyDisplay, hasHotKey: hotKey != nil, hasNotch: notchVisibleMinX != nil)
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, but macOS waits for the user to allow it in System
    /// Settings → General → Login Items; the switch reads off meanwhile.
    var launchAtLoginNeedsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
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
        // Registering can succeed (or throw) and still leave the login item
        // switched off in System Settings: say so and take the user there.
        if enabled && launchAtLoginNeedsApproval {
            feedback = L10n.t("还差一步：在「系统设置 → 通用 → 登录项」里允许 YoungBar",
                              "One more step: allow YoungBar in System Settings → General → Login Items")
            SMAppService.openSystemSettingsLoginItems()
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
}
