// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import PelmetCore
import PelmetEngine
import YoungBarCore

/// Writes a machine-readable snapshot of the running app when the
/// `YOUNGBAR_DIAGNOSTICS=1` environment variable is set. The window server
/// denies screenshots to the agent shell, so this file is the evidence path
/// for "what does the app actually see" during live validation.
enum Diagnostics {
    struct Item: Codable {
        let key: String
        let name: String
        let x: Double?
        let y: Double?
        let width: Double?
        let height: Double?
        /// Where the owning app's own status item says it is (AX), even
        /// while concealed: an in-place press opens its menu under this.
        let axX: Double?
        let mode: Int
    }

    struct Payload: Codable {
        let at: String
        let axTrusted: Bool
        let assessmentAvailable: Bool
        let launched: Bool
        let itemCount: Int
        let concealedCount: Int
        let concealed: [String]
        let expanded: Bool
        let feedback: String
        let items: [Item]
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["YOUNGBAR_DIAGNOSTICS"] == "1"
    }

    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YoungBar", isDirectory: true)
            .appendingPathComponent("diagnostics.json")
    }

    @MainActor
    static func write(app: BarApp, snapshot: EngineSnapshot?) {
        guard isEnabled else { return }
        let entries = app.diagnosticsItems(snapshot: snapshot)
        let payload = Payload(
            at: ISO8601DateFormatter().string(from: Date()),
            axTrusted: AXIsProcessTrusted(),
            assessmentAvailable: AssessmentMode.isAvailable,
            launched: app.diagnosticsStarted,
            itemCount: entries.count,
            concealedCount: snapshot?.concealed.count ?? 0,
            concealed: snapshot?.concealed.map { $0.sectionKey.rawValue }.sorted() ?? [],
            expanded: app.diagnosticsExpanded,
            feedback: app.diagnosticsFeedback,
            items: entries
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: url, options: .atomic)
        } catch {
            NSLog("YoungBar diagnostics write failed: \(error)")
        }
    }
}

/// "Copy Diagnostics": a plain-text report a user can paste into a comment or
/// chat when something looks wrong. Versions, the displays, the shortcut, where
/// the control and YoungBar's own item sit, each icon's state by name, whether
/// the ••• is where it should be, and the flight recorder's newest lines.
/// Nothing leaves the Mac unless the user pastes it.
extension BarApp {
    /// Enough to see how it came to this, and short enough to paste. The whole
    /// log is `events.log`, one button away in the alert.
    static let reportEventLines = 60
    static let issueFormURL = URL(string: "https://github.com/51younglowkey/youngbar/issues/new?template=bug_report.yml")!

    @objc func copyDiagnostics() {
        Task {
            let summary = await diagnosticsSummary()
            let text = summary + diagnosticsEvents()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            flight.flush()
            // The alert is modal. Run from inside this task it would hold the
            // main actor, so no other task ran until OK: an item opened from
            // the strip stayed on the bar, refreshes stopped. From the run
            // loop, they go on.
            perform(#selector(showDiagnosticsAlert(_:)), with: summary as NSString, afterDelay: 0)
        }
    }

    /// Shows the summary: the event lines would make the alert taller than
    /// the screen. They are in what was copied.
    @objc func showDiagnosticsAlert(_ text: NSString) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.t("诊断信息已复制", "Diagnostics copied")
        alert.informativeText = L10n.t(
            "可以直接粘贴到评论区、群里或 GitHub。除了下面这些，还带了最近的事件记录（图标名称、位置和屏幕变化，不含窗口内容）。",
            "Paste it into a comment, a chat or GitHub. Besides what's below, it has the latest events (icon names, positions and display changes, nothing from your windows).")
            + "\n\n" + (text as String)
        alert.addButton(withTitle: L10n.t("好", "OK"))
        alert.addButton(withTitle: L10n.t("在访达中显示日志", "Show Log in Finder"))
        alert.addButton(withTitle: L10n.t("去 GitHub 反馈", "Report on GitHub"))
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([FlightRecorder.url])
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(Self.issueFormURL)
        default:
            break
        }
    }

    nonisolated static func sysctl(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname(name, &value, &size, nil, 0)
        return String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func diagnosticsReport() async -> String {
        await diagnosticsSummary() + diagnosticsEvents()
    }

    func diagnosticsEvents() -> String {
        let lines = flight.recent(Self.reportEventLines)
        return "\n\n" + L10n.t("最近事件", "Recent events") + " (\(lines.count)):\n" + lines.joined(separator: "\n")
    }

    /// Where the ••• is against where it should be, right now.
    func controlCheck(_ snapshot: EngineSnapshot) -> ControlCheck? {
        guard let panel = controlPanel, let screen = panel.screen ?? NSScreen.screens.first else { return nil }
        // With a full bar the ••• sits in the « pile, not beside the first icon.
        let own = snapshot.items.first { $0.id.bundleID == Bundle.main.bundleIdentifier }?.id.sectionKey.rawValue
        let inPile = own.map { outOfSightKeys(snapshot).contains($0) } ?? false
        let icon = inPile ? nil : leadingIcon(in: snapshot, on: screen).map { Double($0.frame.minX) }
        return ControlCheck.evaluate(control: panel.frame, screens: NSScreen.screens.map(\.frame),
                                     barMinY: Double(screen.frame.maxY - menuBarHeight(of: screen)),
                                     barMaxY: Double(screen.frame.maxY), leadingIconX: icon)
    }

    func diagnosticsSummary() async -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        // Numbers, not the localized "版本 27.0.1（版号 …）".
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion) (\(Self.sysctl("kern.osversion")))"
        let modelName = Self.sysctl("hw.model")

        let snapshot = await engine.freshSnapshot()
        let hiding = await engine.holdsAssertion
        let screen = controlPanel?.screen ?? NSScreen.screens.first
        let screenText = screen.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "?"
        let ownX = snapshot.items.first { $0.id.bundleID == Bundle.main.bundleIdentifier }?.frame.map { "x\(Int($0.minX))" } ?? "-"
        let control = controlPanel.map { "x\(Int($0.frame.minX)) w\(Int($0.frame.width))" } ?? "-"
        let yes = "✓", no = "✗"
        // Which source the ••• goes by, and what the window server says now.
        let barSpace = MenuBarLook.space(on: controlPanel?.screen)
        let barTheme = barSpace.flatMap { MenuBarLook.rawTheme(space: $0) }.map(String.init) ?? "-"
        let barLook = "\(menuBarThemeTrusted ? "theme" : "button") \(barTheme)"

        let frames = Dictionary(snapshot.items.compactMap { item in item.frame.map { (item.id.sectionKey.rawValue, $0) } },
                                uniquingKeysWith: { first, _ in first })
        func list(_ keys: [String], positions: Bool = false) -> String {
            keys.map { key in
                guard positions, let frame = frames[key] else { return name(for: key) }
                return "\(name(for: key)) x\(Int(frame.minX))"
            }.joined(separator: ", ")
        }
        let keys = orderedKeys()
        let shown = keys.filter { (modes[$0] ?? 0) == 0 && !overflowKeys.contains($0) }
        let hidden = keys.filter { modes[$0] == 1 }
        let always = keys.filter { modes[$0] == 2 }
        let covered = keys.filter { overflowKeys.contains($0) }
        let mark: (Bool) -> String = { $0 ? yes : no }
        var checkText = "-"
        if let check = controlCheck(snapshot) {
            let gap = check.gapToIcon.map { " (\(Int($0)))" } ?? ""
            checkText = L10n.t("在屏幕上", "On screen") + " \(mark(check.onScreen)) · "
                + L10n.t("在菜单栏内", "In the bar") + " \(mark(check.inBar)) · "
                + L10n.t("贴着图标", "Beside icons") + " \(check.besideIcons.map(mark) ?? "-")\(gap)"
        }
        let crashes = recentCrashTimes()
        return """
        YoungBar \(version) · macOS \(os) · \(modelName)
        \(L10n.t("屏幕", "Displays")) \(NSScreen.screens.count) · \(screenText) · \(L10n.t("刘海", "Notch")) \(notchVisibleMinX != nil ? yes : no)
        \(L10n.t("屏幕排列", "Layout")) \(screenLayoutText)
        ••• \(checkText) · \(L10n.t("10 分钟内大幅移动", "Jumps in 10 min")) \(flight.recentJumps)
        \(L10n.t("近 30 天崩溃", "Crashes in 30 days")) (\(crashes.count))\(crashes.isEmpty ? "" : ": " + crashes.prefix(3).joined(separator: ", "))
        \(L10n.t("权限", "Permission")) \(AXIsProcessTrusted() ? yes : no) · \(L10n.t("原生隐藏", "Native hiding")) \(AssessmentMode.isAvailable ? yes : no) · \(L10n.t("正在隐藏", "Hiding")) \(hiding ? yes : no)
        \(L10n.t("快捷键", "Shortcut")) \(hotKeyDisplay) · \(L10n.t("控件", "Control")) \(control) · \(L10n.t("占位", "Own item")) \(ownX) · \(L10n.t("菜单栏外观", "Bar look")) \(barLook)
        \(L10n.t("显示", "Shown")) (\(shown.count)): \(list(shown, positions: true))
        \(L10n.t("隐藏", "Hidden")) (\(hidden.count)): \(list(hidden))
        \(L10n.t("始终隐藏", "Always hidden")) (\(always.count)): \(list(always))
        \(L10n.t("被 « 收走", "In macOS «")) (\(covered.count)): \(list(covered))
        """
    }
}

extension BarApp {
    // Read-only accessors for the opt-in diagnostics snapshot.
    var diagnosticsStarted: Bool { started }
    var diagnosticsExpanded: Bool { expanded }
    var diagnosticsFeedback: String { feedback }

    func diagnosticsItems(snapshot: EngineSnapshot?) -> [Diagnostics.Item] {
        orderedKeys().map { key in
            // Only the live snapshot has a trustworthy frame: catalog entries
            // keep the last seen frame even after an item is concealed.
            let frame = snapshot?.items.first { $0.id.sectionKey.rawValue == key }?.frame
            return Diagnostics.Item(
                key: key,
                name: name(for: key),
                x: frame.map { Double($0.minX) },
                y: frame.map { Double($0.minY) },
                width: frame.map { Double($0.width) },
                height: frame.map { Double($0.height) },
                axX: axPosition(for: key).map { Double($0.x) },
                mode: modes[key] ?? 0
            )
        }
    }
}
