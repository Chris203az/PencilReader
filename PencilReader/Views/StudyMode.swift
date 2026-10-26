import Observation
import PencilKit
import ReaderCore
import SwiftUI

// MARK: Method

/// The highlighter colors of the study method, each with one fixed meaning.
enum StudyColor: String, CaseIterable {
    case key, formula, review

    var label: String {
        switch self {
        case .key: "Concetto chiave"
        case .formula: "Formula / dato"
        case .review: "Da rivedere"
        }
    }

    var shortLabel: String {
        switch self {
        case .key: "Concetto"
        case .formula: "Formula"
        case .review: "Rivedere"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .key: UIColor(red: 1.0, green: 0.62, blue: 0.15, alpha: 1)
        case .formula: UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1)
        case .review: UIColor(red: 1.0, green: 0.45, blue: 0.7, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

/// What the Pencil does in study mode.
enum StudyTool: Equatable {
    case highlighter(StudyColor)
    /// A thin line under the English terms to learn, straightened when the Pencil lifts.
    case underline
    /// Questions and notes in the margin, in one's own words.
    case pen
    case eraser

    static let underlineColor = UIColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1)
    static let penColor = UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1)
    /// See-through, and multiplied over the page, so the words stay black under the color.
    static let highlightAlpha: CGFloat = 0.58

    /// Widths are in page units: the page is `StudyCanvasView.pageWidth` wide.
    var pkTool: PKTool {
        switch self {
        case .highlighter(let color): PKInkingTool(.marker, color: color.uiColor.withAlphaComponent(Self.highlightAlpha), width: 22)
        case .underline: PKInkingTool(.pen, color: Self.underlineColor, width: 2.5)
        case .pen: PKInkingTool(.pen, color: Self.penColor, width: 2.2)
        case .eraser: PKEraserTool(.vector)
        }
    }
}

// MARK: Model

/// Study mode of one open book: whether it is on, the tool in hand, which pages have marks.
/// The marks are saved a moment after the last stroke, when the page changes, when the mode
/// is turned off and when the app leaves the screen.
@MainActor
@Observable
final class StudyModel {
    let bookID: UUID
    private(set) var isActive = false
    var tool: StudyTool = .highlighter(.key)
    /// Pages of this book with study marks on them.
    private(set) var markedPages: Set<Int>
    var canUndo = false
    var showsGuide = false

    @ObservationIgnored weak var canvas: StudyCanvasView?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let guideKey = "studyGuideSeen"
    private static let saveDelay = Duration.seconds(1)

    init(bookID: UUID) {
        self.bookID = bookID
        markedPages = AnnotationStore.pagesWithMarks(of: bookID)
    }

    /// The first time, the guide opens with it.
    func toggle() {
        if isActive {
            flush()
            isActive = false
        } else {
            isActive = true
            if !UserDefaults.standard.bool(forKey: Self.guideKey) {
                UserDefaults.standard.set(true, forKey: Self.guideKey)
                showsGuide = true
            }
        }
    }

    func drawing(of page: Int) -> PKDrawing {
        guard var drawing = AnnotationStore.drawing(of: bookID, page: page) else { return PKDrawing() }
        // Highlights saved with an older look: the transparency of today, and orange for the old yellow.
        for i in drawing.strokes.indices where drawing.strokes[i].ink.inkType == .marker {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            drawing.strokes[i].ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let wasYellow = abs(r - 1) < 0.05 && abs(g - 0.86) < 0.05 && abs(b - 0.1) < 0.05
            guard wasYellow || abs(a - StudyTool.highlightAlpha) > 0.01 else { continue }
            let color = wasYellow ? StudyColor.key.uiColor : UIColor(red: r, green: g, blue: b, alpha: 1)
            drawing.strokes[i].ink = PKInk(.marker, color: color.withAlphaComponent(StudyTool.highlightAlpha))
        }
        return drawing
    }

    func save(_ drawing: PKDrawing, page: Int) {
        if AnnotationStore.save(drawing, of: bookID, page: page) {
            markedPages.insert(page)
        } else {
            markedPages.remove(page)
        }
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
        guard let canvas, let page = canvas.page else { return }
        save(canvas.drawing, page: page)
    }

    func undo() { canvas?.undo() }
}

// MARK: Canvas

/// The marks over the book page. The drawing is in page units, `pageWidth` wide whatever the
/// page's size on screen; the canvas' zoom and scroll put it exactly over the page image, so
/// the marks stay on their text when the page is zoomed, moved, rotated or resized by the notebook.
/// Only the Pencil draws: finger gestures reach the reader view the canvas sits in.
final class StudyCanvasView: PKCanvasView {
    static let pageWidth: CGFloat = 1000

    let study: StudyModel
    /// The page whose marks the canvas shows.
    private(set) var page: Int?
    private var pageFrame: CGRect = .zero
    private var pageText: PageText?
    private var appliedTool: StudyTool?

    /// Never the canvas itself, as in the notebook: PencilKit would call it forever.
    private let events = StudyCanvasEvents()
    /// The drawing before each change, for Annulla. One entry per stroke or eraser drag.
    private var history: [PKDrawing] = []
    /// The drawing when the Pencil touched down, and its stroke count.
    private var atStart: PKDrawing?
    private var recordedThisStroke = false
    private var snappedThisStroke = false
    private var isSettingDrawing = false

    private var pageHeight: CGFloat {
        guard pageFrame.width > 0 else { return Self.pageWidth }
        return Self.pageWidth * pageFrame.height / pageFrame.width
    }

    init(study: StudyModel) {
        self.study = study
        super.init(frame: .zero)
        drawingPolicy = .pencilOnly
        backgroundColor = .clear
        isOpaque = false
        // The page is a scan on white: the ink keeps its colors in dark mode.
        overrideUserInterfaceStyle = .light
        // Ink multiplies with the page like a real highlighter: the text under it stays black.
        layer.compositingFilter = "multiplyBlendMode"
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 0.05
        maximumZoomScale = 20
        isScrollEnabled = false
        // The scroll view's own pan and pinch would take the fingers from the reader's zoom.
        // Disabling them is not enough: the scroll view turns its pinch back on when the zoom changes.
        let pencil = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        panGestureRecognizer.allowedTouchTypes = pencil
        pinchGestureRecognizer?.allowedTouchTypes = pencil
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        events.canvas = self
        delegate = events
        study.canvas = self
        leaveFingersToReader()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        leaveFingersToReader()
    }

    /// PencilKit's own gestures, here and in its inner views, only take the Pencil:
    /// fingers go to the reader view under the canvas, which pinches, swipes and taps.
    private func leaveFingersToReader() {
        let pencil = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        var views: [UIView] = [self]
        while let view = views.popLast() {
            view.gestureRecognizers?.forEach { $0.allowedTouchTypes = pencil }
            views.append(contentsOf: view.subviews)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("StudyCanvasView si crea solo da codice")
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer || gestureRecognizer === pinchGestureRecognizer { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// Follows the reader: the page shown, where its image is on screen, its recognized text, the tool.
    func update(page newPage: Int, frame: CGRect, text: PageText?) {
        pageText = text
        if appliedTool != study.tool {
            tool = study.tool.pkTool
            appliedTool = study.tool
        }
        if newPage != page {
            // This runs inside a SwiftUI update: the model, which views observe, changes just after it.
            if let page {
                let marks = drawing, study = study
                DispatchQueue.main.async {
                    study.save(marks, page: page)
                    study.canUndo = false
                }
            }
            page = newPage
            history = []
            atStart = nil
            // Placed first: the new marks are drawn at the zoom and scroll of the page they belong to.
            place(on: frame)
            let marks = study.drawing(of: newPage)
            setDrawing(marks)
            // PencilKit can keep showing the last stroke of the old page, on top of the new one,
            // until the next stroke repaints the canvas. Emptied and refilled once it has settled,
            // the canvas repaints everything.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.page == newPage, self.drawing == marks else { return }
                self.setDrawing(PKDrawing())
                self.setDrawing(marks)
            }
        }
        place(on: frame)
    }

    /// Zooms and scrolls the canvas so that the page's units land on the image.
    func place(on frame: CGRect) {
        guard frame.width > 0 else { return }
        pageFrame = frame
        let zoom = frame.width / Self.pageWidth
        if abs(zoomScale - zoom) > 0.0001 { zoomScale = zoom }
        contentSize = frame.size
        contentOffset = CGPoint(x: -frame.minX, y: -frame.minY)
    }

    /// After the canvas itself was resized.
    func reposition() { place(on: pageFrame) }

    func undo() {
        guard let previous = history.popLast() else { return }
        setDrawing(previous)
        study.canUndo = !history.isEmpty
        study.drawingDidChange()
    }

    private func setDrawing(_ newDrawing: PKDrawing) {
        isSettingDrawing = true
        drawing = newDrawing
        isSettingDrawing = false
    }

    fileprivate func toolBegan() {
        atStart = drawing
        recordedThisStroke = false
        snappedThisStroke = false
    }

    fileprivate func drawingDidChange() {
        guard !isSettingDrawing else { return }
        // PencilKit may add the stroke just after the Pencil lifts, so the stroke is told apart
        // by its start, not by its end.
        if !recordedThisStroke, let atStart {
            history.append(atStart)
            recordedThisStroke = true
            study.canUndo = true
        }
        if !snappedThisStroke, let atStart, drawing.strokes.count == atStart.strokes.count + 1 {
            snappedThisStroke = true
            let tool = study.tool
            // Outside PencilKit's callback, which must not see the drawing change under it.
            DispatchQueue.main.async { [weak self] in self?.snapLastStroke(made: tool) }
        }
        study.drawingDidChange()
    }

    // MARK: Snapping

    /// A highlight becomes bands over the lines of text it went over; an underline becomes straight.
    private func snapLastStroke(made tool: StudyTool) {
        guard let stroke = drawing.strokes.last, !stroke.path.isEmpty else { return }
        let height = pageHeight
        let points = stroke.path.map { point -> CGPoint in
            let p = point.location.applying(stroke.transform)
            return CGPoint(x: p.x / Self.pageWidth, y: p.y / height)
        }
        let sample = stroke.path[stroke.path.count / 2]
        let replacement: [PKStroke]
        switch tool {
        case .highlighter:
            guard let pageText else { return }
            let rects = StudyMarks.highlightRects(for: points, in: pageText)
            guard !rects.isEmpty else { return }
            replacement = rects.map { rect in
                let band = CGRect(x: rect.minX * Self.pageWidth, y: rect.minY * height,
                                  width: rect.width * Self.pageWidth, height: rect.height * height)
                // A bit taller than the letters; the round ends stay inside the words.
                let size = band.height * 1.15
                let inset = min(size * 0.35, band.width / 2)
                return line(from: CGPoint(x: band.minX + inset, y: band.midY),
                            to: CGPoint(x: band.maxX - inset, y: band.midY),
                            size: CGSize(width: size, height: size), like: stroke, sample: sample)
            }
        case .underline:
            guard let segment = StudyMarks.underline(for: points, in: pageText) else { return }
            replacement = [line(from: CGPoint(x: segment.start.x * Self.pageWidth, y: segment.start.y * height),
                                to: CGPoint(x: segment.end.x * Self.pageWidth, y: segment.end.y * height),
                                size: sample.size, like: stroke, sample: sample)]
        case .pen, .eraser:
            return
        }
        var updated = drawing
        updated.strokes.removeLast()
        updated.strokes.append(contentsOf: replacement)
        // The history already holds the page before the hand-drawn stroke: one Annulla takes all of it away.
        setDrawing(updated)
        study.drawingDidChange()
    }

    private func line(from start: CGPoint, to end: CGPoint, size: CGSize, like stroke: PKStroke,
                      sample: PKStrokePoint) -> PKStroke {
        let steps = max(Int(hypot(end.x - start.x, end.y - start.y) / 4), 1)
        let controls = (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                                 timeOffset: TimeInterval(i) * 0.005, size: size, opacity: sample.opacity,
                                 force: sample.force, azimuth: sample.azimuth, altitude: sample.altitude)
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: controls, creationDate: stroke.path.creationDate))
    }
}

private final class StudyCanvasEvents: NSObject, PKCanvasViewDelegate {
    weak var canvas: StudyCanvasView?

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        canvas?.toolBegan()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        canvas?.drawingDidChange()
    }
}

// MARK: Tool bar

/// The study tools, floating over the bottom of the page while study mode is on.
struct StudyToolbar: View {
    @Bindable var study: StudyModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(labeled: true)
            bar(labeled: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    private func bar(labeled: Bool) -> some View {
        HStack(spacing: labeled ? 6 : 2) {
            ForEach(StudyColor.allCases, id: \.self) { color in
                toolButton(.highlighter(color), labeled: labeled, label: color.shortLabel, help: color.label) {
                    Image(systemName: "highlighter")
                        .foregroundStyle(color.color)
                }
            }
            Divider().frame(height: 28)
            toolButton(.underline, labeled: labeled, label: "Termine", help: "Sottolinea un termine inglese") {
                Image(systemName: "underline")
                    .foregroundStyle(Color(uiColor: StudyTool.underlineColor))
            }
            toolButton(.pen, labeled: labeled, label: "Nota", help: "Nota a margine") {
                Image(systemName: "pencil.line")
                    .foregroundStyle(Color(uiColor: StudyTool.penColor))
            }
            toolButton(.eraser, labeled: labeled, label: "Gomma", help: "Gomma") {
                Image(systemName: "eraser")
            }
            Divider().frame(height: 28)
            Button("Annulla", systemImage: "arrow.uturn.backward") { study.undo() }
                .disabled(!study.canUndo)
                .frame(width: 40, height: 40)
            Button("Come studiare", systemImage: "questionmark.circle") { study.showsGuide = true }
                .frame(width: 40, height: 40)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .fixedSize()
    }

    private func toolButton(_ tool: StudyTool, labeled: Bool, label: String, help: String,
                            @ViewBuilder icon: () -> some View) -> some View {
        let selected = study.tool == tool
        return Button {
            study.tool = tool
        } label: {
            VStack(spacing: 1) {
                icon()
                if labeled {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, labeled ? 4 : 0)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Guide

/// How to study with the marks, from the research on learning from text.
struct StudyGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("Leggi prima, segna dopo",
         "Leggi tutto il paragrafo senza la penna. Solo alla fine decidi cosa conta: così scegli, invece di colorare tutto."),
        ("Poco e sempre con lo stesso significato",
         "Al massimo una frase per paragrafo. Ogni colore vuol dire sempre la stessa cosa (legenda sotto)."),
        ("Sottolinea i termini inglesi",
         "Una riga sotto le parole tecniche da imparare. La riga si raddrizza da sola."),
        ("Scrivi una domanda a margine",
         "Con la penna, con parole tue: «Perché il CL crolla dopo lo stallo?». Riformulare fissa il concetto molto più del colore."),
        ("Ripassa provando a ricordare",
         "Nei giorni seguenti copri il testo e rispondi alle domande a margine. Comincia dalle pagine con il rosa e torna su quelle che sbagli.")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Evidenziare da solo aiuta poco a ricordare. Funziona quando è selettivo e soprattutto quando lo usi per farti domande e poi provare a ricordare senza guardare.")
                        .foregroundStyle(.secondary)
                }
                Section("Il metodo") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.0).font(.headline)
                                Text(step.1).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("Legenda") {
                    ForEach(StudyColor.allCases, id: \.self) { color in
                        legendRow(color.color, opacity: StudyTool.highlightAlpha, title: color.label, detail: detail(of: color))
                    }
                    legendRow(Color(uiColor: StudyTool.underlineColor), opacity: 1, title: "Sottolineato",
                              detail: "Termine inglese da imparare", thin: true)
                    legendRow(Color(uiColor: StudyTool.penColor), opacity: 1, title: "Penna",
                              detail: "Domande e note a margine", thin: true)
                }
                Section("Come si usa") {
                    Label("La Pencil segna; il cerchio per tradurre è spento finché la modalità è attiva.", systemImage: "applepencil")
                    Label("Con il dito sfogli, zoomi e giri pagina come sempre.", systemImage: "hand.point.up.left")
                    Label("Sulle pagine col testo riconosciuto l'evidenziatore si aggancia alle righe.", systemImage: "text.viewfinder")
                    Label("Le pagine segnate hanno l'evidenziatore nella griglia delle pagine.", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle("Come studiare con questa modalità")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private func detail(of color: StudyColor) -> String {
        switch color {
        case .key: "Definizioni e idee principali"
        case .formula: "Equazioni, valori, ipotesi e unità"
        case .review: "Non chiaro: da rivedere o chiedere"
        }
    }

    private func legendRow(_ color: Color, opacity: Double, title: String, detail: String, thin: Bool = false) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: thin ? 1 : 4)
                .fill(color.opacity(opacity))
                .frame(width: 34, height: thin ? 3 : 18)
                .frame(height: 18)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
