package it.pencilreader.core

import java.text.Normalizer

/// Un intervallo di caratteri [start, end) dentro una stringa (indici UTF-16, come `String` di Kotlin).
data class Span(val start: Int, val end: Int) {
    val length get() = end - start
    fun of(text: String): String = text.substring(start, end)
    fun overlaps(o: Span): Boolean = start < o.end && o.start < end && length > 0 && o.length > 0
}

/// Confronti che ignorano maiuscole e accenti, come le opzioni
/// `.caseInsensitive` e `.diacriticInsensitive` di Foundation.
object TextFolding {
    private val marks = Regex("\\p{Mn}+")

    /// Minuscolo e senza accenti.
    fun fold(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFD).replace(marks, "").lowercase()

    /// Il testo piegato, e per ogni suo carattere l'indice del carattere originale da cui viene.
    private fun foldWithMap(s: String): Pair<String, IntArray> {
        val out = StringBuilder()
        val map = ArrayList<Int>(s.length)
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            val len = Character.charCount(cp)
            val folded = fold(s.substring(i, i + len))
            for (ch in folded) {
                out.append(ch)
                map.add(i)
            }
            i += len
        }
        return out.toString() to map.toIntArray()
    }

    /// Tutte le occorrenze di `needle` in `text`, senza sovrapporsi, come intervalli del testo originale.
    fun findAll(needle: String, text: String): List<Span> {
        val foldedNeedle = fold(needle)
        if (foldedNeedle.isEmpty()) return emptyList()
        val (hay, map) = foldWithMap(text)
        val result = mutableListOf<Span>()
        var from = 0
        while (true) {
            val at = hay.indexOf(foldedNeedle, from)
            if (at < 0) break
            val last = at + foldedNeedle.length - 1
            val start = map[at]
            val lastOrig = map[last]
            val end = lastOrig + Character.charCount(text.codePointAt(lastOrig))
            result.add(Span(start, end))
            from = at + foldedNeedle.length
        }
        return result
    }
}
