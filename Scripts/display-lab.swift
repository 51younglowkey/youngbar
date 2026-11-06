#!/usr/bin/env swift
// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// Runs YoungBar's multi-display checks through the display arrangements this
// Mac can reach, unattended, and puts everything back. You run this yourself:
// it changes the display arrangement (for this login session only).
//
//   TESTHOOKS=1 sh Scripts/build.sh
//   swift Scripts/display-lab.swift --dry-run     # only prints the plan
//   swift Scripts/display-lab.swift               # about 10 minutes; hands off
//   swift Scripts/display-lab.swift --with-off    # also turns each display off in software
//   swift Scripts/display-lab.swift --restore     # puts the saved arrangement back
//
// Quit the YoungBar you normally run first; this starts the test build. Windows
// may land elsewhere while displays move, and macOS doesn't always put them back.
// Safety: changes are session-only (a logout resets them), and a watchdog process
// restores the arrangement if this script dies or runs past 30 minutes.

import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
let dryRun = arguments.contains("--dry-run")
let withOff = arguments.contains("--with-off")
let support = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/YoungBar", isDirectory: true)
let savedURL = support.appendingPathComponent("display-lab-original.json")
let bundleID = "studio.wuyiyang.youngbar"

func log(_ text: String) {
    print(text)
    fflush(stdout)
}

func displays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var list = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &list, &count)
    return Array(list.prefix(Int(count)))
}

// MARK: - Saving and restoring

struct Saved: Codable {
    var origins: [String: [Int]]   // display id -> x, y
    var modes: [String: Int32]     // display id -> mode number
    var loginItemToken: String?
}

func modeNumber(of id: CGDirectDisplayID) -> Int32 {
    CGDisplayCopyDisplayMode(id)?.ioDisplayModeID ?? 0
}

func currentState(token: String?) -> Saved {
    var origins: [String: [Int]] = [:]
    var modes: [String: Int32] = [:]
    for id in displays() {
        let bounds = CGDisplayBounds(id)
        origins[String(id)] = [Int(bounds.minX), Int(bounds.minY)]
        modes[String(id)] = modeNumber(of: id)
    }
    return Saved(origins: origins, modes: modes, loginItemToken: token)
}

typealias EnableDisplay = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
let enableDisplay: EnableDisplay? = {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let call = dlsym(handle, "SLSConfigureDisplayEnabled") else { return nil }
    return unsafeBitCast(call, to: EnableDisplay.self)
}()

@discardableResult
func configure(_ body: (CGDisplayConfigRef?) -> Void) -> Bool {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return false }
    body(config)
    return CGCompleteDisplayConfiguration(config, .forSession) == .success
}

func restore(_ saved: Saved) {
    // Anything off comes back on first, and any mirroring ends.
    for key in saved.origins.keys {
        guard let id = CGDirectDisplayID(key) else { continue }
        configure { config in
            _ = enableDisplay?(config, id, true)
        }
    }
    sleep(2)
    configure { config in
        for key in saved.origins.keys {
            guard let id = CGDirectDisplayID(key) else { continue }
            CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        }
    }
    sleep(1)
    configure { config in
        for (key, origin) in saved.origins {
            guard let id = CGDirectDisplayID(key), origin.count == 2 else { continue }
            CGConfigureDisplayOrigin(config, id, Int32(origin[0]), Int32(origin[1]))
            if let number = saved.modes[key],
               let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode],
               let mode = modes.first(where: { $0.ioDisplayModeID == number }) {
                CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
            }
        }
    }
}

func loadSaved() -> Saved? {
    (try? Data(contentsOf: savedURL)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
}

if arguments.contains("--restore") {
    guard let saved = loadSaved() else {
        log("No saved arrangement at \(savedURL.path)")
        exit(1)
    }
    restore(saved)
    log("Restored the saved arrangement.")
    exit(0)
}

// The watchdog: `--watchdog <pid>` waits for that process or 30 minutes.
if let index = arguments.firstIndex(of: "--watchdog"), index + 1 < arguments.count, let pid = pid_t(arguments[index + 1]) {
    let deadline = Date().addingTimeInterval(30 * 60)
    while kill(pid, 0) == 0, Date() < deadline { sleep(2) }
    // The script removes the saved file once it has restored by itself.
    if let saved = loadSaved() {
        restore(saved)
        try? FileManager.default.removeItem(at: savedURL)
    }
    exit(0)
}

// MARK: - The plan

guard displays().count >= 2 || CGDisplayMirrorsDisplay(displays()[0]) != kCGNullDirectDisplay else {
    log("Only one display is online: connect another and run this again.")
    exit(1)
}
let builtIn = displays().first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
let external = displays().first { $0 != builtIn } ?? kCGNullDirectDisplay
let inner = CGDisplayBounds(builtIn).size
let outer = CGDisplayBounds(external).size
let (innerW, innerH, outerW, outerH) = (Int32(inner.width), Int32(inner.height), Int32(outer.width), Int32(outer.height))

struct Step {
    let name: String
    let what: String
    /// Quit and start YoungBar again in this arrangement too.
    var relaunch = false
    let apply: (CGDisplayConfigRef?) -> Void
}

func place(_ config: CGDisplayConfigRef?, inner a: (Int32, Int32), outer b: (Int32, Int32)) {
    CGConfigureDisplayOrigin(config, builtIn, a.0, a.1)
    CGConfigureDisplayOrigin(config, external, b.0, b.1)
}

/// A low-resolution mode of the external display: a narrow bar, crowded.
func narrowMode() -> CGDisplayMode? {
    let modes = (CGDisplayCopyAllDisplayModes(external, nil) as? [CGDisplayMode]) ?? []
    return modes.filter { $0.width >= 1024 && $0.isUsableForDesktopGUI() }.min { $0.width < $1.width }
}

var steps: [Step] = [
    Step(name: "right-top", what: "external to the right, tops aligned") { place($0, inner: (0, 0), outer: (innerW, 0)) },
    Step(name: "right-lower", what: "external to the right, 300 lower") { place($0, inner: (0, 0), outer: (innerW, 300)) },
    Step(name: "left", what: "external to the left", relaunch: true) { place($0, inner: (0, 0), outer: (-outerW, 0)) },
    Step(name: "above", what: "external above: the two bars share x", relaunch: true) { place($0, inner: (0, 0), outer: (0, -outerH)) },
    Step(name: "below", what: "external below the built-in") { place($0, inner: (0, 0), outer: (0, innerH)) },
    Step(name: "main-external-right", what: "external is the main display, built-in to its left", relaunch: true) {
        place($0, inner: (-innerW, 0), outer: (0, 0))
    },
    Step(name: "main-external-below", what: "external is the main display, built-in below it") {
        place($0, inner: (0, outerH), outer: (0, 0))
    },
    Step(name: "narrow-external", what: "external at a low resolution, to the right") { config in
        place(config, inner: (0, 0), outer: (innerW, 0))
        if let mode = narrowMode() { CGConfigureDisplayWithDisplayMode(config, external, mode, nil) }
    },
    Step(name: "mirror", what: "mirrored", relaunch: true) { config in
        if let mode = (CGDisplayCopyAllDisplayModes(external, nil) as? [CGDisplayMode])?.first(where: { $0.ioDisplayModeID == loadSaved()?.modes[String(external)] }) {
            CGConfigureDisplayWithDisplayMode(config, external, mode, nil)
        }
        CGConfigureDisplayMirrorOfDisplay(config, external, builtIn)
    },
]
if withOff, enableDisplay != nil {
    steps += [
        Step(name: "external-off", what: "external turned off: like unplugging it") { config in
            CGConfigureDisplayMirrorOfDisplay(config, external, kCGNullDirectDisplay)
            _ = enableDisplay?(config, external, false)
        },
        Step(name: "external-back", what: "external back: like plugging it in") { config in
            _ = enableDisplay?(config, external, true)
        },
        Step(name: "only-external", what: "built-in off: like a Mac mini, or the lid closed", relaunch: true) { config in
            _ = enableDisplay?(config, builtIn, false)
        },
        Step(name: "built-in-back", what: "built-in back: like opening the lid") { config in
            _ = enableDisplay?(config, builtIn, true)
        },
    ]
}

log("Displays: built-in \(builtIn) \(innerW)×\(innerH), external \(external) \(outerW)×\(outerH)")
for step in steps { log("  \(step.name): \(step.what)\(step.relaunch ? " (and a fresh launch)" : "")") }
if dryRun {
    log("Dry run: nothing changed.")
    exit(0)
}

// MARK: - Running it

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let app = root.appendingPathComponent("build/YoungBar.app")
guard FileManager.default.fileExists(atPath: app.path) else {
    log("No build/YoungBar.app here: run TESTHOOKS=1 sh Scripts/build.sh in the repository first.")
    exit(1)
}
if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
    log("YoungBar is running: quit it first (right-click ••• → Quit), then run this again.")
    exit(1)
}

func shell(_ path: String, _ args: [String], env: [String: String] = [:]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

let stamp = shell("/bin/date", ["+%Y%m%d-%H%M%S"]).trimmingCharacters(in: .whitespacesAndNewlines)
let out = support.appendingPathComponent("display-lab/\(stamp)", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let defaultsBefore = shell("/usr/bin/defaults", ["export", bundleID, "-"])
try defaultsBefore.write(to: out.appendingPathComponent("defaults-before.plist"), atomically: true, encoding: .utf8)

// A run from this checkout must not move the login item here (AGENTS.md section 5).
let tokenRead = shell("/usr/bin/defaults", ["read", bundleID, "loginItemToken"]).trimmingCharacters(in: .whitespacesAndNewlines)
let token = tokenRead.contains("does not exist") ? "" : tokenRead
let build = shell("/usr/libexec/PlistBuddy", ["-c", "Print CFBundleVersion", app.appendingPathComponent("Contents/Info.plist").path])
    .trimmingCharacters(in: .whitespacesAndNewlines)
_ = shell("/usr/bin/defaults", ["write", bundleID, "loginItemToken", "\(app.path)|\(build)"])

let saved = currentState(token: token.isEmpty ? nil : token)
try JSONEncoder().encode(saved).write(to: savedURL)
let watchdog = Process()
watchdog.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
watchdog.arguments = [#filePath, "--watchdog", String(getpid())]
try? watchdog.run()

func lab(_ command: String) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("studio.wuyiyang.youngbar.lab"), object: command, userInfo: nil, deliverImmediately: true)
}

func launch() {
    try? FileManager.default.removeItem(at: support.appendingPathComponent("displaylab-ready.json"))
    _ = shell("/usr/bin/open", ["--env", "YOUNGBAR_DISPLAYLAB=1", "--env", "YOUNGBAR_DISPLAY_POINTER=1", app.path])
    let deadline = Date().addingTimeInterval(40)
    while Date() < deadline, !FileManager.default.fileExists(atPath: support.appendingPathComponent("displaylab-ready.json").path) { sleep(1) }
}

func quitApp() {
    lab("quit")
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline, !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { sleep(1) }
}

/// Every display's bar and strip of screen below it, then the checks.
func record(_ name: String) -> Bool {
    for (index, id) in displays().enumerated() where CGDisplayIsActive(id) != 0 {
        let bounds = CGDisplayBounds(id)
        let rect = "\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),70"
        _ = shell("/usr/sbin/screencapture", ["-x", "-R", rect, out.appendingPathComponent("\(name)-display\(index + 1).png").path])
    }
    let file = support.appendingPathComponent("\(name).json")
    try? FileManager.default.removeItem(at: file)
    lab("run:\(name)")
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
        sleep(2)
        if let data = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let passed = json["passed"] as? Bool {
            try? FileManager.default.moveItem(at: file, to: out.appendingPathComponent("\(name).json"))
            return passed
        }
    }
    return false
}

var summary: [String] = []
func note(_ name: String, _ passed: Bool) {
    let line = "\(passed ? "PASS" : "FAIL")  \(name)"
    summary.append(line)
    log(line)
}

log("Results in \(out.path)")
launch()
sleep(4)
note("start", record("start"))
for step in steps {
    log("→ \(step.what)")
    guard configure(step.apply) else {
        note("\(step.name): the arrangement was refused", false)
        continue
    }
    // Long enough for the walks after a display change to finish.
    sleep(6)
    note(step.name, record(step.name))
    if step.relaunch {
        quitApp()
        launch()
        sleep(4)
        note("\(step.name), fresh launch", record("\(step.name)-launch"))
    }
}
restore(saved)
sleep(6)
note("restored", record("restored"))
quitApp()
try? FileManager.default.removeItem(at: savedURL)
if let token = saved.loginItemToken {
    _ = shell("/usr/bin/defaults", ["write", bundleID, "loginItemToken", token])
} else {
    _ = shell("/usr/bin/defaults", ["delete", bundleID, "loginItemToken"])
}
try? FileManager.default.copyItem(at: support.appendingPathComponent("events.log"), to: out.appendingPathComponent("events.log"))
let defaultsAfter = shell("/usr/bin/defaults", ["export", bundleID, "-"])
try defaultsAfter.write(to: out.appendingPathComponent("defaults-after.plist"), atomically: true, encoding: .utf8)
summary.append(defaultsBefore == defaultsAfter ? "defaults: unchanged" : "defaults: CHANGED, compare defaults-before.plist and defaults-after.plist")
let text = summary.joined(separator: "\n") + "\n"
try text.write(to: out.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
log(text)
log("Done. The arrangement is back. Start your usual YoungBar again; results in \(out.path)")
