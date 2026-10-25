import Foundation

/// Where the handwritten note of one book page lives: one PencilKit drawing per page,
/// in a folder named after the book.
public struct PageNote: Sendable, Hashable, Identifiable {
    public let bookID: UUID
    /// Zero-based, like the rest of the reader.
    public let pageIndex: Int

    public init(bookID: UUID, pageIndex: Int) {
        self.bookID = bookID
        self.pageIndex = pageIndex
    }

    public var id: String { relativePath }

    /// `<book id>/<page>.drawing`, relative to the notes folder.
    public var relativePath: String {
        Self.relativePath(bookID: bookID, pageIndex: pageIndex)
    }

    public static func relativePath(bookID: UUID, pageIndex: Int) -> String {
        bookID.uuidString + "/" + fileName(pageIndex: pageIndex)
    }

    public static func fileName(pageIndex: Int) -> String {
        String(format: "%04d.drawing", pageIndex)
    }

    /// The page a note file belongs to, or nil for any other file.
    public static func pageIndex(fromFileName name: String) -> Int? {
        let suffix = ".drawing"
        guard name.hasSuffix(suffix) else { return nil }
        return Int(name.dropLast(suffix.count))
    }
}

/// Paper behind the notebook. The raw value is what gets stored in the settings.
public enum PaperStyle: String, CaseIterable, Sendable {
    case grid
    case lines
    case blank

    public var label: String {
        switch self {
        case .grid: "Quadretti"
        case .lines: "Righe"
        case .blank: "Bianco"
        }
    }
}

/// Share of the width given to the book page when the notebook is open.
public enum SplitRatio {
    public static let range: ClosedRange<Double> = 0.3...0.7
    public static let standard = 0.5

    public static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
