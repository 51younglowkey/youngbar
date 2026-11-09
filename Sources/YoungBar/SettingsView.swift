// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import YoungBarCore

/// Settings window content, modelled on System Settings: a source-list
/// sidebar and grouped forms. Hosted by `BarSettings`; everything that touches
/// the menu bar stays in AppKit and is reached through `SettingsAction`.

extension BarEntry: Identifiable {
    var id: String { key }
}

/// Sidebar order is how often each page is used: the menu-bar icons first
/// (why Settings is usually opened), General last (set once).
enum SettingsPage: String, CaseIterable, Identifiable {
    case layout, appearance, general

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
    case option(Option, Int)
    case mode(String, Int)
    case move(String, String)
    case login(Bool)
    case permission(String)
    case spacing(Int)
    case chooseCustomIcon
    case removeCustomIcon
    /// Start (true) or cancel (false) recording a new global shortcut.
    case recordHotKey(Bool)
    case clearHotKey
    case exportConfig
    case importConfig
    case showGuide
    case checkUpdates
}

@MainActor
@Observable
final class SettingsModel {
    var page: SettingsPage? = .layout {
        didSet { onPageChange(page ?? .layout) }
    }
    var entries: [BarEntry] = []
    var options: [String: Int] = [:]
    var launchAtLogin = false
    /// Registered, but switched off in System Settings → Login Items.
    var loginNeedsApproval = false
    var axTrusted = false
    var message = ""
    var customIcon: NSImage?
    /// Hover and drop highlights live here, not in `@State`: on the
    /// Command Line Tools toolchain `@State` is a macro whose plugin
    /// ships only with Xcode, so the package must not use it.
    var hoveredPage: SettingsPage?
    var dropTarget: String?
    var hotKeyDisplay = ""
    var hasHotKey = true
    var recordingHotKey = false
    /// The control's display has a notch.
    var hasNotch = false

    /// Frames (SwiftUI global space) of controls the self-tests click.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored var send: (SettingsAction) -> Void = { _ in }
    @ObservationIgnored var onPageChange: (SettingsPage) -> Void = { _ in }

    func value(_ key: Option, _ fallback: Int = 0) -> Int { options[key] ?? fallback }

    func set(_ key: Option, _ value: Int) {
        options[key] = value
        send(.option(key, value))
    }

    func intBinding(_ key: Option, _ fallback: Int = 0) -> Binding<Int> {
        Binding(get: { self.value(key, fallback) }, set: { self.set(key, $0) })
    }

    func boolBinding(_ key: Option, default fallback: Bool = false) -> Binding<Bool> {
        Binding(get: { self.value(key, fallback ? 1 : 0) == 1 }, set: { self.set(key, $0 ? 1 : 0) })
    }

    var theme: ThemeColor { ThemeColor(rawValue: value(.themeColor)) ?? .blue }
    var stripOpacity: Int { stripOpacityPercent(options) }
    var accent: Color? { Color(nsColor: theme.accent) }

    /// The Clear theme's strip has no colour, so no opacity.
    var stripTintLocked: Bool { theme == .clear }

    func setMode(_ key: String, _ mode: Int) {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        entries[index].mode = mode
        send(.mode(key, mode))
    }

    /// Dropping a row on another takes that row's place.
    func drop(_ key: String?, on target: String) -> Bool {
        guard let key, key != target,
              let source = entries.firstIndex(where: { $0.key == key }),
              let index = entries.firstIndex(where: { $0.key == target }),
              !entries[source].pinned,
              // Strip rows and bar rows don't swap: the mode says which it is.
              (entries[source].mode > 0) == (entries[index].mode > 0) else { return false }
        move(from: source, to: source < index ? index + 1 : index)
        return true
    }

    /// The strip's rows (Hide, Always Hide), then the bar's.
    var hiddenEntries: [BarEntry] { entries.filter { $0.mode > 0 } }
    var shownEntries: [BarEntry] { entries.filter { $0.mode == 0 } }

    /// The first row of `entry`'s group: the strip's rows come first.
    func groupStart(of entry: BarEntry) -> Int {
        entry.mode > 0 ? 0 : entries.filter { $0.mode > 0 }.count
    }

    /// The last row of `entry`'s group.
    func groupEnd(of entry: BarEntry) -> Int {
        entry.mode > 0 ? entries.filter { $0.mode > 0 }.count - 1 : entries.count - 1
    }

    /// `destination` is the index the row is placed before (as in `onMove`).
    /// A row stays in its group (strip or bar), and never lands after the
    /// macOS-pinned items at the right edge.
    func move(from source: Int, to destination: Int) {
        guard entries.indices.contains(source), !entries[source].pinned else { return }
        var list = entries
        let item = list.remove(at: source)
        var index = destination > source ? destination - 1 : destination
        // Never after the locked run at the right end (the clock and Control
        // Center). A locked Apple item in the middle (Time Machine, VPN…)
        // doesn't stop others passing it: clamping at the first locked row
        // turned a move to the right into one to the left.
        let end = list.lastIndex(where: { !$0.pinned }).map { $0 + 1 } ?? 0
        index = LayoutOrder.clampedIndex(index, hidden: item.mode > 0,
                                         hiddenCount: list.filter { $0.mode > 0 }.count, end: end)
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
            switch model.page ?? .layout {
            case .general: GeneralPane(model: model)
            case .layout: LayoutPane(model: model)
            case .appearance: AppearancePane(model: model)
            }
        }
        .scrollContentBackground(.hidden)
        // The title is its own strip of glass at the very top, level with
        // the traffic lights; content scrolling underneath is blurred
        // instead of running into the title.
        .safeAreaInset(edge: .top, spacing: 0) {
            Text((model.page ?? .layout).title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .frame(height: 52)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                }
        }
        .ignoresSafeArea(.container, edges: .top)
        // The original window's scrim: keeps text legible on busy wallpapers
        // while the glass still reads as glass.
        .background((colorScheme == .dark ? Color.black.opacity(0.46) : Color.white.opacity(0.58))
            .ignoresSafeArea())
        .tint(model.accent)
        // Strings are read from L10n, so a language switch rebuilds the tree.
        .id(model.value(.language))
    }
}

struct SettingsSidebar: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 2) {
            AppIdentityHeader(theme: model.theme)
            ForEach(SettingsPage.allCases) { page in
                SidebarRow(title: page.title, symbol: page.symbol, color: color(for: page),
                           accent: model.accent ?? .accentColor, selected: (model.page ?? .layout) == page,
                           hovering: model.hoveredPage == page,
                           onHover: { inside in
                               if inside { model.hoveredPage = page } else if model.hoveredPage == page { model.hoveredPage = nil }
                           }) {
                    model.page = page
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((model.accent ?? .clear).opacity(0.08).ignoresSafeArea())
        .id(model.value(.language))
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
    let hovering: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

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
        .onHover(perform: onHover)
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

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0; model.send(.login($0)) })) {
                    Text(L10n.t("登录时打开", "Open at login"))
                    if model.loginNeedsApproval {
                        Text(L10n.t("还需要在「系统设置 → 通用 → 登录项」里允许；打开开关会带你过去",
                                    "Still needs your OK in System Settings → General → Login Items; turning this on takes you there"))
                    }
                }
                .settingsFrame("login", model)
                // Form drops geometry modifiers on its pickers, so the row
                // is wrapped to give the self-test a frame.
                LabeledContent(L10n.t("语言", "Language")) {
                    Picker(L10n.t("语言", "Language"), selection: model.intBinding(.language)) {
                        ForEach(Language.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .tint(.primary)
                }
                .settingsFrame("language", model)
            }

            Section {
                LabeledContent {
                    HotKeyField(model: model)
                } label: {
                    Text(L10n.t("快捷键", "Shortcut"))
                    Text(L10n.t("打开后按 1–9 直接打开对应图标，Esc 关闭",
                                "Then press 1–9 to open that icon; Esc closes"))
                }
                Toggle(isOn: model.boolBinding(.shelfNumbers, default: true)) {
                    Text(L10n.t("图标下方显示数字", "Show numbers under icons"))
                    Text(L10n.t("收纳条里的前 9 个图标标出 1–9；关掉后按数字照样能打开", "The first nine icons are numbered; the number keys work either way"))
                }
                Toggle(L10n.t("鼠标悬停 0.5 秒后打开", "Open on hover after 0.5 s"),
                       isOn: model.boolBinding(.hoverExpand))
                Toggle(isOn: model.boolBinding(.autoHideNew)) {
                    Text(L10n.t("新图标自动收纳", "Put new icons in the strip"))
                    Text(L10n.t("新装应用的图标直接进收纳条，系统图标不受影响",
                                "New apps' icons go straight to the strip; system icons stay"))
                }
            } header: {
                Text(L10n.t("收纳条", "Strip"))
            }

            Section {
                LabeledContent {
                    Button(L10n.t("检查更新…", "Check for Updates…")) { model.send(.checkUpdates) }
                } label: {
                    Text(L10n.t("版本 \(Self.version)", "Version \(Self.version)"))
                    Text(L10n.t("每天自动检查；有新版本时右键 ••• 会提示", "Checked daily; a new version shows in the ••• right-click menu"))
                }
                LabeledContent {
                    Button(L10n.t("打开", "Open")) { model.send(.showGuide) }
                } label: {
                    Text(L10n.t("使用引导", "Getting started"))
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        Button(L10n.t("导出…", "Export…")) { model.send(.exportConfig) }
                        Button(L10n.t("导入…", "Import…")) { model.send(.importConfig) }
                    }
                } label: {
                    Text(L10n.t("收纳配置", "Layout file"))
                    Text(L10n.t("换电脑或重装时用", "For a new Mac or a reinstall"))
                }
            } header: {
                Text(L10n.t("关于", "About"))
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

/// Shows the shortcut; click it, then press the new combination. Esc
/// cancels, ⌫ clears. The recording itself runs in `BarSettings`.
struct HotKeyField: View {
    let model: SettingsModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.send(.recordHotKey(!model.recordingHotKey))
            } label: {
                Text(model.recordingHotKey ? L10n.t("按下新的快捷键，或连按两下 ⌘…", "Press a shortcut, or ⌘ twice…") : model.hotKeyDisplay)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 120)
            }
            .help(L10n.t("点一下，然后按下新的组合键（需包含 ⌘、⌃ 或 ⌥），或连按两下 ⌘ / ⌥ / ⌃；Esc 取消，⌫ 清除",
                         "Click, then press the new combination (with ⌘, ⌃ or ⌥), or press ⌘, ⌥ or ⌃ twice; Esc cancels, ⌫ clears"))
            .accessibilityLabel(L10n.t("快捷键：\(model.hotKeyDisplay)", "Shortcut: \(model.hotKeyDisplay)"))
            Button {
                model.send(.clearHotKey)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!model.hasHotKey || model.recordingHotKey)
            .help(L10n.t("关闭快捷键", "Turn the shortcut off"))
            .accessibilityLabel(L10n.t("关闭快捷键", "Turn the shortcut off"))
        }
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
            // The first page anyone sees: without the permission there is
            // nothing to list, so it is granted right here.
            if !model.axTrusted {
                Section {
                    PermissionRow(title: L10n.t("设备控制与数据访问", "Device Control and Data Access"),
                                  detail: L10n.t("读取、隐藏和排序菜单栏图标", "Read, hide and reorder menu-bar items"),
                                  granted: model.axTrusted) { model.send(.permission("accessibility")) }
                } header: {
                    Text(L10n.t("需要授权", "Permission needed"))
                }
            }
            // Left of the ••• first: what the strip shows, in its order.
            if !model.hiddenEntries.isEmpty {
                Section {
                    ForEach(model.hiddenEntries) { entry in
                        LayoutRow(entry: entry, model: model)
                    }
                } header: {
                    Text(L10n.t("收纳条：从左到右", "Strip: left to right"))
                }
            }
            Section {
                if model.entries.isEmpty {
                    Text(model.axTrusted
                         ? L10n.t("正在读取菜单栏图标…", "Reading menu-bar items…")
                         : L10n.t("授权后这里会列出菜单栏里的每个图标。", "Once allowed, every menu-bar icon is listed here."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    // Form rows don't honour `onMove`, so rows use drag and drop.
                    ForEach(model.shownEntries) { entry in
                        LayoutRow(entry: entry, model: model)
                    }
                }
            } header: {
                Text(L10n.t("菜单栏：从 ••• 往右，从左到右", "Menu bar: from the ••• rightwards, left to right"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    // What a change just did ("macOS did not accept the
                    // order"…), here where the change was made.
                    if !model.message.isEmpty {
                        Text(model.message)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Text(L10n.t("把一行拖到另一行上即可换到那个位置，也可以右键选择移动。带锁的项目由 macOS 固定位置，但仍可隐藏。「始终隐藏」的项目只在按住 ⌥ 点击 ••• 时出现在收纳条中。",
                                "Drag a row onto another, or right-click it, to reorder. Locked items stay where macOS puts them but can be hidden. Always Hide items appear in the strip only when you ⌥-click •••."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    SegmentedButtons(options: [L10n.t("默认", "Default"), L10n.t("较小", "Smaller"),
                                               L10n.t("小", "Small"), L10n.t("无", "None")],
                                     selection: Binding(
                                        get: { model.value(.iconSpacing) },
                                        set: { model.options[.iconSpacing] = $0; model.send(.spacing($0)) }),
                                     width: 252)
                } label: {
                    Text(L10n.t("图标间隙", "Icon spacing"))
                    Text(L10n.t("写入系统全局偏好，重启电脑后生效", "Writes a global preference; takes effect after a reboot"))
                }
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

    private var targeted: Bool { model.dropTarget == entry.key }

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
                if entry.covered {
                    CoveredTag()
                }
            }
        }
        // The whole row takes a drag or a right-click, not just its text and
        // icon: past a short name ("iFan") the row was dead.
        .contentShape(Rectangle())
        .settingsFrame("row:\(entry.key)", model)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(targeted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
                .padding(.horizontal, -6)
                .padding(.vertical, -4)
        }
        .movable(!entry.pinned, key: entry.key) { LayoutDragPreview(entry: entry) }
        .dropDestination(for: String.self) { keys, _ in
            model.drop(keys.first, on: entry.key)
        } isTargeted: { inside in
            if inside { model.dropTarget = entry.key } else if model.dropTarget == entry.key { model.dropTarget = nil }
        }
        .help(entry.pinned
              ? L10n.t("位置由 macOS 固定，不能移动；仍然可以隐藏", "macOS fixes this item's position; it can still be hidden")
              : "")
        .contextMenu {
            if !entry.pinned, let index = model.entries.firstIndex(where: { $0.key == entry.key }) {
                // Within its group: the strip's rows, or the bar's.
                let first = model.groupStart(of: entry), last = model.groupEnd(of: entry)
                Button(L10n.t("移到最左", "Move to Far Left")) { model.move(from: index, to: first) }
                    .disabled(index <= first)
                Button(L10n.t("左移一位", "Move Left")) { model.move(from: index, to: index - 1) }
                    .disabled(index <= first)
                Button(L10n.t("右移一位", "Move Right")) { model.move(from: index, to: index + 2) }
                    .disabled(index >= last)
                Button(L10n.t("移到最右", "Move to Far Right")) { model.move(from: index, to: last + 1) }
                    .disabled(index >= last)
            }
        }
    }
}

/// A row set to Show that the bar has no room for: macOS moved it into «
/// (or it sits under the notch), so for now it opens from the strip.
struct CoveredTag: View {
    var body: some View {
        Text(L10n.t("放不下", "No room"))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .fixedSize()
            .help(L10n.t("菜单栏太挤，macOS 把它收进了 «。现在可以从收纳条打开它；隐藏几个别的图标，它就会回到菜单栏。",
                         "The menu bar is full, so macOS moved it into «. Open it from the strip for now; hide a few other icons and it comes back."))
            .accessibilityLabel(L10n.t("菜单栏放不下，已在收纳条里", "No room in the menu bar; in the strip for now"))
    }
}

/// What follows the pointer while a row is dragged: the whole row as one
/// card (handle, icon, name, current state) rather than just its icon.
struct LayoutDragPreview: View {
    let entry: BarEntry

    private var state: String {
        [L10n.t("显示", "Show"), L10n.t("隐藏", "Hide"), L10n.t("始终隐藏", "Always Hide")][min(max(entry.mode, 0), 2)]
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Group {
                if let image = entry.image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                }
            }
            .frame(width: 20, height: 20)
            Text(entry.name).lineLimit(1)
            Spacer(minLength: 12)
            Text(state)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(width: 360, height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Show / Hide / Always Hide as three buttons, so a change is one click.
/// Its own view type so `Form` keeps the frame modifier the self-test reads.
struct ModeControl: View {
    let entry: BarEntry
    let model: SettingsModel

    var body: some View {
        SegmentedButtons(options: [L10n.t("显示", "Show"), L10n.t("隐藏", "Hide"), L10n.t("始终隐藏", "Always Hide")],
                         selection: Binding(get: { entry.mode }, set: { model.setMode(entry.key, $0) }),
                         width: 270)
            .accessibilityLabel(entry.name)
            .settingsFrame("mode:\(entry.key)", model)
    }
}

/// Equal-width segments drawn by YoungBar instead of `NSSegmentedControl`:
/// the native control hides the dividers next to the selected segment and
/// sizes segments by their (bold when selected) labels, so rows didn't line
/// up. Here every divider is always drawn and the width never changes.
struct SegmentedButtons: View {
    let options: [String]
    @Binding var selection: Int
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Text(options[index])
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(index == selection ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if index == selection {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.tint)
                                    .padding(2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(options[index])
                .accessibilityAddTraits(index == selection ? .isSelected : [])
                if index < options.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 1, height: 12)
                }
            }
        }
        .frame(width: width, height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.t("外观", "Appearance")) {
                    SegmentedButtons(options: AppearanceMode.allCases.map(\.title),
                                     selection: model.intBinding(.appearanceMode), width: 252)
                }
            }

            Section {
                StripPreview(color: model.theme,
                             opacity: CGFloat(model.stripOpacity) / 100,
                             isDark: colorScheme == .dark)
                    .frame(width: 280, height: 40)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityLabel(L10n.t("收纳条预览", "Strip preview"))
                HStack(alignment: .top) {
                    Text(L10n.t("配色", "Colour"))
                    Spacer()
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(ThemeColor.allCases, id: \.self) { theme in
                            Button { model.set(.themeColor, theme.rawValue) } label: {
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
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(model.stripOpacity) },
                            set: { model.set(.stripOpacity, Int($0.rounded())) }),
                               in: Double(stripOpacityRange.lowerBound)...Double(stripOpacityRange.upperBound))
                            .frame(width: 160)
                        Text("\(model.stripOpacity)%")
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                } label: {
                    Text(L10n.t("收纳条不透明度", "Strip opacity"))
                    Text(L10n.t("100% 为纯色，越低越透出背后的毛玻璃", "100% is solid; lower is more see-through"))
                }
                .disabled(model.stripTintLocked)
            } header: {
                Text(L10n.t("主题", "Theme"))
            } footer: {
                if model.stripTintLocked {
                    Text(L10n.t("「透明」主题的收纳条跟随系统毛玻璃，没有主题色可调。", "The Clear theme uses the system blur only, so there is no colour to adjust."))
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
                            IconTile(selected: model.value(.controlIcon) == index) {
                                model.set(.controlIcon, index)
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
        return IconTile(selected: model.value(.controlIcon) == customIndex) {
            if model.customIcon == nil {
                model.send(.chooseCustomIcon)
            } else {
                model.set(.controlIcon, customIndex)
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 86)
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
    /// Lets a menu-bar row be dragged onto another row; `preview` is what
    /// follows the pointer.
    @ViewBuilder
    func movable<Preview: View>(_ enabled: Bool, key: String,
                                @ViewBuilder preview: @escaping () -> Preview) -> some View {
        if enabled { draggable(key, preview: preview) } else { self }
    }

    /// Records the control's frame so self-tests can click it. Release
    /// builds skip the geometry tracking.
    @ViewBuilder
    func settingsFrame(_ key: String, _ model: SettingsModel) -> some View {
        #if YOUNGBAR_TESTHOOKS
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.frames[key] = $0 }
        #else
        self
        #endif
    }
}
