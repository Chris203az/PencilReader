import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

private func near(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 0.01) -> Bool {
    hypot(a.x - b.x, a.y - b.y) <= tolerance
}

struct ShapeEditingTests {
    private let rectangle = InkShape.polygon([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0),
                                              CGPoint(x: 200, y: 100), CGPoint(x: 0, y: 100)])

    @Test func aRectangleHasCornerAndSideGrips() {
        #expect(rectangle.isRectangle)
        #expect(rectangle.grips.count == 8)
        #expect(near(rectangle.grips[4], CGPoint(x: 100, y: 0)))
        let triangle = InkShape.polygon([.zero, CGPoint(x: 100, y: 0), CGPoint(x: 50, y: 80)])
        #expect(!triangle.isRectangle && triangle.grips.count == 3)
    }

    @Test func draggingACornerKeepsTheRectangleAndItsOppositeCorner() {
        guard case .polygon(let corners) = rectangle.reshaped(grip: 2, to: CGPoint(x: 300, y: 150)) else {
            Issue.record("not a polygon")
            return
        }
        #expect(near(corners[0], .zero))
        #expect(near(corners[1], CGPoint(x: 300, y: 0)))
        #expect(near(corners[2], CGPoint(x: 300, y: 150)))
        #expect(near(corners[3], CGPoint(x: 0, y: 150)))
    }

    @Test func draggingASideMovesOnlyThatSide() {
        // The right side (corners 1 and 2) pulled out, even with the finger a little off.
        guard case .polygon(let corners) = rectangle.reshaped(grip: 5, to: CGPoint(x: 260, y: 70)) else {
            Issue.record("not a polygon")
            return
        }
        #expect(near(corners[0], .zero) && near(corners[3], CGPoint(x: 0, y: 100)))
        #expect(near(corners[1], CGPoint(x: 260, y: 0)) && near(corners[2], CGPoint(x: 260, y: 100)))
        // Pushed past the opposite side, it stops just short of it.
        guard case .polygon(let squashed) = rectangle.reshaped(grip: 5, to: CGPoint(x: -50, y: 50)) else { return }
        #expect(abs(squashed[1].x - 4) < 0.01)
    }

    @Test func aTurnedRectangleStaysTurned() {
        let turn = CGAffineTransform(rotationAngle: 0.4)
        let turned = rectangle.applying(turn)
        #expect(turned.isRectangle)
        let wider = turned.reshaped(grip: 5, to: CGPoint(x: 300, y: 50).applying(turn))
        #expect(wider.isRectangle)
        guard case .polygon(let corners) = wider else { return }
        #expect(abs(hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y) - 300) < 0.01)
        #expect(abs(hypot(corners[3].x - corners[0].x, corners[3].y - corners[0].y) - 100) < 0.01)
    }

    @Test func aCircleGrowsAndStaysACircle() {
        let circle = InkShape.ellipse(center: CGPoint(x: 100, y: 100), radii: CGSize(width: 50, height: 50), angle: 0)
        #expect(circle.isCircle && circle.grips.count == 4)
        let bigger = circle.reshaped(grip: 2, to: CGPoint(x: 160, y: 180))
        guard case .ellipse(let center, let radii, _) = bigger else {
            Issue.record("not an ellipse")
            return
        }
        #expect(center == CGPoint(x: 100, y: 100))
        #expect(abs(radii.width - 100) < 0.01 && radii.width == radii.height)
    }

    @Test func anEllipseChangesOneAxisAtATime() {
        let oval = InkShape.ellipse(center: .zero, radii: CGSize(width: 80, height: 40), angle: 0)
        guard case .ellipse(_, let radii, let angle) = oval.reshaped(grip: 3, to: CGPoint(x: 10, y: -70)) else {
            Issue.record("not an ellipse")
            return
        }
        #expect(radii.width == 80 && abs(radii.height - 70) < 0.01 && angle == 0)
    }

    @Test func anArcEndMovesAndTheMiddleGripStaysInTheMiddle() {
        let arc = InkShape.arc(start: CGPoint(x: 100, y: 0), through: CGPoint(x: 0, y: 100), end: CGPoint(x: -100, y: 0))
        guard case .arc(let start, let through, let end) = arc.reshaped(grip: 2, to: CGPoint(x: 0, y: -100)) else {
            Issue.record("not an arc")
            return
        }
        #expect(near(start, CGPoint(x: 100, y: 0)) && near(end, CGPoint(x: 0, y: -100)))
        // Still on the circle of radius 100 around the origin, halfway round from start to end.
        #expect(abs(hypot(through.x, through.y) - 100) < 0.01)
        #expect(near(through, CGPoint(x: -100 / 2.squareRoot(), y: 100 / 2.squareRoot()), within: 0.05))
        // Dragging the middle changes how much it bends.
        guard case .arc(_, let bent, _) = arc.reshaped(grip: 1, to: CGPoint(x: 0, y: 40)) else { return }
        #expect(bent == CGPoint(x: 0, y: 40))
    }

    @Test func curveControlPointsMove() {
        let curve = InkShape.curve([.zero, CGPoint(x: 50, y: 30), CGPoint(x: 100, y: 0), CGPoint(x: 150, y: 30)])
        guard case .curve(let controls) = curve.reshaped(grip: 1, to: CGPoint(x: 50, y: 90)) else {
            Issue.record("not a curve")
            return
        }
        #expect(controls[1] == CGPoint(x: 50, y: 90) && controls[0] == .zero)
        // The curve goes through every control point.
        let outline = InkShape.curve(controls).outline()
        #expect(controls.allSatisfy { c in outline.contains { near($0, c, within: 0.5) } })
    }

    @Test func movingCarriesTheWholeShape() {
        let line = InkShape.line(.zero, CGPoint(x: 10, y: 0)).moved(by: CGPoint(x: 5, y: 7))
        #expect(line == .line(CGPoint(x: 5, y: 7), CGPoint(x: 15, y: 7)))
    }

    @Test func aStretchedCircleBecomesAnEllipse() {
        let circle = InkShape.ellipse(center: .zero, radii: CGSize(width: 10, height: 10), angle: 0)
        guard case .ellipse(_, let radii, let angle) = circle.applying(CGAffineTransform(scaleX: 1, y: 3)) else {
            Issue.record("not an ellipse")
            return
        }
        #expect(abs(radii.width - 30) < 0.01 && abs(radii.height - 10) < 0.01)
        #expect(abs(abs(angle) - .pi / 2) < 0.01)
        guard case .ellipse(_, let same, _) = circle.applying(CGAffineTransform(rotationAngle: 1).scaledBy(x: 2, y: 2)) else { return }
        #expect(abs(same.width - 20) < 0.01 && same.width == same.height)
    }

    @Test func tapsNearTheLineFindTheShape() {
        #expect(rectangle.outlineDistance(to: CGPoint(x: 100, y: 5)) < 6)
        #expect(rectangle.outlineDistance(to: CGPoint(x: 100, y: 50)) > 40)
    }
}
