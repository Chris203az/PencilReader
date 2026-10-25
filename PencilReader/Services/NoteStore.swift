import Foundation
import PencilKit
import ReaderCore

/// Handwritten notes, one PencilKit drawing per book page, in
/// Application Support/Notes/<book id>/<page>.drawing. A blank page has no file.
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
