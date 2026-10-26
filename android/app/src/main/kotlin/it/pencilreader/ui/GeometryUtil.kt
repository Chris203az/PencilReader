package it.pencilreader.ui

import it.pencilreader.core.Point
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/// La distanza di `p` dal segmento da `a` a `b`.
fun segmentDistance(p: Point, a: Point, b: Point): Double {
    val dx = b.x - a.x
    val dy = b.y - a.y
    val len2 = dx * dx + dy * dy
    var t = 0.0
    if (len2 > 0) t = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

/// La distanza di `p` dalla spezzata aperta `points`.
fun polylineDistance(p: Point, points: List<Point>): Double {
    if (points.isEmpty()) return Double.POSITIVE_INFINITY
    if (points.size == 1) return hypot(points[0].x - p.x, points[0].y - p.y)
    var best = Double.POSITIVE_INFINITY
    for (i in 0 until points.size - 1) best = min(best, segmentDistance(p, points[i], points[i + 1]))
    return best
}
