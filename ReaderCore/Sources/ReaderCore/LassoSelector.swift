import CoreGraphics

/// Decides which words a hand-drawn Pencil stroke refers to.
///
/// Works in any cartesian space with y growing downwards, as long as the
/// stroke and the word rects share it (in the app: view points).
///
/// - Loop (circle, oval, open "C"): the stroke is closed by joining its ends.
///   A word is selected when its centre is inside, or when more than half of
///   it is inside the outline widened by a small tolerance.
/// - Line (underline or strike-through): words covered horizontally by the
///   stroke on the text row the stroke is closest to.
public enum LassoSelector {
    /// Returns the indices into `wordRects` of the selected words, ascending.
    public static func select(stroke rawStroke: [CGPoint], wordRects rects: [CGRect]) -> [Int] {
        let stroke = decimate(rawStroke, maxPoints: 200)
        guard stroke.count >= 2, !rects.isEmpty else { return [] }

        let lineHeight = median(rects.map(\.height))
        let bounds = CGRect(boundingPoints: stroke)
        let area = abs(Polygon.signedArea(stroke))
        let isLine = bounds.height < lineHeight * 0.7
            || area < bounds.width * bounds.height * 0.25

        let selected = isLine
            ? selectAlongLine(stroke, bounds: bounds, rects: rects, lineHeight: lineHeight)
            : selectInsideLoop(stroke, bounds: bounds, rects: rects, lineHeight: lineHeight)
        if !selected.isEmpty { return selected }

        // A tiny loop or tick drawn on top of a single word.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let slack = lineHeight * 0.15
        if let hit = rects.firstIndex(where: { $0.insetBy(dx: -slack, dy: -slack).contains(center) }) {
            return [hit]
        }
        return []
    }

    private static func selectInsideLoop(_ poly: [CGPoint], bounds: CGRect,
                                         rects: [CGRect], lineHeight: CGFloat) -> [Int] {
        let tolerance = lineHeight * 0.15
        let searchArea = bounds.insetBy(dx: -tolerance, dy: -tolerance)

        func insideOrNear(_ p: CGPoint) -> Bool {
            Polygon.contains(p, in: poly) || Polygon.distance(from: p, to: poly) <= tolerance
        }

        var selected: [Int] = []
        for (i, r) in rects.enumerated() where r.intersects(searchArea) {
            if Polygon.contains(CGPoint(x: r.midX, y: r.midY), in: poly) {
                selected.append(i)
                continue
            }
            var hits = 0, total = 0
            for fx in [0.1, 0.3, 0.5, 0.7, 0.9] as [CGFloat] {
                for fy in [0.2, 0.5, 0.8] as [CGFloat] {
                    total += 1
                    if insideOrNear(CGPoint(x: r.minX + fx * r.width, y: r.minY + fy * r.height)) { hits += 1 }
                }
            }
            if hits * 2 > total { selected.append(i) }
        }
        return selected
    }

    private static func selectAlongLine(_ stroke: [CGPoint], bounds: CGRect,
                                        rects: [CGRect], lineHeight: CGFloat) -> [Int] {
        var candidates: [(index: Int, score: CGFloat)] = []
        for (i, r) in rects.enumerated() {
            let overlap = min(r.maxX, bounds.maxX) - max(r.minX, bounds.minX)
            guard overlap >= r.width * 0.5 else { continue }
            let y = strokeY(atX: min(max(r.midX, bounds.minX), bounds.maxX), stroke)
            let score: CGFloat
            if y < r.minY {
                score = (r.minY - y) * 5        // a stroke above a word rarely means it
            } else if y > r.maxY {
                score = y - r.maxY              // underline
            } else {
                score = 0                       // strike-through
            }
            if score <= lineHeight * 0.6 { candidates.append((i, score)) }
        }
        guard let best = candidates.map(\.score).min() else { return [] }
        return candidates.filter { $0.score <= best + lineHeight * 0.25 }.map(\.index)
    }

    private static func strokeY(atX x: CGFloat, _ stroke: [CGPoint]) -> CGFloat {
        stroke.min(by: { abs($0.x - x) < abs($1.x - x) })?.y ?? 0
    }

    private static func decimate(_ pts: [CGPoint], maxPoints: Int) -> [CGPoint] {
        guard pts.count > maxPoints else { return pts }
        let step = Double(pts.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { pts[Int((Double($0) * step).rounded())] }
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
