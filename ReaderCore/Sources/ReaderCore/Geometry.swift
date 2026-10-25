import CoreGraphics

public extension CGRect {
    /// Smallest rect containing all `points` (`.null` when empty).
    init(boundingPoints points: [CGPoint]) {
        guard let first = points.first else {
            self = .null
            return
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Maps a rect normalized to [0,1] (top-left origin) into `frame`.
    func denormalized(in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + minX * frame.width,
               y: frame.minY + minY * frame.height,
               width: width * frame.width,
               height: height * frame.height)
    }

    /// Inverse of `denormalized(in:)`.
    func normalized(in frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGRect(x: (minX - frame.minX) / frame.width,
                      y: (minY - frame.minY) / frame.height,
                      width: width / frame.width,
                      height: height / frame.height)
    }
}

enum Polygon {
    /// Signed area (shoelace) of the polygon closed between last and first point.
    static func signedArea(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Non-zero winding rule, so a lasso that goes around more than once
    /// (overlapping ends) still counts its overlap as inside.
    static func contains(_ p: CGPoint, in pts: [CGPoint]) -> Bool {
        guard pts.count >= 3 else { return false }
        var winding = 0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            if a.y <= p.y {
                if b.y > p.y, cross(a, b, p) > 0 { winding += 1 }
            } else if b.y <= p.y, cross(a, b, p) < 0 {
                winding -= 1
            }
        }
        return winding != 0
    }

    /// Distance from `p` to the closed outline.
    static func distance(from p: CGPoint, to pts: [CGPoint]) -> CGFloat {
        guard let first = pts.first else { return .infinity }
        if pts.count == 1 { return hypot(p.x - first.x, p.y - first.y) }
        var best = CGFloat.infinity
        for i in pts.indices {
            best = min(best, segmentDistance(p, pts[i], pts[(i + 1) % pts.count]))
        }
        return best
    }

    static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t: CGFloat = 0
        if len2 > 0 { t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) }
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat {
        (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
    }
}
