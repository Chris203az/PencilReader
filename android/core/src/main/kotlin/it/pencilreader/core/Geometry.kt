package it.pencilreader.core

import kotlinx.serialization.Serializable
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/// Geometria di base, con la y che cresce verso il basso come su schermo.
/// Equivalenti di CGPoint, CGSize, CGRect e CGAffineTransform, con la stessa semantica.

@Serializable
data class Point(val x: Double, val y: Double) {
    fun applying(t: AffineTransform): Point =
        Point(t.a * x + t.c * y + t.tx, t.b * x + t.d * y + t.ty)

    operator fun plus(o: Point) = Point(x + o.x, y + o.y)
    operator fun minus(o: Point) = Point(x - o.x, y - o.y)

    companion object {
        val ZERO = Point(0.0, 0.0)
    }
}

@Serializable
data class Size(val width: Double, val height: Double)

/// Rettangolo con origine in alto a sinistra. `NULL` è il rettangolo vuoto di CoreGraphics.
@Serializable
data class Rect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val isNull: Boolean get() = x.isInfinite() && y.isInfinite()
    val minX get() = min(x, x + width)
    val maxX get() = max(x, x + width)
    val minY get() = min(y, y + height)
    val maxY get() = max(y, y + height)
    val midX get() = (minX + maxX) / 2
    val midY get() = (minY + maxY) / 2
    val center get() = Point(midX, midY)
    val isEmpty get() = isNull || width == 0.0 || height == 0.0

    fun standardized(): Rect = if (isNull) this else Rect(minX, minY, abs(width), abs(height))

    fun insetBy(dx: Double, dy: Double): Rect {
        if (isNull) return this
        val s = standardized()
        val w = s.width - 2 * dx
        val h = s.height - 2 * dy
        if (w < 0 || h < 0) return NULL
        return Rect(s.x + dx, s.y + dy, w, h)
    }

    fun offsetBy(dx: Double, dy: Double) = if (isNull) this else Rect(x + dx, y + dy, width, height)

    /// Come CGRectContainsPoint: i bordi minimi sono dentro, quelli massimi fuori.
    fun contains(p: Point): Boolean =
        !isNull && p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY

    fun intersects(o: Rect): Boolean {
        if (isNull || o.isNull) return false
        return minX < o.maxX && o.minX < maxX && minY < o.maxY && o.minY < maxY
    }

    fun union(o: Rect): Rect {
        if (isNull) return o
        if (o.isNull) return this
        val x0 = min(minX, o.minX)
        val y0 = min(minY, o.minY)
        return Rect(x0, y0, max(maxX, o.maxX) - x0, max(maxY, o.maxY) - y0)
    }

    /// Da un rettangolo normalizzato in [0,1] (origine in alto a sinistra) a `frame`.
    fun denormalized(frame: Rect) = Rect(
        frame.minX + minX * frame.width,
        frame.minY + minY * frame.height,
        width * frame.width,
        height * frame.height,
    )

    /// L'inverso di `denormalized`.
    fun normalized(frame: Rect): Rect {
        if (frame.width <= 0 || frame.height <= 0) return ZERO
        return Rect(
            (minX - frame.minX) / frame.width,
            (minY - frame.minY) / frame.height,
            width / frame.width,
            height / frame.height,
        )
    }

    companion object {
        val NULL = Rect(Double.POSITIVE_INFINITY, Double.POSITIVE_INFINITY, 0.0, 0.0)
        val ZERO = Rect(0.0, 0.0, 0.0, 0.0)

        /// Il rettangolo più piccolo che contiene tutti i punti (`NULL` se non ce ne sono).
        fun bounding(points: List<Point>): Rect {
            if (points.isEmpty()) return NULL
            var minX = points[0].x
            var maxX = minX
            var minY = points[0].y
            var maxY = minY
            for (i in 1 until points.size) {
                val p = points[i]
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return Rect(minX, minY, maxX - minX, maxY - minY)
        }
    }
}

/// Trasformazione affine con la stessa convenzione di CGAffineTransform:
/// x' = a·x + c·y + tx, y' = b·x + d·y + ty.
@Serializable
data class AffineTransform(
    val a: Double = 1.0,
    val b: Double = 0.0,
    val c: Double = 0.0,
    val d: Double = 1.0,
    val tx: Double = 0.0,
    val ty: Double = 0.0,
) {
    val isIdentity: Boolean
        get() = a == 1.0 && b == 0.0 && c == 0.0 && d == 1.0 && tx == 0.0 && ty == 0.0

    /// Prima questa, poi `t`.
    fun concatenating(t: AffineTransform) = AffineTransform(
        a = a * t.a + b * t.c,
        b = a * t.b + b * t.d,
        c = c * t.a + d * t.c,
        d = c * t.b + d * t.d,
        tx = tx * t.a + ty * t.c + t.tx,
        ty = tx * t.b + ty * t.d + t.ty,
    )

    /// Prima la scala, poi questa (come `scaledBy` di CoreGraphics).
    fun scaledBy(sx: Double, sy: Double) = scale(sx, sy).concatenating(this)

    /// Quanto la trasformazione ingrandisce le lunghezze, in media.
    val scaleFactor: Double get() = kotlin.math.sqrt(abs(a * d - b * c))

    companion object {
        val IDENTITY = AffineTransform()
        fun translation(x: Double, y: Double) = AffineTransform(tx = x, ty = y)
        fun scale(x: Double, y: Double) = AffineTransform(a = x, d = y)
        fun rotation(angle: Double) = AffineTransform(a = cos(angle), b = sin(angle), c = -sin(angle), d = cos(angle))
    }
}

internal fun distance(a: Point, b: Point): Double = hypot(b.x - a.x, b.y - a.y)

/// Come `rounded()` di Swift: la metà va lontano dallo zero.
internal fun roundHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)

internal object PolygonMath {
    /// Area con segno (formula del laccio) del poligono chiuso tra l'ultimo e il primo punto.
    fun signedArea(pts: List<Point>): Double {
        if (pts.size < 3) return 0.0
        var sum = 0.0
        for (i in pts.indices) {
            val a = pts[i]
            val b = pts[(i + 1) % pts.size]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Regola del numero di avvolgimento non nullo: un lazo che fa più di un giro
    /// (con le estremità sovrapposte) conta comunque la sovrapposizione come dentro.
    fun contains(p: Point, pts: List<Point>): Boolean {
        if (pts.size < 3) return false
        var winding = 0
        for (i in pts.indices) {
            val a = pts[i]
            val b = pts[(i + 1) % pts.size]
            if (a.y <= p.y) {
                if (b.y > p.y && cross(a, b, p) > 0) winding += 1
            } else if (b.y <= p.y && cross(a, b, p) < 0) {
                winding -= 1
            }
        }
        return winding != 0
    }

    /// Distanza di `p` dal contorno chiuso.
    fun distance(p: Point, pts: List<Point>): Double {
        if (pts.isEmpty()) return Double.POSITIVE_INFINITY
        if (pts.size == 1) return hypot(p.x - pts[0].x, p.y - pts[0].y)
        var best = Double.POSITIVE_INFINITY
        for (i in pts.indices) {
            best = min(best, segmentDistance(p, pts[i], pts[(i + 1) % pts.size]))
        }
        return best
    }

    fun segmentDistance(p: Point, a: Point, b: Point): Double {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val len2 = dx * dx + dy * dy
        var t = 0.0
        if (len2 > 0) t = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private fun cross(a: Point, b: Point, p: Point): Double =
        (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
}
