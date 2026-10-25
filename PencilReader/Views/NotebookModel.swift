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
    /// Turns a stroke that looks like a line, a rectangle, a triangle or a circle into a clean shape.
    var straightensShapes: Bool {
        didSet { UserDefaults.standard.set(straightensShapes, forKey: Self.shapesKey) }
    }

    @ObservationIgnored private weak var canvas: NotebookCanvasView?
    /// The page whose drawing the canvas shows. It can differ from `pageIndex` only while
    /// a page change is being handled, so saving always goes to the page that was written on.
    @ObservationIgnored private var canvasPage: Int?
    /// How many strokes of the shown page have already been looked at for shapes.
    @ObservationIgnored private var checkedStrokeCount = 0
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
            self?.finishStroke()
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

    /// Runs once the pen has lifted: straightens the stroke just written if it is a shape, then saves.
    private func finishStroke() {
        straightenNewStroke()
        flush()
    }

    private func straightenNewStroke() {
        guard let canvas else { return }
        var strokes = canvas.drawing.strokes
        defer { checkedStrokeCount = strokes.count }
        guard straightensShapes, strokes.count > checkedStrokeCount, let stroke = strokes.last,
              let template = stroke.path.first else { return }

        let points = stroke.path.map { $0.location.applying(stroke.transform) }
        // Only a stroke the pen holds at its end becomes a shape; one written in motion stays as it is.
        guard ShapeRecognizer.endsWithHold(points, times: stroke.path.map(\.timeOffset)),
              let shape = ShapeRecognizer.recognize(points) else { return }

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
        checkedStrokeCount = canvas.drawing.strokes.count
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
