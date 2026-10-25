import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

/// A page of 3 lines x 5 words, words 80x24 pt, 16 pt apart, line pitch 36 pt.
private let grid: [CGRect] = (0..<3).flatMap { line in
    (0..<5).map { col in CGRect(x: 100 + CGFloat(col) * 96, y: 100 + CGFloat(line) * 36, width: 80, height: 24) }
}
private func index(line: Int, col: Int) -> Int { line * 5 + col }

private func ellipse(around r: CGRect, padX: CGFloat = 10, padY: CGFloat = 8,
                     from a0: Double = 0, to a1: Double = 2 * .pi, steps: Int = 60) -> [CGPoint] {
    let rx = r.width / 2 + padX, ry = r.height / 2 + padY
    return (0...steps).map { i in
        let a = a0 + (a1 - a0) * Double(i) / Double(steps)
        return CGPoint(x: r.midX + rx * CGFloat(cos(a)), y: r.midY + ry * CGFloat(sin(a)))
    }
}

struct LassoSelectorTests {
    @Test func circleAroundOneWord() {
        let target = grid[index(line: 1, col: 2)]
        #expect(LassoSelector.select(stroke: ellipse(around: target), wordRects: grid) == [index(line: 1, col: 2)])
    }

    @Test func ovalAroundTwoWords() {
        let span = grid[index(line: 0, col: 1)].union(grid[index(line: 0, col: 2)])
        #expect(LassoSelector.select(stroke: ellipse(around: span), wordRects: grid)
                == [index(line: 0, col: 1), index(line: 0, col: 2)])
    }

    @Test func openCShapeStillSelects() {
        let target = grid[index(line: 2, col: 0)]
        let stroke = ellipse(around: target, from: 0.4, to: 2 * .pi - 0.4)
        #expect(LassoSelector.select(stroke: stroke, wordRects: grid) == [index(line: 2, col: 0)])
    }

    @Test func sloppyCircleClippingNeighbourEdge() {
        // Shifted right so it bites ~20% into the next word.
        let target = grid[index(line: 1, col: 1)]
        let stroke = ellipse(around: target.offsetBy(dx: 14, dy: 0), padX: 12)
        #expect(LassoSelector.select(stroke: stroke, wordRects: grid) == [index(line: 1, col: 1)])
    }

    @Test func overlappingLoopEnds() {
        let target = grid[index(line: 1, col: 3)]
        let stroke = ellipse(around: target, from: 0, to: 2.4 * .pi, steps: 80)
        #expect(LassoSelector.select(stroke: stroke, wordRects: grid) == [index(line: 1, col: 3)])
    }

    @Test func tinyLoopInsideWord() {
        let target = grid[index(line: 0, col: 4)]
        let stroke = ellipse(around: target.insetBy(dx: 30, dy: 9), padX: 0, padY: 0)
        #expect(LassoSelector.select(stroke: stroke, wordRects: grid) == [index(line: 0, col: 4)])
    }

    @Test func underlineSelectsWordsAbove() {
        let a = grid[index(line: 0, col: 1)], b = grid[index(line: 0, col: 2)]
        let stroke = stride(from: a.minX, through: b.maxX, by: 8).map { CGPoint(x: $0, y: a.maxY + 4) }
        #expect(LassoSelector.select(stroke: stroke, wordRects: grid)
                == [index(line: 0, col: 1), index(line: 0, col: 2)])
    }

    @Test func strikeThrough() {
        let a = grid[index(line: 2, col: 3)]
        let stroke = stride(from: a.minX - 4, through: a.maxX + 4, by: 6).map { CGPoint(x: $0, y: a.midY) }
        #expect(LassoSelector.select(stroke: stroke, wordRects: grid) == [index(line: 2, col: 3)])
    }

    @Test func circleInEmptyMargin() {
        let empty = CGRect(x: 700, y: 400, width: 80, height: 24)
        #expect(LassoSelector.select(stroke: ellipse(around: empty), wordRects: grid).isEmpty)
    }

    @Test func singleTapSelectsNothing() {
        #expect(LassoSelector.select(stroke: [CGPoint(x: 150, y: 110)], wordRects: grid).isEmpty)
    }
}
