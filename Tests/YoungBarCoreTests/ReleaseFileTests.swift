// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import YoungBarCore

/// The real changelogs in docs/: the app shows one language of them after an
/// update (Scripts/build.sh bundles the current one), GitHub shows both.
@Suite struct ReleaseFileTests {
    static let docs = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs", isDirectory: true)

    /// Changelogs from 0.1.4 on are written in two halves.
    func bilingualReleases() throws -> [(name: String, text: String)] {
        let files = try FileManager.default.contentsOfDirectory(at: Self.docs, includingPropertiesForKeys: nil)
        return try files.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("RELEASE-"), url.pathExtension == "md",
                  let version = AppVersion(String(url.deletingPathExtension().lastPathComponent.dropFirst("RELEASE-".count))),
                  let first = AppVersion("0.1.4"), version >= first else { return nil }
            return (name, try String(contentsOf: url, encoding: .utf8))
        }
    }

    @Test func thereAreChangelogsToCheck() throws {
        #expect(try bilingualReleases().count >= 2)
    }

    @Test func eachHalfHasOnlyChangeSections() throws {
        let chinese: Set<String> = ["新增", "优化", "移除", "修复"]
        let english: Set<String> = ["New", "Improved", "Removed", "Fixed"]
        for release in try bilingualReleases() {
            #expect(release.text.contains("\n" + ReleaseNotes.englishMarker + "\n"), "\(release.name) has no English half")
            let zh = ReleaseNotes.blocks(ReleaseNotes.localized(release.text, preferredLanguages: ["zh-Hans"]))
            let en = ReleaseNotes.blocks(ReleaseNotes.localized(release.text, preferredLanguages: ["en"]))
            let zhSections = zh.compactMap { if case .section(let title) = $0 { title } else { nil } }
            let enSections = en.compactMap { if case .section(let title) = $0 { title } else { nil } }
            #expect(!zhSections.isEmpty && Set(zhSections).isSubset(of: chinese), "\(release.name): \(zhSections)")
            #expect(!enSections.isEmpty && Set(enSections).isSubset(of: english), "\(release.name): \(enSections)")
            #expect(zhSections.count == enSections.count, "\(release.name): the halves have different sections")
            let zhBullets = zh.filter { if case .bullet = $0 { true } else { false } }.count
            let enBullets = en.filter { if case .bullet = $0 { true } else { false } }.count
            #expect(zhBullets == enBullets, "\(release.name): \(zhBullets) Chinese vs \(enBullets) English lines")
        }
    }

    @Test func nothingMeantForTheWebShowsInTheApp() throws {
        for release in try bilingualReleases() {
            for language in ["zh-Hans", "en"] {
                let shown = ReleaseNotes.forDisplay(ReleaseNotes.localized(release.text, preferredLanguages: [language]))
                for web in ["shasum", "curl", "对应源码", "Corresponding source", ReleaseNotes.englishMarker] {
                    #expect(!shown.contains(web), "\(release.name) (\(language)) shows \(web)")
                }
            }
        }
    }
}
