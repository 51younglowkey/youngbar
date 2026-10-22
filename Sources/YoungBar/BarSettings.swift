// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ServiceManagement

struct BarEntry {
    let key: String
    let name: String
    let image: NSImage?
    let mode: Int
    let pinned: Bool
}

/// Settings window modelled on the iBar Pro preferences layout:
/// a 200 pt sidebar with two sections, and a 660 pt content pane.
@MainActor
final class BarSettings: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var entries: [BarEntry] = []
    var onMode: ((String, Int) -> Void)?
    var onMove: ((String, String) -> Void)?
    var onCapture: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOption: ((String, Int) -> Void)?
    var onLogin: ((Bool) -> Void)?
    var onPermission: ((String) -> Void)?
    var onSpacing: ((Int) -> Void)?
    var onCustomIcon: (() -> Void)?
    var onRemoveCustomIcon: (() -> Void)?

    private let window: NSWindow
    private let glass = NSGlassEffectView()
    private let scrim = NSView()
    private let sidebar = NSVisualEffectView()
    private let sidebarTint = NSView()
    private let generalPage = NSView()
    private let layoutPage = NSView()
    private let appearancePage = NSView()
    private let table = NSTableView()
    private let layoutScroll = NSScrollView()
    private let pasteType = NSPasteboard.PasteboardType("dev.leorea.youngbar.layout")
    private var navButtons: [String: SidebarButton] = [:]
    private var currentPage = "general"

    private let loginCheck = NSButton(checkboxWithTitle: L10n.t("开机自启动", "Launch at login"), target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: [L10n.t("普通模式", "Standard"), L10n.t("聚合模式", "Aggregate")], trackingMode: .selectOne, target: nil, action: nil)
    private let keepCheck = NSButton(checkboxWithTitle: L10n.t("聚合模式下工具条始终显示", "Keep the strip visible in Aggregate mode"), target: nil, action: nil)
    private let hoverCheck = NSButton(checkboxWithTitle: L10n.t("鼠标悬停 0.5 秒展开", "Open on hover (0.5 s)"), target: nil, action: nil)
    private let blankCheck = NSButton(checkboxWithTitle: L10n.t("点击菜单栏空白处展开", "Open when clicking empty menu-bar space"), target: nil, action: nil)
    private let delaySlider = NSSlider(value: 20, minValue: 5, maxValue: 60, target: nil, action: nil)
    private let delayValue = NSTextField(labelWithString: L10n.t("20 秒", "20 s"))
    private let spacingPopup = NSPopUpButton()
    private let axStatus = NSTextField(labelWithString: "")
    private let axButton = NSButton(title: L10n.t("授权…", "Authorize…"), target: nil, action: nil)
    private let captureStatus = NSTextField(labelWithString: "")
    private let captureButton = NSButton(title: L10n.t("授权…", "Authorize…"), target: nil, action: nil)
    private let messageField = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: L10n.t("刷新图标列表", "Refresh item list"), target: nil, action: nil)
    private(set) var refreshClickCount = 0
    private let emptyLabel = NSTextField(labelWithString: "")
    private let appearanceModeControl = NSSegmentedControl(labels: [L10n.t("跟随系统", "System"), L10n.t("浅色", "Light"), L10n.t("深色", "Dark")],
                                                           trackingMode: .selectOne, target: nil, action: nil)
    private let stripStyleControl = NSSegmentedControl(labels: [L10n.t("纯色", "Solid"), L10n.t("半透明", "Translucent"), L10n.t("毛玻璃", "Glass")],
                                                       trackingMode: .selectOne, target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private let scopeControl = NSSegmentedControl(labels: ThemeScope.allCases.map(\.title),
                                                  trackingMode: .selectOne, target: nil, action: nil)
    private let appIconView = NSImageView()
    private var colorButtons: [ThemeSwatchButton] = []
    private let preview = ThemePreviewView()
    private var iconButtons: [NSButton] = []
    private let iconPreview = NSImageView()
    private let customIconButton = NSButton(title: "", target: nil, action: nil)
    private let removeCustomButton = NSButton(title: "", target: nil, action: nil)

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "YoungBar"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false
        window.minSize = NSSize(width: 860, height: 560)
        window.center()
        window.contentView = buildRoot()
        selectPage("general")
    }

    // MARK: - Construction

    private func buildRoot() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 692))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        glass.frame = root.bounds
        glass.autoresizingMask = [.width, .height]
        glass.style = .regular
        glass.cornerRadius = 0
        // The glass view can install interactive gestures; this window only
        // needs it as a background material.
        if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
            glass.setValue(false, forKey: "effectIsInteractive")
        }
        root.addSubview(glass)

        scrim.frame = root.bounds
        scrim.autoresizingMask = [.width, .height]
        scrim.wantsLayer = true
        root.addSubview(scrim)

        sidebar.frame = NSRect(x: 0, y: 0, width: 200, height: 692)
        sidebar.autoresizingMask = [.height]
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.wantsLayer = true
        root.addSubview(sidebar)

        sidebarTint.frame = sidebar.bounds
        sidebarTint.autoresizingMask = [.width, .height]
        sidebarTint.wantsLayer = true
        sidebar.addSubview(sidebarTint, positioned: .below, relativeTo: nil)

        appIconView.frame = NSRect(x: 64, y: 546, width: 72, height: 72)
        appIconView.autoresizingMask = [.minYMargin]
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.wantsLayer = true
        appIconView.layer?.cornerRadius = 16
        appIconView.layer?.masksToBounds = true
        sidebar.addSubview(appIconView)

        let title = label("YoungBar", NSRect(x: 16, y: 512, width: 168, height: 28),
                          .systemFont(ofSize: 21, weight: .semibold))
        title.alignment = .center
        title.autoresizingMask = [.minYMargin]
        sidebar.addSubview(title)
        let subtitle = label("YoungBar 0.1.0", NSRect(x: 16, y: 492, width: 168, height: 16),
                             .systemFont(ofSize: 11))
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        subtitle.autoresizingMask = [.minYMargin]
        sidebar.addSubview(subtitle)

        for (index, item) in [("layout", L10n.t("布局", "Layout"), "list.bullet.rectangle"),
                              ("appearance", L10n.t("外观", "Appearance"), "paintpalette"),
                              ("general", L10n.t("设置", "Settings"), "gearshape")].enumerated() {
            let button = SidebarButton(title: "", target: self, action: #selector(navigate(_:)))
            button.identifier = .init(item.0)
            button.labelText = item.1
            button.symbolName = item.2
            button.frame = NSRect(x: 0, y: 420 - CGFloat(index) * 40, width: 200, height: 36)
            button.isBordered = false
            button.autoresizingMask = [.minYMargin]
            sidebar.addSubview(button)
            navButtons[item.0] = button
        }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 692))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        let scroll = NSScrollView(frame: NSRect(x: 200, y: 0, width: 660, height: 692))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = content
        scroll.autoresizingMask = [.width, .height]
        root.addSubview(scroll)

        generalPage.frame = content.bounds
        layoutPage.frame = content.bounds
        appearancePage.frame = content.bounds
        content.addSubview(generalPage)
        content.addSubview(layoutPage)
        content.addSubview(appearancePage)
        buildGeneralPage()
        buildLayoutPage()
        buildAppearancePage()
        return root
    }

    private func buildGeneralPage() {
        addHeader(to: generalPage, title: L10n.t("设置", "Settings"))

        // Startup
        generalPage.addSubview(sectionLabel(L10n.t("启动", "Startup"), y: 532))
        generalPage.addSubview(card(y: 486, height: 36))
        loginCheck.target = self
        loginCheck.action = #selector(loginChanged)
        loginCheck.frame = NSRect(x: 32, y: 492, width: 300, height: 24)
        generalPage.addSubview(loginCheck)

        let languageLabel = label(L10n.t("语言", "Language"),
                                  NSRect(x: 372, y: 495, width: 62, height: 16),
                                  .systemFont(ofSize: 11, weight: .medium))
        languageLabel.textColor = .secondaryLabelColor
        generalPage.addSubview(languageLabel)
        languagePopup.addItems(withTitles: ["中文", "English"])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        languagePopup.frame = NSRect(x: 438, y: 486, width: 158, height: 28)
        generalPage.addSubview(languagePopup)

        // Display & behaviour
        generalPage.addSubview(sectionLabel(L10n.t("显示与行为", "Display & Behaviour"), y: 456))
        generalPage.addSubview(card(y: 268, height: 168))
        generalPage.addSubview(label(L10n.t("显示模式", "Display mode"),
                                     NSRect(x: 32, y: 424, width: 160, height: 18),
                                     .systemFont(ofSize: 12, weight: .medium)))
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.frame = NSRect(x: 32, y: 394, width: 250, height: 28)
        modeControl.toolTip = L10n.t("聚合模式把收纳项收进一条工具条。",
                                     "Aggregate mode collects concealed items into one strip.")
        generalPage.addSubview(modeControl)

        var y: CGFloat = 362
        for (check, key) in [(keepCheck, "keepShelfOpen"), (hoverCheck, "hoverExpand"), (blankCheck, "blankClick")] {
            check.target = self
            check.action = #selector(optionChanged(_:))
            check.identifier = .init(key)
            check.frame = NSRect(x: 32, y: y, width: 460, height: 24)
            generalPage.addSubview(check)
            y -= 26
        }

        generalPage.addSubview(label(L10n.t("再次自动隐藏", "Auto-hide after"),
                                     NSRect(x: 32, y: 280, width: 120, height: 18),
                                     .systemFont(ofSize: 12, weight: .medium)))
        delaySlider.target = self
        delaySlider.action = #selector(delayChanged)
        delaySlider.isContinuous = true
        delaySlider.frame = NSRect(x: 156, y: 278, width: 270, height: 24)
        delaySlider.toolTip = L10n.t("点击收纳项后，它在菜单栏上保持原生的时长。",
                                     "How long a clicked item stays native on the bar.")
        generalPage.addSubview(delaySlider)
        delayValue.frame = NSRect(x: 436, y: 281, width: 80, height: 18)
        generalPage.addSubview(delayValue)

        // Menu bar
        generalPage.addSubview(sectionLabel(L10n.t("菜单栏", "Menu Bar"), y: 240))
        generalPage.addSubview(card(y: 186, height: 44))
        generalPage.addSubview(label(L10n.t("菜单栏图标间隙", "Menu-bar icon spacing"),
                                     NSRect(x: 32, y: 206, width: 190, height: 18),
                                     .systemFont(ofSize: 12, weight: .medium)))
        spacingPopup.addItems(withTitles: [L10n.t("默认间隙", "Default"), L10n.t("较小间隙", "Smaller"),
                                           L10n.t("小间隙", "Small"), L10n.t("无间隙", "None")])
        spacingPopup.target = self
        spacingPopup.action = #selector(spacingChanged)
        spacingPopup.frame = NSRect(x: 226, y: 200, width: 190, height: 28)
        spacingPopup.toolTip = L10n.t("写入全局偏好，重启电脑后生效。",
                                      "Writes a global preference; takes effect after a reboot.")
        generalPage.addSubview(spacingPopup)

        // Permissions
        generalPage.addSubview(sectionLabel(L10n.t("权限", "Permissions"), y: 164))
        generalPage.addSubview(card(y: 80, height: 74))
        axStatus.frame = NSRect(x: 32, y: 124, width: 360, height: 18)
        axStatus.font = .systemFont(ofSize: 12)
        generalPage.addSubview(axStatus)
        axButton.target = self
        axButton.action = #selector(axTapped)
        axButton.frame = NSRect(x: 306, y: 118, width: 90, height: 30)
        generalPage.addSubview(axButton)

        captureStatus.frame = NSRect(x: 32, y: 88, width: 360, height: 18)
        captureStatus.font = .systemFont(ofSize: 12)
        generalPage.addSubview(captureStatus)
        captureButton.target = self
        captureButton.action = #selector(captureTapped)
        captureButton.frame = NSRect(x: 306, y: 82, width: 90, height: 30)
        generalPage.addSubview(captureButton)

        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.frame = NSRect(x: 32, y: 44, width: 140, height: 30)
        generalPage.addSubview(refreshButton)

        messageField.frame = NSRect(x: 32, y: 18, width: 596, height: 20)
        messageField.textColor = .secondaryLabelColor
        messageField.font = .systemFont(ofSize: 10.5)
        generalPage.addSubview(messageField)

        let version = label(L10n.t("YoungBar 0.1.0 · GPLv3 · 基于 Dimble / Pelmet",
                                   "YoungBar 0.1.0 · GPLv3 · Built on Dimble / Pelmet"),
                            NSRect(x: 32, y: 2, width: 596, height: 14),
                            .systemFont(ofSize: 10))
        version.alignment = .center
        version.textColor = .tertiaryLabelColor
        generalPage.addSubview(version)
    }

    private func sectionLine(y: CGFloat) -> NSBox {
        let line = NSBox(frame: NSRect(x: 32, y: y, width: 596, height: 1))
        line.boxType = .separator
        return line
    }

    private func updateRowHeight() {
        let count = max(1, entries.count)
        let available = layoutScroll.contentSize.height
        let spacing: CGFloat = 4
        let proposed = (available - spacing * CGFloat(count - 1)) / CGFloat(count)
        let height = floor(min(46, max(27, proposed)))
        table.rowHeight = height
        table.intercellSpacing = NSSize(width: 0, height: spacing)
        let total = height * CGFloat(count) + spacing * CGFloat(count - 1)
        layoutScroll.hasVerticalScroller = total > available + 1
        table.sizeToFit()
    }

    private func buildLayoutPage() {
        addHeader(to: layoutPage, title: L10n.t("菜单栏布局", "Layout"), subtitle: L10n.t("拖动行调整从左到右的顺序；勾选决定每一项的可见方式。", "Drag rows to set the left-to-right order; tick how each item should appear."))

        table.rowHeight = 44
        table.style = .plain
        table.headerView = nil
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 6)
        for (id, width) in [("app", 300.0), ("icon", 70.0), ("hide", 90.0), ("always", 110.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([pasteType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        layoutScroll.frame = NSRect(x: 24, y: 84, width: 612, height: 440)
        layoutScroll.hasVerticalScroller = false
        layoutScroll.borderType = .noBorder
        layoutScroll.drawsBackground = false
        layoutScroll.documentView = table
        layoutPage.addSubview(layoutScroll)

        for (title, x) in [(L10n.t("名称", "Name"), 48.0), (L10n.t("图标", "Icon"), 350.0), (L10n.t("隐藏", "Hidden"), 428.0), (L10n.t("始终隐藏", "Always Hidden"), 512.0)] {
            let label = label(title, NSRect(x: x, y: 538, width: 90, height: 16), .systemFont(ofSize: 11, weight: .medium))
            label.textColor = .secondaryLabelColor
            layoutPage.addSubview(label)
        }

        layoutPage.addSubview(hint(L10n.t("拖住任意一行可以调整顺序；始终隐藏项不在普通收纳栏显示，按住 ⌥ 点击 ••• 可访问。", "Drag any row to reorder. Always Hidden items only appear in the strip while holding ⌥."), y: 56))

        emptyLabel.frame = NSRect(x: 44, y: 290, width: 572, height: 40)
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.maximumNumberOfLines = 2
        layoutPage.addSubview(emptyLabel)
    }

    private func buildAppearancePage() {
        addHeader(to: appearancePage, title: L10n.t("外观", "Appearance"))

        appearancePage.addSubview(sectionLabel(L10n.t("外观模式", "Appearance mode"), y: 540))
        appearancePage.addSubview(card(y: 498, height: 36))
        appearanceModeControl.target = self
        appearanceModeControl.action = #selector(appearanceModeChanged)
        appearanceModeControl.frame = NSRect(x: 32, y: 508, width: 300, height: 28)
        appearancePage.addSubview(appearanceModeControl)

        appearancePage.addSubview(sectionLabel(L10n.t("主题色", "Palette"), y: 464))
        appearancePage.addSubview(card(y: 392, height: 66))
        for (index, theme) in ThemeColor.allCases.enumerated() {
            let button = ThemeSwatchButton(title: "", target: self, action: #selector(colorPicked(_:)))
            button.frame = NSRect(x: 32 + CGFloat(index) * 90, y: 424, width: 46, height: 28)
            button.isBordered = false
            button.theme = theme
            button.tag = index
            button.toolTip = theme.title
            button.setAccessibilityLabel(theme.title)
            colorButtons.append(button)
            appearancePage.addSubview(button)
            let name = label(theme.title, NSRect(x: 32 + CGFloat(index) * 90, y: 404, width: 100, height: 16),
                             .systemFont(ofSize: 10.5))
            name.textColor = .secondaryLabelColor
            appearancePage.addSubview(name)
        }

        appearancePage.addSubview(sectionLabel(L10n.t("主题应用", "Theme scope"), y: 368))
        appearancePage.addSubview(card(y: 322, height: 36))
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.frame = NSRect(x: 32, y: 326, width: 360, height: 28)
        appearancePage.addSubview(scopeControl)

        appearancePage.addSubview(sectionLabel(L10n.t("收纳条", "Strip"), y: 292))
        appearancePage.addSubview(card(y: 248, height: 38))
        stripStyleControl.target = self
        stripStyleControl.action = #selector(stripStyleChanged)
        stripStyleControl.frame = NSRect(x: 32, y: 260, width: 300, height: 28)
        appearancePage.addSubview(stripStyleControl)

        appearancePage.addSubview(sectionLabel(L10n.t("菜单栏按钮", "Menu-bar button"), y: 212))
        appearancePage.addSubview(card(y: 116, height: 90))
        for (index, symbol) in ControlIcon.symbols.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(iconPicked(_:)))
            button.frame = NSRect(x: 32 + CGFloat(index) * 54, y: 166, width: 40, height: 40)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: ControlIcon.title(index))
            button.imagePosition = .imageOnly
            button.contentTintColor = .labelColor
            button.tag = index
            button.toolTip = ControlIcon.title(index)
            button.setAccessibilityLabel(ControlIcon.title(index))
            iconButtons.append(button)
            appearancePage.addSubview(button)
        }

        customIconButton.title = L10n.t("自定义图片…", "Custom image…")
        customIconButton.target = self
        customIconButton.action = #selector(customIconTapped)
        customIconButton.frame = NSRect(x: 32, y: 122, width: 150, height: 30)
        appearancePage.addSubview(customIconButton)
        let reset = NSButton(title: L10n.t("恢复默认", "Reset"),
                             target: self, action: #selector(resetIcon))
        reset.frame = NSRect(x: 190, y: 122, width: 100, height: 30)
        appearancePage.addSubview(reset)

        removeCustomButton.title = L10n.t("移除自定义", "Remove custom")
        removeCustomButton.target = self
        removeCustomButton.action = #selector(removeCustomTapped)
        removeCustomButton.frame = NSRect(x: 298, y: 122, width: 120, height: 30)
        appearancePage.addSubview(removeCustomButton)

        appearancePage.addSubview(sectionLabel(L10n.t("预览", "Preview"), y: 92))
        appearancePage.addSubview(card(y: 34, height: 50))
        preview.frame = NSRect(x: 32, y: 44, width: 320, height: 40)
        appearancePage.addSubview(preview)
    }

    @objc private func iconPicked(_ sender: NSButton) {
        onOption?("controlIcon", sender.tag)
    }

    @objc private func customIconTapped() {
        onCustomIcon?()
    }

    @objc private func resetIcon() {
        onOption?("controlIcon", 0)
    }

    @objc private func removeCustomTapped() {
        onRemoveCustomIcon?()
    }

    private func addHeader(to page: NSView, title: String, subtitle: String = "") {
        page.addSubview(label(title, NSRect(x: 32, y: 596, width: 400, height: 32),
                              .systemFont(ofSize: 24, weight: .semibold)))
        if !subtitle.isEmpty { page.addSubview(hint(subtitle, y: 576)) }
        let line = NSBox(frame: NSRect(x: 32, y: 566, width: 596, height: 1))
        line.boxType = .separator
        page.addSubview(line)
    }

    private func card(y: CGFloat, height: CGFloat, x: CGFloat = 24, width: CGFloat = 612) -> NSView {
        let view = NSView(frame: NSRect(x: x, y: y, width: width, height: height))
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        return view
    }

    private func sectionLabel(_ text: String, y: CGFloat) -> NSTextField {
        let field = label(text, NSRect(x: 32, y: y, width: 300, height: 16), .systemFont(ofSize: 11, weight: .semibold))
        field.textColor = .secondaryLabelColor
        return field
    }

    private func label(_ text: String, _ frame: NSRect, _ font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = font
        return field
    }

    private func hint(_ text: String, y: CGFloat) -> NSTextField {
        let field = label(text, NSRect(x: 32, y: y, width: 596, height: 16), .systemFont(ofSize: 11))
        field.textColor = .secondaryLabelColor
        return field
    }

    // MARK: - Actions

    @objc private func navigate(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        selectPage(id)
    }

    private func selectPage(_ id: String) {
        currentPage = id
        generalPage.isHidden = id != "general"
        layoutPage.isHidden = id != "layout"
        appearancePage.isHidden = id != "appearance"
        for (key, button) in navButtons { button.selected = key == id }
        if id == "layout" { table.reloadData() }
    }

    @objc private func loginChanged() {
        onLogin?(loginCheck.state == .on)
    }

    @objc private func modeChanged() {
        onOption?("nativeExpand", modeControl.selectedSegment)
    }

    @objc private func optionChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        onOption?(key, sender.state == .on ? 1 : 0)
    }

    @objc private func spacingChanged() {
        onSpacing?(spacingPopup.indexOfSelectedItem)
    }

    @objc private func delayChanged() {
        let seconds = Int(delaySlider.doubleValue.rounded())
        delayValue.stringValue = L10n.t("\(seconds) 秒", "\(seconds) s")
        onOption?("revealSeconds", seconds)
    }

    @objc private func appearanceModeChanged() {
        onOption?("appearanceMode", appearanceModeControl.selectedSegment)
    }

    @objc private func stripStyleChanged() {
        onOption?("stripStyle", stripStyleControl.selectedSegment)
    }

    @objc private func languageChanged() {
        onOption?("language", languagePopup.indexOfSelectedItem)
    }

    @objc private func scopeChanged() {
        onOption?("themeScope", scopeControl.selectedSegment)
    }

    @objc private func colorPicked(_ sender: NSButton) {
        onOption?("themeColor", sender.tag)
    }

    @objc private func axTapped() { onPermission?("accessibility") }
    @objc private func captureTapped() { onPermission?("screen") }
    @objc private func refreshTapped() {
        refreshClickCount += 1
        onRefresh?()
    }

    // MARK: - State

    var isVisible: Bool { window.isVisible }

    func close() { window.close() }
    var windowForCapture: NSWindow { window }

    func refreshButtonScreenRect() -> NSRect? {
        guard window.isVisible else { return nil }
        return window.convertToScreen(refreshButton.convert(refreshButton.bounds, to: nil))
    }

    /// Diagnostic: what would receive a click on the login checkbox?
    func loginHitTest() -> [String: Any] {
        let rect = loginCheck.convert(loginCheck.bounds, to: nil)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        let local = window.contentView?.convert(point, from: nil) ?? point
        var view = window.contentView?.hitTest(local)
        var chain: [String] = []
        while let current = view {
            chain.append(String(describing: type(of: current)))
            view = current.superview
        }
        return [
            "point": NSStringFromPoint(point),
            "chain": chain,
            "isKey": window.isKeyWindow,
            "ignoresMouse": window.ignoresMouseEvents,
            "isVisible": window.isVisible,
            "contentFrame": NSStringFromRect(window.contentView?.frame ?? .zero),
        ]
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(entries: [BarEntry], message: String, captureAllowed: Bool, axTrusted: Bool,
                launchAtLogin: Bool, controlIcon: NSImage?, controlIconIndex: Int,
                options: [String: Int]) {
        let changed = self.entries.map { "\($0.key):\($0.mode)" } != entries.map { "\($0.key):\($0.mode)" }
        self.entries = entries
        updateRowHeight()
        if changed { table.reloadData() }

        loginCheck.state = launchAtLogin ? .on : .off
        keepCheck.state = options["keepShelfOpen"] == 1 ? .on : .off
        hoverCheck.state = options["hoverExpand"] == 1 ? .on : .off
        blankCheck.state = options["blankClick"] == 1 ? .on : .off
        modeControl.selectedSegment = options["nativeExpand"] ?? 0
        let seconds = options["revealSeconds"] ?? 20
        delaySlider.doubleValue = Double(seconds)
        delayValue.stringValue = L10n.t("\(seconds) 秒", "\(seconds) s")
        spacingPopup.selectItem(at: options["iconSpacing"] ?? 0)

        axStatus.stringValue = axTrusted ? L10n.t("辅助功能：已授权", "Accessibility: granted") : L10n.t("辅助功能：未授权", "Accessibility: not granted")
        axStatus.textColor = axTrusted ? .secondaryLabelColor : .systemOrange
        axButton.title = axTrusted ? L10n.t("设置…", "Settings…") : L10n.t("授权…", "Authorize…")
        captureStatus.stringValue = captureAllowed ? L10n.t("屏幕录制：已授权", "Screen Recording: granted") : L10n.t("屏幕录制：未授权（原始图标不可用）", "Screen Recording: not granted (original icons unavailable)")
        captureButton.title = captureAllowed ? L10n.t("设置…", "Settings…") : L10n.t("授权…", "Authorize…")
        messageField.stringValue = message

        languagePopup.selectItem(at: options["language"] ?? 0)
        appearanceModeControl.selectedSegment = options["appearanceMode"] ?? 0
        stripStyleControl.selectedSegment = options["stripStyle"] ?? 0
        scopeControl.selectedSegment = options["themeScope"] ?? 0
        let theme = ThemeColor(rawValue: options["themeColor"] ?? 0) ?? .blue
        preview.color = theme
        preview.style = StripStyle(rawValue: options["stripStyle"] ?? 0) ?? .solid
        for (index, button) in colorButtons.enumerated() {
            button.selected = index == theme.rawValue
        }
        appIconView.image = themeIcon(theme)
        iconPreview.image = controlIcon
        iconPreview.contentTintColor = controlIconIndex == ControlIcon.symbols.count ? nil : .white
        for (index, button) in iconButtons.enumerated() {
            button.layer?.borderWidth = index == controlIconIndex ? 2 : 0
            button.layer?.borderColor = theme.accent.cgColor
        }
        customIconButton.layer?.borderWidth = controlIconIndex == ControlIcon.symbols.count ? 2 : 0
        customIconButton.layer?.borderColor = theme.accent.cgColor
        removeCustomButton.isEnabled = controlIconIndex == ControlIcon.symbols.count
        let scope = ThemeScope(rawValue: options["themeScope"] ?? 0) ?? .both
        let tintedInterface = scope != .stripOnly
        for button in navButtons.values {
            button.highlightColor = tintedInterface ? theme.accent : .controlAccentColor
        }
        glass.tintColor = tintedInterface ? theme.accent.withAlphaComponent(0.10) : .clear
        window.backgroundColor = .clear
        sidebarTint.layer?.backgroundColor = (tintedInterface
            ? theme.accent.withAlphaComponent(0.08)
            : NSColor.clear).cgColor
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        preview.isDark = isDark
        preview.color = scope == .interfaceOnly ? .clear : theme
        scrim.layer?.backgroundColor = (isDark
            ? NSColor.black.withAlphaComponent(0.46)
            : NSColor.white.withAlphaComponent(0.58)).cgColor
        emptyLabel.isHidden = !entries.isEmpty
        emptyLabel.stringValue = axTrusted ? L10n.t("正在读取菜单栏图标…", "Reading menu-bar items…") : L10n.t("需要辅助功能权限后才能读取菜单栏项目。", "Accessibility permission is required to read menu-bar items.") 
    }

    /// Renders the settings window to PNG without Screen Recording permission.
    /// Used by the agent's `YOUNGBAR_SNAPSHOT_DIR` live check.
    func writeSnapshots(to directory: String) {
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for page in ["general", "layout", "appearance"] {
            selectPage(page)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: base.appendingPathComponent("\(page).png"))
        }
        selectPage("general")
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LayoutRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch column?.identifier.rawValue {
        case "icon":
            let rowHeight = tableView.rowHeight
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 70, height: rowHeight))
            let image = NSImageView(frame: NSRect(x: 24, y: (rowHeight - 22) / 2, width: 22, height: 22))
            image.image = entry.image
            image.imageScaling = .scaleProportionallyDown
            view.addSubview(image)
            return view
        case "hide", "always":
            let isHide = column?.identifier.rawValue == "hide"
            let mode = isHide ? 1 : 2
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(rowModeChanged(_:)))
            button.frame = NSRect(x: isHide ? 34 : 44, y: (tableView.rowHeight - 18) / 2, width: 18, height: 18)
            button.identifier = .init("\(entry.key)|\(mode)")
            button.state = entry.mode == mode ? .on : .off
            let view = NSView(frame: NSRect(x: 0, y: 0, width: column?.width ?? 70, height: tableView.rowHeight))
            view.addSubview(button)
            return view
        default:
            let rowHeight = tableView.rowHeight
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: rowHeight))
            let handle = NSImageView(frame: NSRect(x: 14, y: (rowHeight - 14) / 2, width: 14, height: 14))
            handle.image = NSImage(systemSymbolName: entry.pinned ? "lock.fill" : "line.3.horizontal",
                                   accessibilityDescription: nil)
            handle.contentTintColor = entry.pinned ? .secondaryLabelColor : .tertiaryLabelColor
            handle.imageScaling = .scaleProportionallyDown
            view.addSubview(handle)
            let label = NSTextField(labelWithString: entry.name)
            label.frame = NSRect(x: 38, y: (rowHeight - 20) / 2, width: 254, height: 20)
            label.lineBreakMode = .byTruncatingTail
            if entry.pinned {
                label.toolTip = L10n.t("位置由 macOS 固定在菜单栏最右端，不能拖动；隐藏仍然可用", "macOS fixes this item's position; it cannot be dragged, but it can be hidden.")
            }
            view.addSubview(label)
            return view
        }
    }

    @objc private func rowModeChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let mode = Int(parts[1]) else { return }
        onMode?(parts[0], sender.state == .on ? mode : 0)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard !entries[row].pinned else { return nil }
        let item = NSPasteboardItem()
        item.setString(entries[row].key, forType: pasteType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === table else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let key = info.draggingPasteboard.string(forType: pasteType),
              let from = entries.firstIndex(where: { $0.key == key }), !entries[from].pinned else { return false }
        var changed = entries
        let moved = changed.remove(at: from)
        let destination = min(changed.count, max(0, row > from ? row - 1 : row))
        changed.insert(moved, at: destination)
        let next = destination + 1 < changed.count ? changed[destination + 1].key : ""
        entries = changed
        table.reloadData()
        onMove?(key, next)
        return true
    }
}

final class LayoutRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Rows are controls, not a selection list.
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 6, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
    }
}

@MainActor
final class SidebarButton: NSButton {
    var selected = false {
        didSet { needsDisplay = true }
    }
    var highlightColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }
    var symbolName = "" {
        didSet { needsDisplay = true }
    }
    var labelText = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            highlightColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 8, yRadius: 8).fill()
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
            let tint = selected ? NSColor.labelColor : NSColor.secondaryLabelColor
            let icon = tintedImage(image, color: tint)
            icon.draw(in: NSRect(x: 22, y: (bounds.height - 16) / 2, width: 16, height: 16),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        (labelText as NSString).draw(at: NSPoint(x: 46, y: (bounds.height - 17) / 2),
                                     withAttributes: attributes)
    }
}
