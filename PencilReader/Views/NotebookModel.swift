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
    var paper: PaperStyle {
        didSet { UserDefaults.standard.set(paper.rawValue, forKey: Self.paperKey) }
    }
    /// Turns a stroke the pen holds at the end into the clean shape it was meant to be.
    var straightensShapes: Bool {
        didSet { UserDefaults.standard.set(straightensShapes, forKey: Self.shapesKey) }
    }

    @ObservationIgnored private weak var canvas: NotebookCanvasView?
    /// The page whose drawing the canvas shows. It can differ from `pageIndex` only while
    /// a page change is being handled, so saving always goes to the page that was written on.
    @ObservationIgnored private var canvasPage: Int?
    /// How many strokes of the shown page are already settled, shape or not.
    @ObservationIgnored private var settledStrokeCount = 0
    /// The shape of the stroke the pen just held, waiting for PencilKit to commit that stroke.
    @ObservationIgnored private var pendingShape: InkShape?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let paperKey = "notebookPaper"
    private static let shapesKey = "notebookShapes"
    private static let saveDelay = Duration.seconds(1)

    init(bookID: UUID, pageIndex: Int) {
        self.bookID = bookID
        self.pageIndex = pageIndex
        let noted = NoteStore.pagesWithNotes(of: bookID)
        notedPages = noted
        isWriting = noted.contains(pageIndex)
        paper = UserDefaults.standard.string(forKey: Self.paperKey).flatMap(PaperStyle.init) ?? .grid
        straightensShapes = UserDefaults.standard.object(forKey: Self.shapesKey) as? Bool ?? true
    }

    /// Turns to another page of the book: saves the current one, then shows the new one's note if it has one.
    func show(_ page: Int) {
        guard page != pageIndex else { return }
        flush()
        pageIndex = page
        isWriting = notedPages.contains(page)
        pendingShape = nil
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
        // An erase or an undo can leave fewer strokes than were settled before.
        settledStrokeCount = min(settledStrokeCount, canvas?.drawing.strokes.count ?? 0)
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
        if NoteStore.save(canvas.drawing, of: bookID, page: page) {
            notedPages.insert(page)
        } else {
            notedPages.remove(page)
        }
    }

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }

    /// The pen was held at the end of a stroke and it showed this shape: replace the stroke with it.
    func setPendingShape(_ shape: InkShape) {
        pendingShape = shape
        applyPendingShape()
    }

    /// Replaces the newest stroke with the pending shape, once PencilKit has committed that stroke.
    /// Called outside PencilKit's callbacks, so the drawing is never changed while PencilKit is still busy.
    func applyPendingShape() {
        guard let shape = pendingShape, let canvas else { return }
        var strokes = canvas.drawing.strokes
        guard strokes.count > settledStrokeCount, let stroke = strokes.last,
              let template = stroke.path.first else { return }
        pendingShape = nil

        // Same ink, color and pressure as the stroke it replaces.
        let controls = shape.outline.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.01,
                          size: template.size, opacity: template.opacity, force: template.force,
                          azimuth: template.azimuth, altitude: template.altitude)
        }
        strokes[strokes.count - 1] = PKStroke(ink: stroke.ink,
                                              path: PKStrokePath(controlPoints: controls,
                                                                 creationDate: stroke.path.creationDate))
        swapDrawing(to: PKDrawing(strokes: strokes))
        settledStrokeCount = strokes.count
    }

    /// Shows another drawing and records the change, so Annulla brings the previous one back.
    private func swapDrawing(to drawing: PKDrawing) {
        guard let canvas else { return }
        let previous = canvas.drawing
        canvas.drawing = drawing
        canvas.undoManager?.registerUndo(withTarget: canvas) { [weak self] _ in
            self?.swapDrawing(to: previous)
        }
    }

    private func loadDrawing() {
        guard let canvas else { return }
        canvasPage = pageIndex
        canvas.drawing = NoteStore.drawing(of: bookID, page: pageIndex) ?? PKDrawing()
        canvas.undoManager?.removeAllActions()
        canvas.fitContent()
        settledStrokeCount = canvas.drawing.strokes.count
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
