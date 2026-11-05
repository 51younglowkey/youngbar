// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import YoungBarCore

@Suite struct ImageFitTests {
    let box = CGRect(x: 0, y: 0, width: 36, height: 36)

    @Test func squareFillsTheBox() {
        #expect(ImageFit.aspectFit(CGSize(width: 512, height: 512), in: box) == box)
    }

    @Test func wideKeepsItsShapeAndIsCentred() {
        let rect = ImageFit.aspectFit(CGSize(width: 200, height: 100), in: box)
        #expect(rect == CGRect(x: 0, y: 9, width: 36, height: 18))
    }

    @Test func tallKeepsItsShapeAndIsCentred() {
        let rect = ImageFit.aspectFit(CGSize(width: 30, height: 120), in: box)
        #expect(rect == CGRect(x: 13.5, y: 0, width: 9, height: 36))
    }

    @Test func smallPicturesScaleUp() {
        #expect(ImageFit.aspectFit(CGSize(width: 18, height: 9), in: box) == CGRect(x: 0, y: 9, width: 36, height: 18))
    }

    @Test func emptySizeFillsTheBox() {
        #expect(ImageFit.aspectFit(.zero, in: box) == box)
        #expect(ImageFit.aspectFit(CGSize(width: 10, height: 0), in: box) == box)
    }
}

@Suite struct PreferredLanguageTests {
    @Test func chineseVariantsAreChinese() {
        #expect(PreferredLanguage.isChinese(["zh-Hans-CN", "en-GB"]))
        #expect(PreferredLanguage.isChinese(["zh-Hant-TW"]))
        #expect(PreferredLanguage.isChinese(["yue-Hant-HK"]))
        #expect(PreferredLanguage.isChinese(["ZH-HANS"]))
    }

    @Test func onlyTheFirstChoiceCounts() {
        #expect(!PreferredLanguage.isChinese(["en-GB", "zh-Hans-CN"]))
        #expect(!PreferredLanguage.isChinese(["ja-JP"]))
    }

    @Test func noPreferenceKeepsTheOldDefault() {
        #expect(PreferredLanguage.isChinese([]))
    }
}

@Suite struct MenuBarThemeTests {
    @Test func theTwoKnownValues() {
        #expect(MenuBarTheme.isDark(rawValue: 0) == false)
        #expect(MenuBarTheme.isDark(rawValue: 1) == true)
    }

    @Test func anythingElseIsUnknown() {
        #expect(MenuBarTheme.isDark(rawValue: 2) == nil)
        #expect(MenuBarTheme.isDark(rawValue: -1) == nil)
    }
}
