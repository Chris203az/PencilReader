package it.pencilreader.core

import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

private fun line(a: Point, b: Point, count: Int = 20): List<Point> = (0..count).map { i ->
    val t = i.toDouble() / count
    Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
}

private fun close(a: Point, b: Point, within: Double = 0.01) = hypot(a.x - b.x, a.y - b.y) <= within
private fun close(a: Double, b: Double, within: Double = 0.0001) = abs(a - b) <= within

class StrokeLassoTest {
    private val square = listOf(pt(0, 0), pt(100, 0), pt(100, 100), pt(0, 100))

    @Test fun takesStrokesMostlyInside() {
        val inside = line(pt(10, 50), pt(90, 50))
        val outside = line(pt(150, 50), pt(250, 50))
        // Tre quarti dentro.
        val across = line(pt(25, 20), pt(125, 20))
        // Un quarto dentro.
        val mostlyOut = line(pt(75, 80), pt(175, 80))
        expect(StrokeLasso.selected(listOf(inside, outside, across, mostlyOut), square) == listOf(0, 2))
    }

    @Test fun anOpenLassoIsClosedBetweenItsEnds() {
        val open = square.dropLast(1) + pt(0, 90)
        val stroke = line(pt(20, 50), pt(80, 50))
        expect(StrokeLasso.selected(listOf(stroke), open) == listOf(0))
    }

    @Test fun aTapSelectsNothing() {
        val stroke = line(pt(20, 50), pt(80, 50))
        expect(StrokeLasso.selected(listOf(stroke), listOf(pt(50, 50), pt(51, 50))).isEmpty())
    }
}

class SelectionFrameTest {
    private val rect = rect(100, 100, 200, 100)

    @Test fun startsWithoutChangingAnything() {
        val frame = SelectionFrame.around(rect)
        expect(frame.transform.isIdentity)
        expect(close(frame.corners[0], pt(100, 100)))
        expect(close(frame.corners[2], pt(300, 200)))
    }

    @Test fun movingCarriesTheStrokes() {
        val frame = SelectionFrame.around(rect).moved(pt(150, 150), pt(180, 110))
        expect(close(pt(100, 100).applying(frame.transform), pt(130, 60)))
    }

    @Test fun aCornerKeepsTheProportionsAndTheOppositeCorner() {
        val frame = SelectionFrame.around(rect)
        // Trascinato lungo la diagonale e un po' fuori.
        val bigger = frame.resized(SelectionHandle.BOTTOM_RIGHT, pt(300, 200), pt(500, 290))
        expect(close(bigger.size.width / bigger.size.height, 2.0))
        expect(bigger.size.width > 300)
        expect(close(pt(100, 100).applying(bigger.transform), pt(100, 100)))
        expect(close(pt(300, 200).applying(bigger.transform), bigger.corners[2]))
    }

    @Test fun aSideStretchesOneWayOnly() {
        val frame = SelectionFrame.around(rect)
        val taller = frame.resized(SelectionHandle.BOTTOM, pt(200, 200), pt(260, 250))
        expect(close(taller.size.width, 200.0))
        expect(close(taller.size.height, 150.0))
        expect(close(pt(100, 100).applying(taller.transform), pt(100, 100)))
        val narrower = frame.resized(SelectionHandle.LEFT, pt(100, 150), pt(160, 150))
        expect(close(narrower.size.width, 140.0))
        expect(close(narrower.corners[1], pt(300, 100)))
    }

    @Test fun theBoxNeverFlips() {
        val frame = SelectionFrame.around(rect)
        val squeezed = frame.resized(SelectionHandle.RIGHT, pt(300, 150), pt(0, 150))
        expect(squeezed.size.width == SelectionFrame.MINIMUM_SIDE)
        val tiny = frame.resized(SelectionHandle.TOP_LEFT, pt(100, 100), pt(900, 900))
        expect(minOf(tiny.size.width, tiny.size.height) >= SelectionFrame.MINIMUM_SIDE - 0.001)
    }

    @Test fun turnsAroundTheCenter() {
        val frame = SelectionFrame.around(rect)
        // Da sopra il centro alla sua destra: un quarto di giro in senso orario.
        val turned = frame.rotated(pt(200, 50), pt(260, 150))
        expect(close(turned.angle, PI / 2))
        expect(close(pt(200, 150).applying(turned.transform), pt(200, 150)))
        expect(close(pt(300, 150).applying(turned.transform), pt(200, 250)))
    }

    @Test fun snapsToQuarterTurns() {
        val frame = SelectionFrame.around(rect)
        val center = pt(200, 150)
        fun pointer(degrees: Double): Point {
            val a = degrees * PI / 180
            return Point(center.x + 100 * cos(a), center.y + 100 * sin(a))
        }
        expect(frame.rotated(pointer(0.0), pointer(93.0)).angle == PI / 2)
        expect(frame.rotated(pointer(0.0), pointer(-4.0)).angle == 0.0)
        expect(close(frame.rotated(pointer(0.0), pointer(30.0)).angle, PI / 6))
        expect(close(abs(frame.rotated(pointer(0.0), pointer(178.0)).angle), PI))
    }

    @Test fun resizingATurnedBoxFollowsItsSides() {
        val frame = SelectionFrame.around(rect).copy(angle = PI / 2)
        // Girato di un quarto, il lato destro del riquadro guarda in basso sulla pagina.
        val start = frame.position(SelectionHandle.RIGHT, 0.0)
        expect(close(start, pt(200, 250)))
        val longer = frame.resized(SelectionHandle.RIGHT, start, Point(start.x, start.y + 50))
        expect(close(longer.size.width, 250.0))
        expect(close(longer.size.height, 100.0))
    }

    @Test fun findsTheGripUnderThePointer() {
        val frame = SelectionFrame.around(rect)
        expect(frame.handle(pt(103, 98), 20.0, 30.0) == SelectionHandle.TOP_LEFT)
        expect(frame.handle(pt(200, 72), 20.0, 30.0) == SelectionHandle.ROTATE)
        expect(frame.handle(pt(200, 150), 20.0, 30.0) == null)
        expect(frame.contains(pt(200, 150)))
        expect(!frame.contains(pt(350, 150)))
        expect(frame.contains(pt(305, 150), slack = 10.0))
    }
}
