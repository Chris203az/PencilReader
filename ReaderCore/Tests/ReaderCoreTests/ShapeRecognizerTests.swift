import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

/// Points along the closed outline through `corners`, starting `start` of the way round, back to the start.
private func outline(_ corners: [CGPoint], start: Double = 0, perSide: Int = 30) -> [CGPoint] {
    var points: [CGPoint] = []
    for (i, a) in corners.enumerated() {
        let b = corners[(i + 1) % corners.count]
        for j in 0..<perSide {
            let t = CGFloat(j) / CGFloat(perSide)
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }
    let shift = Int(start * Double(points.count))
    let rotated = Array(points[shift...] + points[..<shift])
    return rotated + [rotated[0]]
}

/// A slow, regular wobble, like a hand that is not perfectly steady.
private func wobbly(_ points: [CGPoint], by amount: CGFloat = 2) -> [CGPoint] {
    points.enumerated().map { i, p in
        CGPoint(x: p.x + amount * sin(CGFloat(i) * 0.3), y: p.y + amount * cos(CGFloat(i) * 0.23))
    }
}

private func round(center: CGPoint, rx: CGFloat, ry: CGFloat, turn: CGFloat = 0, upTo end: CGFloat = 2 * .pi) -> [CGPoint] {
    (0...60).map { i in
        let t = end * CGFloat(i) / 60
        let x = rx * cos(t), y = ry * sin(t)
        return CGPoint(x: center.x + x * cos(turn) - y * sin(turn), y: center.y + x * sin(turn) + y * cos(turn))
    }
}

private func corners(of shape: InkShape?) -> [CGPoint]? {
    if case .polygon(let corners) = shape { return corners }
    return nil
}

private func sides(_ corners: [CGPoint]) -> [CGFloat] {
    corners.indices.map { i in
        let next = corners[(i + 1) % corners.count]
        return hypot(next.x - corners[i].x, next.y - corners[i].y)
    }
}

private func near(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 1) -> Bool {
    hypot(a.x - b.x, a.y - b.y) <= tolerance
}

struct ShapeRecognizerTests {
    // MARK: Lines

    @Test func nearlyHorizontalLineBecomesHorizontal() {
        let points = wobbly((0...80).map { CGPoint(x: 100 + CGFloat($0) * 3, y: 200 + CGFloat($0) * 0.1) }, by: 1)
        guard case .line(let a, let b) = ShapeRecognizer.recognize(points) else {
            Issue.record("not a line")
            return
        }
        #expect(abs(a.y - b.y) < 0.001)
    }

    @Test func slantedLineKeepsItsDirection() {
        let points = (0...80).map { CGPoint(x: CGFloat($0) * 3, y: CGFloat($0) * 2) }
        guard case .line(let a, let b) = ShapeRecognizer.recognize(points) else {
            Issue.record("not a line")
            return
        }
        #expect(near(a, points[0]) && near(b, points[80]))
    }

    @Test func bentStrokeIsNotALine() {
        let bent = outline([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 200, y: 0)]).prefix(61)
        #expect(ShapeRecognizer.recognize(Array(bent)) == nil)
    }

    // MARK: Polygons

    @Test func squareStartedMidSideBecomesASquare() {
        let drawn = wobbly(outline([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 4), CGPoint(x: 196, y: 210), CGPoint(x: -4, y: 200)],
                                   start: 0.1))
        guard let square = corners(of: ShapeRecognizer.recognize(drawn)) else {
            Issue.record("not a polygon")
            return
        }
        #expect(square.count == 4)
        let lengths = sides(square)
        #expect(lengths.allSatisfy { abs($0 - lengths[0]) < 0.001 })
        // Sides straightened to the axes.
        #expect(abs(square[0].y - square[1].y) < 0.001 || abs(square[0].x - square[1].x) < 0.001)
    }

    @Test func turnedRectangleKeepsItsAngleAndSize() {
        let turn: CGFloat = 0.5
        let flat = [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 120), CGPoint(x: 0, y: 120)]
        let drawn = outline(flat.map { CGPoint(x: $0.x * cos(turn) - $0.y * sin(turn), y: $0.x * sin(turn) + $0.y * cos(turn)) },
                            start: 0.4)
        guard let rectangle = corners(of: ShapeRecognizer.recognize(drawn)) else {
            Issue.record("not a polygon")
            return
        }
        #expect(rectangle.count == 4)
        let lengths = sides(rectangle).sorted()
        #expect(abs(lengths[0] - 120) < 2 && abs(lengths[3] - 300) < 2)
    }

    @Test func triangleKeepsItsThreeCorners() {
        let triangle = [CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 180), CGPoint(x: 0, y: 180)]
        guard let found = corners(of: ShapeRecognizer.recognize(wobbly(outline(triangle, start: 0.3)))) else {
            Issue.record("not a polygon")
            return
        }
        #expect(found.count == 3)
        #expect(triangle.allSatisfy { corner in found.contains { near($0, corner, within: 8) } })
    }

    @Test func pentagonIsAPolygonNotACircle() {
        let pentagon: [CGPoint] = (0..<5).map { i in
            let angle: CGFloat = 2 * CGFloat.pi * CGFloat(i) / 5
            return CGPoint(x: 100 + 100 * cos(angle), y: 100 + 100 * sin(angle))
        }
        let found = corners(of: ShapeRecognizer.recognize(wobbly(outline(pentagon, start: 0.5))))
        #expect(found?.count == 5)
    }

    // MARK: Ellipses

    @Test func roundStrokeBecomesACircle() {
        let shape = ShapeRecognizer.recognize(wobbly(round(center: CGPoint(x: 100, y: 100), rx: 100, ry: 94)))
        guard case .ellipse(let center, let radii, _) = shape else {
            Issue.record("not round: \(String(describing: shape))")
            return
        }
        #expect(radii.width == radii.height)
        #expect(near(center, CGPoint(x: 100, y: 100), within: 4))
    }

    @Test func turnedOvalKeepsItsAxes() {
        let shape = ShapeRecognizer.recognize(round(center: CGPoint(x: 0, y: 0), rx: 150, ry: 60, turn: 0.6))
        guard case .ellipse(_, let radii, let angle) = shape else {
            Issue.record("not an ellipse")
            return
        }
        #expect(abs(radii.width - 150) < 2 && abs(radii.height - 60) < 2)
        #expect(abs(abs(angle) - 0.6) < 0.02)
    }

    // MARK: Left alone

    @Test func handwritingAndScribblesStayAsTheyAre() {
        // Digits and letters at writing size, such as 1 and 0.
        let one = (0...20).map { CGPoint(x: 10 + CGFloat($0) * 0.2, y: CGFloat($0)) }
        let zero = round(center: CGPoint(x: 10, y: 10), rx: 6, ry: 10)
        #expect(ShapeRecognizer.recognize(one) == nil)
        #expect(ShapeRecognizer.recognize(zero) == nil)
        let zigzag = (0..<80).map { CGPoint(x: CGFloat($0) * 4, y: CGFloat($0 % 10) * 6) }
        #expect(ShapeRecognizer.recognize(zigzag) == nil)
    }

    @Test func digitsAtShapeSizeStayAsTheyAre() {
        // A 2: a hook, then a sharp corner into the base.
        let hook = round(center: CGPoint(x: 50, y: 40), rx: 30, ry: 30, turn: -.pi, upTo: 1.25 * .pi)
        let two = hook + (1...20).map { i in CGPoint(x: hook.last!.x + (20 - hook.last!.x) * CGFloat(i) / 20,
                                                   y: hook.last!.y + (120 - hook.last!.y) * CGFloat(i) / 20) }
            + (1...20).map { CGPoint(x: 20 + CGFloat($0) * 4, y: 120) }
        #expect(ShapeRecognizer.recognize(two) == nil)
        // A 7: across, then sharply down.
        let seven = (0...20).map { CGPoint(x: CGFloat($0) * 5, y: 0) } + (1...30).map { CGPoint(x: 100 - CGFloat($0) * 1.5, y: CGFloat($0) * 4) }
        #expect(ShapeRecognizer.recognize(seven) == nil)
        // A 3: two bumps meeting in a point.
        let top = round(center: CGPoint(x: 50, y: 30), rx: 30, ry: 30, turn: -.pi / 2, upTo: .pi)
        let bottom = round(center: CGPoint(x: 50, y: 90), rx: 30, ry: 30, turn: -.pi / 2, upTo: .pi)
        #expect(ShapeRecognizer.recognize(top + bottom) == nil)
    }

    // MARK: Arcs and curves

    @Test func halfCircleBecomesAnArc() {
        let drawn = wobbly(round(center: CGPoint(x: 100, y: 100), rx: 100, ry: 100, upTo: .pi), by: 1.5)
        guard case .arc(let start, let through, let end) = ShapeRecognizer.recognize(drawn) else {
            Issue.record("not an arc")
            return
        }
        #expect(near(start, CGPoint(x: 200, y: 100), within: 6))
        #expect(near(end, CGPoint(x: 0, y: 100), within: 6))
        #expect(near(through, CGPoint(x: 100, y: 200), within: 6))
    }

    @Test func arcOutlineFollowsItsCircle() {
        let arc = InkShape.arc(start: CGPoint(x: 100, y: 0), through: CGPoint(x: 0, y: 100), end: CGPoint(x: -100, y: 0))
        let points = arc.outline()
        #expect(points.allSatisfy { abs(hypot($0.x, $0.y) - 100) < 0.01 })
        // Through the bottom, not the top.
        #expect(points.allSatisfy { $0.y >= -0.01 })
        #expect(near(points.first!, CGPoint(x: 100, y: 0), within: 0.01) && near(points.last!, CGPoint(x: -100, y: 0), within: 0.01))
    }

    @Test func waveBecomesASmoothCurve() {
        let wave = (0...80).map { CGPoint(x: CGFloat($0) * 4, y: 100 + 40 * sin(CGFloat($0) * 4 / 320 * 2 * .pi)) }
        guard case .curve(let controls) = ShapeRecognizer.recognize(wave) else {
            Issue.record("not a curve")
            return
        }
        #expect((4...8).contains(controls.count))
        #expect(near(controls.first!, wave.first!, within: 0.01) && near(controls.last!, wave.last!, within: 0.01))
        let curve = InkShape.curve(controls).outline()
        let worst = wave.map { p in curve.map { hypot($0.x - p.x, $0.y - p.y) }.min()! }.max()!
        #expect(worst < 8)
    }

    @Test func shapesSurviveSaving() throws {
        let shapes: [InkShape] = [
            .line(.zero, CGPoint(x: 1, y: 2)),
            .arc(start: .zero, through: CGPoint(x: 5, y: 5), end: CGPoint(x: 10, y: 0)),
            .curve([.zero, CGPoint(x: 3, y: 4), CGPoint(x: 9, y: 1), CGPoint(x: 12, y: 6)]),
            .ellipse(center: CGPoint(x: 4, y: 4), radii: CGSize(width: 3, height: 2), angle: 0.3)
        ]
        let data = try JSONEncoder().encode(shapes)
        #expect(try JSONDecoder().decode([InkShape].self, from: data) == shapes)
    }

    // MARK: Dragging after the snap

    @Test func draggedLineEndFollowsThePencil() {
        let line = InkShape.line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        let anchor = line.anchor(oppositeTo: CGPoint(x: 100, y: 0))
        #expect(anchor == CGPoint(x: 0, y: 0))
        guard case .line(let a, let b) = line.dragged(anchor: anchor, from: CGPoint(x: 100, y: 0), to: CGPoint(x: 60, y: 80)) else {
            Issue.record("not a line")
            return
        }
        #expect(near(a, .zero, within: 0.01) && near(b, CGPoint(x: 60, y: 80), within: 0.01))
    }

    @Test func draggedRectangleKeepsTheOppositeCorner() {
        let square = InkShape.polygon([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)])
        let anchor = square.anchor(oppositeTo: CGPoint(x: 100, y: 100))
        #expect(anchor == .zero)
        guard let bigger = corners(of: square.dragged(anchor: anchor, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 150))) else {
            Issue.record("not a polygon")
            return
        }
        #expect(sides(bigger).allSatisfy { abs($0 - 150) < 0.01 })
        #expect(near(bigger[0], .zero, within: 0.01))
    }

    @Test func draggedCircleStaysACircle() {
        let circle = InkShape.ellipse(center: CGPoint(x: 50, y: 0), radii: CGSize(width: 50, height: 50), angle: 0)
        let anchor = circle.anchor(oppositeTo: CGPoint(x: 100, y: 0))
        guard case .ellipse(_, let radii, let angle) = circle.dragged(anchor: anchor, from: CGPoint(x: 100, y: 0),
                                                                      to: CGPoint(x: 0, y: 200)) else {
            Issue.record("not an ellipse")
            return
        }
        #expect(abs(radii.width - 100) < 0.5 && radii.width == radii.height && angle == 0)
    }

    // MARK: Outline

    @Test func outlineIsClosedAndDense() {
        let square = InkShape.polygon([CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 40), CGPoint(x: 0, y: 40)])
        let points = square.outline(spacing: 4)
        #expect(points.first == points.last)
        #expect(points.count == 41)
        #expect(zip(points, points.dropFirst()).allSatisfy { hypot($1.x - $0.x, $1.y - $0.y) <= 4.001 })
    }

    @Test func resamplingGivesEvenlySpacedPoints() {
        let points = ShapeRecognizer.resampled([CGPoint(x: 0, y: 0), CGPoint(x: 630, y: 0)], count: 64)
        #expect(points.count == 64)
        #expect(zip(points, points.dropFirst()).allSatisfy { abs(($1.x - $0.x) - 10) < 0.01 })
    }
}
