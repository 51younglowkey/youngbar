// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import YoungBarCore

/// "What's New": the changelog bundled with this version (copied from
/// `docs/RELEASE-<version>.md` by `Scripts/build.sh`), shown once after an
/// update and from the ••• menu any time.
struct WhatsNewView: View {
    let version: String
    let notes: [ReleaseNotes.Block]
    let theme: ThemeColor
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("YoungBar \(version) 更新内容", "What's new in YoungBar \(version)"))
                .font(.system(size: 16, weight: .semibold))
            ScrollView {
                NotesView(blocks: notes, accent: theme == .clear ? .accentColor : Color(nsColor: theme.accent))
                    .padding(14)
            }
            .defaultScrollAnchor(.top)
            .frame(height: 300)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
            HStack {
                Spacer()
                Button(L10n.t("好", "OK"), action: close)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380, alignment: .leading)
        .tint(theme == .clear ? nil : Color(nsColor: theme.accent))
    }
}

extension BarApp {
    var bundledReleaseNotes: [ReleaseNotes.Block]? {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let blocks = ReleaseNotes.blocks(text)
        return blocks.isEmpty ? nil : blocks
    }

    @objc func showWhatsNew() {
        guard let notes = bundledReleaseNotes else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let window = whatsNewWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                                                styleMask: [.titled, .closable, .fullSizeContentView],
                                                backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = L10n.t("更新内容", "What's New")
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: WhatsNewView(
            version: version, notes: notes, theme: themeColor,
            close: { [weak window] in window?.orderOut(nil) }))
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        whatsNewWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
