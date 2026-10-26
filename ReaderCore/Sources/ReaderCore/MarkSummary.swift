import CoreGraphics
import Foundation

/// The study marks of a page gathered into zones, for the book's summary. A zone is the marks
/// of one kind that sit close together: the lines of one highlighted passage, the words of one
/// underline, the strokes of one margin note. All coordinates are normalized to the page,
/// [0,1] with the origin top-left, like the OCR's.
public enum MarkSummary {
    /// One mark: its kind (the app's own name for a color or tool) and the box around it.
    public struct Mark: Sendable, Hashable {
        public var kind: String
        public var rect: CGRect

        public init(kind: String, rect: CGRect) {
            self.kind = kind
            self.rect = rect
        }
    }

    public struct Zone: Sendable, Hashable {
        public let kind: String
        /// The boxes of its marks.
        public let rects: [CGRect]
        /// Around all of them, with a margin, inside the page.
        public let rect: CGRect
    }

    /// Joins the marks of each kind that are less than `gap` apart, in reading order:
    /// top to bottom, then left to right.
    public static func zones(of marks: [Mark], gap: CGFloat = 0.02, margin: CGFloat = 0.015) -> [Zone] {
        var zones: [Zone] = []
        for (kind, group) in Dictionary(grouping: marks, by: \.kind) {
            var clusters = group.map { [$0.rect] }
            // Merges until no two clusters touch: a mark can join two clusters together.
            var merged = true
            while merged {
                merged = false
                outer: for i in clusters.indices {
                    for j in clusters.indices where j > i {
                        if touch(clusters[i], clusters[j], gap: gap) {
                            clusters[i] += clusters[j]
                            clusters.remove(at: j)
                            merged = true
                            break outer
                        }
                    }
                }
            }
            for rects in clusters {
                let box = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
                let padded = box.insetBy(dx: -margin, dy: -margin)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                zones.append(Zone(kind: kind, rects: rects, rect: padded))
            }
        }
        return zones.sorted { a, b in
            if abs(a.rect.minY - b.rect.minY) > 0.005 { return a.rect.minY < b.rect.minY }
            return a.rect.minX < b.rect.minX
        }
    }

    private static func touch(_ a: [CGRect], _ b: [CGRect], gap: CGFloat) -> Bool {
        a.contains { ra in
            let grown = ra.insetBy(dx: -gap, dy: -gap)
            return b.contains { grown.intersects($0) }
        }
    }

    /// The recognized words a zone covers: those whose center lies in one of its marks.
    /// `above` widens each mark upward by that much, for underlines, which sit below their words.
    public static func text(of zone: Zone, in page: PageText, above: CGFloat = 0) -> String {
        let areas = zone.rects.map { rect in
            CGRect(x: rect.minX, y: rect.minY - above, width: rect.width, height: rect.height + above)
                .insetBy(dx: -0.003, dy: -0.003)
        }
        let ids = page.words.filter { word in
            let center = CGPoint(x: word.rect.midX, y: word.rect.midY)
            return areas.contains { $0.contains(center) }
        }.map(\.id)
        return ids.isEmpty ? "" : page.text(for: ids)
    }
}
