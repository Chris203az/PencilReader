import CoreGraphics
import Foundation

/// Takes the shake out of a hand-written stroke without moving it: every point stays within
/// `maxShift` of where the Pencil put it (`shortMaxShift` on short strokes), the ends and the corners stay exactly where they are,
/// and short strokes such as dots, accents and small indices are left alone.
public enum StrokeSmoother {
    /// Strokes with fewer points than this are never touched.
    public static let minPoints = 10
    /// Strokes shorter than this, in points along the path, are never touched.
    public static let minLength: CGFloat = 8
    /// The farthest a point may move, unless told otherwise.
    public static let maxShift: CGFloat = 3
    /// The strengths, as the farthest a point may move, that can be chosen.
    public static let strengths: ClosedRange<CGFloat> = 1...4
    /// The farthest a point may move on a stroke shorter than `shortLength`, such as a small letter.
    public static let shortMaxShift: CGFloat = 1
    public static let shortLength: CGFloat = 20
    /// A turn sharper than this, in degrees, is a corner the writer meant, and stays put.
    public static let cornerAngle: CGFloat = 40

    /// Weights of the moving average, centered on the point being smoothed.
    private static let weights: [CGFloat] = [1, 2, 3, 4, 3, 2, 1]
    /// For the stronger settings: a wider stretch, so slower wobbles go too.
    private static let wideWeights: [CGFloat] = [1, 2, 3, 4, 5, 4, 3, 2, 1]

    /// The stroke's points smoothed, as many as given and in the same order, none moved further than
    /// `strength` (`shortMaxShift` on short strokes); nil when the stroke is too short to be smoothed
    /// safely or nothing would change. A stronger setting also averages over a wider stretch.
    public static func smoothed(_ points: [CGPoint], strength: CGFloat = maxShift) -> [CGPoint]? {
        let strength = min(max(strength, strengths.lowerBound), strengths.upperBound)
        let weights = strength >= 3 ? wideWeights : self.weights
        let length = pathLength(points)
        guard points.count >= minPoints, length >= minLength else { return nil }
        let limit = length < shortLength ? min(shortMaxShift, strength) : strength
        let fixed = fixedIndices(points)
        var result = points
        var changed = false
        let half = weights.count / 2
        for i in points.indices where !fixed.contains(i) {
            // The average never reaches across a fixed point, so corners stay sharp, and it is as wide
            // on both sides, so a straight or evenly curved stretch stays exactly where it is.
            var reach = 0
            while reach < half, !fixed.contains(i - reach), !fixed.contains(i + reach) { reach += 1 }
            var sum = CGPoint.zero
            var total: CGFloat = 0
            for j in (i - reach)...(i + reach) {
                let weight = weights[j - i + half]
                sum.x += points[j].x * weight
                sum.y += points[j].y * weight
                total += weight
            }
            var target = CGPoint(x: sum.x / total, y: sum.y / total)
            let dx = target.x - points[i].x, dy = target.y - points[i].y
            let shift = hypot(dx, dy)
            if shift > limit {
                target = CGPoint(x: points[i].x + dx / shift * limit, y: points[i].y + dy / shift * limit)
            }
            if shift > 0.01 { changed = true }
            result[i] = target
        }
        return changed ? result : nil
    }

    /// The two ends, and every point where the stroke turns more sharply than `cornerAngle`.
    /// The turn is measured over two points on each side, so the Pencil's own jitter does not count.
    static func fixedIndices(_ points: [CGPoint]) -> Set<Int> {
        var fixed: Set<Int> = [0, points.count - 1]
        guard points.count > 4 else { return Set(points.indices) }
        for i in 2..<(points.count - 2) {
            let a = points[i - 2], b = points[i], c = points[i + 2]
            let incoming = atan2(b.y - a.y, b.x - a.x)
            let outgoing = atan2(c.y - b.y, c.x - b.x)
            var turn = abs(outgoing - incoming)
            if turn > .pi { turn = 2 * .pi - turn }
            if turn * 180 / .pi > cornerAngle { fixed.insert(i) }
        }
        return fixed
    }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
}
