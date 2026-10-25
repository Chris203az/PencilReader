import Foundation

/// One occurrence of a search query on a page.
public struct SearchMatch: Sendable, Hashable {
    /// Words covered by the occurrence, to highlight them on the page.
    public let wordIDs: [Int]
    /// The surrounding text, shortened with "…".
    public let snippet: String
    /// The occurrence inside `snippet`.
    public let highlight: Range<String.Index>
}

extension PageText {
    /// Case- and accent-insensitive search in the running text of each block,
    /// so words hyphenated across lines and phrases spanning lines are found.
    public func search(_ query: String, snippetRadius: Int = 60) -> [SearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var matches: [SearchMatch] = []
        for block in blocks {
            let text = block.text
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchRange) {
                let ids = block.wordRanges
                    .filter { $0.value.overlaps(found) }
                    .map(\.key)
                    .sorted()
                matches.append(Self.snippet(of: found, in: text, radius: snippetRadius, wordIDs: ids))
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return matches
    }

    private static func snippet(of found: Range<String.Index>, in text: String, radius: Int,
                                wordIDs: [Int]) -> SearchMatch {
        var lower = text.index(found.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        var upper = text.index(found.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        // Don't cut words in half.
        if lower > text.startIndex, let space = text[lower..<found.lowerBound].firstIndex(of: " ") {
            lower = text.index(after: space)
        }
        if upper < text.endIndex, let space = text[found.upperBound..<upper].lastIndex(of: " ") {
            upper = space
        }
        let prefix = lower > text.startIndex ? "…" : ""
        let suffix = upper < text.endIndex ? "…" : ""
        let snippet = prefix + text[lower..<upper] + suffix
        let start = prefix.count + text.distance(from: lower, to: found.lowerBound)
        let length = text.distance(from: found.lowerBound, to: found.upperBound)
        let hlLower = snippet.index(snippet.startIndex, offsetBy: start)
        let hlUpper = snippet.index(hlLower, offsetBy: length)
        return SearchMatch(wordIDs: wordIDs, snippet: snippet, highlight: hlLower..<hlUpper)
    }
}
