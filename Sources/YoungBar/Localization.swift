import Foundation

enum Language: Int, CaseIterable {
    case chinese, english

    var title: String { self == .chinese ? "中文" : "English" }
}

enum L10n {
    nonisolated(unsafe) static var current: Language = .chinese

    static func t(_ zh: String, _ en: String) -> String {
        current == .chinese ? zh : en
    }
}
