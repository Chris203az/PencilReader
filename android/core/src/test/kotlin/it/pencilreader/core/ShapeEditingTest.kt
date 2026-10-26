package it.pencilreader.core

import org.junit.Assert.fail
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.sqrt

private fun near(a: Point, b: Point, within: Double = 0.01) = hypot(a.x - b.x, a.y - b.y) <= within

class ShapeEditingTest {
    private val rectangle = InkShape.Polygon(listOf(pt(0, 0), pt(200, 0), pt(200, 100), pt(0, 100)))

    @Test fun aRectangleHasCornerAndSideGrips() {
        expect(rectangle.isRectangle)
        expect(rectangle.grips.size == 8)
        expect(near(rectangle.grips[4], pt(100, 0)))
        val triangle = InkShape.Polygon(listOf(Point.ZERO, pt(100, 0), pt(50, 80)))
        expect(!triangle.isRectangle && triangle.grips.size == 3)
    }

    @Test fun draggingACornerKeepsTheRectangleAndItsOppositeCorner() {
        val corners = (rectangle.reshaped(2, pt(300, 150)) as? InkShape.Polygon)?.corners ?: return fail("non è un poligono")
        expect(near(corners[0], Point.ZERO))
        expect(near(corners[1], pt(300, 0)))
        expect(near(corners[2], pt(300, 150)))
        expect(near(corners[3], pt(0, 150)))
    }

    @Test fun draggingASideMovesOnlyThatSide() {
        // Il lato destro (angoli 1 e 2) tirato fuori, anche con il dito un po' fuori posto.
        val corners = (rectangle.reshaped(5, pt(260, 70)) as? InkShape.Polygon)?.corners ?: return fail("non è un poligono")
        expect(near(corners[0], Point.ZERO) && near(corners[3], pt(0, 100)))
        expect(near(corners[1], pt(260, 0)) && near(corners[2], pt(260, 100)))
        // Spinto oltre il lato opposto, si ferma poco prima.
        val squashed = (rectangle.reshaped(5, pt(-50, 50)) as InkShape.Polygon).corners
        expect(abs(squashed[1].x - 4) < 0.01)
    }

    @Test fun aTurnedRectangleStaysTurned() {
        val turn = AffineTransform.rotation(0.4)
        val turned = rectangle.applying(turn)
        expect(turned.isRectangle)
        val wider = turned.reshaped(5, pt(300, 50).applying(turn))
        expect(wider.isRectangle)
        val corners = (wider as InkShape.Polygon).corners
        expect(abs(hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y) - 300) < 0.01)
        expect(abs(hypot(corners[3].x - corners[0].x, corners[3].y - corners[0].y) - 100) < 0.01)
    }

    @Test fun aCircleGrowsAndStaysACircle() {
        val circle = InkShape.Ellipse(pt(100, 100), Size(50.0, 50.0), 0.0)
        expect(circle.isCircle && circle.grips.size == 4)
        val bigger = circle.reshaped(2, pt(160, 180)) as? InkShape.Ellipse ?: return fail("non è un'ellisse")
        expect(bigger.center == pt(100, 100))
        expect(abs(bigger.radii.width - 100) < 0.01 && bigger.radii.width == bigger.radii.height)
    }

    @Test fun anEllipseChangesOneAxisAtATime() {
        val oval = InkShape.Ellipse(Point.ZERO, Size(80.0, 40.0), 0.0)
        val e = oval.reshaped(3, pt(10, -70)) as? InkShape.Ellipse ?: return fail("non è un'ellisse")
        expect(e.radii.width == 80.0 && abs(e.radii.height - 70) < 0.01 && e.angle == 0.0)
    }

    @Test fun anArcEndMovesAndTheMiddleGripStaysInTheMiddle() {
        val arc = InkShape.Arc(pt(100, 0), pt(0, 100), pt(-100, 0))
        val moved = arc.reshaped(2, pt(0, -100)) as? InkShape.Arc ?: return fail("non è un arco")
        expect(near(moved.start, pt(100, 0)) && near(moved.end, pt(0, -100)))
        // Ancora sul cerchio di raggio 100 attorno all'origine, a metà strada dall'inizio alla fine.
        expect(abs(hypot(moved.through.x, moved.through.y) - 100) < 0.01)
        expect(near(moved.through, pt(-100 / sqrt(2.0), 100 / sqrt(2.0)), 0.05))
        // Trascinare il centro cambia quanto si piega.
        val bent = arc.reshaped(1, pt(0, 40)) as InkShape.Arc
        expect(bent.through == pt(0, 40))
    }

    @Test fun curveControlPointsMove() {
        val curve = InkShape.Curve(listOf(Point.ZERO, pt(50, 30), pt(100, 0), pt(150, 30)))
        val moved = curve.reshaped(1, pt(50, 90)) as? InkShape.Curve ?: return fail("non è una curva")
        expect(moved.controls[1] == pt(50, 90) && moved.controls[0] == Point.ZERO)
        // La curva passa per ogni punto di controllo.
        val outline = InkShape.Curve(moved.controls).outline()
        expect(moved.controls.all { c -> outline.any { near(it, c, 0.5) } })
    }

    @Test fun movingCarriesTheWholeShape() {
        val line = InkShape.Line(Point.ZERO, pt(10, 0)).moved(pt(5, 7))
        expect(line == InkShape.Line(pt(5, 7), pt(15, 7)))
    }

    @Test fun aStretchedCircleBecomesAnEllipse() {
        val circle = InkShape.Ellipse(Point.ZERO, Size(10.0, 10.0), 0.0)
        val e = circle.applying(AffineTransform.scale(1.0, 3.0)) as? InkShape.Ellipse ?: return fail("non è un'ellisse")
        expect(abs(e.radii.width - 30) < 0.01 && abs(e.radii.height - 10) < 0.01)
        expect(abs(abs(e.angle) - PI / 2) < 0.01)
        val same = (circle.applying(AffineTransform.rotation(1.0).scaledBy(2.0, 2.0)) as InkShape.Ellipse).radii
        expect(abs(same.width - 20) < 0.01 && same.width == same.height)
    }

    @Test fun tapsNearTheLineFindTheShape() {
        expect(rectangle.outlineDistance(pt(100, 5)) < 6)
        expect(rectangle.outlineDistance(pt(100, 50)) > 40)
    }
}
