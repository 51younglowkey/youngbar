// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import PelmetCore
import PelmetEngine

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

/// "Copy Diagnostics": a short plain-text report a user can paste into a
/// comment or chat when something looks wrong. Versions, the display, the
/// shortcut, where the control and YoungBar's own item sit, and each icon's
/// state by name. Nothing leaves the Mac unless the user pastes it.
extension BarApp {
    @objc func copyDiagnostics() {
        Task {
            let text = await diagnosticsReport()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.t("诊断信息已复制", "Diagnostics copied")
            alert.informativeText = L10n.t("可以直接粘贴到评论区或群里。内容如下：", "Paste it into a comment or chat. It reads:")
                + "\n\n" + text
            alert.addButton(withTitle: L10n.t("好", "OK"))
            alert.runModal()
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
        return """
        YoungBar \(version) · macOS \(os) · \(modelName)
        \(L10n.t("屏幕", "Displays")) \(NSScreen.screens.count) · \(screenText) · \(L10n.t("刘海", "Notch")) \(notchVisibleMinX != nil ? yes : no)
        \(L10n.t("权限", "Permission")) \(AXIsProcessTrusted() ? yes : no) · \(L10n.t("原生隐藏", "Native hiding")) \(AssessmentMode.isAvailable ? yes : no) · \(L10n.t("正在隐藏", "Hiding")) \(hiding ? yes : no)
        \(L10n.t("快捷键", "Shortcut")) \(hotKeyDisplay) · \(L10n.t("控件", "Control")) \(control) · \(L10n.t("占位", "Own item")) \(ownX)
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
