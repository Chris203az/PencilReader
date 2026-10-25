import Observation
import PencilKit
import ReaderCore
import SwiftUI

/// The notebook beside a book page. Holds the page it shows and saves what is written on it
/// a moment after the last stroke, when the page changes, when the notebook closes and when the app leaves the screen.
/// A page gets a note only when the user starts one on it; turning pages never creates one.
@MainActor
@Observable
final class NotebookModel {
    let bookID: UUID
    private(set) var pageIndex: Int
    /// Pages of this book with something written on them.
    private(set) var notedPages: Set<Int>
    /// Whether the current page is showing its note, the canvas to write on.
    private(set) var isWriting: Bool
    /// The tool in hand, its color and width, and how the tool bar is laid out.
    let tools = NotebookTools()
    var paper: PaperStyle {
        didSet { UserDefaults.standard.set(paper.rawValue, forKey: Self.paperKey) }
    }
    /// Holding the Pencil still at the end of a stroke turns it into a clean line, polygon or ellipse.
    var straightensShapes: Bool {
        didSet { UserDefaults.standard.set(straightensShapes, forKey: Self.shapesKey) }
    }
    /// Each stroke loses its shake when the Pencil lifts, without moving by more than a point.
    var smoothsStrokes: Bool {
        didSet { UserDefaults.standard.set(smoothsStrokes, forKey: Self.smoothKey) }
    }
    /// How far, in points, smoothing may move a stroke's points: 1 to 4.
    var smoothingStrength: Double {
        didSet { UserDefaults.standard.set(smoothingStrength, forKey: Self.strengthKey) }
    }

    /// The clean shapes on the page shown, by the random seed of their stroke, as drawn before any
    /// transform the stroke carries. Shapes no longer on the page stay until it is saved, for Annulla.
    @ObservationIgnored private(set) var shapes: [UInt32: InkShape] = [:]
    @ObservationIgnored private weak var canvas: NotebookCanvasView?
    /// The page whose drawing the canvas shows. It can differ from `pageIndex` only while
    /// a page change is being handled, so saving always goes to the page that was written on.
    @ObservationIgnored private var canvasPage: Int?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let paperKey = "notebookPaper"
    private static let shapesKey = "notebookShapes"
    private static let smoothKey = "notebookSmoothStrokes"
    private static let strengthKey = "notebookSmoothingStrength"
    private static let saveDelay = Duration.seconds(1)

    init(bookID: UUID, pageIndex: Int) {
        self.bookID = bookID
        self.pageIndex = pageIndex
        let noted = NoteStore.pagesWithNotes(of: bookID)
        notedPages = noted
        isWriting = noted.contains(pageIndex)
        paper = UserDefaults.standard.string(forKey: Self.paperKey).flatMap(PaperStyle.init) ?? .grid
        straightensShapes = UserDefaults.standard.object(forKey: Self.shapesKey) as? Bool ?? true
        smoothsStrokes = UserDefaults.standard.object(forKey: Self.smoothKey) as? Bool ?? true
        smoothingStrength = UserDefaults.standard.object(forKey: Self.strengthKey) as? Double ?? 3
    }

    /// Turns to another page of the book: saves the current one, then shows the new one's note if it has one.
    func show(_ page: Int) {
        guard page != pageIndex else { return }
        flush()
        pageIndex = page
        isWriting = notedPages.contains(page)
        if isWriting {
            loadDrawing()
        } else {
            canvas = nil
            canvasPage = nil
        }
    }

    /// Starts a note on the current page, when the user asks for one.
    func startNote() {
        isWriting = true
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
        canvasPage = nil
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
        guard let canvas, let page = canvasPage else { return }
        NoteStore.saveShapes(shapes, for: canvas.drawing, of: bookID, page: page)
        if NoteStore.save(canvas.drawing, of: bookID, page: page) {
            notedPages.insert(page)
        } else {
            notedPages.remove(page)
        }
    }

    /// Remembers a shape about to be put on the page; its stroke must carry the seed returned.
    func register(_ shape: InkShape) -> UInt32 {
        var seed = UInt32.random(in: 1...UInt32.max)
        while shapes[seed] != nil { seed = UInt32.random(in: 1...UInt32.max) }
        shapes[seed] = shape
        return seed
    }

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }

    private func loadDrawing() {
        guard let canvas else { return }
        canvasPage = pageIndex
        shapes = NoteStore.shapes(of: bookID, page: pageIndex)
        canvas.drawing = NoteStore.drawing(of: bookID, page: pageIndex) ?? PKDrawing()
        canvas.undoManager?.removeAllActions()
        canvas.resetZoom()
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
