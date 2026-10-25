import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import UIKit
import Vision

/// Turns photos and PDF pages into upright bitmaps ready for OCR.
enum PageImages {
    static let maxDimension: CGFloat = 2600

    /// Applies EXIF orientation and caps the size, so OCR and display share one pixel grid.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = maxDimension) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        if image.imageOrientation == .up, scale == 1 { return image }
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Finds the page in a photo and corrects the perspective. Returns the
    /// input unchanged when no convincing page outline is found.
    static func straightened(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        guard let page = request.results?.first, page.confidence > 0.6 else { return image }

        // Skip when the "page" is a small region: likely a false detection.
        let quad = [page.topLeft, page.topRight, page.bottomRight, page.bottomLeft]
        var area: CGFloat = 0
        for i in quad.indices {
            let a = quad[i], b = quad[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        guard abs(area) / 2 > 0.2 else { return image }

        // Vision and Core Image both use a bottom-left origin.
        let input = CIImage(cgImage: cgImage)
        let w = input.extent.width, h = input.extent.height
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = input
        filter.topLeft = scaled(page.topLeft)
        filter.topRight = scaled(page.topRight)
        filter.bottomRight = scaled(page.bottomRight)
        filter.bottomLeft = scaled(page.bottomLeft)
        guard let output = filter.outputImage,
              let result = CIContext().createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: result)
    }

    static func render(_ page: PDFPage, maxDimension: CGFloat = maxDimension) -> UIImage {
        var size = page.bounds(for: .cropBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let scale = maxDimension / max(size.width, size.height)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            // PDF space is bottom-left; draw(with:to:) applies the page rotation itself.
            ctx.cgContext.translateBy(x: 0, y: target.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .cropBox, to: ctx.cgContext)
        }
    }
}
