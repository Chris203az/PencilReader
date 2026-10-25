import Observation
import PencilKit
import ReaderCore
import SwiftUI

/// The notebook beside a book page. Holds the page it shows and saves what is written on it
/// a moment after the last stroke, when the page changes, when the notebook closes and when the app leaves the screen.
@MainActor
@Observable
final class NotebookModel {
    let bookID: UUID
    private(set) var pageIndex: Int
    /// Pages of this book with something written on them.
    private(set) var notedPages: Set<Int>
    var paper: PaperStyle {
        didSet { UserDefaults.standard.set(paper.rawValue, forKey: Self.paperKey) }
    }

    @ObservationIgnored private weak var canvas: NotebookCanvasView?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let paperKey = "notebookPaper"
    private static let saveDelay = Duration.seconds(1)

    init(bookID: UUID, pageIndex: Int) {
        self.bookID = bookID
        self.pageIndex = pageIndex
        notedPages = NoteStore.pagesWithNotes(of: bookID)
        paper = UserDefaults.standard.string(forKey: Self.paperKey).flatMap(PaperStyle.init) ?? .grid
    }

    /// Turns to another page of the book: saves the current one, then shows the new one.
    func show(_ page: Int) {
        guard page != pageIndex else { return }
        flush()
        pageIndex = page
        loadDrawing()
    }

    func attach(_ canvas: NotebookCanvasView) {
        self.canvas = canvas
        loadDrawing()
    }

    /// Saves and lets go of the canvas, if it is still the one shown.
    func detach(_ canvas: NotebookCanvasView) {
        guard self.canvas === canvas else { return }
        flush()
        self.canvas = nil
    }

    func drawingDidChange() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let canvas else { return }
        if NoteStore.save(canvas.drawing, of: bookID, page: pageIndex) {
            notedPages.insert(pageIndex)
        } else {
            notedPages.remove(pageIndex)
        }
    }

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }

    private func loadDrawing() {
        guard let canvas else { return }
        canvas.drawing = NoteStore.drawing(of: bookID, page: pageIndex) ?? PKDrawing()
        canvas.undoManager?.removeAllActions()
        canvas.fitContent()
    }
}

/// Where the book page and the notebook share the width. Kept between openings.
enum NotebookSettings {
    private static let splitKey = "notebookSplit"

    static var split: Double {
        UserDefaults.standard.object(forKey: splitKey) as? Double ?? SplitRatio.standard
    }

    static func saveSplit(_ value: Double) {
        UserDefaults.standard.set(value, forKey: splitKey)
    }
}
