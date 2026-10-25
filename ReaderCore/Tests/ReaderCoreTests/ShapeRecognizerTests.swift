import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

/// Points along the segments that join `corners`, `step` points apart, closed back to the first corner.
private func trace(_ corners: [CGPoint], closed: Bool = true, step: Int = 6) -> [CGPoint] {
    let ring = closed ? corners + [corners[0]] : corners
    return zip(ring, ring.dropFirst()).flatMap { a, b in
        (0..<step).map { i in
            let t = CGFloat(i) / CGFloat(step)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    } + [ring.last!]
}

private func circle(center: CGPoint, radius: CGFloat, count: Int = 60) -> [CGPoint] {
    (0...count).map { i in
        let angle = CGFloat(i) / CGFloat(count) * 2 * .pi
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

struct ShapeRecognizerTests {
    @Test func straightStrokeBecomesALine() {
        let points = trace([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 4)], closed: false)
        #expect(ShapeRecognizer.recognize(points) == .line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 4)))
    }

    @Test func bentStrokeIsNotALine() {
        let points = trace([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 200, y: 0)], closed: false)
        #expect(ShapeRecognizer.recognize(points) == nil)
    }

    @Test func roundStrokeBecomesACircle() {
        let shape = ShapeRecognizer.recognize(circle(center: CGPoint(x: 100, y: 100), radius: 60))
        guard case let .ellipse(box)? = shape else {
            Issue.record("expected an ellipse, got \(String(describing: shape))")
            return
        }
        #expect(abs(box.width - box.height) < 4)
        #expect(abs(box.midX - 100) < 2 && abs(box.midY - 100) < 2)
    }

    @Test func closedRectangleBecomesARectangle() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 220, y: 0), CGPoint(x: 220, y: 90), CGPoint(x: 0, y: 90)]
        let shape = ShapeRecognizer.recognize(trace(corners))
        guard case let .polygon(vertices)? = shape else {
            Issue.record("expected a polygon, got \(String(describing: shape))")
            return
        }
        #expect(vertices.count == 4)
        #expect(vertices.contains(CGPoint(x: 220, y: 90)))
    }

    @Test func nearlyEqualSidesBecomeASquare() {
        let corners = [CGPoint(x: 10, y: 10), CGPoint(x: 150, y: 12), CGPoint(x: 148, y: 150), CGPoint(x: 8, y: 146)]
        let shape = ShapeRecognizer.recognize(trace(corners))
        guard case let .polygon(vertices)? = shape else {
            Issue.record("expected a square, got \(String(describing: shape))")
            return
        }
        let width = vertices[1].x - vertices[0].x
        let height = vertices[3].y - vertices[0].y
        #expect(abs(width - height) < 0.01)
    }

    @Test func closedTriangleBecomesATriangle() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 160, y: 0), CGPoint(x: 80, y: 140)]
        let shape = ShapeRecognizer.recognize(trace(corners))
        guard case let .polygon(vertices)? = shape else {
            Issue.record("expected a triangle, got \(String(describing: shape))")
            return
        }
        #expect(vertices.count == 3)
    }

    @Test func smallMarksAreLeftAlone() {
        let points = trace([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)], closed: false)
        #expect(ShapeRecognizer.recognize(points) == nil)
        #expect(ShapeRecognizer.recognize(circle(center: .zero, radius: 12)) == nil)
    }

    @Test func openCurveIsNotAShape() {
        let arc = (0...40).map { i -> CGPoint in
            let angle = CGFloat(i) / 40 * .pi
            return CGPoint(x: cos(angle) * 100, y: sin(angle) * 100)
        }
        #expect(ShapeRecognizer.recognize(arc) == nil)
    }

    @Test func tooFewPointsAreNotRecognized() {
        #expect(ShapeRecognizer.recognize([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)]) == nil)
    }
}
