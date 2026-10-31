import Foundation

/// The language of the books and the one they are translated into, as BCP-47 codes ("en", "it").
/// The AI prompts are written in Italian, so they name the two languages in Italian.
public struct LanguagePair: Sendable, Equatable {
    public var source: String
    public var target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }

    /// English books, Italian translations.
    public static let `default` = LanguagePair(source: "en", target: "it")

    /// "inglese", "tedesco": the source language as the prompts call it.
    public var sourceName: String { Self.italianName(of: source) }
    /// "italiano", "spagnolo": the target language as the prompts call it.
    public var targetName: String { Self.italianName(of: target) }

    private static func italianName(of code: String) -> String {
        Locale(identifier: "it").localizedString(forIdentifier: code) ?? code
    }
}
