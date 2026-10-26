package it.pencilreader.core

import kotlin.math.abs

/// Geometria dei segni di studio: i tratti dell'evidenziatore agganciati a una riga di testo
/// ciascuno, e le sottolineature raddrizzate. Tutte le coordinate sono normalizzate sulla pagina,
/// [0,1] con l'origine in alto a sinistra, come quelle dell'OCR.
object StudyMarks {
    /// L'unica fascia di testo a cui è destinato un tratto di evidenziatore: mai più di una riga, anche
    /// quando una mano che trema sconfina sulle righe sopra o sotto.
    /// Con il testo della pagina, la riga su cui è passata la maggior parte del tratto, dalla prima parola
    /// toccata all'ultima; senza, o fuori dal testo, una fascia alta `fallbackHeight` (o l'altezza media
    /// delle righe della pagina) centrata sull'altezza mediana del tratto. Null per un tratto senza
    /// larghezza fuori dal testo.
    fun highlightBand(stroke: List<Point>, page: PageText?, fallbackHeight: Double): Rect? {
        if (stroke.isEmpty()) return null
        val minX = stroke.minOf { it.x }
        val maxX = stroke.maxOf { it.x }
        val ys = stroke.map { it.y }.sorted()
        val medianY = ys[ys.size / 2]
        if (page != null) {
            val line = mainLine(stroke, medianY, minX, maxX, page)
            if (line != null) {
                val touched = line.wordIDs.map { page.words[it] }.filter { it.rect.maxX >= minX && it.rect.minX <= maxX }
                val left = touched.firstOrNull()?.rect?.minX ?: minX
                val right = touched.lastOrNull()?.rect?.maxX ?: maxX
                return Rect(left, line.rect.minY, right - left, line.rect.height)
            }
        }
        if (maxX <= minX) return null
        var height = fallbackHeight
        if (page != null && page.lines.isNotEmpty()) {
            height = page.lines.sumOf { it.rect.height } / page.lines.size
        }
        return Rect(minX, medianY - height / 2, maxX - minX, height)
    }

    /// La riga che contiene più punti del tratto; a parità, la più vicina alla sua altezza mediana.
    internal fun mainLine(stroke: List<Point>, medianY: Double, minX: Double, maxX: Double, page: PageText): Line? {
        var best: Line? = null
        var bestCount = 0
        var bestDistance = 0.0
        for (line in page.lines) {
            if (line.rect.maxX < minX || line.rect.minX > maxX) continue
            // Un quarto di riga di margine sopra e sotto, perché il tratto raramente sta proprio a metà.
            val band = line.rect.insetBy(0.0, -line.rect.height * 0.25)
            val count = stroke.count { it.y >= band.minY && it.y <= band.maxY }
            if (count <= 0) continue
            val distance = abs(line.rect.midY - medianY)
            if (best == null || count > bestCount || (count == bestCount && distance < bestDistance)) {
                best = line
                bestCount = count
                bestDistance = distance
            }
        }
        return best
    }

    /// Un'evidenziatura dritta: i centri delle sue estremità arrotondate, e il suo spessore.
    /// A differenza del resto, in qualunque unità uguale sui due assi, come quella del disegno.
    data class Segment(val y: Double, val minX: Double, val maxX: Double, val height: Double)

    data class Merged(val segment: Segment, val absorbed: List<Int>)

    /// Una nuova evidenziatura unita a quelle dello stesso colore che tocca sulla sua riga,
    /// così ripassare sulle stesse parole non le scurisce mai.
    /// Restituisce il segmento unito, all'altezza del nuovo, e gli indici di `others` che ha preso.
    fun merge(segment: Segment, others: List<Segment>): Merged {
        var merged = segment
        val absorbed = mutableSetOf<Int>()
        var changed = true
        while (changed) {
            changed = false
            for ((i, other) in others.withIndex()) {
                if (i in absorbed) continue
                val sameLine = abs(other.y - merged.y) < minOf(other.height, merged.height) / 2
                // Le estremità arrotondate arrivano metà spessore oltre le estremità del segmento.
                val reach = (other.height + merged.height) / 2
                val touches = other.minX - merged.maxX < reach && merged.minX - other.maxX < reach
                if (!sameLine || !touches) continue
                merged = merged.copy(minX = minOf(merged.minX, other.minX), maxX = maxOf(merged.maxX, other.maxX))
                absorbed.add(i)
                changed = true
            }
        }
        return Merged(merged, absorbed.sorted())
    }

    /// Un tratto trasformato in un segmento orizzontale, dal punto più a sinistra al più a destra.
    /// Con il testo della pagina, sta appena sotto la riga sotto cui è stato tracciato.
    fun underline(stroke: List<Point>, page: PageText?): Pair<Point, Point>? {
        if (stroke.isEmpty()) return null
        val minX = stroke.minOf { it.x }
        val maxX = stroke.maxOf { it.x }
        if (maxX <= minX) return null
        val ys = stroke.map { it.y }.sorted()
        var y = ys[ys.size / 2]
        val line = page?.lines?.firstOrNull { line ->
            val r = line.rect
            r.maxX >= minX && r.minX <= maxX && y >= r.midY && y <= r.maxY + r.height * 0.6
        }
        if (line != null) y = line.rect.maxY + line.rect.height * 0.08
        return Point(minX, y) to Point(maxX, y)
    }
}
