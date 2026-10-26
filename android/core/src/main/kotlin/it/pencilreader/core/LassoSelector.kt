package it.pencilreader.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/// Decide a quali parole si riferisce un tratto fatto a mano con la penna.
///
/// Funziona in qualunque spazio cartesiano con la y verso il basso, purché il tratto e i
/// rettangoli delle parole lo condividano (nell'app: i pixel della vista).
///
/// - Anello (cerchio, ovale, "C" aperta): il tratto si chiude unendone le estremità. Una parola
///   è scelta se il suo centro è dentro, o se più di metà sta dentro il contorno allargato di poco.
/// - Linea (sottolineatura o barratura): le parole coperte in orizzontale dal tratto, sulla riga
///   di testo più vicina al tratto.
object LassoSelector {
    /// Gli indici in `wordRects` delle parole scelte, in ordine crescente.
    fun select(stroke: List<Point>, wordRects: List<Rect>): List<Int> {
        val pts = decimate(stroke, 200)
        if (pts.size < 2 || wordRects.isEmpty()) return emptyList()

        val lineHeight = median(wordRects.map { it.height })
        val bounds = Rect.bounding(pts)
        val area = abs(PolygonMath.signedArea(pts))
        val isLine = bounds.height < lineHeight * 0.7 || area < bounds.width * bounds.height * 0.25

        val selected = if (isLine) selectAlongLine(pts, bounds, wordRects, lineHeight)
        else selectInsideLoop(pts, bounds, wordRects, lineHeight)
        if (selected.isNotEmpty()) return selected

        // Un anellino o un segno minuscolo sopra una sola parola.
        val center = Point(bounds.midX, bounds.midY)
        val slack = lineHeight * 0.15
        val hit = wordRects.indexOfFirst { it.insetBy(-slack, -slack).contains(center) }
        return if (hit >= 0) listOf(hit) else emptyList()
    }

    private fun selectInsideLoop(poly: List<Point>, bounds: Rect, rects: List<Rect>, lineHeight: Double): List<Int> {
        val tolerance = lineHeight * 0.15
        val searchArea = bounds.insetBy(-tolerance, -tolerance)
        fun insideOrNear(p: Point) = PolygonMath.contains(p, poly) || PolygonMath.distance(p, poly) <= tolerance

        val selected = mutableListOf<Int>()
        for ((i, r) in rects.withIndex()) {
            if (!r.intersects(searchArea)) continue
            if (PolygonMath.contains(Point(r.midX, r.midY), poly)) {
                selected.add(i)
                continue
            }
            var hits = 0
            var total = 0
            for (fx in doubleArrayOf(0.1, 0.3, 0.5, 0.7, 0.9)) {
                for (fy in doubleArrayOf(0.2, 0.5, 0.8)) {
                    total += 1
                    if (insideOrNear(Point(r.minX + fx * r.width, r.minY + fy * r.height))) hits += 1
                }
            }
            if (hits * 2 > total) selected.add(i)
        }
        return selected
    }

    private fun selectAlongLine(stroke: List<Point>, bounds: Rect, rects: List<Rect>, lineHeight: Double): List<Int> {
        val candidates = mutableListOf<Pair<Int, Double>>()
        for ((i, r) in rects.withIndex()) {
            val overlap = min(r.maxX, bounds.maxX) - max(r.minX, bounds.minX)
            if (overlap < r.width * 0.5) continue
            val y = strokeY(min(max(r.midX, bounds.minX), bounds.maxX), stroke)
            val score = when {
                y < r.minY -> (r.minY - y) * 5 // un tratto sopra una parola raramente la indica
                y > r.maxY -> y - r.maxY // sottolineatura
                else -> 0.0 // barratura
            }
            if (score <= lineHeight * 0.6) candidates.add(i to score)
        }
        val best = candidates.minOfOrNull { it.second } ?: return emptyList()
        return candidates.filter { it.second <= best + lineHeight * 0.25 }.map { it.first }
    }

    private fun strokeY(x: Double, stroke: List<Point>): Double =
        stroke.minByOrNull { abs(it.x - x) }?.y ?: 0.0

    private fun decimate(pts: List<Point>, maxPoints: Int): List<Point> {
        if (pts.size <= maxPoints) return pts
        val step = (pts.size - 1).toDouble() / (maxPoints - 1)
        return (0 until maxPoints).map { pts[roundHalfAway(it * step).toInt()] }
    }

    private fun median(values: List<Double>): Double {
        val sorted = values.sorted()
        return if (sorted.isEmpty()) 0.0 else sorted[sorted.size / 2]
    }
}
