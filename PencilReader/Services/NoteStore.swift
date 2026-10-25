import Foundation
import PencilKit
import ReaderCore

/// Handwritten notes, one PencilKit drawing per book page, in
/// Application Support/Notes/<book id>/<page>.drawing. A blank page has no file.
/// Beside it, <page>.shapes.json keeps the geometry of the strokes that are clean shapes,
/// by the stroke's random seed, so that they can be reshaped later.
enum NoteStore {
    private static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Notes", directoryHint: .isDirectory)
    }

    private static func folder(of bookID: UUID) -> URL {
        root.appending(path: bookID.uuidString, directoryHint: .isDirectory)
    }

    static func url(of bookID: UUID, page: Int) -> URL {
        root.appending(path: PageNote(bookID: bookID, pageIndex: page).relativePath)
    }

    private static func shapesURL(of bookID: UUID, page: Int) -> URL {
        folder(of: bookID).appending(path: String(format: "%04d.shapes.json", page))
    }

    /// The shapes of a page, by the random seed of their stroke.
    static func shapes(of bookID: UUID, page: Int) -> [UInt32: InkShape] {
        guard let data = try? Data(contentsOf: shapesURL(of: bookID, page: page)) else { return [:] }
        return (try? JSONDecoder().decode([UInt32: InkShape].self, from: data)) ?? [:]
    }

    /// Keeps only the shapes still on the page; no file when there are none.
    static func saveShapes(_ shapes: [UInt32: InkShape], for drawing: PKDrawing, of bookID: UUID, page: Int) {
        let seeds = Set(drawing.strokes.map(\.randomSeed))
        let kept = shapes.filter { seeds.contains($0.key) }
        let file = shapesURL(of: bookID, page: page)
        guard !kept.isEmpty, let data = try? JSONEncoder().encode(kept) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: folder(of: bookID), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func drawing(of bookID: UUID, page: Int) -> PKDrawing? {
        guard let data = try? Data(contentsOf: url(of: bookID, page: page)) else { return nil }
        return try? PKDrawing(data: data)
    }

    /// Writes the drawing, or removes the file when nothing is left on the page.
    /// Returns whether the page has ink now.
    @discardableResult
    static func save(_ drawing: PKDrawing, of bookID: UUID, page: Int) -> Bool {
        let file = url(of: bookID, page: page)
        guard !drawing.strokes.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return false
        }
        try? FileManager.default.createDirectory(at: folder(of: bookID), withIntermediateDirectories: true)
        if let data = try? drawing.dataRepresentation() {
            try? data.write(to: file, options: .atomic)
        }
        return true
    }

    static func pagesWithNotes(of bookID: UUID) -> Set<Int> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder(of: bookID).path(percentEncoded: false))) ?? []
        return Set(names.compactMap(PageNote.pageIndex(fromFileName:)))
    }

    /// Called when the book itself is deleted.
    static func deleteNotes(of bookID: UUID) {
        try? FileManager.default.removeItem(at: folder(of: bookID))
    }
}
