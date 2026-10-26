import CoreGraphics

/// The part of a screen snapshot chosen by a stroke drawn with the Pencil.
///
/// Works in screen points, y growing downwards. Whatever the stroke's shape (a circle,
/// a shaky loop, a diagonal), the copy is the rectangle reaching its farthest points,
/// so the image never has a hand-drawn edge.
public struct ScreenClip: Equatable, Sendable {
    /// Bounding box of the stroke, inside the screen and on whole pixels.
    public let rect: CGRect

    /// Below this side, in points, the stroke is taken for a slip, not a selection.
    public static let minimumSide: CGFloat = 16

    /// Nil when the stroke spans too little to copy (a dot, a straight line) or lies off `bounds`.
    public static func make(stroke: [CGPoint], bounds: CGRect, scale: CGFloat) -> ScreenClip? {
        guard stroke.count >= 2, scale > 0 else { return nil }
        let box = CGRect(boundingPoints: stroke)
        guard box.width >= minimumSide, box.height >= minimumSide else { return nil }

        let rect = pixelAligned(box, scale: scale).intersection(pixelAligned(bounds, scale: scale))
        guard !rect.isNull, rect.width >= minimumSide / 2, rect.height >= minimumSide / 2 else { return nil }
        return ScreenClip(rect: rect)
    }

    /// Grown outwards to whole pixels, so the crop never cuts a pixel in half.
    static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        let minX = (r.minX * scale).rounded(.down) / scale, minY = (r.minY * scale).rounded(.down) / scale
        let maxX = (r.maxX * scale).rounded(.up) / scale, maxY = (r.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
