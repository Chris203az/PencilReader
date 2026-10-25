import CoreGraphics
import Foundation

/// A clean shape that a hand-drawn stroke is straightened into.
public enum InkShape: Equatable, Sendable {
    case line(from: CGPoint, to: CGPoint)
    /// Closed polygon: a rectangle, a square or a triangle.
    case polygon([CGPoint])
    /// Ellipse inside the rectangle; a circle when the rectangle is square.
    case ellipse(CGRect)

    /// Points to draw the shape through, in order. Closed shapes repeat their first point at the end.
    public var outline: [CGPoint] {
        switch self {
        case let .line(from, to):
            [from, to]
        case let .polygon(corners):
            corners + [corners[0]]
        case let .ellipse(box):
            (0...72).map { step in
                let angle = CGFloat(step) / 72 * 2 * .pi
                return CGPoint(x: box.midX + cos(angle) * box.width / 2,
                               y: box.midY + sin(angle) * box.height / 2)
            }
        }
    }
}

/// Recognizes a single stroke as a line, a rectangle, a square, a triangle, an ellipse or a circle.
/// Conservative on purpose: anything that does not clearly fit stays as it was written.
public enum ShapeRecognizer {
    /// Strokes smaller than this (in points) are letters or marks, never shapes.
    public static let minimumSize: CGFloat = 40

    public static func recognize(_ points: [CGPoint]) -> InkShape? {
        guard points.count >= 6, let first = points.first, let last = points.last else { return nil }
        let box = boundingBox(of: points)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= minimumSize else { return nil }
        let length = pathLength(points)

        // A straight stroke: its ends are about as far apart as its whole length.
        let chord = distance(first, last)
        if chord > 0.9 * length {
            // Short strokes are letters such as l, 1 or -; only a long, dead-straight one is a line.
            guard chord >= 2 * minimumSize else { return nil }
            let deviation = points.map { distance(of: $0, toSegmentFrom: first, to: last) }.max() ?? 0
            return deviation <= 0.03 * chord + 1.5 ? .line(from: first, to: last) : nil
        }

        // Any other shape must come back to where it started.
        guard chord <= 0.2 * diagonal, length >= 2 * max(box.width, box.height) else { return nil }

        if isEllipse(points, in: box) {
            return .ellipse(box)
        }

        let corners = simplify(points + [last], tolerance: 0.1 * diagonal).dropLast()
        let vertices = Array(corners)
        switch vertices.count {
        case 3:
            return .polygon(vertices)
        case 4 where vertices.allSatisfy({ isNearBoxCorner($0, of: box, tolerance: 0.2 * diagonal) }):
            let side = (box.width + box.height) / 2
            let isSquare = abs(box.width - box.height) <= 0.15 * max(box.width, box.height)
            let rect = isSquare
                ? CGRect(x: box.minX, y: box.minY, width: side, height: side)
                : box
            return .polygon([
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
            ])
        default:
            return nil
        }
    }

    // MARK: Helpers

    /// True when every point sits close to the ellipse inscribed in the box.
    private static func isEllipse(_ points: [CGPoint], in box: CGRect) -> Bool {
        let rx = box.width / 2, ry = box.height / 2
        guard rx > 4, ry > 4 else { return false }
        // Each point's distance from the ellipse, as a share of its radius: 0 is exact.
        let error = points.reduce(CGFloat(0)) { sum, point in
            let x = (point.x - box.midX) / rx, y = (point.y - box.midY) / ry
            return sum + abs(hypot(x, y) - 1)
        } / CGFloat(points.count)
        return error <= 0.07
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func distance(of point: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return distance(point, a) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / squared, 0), 1)
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private static func isNearBoxCorner(_ point: CGPoint, of box: CGRect, tolerance: CGFloat) -> Bool {
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        return corners.contains { distance(point, $0) <= tolerance }
    }

    /// Douglas–Peucker: keeps the points that bend the path by more than `tolerance`.
    private static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest = 0
        var farthestDistance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let d = distance(of: points[index], toSegmentFrom: first, to: last)
            if d > farthestDistance {
                farthest = index
                farthestDistance = d
            }
        }
        guard farthestDistance > tolerance else { return [first, last] }
        let left = simplify(Array(points[...farthest]), tolerance: tolerance)
        let right = simplify(Array(points[farthest...]), tolerance: tolerance)
        return left.dropLast() + right
    }
}
