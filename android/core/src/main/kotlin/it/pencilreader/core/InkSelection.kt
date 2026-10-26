package it.pencilreader.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/// Quali tratti prende un lazo disegnato sul quaderno.
object StrokeLasso {
    /// Gli indici dei tratti con almeno `share` dei loro punti dentro il lazo chiuso.
    /// Ogni tratto è dato come i suoi punti sulla pagina, dopo la sua trasformazione.
    fun selected(strokes: List<List<Point>>, lasso: List<Point>, share: Double = 0.5): List<Int> {
        if (lasso.size < 3) return emptyList()
        val bounds = Rect.bounding(lasso)
        return strokes.indices.filter { index ->
            val points = strokes[index]
            if (points.isEmpty()) return@filter false
            val inside = points.count { bounds.contains(it) && PolygonMath.contains(it, lasso) }
            inside.toDouble() >= share * points.size
        }
    }
}

/// Una maniglia del riquadro della selezione: gli angoli ridimensionano tenendo le proporzioni, i lati
/// allungano in un verso solo, `ROTATE` sta sopra il lato alto e gira la selezione.
enum class SelectionHandle(val dx: Double, val dy: Double) {
    TOP_LEFT(-1.0, -1.0), TOP(0.0, -1.0), TOP_RIGHT(1.0, -1.0), RIGHT(1.0, 0.0),
    BOTTOM_RIGHT(1.0, 1.0), BOTTOM(0.0, 1.0), BOTTOM_LEFT(-1.0, 1.0), LEFT(-1.0, 0.0), ROTATE(0.0, -1.0);

    val isCorner: Boolean get() = dx != 0.0 && dy != 0.0
}

/// Il riquadro attorno ai tratti scelti, mentre si sposta, si ridimensiona e gira.
///
/// `original` è il riquadro dei tratti quando sono stati scelti; `center`, `size` e `angle`
/// dicono dov'è ora. `transform` porta i tratti da dov'erano a dov'è il riquadro.
data class SelectionFrame(
    val original: Rect,
    val center: Point,
    val size: Size,
    /// Radianti, in senso orario sullo schermo (la y cresce verso il basso).
    val angle: Double,
) {
    val transform: AffineTransform
        get() {
            val fromW = max(original.width, 1.0)
            val fromH = max(original.height, 1.0)
            return AffineTransform.translation(-original.midX, -original.midY)
                .concatenating(AffineTransform.scale(size.width / fromW, size.height / fromH))
                .concatenating(AffineTransform.rotation(angle))
                .concatenating(AffineTransform.translation(center.x, center.y))
        }

    /// Gli angoli, in senso orario da quello in alto a sinistra.
    val corners: List<Point>
        get() = listOf(-1.0 to -1.0, 1.0 to -1.0, 1.0 to 1.0, -1.0 to 1.0)
            .map { (sx, sy) -> point(Point(sx * size.width / 2, sy * size.height / 2)) }

    /// Dove si disegna una maniglia. Quella per girare sta `rotationGap` sopra il lato alto.
    fun position(handle: SelectionHandle, rotationGap: Double): Point {
        var local = Point(handle.dx * size.width / 2, handle.dy * size.height / 2)
        if (handle == SelectionHandle.ROTATE) local = local.copy(y = local.y - rotationGap)
        return point(local)
    }

    /// La maniglia entro `radius` da `point`, la più vicina; null se non ce n'è.
    fun handle(point: Point, radius: Double, rotationGap: Double): SelectionHandle? =
        SelectionHandle.entries
            .map { it to distance(position(it, rotationGap), point) }
            .filter { it.second <= radius }
            .minByOrNull { it.second }?.first

    /// Se `point` è nel riquadro, o entro `slack` da esso.
    fun contains(point: Point, slack: Double = 0.0): Boolean {
        val p = local(point)
        return abs(p.x) <= size.width / 2 + slack && abs(p.y) <= size.height / 2 + slack
    }

    /// Il riquadro spostato dalla penna o dal dito da `start` a `now`.
    fun moved(start: Point, now: Point) = copy(center = Point(center.x + now.x - start.x, center.y + now.y - start.y))

    /// Il riquadro con `handle` trascinata da `start` a `now`; l'angolo o il lato opposti restano fermi.
    /// Gli angoli tengono le proporzioni, i lati cambiano una dimensione sola.
    fun resized(handle: SelectionHandle, start: Point, now: Point): SelectionFrame {
        if (handle == SelectionHandle.ROTATE) return this
        val halfW = size.width / 2
        val halfH = size.height / 2
        val anchor = Point(-handle.dx * halfW, -handle.dy * halfH)
        val grip = Point(handle.dx * halfW, handle.dy * halfH)
        // La maniglia segue il puntatore anche quando non è partito esattamente su di essa.
        val moved = local(now)
        val started = local(start)
        val target = Point(grip.x + moved.x - started.x, grip.y + moved.y - started.y)

        var width = size.width
        var height = size.height
        if (handle.isCorner) {
            val vector = Point(grip.x - anchor.x, grip.y - anchor.y)
            val length2 = vector.x * vector.x + vector.y * vector.y
            var scale = ((target.x - anchor.x) * vector.x + (target.y - anchor.y) * vector.y) / length2
            scale = max(scale, MINIMUM_SIDE / min(size.width, size.height))
            width *= scale
            height *= scale
        } else if (handle.dx != 0.0) {
            width = max((target.x - anchor.x) * handle.dx, MINIMUM_SIDE)
        } else {
            height = max((target.y - anchor.y) * handle.dy, MINIMUM_SIDE)
        }
        val newCenter = Point(anchor.x + handle.dx * width / 2, anchor.y + handle.dy * height / 2)
        return copy(size = Size(width, height), center = point(newCenter))
    }

    /// Il riquadro girato attorno al centro dell'angolo percorso dal puntatore da `start` a `now`,
    /// agganciato a 0°, 90°, 180° o 270° quando è entro cinque gradi da uno di essi.
    fun rotated(start: Point, now: Point): SelectionFrame {
        val swept = atan2(now.y - center.y, now.x - center.x) - atan2(start.y - center.y, start.x - center.x)
        return copy(angle = snapped(normalized(angle + swept)))
    }

    /// Dalle coordinate del riquadro (origine al centro, assi lungo i lati) alla pagina.
    private fun point(p: Point) = Point(
        center.x + p.x * cos(angle) - p.y * sin(angle),
        center.y + p.x * sin(angle) + p.y * cos(angle),
    )

    private fun local(p: Point): Point {
        val x = p.x - center.x
        val y = p.y - center.y
        return Point(x * cos(angle) + y * sin(angle), -x * sin(angle) + y * cos(angle))
    }

    companion object {
        /// Più piccolo di così il riquadro non si schiaccia, così non si ribalta e non sparisce.
        const val MINIMUM_SIDE = 8.0
        /// La rotazione si aggancia a un quarto di giro quando ci arriva così vicino.
        const val ROTATION_SNAP = 5 * PI / 180

        fun around(rect: Rect): SelectionFrame {
            val r = rect.standardized()
            return SelectionFrame(r, Point(r.midX, r.midY), Size(max(r.width, 1.0), max(r.height, 1.0)), 0.0)
        }

        /// L'angolo in (-π, π].
        internal fun normalized(angle: Double): Double {
            var a = angle % (2 * PI)
            if (a <= -PI) a += 2 * PI
            if (a > PI) a -= 2 * PI
            return a
        }

        internal fun snapped(angle: Double): Double {
            val quarter = PI / 2
            val nearest = roundHalfAway(angle / quarter) * quarter
            return if (abs(angle - nearest) <= ROTATION_SNAP) normalized(nearest) else angle
        }

        private fun distance(a: Point, b: Point) = hypot(a.x - b.x, a.y - b.y)
    }
}
