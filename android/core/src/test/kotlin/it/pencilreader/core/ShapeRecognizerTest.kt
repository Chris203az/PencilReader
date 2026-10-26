package it.pencilreader.core

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.Assert.fail
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/// Punti lungo il contorno chiuso per `corners`, a partire da `start` del giro, fino all'inizio.
private fun outline(corners: List<Point>, start: Double = 0.0, perSide: Int = 30): List<Point> {
    val points = mutableListOf<Point>()
    for ((i, a) in corners.withIndex()) {
        val b = corners[(i + 1) % corners.size]
        for (j in 0 until perSide) {
            val t = j.toDouble() / perSide
            points.add(Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
        }
    }
    val shift = (start * points.size).toInt()
    val rotated = points.subList(shift, points.size) + points.subList(0, shift)
    return rotated + rotated[0]
}

/// Un'oscillazione lenta e regolare, come una mano non del tutto ferma.
private fun wobbly(points: List<Point>, amount: Double = 2.0): List<Point> =
    points.mapIndexed { i, p -> Point(p.x + amount * sin(i * 0.3), p.y + amount * cos(i * 0.23)) }

private fun round(center: Point, rx: Double, ry: Double, turn: Double = 0.0, upTo: Double = 2 * PI): List<Point> =
    (0..60).map { i ->
        val t = upTo * i / 60
        val x = rx * cos(t)
        val y = ry * sin(t)
        Point(center.x + x * cos(turn) - y * sin(turn), center.y + x * sin(turn) + y * cos(turn))
    }

private fun corners(shape: InkShape?): List<Point>? = (shape as? InkShape.Polygon)?.corners

private fun sides(corners: List<Point>): List<Double> = corners.indices.map { i ->
    val next = corners[(i + 1) % corners.size]
    hypot(next.x - corners[i].x, next.y - corners[i].y)
}

private fun near(a: Point, b: Point, within: Double = 1.0) = hypot(a.x - b.x, a.y - b.y) <= within

class ShapeRecognizerTest {
    // Linee

    @Test fun nearlyHorizontalLineBecomesHorizontal() {
        val points = wobbly((0..80).map { pt(100 + it * 3.0, 200 + it * 0.1) }, amount = 1.0)
        val line = ShapeRecognizer.recognize(points) as? InkShape.Line ?: return fail("non è una linea")
        expect(abs(line.a.y - line.b.y) < 0.001)
    }

    @Test fun slantedLineKeepsItsDirection() {
        val points = (0..80).map { pt(it * 3.0, it * 2.0) }
        val line = ShapeRecognizer.recognize(points) as? InkShape.Line ?: return fail("non è una linea")
        expect(near(line.a, points[0]) && near(line.b, points[80]))
    }

    @Test fun bentStrokeIsNotALine() {
        val bent = outline(listOf(pt(0, 0), pt(100, 80), pt(200, 0))).take(61)
        expect(ShapeRecognizer.recognize(bent) == null)
    }

    // Poligoni

    @Test fun squareStartedMidSideBecomesASquare() {
        val drawn = wobbly(outline(listOf(pt(0, 0), pt(200, 4), pt(196, 210), pt(-4, 200)), start = 0.1))
        val square = corners(ShapeRecognizer.recognize(drawn)) ?: return fail("non è un poligono")
        expect(square.size == 4)
        val lengths = sides(square)
        expect(lengths.all { abs(it - lengths[0]) < 0.001 })
        // Lati raddrizzati sugli assi.
        expect(abs(square[0].y - square[1].y) < 0.001 || abs(square[0].x - square[1].x) < 0.001)
    }

    @Test fun turnedRectangleKeepsItsAngleAndSize() {
        val turn = 0.5
        val flat = listOf(pt(0, 0), pt(300, 0), pt(300, 120), pt(0, 120))
        val drawn = outline(flat.map { Point(it.x * cos(turn) - it.y * sin(turn), it.x * sin(turn) + it.y * cos(turn)) }, start = 0.4)
        val rectangle = corners(ShapeRecognizer.recognize(drawn)) ?: return fail("non è un poligono")
        expect(rectangle.size == 4)
        val lengths = sides(rectangle).sorted()
        expect(abs(lengths[0] - 120) < 2 && abs(lengths[3] - 300) < 2)
    }

    @Test fun triangleKeepsItsThreeCorners() {
        val triangle = listOf(pt(100, 0), pt(200, 180), pt(0, 180))
        val found = corners(ShapeRecognizer.recognize(wobbly(outline(triangle, start = 0.3)))) ?: return fail("non è un poligono")
        expect(found.size == 3)
        expect(triangle.all { corner -> found.any { near(it, corner, 8.0) } })
    }

    @Test fun pentagonIsAPolygonNotACircle() {
        val pentagon = (0 until 5).map { i ->
            val angle = 2 * PI * i / 5
            Point(100 + 100 * cos(angle), 100 + 100 * sin(angle))
        }
        val found = corners(ShapeRecognizer.recognize(wobbly(outline(pentagon, start = 0.5))))
        expect(found?.size == 5)
    }

    // Ellissi

    @Test fun roundStrokeBecomesACircle() {
        val shape = ShapeRecognizer.recognize(wobbly(round(pt(100, 100), 100.0, 94.0)))
        val e = shape as? InkShape.Ellipse ?: return fail("non è tondo: $shape")
        expect(e.radii.width == e.radii.height)
        expect(near(e.center, pt(100, 100), 4.0))
    }

    @Test fun turnedOvalKeepsItsAxes() {
        val e = ShapeRecognizer.recognize(round(pt(0, 0), 150.0, 60.0, turn = 0.6)) as? InkShape.Ellipse
            ?: return fail("non è un'ellisse")
        expect(abs(e.radii.width - 150) < 2 && abs(e.radii.height - 60) < 2)
        expect(abs(abs(e.angle) - 0.6) < 0.02)
    }

    // Lasciati come sono

    @Test fun handwritingAndScribblesStayAsTheyAre() {
        // Cifre e lettere grandi come la scrittura, come 1 e 0.
        val one = (0..20).map { pt(10 + it * 0.2, it) }
        val zero = round(pt(10, 10), 6.0, 10.0)
        expect(ShapeRecognizer.recognize(one) == null)
        expect(ShapeRecognizer.recognize(zero) == null)
        val zigzag = (0 until 80).map { pt(it * 4, (it % 10) * 6) }
        expect(ShapeRecognizer.recognize(zigzag) == null)
    }

    @Test fun digitsAtShapeSizeStayAsTheyAre() {
        // Un 2: un uncino, poi un angolo netto verso la base.
        val hook = round(pt(50, 40), 30.0, 30.0, turn = -PI, upTo = 1.25 * PI)
        val last = hook.last()
        val two = hook + (1..20).map { i -> Point(last.x + (20 - last.x) * i / 20, last.y + (120 - last.y) * i / 20) } +
            (1..20).map { pt(20 + it * 4, 120) }
        expect(ShapeRecognizer.recognize(two) == null)
        // Un 7: di traverso, poi giù di colpo.
        val seven = (0..20).map { pt(it * 5, 0) } + (1..30).map { pt(100 - it * 1.5, it * 4) }
        expect(ShapeRecognizer.recognize(seven) == null)
        // Un 3: due gobbe che si incontrano in un punto.
        val top = round(pt(50, 30), 30.0, 30.0, turn = -PI / 2, upTo = PI)
        val bottom = round(pt(50, 90), 30.0, 30.0, turn = -PI / 2, upTo = PI)
        expect(ShapeRecognizer.recognize(top + bottom) == null)
    }

    // Archi e curve

    @Test fun halfCircleBecomesAnArc() {
        val drawn = wobbly(round(pt(100, 100), 100.0, 100.0, upTo = PI), amount = 1.5)
        val arc = ShapeRecognizer.recognize(drawn) as? InkShape.Arc ?: return fail("non è un arco")
        expect(near(arc.start, pt(200, 100), 6.0))
        expect(near(arc.end, pt(0, 100), 6.0))
        expect(near(arc.through, pt(100, 200), 6.0))
    }

    @Test fun arcOutlineFollowsItsCircle() {
        val arc = InkShape.Arc(pt(100, 0), pt(0, 100), pt(-100, 0))
        val points = arc.outline()
        expect(points.all { abs(hypot(it.x, it.y) - 100) < 0.01 })
        // Passa per il basso, non per l'alto.
        expect(points.all { it.y >= -0.01 })
        expect(near(points.first(), pt(100, 0), 0.01) && near(points.last(), pt(-100, 0), 0.01))
    }

    @Test fun waveBecomesASmoothCurve() {
        val wave = (0..80).map { pt(it * 4, 100 + 40 * sin(it * 4.0 / 320 * 2 * PI)) }
        val curve = ShapeRecognizer.recognize(wave) as? InkShape.Curve ?: return fail("non è una curva")
        expect(curve.controls.size in 4..8)
        expect(near(curve.controls.first(), wave.first(), 0.01) && near(curve.controls.last(), wave.last(), 0.01))
        val line = InkShape.Curve(curve.controls).outline()
        val worst = wave.maxOf { p -> line.minOf { hypot(it.x - p.x, it.y - p.y) } }
        expect(worst < 8)
    }

    @Test fun shapesSurviveSaving() {
        val shapes: List<InkShape> = listOf(
            InkShape.Line(Point.ZERO, pt(1, 2)),
            InkShape.Arc(Point.ZERO, pt(5, 5), pt(10, 0)),
            InkShape.Curve(listOf(Point.ZERO, pt(3, 4), pt(9, 1), pt(12, 6))),
            InkShape.Ellipse(pt(4, 4), Size(3.0, 2.0), 0.3),
            InkShape.Polygon(listOf(Point.ZERO, pt(3, 0), pt(3, 3))),
        )
        val serializer = ListSerializer(InkShape.serializer())
        val data = Json.encodeToString(serializer, shapes)
        expect(Json.decodeFromString(serializer, data) == shapes)
    }

    // Trascinare dopo l'aggancio

    @Test fun draggedLineEndFollowsThePencil() {
        val line = InkShape.Line(pt(0, 0), pt(100, 0))
        val anchor = line.anchor(pt(100, 0))
        expect(anchor == pt(0, 0))
        val dragged = line.dragged(anchor, pt(100, 0), pt(60, 80)) as? InkShape.Line ?: return fail("non è una linea")
        expect(near(dragged.a, Point.ZERO, 0.01) && near(dragged.b, pt(60, 80), 0.01))
    }

    @Test fun draggedRectangleKeepsTheOppositeCorner() {
        val square = InkShape.Polygon(listOf(pt(0, 0), pt(100, 0), pt(100, 100), pt(0, 100)))
        val anchor = square.anchor(pt(100, 100))
        expect(anchor == Point.ZERO)
        val bigger = corners(square.dragged(anchor, pt(100, 100), pt(150, 150))) ?: return fail("non è un poligono")
        expect(sides(bigger).all { abs(it - 150) < 0.01 })
        expect(near(bigger[0], Point.ZERO, 0.01))
    }

    @Test fun draggedCircleStaysACircle() {
        val circle = InkShape.Ellipse(pt(50, 0), Size(50.0, 50.0), 0.0)
        val anchor = circle.anchor(pt(100, 0))
        val e = circle.dragged(anchor, pt(100, 0), pt(0, 200)) as? InkShape.Ellipse ?: return fail("non è un'ellisse")
        expect(abs(e.radii.width - 100) < 0.5 && e.radii.width == e.radii.height && e.angle == 0.0)
    }

    // Contorno

    @Test fun outlineIsClosedAndDense() {
        val square = InkShape.Polygon(listOf(pt(0, 0), pt(40, 0), pt(40, 40), pt(0, 40)))
        val points = square.outline(4.0)
        expect(points.first() == points.last())
        expect(points.size == 41)
        expect(points.zipWithNext().all { (a, b) -> hypot(b.x - a.x, b.y - a.y) <= 4.001 })
    }

    @Test fun resamplingGivesEvenlySpacedPoints() {
        val points = ShapeRecognizer.resampled(listOf(pt(0, 0), pt(630, 0)), 64)
        expect(points.size == 64)
        expect(points.zipWithNext().all { (a, b) -> abs((b.x - a.x) - 10) < 0.01 })
    }
}
