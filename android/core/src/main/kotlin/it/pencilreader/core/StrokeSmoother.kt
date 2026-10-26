package it.pencilreader.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot

/// Toglie il tremolio da un tratto scritto a mano senza spostarlo: ogni punto resta entro `MAX_SHIFT`
/// da dove l'ha messo la penna (`SHORT_MAX_SHIFT` sui tratti corti), le estremità e gli angoli restano
/// esattamente dove sono, e i tratti corti come punti, accenti e piccoli indici non si toccano.
object StrokeSmoother {
    /// I tratti con meno punti di così non si toccano mai.
    const val MIN_POINTS = 10
    /// I tratti più corti di così, lungo il percorso, non si toccano mai.
    const val MIN_LENGTH = 8.0
    /// Il massimo che un punto si può spostare, salvo indicazione diversa.
    const val MAX_SHIFT = 3.0
    /// Le intensità possibili, come massimo spostamento di un punto.
    val strengths = 1.0..4.0
    /// Il massimo spostamento su un tratto più corto di `SHORT_LENGTH`, come una lettera piccola.
    const val SHORT_MAX_SHIFT = 1.0
    const val SHORT_LENGTH = 20.0
    /// Una svolta più brusca di così, in gradi, è un angolo voluto, e resta ferma.
    const val CORNER_ANGLE = 40.0

    /// Pesi della media mobile, centrata sul punto da levigare.
    private val weights = doubleArrayOf(1.0, 2.0, 3.0, 4.0, 3.0, 2.0, 1.0)
    /// Per le intensità più forti: un tratto più ampio, così vanno via anche le ondulazioni lente.
    private val wideWeights = doubleArrayOf(1.0, 2.0, 3.0, 4.0, 5.0, 4.0, 3.0, 2.0, 1.0)

    /// I punti del tratto levigati, tanti quanti erano e nello stesso ordine, nessuno spostato più di
    /// `strength` (`SHORT_MAX_SHIFT` sui tratti corti); null quando il tratto è troppo corto per levigarlo
    /// senza rischi o non cambierebbe nulla. Un'intensità maggiore fa anche la media su un tratto più ampio.
    fun smoothed(points: List<Point>, strength: Double = MAX_SHIFT): List<Point>? {
        val s = strength.coerceIn(strengths.start, strengths.endInclusive)
        val w = if (s >= 3) wideWeights else weights
        val length = pathLength(points)
        if (points.size < MIN_POINTS || length < MIN_LENGTH) return null
        val limit = if (length < SHORT_LENGTH) minOf(SHORT_MAX_SHIFT, s) else s
        val fixed = fixedIndices(points)
        val result = points.toMutableList()
        var changed = false
        val half = w.size / 2
        for (i in points.indices) {
            if (i in fixed) continue
            // La media non scavalca mai un punto fermo, così gli angoli restano netti, ed è larga uguale
            // dalle due parti, così un tratto dritto o curvo in modo regolare resta esattamente dov'è.
            var reach = 0
            while (reach < half && (i - reach) !in fixed && (i + reach) !in fixed) reach += 1
            var sx = 0.0
            var sy = 0.0
            var total = 0.0
            for (j in (i - reach)..(i + reach)) {
                val weight = w[j - i + half]
                sx += points[j].x * weight
                sy += points[j].y * weight
                total += weight
            }
            var target = Point(sx / total, sy / total)
            val dx = target.x - points[i].x
            val dy = target.y - points[i].y
            val shift = hypot(dx, dy)
            if (shift > limit) target = Point(points[i].x + dx / shift * limit, points[i].y + dy / shift * limit)
            if (shift > 0.01) changed = true
            result[i] = target
        }
        return if (changed) result else null
    }

    /// Le due estremità, e ogni punto dove il tratto gira più bruscamente di `CORNER_ANGLE`.
    /// La svolta si misura su due punti per parte, così il tremolio della penna non conta.
    internal fun fixedIndices(points: List<Point>): Set<Int> {
        if (points.size <= 4) return points.indices.toSet()
        val fixed = mutableSetOf(0, points.size - 1)
        for (i in 2 until points.size - 2) {
            val a = points[i - 2]
            val b = points[i]
            val c = points[i + 2]
            val incoming = atan2(b.y - a.y, b.x - a.x)
            val outgoing = atan2(c.y - b.y, c.x - b.x)
            var turn = abs(outgoing - incoming)
            if (turn > PI) turn = 2 * PI - turn
            if (turn * 180 / PI > CORNER_ANGLE) fixed.add(i)
        }
        return fixed
    }

    fun pathLength(points: List<Point>): Double {
        var sum = 0.0
        for (i in 0 until points.size - 1) sum += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        return sum
    }
}
