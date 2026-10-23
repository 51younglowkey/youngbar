// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
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
