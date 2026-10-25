import CoreGraphics
import Foundation
import NaturalLanguage

/// A word as produced by OCR. `rect` is normalized to [0,1], top-left origin.
public struct RawWord: Sendable, Hashable, Codable {
    public var text: String
    public var rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

/// A text line as produced by OCR, in reading order.
public struct RawLine: Sendable, Hashable, Codable {
    public var text: String
    public var rect: CGRect
    public var words: [RawWord]

    public init(text: String, rect: CGRect, words: [RawWord]) {
        self.text = text
        self.rect = rect
        self.words = words
    }
}

public struct Word: Sendable, Hashable, Identifiable {
    public let id: Int
    public let text: String
    public let rect: CGRect
    public let lineIndex: Int
}

public struct Line: Sendable, Hashable {
    public let rect: CGRect
    public let wordIDs: Range<Int>
    public let blockIndex: Int
}

/// Consecutive lines of the same paragraph or column, joined into running text.
public struct Block: Sendable, Hashable {
    public let text: String
    /// Range inside `text` of every word of the block, keyed by word id.
    public let wordRanges: [Int: Range<String.Index>]
}

/// Everything recognized on one page, indexed for fast lookups on every lasso.
public struct PageText: Sendable {
    /// The OCR output this was built from; persist this and rebuild with `init(lines:)`.
    public let rawLines: [RawLine]
    public let words: [Word]
    public let lines: [Line]
    public let blocks: [Block]

    public init(lines rawLines: [RawLine]) {
        let raw = rawLines.filter { !$0.words.isEmpty }
        let blockOfLine = Self.groupIntoBlocks(raw.map(\.rect))

        var words: [Word] = []
        var lines: [Line] = []
        for (li, rawLine) in raw.enumerated() {
            let start = words.count
            for w in rawLine.words {
                words.append(Word(id: words.count, text: w.text, rect: w.rect, lineIndex: li))
            }
            lines.append(Line(rect: rawLine.rect, wordIDs: start..<words.count, blockIndex: blockOfLine[li]))
        }

        var blocks: [Block] = []
        var li = 0
        while li < lines.count {
            var end = li
            while end < lines.count, lines[end].blockIndex == lines[li].blockIndex { end += 1 }
            blocks.append(Self.makeBlock(lines[li..<end], words: words))
            li = end
        }

        self.rawLines = raw
        self.words = words
        self.lines = lines
        self.blocks = blocks
    }

    // MARK: Queries

    /// The selected words as one string: re-joins words hyphenated across a
    /// line break and trims surrounding punctuation ("stall," -> "stall").
    public func text(for ids: [Int]) -> String {
        let sorted = Array(Set(ids)).sorted()
        var out = ""
        for (k, id) in sorted.enumerated() {
            let next = k + 1 < sorted.count ? sorted[k + 1] : nil
            if let next, next == id + 1, joinsWithNextLine(id) {
                out += words[id].text.dropLast()
            } else {
                out += words[id].text
                if next != nil { out += " " }
            }
        }
        return out.trimmingCharacters(in: Self.trimmed)
    }

    /// The full sentence(s) containing the selection, and where the selection
    /// sits in them (located only in the first block when it spans several).
    public func contextSentences(for ids: [Int]) -> SentenceContext? {
        var parts: [String] = []
        var selectionOffsets: (Int, Int)?
        let byBlock = Dictionary(grouping: Set(ids), by: { lines[words[$0].lineIndex].blockIndex })
        for blockIndex in byBlock.keys.sorted() {
            let block = blocks[blockIndex]
            let ranges = byBlock[blockIndex]!.compactMap { block.wordRanges[$0] }
            guard let lower = ranges.map(\.lowerBound).min(),
                  let upper = ranges.map(\.upperBound).max() else { continue }

            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = block.text
            var start: String.Index?
            var end: String.Index?
            tokenizer.enumerateTokens(in: block.text.startIndex..<block.text.endIndex) { range, _ in
                if range.upperBound > lower, range.lowerBound < upper {
                    start = start ?? range.lowerBound
                    end = range.upperBound
                }
                return range.lowerBound < upper
            }
            guard var start, var end else { continue }
            let text = block.text
            while start < end, text[start].isWhitespace { start = text.index(after: start) }
            while end > start, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }

            if parts.isEmpty {
                // Same punctuation trimming as `text(for:)`.
                var lo = max(lower, start), hi = min(upper, end)
                while lo < hi, text[lo].unicodeScalars.allSatisfy(Self.trimmed.contains) { lo = text.index(after: lo) }
                while hi > lo, text[text.index(before: hi)].unicodeScalars.allSatisfy(Self.trimmed.contains) {
                    hi = text.index(before: hi)
                }
                if lo < hi {
                    selectionOffsets = (text.distance(from: start, to: lo), text.distance(from: start, to: hi))
                }
            }
            parts.append(String(text[start..<end]))
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: " … ")
        let selection = selectionOffsets.map {
            joined.index(joined.startIndex, offsetBy: $0.0)..<joined.index(joined.startIndex, offsetBy: $0.1)
        }
        return SentenceContext(text: joined, selection: selection)
    }

    // MARK: Building

    private static let hyphens: Set<Character> = ["-", "\u{00AD}", "\u{2010}"]
    private static let trimmed = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ".,;:!?\"“”‘’()[]{}«»"))

    /// True when word `id` ends its line with a hyphen and continues on the next one.
    private func joinsWithNextLine(_ id: Int) -> Bool {
        let word = words[id]
        guard id + 1 < words.count,
              lines[word.lineIndex].wordIDs.last == id,
              word.text.count > 1, let last = word.text.last, Self.hyphens.contains(last)
        else { return false }
        let next = words[id + 1]
        return next.lineIndex == word.lineIndex + 1
            && lines[next.lineIndex].blockIndex == lines[word.lineIndex].blockIndex
            && next.text.first?.isLowercase == true
    }

    private static func makeBlock(_ blockLines: ArraySlice<Line>, words: [Word]) -> Block {
        // Track UTF-16 offsets while appending; String indices are only valid
        // for the final string.
        var text = ""
        var offsets: [Int: (Int, Int)] = [:]
        let ids = blockLines.flatMap { Array($0.wordIDs) }
        for (k, id) in ids.enumerated() {
            let word = words[id]
            let isLineEnd = blockLines.contains { $0.wordIDs.last == id }
            let nextWord = k + 1 < ids.count ? words[ids[k + 1]] : nil
            let hyphenated = isLineEnd && word.text.count > 1
                && word.text.last.map(hyphens.contains) == true
                && nextWord?.text.first?.isLowercase == true

            let piece = hyphenated ? String(word.text.dropLast()) : word.text
            let start = text.utf16.count
            text += piece
            offsets[id] = (start, text.utf16.count)
            if !hyphenated, nextWord != nil { text += " " }
        }
        var ranges: [Int: Range<String.Index>] = [:]
        for (id, (s, e)) in offsets {
            ranges[id] = String.Index(utf16Offset: s, in: text)..<String.Index(utf16Offset: e, in: text)
        }
        return Block(text: text, wordRanges: ranges)
    }

    /// Assigns a block number to each line (in reading order). A new block
    /// starts on a large vertical gap, when going back up, or on a column change.
    static func groupIntoBlocks(_ rects: [CGRect]) -> [Int] {
        guard !rects.isEmpty else { return [] }
        let heights = rects.map(\.height).sorted()
        let lineHeight = heights[heights.count / 2]
        var result = [0]
        var block = 0
        for i in 1..<rects.count {
            let prev = rects[i - 1], cur = rects[i]
            let gap = cur.minY - prev.maxY
            let overlap = min(prev.maxX, cur.maxX) - max(prev.minX, cur.minX)
            let narrower = min(prev.width, cur.width)
            let sameColumn = narrower > 0 && overlap / narrower > 0.3
            if gap > lineHeight * 0.9 || gap < -lineHeight * 0.5 || !sameColumn {
                block += 1
            }
            result.append(block)
        }
        return result
    }
}
