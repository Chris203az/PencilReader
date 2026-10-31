import PDFKit
import PencilKit
import ReaderCore
import UIKit

/// Everything the export needs, gathered on the main actor so the rendering can run away from it.
struct PDFExportJob: Sendable {
    enum Source: Sendable {
        case pdf(URL)
        /// The folder of the scanned pages, NNNN.jpg.
        case images(folder: URL)
    }

    let bookID: UUID
    let title: String
    let source: Source
    /// Zero-based, in the order they go in the PDF.
    let pages: [Int]
    let includesMarks: Bool
    let noteLayout: NoteLayout
    /// The book page's share of the width, as on the screen.
    let split: Double
    let paper: PaperStyle
    /// Width of the study marks' page, `StudyCanvasView.pageWidth`.
    let marksPageWidth: CGFloat
    /// Distance between the paper's lines, `PaperView.step`.
    let paperStep: CGFloat
}

struct PDFExportResult: Sendable {
    let url: URL
    /// Pages of the PDF, notes included.
    let pageCount: Int
}

enum PDFExportError: LocalizedError {
    case unreadableBook

    var errorDescription: String? {
        switch self {
        case .unreadableBook: String(localized: "Impossibile aprire il PDF del libro.")
        }
    }
}

/// Writes a book with its study marks and notebook notes into one PDF, page by page.
/// The book's PDF pages stay vector; marks and notes are drawn as sharp images over them.
/// Stops between two pages when its task is cancelled, and leaves no file behind.
enum PDFExporter {
    /// Pixels of ink per point of the PDF.
    private static let inkResolution: CGFloat = 3
    /// The narrowest a note is taken to be, near the notebook's width on screen.
    private static let noteMinWidth: CGFloat = 500
    /// Scanned pages get the long side of an A4 sheet.
    private static let imagePageLongSide: CGFloat = 842
    private static let notePageMargin: CGFloat = 36
    private static let captionHeight: CGFloat = 28

    static func export(_ job: PDFExportJob, progress: @Sendable (Int) -> Void) throws -> PDFExportResult {
        var pdf: PDFDocument?
        if case .pdf(let url) = job.source {
            guard let document = PDFDocument(url: url) else { throw PDFExportError.unreadableBook }
            pdf = document
        }
        let folder = URL.temporaryDirectory.appending(path: "Esportazioni", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: PDFExportPlan.fileName(for: job.title))

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: job.title,
                               kCGPDFContextCreator as String: "PencilReader"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        var cancelled = false
        var written = 0
        try renderer.writePDF(to: url) { context in
            for (done, page) in job.pages.enumerated() {
                if Task.isCancelled {
                    cancelled = true
                    break
                }
                autoreleasepool {
                    written += render(page, of: job, pdf: pdf, into: context)
                }
                progress(done + 1)
            }
        }
        if cancelled {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        return PDFExportResult(url: url, pageCount: written)
    }

    // MARK: Pages

    /// One page of the book with its marks and note. Returns how many PDF pages it took.
    private static func render(_ index: Int, of job: PDFExportJob, pdf: PDFDocument?,
                               into context: UIGraphicsPDFRendererContext) -> Int {
        let book = bookPage(index, of: job, pdf: pdf)
        let bookRect = CGRect(origin: .zero, size: book.size)
        let note = job.noteLayout == .none ? nil : NoteStore.drawing(of: job.bookID, page: index)
            .flatMap { $0.strokes.isEmpty ? nil : $0 }

        func drawBook() {
            book.draw(bookRect, context.cgContext)
            if job.includesMarks { drawMarks(of: index, job: job, in: bookRect) }
        }

        guard let note else {
            context.beginPage(withBounds: bookRect, pageInfo: [:])
            drawBook()
            return 1
        }
        let noteSize = PDFExportPlan.noteSize(inkBounds: note.bounds, minWidth: noteMinWidth)

        switch job.noteLayout {
        case .beside:
            let width = PDFExportPlan.noteColumnWidth(pageWidth: book.size.width, split: job.split)
            let column = CGRect(x: book.size.width, y: 0, width: width, height: book.size.height)
            let bounds = CGRect(x: 0, y: 0, width: book.size.width + width, height: book.size.height)
            let slices = PDFExportPlan.slices(noteSize: noteSize, box: column.size)
            for (i, slice) in slices.enumerated() {
                context.beginPage(withBounds: bounds, pageInfo: [:])
                if i == 0 {
                    drawBook()
                } else {
                    fillWhite(bookRect, context.cgContext)
                    drawCaption(String(localized: "Nota di pagina \(index + 1), continua (\(i + 1)/\(slices.count))"),
                                in: bookRect.insetBy(dx: notePageMargin, dy: notePageMargin))
                }
                drawNote(note, slice: slice, in: column, job: job, context: context.cgContext)
                drawDivider(at: book.size.width, height: book.size.height, context: context.cgContext)
            }
            return slices.count
        case .after:
            context.beginPage(withBounds: bookRect, pageInfo: [:])
            drawBook()
            let inner = bookRect.insetBy(dx: notePageMargin, dy: notePageMargin)
            let box = CGRect(x: inner.minX, y: inner.minY + captionHeight,
                             width: inner.width, height: inner.height - captionHeight)
            let slices = PDFExportPlan.slices(noteSize: noteSize, box: box.size)
            for (i, slice) in slices.enumerated() {
                context.beginPage(withBounds: bookRect, pageInfo: [:])
                fillWhite(bookRect, context.cgContext)
                drawCaption(slices.count > 1 ? String(localized: "Nota di pagina \(index + 1) (\(i + 1)/\(slices.count))")
                                             : String(localized: "Nota di pagina \(index + 1)"), in: inner)
                drawNote(note, slice: slice, in: box, job: job, context: context.cgContext)
            }
            return 1 + slices.count
        case .none:
            return 0
        }
    }

    private struct BookPage {
        let size: CGSize
        let draw: (CGRect, CGContext) -> Void
    }

    private static func bookPage(_ index: Int, of job: PDFExportJob, pdf: PDFDocument?) -> BookPage {
        let blank = BookPage(size: CGSize(width: 595, height: 842)) { rect, context in fillWhite(rect, context) }
        switch job.source {
        case .pdf:
            guard let page = pdf?.page(at: index) else { return blank }
            var size = page.bounds(for: .cropBox).size
            if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            return BookPage(size: size) { rect, context in
                fillWhite(rect, context)
                context.saveGState()
                // As in PageImages.render: PDF space is bottom-left, draw(with:to:) applies the rotation.
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: rect.width / size.width, y: -rect.height / size.height)
                page.draw(with: .cropBox, to: context)
                context.restoreGState()
            }
        case .images(let folder):
            let file = folder.appending(path: String(format: "%04d.jpg", index))
            guard let image = UIImage(contentsOfFile: file.path(percentEncoded: false)),
                  image.size.width > 0, image.size.height > 0 else { return blank }
            let scale = imagePageLongSide / max(image.size.width, image.size.height)
            let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            return BookPage(size: size) { rect, _ in image.draw(in: rect) }
        }
    }

    // MARK: Ink

    /// The study marks, multiplied over the page as on the screen, so the words stay black under the color.
    private static func drawMarks(of page: Int, job: PDFExportJob, in rect: CGRect) {
        guard let saved = AnnotationStore.drawing(of: job.bookID, page: page), !saved.strokes.isEmpty else { return }
        let drawing = StudyModel.upgraded(saved)
        let area = CGRect(x: 0, y: 0, width: job.marksPageWidth,
                          height: job.marksPageWidth * rect.height / rect.width)
        let image = lightImage(of: drawing, from: area, scale: rect.width / area.width * inkResolution)
        image.draw(in: rect, blendMode: .multiply, alpha: 1)
    }

    /// One band of a note on its paper, scaled to the width of `box`.
    private static func drawNote(_ drawing: PKDrawing, slice: CGRect, in box: CGRect,
                                 job: PDFExportJob, context: CGContext) {
        fillWhite(box, context)
        let scale = box.width / slice.width
        if job.paper != .blank {
            context.saveGState()
            context.clip(to: box)
            context.translateBy(x: box.minX, y: box.minY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -slice.minX, y: -slice.minY)
            context.setStrokeColor(UIColor(white: 0.84, alpha: 1).cgColor)
            context.setLineWidth(0.5 / scale)
            let step = job.paperStep
            var y = floor(slice.minY / step) * step
            while y <= slice.maxY {
                context.move(to: CGPoint(x: slice.minX, y: y))
                context.addLine(to: CGPoint(x: slice.maxX, y: y))
                y += step
            }
            if job.paper == .grid {
                var x = floor(slice.minX / step) * step
                while x <= slice.maxX {
                    context.move(to: CGPoint(x: x, y: slice.minY))
                    context.addLine(to: CGPoint(x: x, y: slice.maxY))
                    x += step
                }
            }
            context.strokePath()
            context.restoreGState()
        }
        lightImage(of: drawing, from: slice, scale: scale * inkResolution).draw(in: box)
    }

    /// The ink as it looks in light mode: in dark mode PencilKit would turn black ink white.
    private static func lightImage(of drawing: PKDrawing, from rect: CGRect, scale: CGFloat) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }

    // MARK: Paper

    private static func fillWhite(_ rect: CGRect, _ context: CGContext) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
    }

    private static func drawDivider(at x: CGFloat, height: CGFloat, context: CGContext) {
        context.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: height))
        context.strokePath()
    }

    private static func drawCaption(_ text: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor(white: 0.45, alpha: 1)
        ]
        (text as NSString).draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: captionHeight),
                                withAttributes: attributes)
    }
}
