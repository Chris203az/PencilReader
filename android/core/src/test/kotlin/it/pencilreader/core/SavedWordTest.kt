package it.pencilreader.core

import org.junit.Test
import java.util.UUID

private val book = UUID.randomUUID().toString()

private fun word(
    term: String, translation: String, page: Int = 0, at: Long = 0,
    document: String = book, title: String = "ignition",
) = SavedWord(
    term = term, translation = translation, sentence = "The $term here.",
    sentenceTranslation = "Il $translation qui.", documentID = document, documentTitle = title,
    page = page, firstLookedUp = at * 1000,
)

class SavedWordTest {
    @Test fun keyIgnoresCaseAndAccentsButNotBook() {
        expect(word("Stall", "stallo").key == word("stall", "stallo").key)
        expect(word("Stàll", "stallo").key == word("stall", "stallo").key)
        expect(word("stall", "stallo").key != word("stall", "stallo", document = UUID.randomUUID().toString()).key)
    }

    @Test fun mergeKeepsOneEntryWithLatestContext() {
        val saved = word("stall", "stallo", page = 3, at = 10).merge(word("stall", "lo stallo", page = 20, at = 50))
        expect(saved.lookups == 2)
        expect(saved.page == 20)
        expect(saved.translation == "lo stallo")
        expect(saved.firstLookedUp == 10_000L)
        expect(saved.lastLookedUp == 50_000L)
    }

    @Test fun markdownGroupsByBookMostRecentFirst() {
        val other = UUID.randomUUID().toString()
        val thrust = word("thrust", "spinta", page = 4, at = 30).copy(lookups = 3)
        val text = WordExport.markdown(listOf(
            word("nozzle", "ugello", page = 1, at = 10, document = other, title = "Rocket Propulsion"),
            word("stall", "stallo", page = 20, at = 20),
            thrust,
        ), exportedOn = "25 ottobre 2026")

        expect(text.contains("Esportate il 25 ottobre 2026 · 3 parole"))
        expect(text.contains("## ignition (2 parole)"))
        expect(text.contains("## Rocket Propulsion (1 parola)"))
        expect(text.indexOf("## ignition") < text.indexOf("## Rocket Propulsion"))
        expect(text.indexOf("**thrust**") < text.indexOf("**stall**"))
        expect(text.contains("- **thrust** → spinta · p. 5 · cercata 3 volte\n  - EN: The thrust here.\n  - IT: Il spinta qui.\n"))
        expect(text.contains("- **stall** → stallo · p. 21\n"))
    }
}
