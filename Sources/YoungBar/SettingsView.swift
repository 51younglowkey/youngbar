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
    var stripOpacity: Int { stripOpacityPercent(options) }
    var tintsInterface: Bool { scope != .stripOnly }
    var accent: Color? { tintsInterface ? Color(nsColor: theme.accent) : nil }

    /// The strip has no theme colour (so no opacity) when it follows the
    /// system look.
    var stripTintLocked: Bool { scope == .interfaceOnly || theme == .clear }

    func setMode(_ key: String, _ mode: Int) {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        let entry = entries[index]
        entries[index] = BarEntry(key: entry.key, name: entry.name, image: entry.image,
                                  mode: mode, pinned: entry.pinned)
        send(.mode(key, mode))
    }

    /// Dropping a row on another takes that row's place.
    func drop(_ key: String?, on target: String) -> Bool {
        guard let key, key != target,
              let source = entries.firstIndex(where: { $0.key == key }),
              let index = entries.firstIndex(where: { $0.key == target }),
              !entries[source].pinned else { return false }
        move(from: source, to: source < index ? index + 1 : index)
        return true
    }

    /// `destination` is the index the row is placed before (as in `onMove`).
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

/// The detail column. The window behind it is tinted glass (`BarSettings`);
/// forms draw no background of their own so it shows through.
struct SettingsDetailView: View {
    @Bindable var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch model.page ?? .general {
            case .general: GeneralPane(model: model)
            case .layout: LayoutPane(model: model)
            case .appearance: AppearancePane(model: model)
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text((model.page ?? .general).title)
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .frame(height: 52)
        }
        // The original window's scrim: keeps text legible on busy wallpapers
        // while the glass still reads as glass.
        .background((colorScheme == .dark ? Color.black.opacity(0.46) : Color.white.opacity(0.58))
            .ignoresSafeArea())
        .tint(model.accent)
        // Strings are read from L10n, so a language switch rebuilds the tree.
        .id(model.value("language"))
    }
}

struct SettingsSidebar: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 2) {
            AppIdentityHeader(theme: model.theme)
            ForEach(SettingsPage.allCases) { page in
                SidebarRow(title: page.title, symbol: page.symbol, color: color(for: page),
                           accent: model.accent ?? .accentColor, selected: (model.page ?? .general) == page) {
                    model.page = page
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((model.accent ?? .clear).opacity(0.08).ignoresSafeArea())
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

/// A sidebar entry with the theme-coloured selection of the original design.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color
    let accent: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SidebarIcon(symbol: symbol, color: color)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? accent.opacity(0.22) : (hovering ? Color.primary.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The character, name and version at the top of the sidebar; not selectable.
struct AppIdentityHeader: View {
    let theme: ThemeColor

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = themeIcon(theme) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            Text("YoungBar")
                .font(.system(size: 21, weight: .semibold))
                .padding(.top, 4)
            Text(L10n.t("版本 \(version)", "Version \(version)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 16)
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
                // Form drops geometry modifiers on its pickers, so the row
                // is wrapped to give the self-test a frame.
                LabeledContent(L10n.t("语言", "Language")) {
                    Picker(L10n.t("语言", "Language"), selection: model.intBinding("language")) {
                        ForEach(Language.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .tint(.primary)
                }
                .settingsFrame("language", model)
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
                .pickerStyle(.segmented)
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
                    // Form rows don't honour `onMove`, so rows use drag and drop.
                    ForEach(model.entries) { entry in
                        LayoutRow(entry: entry, model: model)
                    }
                }
            } header: {
                Text(L10n.t("按菜单栏中的顺序，从左到右", "In menu-bar order, left to right"))
            } footer: {
                Text(L10n.t("把一行拖到另一行上即可换到那个位置，也可以右键选择移动。带锁的项目由 macOS 固定位置，但仍可隐藏。「始终隐藏」的项目只在按住 ⌥ 点击 ••• 时出现在收纳条中。",
                            "Drag a row onto another to take its place, or right-click it to reorder. Locked items are placed by macOS but can still be hidden. Always Hidden items only appear in the strip when you ⌥-click •••."))
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
                .pickerStyle(.segmented)
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
    @State private var targeted = false

    var body: some View {
        LabeledContent {
            ModeControl(entry: entry, model: model)
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
        .settingsFrame("row:\(entry.key)", model)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(targeted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
                .padding(.horizontal, -6)
                .padding(.vertical, -4)
        }
        .movable(!entry.pinned, key: entry.key)
        .dropDestination(for: String.self) { keys, _ in
            model.drop(keys.first, on: entry.key)
        } isTargeted: { targeted = $0 }
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

/// Shown / Hidden / Always Hidden as three buttons, so a change is one click.
/// Its own view type so `Form` keeps the frame modifier the self-test reads.
struct ModeControl: View {
    let entry: BarEntry
    let model: SettingsModel

    var body: some View {
        Picker(entry.name, selection: Binding(get: { entry.mode }, set: { model.setMode(entry.key, $0) })) {
            Text(L10n.t("显示", "Shown")).tag(0)
            Text(L10n.t("隐藏", "Hidden")).tag(1)
            Text(L10n.t("始终隐藏", "Always Hidden")).tag(2)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .settingsFrame("mode:\(entry.key)", model)
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
                             opacity: CGFloat(model.stripOpacity) / 100,
                             isDark: colorScheme == .dark)
                    .frame(width: 280, height: 40)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityLabel(L10n.t("收纳条预览", "Strip preview"))
                HStack(alignment: .top) {
                    Text(L10n.t("配色", "Colour"))
                    Spacer()
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(ThemeColor.allCases, id: \.self) { theme in
                            Button { model.set("themeColor", theme.rawValue) } label: {
                                ThemeSwatch(theme: theme, opacity: CGFloat(model.stripOpacity) / 100,
                                            selected: theme == model.theme)
                            }
                            .buttonStyle(.plain)
                            .help(theme.title)
                            .accessibilityLabel(theme.title)
                            .accessibilityAddTraits(theme == model.theme ? .isSelected : [])
                        }
                    }
                }
                Picker(L10n.t("应用到", "Apply to"), selection: model.intBinding("themeScope")) {
                    ForEach(ThemeScope.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(model.stripOpacity) },
                            set: { model.set("stripOpacity", Int($0.rounded())) }),
                               in: Double(stripOpacityRange.lowerBound)...Double(stripOpacityRange.upperBound))
                            .frame(width: 160)
                        Text("\(model.stripOpacity)%")
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                } label: {
                    Text(L10n.t("收纳条不透明度", "Strip opacity"))
                    Text(L10n.t("100% 为纯色，越低越透出背后的毛玻璃", "100% is solid; lower shows more of the blur behind"))
                }
                .disabled(model.stripTintLocked)
            } header: {
                Text(L10n.t("主题", "Theme"))
            } footer: {
                if model.stripTintLocked {
                    Text(model.theme == .clear
                         ? L10n.t("「透明」主题的收纳条跟随系统毛玻璃，没有主题色可调。", "The Clear theme uses the system blur only, so there is no colour to adjust.")
                         : L10n.t("主题只应用到界面时，收纳条使用系统毛玻璃。", "When the theme only applies to the interface, the strip uses the system blur."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text(L10n.t("图标", "Icon"))
                    Spacer()
                    HStack(spacing: 10) {
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
                Image(nsImage: image).resizable().scaledToFit().frame(width: 22, height: 22)
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

/// A miniature strip drawn like the real one (blur stand-in, then the
/// theme colour at the current opacity) with the theme name underneath.
struct ThemeSwatch: View {
    let theme: ThemeColor
    let opacity: CGFloat
    let selected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                Color(white: colorScheme == .dark ? 0.24 : 0.86).opacity(colorScheme == .dark ? 0.55 : 0.72)
                if theme.isTransparent {
                    Canvas { context, size in
                        let cell = size.height / 2
                        for row in 0..<2 {
                            for column in 0..<Int((size.width / cell).rounded(.up)) where (row + column) % 2 == 0 {
                                context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                                         width: cell, height: cell)),
                                             with: .color(Color.white.opacity(0.35)))
                            }
                        }
                    }
                } else {
                    Color(nsColor: theme.strip).opacity(opacity)
                }
            }
            .frame(width: 52, height: 26)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
            Text(theme.title)
                .font(.system(size: 11))
                .foregroundStyle(selected ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
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
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StripPreview: NSViewRepresentable {
    let color: ThemeColor
    let opacity: CGFloat
    let isDark: Bool

    func makeNSView(context: Context) -> ThemePreviewView { ThemePreviewView() }

    func updateNSView(_ view: ThemePreviewView, context: Context) {
        view.color = color
        view.opacity = opacity
        view.isDark = isDark
    }
}

extension View {
    /// Lets a menu-bar row be dragged onto another row.
    @ViewBuilder
    func movable(_ enabled: Bool, key: String) -> some View {
        if enabled { draggable(key) } else { self }
    }

    /// Records the control's frame so self-tests can click it.
    func settingsFrame(_ key: String, _ model: SettingsModel) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.frames[key] = $0 }
    }
}
