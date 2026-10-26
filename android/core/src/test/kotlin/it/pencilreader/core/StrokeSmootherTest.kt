package it.pencilreader.core

import org.junit.Assert.fail
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

private fun shaky(points: List<Point>, amount: Double = 0.8): List<Point> =
    points.mapIndexed { i, p -> Point(p.x, p.y + if (i % 2 == 0) amount else -amount) }

private fun line(a: Point, b: Point, count: Int = 30): List<Point> = (0..count).map { i ->
    val t = i.toDouble() / count
    Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
}

class StrokeSmootherTest {
    @Test fun shakeIsReduced() {
        val points = shaky(line(pt(0, 0), pt(60, 0)))
        val smooth = StrokeSmoother.smoothed(points) ?: return fail("un tratto tremolante è stato lasciato com'era")
        val before = points.drop(1).dropLast(1).sumOf { abs(it.y) }
        val after = smooth.drop(1).dropLast(1).sumOf { abs(it.y) }
        expect(after < before / 2)
    }

    @Test fun noPointMovesMoreThanTheLimit() {
        val points = shaky(line(pt(0, 0), pt(60, 20)), amount = 3.0)
        val smooth = StrokeSmoother.smoothed(points) ?: points
        expect(smooth.size == points.size)
        for ((a, b) in points.zip(smooth)) expect(hypot(a.x - b.x, a.y - b.y) <= StrokeSmoother.MAX_SHIFT + 0.0001)
    }

    @Test fun shortStrokesMoveAtMostOnePoint() {
        val points = shaky(line(pt(0, 0), pt(12, 4), count = 14), amount = 2.0)
        if (StrokeSmoother.pathLength(points) >= StrokeSmoother.SHORT_LENGTH) return
        val smooth = StrokeSmoother.smoothed(points) ?: points
        for ((a, b) in points.zip(smooth)) expect(hypot(a.x - b.x, a.y - b.y) <= StrokeSmoother.SHORT_MAX_SHIFT + 0.0001)
    }

    @Test fun strengthLimitsTheShift() {
        val points = shaky(line(pt(0, 0), pt(80, 30), count = 40), amount = 5.0)
        for (strength in listOf(1.0, 2.0, 3.0, 4.0)) {
            val smooth = StrokeSmoother.smoothed(points, strength) ?: points
            for ((a, b) in points.zip(smooth)) expect(hypot(a.x - b.x, a.y - b.y) <= strength + 0.0001)
        }
    }

    @Test fun endsStayPut() {
        val points = shaky(line(pt(0, 0), pt(60, 0)))
        val smooth = StrokeSmoother.smoothed(points)!!
        expect(smooth.first() == points.first())
        expect(smooth.last() == points.last())
    }

    @Test fun cornersStaySharp() {
        // La punta di una freccia: una V netta.
        val points = line(pt(0, 0), pt(20, 20), count = 15) + line(pt(20, 20), pt(40, 0), count = 15).drop(1)
        val corner = 15
        val input = shaky(points, amount = 0.5)
        val smooth = StrokeSmoother.smoothed(input) ?: input
        expect(smooth[corner] == input[corner])
    }

    @Test fun dotsAndShortStrokesAreLeftAlone() {
        val dot = (0 until 6).map { pt(it * 0.3, 0) }
        expect(StrokeSmoother.smoothed(dot) == null)
        val short = shaky(line(Point.ZERO, pt(6, 0), count = 12), amount = 0.1)
        expect(StrokeSmoother.smoothed(short) == null)
    }

    @Test fun smoothStrokeIsLeftAlone() {
        expect(StrokeSmoother.smoothed(line(Point.ZERO, pt(60, 0))) == null)
    }
}
