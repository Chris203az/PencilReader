import CoreGraphics
import Foundation

/// Reshaping a shape already on the page, as in GoodNotes: its own grips change its geometry,
/// while the line keeps its width (unlike the lasso, which scales everything it holds).
public extension InkShape {
    /// The grips shown when the shape is tapped, in this order:
    /// a line's two ends; a rectangle's four corners then the middles of its four sides;
    /// any other polygon's corners; an ellipse's four ends of its axes (+width, -width, +height, -height);
    /// an arc's start, middle and end; a curve's control points.
    var grips: [CGPoint] {
        switch self {
        case .line(let a, let b):
            return [a, b]
        case .polygon(let corners):
            guard isRectangle else { return corners }
            return corners + corners.indices.map { i in midpoint(corners[i], corners[(i + 1) % 4]) }
        case .ellipse(let center, let radii, let angle):
            let e1 = CGPoint(x: cos(angle), y: sin(angle)), e2 = CGPoint(x: -sin(angle), y: cos(angle))
            return [
                CGPoint(x: center.x + e1.x * radii.width, y: center.y + e1.y * radii.width),
                CGPoint(x: center.x - e1.x * radii.width, y: center.y - e1.y * radii.width),
                CGPoint(x: center.x + e2.x * radii.height, y: center.y + e2.y * radii.height),
                CGPoint(x: center.x - e2.x * radii.height, y: center.y - e2.y * radii.height)
            ]
        case .arc(let start, let through, let end):
            return [start, through, end]
        case .curve(let controls):
            return controls
        }
    }

    /// Four corners at right angles: its grips are corners and sides, and it stays a rectangle.
    var isRectangle: Bool {
        guard case .polygon(let corners) = self, corners.count == 4 else { return false }
        return corners.indices.allSatisfy { i in
            let a = corners[(i + 3) % 4], b = corners[i], c = corners[(i + 1) % 4]
            let u = CGPoint(x: a.x - b.x, y: a.y - b.y), v = CGPoint(x: c.x - b.x, y: c.y - b.y)
            let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
            return lengths > 0 && abs(u.x * v.x + u.y * v.y) / lengths < sin(0.5 * .pi / 180)
        }
    }

    var isCircle: Bool {
        guard case .ellipse(_, let radii, _) = self else { return false }
        return abs(radii.width - radii.height) <= 0.001 * max(radii.width, radii.height)
    }

    /// The shape with grip number `grip` (see `grips`) taken to `point`.
    func reshaped(grip: Int, to point: CGPoint) -> InkShape {
        let all = grips
        guard all.indices.contains(grip) else { return self }
        switch self {
        case .line(let a, let b):
            return grip == 0 ? .line(point, b) : .line(a, point)
        case .polygon(var corners):
            guard isRectangle else {
                corners[grip] = point
                return .polygon(corners)
            }
            return grip < 4 ? .polygon(Self.rectangle(corners, corner: grip, to: point))
                            : .polygon(Self.rectangle(corners, side: grip - 4, to: point))
        case .ellipse(let center, let radii, let angle):
            let minimum: CGFloat = 3
            if isCircle {
                let r = max(hypot(point.x - center.x, point.y - center.y), minimum)
                return .ellipse(center: center, radii: CGSize(width: r, height: r), angle: 0)
            }
            let axis = grip < 2 ? CGPoint(x: cos(angle), y: sin(angle)) : CGPoint(x: -sin(angle), y: cos(angle))
            let reach = max(abs((point.x - center.x) * axis.x + (point.y - center.y) * axis.y), minimum)
            let newRadii = grip < 2 ? CGSize(width: reach, height: radii.height) : CGSize(width: radii.width, height: reach)
            return .ellipse(center: center, radii: newRadii, angle: angle)
        case .arc(let start, let through, let end):
            switch grip {
            case 0: return Self.arcKeepingItsMiddle(point, through, end)
            case 2: return Self.arcKeepingItsMiddle(start, through, point)
            default: return .arc(start: start, through: point, end: end)
            }
        case .curve(var controls):
            controls[grip] = point
            return .curve(controls)
        }
    }

    /// The whole shape moved by `offset`.
    func moved(by offset: CGPoint) -> InkShape {
        applying(CGAffineTransform(translationX: offset.x, y: offset.y))
    }

    /// The shape as an affine transform draws it, such as the one the lasso leaves on a stroke.
    /// An ellipse stays an ellipse, along its new axes; an arc goes through its three points moved.
    func applying(_ t: CGAffineTransform) -> InkShape {
        switch self {
        case .line(let a, let b): return .line(a.applying(t), b.applying(t))
        case .polygon(let corners): return .polygon(corners.map { $0.applying(t) })
        case .arc(let start, let through, let end):
            return .arc(start: start.applying(t), through: through.applying(t), end: end.applying(t))
        case .curve(let controls): return .curve(controls.map { $0.applying(t) })
        case .ellipse(let center, let radii, let angle):
            // The columns of M take the unit circle to the new ellipse: its axes are M's singular vectors.
            let c = cos(angle), s = sin(angle)
            let m11 = t.a * c * radii.width + t.c * s * radii.width
            let m21 = t.b * c * radii.width + t.d * s * radii.width
            let m12 = -t.a * s * radii.height + t.c * c * radii.height
            let m22 = -t.b * s * radii.height + t.d * c * radii.height
            let p = m11 * m11 + m12 * m12, q = m11 * m21 + m12 * m22, r = m21 * m21 + m22 * m22
            let half = ((p - r) * (p - r) / 4 + q * q).squareRoot()
            let major = ((p + r) / 2 + half).squareRoot(), minor = max((p + r) / 2 - half, 0).squareRoot()
            let newCenter = center.applying(t)
            guard abs(major - minor) > 0.001 * major else {
                return .ellipse(center: newCenter, radii: CGSize(width: major, height: major), angle: 0)
            }
            return .ellipse(center: newCenter, radii: CGSize(width: major, height: minor), angle: 0.5 * atan2(2 * q, p - r))
        }
    }

    /// How far `point` is from the line of the shape.
    func outlineDistance(to point: CGPoint) -> CGFloat {
        let line = outline(spacing: 4)
        guard line.count > 1 else { return line.first.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity }
        return zip(line, line.dropFirst()).map { Polygon.segmentDistance(point, $0.0, $0.1) }.min() ?? .infinity
    }

    // MARK: Rectangles

    /// The rectangle with one corner dragged: the opposite corner stays, the sides keep their directions.
    private static func rectangle(_ corners: [CGPoint], corner: Int, to point: CGPoint) -> [CGPoint] {
        let anchor = corners[(corner + 2) % 4]
        let u = unit(from: corners[0], to: corners[1]), v = unit(from: corners[0], to: corners[3])
        func local(_ p: CGPoint) -> CGPoint {
            let d = CGPoint(x: p.x - anchor.x, y: p.y - anchor.y)
            return CGPoint(x: d.x * u.x + d.y * u.y, y: d.x * v.x + d.y * v.y)
        }
        var target = local(point)
        // Never flat: at least a few points each way.
        let old = local(corners[corner])
        if abs(target.x) < 4 { target.x = old.x < 0 ? -4 : 4 }
        if abs(target.y) < 4 { target.y = old.y < 0 ? -4 : 4 }
        return corners.map { c in
            let l = local(c)
            let x = abs(l.x) > 0.001 ? target.x : 0, y = abs(l.y) > 0.001 ? target.y : 0
            return CGPoint(x: anchor.x + u.x * x + v.x * y, y: anchor.y + u.y * x + v.y * y)
        }
    }

    /// The rectangle with one side pushed or pulled: the opposite side stays.
    private static func rectangle(_ corners: [CGPoint], side: Int, to point: CGPoint) -> [CGPoint] {
        let a = corners[side], b = corners[(side + 1) % 4]
        let opposite = corners[(side + 2) % 4]
        let along = unit(from: a, to: b)
        var normal = CGPoint(x: -along.y, y: along.x)
        // Pointing away from the opposite side.
        if (a.x - opposite.x) * normal.x + (a.y - opposite.y) * normal.y < 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let middle = midpoint(a, b)
        let depth = (a.x - opposite.x) * normal.x + (a.y - opposite.y) * normal.y
        var push = (point.x - middle.x) * normal.x + (point.y - middle.y) * normal.y
        push = max(push, 4 - depth)
        var result = corners
        for i in [side, (side + 1) % 4] {
            result[i] = CGPoint(x: corners[i].x + normal.x * push, y: corners[i].y + normal.y * push)
        }
        return result
    }

    /// An arc with a new end, still bulging through `through`, which then moves back to its middle.
    private static func arcKeepingItsMiddle(_ start: CGPoint, _ through: CGPoint, _ end: CGPoint) -> InkShape {
        guard let circle = arcCircle(start, through, end) else { return .arc(start: start, through: through, end: end) }
        let t = circle.startAngle + circle.sweep / 2
        let middle = CGPoint(x: circle.center.x + circle.radius * cos(t), y: circle.center.y + circle.radius * sin(t))
        return .arc(start: start, through: middle, end: end)
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let length = max(hypot(b.x - a.x, b.y - a.y), 0.000_1)
        return CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
    }
}

private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}
