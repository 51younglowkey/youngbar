// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

/// The language a fresh install starts in. YoungBar has Chinese and
/// English; until 0.1.5 every install started in Chinese, so English-speaking
/// users met a Chinese guide on first launch.
public enum PreferredLanguage {
    /// Whether the Mac's first preferred language is a Chinese one
    /// ("zh-Hans-CN", "zh-Hant-TW", "yue-Hant-HK"…). No preference at all
    /// keeps Chinese, the earlier default.
    public static func isChinese(_ preferred: [String]) -> Bool {
        guard let first = preferred.first?.lowercased() else { return true }
        return first.hasPrefix("zh") || first.hasPrefix("yue")
    }
}
