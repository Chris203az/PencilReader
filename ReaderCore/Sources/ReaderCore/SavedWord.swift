import Foundation

/// A word or phrase circled while reading, with its translation and where it was found.
public struct SavedWord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var term: String
    /// Italian for the term as used in the sentence (or on its own when it couldn't be located).
    public var translation: String
    public var sentence: String?
    public var sentenceTranslation: String?
    public let documentID: UUID
    public var documentTitle: String
    /// Zero-based page of the latest lookup.
    public var page: Int
    public var lookups: Int
    public let firstLookedUp: Date
    public var lastLookedUp: Date

    public init(term: String, translation: String, sentence: String?, sentenceTranslation: String?,
                documentID: UUID, documentTitle: String, page: Int, date: Date) {
        id = UUID()
        self.term = term
        self.translation = translation
        self.sentence = sentence
        self.sentenceTranslation = sentenceTranslation
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.page = page
        lookups = 1
        firstLookedUp = date
        lastLookedUp = date
    }

    /// Same word in the same book, whatever the case or surrounding punctuation.
    public var key: String {
        documentID.uuidString + "|" + term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Looking the word up again keeps one entry, updated with the latest context.
    public mutating func merge(_ newer: SavedWord) {
        term = newer.term
        translation = newer.translation
        sentence = newer.sentence
        sentenceTranslation = newer.sentenceTranslation
        documentTitle = newer.documentTitle
        page = newer.page
        lookups += 1
        lastLookedUp = newer.lastLookedUp
    }
}

public enum WordExport {
    /// Plain Markdown, readable as is and easy to paste into an AI chat:
    /// one section per book, most recently read first.
    public static func markdown(_ words: [SavedWord], exportedOn date: String, languages: LanguagePair = .default) -> String {
        let from = label(languages.source), to = label(languages.target)
        var out = String(localized: "# Parole cercate in PencilReader\n\n")
        out += String(localized: "Esportate il \(date) · \(count(words.count))\n")
        let books = Dictionary(grouping: words, by: \.documentID)
            .values
            .map { $0.sorted { $0.lastLookedUp > $1.lastLookedUp } }
            .sorted { $0[0].lastLookedUp > $1[0].lastLookedUp }
        for book in books {
            out += "\n## \(book[0].documentTitle) (\(count(book.count)))\n\n"
            for word in book {
                out += "- **\(word.term)** → \(word.translation) · p. \(word.page + 1)"
                if word.lookups > 1 { out += " · " + String(localized: "cercata \(word.lookups) volte") }
                out += "\n"
                if let sentence = word.sentence { out += "  - \(from): \(sentence)\n" }
                if let translated = word.sentenceTranslation { out += "  - \(to): \(translated)\n" }
            }
        }
        return out
    }

    /// "EN", "IT": the language part of a code such as "en-GB".
    private static func label(_ code: String) -> String {
        String(code.prefix { $0 != "-" && $0 != "_" }).uppercased()
    }

    private static func count(_ n: Int) -> String { n == 1 ? String(localized: "1 parola") : String(localized: "\(n) parole") }
}
