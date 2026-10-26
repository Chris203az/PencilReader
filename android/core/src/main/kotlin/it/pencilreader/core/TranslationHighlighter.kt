package it.pencilreader.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/// Trova quale parte di una frase tradotta corrisponde alle parole cerchiate.
/// Il traduttore non dà l'allineamento parola per parola, quindi due strategie:
/// mettere la selezione tra virgolette prima di tradurre e cercarle dopo, oppure
/// cercare il termine tradotto a parte dentro la frase tradotta.
object TranslationHighlighter {
    data class Marked(val text: String, val open: Char, val close: Char)

    data class Unmarked(val text: String, val highlight: Span)

    /// La frase con la selezione tra una coppia di virgolette che la frase non usa già.
    fun marked(context: SentenceContext): Marked? {
        val selection = context.selection ?: return null
        val pairs = listOf('“' to '”', '«' to '»', '[' to ']')
        val (open, close) = pairs.firstOrNull { (o, c) -> o !in context.text && c !in context.text } ?: return null
        val t = context.text
        val text = t.substring(0, selection.start) + open + t.substring(selection.start, selection.end) +
            close + t.substring(selection.end)
        return Marked(text, open, close)
    }

    /// Toglie dalla traduzione la coppia di virgolette messa da `marked` e restituisce cosa c'era dentro.
    /// Null quando la coppia non è arrivata intatta.
    fun unmark(translation: String, open: Char, close: Char): Unmarked? {
        if (translation.count { it == open } != 1 || translation.count { it == close } != 1) return null
        val o = translation.indexOf(open)
        val c = translation.indexOf(close)
        if (o < 0 || c < 0 || o >= c) return null
        val before = translation.substring(0, o)
        val inside = translation.substring(o + 1, c)
        val after = translation.substring(c + 1)
        val core = inside.trim { it == ' ' || it == '\t' }
        if (core.isEmpty()) return null
        val text = before + core + after
        return Unmarked(text, Span(before.length, before.length + core.length))
    }

    /// Il punto di `sentence` che corrisponde meglio a `term`, tollerante alle desinenze italiane
    /// ("stallo"/"stalli") e ad articoli e preposizioni attorno.
    fun fuzzyRange(term: String, sentence: String, expectedPosition: Double? = null): Span? {
        val termTokens = tokens(term).map { it.normalized }
        val content = termTokens.filter { it !in STOPWORDS }
        val wanted = content.ifEmpty { termTokens }
        val words = tokens(sentence)
        if (wanted.isEmpty() || words.isEmpty()) return null

        var bestScore = 0.0
        var bestDistance = 0.0
        var bestRange: Span? = null
        val maxWindow = wanted.size + 2
        for (start in words.indices) {
            for (length in 1..maxWindow) {
                if (start + length > words.size) continue
                // Ogni token cercato prende la sua corrispondenza migliore nella finestra.
                var total = 0.0
                val matched = mutableListOf<Int>()
                for (w in wanted) {
                    var topIndex = -1
                    var topScore = 0.0
                    for (j in start until start + length) {
                        val s = similarity(w, words[j].normalized)
                        if (topIndex < 0 || s > topScore) {
                            topIndex = j
                            topScore = s
                        }
                    }
                    if (topIndex >= 0 && topScore > 0) {
                        total += topScore
                        matched.add(topIndex)
                    }
                }
                val score = total / wanted.size
                val first = matched.minOrNull()
                val last = matched.maxOrNull()
                if (score < 0.6 || first == null || last == null || first != start || last != start + length - 1) continue
                val position = start.toDouble() / words.size
                val dist = expectedPosition?.let { abs(it - position) } ?: 0.0
                val range = Span(words[first].range.start, words[last].range.end)
                if (bestRange == null || score > bestScore + 0.01 ||
                    (abs(score - bestScore) <= 0.01 && dist < bestDistance)
                ) {
                    bestScore = score
                    bestDistance = dist
                    bestRange = range
                }
            }
        }
        return bestRange
    }

    private data class Token(val range: Span, val normalized: String)

    /// Sequenze di lettere e cifre; gli apostrofi separano le elisioni ("dell'angolo" -> "dell", "angolo").
    private fun tokens(s: String): List<Token> {
        val result = mutableListOf<Token>()
        var start = -1
        fun flush(end: Int) {
            if (start >= 0) {
                result.add(Token(Span(start, end), TextFolding.fold(s.substring(start, end))))
                start = -1
            }
        }
        for (i in s.indices) {
            if (s[i].isLetterOrDigit()) {
                if (start < 0) start = i
            } else {
                flush(i)
            }
        }
        flush(s.length)
        return result
    }

    private fun similarity(a: String, b: String): Double {
        if (a == b) return 1.0
        val minLength = min(a.length, b.length)
        if (minLength < 4) return 0.0
        var prefix = 0
        while (prefix < minLength && a[prefix] == b[prefix]) prefix += 1
        return if (prefix >= max(4, minLength - 2)) 0.85 else 0.0
    }

    private val STOPWORDS = setOf(
        "il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "di", "del", "dello", "della",
        "dei", "degli", "delle", "dell", "d", "a", "al", "allo", "alla", "ai", "agli", "alle", "all",
        "da", "dal", "dallo", "dalla", "dai", "dagli", "dalle", "dall", "in", "nel", "nello", "nella",
        "nei", "negli", "nelle", "nell", "con", "su", "sul", "sullo", "sulla", "sui", "sugli", "sulle",
        "sull", "per", "tra", "fra", "e", "ed", "o", "che",
    )
}
