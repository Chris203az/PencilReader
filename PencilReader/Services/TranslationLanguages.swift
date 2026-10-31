import Foundation
import ReaderCore
import Translation

/// The language pair chosen in Settings: what the books are written in and what they are
/// translated into. Translation, "Ascolta", text recognition and the AI answers follow it.
enum TranslationLanguages {
    static let sourceKey = "translation.source"
    static let targetKey = "translation.target"

    static var current: LanguagePair {
        let defaults = UserDefaults.standard
        return LanguagePair(source: defaults.string(forKey: sourceKey) ?? LanguagePair.default.source,
                            target: defaults.string(forKey: targetKey) ?? LanguagePair.default.target)
    }

    /// The languages Apple's on-device translation offers, by name in the interface language:
    /// one per language ("en", not every English of the world), unless the variants differ in script.
    static func supported() async -> [String] {
        let languages = await LanguageAvailability().supportedLanguages
        let byLanguage = Dictionary(grouping: languages) {
            [$0.languageCode?.identifier, $0.script?.identifier].compactMap { $0 }.joined(separator: "-")
        }
        let codes = byLanguage.values.map { variants in
            variants.map(\.minimalIdentifier).min { ($0.count, $0) < ($1.count, $1) }!
        }
        return codes.sorted { name(of: $0).localizedCompare(name(of: $1)) == .orderedAscending }
    }

    /// "Inglese (Regno Unito)", "English": a code by name, in the interface language.
    static func name(of code: String) -> String {
        guard let name = Locale.current.localizedString(forIdentifier: code) else { return code }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
