package it.pencilreader.core

import org.junit.Test

class TranslationHighlighterTest {
    private fun context(text: String, selected: String): SentenceContext {
        val at = text.indexOf(selected)
        return SentenceContext(text, if (at < 0) null else Span(at, at + selected.length))
    }

    @Test fun marksSelectionWithQuotes() {
        val marked = TranslationHighlighter.marked(context("The aircraft entered a stall.", "stall"))
        expect(marked?.text == "The aircraft entered a “stall”.")
    }

    @Test fun picksUnusedQuotePair() {
        val marked = TranslationHighlighter.marked(context("He said “stall” twice, a stall.", "twice"))
        expect(marked?.open == '«')
    }

    @Test fun unmarkFindsHighlight() {
        val result = TranslationHighlighter.unmark("L'aereo è entrato in “stallo”.", '“', '”')
        expect(result?.text == "L'aereo è entrato in stallo.")
        expect(result?.let { it.highlight.of(it.text) } == "stallo")
    }

    @Test fun unmarkRejectsLostQuotes() {
        expect(TranslationHighlighter.unmark("L'aereo è entrato in stallo.", '“', '”') == null)
        expect(TranslationHighlighter.unmark("“a” e “b”", '“', '”') == null)
    }

    @Test fun fuzzyExactWord() {
        val s = "L'aereo è entrato in stallo quando l'angolo di attacco ha superato il valore critico."
        expect(TranslationHighlighter.fuzzyRange("stallo", s)?.of(s) == "stallo")
    }

    @Test fun fuzzyIgnoresArticlesAndInflection() {
        val s = "Gli stalli si verificano quando l'angolo di attacco supera il valore critico."
        expect(TranslationHighlighter.fuzzyRange("lo stallo", s)?.of(s) == "stalli")
    }

    @Test fun fuzzyMultiWordWithElision() {
        val s = "La portanza cresce con l'angolo d'attacco fino allo stallo."
        expect(TranslationHighlighter.fuzzyRange("angolo di attacco", s)?.of(s) == "angolo d'attacco")
    }

    @Test fun fuzzyPrefersExpectedPosition() {
        val s = "La resistenza indotta e la resistenza di forma."
        val range = TranslationHighlighter.fuzzyRange("resistenza", s, expectedPosition = 0.8)
        expect(range?.start == 27)
    }

    @Test fun fuzzyNoMatch() {
        expect(TranslationHighlighter.fuzzyRange("bancarella", "L'aereo è entrato in stallo.") == null)
    }
}
