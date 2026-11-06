// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// A dotted version ("0.1.10"), compared number by number; missing parts
/// count as 0, so 0.2 == 0.2.0. A beta ("0.1.8-beta.2") comes before the
/// version it leads up to, so someone on a beta is offered that version.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]
    /// The beta's number; nil for a final version.
    public let beta: Int?

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        var beta: Int?
        if let range = trimmed.range(of: "-beta.") {
            guard let number = Int(trimmed[range.upperBound...]), number >= 0 else { return nil }
            beta = number
            trimmed = String(trimmed[..<range.lowerBound])
        }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
        self.beta = beta
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".") + (beta.map { "-beta.\($0)" } ?? "")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        switch (lhs.beta, rhs.beta) {
        case let (a?, b?): return a < b
        case (_?, nil): return true
        default: return false
        }
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// The parts of GitHub's "latest release" answer the updater needs: the
/// version, the notes, and the app zip with its checksum file.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let notes: String
    public let pageURL: URL
    public let zipURL: URL
    public let zipSize: Int
    public let checksumURL: URL

    public enum ParseError: Error, Equatable {
        case unreadable
        case badVersion(String)
        case missingAsset(String)
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// Parses `GET /repos/{owner}/{repo}/releases/latest`. The zip must be
    /// named `YoungBar-<version>.zip`, as `Scripts/package.sh` makes it.
    public static func parse(_ data: Data) throws -> ReleaseInfo {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true else { throw ParseError.unreadable }
        guard let version = AppVersion(payload.tag_name) else { throw ParseError.badVersion(payload.tag_name) }
        let zipName = "YoungBar-\(version).zip"
        guard let zip = payload.assets.first(where: { $0.name == zipName }) else { throw ParseError.missingAsset(zipName) }
        guard let checksum = payload.assets.first(where: { $0.name == zipName + ".sha256" }) else {
            throw ParseError.missingAsset(zipName + ".sha256")
        }
        return ReleaseInfo(version: version, notes: payload.body ?? "", pageURL: payload.html_url,
                           zipURL: zip.browser_download_url, zipSize: zip.size,
                           checksumURL: checksum.browser_download_url)
    }

    /// The hex digest from a `shasum -a 256` line ("<hex>  <file>").
    public static func expectedDigest(fromChecksumFile text: String) -> String? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let digest = first.lowercased()
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { return nil }
        return digest
    }
}
