package it.pencilreader.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/// Una forma pulita in cui si trasforma un tratto fatto a mano.
@Serializable
sealed class InkShape {
    @Serializable
    @SerialName("line")
    data class Line(val a: Point, val b: Point) : InkShape()

    /// Gli angoli nell'ordine in cui sono stati disegnati; il contorno si chiude tornando al primo.
    @Serializable
    @SerialName("polygon")
    data class Polygon(val corners: List<Point>) : InkShape()

    /// `angle` gira l'asse di `radii.width` rispetto all'orizzontale. Un cerchio ha i raggi uguali.
    @Serializable
    @SerialName("ellipse")
    data class Ellipse(val center: Point, val radii: Size, val angle: Double) : InkShape()

    /// Il pezzo di cerchio da `start` a `end` che passa per `through`.
    @Serializable
    @SerialName("arc")
    data class Arc(val start: Point, val through: Point, val end: Point) : InkShape()

    /// Una curva aperta e morbida attraverso i suoi punti di controllo (Catmull-Rom).
    @Serializable
    @SerialName("curve")
    data class Curve(val controls: List<Point>) : InkShape()

    /// Punti lungo il contorno, al massimo `spacing` uno dall'altro, angoli compresi;
    /// le forme chiuse finiscono dove cominciano.
    fun outline(spacing: Double = 2.0): List<Point> = when (this) {
        is Line -> segment(a, b, spacing) + b
        is Polygon -> {
            val points = mutableListOf<Point>()
            for ((i, corner) in corners.withIndex()) points += segment(corner, corners[(i + 1) % corners.size], spacing)
            points + corners[0]
        }
        is Ellipse -> {
            val perimeter = 2 * PI * sqrt((radii.width * radii.width + radii.height * radii.height) / 2)
            val count = max(36, ceil(perimeter / spacing).toInt())
            (0..count).map { i ->
                val t = 2 * PI * i / count
                val x = radii.width * cos(t)
                val y = radii.height * sin(t)
                Point(center.x + x * cos(angle) - y * sin(angle), center.y + x * sin(angle) + y * cos(angle))
            }
        }
        is Arc -> {
            val circle = arcCircle(start, through, end)
            if (circle == null) {
                segment(start, end, spacing) + end
            } else {
                val count = max(8, ceil(abs(circle.sweep) * circle.radius / spacing).toInt())
                (0..count).map { i ->
                    val t = circle.startAngle + circle.sweep * i / count
                    Point(circle.center.x + circle.radius * cos(t), circle.center.y + circle.radius * sin(t))
                }
            }
        }
        is Curve -> catmullRom(controls, spacing)
    }

    /// Il punto della forma che resta fermo mentre la penna la trascina: il più lontano dalla punta.
    fun anchor(oppositeTo: Point): Point {
        val tip = oppositeTo
        val candidates = when (this) {
            is Line -> listOf(a, b)
            is Polygon -> corners
            is Ellipse -> outline(8.0)
            is Arc -> listOf(start, end)
            is Curve -> listOf(controls.first(), controls.last())
        }
        return candidates.maxByOrNull { distance(it, tip) } ?: tip
    }

    /// La forma scalata e girata attorno ad `anchor`, così il punto sotto `from` segue la penna fino a `to`.
    fun dragged(anchor: Point, from: Point, to: Point): InkShape {
        val before = Point(from.x - anchor.x, from.y - anchor.y)
        val after = Point(to.x - anchor.x, to.y - anchor.y)
        val length = hypot(before.x, before.y)
        if (length <= 1 || hypot(after.x, after.y) <= 1) return this
        val scale = hypot(after.x, after.y) / length
        val turn = atan2(after.y, after.x) - atan2(before.y, before.x)
        fun move(p: Point): Point {
            val x = (p.x - anchor.x) * scale
            val y = (p.y - anchor.y) * scale
            return Point(anchor.x + x * cos(turn) - y * sin(turn), anchor.y + x * sin(turn) + y * cos(turn))
        }
        return when (this) {
            is Line -> {
                val (s, e) = ShapeRecognizer.straightened(move(a), move(b))
                Line(s, e)
            }
            is Polygon -> Polygon(corners.map(::move))
            is Ellipse -> {
                val isCircle = radii.width == radii.height
                Ellipse(move(center), Size(radii.width * scale, radii.height * scale), if (isCircle) 0.0 else angle + turn)
            }
            is Arc -> Arc(move(start), move(through), move(end))
            is Curve -> Curve(controls.map(::move))
        }
    }

    internal data class ArcCircle(val center: Point, val radius: Double, val startAngle: Double, val sweep: Double)

    companion object {
        /// Il cerchio per i tre punti di un arco, dove comincia l'arco e quanto gira
        /// (negativo in senso antiorario sullo schermo); null quando i punti sono quasi allineati.
        internal fun arcCircle(a: Point, b: Point, c: Point): ArcCircle? {
            val d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
            val size = max(distance(a, b) + distance(b, c), 0.001)
            if (abs(d) <= 0.0001 * size * size) return null
            val a2 = a.x * a.x + a.y * a.y
            val b2 = b.x * b.x + b.y * b.y
            val c2 = c.x * c.x + c.y * c.y
            val center = Point(
                (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d,
            )
            val radius = distance(center, a)
            // Un cerchio molto più grande dell'arco è una linea un po' piegata.
            if (radius >= 50 * size) return null
            val start = atan2(a.y - center.y, a.x - center.x)
            fun turn(p: Point): Double {
                var t = atan2(p.y - center.y, p.x - center.x) - start
                while (t < 0) t += 2 * PI
                return t
            }
            val toEnd = turn(c)
            val toMiddle = turn(b)
            // Il giro che dall'inizio passa per il punto di mezzo prima della fine.
            val sweep = if (toMiddle <= toEnd) toEnd else toEnd - 2 * PI
            return ArcCircle(center, radius, start, sweep)
        }

        /// Punti lungo la curva Catmull-Rom attraverso `controls`, estremi compresi.
        internal fun catmullRom(controls: List<Point>, spacing: Double): List<Point> {
            if (controls.size <= 2) {
                if (controls.size != 2) return controls
                return segment(controls[0], controls[1], spacing) + controls[1]
            }
            val points = mutableListOf<Point>()
            val padded = listOf(controls.first()) + controls + listOf(controls.last())
            for (i in 1 until padded.size - 2) {
                val p0 = padded[i - 1]
                val p1 = padded[i]
                val p2 = padded[i + 1]
                val p3 = padded[i + 2]
                val steps = max(2, ceil(distance(p1, p2) * 1.2 / spacing).toInt())
                for (j in 0 until steps) {
                    val t = j.toDouble() / steps
                    val t2 = t * t
                    val t3 = t2 * t
                    fun blend(a: Double, b: Double, c: Double, d: Double) =
                        0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                    points.add(Point(blend(p0.x, p1.x, p2.x, p3.x), blend(p0.y, p1.y, p2.y, p3.y)))
                }
            }
            return points + controls.last()
        }

        /// Da `a` fino a `b` escluso.
        internal fun segment(a: Point, b: Point, spacing: Double): List<Point> {
            val steps = max(1, ceil(distance(a, b) / spacing).toInt())
            return (0 until steps).map { i ->
                val t = i.toDouble() / steps
                Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
            }
        }
    }
}

/// Riconosce il tratto disegnato finora come linea, triangolo, rettangolo o quadrato, altro poligono
/// fino a otto angoli, ellisse o cerchio, arco o curva morbida. Ciò che non è chiaramente una forma dà null.
/// Gira una volta, quando la penna resta ferma, sul tratto ricampionato a un numero fisso di punti.
object ShapeRecognizer {
    /// I tratti più piccoli sono scrittura, mai forme.
    const val MINIMUM_SIZE = 30.0
    internal const val SAMPLE_COUNT = 64

    fun recognize(stroke: List<Point>): InkShape? {
        if (stroke.size < 2) return null
        val points = resampled(stroke, SAMPLE_COUNT)
        val box = Rect.bounding(points)
        val size = hypot(box.width, box.height)
        if (size < MINIMUM_SIZE) return null
        val length = pathLength(points)
        val first = points.first()
        val last = points.last()
        val chord = distance(first, last)

        if (chord > 0.85 * length) {
            val deviation = points.maxOfOrNull { PolygonMath.segmentDistance(it, first, last) } ?: 0.0
            if (deviation <= 0.06 * chord) {
                val (a, b) = straightened(first, last)
                return InkShape.Line(a, b)
            }
        }
        // Un tratto aperto è un pezzo di cerchio, una curva morbida, o niente.
        if (chord > 0.2 * length) return arc(points, size) ?: smoothCurve(points, size)

        var polygonFit = Double.POSITIVE_INFINITY
        var corners = dropFlatCorners(closingEnd(simplify(points, 0.07 * size), size))
        if (corners.size in 3..8) {
            val distances = points.map { PolygonMath.distance(it, corners) }
            if ((distances.maxOrNull() ?: Double.POSITIVE_INFINITY) <= 0.08 * size) {
                polygonFit = distances.sum() / distances.size
            }
        }
        val ellipse = fittedEllipse(points)

        // Possono andar bene tutti e due per un quadrato arrotondato o un poligono con molti lati: vince il più vicino.
        if (polygonFit < Double.POSITIVE_INFINITY && polygonFit <= (ellipse?.second ?: Double.POSITIVE_INFINITY)) {
            corners = refinedCorners(corners, points, size)
            if (corners.size == 4) rectangle(corners)?.let { corners = it }
            return InkShape.Polygon(corners)
        }
        return ellipse?.first
    }

    // Forme

    /// Un tratto aperto che resta vicino a un cerchio e gli gira attorno tra 30° e 330°.
    internal fun arc(points: List<Point>, size: Double): InkShape? {
        val circle = fittedCircle(points) ?: return null
        if (circle.second >= 10 * size) return null
        val (center, radius) = circle
        val residuals = points.map { abs(distance(it, center) - radius) }
        val mean = residuals.sum() / residuals.size
        if (mean > 0.035 * radius || (residuals.maxOrNull() ?: 0.0) > 0.1 * radius) return null
        var turned = 0.0
        var travelled = 0.0
        for (i in 0 until points.size - 1) {
            val a = points[i]
            val b = points[i + 1]
            var step = atan2(b.y - center.y, b.x - center.x) - atan2(a.y - center.y, a.x - center.x)
            if (step > PI) step -= 2 * PI
            if (step < -PI) step += 2 * PI
            turned += step
            travelled += abs(step)
        }
        // Sempre nello stesso verso: un tratto che va avanti e indietro non è un arco.
        val degrees = abs(turned) * 180 / PI
        if (travelled > 1.1 * abs(turned) || degrees < 30 || degrees > 330) return null
        fun onCircle(p: Point): Point {
            val d = max(distance(p, center), 0.0001)
            return Point(center.x + (p.x - center.x) * radius / d, center.y + (p.y - center.y) * radius / d)
        }
        return InkShape.Arc(onCircle(points.first()), onCircle(points[points.size / 2]), onCircle(points.last()))
    }

    /// Un tratto aperto senza angoli: una curva morbida per quattro-otto punti lungo il tratto.
    internal fun smoothCurve(points: List<Point>, size: Double): InkShape? {
        // Una svolta brusca, come in un 2, un 7 o uno zigzag, è un angolo: non una curva.
        val k = 3
        for (i in k until points.size - k) {
            val u = Point(points[i].x - points[i - k].x, points[i].y - points[i - k].y)
            val v = Point(points[i + k].x - points[i].x, points[i + k].y - points[i].y)
            val lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
            if (lengths <= 0) continue
            val turn = acos(max(-1.0, min(1.0, (u.x * v.x + u.y * v.y) / lengths)))
            if (turn > 65 * PI / 180) return null
        }
        val count = min(8, max(4, simplify(points, 0.03 * size).size))
        val controls = (0 until count).map { j ->
            points[roundHalfAway(j.toDouble() * (points.size - 1) / (count - 1)).toInt()]
        }
        val curve = InkShape.catmullRom(controls, 2.0)
        val deviation = points.maxOfOrNull { p ->
            (0 until curve.size - 1).minOfOrNull { PolygonMath.segmentDistance(p, curve[it], curve[it + 1]) }
                ?: Double.POSITIVE_INFINITY
        } ?: Double.POSITIVE_INFINITY
        if (deviation > 0.06 * size) return null
        return InkShape.Curve(controls)
    }

    /// Il cerchio ai minimi quadrati per i punti (Kåsa), attorno al loro centro per precisione.
    internal fun fittedCircle(points: List<Point>): Pair<Point, Double>? {
        val n = points.size.toDouble()
        val mx = points.sumOf { it.x } / n
        val my = points.sumOf { it.y } / n
        var suu = 0.0; var svv = 0.0; var suv = 0.0
        var suuu = 0.0; var svvv = 0.0; var suvv = 0.0; var svuu = 0.0
        for (p in points) {
            val u = p.x - mx
            val v = p.y - my
            suu += u * u; svv += v * v; suv += u * v
            suuu += u * u * u; svvv += v * v * v; suvv += u * v * v; svuu += v * u * u
        }
        val det = suu * svv - suv * suv
        if (abs(det) <= 0.000001) return null
        val b1 = (suuu + suvv) / 2
        val b2 = (svvv + svuu) / 2
        val uc = (b1 * svv - b2 * suv) / det
        val vc = (suu * b2 - suv * b1) / det
        val radius = sqrt(uc * uc + vc * vc + (suu + svv) / n)
        return Point(mx + uc, my + vc) to radius
    }

    /// Quattro angoli quasi retti fanno un vero rettangolo, un quadrato quando i lati quasi coincidono.
    internal fun rectangle(corners: List<Point>): List<Point>? {
        for (i in 0 until 4) {
            val corner = angle(corners[i], corners[(i + 3) % 4], corners[(i + 1) % 4])
            if (abs(corner - PI / 2) > 15 * PI / 180) return null
        }
        val center = Point(corners.sumOf { it.x } / 4, corners.sumOf { it.y } / 4)
        var width = (distance(corners[0], corners[1]) + distance(corners[2], corners[3])) / 2
        var height = (distance(corners[1], corners[2]) + distance(corners[3], corners[0])) / 2
        if (abs(width - height) <= 0.12 * max(width, height)) {
            width = (width + height) / 2
            height = width
        }
        val direction = snapped(atan2(corners[1].y - corners[0].y, corners[1].x - corners[0].x))
        val u = Point(cos(direction), sin(direction))
        // Perpendicolare verso il terzo angolo, così gli angoli restano nell'ordine in cui sono stati disegnati.
        val side = Point(corners[2].x - corners[1].x, corners[2].y - corners[1].y)
        val turn = if (-u.y * side.x + u.x * side.y >= 0) 1.0 else -1.0
        val v = Point(-u.y * turn, u.x * turn)
        val w = width / 2
        val h = height / 2
        val signs = listOf(-1.0 to -1.0, 1.0 to -1.0, 1.0 to 1.0, -1.0 to 1.0)
        return signs.map { (s, t) -> Point(center.x + u.x * w * s + v.x * h * t, center.y + u.y * w * s + v.y * h * t) }
    }

    /// L'ellisse lungo gli assi principali del tratto. Il secondo valore è la distanza media del tratto da essa.
    internal fun fittedEllipse(points: List<Point>): Pair<InkShape, Double>? {
        val n = points.size.toDouble()
        val cx = points.sumOf { it.x } / n
        val cy = points.sumOf { it.y } / n
        var sxx = 0.0; var syy = 0.0; var sxy = 0.0
        for (p in points) {
            sxx += (p.x - cx) * (p.x - cx)
            syy += (p.y - cy) * (p.y - cy)
            sxy += (p.x - cx) * (p.y - cy)
        }
        val angle = 0.5 * atan2(2 * sxy, sxx - syy)
        val c = cos(angle)
        val s = sin(angle)
        val us = points.map { (it.x - cx) * c + (it.y - cy) * s }
        val vs = points.map { -(it.x - cx) * s + (it.y - cy) * c }
        val minU = us.minOrNull() ?: return null
        val maxU = us.maxOrNull() ?: return null
        val minV = vs.minOrNull() ?: return null
        val maxV = vs.maxOrNull() ?: return null
        var a = (maxU - minU) / 2
        var b = (maxV - minV) / 2
        if (a <= 2 || b <= 2) return null
        val mu = (maxU + minU) / 2
        val mv = (maxV + minV) / 2
        var shareError = 0.0
        var fit = 0.0
        for (i in us.indices) {
            val x = us[i] - mu
            val y = vs[i] - mv
            val r = max(hypot(x / a, y / b), 0.0001)
            shareError += abs(r - 1)
            fit += abs(r - 1) * hypot(x, y) / r
        }
        // Un quadrato perfetto fa circa 0,15, un cerchio a mano ben sotto 0,1.
        if (shareError / n > 0.1) return null
        val center = Point(cx + mu * c - mv * s, cy + mu * s + mv * c)
        var shapeAngle = snapped(angle)
        if (abs(a - b) <= 0.15 * max(a, b)) {
            a = (a + b) / 2
            b = a
            shapeAngle = 0.0
        }
        return InkShape.Ellipse(center, Size(a, b), shapeAngle) to fit / n
    }

    /// Una linea vicina all'orizzontale, alla verticale o alla diagonale lo diventa esattamente, attorno al suo centro.
    internal fun straightened(a: Point, b: Point): Pair<Point, Point> {
        val direction = atan2(b.y - a.y, b.x - a.x)
        val snappedDirection = snapped(direction)
        if (snappedDirection == direction) return a to b
        val mid = Point((a.x + b.x) / 2, (a.y + b.y) / 2)
        val half = distance(a, b) / 2
        val d = Point(cos(snappedDirection) * half, sin(snappedDirection) * half)
        return Point(mid.x - d.x, mid.y - d.y) to Point(mid.x + d.x, mid.y + d.y)
    }

    /// Le direzioni entro 5° da un multiplo di 45° diventano quel multiplo.
    internal fun snapped(direction: Double): Double {
        val eighth = PI / 4
        val nearest = roundHalfAway(direction / eighth) * eighth
        return if (abs(direction - nearest) <= 5 * PI / 180) nearest else direction
    }

    // Punti

    /// `count` punti a distanza uguale lungo il tratto, così tratti lunghi e corti costano uguale.
    internal fun resampled(points: List<Point>, count: Int): List<Point> {
        val length = pathLength(points)
        if (length <= 0 || count <= 1) return points
        val step = length / (count - 1)
        val result = mutableListOf(points[0])
        var previous = points[0]
        var carried = 0.0
        var i = 1
        while (i < points.size && result.size < count) {
            val d = distance(previous, points[i])
            if (d > 0 && carried + d >= step) {
                val t = (step - carried) / d
                previous = Point(previous.x + t * (points[i].x - previous.x), previous.y + t * (points[i].y - previous.y))
                result.add(previous)
                carried = 0.0
            } else {
                carried += d
                previous = points[i]
                i += 1
            }
        }
        while (result.size < count) result.add(points.last())
        return result
    }

    /// Douglas-Peucker: tiene i punti che sporgono più di `epsilon` dalla corda.
    internal fun simplify(points: List<Point>, epsilon: Double): List<Point> {
        if (points.size <= 2) return points
        val first = points.first()
        val last = points.last()
        var farthest = 0
        var maxDistance = 0.0
        for (i in 1 until points.size - 1) {
            val d = PolygonMath.segmentDistance(points[i], first, last)
            if (d > maxDistance) {
                maxDistance = d
                farthest = i
            }
        }
        if (maxDistance <= epsilon) return listOf(first, last)
        val left = simplify(points.subList(0, farthest + 1), epsilon)
        val right = simplify(points.subList(farthest, points.size), epsilon)
        return left.dropLast(1) + right
    }

    /// Dove si incontrano i lati dritti. I punti tenuti come angoli stanno fino a mezzo campione prima
    /// dell'angolo vero, quindi a ogni lato si adatta una retta sulla sua parte centrale, e gli angoli
    /// diventano gli incroci di quelle rette.
    internal fun refinedCorners(corners: List<Point>, points: List<Point>, size: Double): List<Point> {
        val ring = points.toMutableList()
        if (ring.size > 0 && distance(ring.first(), ring.last()) < 0.001) ring.removeAt(ring.size - 1)
        val n = ring.size
        if (n < corners.size * 3) return corners
        val indices = corners.map { corner -> ring.indices.minByOrNull { distance(ring[it], corner) } ?: 0 }
        val lines = mutableListOf<Pair<Point, Point>>()
        for (k in corners.indices) {
            val a = indices[k]
            val b = indices[(k + 1) % corners.size]
            val span = (b - a + n) % n
            val side = (0..span).map { ring[(a + it) % n] }
            // Le estremità di un lato piegano negli angoli: solo il centro è dritto.
            val cut = side.size * 15 / 100
            val middle = if (side.size - 2 * cut >= 2) side.subList(cut, side.size - cut) else side
            if (middle.size < 2) return corners
            lines.add(fittedLine(middle))
        }
        return corners.indices.map { k ->
            val previous = lines[(k + corners.size - 1) % corners.size]
            val meet = intersection(previous, lines[k])
            if (meet == null || distance(meet, corners[k]) > 0.15 * size) corners[k] else meet
        }
    }

    /// La retta per il centro dei punti, lungo la loro direzione principale.
    private fun fittedLine(points: List<Point>): Pair<Point, Point> {
        val n = points.size.toDouble()
        val cx = points.sumOf { it.x } / n
        val cy = points.sumOf { it.y } / n
        var sxx = 0.0; var syy = 0.0; var sxy = 0.0
        for (p in points) {
            sxx += (p.x - cx) * (p.x - cx)
            syy += (p.y - cy) * (p.y - cy)
            sxy += (p.x - cx) * (p.y - cy)
        }
        val angle = 0.5 * atan2(2 * sxy, sxx - syy)
        return Point(cx, cy) to Point(cos(angle), sin(angle))
    }

    private fun intersection(first: Pair<Point, Point>, second: Pair<Point, Point>): Point? {
        val d = first.second
        val e = second.second
        val denominator = d.x * e.y - d.y * e.x
        if (abs(denominator) <= 0.000001) return null
        val t = ((second.first.x - first.first.x) * e.y - (second.first.y - first.first.y) * e.x) / denominator
        return Point(first.first.x + t * d.x, first.first.y + t * d.y)
    }

    /// Un tratto chiuso finisce vicino all'inizio: quell'estremità è lo stesso angolo.
    private fun closingEnd(corners: List<Point>, size: Double): List<Point> {
        if (corners.size <= 1 || distance(corners.first(), corners.last()) > 0.2 * size) return corners
        return corners.dropLast(1)
    }

    /// Toglie gli angoli dove il contorno va quasi dritto, come dove il tratto è cominciato a metà di un lato.
    internal fun dropFlatCorners(corners: List<Point>): List<Point> {
        val result = corners.toMutableList()
        var i = 0
        while (result.size > 3 && i < result.size) {
            val a = result[(i + result.size - 1) % result.size]
            val b = result[i]
            val c = result[(i + 1) % result.size]
            if (angle(b, a, c) >= 150 * PI / 180) {
                result.removeAt(i)
                i = 0
            } else {
                i += 1
            }
        }
        return result
    }

    /// L'angolo interno in `b`, da 0 a pi (pi = dritto).
    private fun angle(b: Point, a: Point, c: Point): Double {
        val u = Point(a.x - b.x, a.y - b.y)
        val v = Point(c.x - b.x, c.y - b.y)
        val lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
        if (lengths <= 0) return PI
        return acos(max(-1.0, min(1.0, (u.x * v.x + u.y * v.y) / lengths)))
    }

    internal fun pathLength(points: List<Point>): Double {
        var sum = 0.0
        for (i in 0 until points.size - 1) sum += distance(points[i], points[i + 1])
        return sum
    }
}
