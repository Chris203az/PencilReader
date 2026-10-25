import CoreGraphics
import Foundation

/// Geometry of the study marks: highlighter strokes snapped to the recognized
/// text lines, and underlines straightened. All coordinates are normalized to
/// the page, [0,1] with the origin top-left, like the OCR's.
public enum StudyMarks {
    /// The parts of the text lines a highlighter stroke went over, one rect per line:
    /// on each line, from the first word the stroke touched to the last.
    /// Empty when the stroke missed the text, so it stays freehand.
    public static func highlightRects(for stroke: [CGPoint], in page: PageText) -> [CGRect] {
        guard !stroke.isEmpty else { return [] }
        var rects: [CGRect] = []
        for line in page.lines {
            // Half a line of slack above and below, as the stroke rarely sits right in the middle.
            let band = line.rect.insetBy(dx: 0, dy: -line.rect.height * 0.25)
            let xs = stroke.filter { $0.y >= band.minY && $0.y <= band.maxY }.map(\.x)
            guard let minX = xs.min(), let maxX = xs.max() else { continue }
            let touched = page.words[line.wordIDs].filter { $0.rect.maxX >= minX && $0.rect.minX <= maxX }
            guard let first = touched.first, let last = touched.last else { continue }
            rects.append(CGRect(x: first.rect.minX, y: line.rect.minY,
                                width: last.rect.maxX - first.rect.minX, height: line.rect.height))
        }
        return rects
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
