import CoreGraphics
import Foundation

/// A clean shape that a hand-drawn stroke is turned into.
public enum InkShape: Equatable, Sendable, Codable {
    case line(CGPoint, CGPoint)
    /// Corners in drawing order; the outline closes back to the first one.
    case polygon([CGPoint])
    /// `angle` turns the `radii.width` axis away from horizontal. A circle has equal radii.
    case ellipse(center: CGPoint, radii: CGSize, angle: CGFloat)
    /// The piece of circle from `start` to `end` that goes through `through`.
    case arc(start: CGPoint, through: CGPoint, end: CGPoint)
    /// A smooth open curve through its control points (Catmull-Rom).
    case curve([CGPoint])

    /// Points along the outline, at most `spacing` apart, every corner included;
    /// closed shapes end where they start. Dense enough that PencilKit keeps the corners sharp.
    public func outline(spacing: CGFloat = 2) -> [CGPoint] {
        switch self {
        case .line(let a, let b):
            return Self.segment(a, b, spacing: spacing) + [b]
        case .polygon(let corners):
            var points: [CGPoint] = []
            for (i, corner) in corners.enumerated() {
                points += Self.segment(corner, corners[(i + 1) % corners.count], spacing: spacing)
            }
            return points + [corners[0]]
        case .ellipse(let center, let radii, let angle):
            let perimeter = 2 * CGFloat.pi * ((radii.width * radii.width + radii.height * radii.height) / 2).squareRoot()
            let count = max(36, Int((perimeter / spacing).rounded(.up)))
            return (0...count).map { i in
                let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
                let x = radii.width * cos(t), y = radii.height * sin(t)
                return CGPoint(x: center.x + x * cos(angle) - y * sin(angle),
                               y: center.y + x * sin(angle) + y * cos(angle))
            }
        case .arc(let start, let through, let end):
            guard let circle = Self.arcCircle(start, through, end) else {
                return Self.segment(start, end, spacing: spacing) + [end]
            }
            let count = max(8, Int((abs(circle.sweep) * circle.radius / spacing).rounded(.up)))
            return (0...count).map { i in
                let t = circle.startAngle + circle.sweep * CGFloat(i) / CGFloat(count)
                return CGPoint(x: circle.center.x + circle.radius * cos(t), y: circle.center.y + circle.radius * sin(t))
            }
        case .curve(let controls):
            return Self.catmullRom(controls, spacing: spacing)
        }
    }

    /// The circle through the three points of an arc, where the arc starts on it and how far it turns
    /// (negative counterclockwise on screen); nil when the points are nearly in a line.
    static func arcCircle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint)
        -> (center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let size = max(distance(a, b) + distance(b, c), 0.001)
        guard abs(d) > 0.000_1 * size * size else { return nil }
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y
        let center = CGPoint(x: (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                             y: (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        let radius = distance(center, a)
        // A circle much bigger than the arc is a line drawn slightly bent.
        guard radius < 50 * size else { return nil }
        let start = atan2(a.y - center.y, a.x - center.x)
        func turn(to p: CGPoint) -> CGFloat {
            var t = atan2(p.y - center.y, p.x - center.x) - start
            while t < 0 { t += 2 * .pi }
            return t
        }
        let toEnd = turn(to: c), toMiddle = turn(to: b)
        // The way round from the start that passes the middle point before the end.
        let sweep = toMiddle <= toEnd ? toEnd : toEnd - 2 * .pi
        return (center, radius, start, sweep)
    }

    /// Points along the Catmull-Rom curve through `controls`, ends included.
    static func catmullRom(_ controls: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard controls.count > 2 else {
            guard controls.count == 2 else { return controls }
            return segment(controls[0], controls[1], spacing: spacing) + [controls[1]]
        }
        var points: [CGPoint] = []
        let padded = [controls[0]] + controls + [controls[controls.count - 1]]
        for i in 1..<(padded.count - 2) {
            let p0 = padded[i - 1], p1 = padded[i], p2 = padded[i + 1], p3 = padded[i + 2]
            let steps = max(2, Int((distance(p1, p2) * 1.2 / spacing).rounded(.up)))
            for j in 0..<steps {
                let t = CGFloat(j) / CGFloat(steps), t2 = t * t, t3 = t2 * t
                func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                points.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        return points + [controls[controls.count - 1]]
    }

    /// The point of the shape that stays put while the Pencil drags it: the farthest from the tip.
    /// The far end of a line, the opposite corner of a rectangle, the opposite side of a circle.
    public func anchor(oppositeTo tip: CGPoint) -> CGPoint {
        let candidates: [CGPoint]
        switch self {
        case .line(let a, let b): candidates = [a, b]
        case .polygon(let corners): candidates = corners
        case .ellipse: candidates = outline(spacing: 8)
        case .arc(let start, _, let end): candidates = [start, end]
        case .curve(let controls): candidates = [controls[0], controls[controls.count - 1]]
        }
        return candidates.max { distance($0, tip) < distance($1, tip) } ?? tip
    }

    /// The shape scaled and turned around `anchor`, so that the point under `from` follows the Pencil to `to`.
    public func dragged(anchor: CGPoint, from: CGPoint, to: CGPoint) -> InkShape {
        let before = CGPoint(x: from.x - anchor.x, y: from.y - anchor.y)
        let after = CGPoint(x: to.x - anchor.x, y: to.y - anchor.y)
        let length = hypot(before.x, before.y)
        guard length > 1, hypot(after.x, after.y) > 1 else { return self }
        let scale = hypot(after.x, after.y) / length
        let turn = atan2(after.y, after.x) - atan2(before.y, before.x)
        func move(_ p: CGPoint) -> CGPoint {
            let x = (p.x - anchor.x) * scale, y = (p.y - anchor.y) * scale
            return CGPoint(x: anchor.x + x * cos(turn) - y * sin(turn), y: anchor.y + x * sin(turn) + y * cos(turn))
        }
        switch self {
        case .line(let a, let b):
            let (start, end) = ShapeRecognizer.straightened(move(a), move(b))
            return .line(start, end)
        case .polygon(let corners):
            return .polygon(corners.map(move))
        case .ellipse(let center, let radii, let angle):
            let isCircle = radii.width == radii.height
            return .ellipse(center: move(center),
                            radii: CGSize(width: radii.width * scale, height: radii.height * scale),
                            angle: isCircle ? 0 : angle + turn)
        case .arc(let start, let through, let end):
            return .arc(start: move(start), through: move(through), end: move(end))
        case .curve(let controls):
            return .curve(controls.map(move))
        }
    }

    /// From `a` up to, not including, `b`.
    private static func segment(_ a: CGPoint, _ b: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let steps = max(1, Int((distance(a, b) / spacing).rounded(.up)))
        return (0..<steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }
}

/// Recognizes the stroke drawn so far as a line, a triangle, a rectangle or square, another polygon
/// up to eight corners, or an ellipse or circle. Anything that does not clearly fit gives nil.
/// Runs once, when the Pencil is held still, on the stroke resampled to a fixed number of points.
public enum ShapeRecognizer {
    /// Smaller strokes are handwriting, never shapes.
    public static let minimumSize: CGFloat = 30
    static let sampleCount = 64

    public static func recognize(_ stroke: [CGPoint]) -> InkShape? {
        guard stroke.count >= 2 else { return nil }
        let points = resampled(stroke, count: sampleCount)
        let box = CGRect(boundingPoints: points)
        let size = hypot(box.width, box.height)
        guard size >= minimumSize else { return nil }
        let length = pathLength(points)
        let first = points[0], last = points[points.count - 1]
        let chord = distance(first, last)

        if chord > 0.85 * length {
            let deviation = points.map { Polygon.segmentDistance($0, first, last) }.max() ?? 0
            if deviation <= 0.06 * chord {
                let (a, b) = straightened(first, last)
                return .line(a, b)
            }
        }
        // An open stroke is a piece of circle, a smooth curve, or nothing.
        if chord > 0.2 * length {
            return arc(points, size: size) ?? smoothCurve(points, size: size)
        }

        var polygonFit = CGFloat.infinity
        var corners = dropFlatCorners(closingEnd(simplify(points, epsilon: 0.07 * size), size: size))
        if (3...8).contains(corners.count) {
            let distances = points.map { Polygon.distance(from: $0, to: corners) }
            if (distances.max() ?? .infinity) <= 0.08 * size {
                polygonFit = distances.reduce(0, +) / CGFloat(distances.count)
            }
        }
        let ellipse = fittedEllipse(points)

        // Both may fit a rounded square or a polygon with many sides: the closer one wins.
        if polygonFit < .infinity, polygonFit <= ellipse?.fit ?? .infinity {
            corners = refinedCorners(corners, along: points, size: size)
            if corners.count == 4, let rectangle = rectangle(corners) { corners = rectangle }
            return .polygon(corners)
        }
        return ellipse?.shape
    }

    // MARK: Shapes

    /// An open stroke that keeps close to one circle and turns between 30° and 330° around it.
    static func arc(_ points: [CGPoint], size: CGFloat) -> InkShape? {
        guard let circle = fittedCircle(points), circle.radius < 10 * size else { return nil }
        let residuals = points.map { abs(distance($0, circle.center) - circle.radius) }
        let mean = residuals.reduce(0, +) / CGFloat(residuals.count)
        guard mean <= 0.035 * circle.radius, (residuals.max() ?? 0) <= 0.1 * circle.radius else { return nil }
        var turned: CGFloat = 0, travelled: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            var step = atan2(b.y - circle.center.y, b.x - circle.center.x) - atan2(a.y - circle.center.y, a.x - circle.center.x)
            if step > .pi { step -= 2 * .pi }
            if step < -.pi { step += 2 * .pi }
            turned += step
            travelled += abs(step)
        }
        // Always the same way round: a stroke that goes back and forth is not an arc.
        guard travelled <= 1.1 * abs(turned), (30...330).contains(abs(turned) * 180 / .pi) else { return nil }
        func onCircle(_ p: CGPoint) -> CGPoint {
            let d = max(distance(p, circle.center), 0.000_1)
            return CGPoint(x: circle.center.x + (p.x - circle.center.x) * circle.radius / d,
                           y: circle.center.y + (p.y - circle.center.y) * circle.radius / d)
        }
        return .arc(start: onCircle(points[0]), through: onCircle(points[points.count / 2]), end: onCircle(points[points.count - 1]))
    }

    /// An open stroke without corners: a smooth curve through four to eight points along it.
    static func smoothCurve(_ points: [CGPoint], size: CGFloat) -> InkShape? {
        // A sharp turn anywhere, as in a 2, a 7 or a zigzag, is a corner: not a curve.
        let k = 3
        for i in k..<(points.count - k) {
            let u = CGPoint(x: points[i].x - points[i - k].x, y: points[i].y - points[i - k].y)
            let v = CGPoint(x: points[i + k].x - points[i].x, y: points[i + k].y - points[i].y)
            let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
            guard lengths > 0 else { continue }
            let turn = acos(max(-1, min(1, (u.x * v.x + u.y * v.y) / lengths)))
            if turn > 65 * .pi / 180 { return nil }
        }
        let count = min(8, max(4, simplify(points, epsilon: 0.03 * size).count))
        let controls = (0..<count).map { j in points[Int((CGFloat(j) * CGFloat(points.count - 1) / CGFloat(count - 1)).rounded())] }
        let curve = InkShape.catmullRom(controls, spacing: 2)
        let deviation = points.map { p in
            zip(curve, curve.dropFirst()).map { Polygon.segmentDistance(p, $0.0, $0.1) }.min() ?? .infinity
        }.max() ?? .infinity
        guard deviation <= 0.06 * size else { return nil }
        return .curve(controls)
    }

    /// Least-squares circle through the points (Kåsa), around their center for precision.
    static func fittedCircle(_ points: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
        let n = CGFloat(points.count)
        let mx = points.map(\.x).reduce(0, +) / n, my = points.map(\.y).reduce(0, +) / n
        var suu: CGFloat = 0, svv: CGFloat = 0, suv: CGFloat = 0, suuu: CGFloat = 0, svvv: CGFloat = 0, suvv: CGFloat = 0, svuu: CGFloat = 0
        for p in points {
            let u = p.x - mx, v = p.y - my
            suu += u * u; svv += v * v; suv += u * v
            suuu += u * u * u; svvv += v * v * v; suvv += u * v * v; svuu += v * u * u
        }
        let det = suu * svv - suv * suv
        guard abs(det) > 0.000_001 else { return nil }
        let b1 = (suuu + suvv) / 2, b2 = (svvv + svuu) / 2
        let uc = (b1 * svv - b2 * suv) / det, vc = (suu * b2 - suv * b1) / det
        let radius = (uc * uc + vc * vc + (suu + svv) / n).squareRoot()
        return (CGPoint(x: mx + uc, y: my + vc), radius)
    }

    /// Four corners at nearly right angles make a true rectangle, a square when the sides nearly match.
    static func rectangle(_ corners: [CGPoint]) -> [CGPoint]? {
        for i in 0..<4 {
            let corner = angle(at: corners[i], from: corners[(i + 3) % 4], to: corners[(i + 1) % 4])
            guard abs(corner - .pi / 2) <= 15 * .pi / 180 else { return nil }
        }
        let center = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        var width = (distance(corners[0], corners[1]) + distance(corners[2], corners[3])) / 2
        var height = (distance(corners[1], corners[2]) + distance(corners[3], corners[0])) / 2
        if abs(width - height) <= 0.12 * max(width, height) {
            width = (width + height) / 2
            height = width
        }
        let direction = snapped(atan2(corners[1].y - corners[0].y, corners[1].x - corners[0].x))
        let u = CGPoint(x: cos(direction), y: sin(direction))
        // Perpendicular towards the third corner, so the corners keep the order they were drawn in.
        let side = CGPoint(x: corners[2].x - corners[1].x, y: corners[2].y - corners[1].y)
        let turn: CGFloat = -u.y * side.x + u.x * side.y >= 0 ? 1 : -1
        let v = CGPoint(x: -u.y * turn, y: u.x * turn)
        let w = width / 2, h = height / 2
        let signs: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        return signs.map { sign in
            let (s, t) = sign
            return CGPoint(x: center.x + u.x * w * s + v.x * h * t, y: center.y + u.y * w * s + v.y * h * t)
        }
    }

    /// Ellipse along the stroke's principal axes. `fit` is the mean distance of the stroke from it, in points.
    static func fittedEllipse(_ points: [CGPoint]) -> (shape: InkShape, fit: CGFloat)? {
        let n = CGFloat(points.count)
        let cx = points.map(\.x).reduce(0, +) / n, cy = points.map(\.y).reduce(0, +) / n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points {
            sxx += (p.x - cx) * (p.x - cx)
            syy += (p.y - cy) * (p.y - cy)
            sxy += (p.x - cx) * (p.y - cy)
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let c = cos(angle), s = sin(angle)
        let us = points.map { ($0.x - cx) * c + ($0.y - cy) * s }
        let vs = points.map { -($0.x - cx) * s + ($0.y - cy) * c }
        guard let minU = us.min(), let maxU = us.max(), let minV = vs.min(), let maxV = vs.max() else { return nil }
        var a = (maxU - minU) / 2, b = (maxV - minV) / 2
        guard a > 2, b > 2 else { return nil }
        let mu = (maxU + minU) / 2, mv = (maxV + minV) / 2
        var shareError: CGFloat = 0, fit: CGFloat = 0
        for (u, v) in zip(us, vs) {
            let x = u - mu, y = v - mv
            let r = max(hypot(x / a, y / b), 0.000_1)
            shareError += abs(r - 1)
            fit += abs(r - 1) * hypot(x, y) / r
        }
        // A square drawn perfectly scores about 0.15, a hand-drawn circle well under 0.1.
        guard shareError / n <= 0.1 else { return nil }
        let center = CGPoint(x: cx + mu * c - mv * s, y: cy + mu * s + mv * c)
        var shapeAngle = snapped(angle)
        if abs(a - b) <= 0.15 * max(a, b) {
            a = (a + b) / 2
            b = a
            shapeAngle = 0
        }
        return (.ellipse(center: center, radii: CGSize(width: a, height: b), angle: shapeAngle), fit / n)
    }

    /// A line close to horizontal, vertical or diagonal becomes exactly so, around its middle.
    static func straightened(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGPoint) {
        let direction = atan2(b.y - a.y, b.x - a.x)
        let snappedDirection = snapped(direction)
        guard snappedDirection != direction else { return (a, b) }
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let half = distance(a, b) / 2
        let d = CGPoint(x: cos(snappedDirection) * half, y: sin(snappedDirection) * half)
        return (CGPoint(x: mid.x - d.x, y: mid.y - d.y), CGPoint(x: mid.x + d.x, y: mid.y + d.y))
    }

    /// Directions within 5° of a multiple of 45° become that multiple.
    static func snapped(_ direction: CGFloat) -> CGFloat {
        let eighth = CGFloat.pi / 4
        let nearest = (direction / eighth).rounded() * eighth
        return abs(direction - nearest) <= 5 * .pi / 180 ? nearest : direction
    }

    // MARK: Points

    /// `count` points evenly spaced along the stroke, so long and short strokes cost the same.
    static func resampled(_ points: [CGPoint], count: Int) -> [CGPoint] {
        let length = pathLength(points)
        guard length > 0, count > 1 else { return points }
        let step = length / CGFloat(count - 1)
        var result = [points[0]]
        var previous = points[0]
        var carried: CGFloat = 0
        var i = 1
        while i < points.count, result.count < count {
            let d = distance(previous, points[i])
            if d > 0, carried + d >= step {
                let t = (step - carried) / d
                previous = CGPoint(x: previous.x + t * (points[i].x - previous.x), y: previous.y + t * (points[i].y - previous.y))
                result.append(previous)
                carried = 0
            } else {
                carried += d
                previous = points[i]
                i += 1
            }
        }
        while result.count < count { result.append(points[points.count - 1]) }
        return result
    }

    /// Douglas-Peucker: keeps the points that stick out more than `epsilon` from the chord.
    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        let first = points[0], last = points[points.count - 1]
        var farthest = 0
        var maxDistance: CGFloat = 0
        for i in 1..<(points.count - 1) {
            let d = Polygon.segmentDistance(points[i], first, last)
            if d > maxDistance {
                maxDistance = d
                farthest = i
            }
        }
        guard maxDistance > epsilon else { return [first, last] }
        let left = simplify(Array(points[...farthest]), epsilon: epsilon)
        let right = simplify(Array(points[farthest...]), epsilon: epsilon)
        return left.dropLast() + right
    }

    /// Where the straight sides meet. The sampled points kept as corners sit up to half a sample
    /// short of the real corner, so each side gets a line fitted to its middle part, and the
    /// corners become the crossings of those lines.
    static func refinedCorners(_ corners: [CGPoint], along points: [CGPoint], size: CGFloat) -> [CGPoint] {
        var ring = points
        if let first = ring.first, let last = ring.last, distance(first, last) < 0.001 { ring.removeLast() }
        let n = ring.count
        guard n >= corners.count * 3 else { return corners }
        let indices = corners.map { corner in
            ring.indices.min { distance(ring[$0], corner) < distance(ring[$1], corner) } ?? 0
        }
        var lines: [(point: CGPoint, direction: CGPoint)] = []
        for k in corners.indices {
            let a = indices[k], b = indices[(k + 1) % corners.count]
            let span = (b - a + n) % n
            let side = (0...span).map { ring[(a + $0) % n] }
            // The ends of a side bend into the corners: only its middle is straight.
            let cut = side.count * 15 / 100
            let middle = side.count - 2 * cut >= 2 ? Array(side[cut..<(side.count - cut)]) : side
            guard middle.count >= 2 else { return corners }
            lines.append(fittedLine(middle))
        }
        return corners.indices.map { k in
            let previous = lines[(k + corners.count - 1) % corners.count]
            guard let meet = intersection(previous, lines[k]), distance(meet, corners[k]) <= 0.15 * size else {
                return corners[k]
            }
            return meet
        }
    }

    /// The line through the points' center, along their main direction.
    private static func fittedLine(_ points: [CGPoint]) -> (point: CGPoint, direction: CGPoint) {
        let n = CGFloat(points.count)
        let cx = points.map(\.x).reduce(0, +) / n, cy = points.map(\.y).reduce(0, +) / n
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in points {
            sxx += (p.x - cx) * (p.x - cx)
            syy += (p.y - cy) * (p.y - cy)
            sxy += (p.x - cx) * (p.y - cy)
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        return (CGPoint(x: cx, y: cy), CGPoint(x: cos(angle), y: sin(angle)))
    }

    private static func intersection(_ first: (point: CGPoint, direction: CGPoint),
                                     _ second: (point: CGPoint, direction: CGPoint)) -> CGPoint? {
        let d = first.direction, e = second.direction
        let denominator = d.x * e.y - d.y * e.x
        guard abs(denominator) > 0.000_001 else { return nil }
        let t = ((second.point.x - first.point.x) * e.y - (second.point.y - first.point.y) * e.x) / denominator
        return CGPoint(x: first.point.x + t * d.x, y: first.point.y + t * d.y)
    }

    /// A closed stroke ends near its start: that end is the same corner.
    private static func closingEnd(_ corners: [CGPoint], size: CGFloat) -> [CGPoint] {
        guard corners.count > 1, distance(corners[0], corners[corners.count - 1]) <= 0.2 * size else { return corners }
        return Array(corners.dropLast())
    }

    /// Removes corners where the outline goes almost straight on, such as where the stroke started mid-side.
    static func dropFlatCorners(_ corners: [CGPoint]) -> [CGPoint] {
        var result = corners
        var i = 0
        while result.count > 3, i < result.count {
            let a = result[(i + result.count - 1) % result.count], b = result[i], c = result[(i + 1) % result.count]
            if angle(at: b, from: a, to: c) >= 150 * .pi / 180 {
                result.remove(at: i)
                i = 0
            } else {
                i += 1
            }
        }
        return result
    }

    /// Interior angle at `b`, from 0 to pi (pi = straight on).
    private static func angle(at b: CGPoint, from a: CGPoint, to c: CGPoint) -> CGFloat {
        let u = CGPoint(x: a.x - b.x, y: a.y - b.y), v = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
        guard lengths > 0 else { return .pi }
        return acos(max(-1, min(1, (u.x * v.x + u.y * v.y) / lengths)))
    }

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
