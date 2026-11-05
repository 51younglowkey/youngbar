// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import PelmetCore
import PelmetEngine
import YoungBarCore

/// Keeps what happened on this Mac in `events.log`, so a bug that only shows on
/// someone else's setup comes with its history: every move of the •••, and
/// what changed around it. The lines are for reading a report, so English only.
/// "Copy Diagnostics" puts the newest lines in the text the user pastes.
@MainActor
final class FlightRecorder {
    private var log = EventLog()
    private var isStarted = false
    private var writeScheduled = false
    private let stampFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "MM-dd HH:mm:ss"
        return format
    }()

    /// Where the ••• was last seen, and until when a move is YoungBar's own.
    /// A move outside that came from macOS (or something else).
    var controlFrame: NSRect?
    var ownMoveUntil = Date.distantPast
    private(set) var jumps: [Date] = []
    var lastTrust: Bool?
    var hadIconToFollow = true

    static var url: URL {
        Diagnostics.url.deletingLastPathComponent().appendingPathComponent("events.log")
    }

    /// Not for a settings preview: that runs beside the live app and shares
    /// its file.
    func start() {
        let saved = (try? String(contentsOf: Self.url, encoding: .utf8)) ?? ""
        log = EventLog(restoring: saved)
        isStarted = true
    }

    func note(_ text: String, mergeKey: String? = nil) {
        guard isStarted else { return }
        log.append(text, stamp: stampFormat.string(from: Date()), mergeKey: mergeKey)
        guard !writeScheduled else { return }
        writeScheduled = true
        Task {
            // Often enough that a crash loses a second at most; a burst of
            // moves is still one write.
            try? await Task.sleep(for: .seconds(1))
            writeScheduled = false
            flush()
        }
    }

    func flush() {
        guard isStarted else { return }
        do {
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try log.fileText.write(to: Self.url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("YoungBar event log write failed: \(error)")
        }
    }

    func recent(_ limit: Int) -> [String] { log.recent(limit) }

    func countJump() {
        jumps = jumps.filter { Date().timeIntervalSince($0) < Self.jumpWindow } + [Date()]
    }

    /// Jumps of the ••• in the last `jumpWindow` seconds.
    var recentJumps: Int {
        jumps.filter { Date().timeIntervalSince($0) < Self.jumpWindow }.count
    }

    static let jumpWindow: TimeInterval = 600
}

extension BarApp {
    func startFlightRecorder() {
        flight.start()
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        flight.note("launch YoungBar \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
            + " · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(Self.sysctl("hw.model"))"
            + (previousSessionCrashed ? " · previous run did not quit normally" : ""))
        flight.note("screens \(screenLayoutText)")
        noteTrustIfChanged()

        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "sleep"),
            (NSWorkspace.didWakeNotification, "wake"),
            (NSWorkspace.sessionDidResignActiveNotification, "session left"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session back"),
        ]
        for (name, text) in events {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.flight.note(text) }
            })
        }
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.flight.note("desktop changed · menu bar \(NSMenu.menuBarVisible() ? "visible" : "hidden")", mergeKey: "space")
            }
        })
        workspaceObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.flight.note("screens changed \(self.screenLayoutText)")
            }
        })
    }

    func noteTrustIfChanged() {
        let trusted = AXIsProcessTrusted()
        guard flight.lastTrust != trusted else { return }
        flight.lastTrust = trusted
        flight.note("accessibility permission \(trusted ? "granted" : "not granted")")
    }

    /// Every display as this Mac has them laid out: `*` holds the •••.
    var screenLayoutText: String {
        let control = controlPanel?.screen
        return NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.frame
            let notch = screen.safeAreaInsets.top > 0 ? " notch" : ""
            let mark = screen == control ? "*" : ""
            return "\(index + 1)\(mark): \(Int(frame.width))×\(Int(frame.height))@\(Int(screen.backingScaleFactor))x"
                + " at (\(Int(frame.minX)),\(Int(frame.minY))) bar \(Int(menuBarHeight(of: screen)))\(notch)"
        }.joined(separator: "; ")
    }

    func recordControlMove(from: NSRect, to: NSRect, reason: String, snapshot: EngineSnapshot) {
        let move = "••• x\(Int(from.minX))→\(Int(to.minX)) y\(Int(from.minY))→\(Int(to.minY)) w\(Int(to.width)) · \(reason)"
        guard ControlMove.isJump(from: from.origin, to: to.origin) else {
            flight.note(move, mergeKey: "control-small")
            return
        }
        flight.countJump()
        // A jump is what a report is about: keep what the decision was based on.
        let icons = snapshot.items.compactMap { item -> (CGFloat, String)? in
            guard let frame = item.frame else { return nil }
            return (frame.minX, "\(name(for: item.id.sectionKey.rawValue)) x\(Int(frame.minX)) y\(Int(frame.minY))")
        }.sorted { $0.0 < $1.0 }.map(\.1)
        flight.note("JUMP \(move) · icons: \(icons.joined(separator: ", "))")
    }

    /// The panel moved. YoungBar's own moves are recorded where they're made;
    /// this catches the others, like macOS relocating it with a display.
    func controlDidMove() {
        guard let frame = controlPanel?.frame else { return }
        guard let known = flight.controlFrame else {
            flight.controlFrame = frame
            return
        }
        guard Date() >= flight.ownMoveUntil,
              abs(known.minX - frame.minX) >= 1 || abs(known.minY - frame.minY) >= 1 else { return }
        flight.controlFrame = frame
        let move = "••• x\(Int(known.minX))→\(Int(frame.minX)) y\(Int(known.minY))→\(Int(frame.minY))"
        if ControlMove.isJump(from: known.origin, to: frame.origin) {
            flight.countJump()
            flight.note("JUMP \(move) · moved from outside YoungBar")
        } else {
            flight.note("\(move) · moved from outside YoungBar", mergeKey: "control-outside")
        }
    }

    /// Crash reports macOS kept for YoungBar in the last 30 days, newest first.
    /// Times only: the reports stay where they are.
    func recentCrashTimes() -> [String] {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "MM-dd HH:mm"
        let since = Date().addingTimeInterval(-30 * 24 * 3600)
        return files.filter { $0.lastPathComponent.hasPrefix("YoungBar") }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .filter { $0 > since }
            .sorted(by: >)
            .map { format.string(from: $0) }
    }
}
