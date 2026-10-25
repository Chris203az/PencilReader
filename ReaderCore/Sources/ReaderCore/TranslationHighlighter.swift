import Foundation

/// The sentence around a selection, and where the selection sits in it.
public struct SentenceContext: Sendable, Hashable {
    public let text: String
    public let selection: Range<String.Index>?

    /// Midpoint of the selection as a fraction of the sentence length.
    public var selectionPosition: Double? {
        guard let selection, !text.isEmpty else { return nil }
        let lower = text.distance(from: text.startIndex, to: selection.lowerBound)
        let upper = text.distance(from: text.startIndex, to: selection.upperBound)
        return Double(lower + upper) / 2 / Double(text.count)
    }
}

/// Finds which part of a translated sentence corresponds to the circled words.
/// Apple's Translation framework gives no word alignment, so two strategies:
/// quote the selection before translating and look for the quotes, or search
/// the separately translated term inside the translated sentence.
public enum TranslationHighlighter {
    public struct Marked: Sendable, Hashable {
        public let text: String
        public let open: Character
        public let close: Character
    }

    /// The sentence with the selection wrapped in a quote pair the sentence doesn't already use.
    public static func marked(_ context: SentenceContext) -> Marked? {
        guard let selection = context.selection else { return nil }
        let pairs: [(Character, Character)] = [("“", "”"), ("«", "»"), ("[", "]")]
        guard let (open, close) = pairs.first(where: { !context.text.contains($0.0) && !context.text.contains($0.1) })
        else { return nil }
        let text = context.text[..<selection.lowerBound] + String(open)
            + context.text[selection] + String(close) + context.text[selection.upperBound...]
        return Marked(text: String(text), open: open, close: close)
    }

    /// Removes the quote pair added by `marked(_:)` from a translation and returns
    /// what was inside. Nil when the pair didn't survive intact.
    public static func unmark(_ translation: String, open: Character, close: Character)
        -> (text: String, highlight: Range<String.Index>)? {
        guard translation.filter({ $0 == open }).count == 1,
              translation.filter({ $0 == close }).count == 1,
              let o = translation.firstIndex(of: open),
              let c = translation.firstIndex(of: close), o < c else { return nil }
        let before = String(translation[..<o])
        let inside = String(translation[translation.index(after: o)..<c])
        let after = String(translation[translation.index(after: c)...])
        let core = inside.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return nil }
        let text = before + core + after
        let start = text.index(text.startIndex, offsetBy: before.count)
        return (text, start..<text.index(start, offsetBy: core.count))
    }

    /// Best match of `term` inside `sentence`, tolerant to Italian inflection
    /// ("stallo"/"stalli") and to articles/prepositions around it.
    public static func fuzzyRange(of term: String, in sentence: String,
                                  expectedPosition: Double? = nil) -> Range<String.Index>? {
        let termTokens = tokens(term).map(\.normalized)
        let content = termTokens.filter { !stopwords.contains($0) }
        let wanted = content.isEmpty ? termTokens : content
        let words = tokens(sentence)
        guard !wanted.isEmpty, !words.isEmpty else { return nil }

        var best: (score: Double, distance: Double, range: Range<String.Index>)?
        let maxWindow = wanted.count + 2
        for start in words.indices {
            for length in 1...maxWindow where start + length <= words.count {
                let window = words[start..<(start + length)]
                // Every wanted token takes its best match in the window.
                var total = 0.0
                var matched: [Int] = []
                for w in wanted {
                    let scored = window.indices.map { ($0, similarity(w, window[$0].normalized)) }
                    if let top = scored.max(by: { $0.1 < $1.1 }), top.1 > 0 {
                        total += top.1
                        matched.append(top.0)
                    }
                }
                let score = total / Double(wanted.count)
                guard score >= 0.6, let first = matched.min(), let last = matched.max(),
                      first == start, last == start + length - 1 else { continue }
                let position = Double(start) / Double(words.count)
                let distance = expectedPosition.map { abs($0 - position) } ?? 0
                let range = words[first].range.lowerBound..<words[last].range.upperBound
                if best == nil || score > best!.score + 0.01
                    || (abs(score - best!.score) <= 0.01 && distance < best!.distance) {
                    best = (score, distance, range)
                }
            }
        }
        return best?.range
    }

    // MARK: Helpers

    private struct Token {
        let range: Range<String.Index>
        let normalized: String
    }

    /// Letter/digit runs; apostrophes split elisions ("dell'angolo" -> "dell", "angolo").
    private static func tokens(_ s: String) -> [Token] {
        var result: [Token] = []
        var start: String.Index?
        func flush(_ end: String.Index) {
            if let st = start {
                result.append(Token(range: st..<end,
                                    normalized: s[st..<end].lowercased().folding(options: .diacriticInsensitive, locale: nil)))
                start = nil
            }
        }
        for i in s.indices {
            if s[i].isLetter || s[i].isNumber {
                if start == nil { start = i }
            } else {
                flush(i)
            }
        }
        flush(s.endIndex)
        return result
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let minLength = min(a.count, b.count)
        guard minLength >= 4 else { return 0 }
        let prefix = zip(a, b).prefix { $0 == $1 }.count
        return prefix >= max(4, minLength - 2) ? 0.85 : 0
    }

    private static let stopwords: Set<String> = [
        "il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "di", "del", "dello", "della",
        "dei", "degli", "delle", "dell", "d", "a", "al", "allo", "alla", "ai", "agli", "alle", "all",
        "da", "dal", "dallo", "dalla", "dai", "dagli", "dalle", "dall", "in", "nel", "nello", "nella",
        "nei", "negli", "nelle", "nell", "con", "su", "sul", "sullo", "sulla", "sui", "sugli", "sulle",
        "sull", "per", "tra", "fra", "e", "ed", "o", "che"
    ]
}
