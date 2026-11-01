// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import YoungBarCore

/// After an update: the changelog bundled with this version (copied from
/// `docs/RELEASE-<version>.md` by `Scripts/build.sh`), then a short tour of
/// what changed, one page at a time; either can be skipped. Shown once
/// after an update and from the ••• menu any time.
///
/// Its text follows the system language (the changelog has a Chinese and
/// an English half), not YoungBar's own language setting.
@MainActor
@Observable
final class UpdateIntroModel {
    var page = 0
    /// The shortcut opened the strip while the tour was up.
    var triedShortcut = false
    var autoHideNew = false
    var shortcut = ""
    var version = ""
    var notes: [ReleaseNotes.Block] = []
    var theme: ThemeColor = .blue
    var english = UpdateIntroModel.systemIsEnglish
    @ObservationIgnored var setAutoHideNew: (Bool) -> Void = { _ in }
    @ObservationIgnored var close: () -> Void = {}

    static var systemIsEnglish: Bool { !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false) }

    func t(_ chinese: String, _ english: String) -> String { self.english ? english : chinese }

    /// The tour that goes with this version; none for a version without one.
    var steps: [TourStep] {
        guard version.hasPrefix("0.1.4") else { return [] }
        return [
            TourStep(symbol: "command", kind: .shortcut,
                     title: t("连按两下 ⌘ 打开收纳条", "Press ⌘ twice for the strip"),
                     detail: t("快速按两下 ⌘ 就能打开收纳条，不用去点 •••。在设置的「通用」里可以换成别的快捷键。",
                               "Press ⌘ twice, quickly, to open the strip without reaching for •••. General in Settings has other choices.")),
            TourStep(symbol: "number.square", kind: .plain,
                     title: t("图标快捷键 1–9", "Number keys 1–9"),
                     detail: t("收纳条打开后，图标下方标着 1–9，按数字直接打开对应的图标。不想看到数字，可以在设置里关掉，按数字照样能用。",
                               "With the strip open, the icons are numbered 1–9; press a number to open one. The numbers can be hidden in Settings and the keys still work.")),
            TourStep(symbol: "hand.draw", kind: .plain,
                     title: t("拖动排序，右键改显示方式", "Drag to reorder, right-click to change"),
                     detail: t("在收纳条里按住图标左右拖就能换位置。右键图标，可以放回菜单栏或改为始终隐藏，不用打开设置。",
                               "Hold an icon in the strip and drag it sideways to move it. Right-click it to put it back in the menu bar or make it Always Hidden — no trip to Settings.")),
            TourStep(symbol: "tray.and.arrow.down", kind: .autoHide,
                     title: t("新图标自动收纳", "Auto-hide new icons"),
                     detail: t("打开后，新装应用第一次出现在菜单栏的图标会直接进收纳条，系统图标不受影响。",
                               "When on, an app's icon that appears in the menu bar for the first time goes straight to the strip. System icons are left alone.")),
            TourStep(symbol: "bubble.left.and.text.bubble.right", kind: .plain,
                     title: t("更新提示和问题反馈", "Updates and feedback"),
                     detail: t("有新版本时，右键 ••• 的菜单第一行会提示。遇到 bug，可以在同一个菜单里点「复制诊断信息」，发到群里给我。感谢大家的支持！",
                               "When there is a new version, the first line of the ••• right-click menu says so. If something breaks, choose Copy Diagnostics in that menu and send it to me. Thanks for the support!")),
        ]
    }
}

struct TourStep {
    enum Kind { case plain, shortcut, autoHide }
    let symbol: String
    let kind: Kind
    let title: String
    let detail: String
}

struct UpdateIntroView: View {
    @Bindable var model: UpdateIntroModel

    private var accent: Color { model.theme == .clear ? .accentColor : Color(nsColor: model.theme.accent) }
    private var pageCount: Int { 1 + model.steps.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.page == 0 {
                notesPage
            } else if model.steps.indices.contains(model.page - 1) {
                stepPage(model.steps[model.page - 1])
            }
            footer
        }
        .padding(24)
        .frame(width: 400, height: 470, alignment: .topLeading)
        .tint(model.theme == .clear ? nil : accent)
    }

    private var notesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t("YoungBar \(model.version) 更新内容", "What's new in YoungBar \(model.version)"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                NotesView(blocks: model.notes, accent: accent)
                    .padding(14)
            }
            .defaultScrollAnchor(.top)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func stepPage(_ step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t("新功能 \(model.page)/\(model.steps.count)", "New \(model.page) of \(model.steps.count)"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Image(systemName: step.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.opacity(0.15)))
                .accessibilityHidden(true)
            Text(step.title).font(.system(size: 18, weight: .semibold))
            Text(step.detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch step.kind {
            case .shortcut:
                if model.triedShortcut {
                    Label(model.t("成功打开了收纳条", "That opened the strip"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(model.t("现在试试：\(model.shortcut)", "Try it now: \(model.shortcut)"), systemImage: "keyboard")
                        .foregroundStyle(accent)
                }
            case .autoHide:
                Toggle(model.t("打开新图标自动收纳", "Auto-hide new icons"), isOn: Binding(
                    get: { model.autoHideNew },
                    set: { model.autoHideNew = $0; model.setAutoHideNew($0) }))
                    .toggleStyle(.switch)
            case .plain:
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.page < pageCount - 1 {
                Button(model.t("跳过", "Skip"), action: model.close)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if pageCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == model.page ? accent : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Spacer()
            }
            if model.page > 0 {
                Button(model.t("上一步", "Back")) { model.page -= 1 }
            }
            if model.page < pageCount - 1 {
                Button(model.page == 0 ? model.t("了解新功能", "See what's new") : model.t("下一步", "Next")) { model.page += 1 }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(model.t("完成", "Done"), action: model.close)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension BarApp {
    var bundledReleaseNotes: [ReleaseNotes.Block]? {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let blocks = ReleaseNotes.blocks(ReleaseNotes.localized(text, preferredLanguages: Locale.preferredLanguages))
        return blocks.isEmpty ? nil : blocks
    }

    /// The shortcut in the tour's language (it follows the system's, not
    /// YoungBar's setting, so `hotKeyDisplay` can't be used as is).
    func shortcutForTour(english: Bool) -> String {
        guard let hotKey else { return english ? "the shortcut (none set)" : "快捷键（未设置）" }
        if hotKey.isDoubleTap {
            return english ? "press \(hotKey.modifierSymbols) twice" : "连按两下 \(hotKey.modifierSymbols)"
        }
        return hotKey.display(keyName: Self.keyName(for: hotKey.keyCode))
    }

    @objc func showWhatsNew() {
        guard let notes = bundledReleaseNotes else { return }
        let model = UpdateIntroModel()
        model.version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        model.notes = notes
        model.theme = themeColor
        model.shortcut = shortcutForTour(english: model.english)
        model.autoHideNew = options[.autoHideNew] == 1
        model.setAutoHideNew = { [weak self] on in
            guard let self else { return }
            options[.autoHideNew] = on ? 1 : 0
            UserDefaults.standard.set(options, forKey: "barOptions")
            renderWindow()
        }
        let window = whatsNewWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 470),
                                                styleMask: [.titled, .closable, .fullSizeContentView],
                                                backing: .buffered, defer: false)
        model.close = { [weak window] in window?.orderOut(nil) }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = model.t("更新内容", "What's New")
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: UpdateIntroView(model: model))
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        whatsNewWindow = window
        updateIntro = model
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
