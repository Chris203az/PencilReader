import PencilKit
import ReaderCore
import SwiftUI

/// The notebook next to the book page: a header, then a page the Pencil writes on.
struct NotebookPane: View {
    @Bindable var notebook: NotebookModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if notebook.isWriting {
                NotebookCanvas(notebook: notebook)
            } else {
                ContentUnavailableView {
                    Label("Nessuna nota su questa pagina", systemImage: "square.and.pencil")
                } actions: {
                    Button("Nuova nota") { notebook.startNote() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack(spacing: 18) {
            Text("Note · pag. \(notebook.pageIndex + 1)")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button("Annulla", systemImage: "arrow.uturn.backward") { notebook.undo() }
                .disabled(!notebook.isWriting)
            Button("Ripeti", systemImage: "arrow.uturn.forward") { notebook.redo() }
                .disabled(!notebook.isWriting)
            Menu("Opzioni", systemImage: "slider.horizontal.3") {
                Picker("Sfondo", selection: $notebook.paper) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Raddrizza le forme", isOn: $notebook.straightensShapes)
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Draggable line between the book page and the notebook. The line follows the finger;
/// the two sides are resized once, when it is let go, so they do not shake while moving.
struct NotebookDivider: View {
    @Binding var split: Double
    /// Width the two sides share, without the divider itself.
    let available: CGFloat
    @GestureState private var dragOffset: CGFloat = 0

    static let width: CGFloat = 16

    var body: some View {
        Capsule()
            .fill(.secondary.opacity(0.5))
            .frame(width: 4, height: 44)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in state = value.translation.width }
                    .onEnded { value in
                        split = SplitRatio.clamped(split + Double(value.translation.width / available))
                        NotebookSettings.saveSplit(split)
                    }
            )
            .accessibilityLabel("Divisore tra pagina e quaderno")
    }
}

/// Hosts the notebook page: the paper, then the PencilKit canvas on top of it.
struct NotebookCanvas: UIViewRepresentable {
    let notebook: NotebookModel

    func makeUIView(context: Context) -> NotebookSheetView {
        let view = NotebookSheetView()
        view.canvas.notebook = notebook
        notebook.attach(view.canvas)
        return view
    }

    func updateUIView(_ view: NotebookSheetView, context: Context) {
        view.paper = notebook.paper
    }

    static func dismantleUIView(_ view: NotebookSheetView, coordinator: Void) {
        if let notebook = view.canvas.notebook { notebook.detach(view.canvas) }
    }
}

/// Paper, canvas and the shape preview. The canvas is never given extra subviews, and its
/// view hierarchy is never changed from inside PencilKit's drawing callbacks.
final class NotebookSheetView: UIView {
    let canvas = NotebookCanvasView()
    private let paperView = PaperView()
    /// The clean shape shown while the pen is held, above the ink.
    private let previewLayer = CAShapeLayer()

    var paper: PaperStyle = .grid {
        didSet { paperView.style = paper }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        paperView.style = paper
        addSubview(paperView)
        addSubview(canvas)
        previewLayer.fillColor = nil
        previewLayer.lineWidth = 3
        previewLayer.lineCap = .round
        previewLayer.lineJoin = .round
        layer.addSublayer(previewLayer)
        canvas.onScroll = { [weak self] offset in self?.paperView.scrollOffset = offset }
        canvas.onPreview = { [weak self] shape in self?.showPreview(shape) }
    }

    required init?(coder: NSCoder) {
        fatalError("NotebookSheetView si crea solo da codice")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        paperView.frame = bounds
        canvas.frame = bounds
        previewLayer.frame = bounds
        canvas.fitContent()
    }

    /// Draws the shape where the pen is, or removes the preview.
    private func showPreview(_ shape: InkShape?) {
        guard let shape else {
            previewLayer.path = nil
            return
        }
        // The shape is in drawing coordinates; the layer is in the screen's.
        let offset = canvas.contentOffset
        let path = UIBezierPath()
        for (index, point) in shape.outline.enumerated() {
            let screen = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
            if index == 0 { path.move(to: screen) } else { path.addLine(to: screen) }
        }
        previewLayer.path = path.cgPath
        previewLayer.strokeColor = ((canvas.tool as? PKInkingTool)?.color ?? .label).cgColor
    }
}

/// A scrolling PencilKit canvas: the Pencil writes, a finger scrolls. The page
/// grows downward as the writing goes further down.
final class NotebookCanvasView: PKCanvasView {
    weak var notebook: NotebookModel?
    /// Called on every scroll, so the paper behind can move with the writing.
    var onScroll: ((CGPoint) -> Void)?
    /// Called with the shape to preview while the pen is held still, and with nil to clear it.
    var onPreview: ((InkShape?) -> Void)?

    private let toolPicker = PKToolPicker()
    /// Never the canvas itself: a canvas that is its own delegate also answers
    /// PencilKit's private delegate calls, and calls itself forever when a stroke begins.
    private let events = CanvasEvents()
    /// The Pencil stroke in progress, in drawing coordinates, and when each point was reached.
    private var liveStroke: [(point: CGPoint, time: TimeInterval)] = []
    /// Where the pen is resting, and when it came to rest there.
    private var restPoint: CGPoint?
    private var restTime: TimeInterval = 0
    private var holdTask: Task<Void, Never>?
    private var previewShape: InkShape?
    /// How long the pen must rest before the stroke is taken for a shape.
    private static let holdDelay = Duration.milliseconds(450)
    /// How far the pen may wander while it is still resting.
    private static let restTolerance: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        drawingPolicy = .pencilOnly
        alwaysBounceVertical = true
        backgroundColor = .clear
        events.canvas = self
        delegate = events
        observePencil()
    }

    required init?(coder: NSCoder) {
        fatalError("NotebookCanvasView si crea solo da codice")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        toolPicker.setVisible(true, forFirstResponder: self)
        toolPicker.addObserver(self)
        becomeFirstResponder()
    }

    /// There is always a screen of paper below the last stroke.
    func fitContent() {
        let inkBottom = drawing.strokes.isEmpty ? 0 : drawing.bounds.maxY
        let height = max(bounds.height, inkBottom + bounds.height / 2)
        let size = CGSize(width: bounds.width, height: height)
        if contentSize != size { contentSize = size }
    }

    fileprivate func drawingDidChange() {
        // Grows after the current callback, not while PencilKit is still handling the stroke.
        // A shape waiting for its stroke is applied at the same moment, outside PencilKit's callback.
        DispatchQueue.main.async { [weak self] in
            self?.fitContent()
            self?.notebook?.applyPendingShape()
        }
        notebook?.drawingDidChange()
    }

    // MARK: Shape recognition

    /// Watches the Pencil without taking its touches: PencilKit still draws, and the canvas
    /// learns where the stroke goes and when the pen rests at the end of it.
    private func observePencil() {
        let observer = PencilObserver()
        observer.cancelsTouchesInView = false
        observer.onBegan = { [weak self] point, time in self?.penBegan(at: point, time: time) }
        observer.onMoved = { [weak self] point, time in self?.penMoved(to: point, time: time) }
        observer.onEnded = { [weak self] in self?.penEnded() }
        addGestureRecognizer(observer)
    }

    private func penBegan(at point: CGPoint, time: TimeInterval) {
        liveStroke = [(point, time)]
        restPoint = point
        restTime = time
        clearPreview()
        scheduleHold()
    }

    private func penMoved(to point: CGPoint, time: TimeInterval) {
        liveStroke.append((point, time))
        guard let rest = restPoint, hypot(point.x - rest.x, point.y - rest.y) > Self.restTolerance else { return }
        // The pen moved on: it is no longer resting, so any preview goes until it rests again.
        restPoint = point
        restTime = time
        clearPreview()
        scheduleHold()
    }

    private func penEnded() {
        holdTask?.cancel()
        holdTask = nil
        restPoint = nil
        guard let shape = previewShape else { return }
        previewShape = nil
        onPreview?(nil)
        notebook?.setPendingShape(shape)
        // The stroke may already be committed: then it can be replaced now, not on the next change.
        DispatchQueue.main.async { [weak self] in self?.notebook?.applyPendingShape() }
    }

    private func scheduleHold() {
        holdTask?.cancel()
        guard notebook?.straightensShapes == true else { return }
        let rest = restPoint, since = restTime
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled else { return }
            self?.showPreviewIfHeld(restingAt: rest, since: since)
        }
    }

    /// Shows the shape the stroke makes so far, if the pen is still resting where it was when this was scheduled.
    private func showPreviewIfHeld(restingAt rest: CGPoint?, since: TimeInterval) {
        guard rest == restPoint, since == restTime, liveStroke.count >= 6 else { return }
        guard let shape = ShapeRecognizer.recognize(liveStroke.map(\.point)) else { return }
        previewShape = shape
        onPreview?(shape)
    }

    private func clearPreview() {
        guard previewShape != nil else { return }
        previewShape = nil
        onPreview?(nil)
    }
}

/// Reads the Pencil's touches without taking them from PencilKit.
private final class PencilObserver: UIGestureRecognizer {
    var onBegan: ((CGPoint, TimeInterval) -> Void)?
    var onMoved: ((CGPoint, TimeInterval) -> Void)?
    var onEnded: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = pencilTouch(in: touches) else { return }
        onBegan?(touch.location(in: view), event.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = pencilTouch(in: touches) else { return }
        onMoved?(touch.location(in: view), event.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard pencilTouch(in: touches) != nil else { return }
        onEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard pencilTouch(in: touches) != nil else { return }
        onEnded?()
    }

    private func pencilTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .pencil }
    }
}

/// Receives the canvas' drawing and scroll events.
private final class CanvasEvents: NSObject, PKCanvasViewDelegate {
    weak var canvas: NotebookCanvasView?

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        canvas?.drawingDidChange()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        canvas?.onScroll?(scrollView.contentOffset)
    }
}

/// Ruled or squared paper. It stays still while the canvas scrolls over it and
/// is drawn in the page's own coordinates, so the lines line up with the ink.
private final class PaperView: UIView {
    var style: PaperStyle = .grid {
        didSet { setNeedsDisplay() }
    }

    var scrollOffset: CGPoint = .zero {
        didSet { setNeedsDisplay() }
    }

    private let step: CGFloat = 28

    init() {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("PaperView si crea solo da codice")
    }

    override func draw(_ rect: CGRect) {
        guard style != .blank, let context = UIGraphicsGetCurrentContext() else { return }
        let page = rect.offsetBy(dx: scrollOffset.x, dy: scrollOffset.y)
        context.translateBy(x: -scrollOffset.x, y: -scrollOffset.y)
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(0.5)
        var y = floor(page.minY / step) * step
        while y <= page.maxY {
            context.move(to: CGPoint(x: page.minX, y: y))
            context.addLine(to: CGPoint(x: page.maxX, y: y))
            y += step
        }
        if style == .grid {
            var x = floor(page.minX / step) * step
            while x <= page.maxX {
                context.move(to: CGPoint(x: x, y: page.minY))
                context.addLine(to: CGPoint(x: x, y: page.maxY))
                x += step
            }
        }
        context.strokePath()
    }
}
