package it.pencilreader.core

import org.junit.Test

class TextSearchTest {
    @Test fun findsEveryOccurrenceIgnoringCase() {
        val page = PageText(makeLines(listOf("Liquid hydrogen and liquid", "oxygen. LIQUID fuels.")))
        val matches = page.search("liquid")
        expect(matches.size == 3)
        expect(matches.map { it.wordIDs } == listOf(listOf(0), listOf(3), listOf(5)))
        for (match in matches) expect(match.highlight.of(match.snippet).lowercase() == "liquid")
    }

    @Test fun findsWordHyphenatedAcrossLines() {
        val page = PageText(makeLines(listOf("The aero-", "dynamic force")))
        val matches = page.search("aerodynamic")
        expect(matches.size == 1)
        expect(matches[0].wordIDs == listOf(1, 2))
    }

    @Test fun findsPhraseSpanningLines() {
        val page = PageText(makeLines(listOf("exceeded the angle", "of attack limit")))
        val matches = page.search("angle of attack")
        expect(matches.map { it.wordIDs } == listOf(listOf(2, 3, 4)))
        expect(matches[0].highlight.of(matches[0].snippet) == "angle of attack")
    }

    @Test fun ignoresAccents() {
        val page = PageText(makeLines(listOf("Die Rakete zu den Planetenräumen")))
        expect(page.search("planetenraumen").size == 1)
        expect(page.search("PLANETENRÄUMEN").size == 1)
    }

    @Test fun shortensLongSnippetsAtWordBoundaries() {
        val words = (1..40).map { "word$it" }
        val page = PageText(makeLines(listOf(words.joinToString(" "))))
        val match = page.search("word20", snippetRadius = 20)[0]
        expect(match.snippet.startsWith("…word"), match.snippet)
        expect(match.snippet.endsWith("…"))
        expect(!match.snippet.contains("  "))
        expect(match.highlight.of(match.snippet) == "word20")
    }

    @Test fun emptyQueryFindsNothing() {
        val page = PageText(makeLines(listOf("Some text")))
        expect(page.search("  ").isEmpty())
    }
}
