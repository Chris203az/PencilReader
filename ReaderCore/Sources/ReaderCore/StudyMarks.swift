import CoreGraphics
import Foundation

/// Geometry of the study marks: highlighter strokes snapped to one text
/// line each, and underlines straightened. All coordinates are normalized to
/// the page, [0,1] with the origin top-left, like the OCR's.
public enum StudyMarks {
    /// The one band of text a highlighter stroke is meant for: never more than one line, even
    /// when a shaking hand strays onto the lines above or below.
    /// With the page's text, the line most of the stroke went over, from the first word touched
    /// to the last; without it, or off the text, a band of `fallbackHeight` (or the page's average
    /// line height) centered on the median height of the stroke. Nil for a stroke with no width off the text.
    public static func highlightBand(for stroke: [CGPoint], in page: PageText?, fallbackHeight: CGFloat) -> CGRect? {
        guard let minX = stroke.map(\.x).min(), let maxX = stroke.map(\.x).max() else { return nil }
        let ys = stroke.map(\.y).sorted()
        let medianY = ys[ys.count / 2]
        if let page, let line = mainLine(of: stroke, medianY: medianY, minX: minX, maxX: maxX, in: page) {
            let touched = page.words[line.wordIDs].filter { $0.rect.maxX >= minX && $0.rect.minX <= maxX }
            let left = touched.first?.rect.minX ?? minX
            let right = touched.last?.rect.maxX ?? maxX
            return CGRect(x: left, y: line.rect.minY, width: right - left, height: line.rect.height)
        }
        guard maxX > minX else { return nil }
        var height = fallbackHeight
        if let page, !page.lines.isEmpty {
            height = page.lines.map(\.rect.height).reduce(0, +) / CGFloat(page.lines.count)
        }
        return CGRect(x: minX, y: medianY - height / 2, width: maxX - minX, height: height)
    }

    /// The line holding most points of the stroke; on a tie, the one closest to its median height.
    static func mainLine(of stroke: [CGPoint], medianY: CGFloat, minX: CGFloat, maxX: CGFloat,
                         in page: PageText) -> Line? {
        var best: (line: Line, count: Int, distance: CGFloat)?
        for line in page.lines where line.rect.maxX >= minX && line.rect.minX <= maxX {
            // A quarter of a line of slack above and below, as the stroke rarely sits right in the middle.
            let band = line.rect.insetBy(dx: 0, dy: -line.rect.height * 0.25)
            let count = stroke.filter { $0.y >= band.minY && $0.y <= band.maxY }.count
            guard count > 0 else { continue }
            let distance = abs(line.rect.midY - medianY)
            if best == nil || count > best!.count || (count == best!.count && distance < best!.distance) {
                best = (line, count, distance)
            }
        }
        return best?.line
    }

    /// A straight highlight: the centers of its round ends, and its thickness.
    /// Unlike the rest, in any unit that is the same along both axes, such as the canvas'.
    public struct Segment: Equatable, Sendable {
        public var y: CGFloat
        public var minX: CGFloat
        public var maxX: CGFloat
        public var height: CGFloat

        public init(y: CGFloat, minX: CGFloat, maxX: CGFloat, height: CGFloat) {
            self.y = y
            self.minX = minX
            self.maxX = maxX
            self.height = height
        }
    }

    /// A new highlight joined with the highlights of the same color it overlaps on its line,
    /// so that passing again over the same words never makes them darker.
    /// Returns the joined segment, at the new one's height, and the indices of `others` it took in.
    public static func merge(_ segment: Segment, with others: [Segment]) -> (segment: Segment, absorbed: [Int]) {
        var merged = segment
        var absorbed = Set<Int>()
        var changed = true
        while changed {
            changed = false
            for (i, other) in others.enumerated() where !absorbed.contains(i) {
                let sameLine = abs(other.y - merged.y) < min(other.height, merged.height) / 2
                // The round ends reach half the thickness past the segment's ends.
                let reach = (other.height + merged.height) / 2
                let touches = other.minX - merged.maxX < reach && merged.minX - other.maxX < reach
                guard sameLine, touches else { continue }
                merged.minX = min(merged.minX, other.minX)
                merged.maxX = max(merged.maxX, other.maxX)
                absorbed.insert(i)
                changed = true
            }
        }
        return (merged, absorbed.sorted())
    }

    /// A stroke turned into a horizontal segment, from its leftmost to its rightmost point.
    /// With the page's text, it sits just under the line it was drawn below.
    public static func underline(for stroke: [CGPoint], in page: PageText?) -> (start: CGPoint, end: CGPoint)? {
        guard let minX = stroke.map(\.x).min(), let maxX = stroke.map(\.x).max(), maxX > minX else { return nil }
        let ys = stroke.map(\.y).sorted()
        var y = ys[ys.count / 2]
        if let line = page?.lines.first(where: { line in
            let r = line.rect
            return r.maxX >= minX && r.minX <= maxX && y >= r.midY && y <= r.maxY + r.height * 0.6
        }) {
            y = line.rect.maxY + line.rect.height * 0.08
        }
        return (CGPoint(x: minX, y: y), CGPoint(x: maxX, y: y))
    }
}
