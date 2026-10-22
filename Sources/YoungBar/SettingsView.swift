// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Settings window content, modelled on System Settings: a source-list
/// sidebar and grouped forms. Hosted by `BarSettings`; everything that touches
/// the menu bar stays in AppKit and is reached through `SettingsAction`.

extension BarEntry: Identifiable {
    var id: String { key }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, layout, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.t("通用", "General")
        case .layout: return L10n.t("菜单栏", "Menu Bar")
        case .appearance: return L10n.t("外观", "Appearance")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .layout: return "menubar.rectangle"
        case .appearance: return "paintpalette.fill"
        }
    }
}

enum SettingsAction {
    case option(String, Int)
    case mode(String, Int)
    case move(String, String)
    case login(Bool)
    case permission(String)
    case spacing(Int)
    case chooseCustomIcon
    case removeCustomIcon
    case refresh
}

@MainActor
@Observable
final class SettingsModel {
    var page: SettingsPage? = .general {
        didSet { onPageChange(page ?? .general) }
    }
    var entries: [BarEntry] = []
    var options: [String: Int] = [:]
    var launchAtLogin = false
    var axTrusted = false
    var captureAllowed = false
    var message = ""
    var customIcon: NSImage?

    /// Frames (SwiftUI global space) of controls the self-tests click.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored var send: (SettingsAction) -> Void = { _ in }
    @ObservationIgnored var onPageChange: (SettingsPage) -> Void = { _ in }

    func value(_ key: String, _ fallback: Int = 0) -> Int { options[key] ?? fallback }

    func set(_ key: String, _ value: Int) {
        options[key] = value
        send(.option(key, value))
    }

    func intBinding(_ key: String, _ fallback: Int = 0) -> Binding<Int> {
        Binding(get: { self.value(key, fallback) }, set: { self.set(key, $0) })
    }

    func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { self.value(key) == 1 }, set: { self.set(key, $0 ? 1 : 0) })
    }

    var theme: ThemeColor { ThemeColor(rawValue: value("themeColor")) ?? .blue }
    var scope: ThemeScope { ThemeScope(rawValue: value("themeScope")) ?? .both }
    var stripStyle: StripStyle { StripStyle(rawValue: value("stripStyle")) ?? .solid }
    var tintsInterface: Bool { scope != .stripOnly }
    var accent: Color? { tintsInterface ? Color(nsColor: theme.accent) : nil }

    /// The strip ignores its material when it follows the system look.
    var stripStyleLocked: Bool { scope == .interfaceOnly || theme == .clear }

    func setMode(_ key: String, _ mode: Int) {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        let entry = entries[index]
        entries[index] = BarEntry(key: entry.key, name: entry.name, image: entry.image,
                                  mode: mode, pinned: entry.pinned)
        send(.mode(key, mode))
    }

    /// `destination` follows `onMove`: the index the row is dropped before.
    /// Rows never land after the macOS-pinned items at the right edge.
    func move(from source: Int, to destination: Int) {
        guard entries.indices.contains(source), !entries[source].pinned else { return }
        var list = entries
        let item = list.remove(at: source)
        var index = destination > source ? destination - 1 : destination
        if let firstPinned = list.firstIndex(where: \.pinned) { index = min(index, firstPinned) }
        index = max(0, min(index, list.count))
        guard index != source else { return }
        list.insert(item, at: index)
        let next = index + 1 < list.count ? list[index + 1].key : ""
        entries = list
        send(.move(item.key, next))
    }
}

// MARK: - Root

/// The detail column. The sidebar lives in its own `NSSplitViewItem` so it
/// gets the native floating sidebar material.
struct SettingsDetailView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Group {
            switch model.page ?? .general {
            case .general: GeneralPane(model: model)
            case .layout: LayoutPane(model: model)
            case .appearance: AppearancePane(model: model)
            }
        }
        .tint(model.accent)
        // Strings are read from L10n, so a language switch rebuilds the tree.
        .id(model.value("language"))
    }
}

struct SettingsSidebar: View {
    @Bindable var model: SettingsModel

    var body: some View {
        List(selection: $model.page) {
            AppIdentityRow(theme: model.theme)
            Section {
                ForEach(SettingsPage.allCases) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        SidebarIcon(symbol: page.symbol, color: color(for: page))
                    }
                    .tag(page)
                }
            }
        }
        .listStyle(.sidebar)
        .id(model.value("language"))
    }

    private func color(for page: SettingsPage) -> Color {
        switch page {
        case .general: return .gray
        case .layout: return .blue
        case .appearance: return model.theme == .clear ? .purple : Color(nsColor: model.theme.accent)
        }
    }
}

/// The account-style row at the top of the sidebar; not selectable.
struct AppIdentityRow: View {
    let theme: ThemeColor

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image = themeIcon(theme) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("YoungBar").font(.headline)
                Text(L10n.t("版本 \(version)", "Version \(version)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct SidebarIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.gradient))
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(L10n.t("登录时打开", "Open at login"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0; model.send(.login($0)) }))
                    .settingsFrame("login", model)
                Picker(L10n.t("语言", "Language"), selection: model.intBinding("language")) {
                    ForEach(Language.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .tint(.primary)
            }

            Section {
                Picker(selection: model.intBinding("nativeExpand")) {
                    Text(L10n.t("打开收纳条", "Open the strip")).tag(0)
                    Text(L10n.t("在菜单栏中展开", "Expand in the menu bar")).tag(1)
                } label: {
                    Text(L10n.t("点击 ••• 时", "When clicking •••"))
                    Text(L10n.t("收纳条把隐藏的图标集中在一条浮动栏里；在菜单栏中展开会让它们临时回到原位。",
                                "The strip gathers hidden icons in one floating bar; expanding puts them back in the menu bar for a while."))
                }
                .tint(.primary)
                Toggle(isOn: model.boolBinding("keepShelfOpen")) {
                    Text(L10n.t("始终显示收纳条", "Keep the strip open"))
                    Text(L10n.t("点击别处时不自动关闭", "Don't close it when clicking elsewhere"))
                }
                Toggle(L10n.t("鼠标悬停 0.5 秒后展开", "Open on hover after 0.5 s"),
                       isOn: model.boolBinding("hoverExpand"))
                Toggle(L10n.t("点击菜单栏空白处展开", "Open when clicking empty menu-bar space"),
                       isOn: model.boolBinding("blankClick"))
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(model.value("revealSeconds", 20)) },
                            set: { model.set("revealSeconds", Int($0.rounded())) }), in: 5...60)
                            .frame(width: 160)
                        Text(L10n.t("\(model.value("revealSeconds", 20)) 秒", "\(model.value("revealSeconds", 20)) s"))
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                } label: {
                    Text(L10n.t("自动收起", "Hide again after"))
                    Text(L10n.t("点开收纳项后，它在菜单栏上停留的时间", "How long a clicked item stays in the menu bar"))
                }
            } header: {
                Text(L10n.t("收纳条", "Strip"))
            }

            Section {
                PermissionRow(title: L10n.t("辅助功能", "Accessibility"),
                              detail: L10n.t("读取、隐藏和排序菜单栏图标", "Read, hide and reorder menu-bar items"),
                              granted: model.axTrusted) { model.send(.permission("accessibility")) }
                PermissionRow(title: L10n.t("屏幕录制", "Screen Recording"),
                              detail: L10n.t("在收纳条中显示原始菜单栏图标", "Show original menu-bar icons in the strip"),
                              granted: model.captureAllowed) { model.send(.permission("screen")) }
            } header: {
                Text(L10n.t("权限", "Permissions"))
            }

            Section {
                LabeledContent {
                    Button(L10n.t("刷新", "Refresh")) { model.send(.refresh) }
                        .settingsFrame("refresh", model)
                } label: {
                    Text(L10n.t("菜单栏项目列表", "Menu-bar item list"))
                    Text(L10n.t("重新读取菜单栏里的项目", "Read the menu-bar items again"))
                }
            } footer: {
                if !model.message.isEmpty {
                    Text(model.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(granted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(granted ? L10n.t("已授权", "Granted") : L10n.t("未授权", "Not granted"))
                        .foregroundStyle(.secondary)
                }
                Button(granted ? L10n.t("打开设置…", "Open Settings…") : L10n.t("授权…", "Authorize…"),
                       action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

// MARK: - Menu bar items

struct LayoutPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                if model.entries.isEmpty {
                    Text(model.axTrusted
                         ? L10n.t("正在读取菜单栏图标…", "Reading menu-bar items…")
                         : L10n.t("需要辅助功能权限后才能读取菜单栏项目。", "Accessibility permission is required to read menu-bar items."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    ForEach(model.entries) { entry in
                        LayoutRow(entry: entry, model: model)
                            .moveDisabled(entry.pinned)
                    }
                    .onMove { offsets, destination in
                        if let source = offsets.first { model.move(from: source, to: destination) }
                    }
                }
            } header: {
                Text(L10n.t("按菜单栏中的顺序，从左到右", "In menu-bar order, left to right"))
            } footer: {
                Text(L10n.t("拖动行可以调整顺序，也可以右键选择移动。带锁的项目由 macOS 固定位置，但仍可隐藏。「始终隐藏」的项目只在按住 ⌥ 点击 ••• 时出现在收纳条中。",
                            "Drag a row, or right-click it, to reorder. Locked items are placed by macOS but can still be hidden. Always Hidden items only appear in the strip when you ⌥-click •••."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: Binding(
                    get: { model.value("iconSpacing") },
                    set: { model.options["iconSpacing"] = $0; model.send(.spacing($0)) })) {
                    Text(L10n.t("默认", "Default")).tag(0)
                    Text(L10n.t("较小", "Smaller")).tag(1)
                    Text(L10n.t("小", "Small")).tag(2)
                    Text(L10n.t("无", "None")).tag(3)
                } label: {
                    Text(L10n.t("图标间隙", "Icon spacing"))
                    Text(L10n.t("写入系统全局偏好，重启电脑后生效", "Writes a global preference; takes effect after a reboot"))
                }
                .tint(.primary)
            } header: {
                Text(L10n.t("间距", "Spacing"))
            }

        }
        .formStyle(.grouped)
    }
}

struct LayoutRow: View {
    let entry: BarEntry
    let model: SettingsModel

    var body: some View {
        LabeledContent {
            Picker(entry.name, selection: Binding(get: { entry.mode }, set: { model.setMode(entry.key, $0) })) {
                Text(L10n.t("显示", "Shown")).tag(0)
                Text(L10n.t("隐藏", "Hidden")).tag(1)
                Text(L10n.t("始终隐藏", "Always Hidden")).tag(2)
            }
            .labelsHidden()
            .fixedSize()
            .tint(.primary)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.pinned ? "lock.fill" : "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Group {
                    if let image = entry.image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "app.dashed")
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(entry.pinned
              ? L10n.t("位置由 macOS 固定，不能移动；仍然可以隐藏", "macOS fixes this item's position; it can still be hidden")
              : "")
        .contextMenu {
            if !entry.pinned, let index = model.entries.firstIndex(where: { $0.key == entry.key }) {
                Button(L10n.t("移到最左", "Move to Far Left")) { model.move(from: index, to: 0) }
                    .disabled(index == 0)
                Button(L10n.t("左移一位", "Move Left")) { model.move(from: index, to: index - 1) }
                    .disabled(index == 0)
                Button(L10n.t("右移一位", "Move Right")) { model.move(from: index, to: index + 2) }
                Button(L10n.t("移到最右", "Move to Far Right")) { model.move(from: index, to: model.entries.count) }
            }
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("外观", "Appearance"), selection: model.intBinding("appearanceMode")) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                StripPreview(color: model.scope == .interfaceOnly ? .clear : model.theme,
                             style: model.stripStyle,
                             isDark: colorScheme == .dark)
                    .frame(width: 280, height: 40)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityLabel(L10n.t("收纳条预览", "Strip preview"))
                LabeledContent {
                    HStack(spacing: 10) {
                        ForEach(ThemeColor.allCases, id: \.self) { theme in
                            Button { model.set("themeColor", theme.rawValue) } label: {
                                ThemeSwatch(theme: theme, selected: theme == model.theme)
                            }
                            .buttonStyle(.plain)
                            .help(theme.title)
                            .accessibilityLabel(theme.title)
                            .accessibilityAddTraits(theme == model.theme ? .isSelected : [])
                        }
                    }
                } label: {
                    Text(L10n.t("配色", "Colour"))
                    Text(model.theme.title)
                }
                Picker(L10n.t("应用到", "Apply to"), selection: model.intBinding("themeScope")) {
                    ForEach(ThemeScope.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .tint(.primary)
                Picker(L10n.t("收纳条材质", "Strip material"), selection: model.intBinding("stripStyle")) {
                    ForEach(StripStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(model.stripStyleLocked)
            } header: {
                Text(L10n.t("主题", "Theme"))
            } footer: {
                if model.stripStyleLocked {
                    Text(model.theme == .clear
                         ? L10n.t("「透明」主题的收纳条跟随系统材质，不能单独调整。", "The Clear theme follows the system material, so the strip material can't be changed.")
                         : L10n.t("主题只应用到界面时，收纳条使用系统材质。", "When the theme only applies to the interface, the strip uses the system material."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text(L10n.t("图标", "Icon"))
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(ControlIcon.symbols.indices, id: \.self) { index in
                            IconTile(selected: model.value("controlIcon") == index) {
                                model.set("controlIcon", index)
                            } content: {
                                Image(systemName: ControlIcon.symbols[index])
                            }
                            .help(ControlIcon.title(index))
                            .accessibilityLabel(ControlIcon.title(index))
                        }
                        customTile
                    }
                }
            } header: {
                Text(L10n.t("菜单栏按钮", "Menu-Bar Button"))
            } footer: {
                Text(model.customIcon == nil
                     ? L10n.t("点 ＋ 选择一张图片作为菜单栏按钮，建议使用 36×36 的 PNG。", "Click + to use your own image; a 36×36 PNG works best.")
                     : L10n.t("右键点自定义图片可以更换或移除。", "Right-click the custom image to replace or remove it."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var customTile: some View {
        let customIndex = ControlIcon.symbols.count
        return IconTile(selected: model.value("controlIcon") == customIndex) {
            if model.customIcon == nil {
                model.send(.chooseCustomIcon)
            } else {
                model.set("controlIcon", customIndex)
            }
        } content: {
            if let image = model.customIcon {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 18, height: 18)
            } else {
                Image(systemName: "plus")
            }
        }
        .help(model.customIcon == nil ? L10n.t("选择图片…", "Choose Image…") : ControlIcon.title(customIndex))
        .accessibilityLabel(model.customIcon == nil ? L10n.t("选择图片", "Choose Image") : ControlIcon.title(customIndex))
        .contextMenu {
            Button(L10n.t("选择图片…", "Choose Image…")) { model.send(.chooseCustomIcon) }
            Button(L10n.t("移除自定义图片", "Remove Custom Image")) { model.send(.removeCustomIcon) }
                .disabled(model.customIcon == nil)
        }
    }
}

/// A miniature strip: the theme accent fading into the strip colour.
struct ThemeSwatch: View {
    let theme: ThemeColor
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if theme.isTransparent {
                Canvas { context, size in
                    let cell = size.height / 2
                    for row in 0..<2 {
                        for column in 0..<Int((size.width / cell).rounded(.up)) {
                            let light = (row + column) % 2 == 0
                            context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                                     width: cell, height: cell)),
                                         with: .color(light ? Color.white.opacity(0.55) : Color.gray.opacity(0.45)))
                        }
                    }
                }
            } else {
                LinearGradient(colors: [Color(nsColor: theme.accent), Color(nsColor: theme.strip)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: 36, height: 22)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous)
            .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
        .contentShape(Rectangle())
    }
}

struct IconTile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StripPreview: NSViewRepresentable {
    let color: ThemeColor
    let style: StripStyle
    let isDark: Bool

    func makeNSView(context: Context) -> ThemePreviewView { ThemePreviewView() }

    func updateNSView(_ view: ThemePreviewView, context: Context) {
        view.color = color
        view.style = style
        view.isDark = isDark
    }
}

extension View {
    /// Records the control's frame so self-tests can click it.
    func settingsFrame(_ key: String, _ model: SettingsModel) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.frames[key] = $0 }
    }
}
