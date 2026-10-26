package it.pencilreader.core

import kotlinx.serialization.Serializable
import java.text.BreakIterator
import java.util.Locale

/// Una parola come la dà l'OCR. `rect` è normalizzato in [0,1], origine in alto a sinistra.
@Serializable
data class RawWord(val text: String, val rect: Rect)

/// Una riga di testo come la dà l'OCR, in ordine di lettura.
@Serializable
data class RawLine(val text: String, val rect: Rect, val words: List<RawWord>)

data class Word(val id: Int, val text: String, val rect: Rect, val lineIndex: Int)

/// `wordIDs` va da `firstWord` (compreso) a `endWord` (escluso).
data class Line(val rect: Rect, val wordIDs: IntRange, val blockIndex: Int)

/// Righe consecutive dello stesso paragrafo o colonna, unite in testo continuo.
data class Block(
    val text: String,
    /// Dove sta, dentro `text`, ogni parola del blocco, per id.
    val wordRanges: Map<Int, Span>,
)

/// La frase attorno a una selezione, e dove sta la selezione al suo interno.
data class SentenceContext(val text: String, val selection: Span?) {
    /// Il centro della selezione come frazione della lunghezza della frase.
    val selectionPosition: Double?
        get() {
            val s = selection ?: return null
            if (text.isEmpty()) return null
            return (s.start + s.end).toDouble() / 2 / text.length
        }
}

/// Tutto quello che è stato riconosciuto su una pagina, indicizzato per ricerche rapide a ogni lazo.
class PageText(rawLines: List<RawLine>) {
    /// Il risultato dell'OCR da cui è costruita: si salva questo e si ricostruisce con il costruttore.
    val rawLines: List<RawLine> = rawLines.filter { it.words.isNotEmpty() }
    val words: List<Word>
    val lines: List<Line>
    val blocks: List<Block>

    init {
        val raw = this.rawLines
        val blockOfLine = groupIntoBlocks(raw.map { it.rect })
        val w = mutableListOf<Word>()
        val l = mutableListOf<Line>()
        for ((li, rawLine) in raw.withIndex()) {
            val start = w.size
            for (rw in rawLine.words) w.add(Word(w.size, rw.text, rw.rect, li))
            l.add(Line(rawLine.rect, start until w.size, blockOfLine[li]))
        }
        val b = mutableListOf<Block>()
        var li = 0
        while (li < l.size) {
            var end = li
            while (end < l.size && l[end].blockIndex == l[li].blockIndex) end += 1
            b.add(makeBlock(l.subList(li, end), w))
            li = end
        }
        words = w
        lines = l
        blocks = b
    }

    // Domande

    /// Le parole selezionate come una stringa: riunisce le parole spezzate a fine riga
    /// e toglie la punteggiatura attorno ("stall," -> "stall").
    fun text(ids: List<Int>): String {
        val sorted = ids.toSortedSet().toList()
        val out = StringBuilder()
        for ((k, id) in sorted.withIndex()) {
            val next = if (k + 1 < sorted.size) sorted[k + 1] else null
            if (next != null && next == id + 1 && joinsWithNextLine(id)) {
                out.append(words[id].text.dropLast(1))
            } else {
                out.append(words[id].text)
                if (next != null) out.append(' ')
            }
        }
        return out.toString().trim { isTrimmed(it) }
    }

    /// La frase (o le frasi) che contengono la selezione, e dove sta la selezione al loro interno
    /// (cercata solo nel primo blocco quando ne attraversa più d'uno).
    fun contextSentences(ids: List<Int>): SentenceContext? {
        val parts = mutableListOf<String>()
        var selectionOffsets: Pair<Int, Int>? = null
        val byBlock = ids.toSet().groupBy { lines[words[it].lineIndex].blockIndex }
        for (blockIndex in byBlock.keys.sorted()) {
            val block = blocks[blockIndex]
            val ranges = byBlock.getValue(blockIndex).mapNotNull { block.wordRanges[it] }
            val lower = ranges.minOfOrNull { it.start } ?: continue
            val upper = ranges.maxOfOrNull { it.end } ?: continue
            val text = block.text

            var start: Int? = null
            var end: Int? = null
            val sentences = BreakIterator.getSentenceInstance(Locale.ENGLISH)
            sentences.setText(text)
            var s = sentences.first()
            var e = sentences.next()
            while (e != BreakIterator.DONE) {
                if (e > lower && s < upper) {
                    if (start == null) start = s
                    end = e
                }
                if (s >= upper) break
                s = e
                e = sentences.next()
            }
            var st = start ?: continue
            var en = end ?: continue
            while (st < en && text[st].isWhitespace()) st += 1
            while (en > st && text[en - 1].isWhitespace()) en -= 1

            if (parts.isEmpty()) {
                // Stessa pulizia della punteggiatura di `text(ids)`.
                var lo = maxOf(lower, st)
                var hi = minOf(upper, en)
                while (lo < hi && isTrimmed(text[lo])) lo += 1
                while (hi > lo && isTrimmed(text[hi - 1])) hi -= 1
                if (lo < hi) selectionOffsets = (lo - st) to (hi - st)
            }
            parts.add(text.substring(st, en))
        }
        if (parts.isEmpty()) return null
        val joined = parts.joinToString(" … ")
        return SentenceContext(joined, selectionOffsets?.let { Span(it.first, it.second) })
    }

    /// Vero quando la parola `id` chiude la riga con un trattino e continua sulla successiva.
    private fun joinsWithNextLine(id: Int): Boolean {
        val word = words[id]
        if (id + 1 >= words.size) return false
        if (lines[word.lineIndex].wordIDs.last != id) return false
        if (word.text.length <= 1 || word.text.last() !in HYPHENS) return false
        val next = words[id + 1]
        return next.lineIndex == word.lineIndex + 1 &&
            lines[next.lineIndex].blockIndex == lines[word.lineIndex].blockIndex &&
            next.text.firstOrNull()?.isLowerCase() == true
    }

    companion object {
        private val HYPHENS = setOf('-', '­', '‐')
        private const val TRIMMED_PUNCTUATION = ".,;:!?\"“”‘’()[]{}«»"

        internal fun isTrimmed(c: Char) = c.isWhitespace() || c in TRIMMED_PUNCTUATION

        private fun makeBlock(blockLines: List<Line>, words: List<Word>): Block {
            val text = StringBuilder()
            val offsets = mutableMapOf<Int, Span>()
            val ids = blockLines.flatMap { it.wordIDs.toList() }
            val lineEnds = blockLines.mapNotNull { if (it.wordIDs.isEmpty()) null else it.wordIDs.last }.toSet()
            for ((k, id) in ids.withIndex()) {
                val word = words[id]
                val isLineEnd = id in lineEnds
                val nextWord = if (k + 1 < ids.size) words[ids[k + 1]] else null
                val hyphenated = isLineEnd && word.text.length > 1 &&
                    word.text.last() in HYPHENS &&
                    nextWord?.text?.firstOrNull()?.isLowerCase() == true
                val piece = if (hyphenated) word.text.dropLast(1) else word.text
                val start = text.length
                text.append(piece)
                offsets[id] = Span(start, text.length)
                if (!hyphenated && nextWord != null) text.append(' ')
            }
            return Block(text.toString(), offsets)
        }

        /// Assegna un numero di blocco a ogni riga (in ordine di lettura). Un nuovo blocco comincia
        /// con un grande spazio verticale, quando si torna su, o con un cambio di colonna.
        fun groupIntoBlocks(rects: List<Rect>): List<Int> {
            if (rects.isEmpty()) return emptyList()
            val heights = rects.map { it.height }.sorted()
            val lineHeight = heights[heights.size / 2]
            val result = mutableListOf(0)
            var block = 0
            for (i in 1 until rects.size) {
                val prev = rects[i - 1]
                val cur = rects[i]
                val gap = cur.minY - prev.maxY
                val overlap = minOf(prev.maxX, cur.maxX) - maxOf(prev.minX, cur.minX)
                val narrower = minOf(prev.width, cur.width)
                val sameColumn = narrower > 0 && overlap / narrower > 0.3
                if (gap > lineHeight * 0.9 || gap < -lineHeight * 0.5 || !sameColumn) block += 1
                result.add(block)
            }
            return result
        }
    }
}
