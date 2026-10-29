// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CryptoKit
import Security
import SwiftUI
import YoungBarCore

/// In-app updates from GitHub Releases. Nothing runs on its own: YoungBar
/// goes online only when the user chooses Check for Updates.
///
/// Installing: download the zip and its .sha256, check the digest, unzip,
/// check the new app is signed by the same certificate as this one, then
/// quit normally (every hidden icon comes back) and let a small shell
/// script swap the bundles once this process is gone and reopen the app.
enum UpdateState: Equatable {
    case checking
    case upToDate(String)
    case available(String, String)
    case downloading(Double)
    case installing
    case failed(String)
}

@MainActor
@Observable
final class UpdateModel {
    var state: UpdateState = .checking
    var current = ""
    @ObservationIgnored var install: () -> Void = {}
    @ObservationIgnored var cancel: () -> Void = {}
    @ObservationIgnored var openPage: () -> Void = {}
    @ObservationIgnored var close: () -> Void = {}
}

struct UpdateView: View {
    let model: UpdateModel
    let theme: ThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.state {
            case .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("正在检查更新…", "Checking for updates…"))
                }
                buttons { Button(L10n.t("取消", "Cancel"), action: model.close) }
            case .upToDate(let version):
                title(L10n.t("已是最新版本", "YoungBar is up to date"))
                Text(L10n.t("当前版本 \(version) 就是最新的。", "Version \(version) is the latest."))
                    .foregroundStyle(.secondary)
                buttons { Button(L10n.t("好", "OK"), action: model.close).keyboardShortcut(.defaultAction) }
            case .available(let version, let notes):
                title(L10n.t("发现新版本 \(version)", "YoungBar \(version) is available"))
                Text(L10n.t("当前版本 \(model.current)。安装时 YoungBar 会退出（隐藏的图标先恢复显示），装好后自动重新打开。",
                            "You have \(model.current). YoungBar quits to install (hidden icons come back first) and reopens by itself."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    Text(Self.plainNotes(notes))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
                buttons {
                    Button(L10n.t("在 GitHub 查看", "View on GitHub"), action: model.openPage)
                    Button(L10n.t("稍后", "Later"), action: model.close)
                    Button(L10n.t("安装并重新打开", "Install and Relaunch"), action: model.install)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            case .downloading(let fraction):
                title(L10n.t("正在下载…", "Downloading…"))
                ProgressView(value: fraction)
                Text("\(Int((fraction * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                buttons { Button(L10n.t("取消", "Cancel"), action: model.cancel) }
            case .installing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("正在安装，YoungBar 马上会重新打开…", "Installing; YoungBar will reopen in a moment…"))
                }
            case .failed(let message):
                title(L10n.t("无法完成更新", "Couldn't update"))
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                buttons {
                    Button(L10n.t("在 GitHub 打开", "Open on GitHub"), action: model.openPage)
                    Button(L10n.t("关闭", "Close"), action: model.close).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .tint(theme == .clear ? nil : Color(nsColor: theme.accent))
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 16, weight: .semibold))
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { Spacer(); content() }
    }

    /// GitHub notes are Markdown; headings and code fences read fine as text
    /// once their markers are dropped.
    static func plainNotes(_ notes: String) -> String {
        notes.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("```") }
            .map { line -> String in
                var text = String(line)
                while text.hasPrefix("#") { text.removeFirst() }
                return text.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "`", with: "")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reports download progress from a URLSession delegate.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

extension BarApp {
    static let releasesAPI = URL(string: "https://api.github.com/repos/51younglowkey/youngbar/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/51younglowkey/youngbar/releases/latest")!

    var currentVersion: String {
        #if YOUNGBAR_TESTHOOKS
        // Lets a test build pretend to be older and update to the real release.
        if let pretend = ProcessInfo.processInfo.environment["YOUNGBAR_UPDATE_PRETEND_VERSION"] { return pretend }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    @objc func checkForUpdates() {
        let model = updateModel ?? UpdateModel()
        if updateWindow == nil {
            model.install = { [weak self] in self?.installUpdate() }
            model.cancel = { [weak self] in
                self?.updateTask?.cancel()
                self?.updateWindow?.orderOut(nil)
            }
            model.openPage = { [weak self] in
                NSWorkspace.shared.open(self?.pendingRelease?.pageURL ?? Self.releasesPage)
                self?.updateWindow?.orderOut(nil)
            }
            model.close = { [weak self] in
                self?.updateTask?.cancel()
                self?.updateWindow?.orderOut(nil)
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = L10n.t("检查更新", "Check for Updates")
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: UpdateView(model: model, theme: themeColor))
            host.sizingOptions = [.preferredContentSize]
            window.contentViewController = host
            updateModel = model
            updateWindow = window
        }
        guard updateTask == nil || model.state != .installing else { return }
        model.current = currentVersion
        model.state = .checking
        updateWindow?.center()
        updateWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateTask?.cancel()
        updateTask = Task { await runUpdateCheck(model) }
    }

    func runUpdateCheck(_ model: UpdateModel) async {
        do {
            var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("YoungBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.message(L10n.t("GitHub 暂时没有返回版本信息（\((response as? HTTPURLResponse)?.statusCode ?? 0)），请稍后再试。",
                                                 "GitHub didn't return release information (\((response as? HTTPURLResponse)?.statusCode ?? 0)). Try again later."))
            }
            let release = try ReleaseInfo.parse(data)
            guard let current = AppVersion(currentVersion), release.version > current else {
                model.state = .upToDate(currentVersion)
                return
            }
            pendingRelease = release
            model.state = .available(release.version.description, release.notes)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            model.state = .failed(Self.describe(error))
        }
    }

    func installUpdate() {
        guard let release = pendingRelease, let model = updateModel else { return }
        model.state = .downloading(0)
        updateTask?.cancel()
        updateTask = Task {
            do {
                let app = try await downloadAndVerify(release) { fraction in
                    Task { @MainActor in
                        if case .downloading = model.state { model.state = .downloading(fraction) }
                    }
                }
                try Task.checkCancellation()
                model.state = .installing
                try launchSwap(newApp: app)
                // Quit the normal way: it shows every hidden icon first.
                // Not from inside this task: `terminate` waits in a nested
                // event loop for the reply that `applicationShouldTerminate`
                // sends from another main-actor task, which can't start
                // while this one is blocked. A run-loop perform is outside.
                try? await Task.sleep(for: .milliseconds(600))
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                model.state = .failed(Self.describe(error))
            }
        }
    }

    enum UpdateError: Error {
        case message(String)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case UpdateError.message(let text): return text
        case let error as URLError:
            return L10n.t("网络连接失败：\(error.localizedDescription)", "Network error: \(error.localizedDescription)")
        case ReleaseInfo.ParseError.missingAsset(let name):
            return L10n.t("最新的发布里缺少 \(name)。", "The latest release has no \(name).")
        default:
            return L10n.t("读不懂 GitHub 返回的版本信息。", "Couldn't read the release information from GitHub.")
        }
    }

    /// Downloads, checks the digest, unzips and checks the signature.
    /// Returns the new app bundle in a private temporary folder.
    func downloadAndVerify(_ release: ReleaseInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("YoungBar-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let (checksumData, _) = try await URLSession.shared.data(from: release.checksumURL)
        guard let expected = ReleaseInfo.expectedDigest(fromChecksumFile: String(decoding: checksumData, as: UTF8.self)) else {
            throw UpdateError.message(L10n.t("校验文件格式不对，已停止安装。", "The checksum file is malformed; nothing was installed."))
        }
        let delegate = DownloadDelegate(progress: progress)
        let (downloaded, response) = try await URLSession.shared.download(from: release.zipURL, delegate: delegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.message(L10n.t("下载失败，请稍后再试。", "The download failed. Try again later."))
        }
        let zip = work.appendingPathComponent("YoungBar.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)
        let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else {
            throw UpdateError.message(L10n.t("下载的文件校验不通过（可能被损坏或篡改），已停止安装。",
                                             "The download doesn't match its checksum (damaged or altered); nothing was installed."))
        }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.appendingPathComponent("out").path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = work.appendingPathComponent("out/YoungBar.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError.message(L10n.t("解压失败，已停止安装。", "Couldn't unzip the download; nothing was installed."))
        }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == release.version else {
            throw UpdateError.message(L10n.t("下载的 app 版本信息不对，已停止安装。", "The downloaded app isn't the expected version; nothing was installed."))
        }
        guard Self.signedLikeThisApp(app) else {
            throw UpdateError.message(L10n.t(
                "下载的 app 和当前 app 的签名证书不一致，没有安装。如果你用的是自己从源码编译的版本，请到 GitHub 手动下载。",
                "The downloaded app isn't signed with the same certificate as this one, so it wasn't installed. If you built YoungBar yourself, download the update from GitHub."))
        }
        return app
    }

    /// The new bundle must satisfy this app's own designated requirement:
    /// same identifier, same signing certificate. (An ad-hoc build's
    /// requirement is its own hash, so a self-built copy never matches.)
    nonisolated static func signedLikeThisApp(_ url: URL) -> Bool {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return false }
        var selfStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic else { return false }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement else { return false }
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &newCode) == errSecSuccess, let newCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess
    }

    /// Starts the script that waits for this process to exit, swaps the
    /// bundles (putting the old one back if the move fails) and reopens.
    func launchSwap(newApp: URL) throws {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.message(L10n.t("没有权限替换 \(parent.path) 里的 YoungBar，请到 GitHub 手动下载。",
                                             "No permission to replace YoungBar in \(parent.path); download the update from GitHub."))
        }
        let log = Diagnostics.url.deletingLastPathComponent().appendingPathComponent("update.log")
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        pid="$1"; new="$2"; app="$3"; log="$4"
        work="$(dirname "$new")"
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          i=$((i + 1)); [ $i -gt 240 ] && { echo "$(date) gave up: YoungBar did not quit" >> "$log"; exit 1; }
          sleep 0.25
        done
        if mv "$app" "$work/previous.app"; then
          if mv "$new" "$app"; then
            rm -rf "$work/previous.app"
            echo "$(date) installed $(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null) at $app" >> "$log"
          else
            mv "$work/previous.app" "$app"
            echo "$(date) failed to move the new app; kept the old one" >> "$log"
          fi
        else
          echo "$(date) failed to move the old app aside" >> "$log"
        fi
        xattr -dr com.apple.quarantine "$app" 2>/dev/null
        open "$app"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "youngbar-update", String(ProcessInfo.processInfo.processIdentifier),
                             newApp.path, target.path, log.path]
        try process.run()
    }
}
