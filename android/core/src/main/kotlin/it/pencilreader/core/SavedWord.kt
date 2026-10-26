package it.pencilreader.core

import kotlinx.serialization.Serializable
import java.util.UUID

/// Una parola o un'espressione cerchiata leggendo, con la traduzione e dove è stata trovata.
@Serializable
data class SavedWord(
    val id: String = UUID.randomUUID().toString(),
    val term: String,
    /// L'italiano del termine come è usato nella frase (o da solo quando non si è trovato nella frase).
    val translation: String,
    val sentence: String? = null,
    val sentenceTranslation: String? = null,
    val documentID: String,
    val documentTitle: String,
    /// Pagina, da zero, dell'ultima ricerca.
    val page: Int,
    val lookups: Int = 1,
    /// Millisecondi dal 1970.
    val firstLookedUp: Long,
    val lastLookedUp: Long = firstLookedUp,
) {
    /// La stessa parola nello stesso libro, qualunque siano maiuscole o accenti.
    val key: String get() = documentID + "|" + TextFolding.fold(term)

    /// Cercare di nuovo la parola tiene una sola voce, aggiornata con il contesto più recente.
    fun merge(newer: SavedWord): SavedWord = copy(
        term = newer.term,
        translation = newer.translation,
        sentence = newer.sentence,
        sentenceTranslation = newer.sentenceTranslation,
        documentTitle = newer.documentTitle,
        page = newer.page,
        lookups = lookups + 1,
        lastLookedUp = newer.lastLookedUp,
    )
}

object WordExport {
    /// Markdown semplice, leggibile così com'è e facile da incollare in una chat con un'IA:
    /// una sezione per libro, prima quello letto più di recente.
    fun markdown(words: List<SavedWord>, exportedOn: String): String {
        val out = StringBuilder("# Parole cercate in PencilReader\n\n")
        out.append("Esportate il $exportedOn · ${count(words.size)}\n")
        val books = words.groupBy { it.documentID }.values
            .map { book -> book.sortedByDescending { it.lastLookedUp } }
            .sortedByDescending { it[0].lastLookedUp }
        for (book in books) {
            out.append("\n## ${book[0].documentTitle} (${count(book.size)})\n\n")
            for (word in book) {
                out.append("- **${word.term}** → ${word.translation} · p. ${word.page + 1}")
                if (word.lookups > 1) out.append(" · cercata ${word.lookups} volte")
                out.append("\n")
                word.sentence?.let { out.append("  - EN: $it\n") }
                word.sentenceTranslation?.let { out.append("  - IT: $it\n") }
            }
        }
        return out.toString()
    }

    private fun count(n: Int) = if (n == 1) "1 parola" else "$n parole"
}
