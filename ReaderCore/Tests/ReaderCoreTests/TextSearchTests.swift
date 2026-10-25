import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

/// Builds lines with evenly spaced word boxes (normalized coordinates).
private func makeLines(_ texts: [String], lineHeight: CGFloat = 0.02, gap: CGFloat = 0.008) -> [RawLine] {
    texts.enumerated().map { i, text in
        let y = 0.1 + CGFloat(i) * (lineHeight + gap)
        let tokens = text.split(separator: " ").map(String.init)
        let words = tokens.enumerated().map { j, t in
            RawWord(text: t, rect: CGRect(x: 0.1 + CGFloat(j) * 0.08, y: y, width: 0.07, height: lineHeight))
        }
        return RawLine(text: text, rect: CGRect(x: 0.1, y: y, width: 0.8, height: lineHeight), words: words)
    }
}

struct TextSearchTests {
    @Test func findsEveryOccurrenceIgnoringCase() {
        let page = PageText(lines: makeLines(["Liquid hydrogen and liquid", "oxygen. LIQUID fuels."]))
        let matches = page.search("liquid")
        #expect(matches.count == 3)
        #expect(matches.map(\.wordIDs) == [[0], [3], [5]])
        for match in matches {
            #expect(match.snippet[match.highlight].lowercased() == "liquid")
        }
    }

    @Test func findsWordHyphenatedAcrossLines() {
        let page = PageText(lines: makeLines(["The aero-", "dynamic force"]))
        let matches = page.search("aerodynamic")
        #expect(matches.count == 1)
        #expect(matches[0].wordIDs == [1, 2])
    }

    @Test func findsPhraseSpanningLines() {
        let page = PageText(lines: makeLines(["exceeded the angle", "of attack limit"]))
        let matches = page.search("angle of attack")
        #expect(matches.map(\.wordIDs) == [[2, 3, 4]])
        #expect(matches[0].snippet[matches[0].highlight] == "angle of attack")
    }

    @Test func ignoresAccents() {
        let page = PageText(lines: makeLines(["Die Rakete zu den Planetenräumen"]))
        #expect(page.search("planetenraumen").count == 1)
    }

    @Test func shortensLongSnippetsAtWordBoundaries() {
        let words = (1...40).map { "word\($0)" }
        let page = PageText(lines: makeLines([words.joined(separator: " ")]))
        let match = page.search("word20", snippetRadius: 20)[0]
        #expect(match.snippet.hasPrefix("…word"))
        #expect(match.snippet.hasSuffix("…"))
        #expect(!match.snippet.contains("  "))
        #expect(match.snippet[match.highlight] == "word20")
    }

    @Test func emptyQueryFindsNothing() {
        let page = PageText(lines: makeLines(["Some text"]))
        #expect(page.search("  ").isEmpty)
    }
}
