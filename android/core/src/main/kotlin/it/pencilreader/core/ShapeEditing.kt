package it.pencilreader.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/// Rimodellare una forma già sulla pagina, come in GoodNotes: le sue maniglie ne cambiano la
/// geometria, mentre la linea tiene il suo spessore (a differenza del lazo, che scala tutto ciò che prende).

/// Le maniglie mostrate quando si tocca la forma, in quest'ordine:
/// le due estremità di una linea; i quattro angoli di un rettangolo e poi i centri dei suoi quattro lati;
/// gli angoli di ogni altro poligono; le quattro estremità degli assi di un'ellisse (+larghezza, -larghezza,
/// +altezza, -altezza); inizio, centro e fine di un arco; i punti di controllo di una curva.
val InkShape.grips: List<Point>
    get() = when (this) {
        is InkShape.Line -> listOf(a, b)
        is InkShape.Polygon ->
            if (!isRectangle) corners
            else corners + corners.indices.map { midpoint(corners[it], corners[(it + 1) % 4]) }
        is InkShape.Ellipse -> {
            val e1 = Point(cos(angle), sin(angle))
            val e2 = Point(-sin(angle), cos(angle))
            listOf(
                Point(center.x + e1.x * radii.width, center.y + e1.y * radii.width),
                Point(center.x - e1.x * radii.width, center.y - e1.y * radii.width),
                Point(center.x + e2.x * radii.height, center.y + e2.y * radii.height),
                Point(center.x - e2.x * radii.height, center.y - e2.y * radii.height),
            )
        }
        is InkShape.Arc -> listOf(start, through, end)
        is InkShape.Curve -> controls
    }

/// Quattro angoli retti: le maniglie sono angoli e lati, e resta un rettangolo.
val InkShape.isRectangle: Boolean
    get() {
        if (this !is InkShape.Polygon || corners.size != 4) return false
        return corners.indices.all { i ->
            val a = corners[(i + 3) % 4]
            val b = corners[i]
            val c = corners[(i + 1) % 4]
            val u = Point(a.x - b.x, a.y - b.y)
            val v = Point(c.x - b.x, c.y - b.y)
            val lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
            lengths > 0 && abs(u.x * v.x + u.y * v.y) / lengths < sin(0.5 * PI / 180)
        }
    }

val InkShape.isCircle: Boolean
    get() = this is InkShape.Ellipse && abs(radii.width - radii.height) <= 0.001 * max(radii.width, radii.height)

/// La forma con la maniglia numero `grip` (vedi `grips`) portata in `point`.
fun InkShape.reshaped(grip: Int, point: Point): InkShape {
    if (grip !in grips.indices) return this
    return when (this) {
        is InkShape.Line -> if (grip == 0) InkShape.Line(point, b) else InkShape.Line(a, point)
        is InkShape.Polygon -> {
            if (!isRectangle) {
                InkShape.Polygon(corners.toMutableList().also { it[grip] = point })
            } else if (grip < 4) {
                InkShape.Polygon(rectangleWithCorner(corners, grip, point))
            } else {
                InkShape.Polygon(rectangleWithSide(corners, grip - 4, point))
            }
        }
        is InkShape.Ellipse -> {
            val minimum = 3.0
            if (isCircle) {
                val r = max(hypot(point.x - center.x, point.y - center.y), minimum)
                return InkShape.Ellipse(center, Size(r, r), 0.0)
            }
            val axis = if (grip < 2) Point(cos(angle), sin(angle)) else Point(-sin(angle), cos(angle))
            val reach = max(abs((point.x - center.x) * axis.x + (point.y - center.y) * axis.y), minimum)
            val newRadii = if (grip < 2) Size(reach, radii.height) else Size(radii.width, reach)
            InkShape.Ellipse(center, newRadii, angle)
        }
        is InkShape.Arc -> when (grip) {
            0 -> arcKeepingItsMiddle(point, through, end)
            2 -> arcKeepingItsMiddle(start, through, point)
            else -> InkShape.Arc(start, point, end)
        }
        is InkShape.Curve -> InkShape.Curve(controls.toMutableList().also { it[grip] = point })
    }
}

/// Tutta la forma spostata di `offset`.
fun InkShape.moved(offset: Point): InkShape = applying(AffineTransform.translation(offset.x, offset.y))

/// La forma come la disegna una trasformazione affine, come quella che il lazo lascia su un tratto.
/// Un'ellisse resta un'ellisse, lungo i suoi nuovi assi; un arco passa per i suoi tre punti spostati.
fun InkShape.applying(t: AffineTransform): InkShape = when (this) {
    is InkShape.Line -> InkShape.Line(a.applying(t), b.applying(t))
    is InkShape.Polygon -> InkShape.Polygon(corners.map { it.applying(t) })
    is InkShape.Arc -> InkShape.Arc(start.applying(t), through.applying(t), end.applying(t))
    is InkShape.Curve -> InkShape.Curve(controls.map { it.applying(t) })
    is InkShape.Ellipse -> {
        // Le colonne di M portano il cerchio unitario sulla nuova ellisse: i suoi assi sono i vettori singolari di M.
        val c = cos(angle)
        val s = sin(angle)
        val m11 = t.a * c * radii.width + t.c * s * radii.width
        val m21 = t.b * c * radii.width + t.d * s * radii.width
        val m12 = -t.a * s * radii.height + t.c * c * radii.height
        val m22 = -t.b * s * radii.height + t.d * c * radii.height
        val p = m11 * m11 + m12 * m12
        val q = m11 * m21 + m12 * m22
        val r = m21 * m21 + m22 * m22
        val half = sqrt((p - r) * (p - r) / 4 + q * q)
        val major = sqrt((p + r) / 2 + half)
        val minor = sqrt(max((p + r) / 2 - half, 0.0))
        val newCenter = center.applying(t)
        if (abs(major - minor) <= 0.001 * major) {
            InkShape.Ellipse(newCenter, Size(major, major), 0.0)
        } else {
            InkShape.Ellipse(newCenter, Size(major, minor), 0.5 * atan2(2 * q, p - r))
        }
    }
}

/// Quanto dista `point` dalla linea della forma.
fun InkShape.outlineDistance(point: Point): Double {
    val line = outline(4.0)
    if (line.size <= 1) return line.firstOrNull()?.let { hypot(it.x - point.x, it.y - point.y) } ?: Double.POSITIVE_INFINITY
    var best = Double.POSITIVE_INFINITY
    for (i in 0 until line.size - 1) best = minOf(best, PolygonMath.segmentDistance(point, line[i], line[i + 1]))
    return best
}

// Rettangoli

/// Il rettangolo con un angolo trascinato: l'angolo opposto resta, i lati tengono le loro direzioni.
private fun rectangleWithCorner(corners: List<Point>, corner: Int, point: Point): List<Point> {
    val anchor = corners[(corner + 2) % 4]
    val u = unit(corners[0], corners[1])
    val v = unit(corners[0], corners[3])
    fun local(p: Point): Point {
        val d = Point(p.x - anchor.x, p.y - anchor.y)
        return Point(d.x * u.x + d.y * u.y, d.x * v.x + d.y * v.y)
    }
    var target = local(point)
    // Mai piatto: almeno qualche punto per parte.
    val old = local(corners[corner])
    if (abs(target.x) < 4) target = target.copy(x = if (old.x < 0) -4.0 else 4.0)
    if (abs(target.y) < 4) target = target.copy(y = if (old.y < 0) -4.0 else 4.0)
    return corners.map { c ->
        val l = local(c)
        val x = if (abs(l.x) > 0.001) target.x else 0.0
        val y = if (abs(l.y) > 0.001) target.y else 0.0
        Point(anchor.x + u.x * x + v.x * y, anchor.y + u.y * x + v.y * y)
    }
}

/// Il rettangolo con un lato spinto o tirato: il lato opposto resta.
private fun rectangleWithSide(corners: List<Point>, side: Int, point: Point): List<Point> {
    val a = corners[side]
    val b = corners[(side + 1) % 4]
    val opposite = corners[(side + 2) % 4]
    val along = unit(a, b)
    var normal = Point(-along.y, along.x)
    // Verso l'esterno, lontano dal lato opposto.
    if ((a.x - opposite.x) * normal.x + (a.y - opposite.y) * normal.y < 0) normal = Point(-normal.x, -normal.y)
    val middle = midpoint(a, b)
    val depth = (a.x - opposite.x) * normal.x + (a.y - opposite.y) * normal.y
    var push = (point.x - middle.x) * normal.x + (point.y - middle.y) * normal.y
    push = max(push, 4 - depth)
    val result = corners.toMutableList()
    for (i in listOf(side, (side + 1) % 4)) {
        result[i] = Point(corners[i].x + normal.x * push, corners[i].y + normal.y * push)
    }
    return result
}

/// Un arco con una nuova estremità, che si incurva ancora per `through`, che poi torna a metà.
private fun arcKeepingItsMiddle(start: Point, through: Point, end: Point): InkShape {
    val circle = InkShape.arcCircle(start, through, end) ?: return InkShape.Arc(start, through, end)
    val t = circle.startAngle + circle.sweep / 2
    val middle = Point(circle.center.x + circle.radius * cos(t), circle.center.y + circle.radius * sin(t))
    return InkShape.Arc(start, middle, end)
}

private fun unit(a: Point, b: Point): Point {
    val length = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
    return Point((b.x - a.x) / length, (b.y - a.y) / length)
}

private fun midpoint(a: Point, b: Point) = Point((a.x + b.x) / 2, (a.y + b.y) / 2)
