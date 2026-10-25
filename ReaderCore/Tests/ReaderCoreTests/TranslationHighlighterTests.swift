import Testing
@testable import ReaderCore

struct TranslationHighlighterTests {
    private func context(_ text: String, _ selected: String) -> SentenceContext {
        SentenceContext(text: text, selection: text.range(of: selected))
    }

    @Test func marksSelectionWithQuotes() {
        let marked = TranslationHighlighter.marked(context("The aircraft entered a stall.", "stall"))
        #expect(marked?.text == "The aircraft entered a “stall”.")
    }

    @Test func picksUnusedQuotePair() {
        let marked = TranslationHighlighter.marked(context("He said “stall” twice, a stall.", "twice"))
        #expect(marked?.open == "«")
    }

    @Test func unmarkFindsHighlight() {
        let result = TranslationHighlighter.unmark("L'aereo è entrato in “stallo”.", open: "“", close: "”")
        #expect(result?.text == "L'aereo è entrato in stallo.")
        #expect(result.map { String($0.text[$0.highlight]) } == "stallo")
    }

    @Test func unmarkRejectsLostQuotes() {
        #expect(TranslationHighlighter.unmark("L'aereo è entrato in stallo.", open: "“", close: "”") == nil)
        #expect(TranslationHighlighter.unmark("“a” e “b”", open: "“", close: "”") == nil)
    }

    @Test func fuzzyExactWord() {
        let s = "L'aereo è entrato in stallo quando l'angolo di attacco ha superato il valore critico."
        #expect(TranslationHighlighter.fuzzyRange(of: "stallo", in: s).map { String(s[$0]) } == "stallo")
    }

    @Test func fuzzyIgnoresArticlesAndInflection() {
        let s = "Gli stalli si verificano quando l'angolo di attacco supera il valore critico."
        #expect(TranslationHighlighter.fuzzyRange(of: "lo stallo", in: s).map { String(s[$0]) } == "stalli")
    }

    @Test func fuzzyMultiWordWithElision() {
        let s = "La portanza cresce con l'angolo d'attacco fino allo stallo."
        #expect(TranslationHighlighter.fuzzyRange(of: "angolo di attacco", in: s).map { String(s[$0]) }
                == "angolo d'attacco")
    }

    @Test func fuzzyPrefersExpectedPosition() {
        let s = "La resistenza indotta e la resistenza di forma."
        let range = TranslationHighlighter.fuzzyRange(of: "resistenza", in: s, expectedPosition: 0.8)
        #expect(range.map { s.distance(from: s.startIndex, to: $0.lowerBound) } == 27)
    }

    @Test func fuzzyNoMatch() {
        #expect(TranslationHighlighter.fuzzyRange(of: "bancarella", in: "L'aereo è entrato in stallo.") == nil)
    }
}
