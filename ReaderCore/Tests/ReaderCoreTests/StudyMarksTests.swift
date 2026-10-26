import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

/// Two lines of four words, each word 0.07 wide every 0.08, lines 0.02 high.
private func page() -> PageText {
    let lines = (0..<2).map { i in
        let y = 0.1 + CGFloat(i) * 0.03
        let words = (0..<4).map { j in
            RawWord(text: "w\(i)\(j)", rect: CGRect(x: 0.1 + CGFloat(j) * 0.08, y: y, width: 0.07, height: 0.02))
        }
        return RawLine(text: words.map(\.text).joined(separator: " "),
                       rect: CGRect(x: 0.1, y: y, width: 0.31, height: 0.02), words: words)
    }
    return PageText(lines: lines)
}

struct StudyMarksTests {
    @Test func highlightCoversTouchedWordsOfOneLine() {
        let stroke = [CGPoint(x: 0.2, y: 0.11), CGPoint(x: 0.3, y: 0.112)]
        let band = StudyMarks.highlightBand(for: stroke, in: page(), fallbackHeight: 0.02)!
        // From the second word (0.18) to the third (ends at 0.33).
        #expect(abs(band.minX - 0.18) < 0.0001)
        #expect(abs(band.maxX - 0.33) < 0.0001)
        #expect(abs(band.minY - 0.1) < 0.0001)
        #expect(abs(band.height - 0.02) < 0.0001)
    }

    @Test func shakyHighlightStaysOnTheMainLine() {
        // Mostly on the second line, straying once onto the first.
        let stroke = [CGPoint(x: 0.12, y: 0.14), CGPoint(x: 0.16, y: 0.141), CGPoint(x: 0.2, y: 0.118),
                      CGPoint(x: 0.24, y: 0.139), CGPoint(x: 0.3, y: 0.14)]
        let band = StudyMarks.highlightBand(for: stroke, in: page(), fallbackHeight: 0.02)!
        #expect(abs(band.minY - 0.13) < 0.0001)
        #expect(abs(band.minX - 0.1) < 0.0001)
        #expect(abs(band.maxX - 0.33) < 0.0001)
    }

    @Test func highlightAcrossTwoLinesTakesOnlyOne() {
        let stroke = [CGPoint(x: 0.35, y: 0.11), CGPoint(x: 0.3, y: 0.112), CGPoint(x: 0.12, y: 0.14)]
        let band = StudyMarks.highlightBand(for: stroke, in: page(), fallbackHeight: 0.02)!
        #expect(abs(band.minY - 0.1) < 0.0001)
        #expect(band.height < 0.021)
    }

    @Test func highlightOffTheTextIsStraightAtItsMedian() {
        let stroke = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.25, y: 0.51), CGPoint(x: 0.3, y: 0.52)]
        let band = StudyMarks.highlightBand(for: stroke, in: page(), fallbackHeight: 0.05)!
        // The page's average line height, centered on the median.
        #expect(abs(band.midY - 0.51) < 0.0001)
        #expect(abs(band.height - 0.02) < 0.0001)
        #expect(abs(band.minX - 0.2) < 0.0001 && abs(band.maxX - 0.3) < 0.0001)
    }

    @Test func highlightWithoutTextUsesTheFallbackHeight() {
        let stroke = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.3, y: 0.5)]
        let band = StudyMarks.highlightBand(for: stroke, in: nil, fallbackHeight: 0.03)!
        #expect(abs(band.height - 0.03) < 0.0001)
        #expect(StudyMarks.highlightBand(for: [CGPoint(x: 0.2, y: 0.5)], in: nil, fallbackHeight: 0.03) == nil)
    }

    @Test func secondPassJoinsTheFirst() {
        let first = StudyMarks.Segment(y: 100, minX: 100, maxX: 300, height: 20)
        let again = StudyMarks.Segment(y: 101, minX: 250, maxX: 400, height: 20)
        let merged = StudyMarks.merge(again, with: [first])
        #expect(merged.absorbed == [0])
        #expect(merged.segment.minX == 100 && merged.segment.maxX == 400)
        #expect(merged.segment.y == 101)
    }

    @Test func mergeBridgesHighlightsAndLeavesOtherLines() {
        let left = StudyMarks.Segment(y: 100, minX: 100, maxX: 200, height: 20)
        let right = StudyMarks.Segment(y: 100, minX: 300, maxX: 400, height: 20)
        let below = StudyMarks.Segment(y: 130, minX: 100, maxX: 400, height: 20)
        let far = StudyMarks.Segment(y: 100, minX: 600, maxX: 700, height: 20)
        let middle = StudyMarks.Segment(y: 100, minX: 190, maxX: 310, height: 20)
        let merged = StudyMarks.merge(middle, with: [left, below, right, far])
        #expect(merged.absorbed == [0, 2])
        #expect(merged.segment.minX == 100 && merged.segment.maxX == 400)
    }

    @Test func roundEndsThatTouchAreJoined() {
        // 15 apart: the round ends, 10 each, overlap.
        let first = StudyMarks.Segment(y: 100, minX: 100, maxX: 200, height: 20)
        let next = StudyMarks.Segment(y: 100, minX: 215, maxX: 300, height: 20)
        #expect(StudyMarks.merge(next, with: [first]).absorbed == [0])
        let apart = StudyMarks.Segment(y: 100, minX: 225, maxX: 300, height: 20)
        #expect(StudyMarks.merge(apart, with: [first]).absorbed.isEmpty)
    }

    @Test func underlineIsHorizontalUnderTheLine() {
        let stroke = [CGPoint(x: 0.12, y: 0.121), CGPoint(x: 0.2, y: 0.124), CGPoint(x: 0.3, y: 0.122)]
        let line = StudyMarks.underline(for: stroke, in: page())!
        #expect(line.start.y == line.end.y)
        #expect(line.start.x == 0.12 && line.end.x == 0.3)
        #expect(line.start.y > 0.12 && line.start.y < 0.125)
    }

    @Test func underlineWithoutTextKeepsItsHeight() {
        let stroke = [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.2, y: 0.52), CGPoint(x: 0.3, y: 0.51)]
        let line = StudyMarks.underline(for: stroke, in: nil)!
        #expect(line.start.y == 0.51)
    }
}
