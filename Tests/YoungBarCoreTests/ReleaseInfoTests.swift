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
