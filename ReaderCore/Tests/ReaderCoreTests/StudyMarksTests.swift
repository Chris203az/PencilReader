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
        let rects = StudyMarks.highlightRects(for: stroke, in: page())
        #expect(rects.count == 1)
        // From the second word (0.18) to the third (ends at 0.33).
        #expect(abs(rects[0].minX - 0.18) < 0.0001)
        #expect(abs(rects[0].maxX - 0.33) < 0.0001)
        #expect(abs(rects[0].minY - 0.1) < 0.0001)
    }

    @Test func highlightAcrossTwoLines() {
        let stroke = [CGPoint(x: 0.35, y: 0.11), CGPoint(x: 0.12, y: 0.14)]
        #expect(StudyMarks.highlightRects(for: stroke, in: page()).count == 2)
    }

    @Test func highlightOffTheTextIsEmpty() {
        let stroke = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.3, y: 0.5)]
        #expect(StudyMarks.highlightRects(for: stroke, in: page()).isEmpty)
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
