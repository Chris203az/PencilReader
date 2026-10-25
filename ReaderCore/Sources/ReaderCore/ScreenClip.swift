import CoreGraphics

/// The part of a screen snapshot cut out by an outline drawn with the Pencil.
///
/// Works in screen points, y growing downwards. The outline is closed by joining its ends;
/// what is outside it stays transparent. A stroke that is almost a rectangle keeps the
/// whole rectangle, as that is what was meant.
public struct ScreenClip: Equatable, Sendable {
    /// Bounding box of the outline, inside the screen and on whole pixels.
    public let rect: CGRect
    /// Closed outline relative to `rect`'s origin; nil when the whole rect is kept.
    public let outline: [CGPoint]?

    /// Below this side, in points, the stroke is taken for a slip, not a selection.
    public static let minimumSide: CGFloat = 16

    /// Nil when the stroke encloses nothing worth copying (a dot, a line, a tiny loop)
    /// or lies off `bounds`.
    public static func make(stroke: [CGPoint], bounds: CGRect, scale: CGFloat) -> ScreenClip? {
        guard stroke.count >= 3, scale > 0 else { return nil }
        let box = CGRect(boundingPoints: stroke)
        guard box.width >= minimumSide, box.height >= minimumSide,
              abs(Polygon.signedArea(stroke)) >= box.width * box.height * 0.2 else { return nil }

        let rect = pixelAligned(box, scale: scale).intersection(pixelAligned(bounds, scale: scale))
        guard !rect.isNull, rect.width >= 1 / scale, rect.height >= 1 / scale else { return nil }

        if isNearlyRectangle(stroke, box: box) { return ScreenClip(rect: rect, outline: nil) }
        let outline = stroke.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
        return ScreenClip(rect: rect, outline: outline)
    }

    /// Whether `point` (relative to `rect`'s origin) is kept in the copied image.
    public func contains(_ point: CGPoint) -> Bool {
        guard CGRect(origin: .zero, size: rect.size).contains(point) else { return false }
        guard let outline else { return true }
        return Polygon.contains(point, in: outline)
    }

    /// Filled almost like its bounding box, with nearly every point along the box's sides.
    /// A circle fills π/4 of its box, a hand-drawn rectangle well over 0.85.
    static func isNearlyRectangle(_ stroke: [CGPoint], box: CGRect) -> Bool {
        let area = abs(Polygon.signedArea(stroke))
        guard area >= box.width * box.height * 0.86 else { return false }
        let tolerance = max(6, min(box.width, box.height) * 0.08)
        let onSides = stroke.filter { p in
            min(p.x - box.minX, box.maxX - p.x, p.y - box.minY, box.maxY - p.y) <= tolerance
        }
        return CGFloat(onSides.count) >= CGFloat(stroke.count) * 0.85
    }

    /// Grown outwards to whole pixels, so the crop never cuts a pixel in half.
    static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        let minX = (r.minX * scale).rounded(.down) / scale, minY = (r.minY * scale).rounded(.down) / scale
        let maxX = (r.maxX * scale).rounded(.up) / scale, maxY = (r.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
