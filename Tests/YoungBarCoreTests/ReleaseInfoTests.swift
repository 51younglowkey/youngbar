// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import YoungBarCore

@Suite struct AppVersionTests {
    @Test func comparesNumerically() throws {
        #expect(try #require(AppVersion("0.1.10")) > #require(AppVersion("0.1.9")))
        #expect(try #require(AppVersion("v0.2")) == #require(AppVersion("0.2.0")))
        #expect(try #require(AppVersion("1.0.0")) > #require(AppVersion("0.99.99")))
    }

    @Test func rejectsNonsense() {
        #expect(AppVersion("beta") == nil)
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("") == nil)
    }
}

@Suite struct ReleaseInfoTests {
    func payload(tag: String = "v0.1.2", prerelease: Bool = false, assets: [String]? = nil) -> Data {
        let names = assets ?? ["YoungBar-0.1.2.zip", "YoungBar-0.1.2.zip.sha256"]
        let list = names.map {
            "{\"name\":\"\($0)\",\"browser_download_url\":\"https://example.com/\($0)\",\"size\":1660991}"
        }.joined(separator: ",")
        return Data("""
        {"tag_name":"\(tag)","body":"## Notes","html_url":"https://example.com/r","draft":false,
         "prerelease":\(prerelease),"assets":[\(list)]}
        """.utf8)
    }

    @Test func parsesTheLatestRelease() throws {
        let info = try ReleaseInfo.parse(payload())
        #expect(info.version.description == "0.1.2")
        #expect(info.zipURL.lastPathComponent == "YoungBar-0.1.2.zip")
        #expect(info.checksumURL.lastPathComponent == "YoungBar-0.1.2.zip.sha256")
        #expect(info.zipSize == 1660991)
        #expect(info.notes == "## Notes")
    }

    @Test func needsBothAssets() {
        #expect(throws: ReleaseInfo.ParseError.missingAsset("YoungBar-0.1.2.zip.sha256")) {
            try ReleaseInfo.parse(payload(assets: ["YoungBar-0.1.2.zip"]))
        }
    }

    @Test func ignoresPrereleases() {
        #expect(throws: ReleaseInfo.ParseError.unreadable) { try ReleaseInfo.parse(payload(prerelease: true)) }
    }

    @Test func readsChecksumFiles() {
        let line = "2123579eca70785baed9279e207b2c29bf6765c7f8bc5f9b5c51903dc7d56ff4  YoungBar-0.1.1.zip\n"
        #expect(ReleaseInfo.expectedDigest(fromChecksumFile: line) == "2123579eca70785baed9279e207b2c29bf6765c7f8bc5f9b5c51903dc7d56ff4")
        #expect(ReleaseInfo.expectedDigest(fromChecksumFile: "nope") == nil)
    }
}

@Suite struct ReleaseNotesTests {
    @Test func keepsChangesDropsInstallSections() {
        let notes = """
        # YoungBar 0.1.4 更新日志

        ## 新增

        - **数字键**：按 `1` 打开
          - 子项

        ## 说明

        - 0.1.2 用户：手动点一次。

        ```sh
        curl … | sh
        ```

        ## 校验

        对应源码：本 tag。
        """
        #expect(ReleaseNotes.blocks(notes) == [
            .section("新增"), .bullet("数字键：按 1 打开", level: 0), .bullet("子项", level: 1),
        ])
        #expect(ReleaseNotes.forDisplay(notes) == "【新增】\n• 数字键：按 1 打开\n  • 子项")
    }

    @Test func picksTheReadersLanguage() {
        let body = "## 新增\n- 中文\n## 说明\n- x\n# English\n## New\n- English\n## Notes\n- y\n## 校验 / Checksum\n- z"
        #expect(ReleaseNotes.blocks(ReleaseNotes.localized(body, preferredLanguages: ["zh-Hans-CN", "en"])) ==
                [.section("新增"), .bullet("中文", level: 0)])
        #expect(ReleaseNotes.blocks(ReleaseNotes.localized(body, preferredLanguages: ["en-GB", "zh-Hans"])) ==
                [.section("New"), .bullet("English", level: 0)])
        #expect(ReleaseNotes.localized("## 新增", preferredLanguages: ["en"]) == "## 新增")
    }

    @Test func fencesAndBlankLinesAreDropped() {
        #expect(ReleaseNotes.blocks("## 修复\n\n```\nx\n```\n- a\n\n\nplain\n") == [
            .section("修复"), .bullet("a", level: 0), .text("plain"),
        ])
    }
}
