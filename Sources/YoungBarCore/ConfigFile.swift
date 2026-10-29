// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The exported layout: per-item modes, the saved order and the options.
/// Plain JSON so it can be read, diffed and edited by hand.
public struct ConfigFile: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    public var app: String
    public var exportedAt: Date
    public var itemModes: [String: Int]
    public var itemOrder: [String]
    public var options: [String: Int]

    public init(itemModes: [String: Int], itemOrder: [String], options: [String: Int],
                exportedAt: Date = Date()) {
        format = Self.currentFormat
        app = "YoungBar"
        self.exportedAt = exportedAt
        self.itemModes = itemModes
        self.itemOrder = itemOrder
        self.options = options
    }

    public enum ImportError: Error, Equatable {
        case unreadable
        case notYoungBar
        case newerFormat(Int)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decodes and cleans an exported file: modes outside 0...2 and
    /// repeated order entries are dropped, unknown options are kept out.
    public static func decode(_ data: Data, knownOptions: Set<String>) throws -> ConfigFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var file = try? decoder.decode(ConfigFile.self, from: data) else { throw ImportError.unreadable }
        guard file.app == "YoungBar" else { throw ImportError.notYoungBar }
        guard file.format <= currentFormat else { throw ImportError.newerFormat(file.format) }
        file.itemModes = file.itemModes.filter { (0...2).contains($0.value) }
        file.itemOrder = LayoutOrder.unique(file.itemOrder)
        file.options = file.options.filter { knownOptions.contains($0.key) }
        return file
    }
}
