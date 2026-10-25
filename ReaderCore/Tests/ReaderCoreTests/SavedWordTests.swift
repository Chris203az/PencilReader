import Foundation
import Testing
@testable import ReaderCore

private let book = UUID()

private func word(_ term: String, _ translation: String, page: Int = 0, at seconds: TimeInterval = 0,
                  document: UUID = book, title: String = "ignition") -> SavedWord {
    SavedWord(term: term, translation: translation, sentence: "The \(term) here.",
              sentenceTranslation: "Il \(translation) qui.", documentID: document, documentTitle: title,
              page: page, date: Date(timeIntervalSince1970: seconds))
}

struct SavedWordTests {
    @Test func keyIgnoresCaseAndAccentsButNotBook() {
        #expect(word("Stall", "stallo").key == word("stall", "stallo").key)
        #expect(word("stall", "stallo").key != word("stall", "stallo", document: UUID()).key)
    }

    @Test func mergeKeepsOneEntryWithLatestContext() {
        var saved = word("stall", "stallo", page: 3, at: 10)
        saved.merge(word("stall", "lo stallo", page: 20, at: 50))
        #expect(saved.lookups == 2)
        #expect(saved.page == 20)
        #expect(saved.translation == "lo stallo")
        #expect(saved.firstLookedUp == Date(timeIntervalSince1970: 10))
        #expect(saved.lastLookedUp == Date(timeIntervalSince1970: 50))
    }

    @Test func markdownGroupsByBookMostRecentFirst() {
        let other = UUID()
        var thrust = word("thrust", "spinta", page: 4, at: 30)
        thrust.lookups = 3
        let text = WordExport.markdown([
            word("nozzle", "ugello", page: 1, at: 10, document: other, title: "Rocket Propulsion"),
            word("stall", "stallo", page: 20, at: 20),
            thrust
        ], exportedOn: "25 ottobre 2026")

        #expect(text.contains("Esportate il 25 ottobre 2026 · 3 parole"))
        #expect(text.contains("## ignition (2 parole)"))
        #expect(text.contains("## Rocket Propulsion (1 parola)"))
        #expect(text.range(of: "## ignition")!.lowerBound < text.range(of: "## Rocket Propulsion")!.lowerBound)
        #expect(text.range(of: "**thrust**")!.lowerBound < text.range(of: "**stall**")!.lowerBound)
        #expect(text.contains("- **thrust** → spinta · p. 5 · cercata 3 volte\n  - EN: The thrust here.\n  - IT: Il spinta qui.\n"))
        #expect(text.contains("- **stall** → stallo · p. 21\n"))
    }
}
