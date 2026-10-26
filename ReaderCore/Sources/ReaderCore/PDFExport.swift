import CoreGraphics
import Foundation

/// Which pages of the book go into the exported PDF.
public enum ExportPages: Hashable, Sendable {
    case all
    /// Zero-based, both ends included.
    case range(ClosedRange<Int>)
    /// Pages with study marks or a note.
    case annotated
}

/// Where the notebook's note of a page goes in the exported PDF.
public enum NoteLayout: String, CaseIterable, Sendable {
    case none
    /// Beside the book page, on the right, as on the screen.
    case beside
    /// On a page of its own after the book page.
    case after

    public var label: String {
        switch self {
        case .none: "Nessuna"
        case .beside: "Affiancata"
        case .after: "Pagina dopo"
        }
    }
}

/// The geometry of an exported PDF, apart from the drawing itself.
public enum PDFExportPlan {
    /// Paper left past the last stroke of a note, in the note's points.
    public static let noteMargin: CGFloat = 24

    /// The zero-based pages to export, in order.
    public static func pages(_ choice: ExportPages, pageCount: Int, annotated: Set<Int>) -> [Int] {
        guard pageCount > 0 else { return [] }
        switch choice {
        case .all:
            return Array(0..<pageCount)
        case .range(let range):
            let lower = max(range.lowerBound, 0), upper = min(range.upperBound, pageCount - 1)
            return lower <= upper ? Array(lower...upper) : []
        case .annotated:
            return annotated.filter { (0..<pageCount).contains($0) }.sorted()
        }
    }

    /// Width of the notebook beside a book page `pageWidth` wide, shared as on the screen.
    public static func noteColumnWidth(pageWidth: CGFloat, split: Double) -> CGFloat {
        let split = SplitRatio.clamped(split)
        return pageWidth * CGFloat((1 - split) / split)
    }

    /// The written part of a note, in its own points, from the top-left corner of the paper:
    /// at least `minWidth` wide, with a margin past the ink. Zero high when there is no ink.
    public static func noteSize(inkBounds: CGRect, minWidth: CGFloat) -> CGSize {
        guard !inkBounds.isNull, !inkBounds.isEmpty else { return CGSize(width: minWidth, height: 0) }
        return CGSize(width: max(minWidth, inkBounds.maxX + noteMargin),
                      height: max(0, inkBounds.maxY + noteMargin))
    }

    /// The bands of a note, top to bottom, each filling `box` when scaled to its width.
    /// A note taller than the box goes on over the next bands; there is always at least one.
    public static func slices(noteSize: CGSize, box: CGSize) -> [CGRect] {
        guard noteSize.width > 0, box.width > 0, box.height > 0 else { return [] }
        let height = box.height * noteSize.width / box.width
        // A hair of ink past the band is not worth a page of its own.
        let count = max(1, Int((noteSize.height / height - 0.02).rounded(.up)))
        return (0..<count).map { CGRect(x: 0, y: CGFloat($0) * height, width: noteSize.width, height: height) }
    }

    /// A file name for the export of a book, without the characters that paths do not allow.
    public static func fileName(for title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Libro" : cleaned) + " - annotato.pdf"
    }
}
