import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

private func shaky(_ points: [CGPoint], by amount: CGFloat = 0.8) -> [CGPoint] {
    points.enumerated().map { i, p in CGPoint(x: p.x, y: p.y + (i.isMultiple(of: 2) ? amount : -amount)) }
}

private func line(from a: CGPoint, to b: CGPoint, count: Int = 30) -> [CGPoint] {
    (0...count).map { i in
        let t = CGFloat(i) / CGFloat(count)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct StrokeSmootherTests {
    @Test func shakeIsReduced() {
        let points = shaky(line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 0)))
        guard let smooth = StrokeSmoother.smoothed(points) else {
            Issue.record("a shaky stroke was left alone")
            return
        }
        let before = points.dropFirst().dropLast().map { abs($0.y) }.reduce(0, +)
        let after = smooth.dropFirst().dropLast().map { abs($0.y) }.reduce(0, +)
        #expect(after < before / 2)
    }

    @Test func noPointMovesMoreThanOnePoint() {
        let points = shaky(line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 20)), by: 3)
        let smooth = StrokeSmoother.smoothed(points) ?? points
        #expect(smooth.count == points.count)
        for (a, b) in zip(points, smooth) {
            #expect(hypot(a.x - b.x, a.y - b.y) <= StrokeSmoother.maxShift + 0.0001)
        }
    }

    @Test func shortStrokesMoveAtMostOnePoint() {
        let points = shaky(line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 12, y: 4), count: 14), by: 2)
        guard StrokeSmoother.pathLength(points) < StrokeSmoother.shortLength else { return }
        let smooth = StrokeSmoother.smoothed(points) ?? points
        for (a, b) in zip(points, smooth) {
            #expect(hypot(a.x - b.x, a.y - b.y) <= StrokeSmoother.shortMaxShift + 0.0001)
        }
    }

    @Test func strengthLimitsTheShift() {
        let points = shaky(line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 80, y: 30), count: 40), by: 5)
        for strength in [1, 2, 3, 4] as [CGFloat] {
            let smooth = StrokeSmoother.smoothed(points, strength: strength) ?? points
            for (a, b) in zip(points, smooth) {
                #expect(hypot(a.x - b.x, a.y - b.y) <= strength + 0.0001)
            }
        }
    }

    @Test func endsStayPut() {
        let points = shaky(line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 0)))
        let smooth = StrokeSmoother.smoothed(points)!
        #expect(smooth.first == points.first)
        #expect(smooth.last == points.last)
    }

    @Test func cornersStaySharp() {
        // An arrow head: a sharp V.
        let points = line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 20), count: 15)
            + line(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 40, y: 0), count: 15).dropFirst()
        let corner = 15
        let input = shaky(points, by: 0.5)
        let smooth = StrokeSmoother.smoothed(input) ?? input
        #expect(smooth[corner] == input[corner])
    }

    @Test func dotsAndShortStrokesAreLeftAlone() {
        let dot = (0..<6).map { CGPoint(x: CGFloat($0) * 0.3, y: 0) }
        #expect(StrokeSmoother.smoothed(dot) == nil)
        let short = shaky(line(from: .zero, to: CGPoint(x: 6, y: 0), count: 12), by: 0.1)
        #expect(StrokeSmoother.smoothed(short) == nil)
    }

    @Test func smoothStrokeIsLeftAlone() {
        #expect(StrokeSmoother.smoothed(line(from: .zero, to: CGPoint(x: 60, y: 0))) == nil)
    }
}
