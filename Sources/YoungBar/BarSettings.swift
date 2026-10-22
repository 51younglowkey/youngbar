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

    private let window: NSWindow
    private let glass = NSGlassEffectView()
    private let scrim = NSView()
    private let sidebar = NSVisualEffectView()
    private let sidebarTint = NSView()
    private let generalPage = NSView()
    private let layoutPage = NSView()
    private let appearancePage = NSView()
    private let table = NSTableView()
    private let pasteType = NSPasteboard.PasteboardType("dev.leorea.youngbar.layout")
    private var navButtons: [String: SidebarButton] = [:]
    private var currentPage = "general"

    private let loginCheck = NSButton(checkboxWithTitle: "开机自启动", target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: ["普通模式", "聚合模式"], trackingMode: .selectOne, target: nil, action: nil)
    private let keepCheck = NSButton(checkboxWithTitle: "聚合模式下工具条始终显示", target: nil, action: nil)
    private let hoverCheck = NSButton(checkboxWithTitle: "鼠标悬停 0.5 秒展开", target: nil, action: nil)
    private let blankCheck = NSButton(checkboxWithTitle: "点击菜单栏空白处展开", target: nil, action: nil)
    private let delaySlider = NSSlider(value: 20, minValue: 5, maxValue: 60, target: nil, action: nil)
    private let delayValue = NSTextField(labelWithString: "20 秒")
    private let spacingPopup = NSPopUpButton()
    private let axStatus = NSTextField(labelWithString: "")
    private let axButton = NSButton(title: "授权…", target: nil, action: nil)
    private let captureStatus = NSTextField(labelWithString: "")
    private let captureButton = NSButton(title: "授权…", target: nil, action: nil)
    private let messageField = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "刷新图标列表", target: nil, action: nil)
    private(set) var refreshClickCount = 0
    private let emptyLabel = NSTextField(labelWithString: "")
    private let appearanceModeControl = NSSegmentedControl(labels: ["跟随系统", "浅色", "深色"],
                                                           trackingMode: .selectOne, target: nil, action: nil)
    private let stripStyleControl = NSSegmentedControl(labels: ["纯色", "半透明", "毛玻璃"],
                                                       trackingMode: .selectOne, target: nil, action: nil)
    private var colorButtons: [NSButton] = []
    private let preview = ThemePreviewView()

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "YoungBar"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false
        window.center()
        window.contentView = buildRoot()
        selectPage("general")
    }

    // MARK: - Construction

    private func buildRoot() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 660))
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

        sidebar.frame = NSRect(x: 0, y: 0, width: 200, height: 660)
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.wantsLayer = true
        root.addSubview(sidebar)

        sidebarTint.frame = sidebar.bounds
        sidebarTint.autoresizingMask = [.width, .height]
        sidebarTint.wantsLayer = true
        sidebar.addSubview(sidebarTint, positioned: .below, relativeTo: nil)

        let icon = NSImageView(frame: NSRect(x: 64, y: 546, width: 72, height: 72))
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        icon.image = iconURL.flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        sidebar.addSubview(icon)

        let title = label("YoungBar", NSRect(x: 16, y: 512, width: 168, height: 28),
                          .systemFont(ofSize: 21, weight: .semibold))
        title.alignment = .center
        sidebar.addSubview(title)
        let subtitle = label("YoungBar 0.3.0", NSRect(x: 16, y: 492, width: 168, height: 16),
                             .systemFont(ofSize: 11))
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        sidebar.addSubview(subtitle)

        for (index, item) in [("general", "通用设置", "gearshape"),
                              ("layout", "菜单栏布局", "list.bullet.rectangle"),
                              ("appearance", "外观", "paintpalette")].enumerated() {
            let button = SidebarButton(title: item.1, target: self, action: #selector(navigate(_:)))
            button.identifier = .init(item.0)
            button.frame = NSRect(x: 20, y: 420 - CGFloat(index) * 40, width: 168, height: 36)
            button.image = NSImage(systemSymbolName: item.2, accessibilityDescription: nil)
            button.image?.size = NSSize(width: 17, height: 17)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.isBordered = false
            button.contentTintColor = .labelColor
            sidebar.addSubview(button)
            navButtons[item.0] = button
        }

        let footer = label("v0.3.0 · GPLv3\n基于 Dimble / Pelmet", NSRect(x: 16, y: 24, width: 168, height: 40),
                           .systemFont(ofSize: 10))
        footer.textColor = .tertiaryLabelColor
        footer.maximumNumberOfLines = 2
        sidebar.addSubview(footer)

        let content = NSView(frame: NSRect(x: 200, y: 0, width: 660, height: 660))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(content)

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
        addHeader(to: generalPage, title: "通用设置", subtitle: "控制 YoungBar 如何显示、展开与自动收起。")

        generalPage.addSubview(sectionLabel("启动与显示", y: 520))

        loginCheck.target = self
        loginCheck.action = #selector(loginChanged)
        loginCheck.frame = NSRect(x: 32, y: 492, width: 300, height: 24)
        generalPage.addSubview(loginCheck)
        generalPage.addSubview(hint("登录后自动启动 YoungBar。", y: 476))

        generalPage.addSubview(label("显示模式", NSRect(x: 32, y: 446, width: 200, height: 18), .systemFont(ofSize: 12, weight: .medium)))
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.frame = NSRect(x: 32, y: 414, width: 250, height: 28)
        generalPage.addSubview(modeControl)
        generalPage.addSubview(hint("聚合模式把收纳项放进一条工具条；普通模式直接展开原生菜单栏。", y: 400))

        var y: CGFloat = 374
        for (check, key) in [(keepCheck, "keepShelfOpen"), (hoverCheck, "hoverExpand"), (blankCheck, "blankClick")] {
            check.target = self
            check.action = #selector(optionChanged(_:))
            check.identifier = .init(key)
            check.frame = NSRect(x: 32, y: y, width: 460, height: 24)
            generalPage.addSubview(check)
            y -= 26
        }

        generalPage.addSubview(label("再次自动隐藏", NSRect(x: 32, y: 296, width: 110, height: 18), .systemFont(ofSize: 12, weight: .medium)))
        delaySlider.target = self
        delaySlider.action = #selector(delayChanged)
        delaySlider.isContinuous = true
        delaySlider.frame = NSRect(x: 146, y: 294, width: 280, height: 24)
        generalPage.addSubview(delaySlider)
        delayValue.frame = NSRect(x: 436, y: 297, width: 80, height: 18)
        generalPage.addSubview(delayValue)
        generalPage.addSubview(hint("点击收纳项后，它在菜单栏上保持原生的时长（5–60 秒，对齐 iBar 的滑杆）。", y: 278))

        generalPage.addSubview(label("菜单栏图标间隙", NSRect(x: 32, y: 248, width: 130, height: 18), .systemFont(ofSize: 12, weight: .medium)))
        spacingPopup.addItems(withTitles: ["默认间隙", "较小间隙", "小间隙", "无间隙"])
        spacingPopup.target = self
        spacingPopup.action = #selector(spacingChanged)
        spacingPopup.frame = NSRect(x: 166, y: 242, width: 200, height: 28)
        generalPage.addSubview(spacingPopup)
        generalPage.addSubview(hint("写入系统全局偏好，重启电脑后生效；随时可以改回默认。", y: 222))

        generalPage.addSubview(sectionLabel("权限", y: 186))

        axStatus.frame = NSRect(x: 32, y: 159, width: 260, height: 18)
        axStatus.font = .systemFont(ofSize: 12)
        generalPage.addSubview(axStatus)
        axButton.target = self
        axButton.action = #selector(axTapped)
        axButton.frame = NSRect(x: 306, y: 152, width: 90, height: 30)
        generalPage.addSubview(axButton)

        captureStatus.frame = NSRect(x: 32, y: 123, width: 360, height: 18)
        captureStatus.font = .systemFont(ofSize: 12)
        generalPage.addSubview(captureStatus)
        captureButton.target = self
        captureButton.action = #selector(captureTapped)
        captureButton.frame = NSRect(x: 306, y: 116, width: 90, height: 30)
        generalPage.addSubview(captureButton)

        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.frame = NSRect(x: 32, y: 76, width: 140, height: 30)
        generalPage.addSubview(refreshButton)

        messageField.frame = NSRect(x: 32, y: 34, width: 596, height: 34)
        messageField.textColor = .secondaryLabelColor
        messageField.font = .systemFont(ofSize: 11)
        messageField.maximumNumberOfLines = 2
        generalPage.addSubview(messageField)
    }

    private func buildLayoutPage() {
        addHeader(to: layoutPage, title: "菜单栏布局", subtitle: "拖动行调整从左到右的顺序；勾选决定每一项的可见方式。")

        table.rowHeight = 40
        table.style = .plain
        table.headerView = NSTableHeaderView()
        table.allowsMultipleSelection = false
        for (id, title, width) in [("app", "名称", 296.0), ("icon", "图标", 76.0), ("hide", "隐藏", 70.0), ("always", "始终隐藏", 100.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([pasteType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 84, width: 612, height: 446))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        layoutPage.addSubview(scroll)

        layoutPage.addSubview(hint("始终隐藏项不出现在普通收纳栏；按住 ⌥ 点击 ••• 可访问。日期和控制中心位置固定、不能拖动，但可以隐藏。", y: 56))

        emptyLabel.frame = NSRect(x: 44, y: 290, width: 572, height: 40)
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.maximumNumberOfLines = 2
        layoutPage.addSubview(emptyLabel)
    }

    private func buildAppearancePage() {
        addHeader(to: appearancePage, title: "外观", subtitle: "颜色、深浅模式与收纳条材质。")

        appearancePage.addSubview(sectionLabel("外观模式", y: 520))
        appearanceModeControl.target = self
        appearanceModeControl.action = #selector(appearanceModeChanged)
        appearanceModeControl.frame = NSRect(x: 32, y: 486, width: 300, height: 28)
        appearancePage.addSubview(appearanceModeControl)
        appearancePage.addSubview(hint("跟随系统会随 macOS 的浅色/深色切换。", y: 468))

        appearancePage.addSubview(sectionLabel("主题色", y: 430))
        for (index, theme) in ThemeColor.allCases.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(colorPicked(_:)))
            button.frame = NSRect(x: 32 + CGFloat(index) * 62, y: 390, width: 46, height: 26)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = theme.accent.cgColor
            button.layer?.cornerRadius = 7
            button.tag = index
            button.toolTip = theme.title
            button.setAccessibilityLabel(theme.title)
            colorButtons.append(button)
            appearancePage.addSubview(button)
            let name = label(theme.title, NSRect(x: 32 + CGFloat(index) * 62, y: 370, width: 46, height: 16),
                             .systemFont(ofSize: 11))
            name.alignment = .center
            name.textColor = .secondaryLabelColor
            appearancePage.addSubview(name)
        }

        appearancePage.addSubview(sectionLabel("收纳条", y: 326))
        stripStyleControl.target = self
        stripStyleControl.action = #selector(stripStyleChanged)
        stripStyleControl.frame = NSRect(x: 32, y: 292, width: 300, height: 28)
        appearancePage.addSubview(stripStyleControl)
        appearancePage.addSubview(hint("毛玻璃会透出桌面内容；纯色最稳，半透明介于两者之间。", y: 274))

        appearancePage.addSubview(sectionLabel("预览", y: 236))
        preview.frame = NSRect(x: 32, y: 180, width: 360, height: 46)
        appearancePage.addSubview(preview)
        appearancePage.addSubview(hint("预览使用当前主题与收纳条样式。", y: 158))
    }

    private func addHeader(to page: NSView, title: String, subtitle: String) {
        page.addSubview(label(title, NSRect(x: 32, y: 596, width: 400, height: 32),
                              .systemFont(ofSize: 24, weight: .semibold)))
        page.addSubview(hint(subtitle, y: 576))
        let line = NSBox(frame: NSRect(x: 32, y: 566, width: 596, height: 1))
        line.boxType = .separator
        page.addSubview(line)
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
        delayValue.stringValue = "\(seconds) 秒"
        onOption?("revealSeconds", seconds)
    }

    @objc private func appearanceModeChanged() {
        onOption?("appearanceMode", appearanceModeControl.selectedSegment)
    }

    @objc private func stripStyleChanged() {
        onOption?("stripStyle", stripStyleControl.selectedSegment)
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
                launchAtLogin: Bool, options: [String: Int]) {
        let changed = self.entries.map { "\($0.key):\($0.mode)" } != entries.map { "\($0.key):\($0.mode)" }
        self.entries = entries
        if changed { table.reloadData() }

        loginCheck.state = launchAtLogin ? .on : .off
        keepCheck.state = options["keepShelfOpen"] == 1 ? .on : .off
        hoverCheck.state = options["hoverExpand"] == 1 ? .on : .off
        blankCheck.state = options["blankClick"] == 1 ? .on : .off
        modeControl.selectedSegment = options["nativeExpand"] ?? 0
        let seconds = options["revealSeconds"] ?? 20
        delaySlider.doubleValue = Double(seconds)
        delayValue.stringValue = "\(seconds) 秒"
        spacingPopup.selectItem(at: options["iconSpacing"] ?? 0)

        axStatus.stringValue = axTrusted ? "辅助功能：已授权" : "辅助功能：未授权"
        axStatus.textColor = axTrusted ? .secondaryLabelColor : .systemOrange
        axButton.title = axTrusted ? "设置…" : "授权…"
        captureStatus.stringValue = captureAllowed ? "屏幕录制：已授权" : "屏幕录制：未授权（原始图标不可用）"
        captureButton.title = captureAllowed ? "设置…" : "授权…"
        messageField.stringValue = message

        appearanceModeControl.selectedSegment = options["appearanceMode"] ?? 0
        stripStyleControl.selectedSegment = options["stripStyle"] ?? 0
        let theme = ThemeColor(rawValue: options["themeColor"] ?? 0) ?? .forest
        preview.color = theme
        preview.style = StripStyle(rawValue: options["stripStyle"] ?? 0) ?? .solid
        for (index, button) in colorButtons.enumerated() {
            button.layer?.borderWidth = index == theme.rawValue ? 2 : 0
            button.layer?.borderColor = NSColor.labelColor.cgColor
        }
        for button in navButtons.values { button.highlightColor = theme.accent }
        glass.tintColor = theme.accent.withAlphaComponent(0.10)
        window.backgroundColor = theme.strip.withAlphaComponent(0.92)
        sidebarTint.layer?.backgroundColor = theme.accent.withAlphaComponent(0.08).cgColor
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        scrim.layer?.backgroundColor = (isDark
            ? NSColor.black.withAlphaComponent(0.46)
            : NSColor.white.withAlphaComponent(0.58)).cgColor
        emptyLabel.isHidden = !entries.isEmpty
        emptyLabel.stringValue = axTrusted ? "正在读取菜单栏图标…" : "需要辅助功能权限后才能读取菜单栏项目。" 
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

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch column?.identifier.rawValue {
        case "icon":
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 40))
            let image = NSImageView(frame: NSRect(x: 26, y: 8, width: 24, height: 24))
            image.image = entry.image
            image.imageScaling = .scaleProportionallyDown
            view.addSubview(image)
            return view
        case "hide", "always":
            let isHide = column?.identifier.rawValue == "hide"
            let mode = isHide ? 1 : 2
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(rowModeChanged(_:)))
            button.frame = NSRect(x: isHide ? 24 : 36, y: 10, width: 20, height: 20)
            button.identifier = .init("\(entry.key)|\(mode)")
            button.state = entry.mode == mode ? .on : .off
            let view = NSView(frame: NSRect(x: 0, y: 0, width: column?.width ?? 70, height: 40))
            view.addSubview(button)
            return view
        default:
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 40))
            let handle = NSTextField(labelWithString: entry.pinned ? "🔒" : "↕")
            handle.frame = NSRect(x: 8, y: 11, width: 18, height: 18)
            handle.textColor = .tertiaryLabelColor
            view.addSubview(handle)
            let label = NSTextField(labelWithString: entry.name)
            label.frame = NSRect(x: 30, y: 10, width: 256, height: 20)
            label.lineBreakMode = .byTruncatingTail
            if entry.pinned {
                label.toolTip = "位置由 macOS 固定在菜单栏最右端，不能拖动；隐藏仍然可用"
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

@MainActor
final class SidebarButton: NSButton {
    var selected = false {
        didSet { needsDisplay = true }
    }
    var highlightColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            highlightColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}
