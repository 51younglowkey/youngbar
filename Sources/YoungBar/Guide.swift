// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// First-run guide: the one permission, then where things are. Shown once
/// on a fresh install; Settings → General → Getting started reopens it.
@MainActor
@Observable
final class GuideModel {
    var axTrusted = AXIsProcessTrusted()
    var hotKey = ""
    var theme: ThemeColor = .blue
    @ObservationIgnored var requestAccess: () -> Void = {}
    @ObservationIgnored var openLayout: () -> Void = {}
    @ObservationIgnored var finish: () -> Void = {}
}

struct GuideView: View {
    let model: GuideModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                if let image = themeIcon(model.theme) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("欢迎使用 YoungBar", "Welcome to YoungBar"))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.t("把不常用的菜单栏图标收起来，需要时从收纳条打开。",
                                "Tuck away menu-bar icons you rarely use; open them from the strip."))
                        .foregroundStyle(.secondary)
                }
            }
            GuideStep(number: 1, title: L10n.t("允许「设备控制与数据访问」", "Allow Device Control and Data Access"),
                      detail: L10n.t("YoungBar 用它读取、隐藏和排序菜单栏图标，不截屏、不联网。授权后这里会自动更新。",
                                     "YoungBar uses it to read, hide and reorder menu-bar icons. No screenshots, no network. This updates by itself once allowed.")) {
                if model.axTrusted {
                    Label(L10n.t("已授权", "Allowed"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(L10n.t("授权…", "Allow…"), action: model.requestAccess)
                }
            }
            GuideStep(number: 2, title: L10n.t("选择要收起的图标", "Choose icons to tuck away"),
                      detail: L10n.t("在设置的「菜单栏」页，把不常用的图标设为「隐藏」。",
                                     "In Settings → Menu Bar, set the icons you rarely use to Hide.")) {
                Button(L10n.t("打开", "Open"), action: model.openLayout)
                    .disabled(!model.axTrusted)
            }
            GuideStep(number: 3, title: L10n.t("打开收纳条", "Open the strip"),
                      detail: L10n.t("点菜单栏里的 •••，或按 \(model.hotKey)。打开后直接输入名称搜索，← → 选择，回车打开。",
                                     "Click ••• in the menu bar or press \(model.hotKey). Then type to search, ← → to choose, Return to open.")) {
                EmptyView()
            }
            HStack {
                Spacer()
                Button(L10n.t("完成", "Done"), action: model.finish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 480)
        .tint(model.theme == .clear ? nil : Color(nsColor: model.theme.accent))
    }
}

struct GuideStep<Trailing: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .accessibilityElement(children: .contain)
    }
}

extension BarApp {
    /// A fresh install (no saved layout) gets the guide; an update from an
    /// older version is marked as already introduced.
    var needsGuide: Bool {
        options[.onboarded] != 1 && UserDefaults.standard.object(forKey: "itemModes") == nil
            && UserDefaults.standard.object(forKey: "hiddenBundles") == nil
    }

    func showGuide() {
        if guideWindow == nil {
            let model = GuideModel()
            model.requestAccess = { [weak self] in self?.requestAccessibility() }
            model.openLayout = { [weak self] in
                self?.finishGuide()
                self?.showWindow()
                self?.settings?.select(.layout)
            }
            model.finish = { [weak self] in self?.finishGuide() }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = L10n.t("欢迎使用 YoungBar", "Welcome to YoungBar")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: GuideView(model: model))
            window.center()
            guideModel = model
            guideWindow = window
            guideCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.markGuided() }
            }
        }
        guideModel?.hotKey = hotKeyDisplay
        guideModel?.theme = themeColor
        guideModel?.axTrusted = AXIsProcessTrusted()
        guideWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The grant happens in System Settings; watch for it while the guide is up.
        guideTimer?.invalidate()
        guideTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let window = self.guideWindow, window.isVisible else {
                    self?.guideTimer?.invalidate()
                    return
                }
                let trusted = AXIsProcessTrusted()
                if trusted != self.guideModel?.axTrusted {
                    self.guideModel?.axTrusted = trusted
                    if trusted { await self.refresh() }
                }
            }
        }
    }

    func finishGuide() {
        markGuided()
        guideWindow?.orderOut(nil)
        guideTimer?.invalidate()
    }

    func markGuided() {
        guard options[.onboarded] != 1 else { return }
        options[.onboarded] = 1
        UserDefaults.standard.set(options, forKey: "barOptions")
    }
}
