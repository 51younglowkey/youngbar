// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// Release notes (`docs/RELEASE-<version>.md`, also the GitHub release body)
/// as YoungBar shows them in its own windows: what changed, without the
/// install commands, checksums and source link meant for the web page, and
/// as blocks to draw rather than Markdown to read.
public enum ReleaseNotes {
    public enum Block: Equatable, Sendable {
        case section(String)
        case bullet(String, level: Int)
        case text(String)
    }

    /// Headings whose section is only about getting the build.
    static let skippedSections = ["说明", "安装", "升级", "校验", "要求", "已知限制",
                                  "Notes", "Install", "Updating", "Checksum", "Requirements", "Known"]

    /// A release body is Chinese, then this marker, then English; GitHub
    /// shows both (the marker is an HTML comment), the app one of them.
    public static let englishMarker = "<!-- en -->"

    /// The half for the reader: English unless their first preferred
    /// language is Chinese. A body without the marker is returned whole.
    public static func localized(_ markdown: String, preferredLanguages: [String]) -> String {
        guard let range = markdown.range(of: englishMarker) else { return markdown }
        let chinese = preferredLanguages.first?.hasPrefix("zh") ?? false
        return String(chinese ? markdown[..<range.lowerBound] : markdown[range.upperBound...])
    }

    public static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var skipping = false
        var inFence = false
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence || line.hasPrefix("# ") { continue }
            if line.hasPrefix("## ") {
                skipping = skippedSections.contains { line.contains($0) }
                if !skipping { blocks.append(.section(clean(String(line.dropFirst(3))))) }
                continue
            }
            if skipping || line.hasPrefix("对应源码") || line.hasPrefix("Corresponding source") { continue }
            let indent = line.prefix { $0 == " " }.count
            let body = line.drop { $0 == " " }
            if body.hasPrefix("- ") || body.hasPrefix("* ") {
                blocks.append(.bullet(clean(String(body.dropFirst(2))), level: indent / 2))
            } else if !body.isEmpty {
                blocks.append(.text(clean(String(body))))
            }
        }
        return blocks
    }

    /// Plain text, one block a line, for anywhere styling isn't available.
    public static func forDisplay(_ markdown: String) -> String {
        blocks(markdown).map { block in
            switch block {
            case .section(let title): return "【\(title)】"
            case .bullet(let text, let level): return String(repeating: "  ", count: level) + "• " + text
            case .text(let text): return text
            }
        }.joined(separator: "\n")
    }

    /// Markdown markers dropped: bold and code spans.
    static func clean(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        while text.last?.isWhitespace == true { text.removeLast() }
        return text
    }
}
