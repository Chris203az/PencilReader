package it.pencilreader.core

import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/// Una pagina di 3 righe x 5 parole, parole 80x24, distanti 16, passo di riga 36.
private val grid: List<Rect> = (0 until 3).flatMap { line ->
    (0 until 5).map { col -> rect(100 + col * 96, 100 + line * 36, 80, 24) }
}

private fun index(line: Int, col: Int) = line * 5 + col

private fun ellipse(
    around: Rect, padX: Double = 10.0, padY: Double = 8.0,
    from: Double = 0.0, to: Double = 2 * PI, steps: Int = 60,
): List<Point> {
    val rx = around.width / 2 + padX
    val ry = around.height / 2 + padY
    return (0..steps).map { i ->
        val a = from + (to - from) * i / steps
        Point(around.midX + rx * cos(a), around.midY + ry * sin(a))
    }
}

class LassoSelectorTest {
    @Test fun circleAroundOneWord() {
        val target = grid[index(1, 2)]
        expect(LassoSelector.select(ellipse(target), grid) == listOf(index(1, 2)))
    }

    @Test fun ovalAroundTwoWords() {
        val span = grid[index(0, 1)].union(grid[index(0, 2)])
        expect(LassoSelector.select(ellipse(span), grid) == listOf(index(0, 1), index(0, 2)))
    }

    @Test fun openCShapeStillSelects() {
        val target = grid[index(2, 0)]
        val stroke = ellipse(target, from = 0.4, to = 2 * PI - 0.4)
        expect(LassoSelector.select(stroke, grid) == listOf(index(2, 0)))
    }

    @Test fun sloppyCircleClippingNeighbourEdge() {
        // Spostato a destra, così morde circa il 20% della parola accanto.
        val target = grid[index(1, 1)]
        val stroke = ellipse(target.offsetBy(14.0, 0.0), padX = 12.0)
        expect(LassoSelector.select(stroke, grid) == listOf(index(1, 1)))
    }

    @Test fun overlappingLoopEnds() {
        val target = grid[index(1, 3)]
        val stroke = ellipse(target, from = 0.0, to = 2.4 * PI, steps = 80)
        expect(LassoSelector.select(stroke, grid) == listOf(index(1, 3)))
    }

    @Test fun tinyLoopInsideWord() {
        val target = grid[index(0, 4)]
        val stroke = ellipse(target.insetBy(30.0, 9.0), padX = 0.0, padY = 0.0)
        expect(LassoSelector.select(stroke, grid) == listOf(index(0, 4)))
    }

    @Test fun underlineSelectsWordsAbove() {
        val a = grid[index(0, 1)]
        val b = grid[index(0, 2)]
        val stroke = generateSequence(a.minX) { it + 8 }.takeWhile { it <= b.maxX }.map { Point(it, a.maxY + 4) }.toList()
        expect(LassoSelector.select(stroke, grid) == listOf(index(0, 1), index(0, 2)))
    }

    @Test fun strikeThrough() {
        val a = grid[index(2, 3)]
        val stroke = generateSequence(a.minX - 4) { it + 6 }.takeWhile { it <= a.maxX + 4 }.map { Point(it, a.midY) }.toList()
        expect(LassoSelector.select(stroke, grid) == listOf(index(2, 3)))
    }

    @Test fun circleInEmptyMargin() {
        val empty = rect(700, 400, 80, 24)
        expect(LassoSelector.select(ellipse(empty), grid).isEmpty())
    }

    @Test fun singleTapSelectsNothing() {
        expect(LassoSelector.select(listOf(pt(150, 110)), grid).isEmpty())
    }
}
