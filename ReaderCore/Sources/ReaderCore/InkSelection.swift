import CoreGraphics
import Foundation

/// Which strokes a lasso drawn on the notebook takes.
public enum StrokeLasso {
    /// Indices of the strokes with at least `share` of their points inside the closed lasso.
    /// Each stroke is given as its points on the page, after its own transform.
    public static func selected(strokes: [[CGPoint]], lasso: [CGPoint], share: Double = 0.5) -> [Int] {
        guard lasso.count >= 3 else { return [] }
        let bounds = CGRect(boundingPoints: lasso)
        return strokes.indices.filter { index in
            let points = strokes[index]
            guard !points.isEmpty else { return false }
            let inside = points.filter { bounds.contains($0) && Polygon.contains($0, in: lasso) }.count
            return Double(inside) >= share * Double(points.count)
        }
    }
}

/// A grip of the selection box: the corners resize keeping the proportions, the sides
/// stretch one way only, `rotate` sits above the top side and turns the selection.
public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotate

    /// Where the grip sits on the box, from -1 to 1 on each axis of the box itself.
    var direction: (x: CGFloat, y: CGFloat) {
        switch self {
        case .topLeft: (-1, -1)
        case .top, .rotate: (0, -1)
        case .topRight: (1, -1)
        case .right: (1, 0)
        case .bottomRight: (1, 1)
        case .bottom: (0, 1)
        case .bottomLeft: (-1, 1)
        case .left: (-1, 0)
        }
    }

    public var isCorner: Bool { direction.x != 0 && direction.y != 0 }
}

/// The box around the selected strokes, as it is moved, resized and turned.
///
/// `original` is the box of the strokes when they were selected; `center`, `size` and `angle`
/// are where it is now. `transform` takes the strokes from where they were to where the box is,
/// so the strokes keep their shape inside the box whatever is done to it.
public struct SelectionFrame: Equatable, Sendable {
    public let original: CGRect
    public var center: CGPoint
    public var size: CGSize
    /// Radians, clockwise on screen (y grows downward).
    public var angle: CGFloat

    /// Smaller than this the box cannot be squeezed, so it never flips or vanishes.
    public static let minimumSide: CGFloat = 8
    /// The turn snaps to a quarter turn when it comes this close to one.
    public static let rotationSnap: CGFloat = 5 * .pi / 180

    public init(around rect: CGRect) {
        let rect = rect.standardized
        original = rect
        center = CGPoint(x: rect.midX, y: rect.midY)
        size = CGSize(width: max(rect.width, 1), height: max(rect.height, 1))
        angle = 0
    }

    public var transform: CGAffineTransform {
        let from = CGSize(width: max(original.width, 1), height: max(original.height, 1))
        return CGAffineTransform(translationX: -original.midX, y: -original.midY)
            .concatenating(CGAffineTransform(scaleX: size.width / from.width, y: size.height / from.height))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// The corners, clockwise from the top left.
    public var corners: [CGPoint] {
        let signs: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        return signs.map { point(local: CGPoint(x: $0.0 * size.width / 2, y: $0.1 * size.height / 2)) }
    }

    /// Where a grip is drawn. The rotation grip is `rotationGap` above the top side.
    public func position(of handle: SelectionHandle, rotationGap: CGFloat) -> CGPoint {
        let d = handle.direction
        var local = CGPoint(x: d.x * size.width / 2, y: d.y * size.height / 2)
        if handle == .rotate { local.y -= rotationGap }
        return point(local: local)
    }

    /// The grip within `radius` of `point`, the closest one; nil when none is.
    public func handle(at point: CGPoint, radius: CGFloat, rotationGap: CGFloat) -> SelectionHandle? {
        let near = SelectionHandle.allCases
            .map { ($0, distance(position(of: $0, rotationGap: rotationGap), point)) }
            .filter { $0.1 <= radius }
        return near.min { $0.1 < $1.1 }?.0
    }

    /// Whether `point` is in the box, or within `slack` of it.
    public func contains(_ point: CGPoint, slack: CGFloat = 0) -> Bool {
        let p = local(point)
        return abs(p.x) <= size.width / 2 + slack && abs(p.y) <= size.height / 2 + slack
    }

    /// The box moved by the Pencil or the finger from `start` to `now`.
    public func moved(from start: CGPoint, to now: CGPoint) -> SelectionFrame {
        var frame = self
        frame.center = CGPoint(x: center.x + now.x - start.x, y: center.y + now.y - start.y)
        return frame
    }

    /// The box with `handle` dragged from `start` to `now`; the opposite corner or side stays put.
    /// Corners keep the proportions, sides change one dimension only.
    public func resized(_ handle: SelectionHandle, from start: CGPoint, to now: CGPoint) -> SelectionFrame {
        guard handle != .rotate else { return self }
        let d = handle.direction
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        let anchor = CGPoint(x: -d.x * half.width, y: -d.y * half.height)
        let grip = CGPoint(x: d.x * half.width, y: d.y * half.height)
        // The grip follows the pointer even when the pointer did not start exactly on it.
        let moved = local(now)
        let started = local(start)
        let target = CGPoint(x: grip.x + moved.x - started.x, y: grip.y + moved.y - started.y)

        var width = size.width, height = size.height
        if handle.isCorner {
            let vector = CGPoint(x: grip.x - anchor.x, y: grip.y - anchor.y)
            let length2 = vector.x * vector.x + vector.y * vector.y
            var scale = ((target.x - anchor.x) * vector.x + (target.y - anchor.y) * vector.y) / length2
            scale = max(scale, Self.minimumSide / min(size.width, size.height))
            width *= scale
            height *= scale
        } else if d.x != 0 {
            width = max((target.x - anchor.x) * d.x, Self.minimumSide)
        } else {
            height = max((target.y - anchor.y) * d.y, Self.minimumSide)
        }
        let newCenter = CGPoint(x: anchor.x + d.x * width / 2, y: anchor.y + d.y * height / 2)
        var frame = self
        frame.size = CGSize(width: width, height: height)
        frame.center = point(local: newCenter)
        return frame
    }

    /// The box turned around its center by the angle the pointer swept from `start` to `now`,
    /// snapped to 0°, 90°, 180° or 270° when within five degrees of one.
    public func rotated(from start: CGPoint, to now: CGPoint) -> SelectionFrame {
        let swept = atan2(now.y - center.y, now.x - center.x) - atan2(start.y - center.y, start.x - center.x)
        var frame = self
        frame.angle = Self.snapped(Self.normalized(angle + swept))
        return frame
    }

    /// The angle in (-π, π].
    static func normalized(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }

    static func snapped(_ angle: CGFloat) -> CGFloat {
        let quarter = CGFloat.pi / 2
        let nearest = (angle / quarter).rounded() * quarter
        return abs(angle - nearest) <= rotationSnap ? normalized(nearest) : angle
    }

    /// From the box's own coordinates (origin at its center, axes along its sides) to the page.
    private func point(local p: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x * cos(angle) - p.y * sin(angle),
                y: center.y + p.x * sin(angle) + p.y * cos(angle))
    }

    private func local(_ p: CGPoint) -> CGPoint {
        let x = p.x - center.x, y = p.y - center.y
        return CGPoint(x: x * cos(angle) + y * sin(angle), y: -x * sin(angle) + y * cos(angle))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
