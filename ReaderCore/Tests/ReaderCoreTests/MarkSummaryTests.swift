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

struct MarkSummaryTests {
    @Test func linesOfOnePassageMakeOneZone() {
        let marks = [MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.1, width: 0.31, height: 0.02)),
                     MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.13, width: 0.15, height: 0.02))]
        let zones = MarkSummary.zones(of: marks)
        #expect(zones.count == 1)
        #expect(zones[0].rects.count == 2)
        #expect(zones[0].rect.minY < 0.1)
    }

    @Test func farMarksAndOtherColorsStayApart() {
        let marks = [MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.02)),
                     MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.02)),
                     MarkSummary.Mark(kind: "review", rect: CGRect(x: 0.1, y: 0.13, width: 0.3, height: 0.02))]
        let zones = MarkSummary.zones(of: marks)
        #expect(zones.count == 3)
        // Reading order: top first.
        #expect(zones.map(\.kind) == ["key", "review", "key"])
    }

    @Test func aMarkBetweenTwoJoinsThem() {
        let marks = [MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.02)),
                     MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.16, width: 0.1, height: 0.02)),
                     MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.1, y: 0.13, width: 0.1, height: 0.02))]
        #expect(MarkSummary.zones(of: marks).count == 1)
    }

    @Test func zoneStaysInsideThePage() {
        let marks = [MarkSummary.Mark(kind: "key", rect: CGRect(x: 0, y: 0, width: 0.2, height: 0.02))]
        let rect = MarkSummary.zones(of: marks)[0].rect
        #expect(rect.minX >= 0 && rect.minY >= 0)
    }

    @Test func textOfAHighlight() {
        let zone = MarkSummary.zones(of: [MarkSummary.Mark(kind: "key", rect: CGRect(x: 0.18, y: 0.1, width: 0.15, height: 0.02))])[0]
        #expect(MarkSummary.text(of: zone, in: page()) == "w01 w02")
    }

    @Test func textAboveAnUnderline() {
        let zone = MarkSummary.zones(of: [MarkSummary.Mark(kind: "term", rect: CGRect(x: 0.1, y: 0.122, width: 0.07, height: 0.002))])[0]
        #expect(MarkSummary.text(of: zone, in: page()).isEmpty)
        #expect(MarkSummary.text(of: zone, in: page(), above: 0.02) == "w00")
    }
}
