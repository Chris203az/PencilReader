import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

private func line(from a: CGPoint, to b: CGPoint, count: Int = 20) -> [CGPoint] {
    (0...count).map { i in
        let t = CGFloat(i) / CGFloat(count)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

private func close(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 0.01) -> Bool {
    hypot(a.x - b.x, a.y - b.y) <= tolerance
}

private func close(_ a: CGFloat, _ b: CGFloat, within tolerance: CGFloat = 0.0001) -> Bool {
    abs(a - b) <= tolerance
}

struct StrokeLassoTests {
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    @Test func takesStrokesMostlyInside() {
        let inside = line(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50))
        let outside = line(from: CGPoint(x: 150, y: 50), to: CGPoint(x: 250, y: 50))
        // Three quarters inside.
        let across = line(from: CGPoint(x: 25, y: 20), to: CGPoint(x: 125, y: 20))
        // A quarter inside.
        let mostlyOut = line(from: CGPoint(x: 75, y: 80), to: CGPoint(x: 175, y: 80))
        let picked = StrokeLasso.selected(strokes: [inside, outside, across, mostlyOut], lasso: square)
        #expect(picked == [0, 2])
    }

    @Test func anOpenLassoIsClosedBetweenItsEnds() {
        let open = Array(square.dropLast()) + [CGPoint(x: 0, y: 90)]
        let stroke = line(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 80, y: 50))
        #expect(StrokeLasso.selected(strokes: [stroke], lasso: open) == [0])
    }

    @Test func aTapSelectsNothing() {
        let stroke = line(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 80, y: 50))
        #expect(StrokeLasso.selected(strokes: [stroke], lasso: [CGPoint(x: 50, y: 50), CGPoint(x: 51, y: 50)]).isEmpty)
    }
}

struct SelectionFrameTests {
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func startsWithoutChangingAnything() {
        let frame = SelectionFrame(around: rect)
        #expect(frame.transform.isIdentity)
        #expect(close(frame.corners[0], CGPoint(x: 100, y: 100)))
        #expect(close(frame.corners[2], CGPoint(x: 300, y: 200)))
    }

    @Test func movingCarriesTheStrokes() {
        let frame = SelectionFrame(around: rect).moved(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 180, y: 110))
        #expect(close(CGPoint(x: 100, y: 100).applying(frame.transform), CGPoint(x: 130, y: 60)))
    }

    @Test func aCornerKeepsTheProportionsAndTheOppositeCorner() {
        let frame = SelectionFrame(around: rect)
        // Dragged out along the diagonal and a little off it.
        let bigger = frame.resized(.bottomRight, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 500, y: 290))
        #expect(close(bigger.size.width / bigger.size.height, 2))
        #expect(bigger.size.width > 300)
        #expect(close(CGPoint(x: 100, y: 100).applying(bigger.transform), CGPoint(x: 100, y: 100)))
        #expect(close(CGPoint(x: 300, y: 200).applying(bigger.transform), bigger.corners[2]))
    }

    @Test func aSideStretchesOneWayOnly() {
        let frame = SelectionFrame(around: rect)
        let taller = frame.resized(.bottom, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 260, y: 250))
        #expect(close(taller.size.width, 200))
        #expect(close(taller.size.height, 150))
        #expect(close(CGPoint(x: 100, y: 100).applying(taller.transform), CGPoint(x: 100, y: 100)))
        let narrower = frame.resized(.left, from: CGPoint(x: 100, y: 150), to: CGPoint(x: 160, y: 150))
        #expect(close(narrower.size.width, 140))
        #expect(close(narrower.corners[1], CGPoint(x: 300, y: 100)))
    }

    @Test func theBoxNeverFlips() {
        let frame = SelectionFrame(around: rect)
        let squeezed = frame.resized(.right, from: CGPoint(x: 300, y: 150), to: CGPoint(x: 0, y: 150))
        #expect(squeezed.size.width == SelectionFrame.minimumSide)
        let tiny = frame.resized(.topLeft, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 900, y: 900))
        #expect(min(tiny.size.width, tiny.size.height) >= SelectionFrame.minimumSide - 0.001)
    }

    @Test func turnsAroundTheCenter() {
        let frame = SelectionFrame(around: rect)
        // From straight above the center to the right of it: a quarter turn clockwise.
        let turned = frame.rotated(from: CGPoint(x: 200, y: 50), to: CGPoint(x: 260, y: 150))
        #expect(close(turned.angle, .pi / 2))
        #expect(close(CGPoint(x: 200, y: 150).applying(turned.transform), CGPoint(x: 200, y: 150)))
        #expect(close(CGPoint(x: 300, y: 150).applying(turned.transform), CGPoint(x: 200, y: 250)))
    }

    @Test func snapsToQuarterTurns() {
        let frame = SelectionFrame(around: rect)
        let center = CGPoint(x: 200, y: 150)
        func pointer(at degrees: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: center.x + 100 * cos(a), y: center.y + 100 * sin(a))
        }
        #expect(frame.rotated(from: pointer(at: 0), to: pointer(at: 93)).angle == .pi / 2)
        #expect(frame.rotated(from: pointer(at: 0), to: pointer(at: -4)).angle == 0)
        #expect(close(frame.rotated(from: pointer(at: 0), to: pointer(at: 30)).angle, .pi / 6))
        #expect(close(abs(frame.rotated(from: pointer(at: 0), to: pointer(at: 178)).angle), .pi))
    }

    @Test func resizingATurnedBoxFollowsItsSides() {
        var frame = SelectionFrame(around: rect)
        frame.angle = .pi / 2
        // Turned a quarter, the box's right side faces down on the page.
        let start = frame.position(of: .right, rotationGap: 0)
        #expect(close(start, CGPoint(x: 200, y: 250)))
        let longer = frame.resized(.right, from: start, to: CGPoint(x: start.x, y: start.y + 50))
        #expect(close(longer.size.width, 250))
        #expect(close(longer.size.height, 100))
    }

    @Test func findsTheGripUnderThePointer() {
        let frame = SelectionFrame(around: rect)
        #expect(frame.handle(at: CGPoint(x: 103, y: 98), radius: 20, rotationGap: 30) == .topLeft)
        #expect(frame.handle(at: CGPoint(x: 200, y: 72), radius: 20, rotationGap: 30) == .rotate)
        #expect(frame.handle(at: CGPoint(x: 200, y: 150), radius: 20, rotationGap: 30) == nil)
        #expect(frame.contains(CGPoint(x: 200, y: 150)))
        #expect(!frame.contains(CGPoint(x: 350, y: 150)))
        #expect(frame.contains(CGPoint(x: 305, y: 150), slack: 10))
    }
}
